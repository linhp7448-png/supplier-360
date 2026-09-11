-- Migration 00017: Phase 1 + Phase 2 Gap Fixes
-- P1-B: Role check trong sm_decide_supplier_request
-- P1-C: Materialization Update_Profile / Change_Bank_Account
-- P1-D: Outbox event khi lifecycle approved
-- P2-A: sm_supplier_scope_history table
-- P2-B/C: Request types moi + RPC Qualification/Classification qua Maker-Checker

-- ============================================================
-- P2-A: sm_supplier_scope_history TABLE
-- (Duoc dung trong 00012 nhung chua co migration tao bang)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.sm_supplier_scope_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_id uuid REFERENCES public.sm_supplier_scope(id) ON DELETE CASCADE,
    event_type text NOT NULL,  -- 'SCOPE_CREATED', 'QUALIFICATION_UPDATED', 'CLASSIFICATION_UPDATED', 'SCOPE_CLOSED'
    before_state jsonb,
    after_state jsonb,
    actor_id uuid REFERENCES auth.users(id),
    request_id uuid REFERENCES public.sm_supplier_request(id),
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.sm_supplier_scope_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Internal users can read scope history" ON public.sm_supplier_scope_history
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
    );

-- ============================================================
-- P2-C: Them request types moi cho Qualification / Classification
-- ============================================================
ALTER TYPE public.supplier_request_type ADD VALUE IF NOT EXISTS 'Set_Qualification';
ALTER TYPE public.supplier_request_type ADD VALUE IF NOT EXISTS 'Set_Classification';

-- ============================================================
-- P2-B: sm_submit_qualification_request
-- Tao request thay doi Qualification cho mot scope (Maker-Checker)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_submit_qualification_request(
    p_supplier_id uuid,
    p_scope_id uuid,
    p_new_status text,     -- qualification_status value
    p_valid_from date,
    p_valid_to date DEFAULT NULL,
    p_conditions text DEFAULT NULL,
    p_rationale text DEFAULT NULL,
    p_submission_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_request_id uuid;
    v_request_no text;
    v_sub_key text;
BEGIN
    -- Role check
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Buyer', 'Supplier_Manager', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Insufficient permissions to submit qualification request';
    END IF;

    -- Idempotency
    v_sub_key := COALESCE(p_submission_key, gen_random_uuid()::text);
    SELECT id INTO v_request_id FROM sm_supplier_request WHERE submission_key = v_sub_key;
    IF v_request_id IS NOT NULL THEN RETURN v_request_id; END IF;

    -- Request number
    v_request_no := 'QUAL-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substring(md5(random()::text) from 1 for 4);

    INSERT INTO sm_supplier_request (
        request_no, supplier_id, request_type, status,
        proposed_payload, submission_key, requested_by
    ) VALUES (
        v_request_no, p_supplier_id, 'Set_Qualification', 'Submitted',
        jsonb_build_object(
            'scope_id', p_scope_id,
            'new_status', p_new_status,
            'valid_from', p_valid_from,
            'valid_to', p_valid_to,
            'conditions', p_conditions,
            'rationale', p_rationale
        ),
        v_sub_key, auth.uid()
    ) RETURNING id INTO v_request_id;

    RETURN v_request_id;
END;
$$;

-- ============================================================
-- P2-B: sm_submit_classification_request
-- Tao request thay doi Classification (Maker-Checker)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_submit_classification_request(
    p_supplier_id uuid,
    p_scope_id uuid,
    p_new_tier text,
    p_rationale text DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_to date DEFAULT NULL,
    p_submission_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_request_id uuid;
    v_request_no text;
    v_sub_key text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Buyer', 'Supplier_Manager', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Insufficient permissions to submit classification request';
    END IF;

    v_sub_key := COALESCE(p_submission_key, gen_random_uuid()::text);
    SELECT id INTO v_request_id FROM sm_supplier_request WHERE submission_key = v_sub_key;
    IF v_request_id IS NOT NULL THEN RETURN v_request_id; END IF;

    v_request_no := 'CLASS-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substring(md5(random()::text) from 1 for 4);

    INSERT INTO sm_supplier_request (
        request_no, supplier_id, request_type, status,
        proposed_payload, submission_key, requested_by
    ) VALUES (
        v_request_no, p_supplier_id, 'Set_Classification', 'Submitted',
        jsonb_build_object(
            'scope_id', p_scope_id,
            'new_tier', p_new_tier,
            'rationale', p_rationale,
            'valid_from', COALESCE(p_valid_from, CURRENT_DATE),
            'valid_to', p_valid_to
        ),
        v_sub_key, auth.uid()
    ) RETURNING id INTO v_request_id;

    RETURN v_request_id;
END;
$$;

-- ============================================================
-- P1-B + P1-C + P1-D: sm_decide_supplier_request (IMPROVED)
-- Them: Role check, materialization Update_Profile/Bank/Qual/Class, outbox event
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_decide_supplier_request(
    p_request_id uuid,
    p_decision text,             -- 'Approve', 'Reject', 'Return_For_Edit'
    p_reason text,
    p_expected_row_version integer DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request sm_supplier_request%ROWTYPE;
    v_vendor  vendor%ROWTYPE;
    v_transition_rule sm_lifecycle_transition_rule%ROWTYPE;
    v_user_role text;
    v_required_role text;
    v_payload jsonb;
    v_scope_id uuid;
    v_before_state jsonb;
    v_after_json jsonb;
BEGIN
    -- 1. Lay request
    SELECT * INTO v_request FROM sm_supplier_request WHERE id = p_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Request not found: %', p_request_id; END IF;
    IF v_request.status NOT IN ('Submitted', 'In_Review') THEN
        RAISE EXCEPTION 'Request % is not in a decidable state (current: %)', p_request_id, v_request.status;
    END IF;

    -- 2. Maker-Checker: requester khong tu duyet
    IF v_request.requested_by = auth.uid() THEN
        RAISE EXCEPTION 'Requester cannot approve their own request';
    END IF;

    -- 3. Role check
    SELECT role::text INTO v_user_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_user_role IS NULL THEN
        RAISE EXCEPTION 'No role assigned to current user';
    END IF;

    -- Kiem tra role co du quyen duyet request loai nay khong
    IF v_request.request_type IN ('Activate_Supplier', 'Suspend_Supplier', 'Reinstate_Supplier',
                                    'Disqualify_Supplier', 'Inactivate_Supplier') THEN
        IF v_user_role NOT IN ('Approver', 'Admin') THEN
            RAISE EXCEPTION 'Only Approver/Admin can decide lifecycle requests';
        END IF;
    ELSIF v_request.request_type IN ('Set_Qualification', 'Set_Classification') THEN
        IF v_user_role NOT IN ('Approver', 'Admin', 'Supplier_Manager') THEN
            RAISE EXCEPTION 'Only Approver/Admin/Supplier_Manager can decide qualification/classification requests';
        END IF;
    ELSIF v_request.request_type IN ('Update_Profile', 'Submit_Onboarding', 'Create_Supplier') THEN
        IF v_user_role NOT IN ('Approver', 'Admin', 'Supplier_Manager') THEN
            RAISE EXCEPTION 'Only Approver/Admin/Supplier_Manager can decide profile requests';
        END IF;
    ELSIF v_request.request_type = 'Change_Bank_Account' THEN
        IF v_user_role NOT IN ('Approver', 'Admin', 'Accounting') THEN
            RAISE EXCEPTION 'Only Approver/Admin/Accounting can decide bank account changes';
        END IF;
    END IF;

    -- 4. Lay vendor neu request lien quan den vendor
    IF v_request.supplier_id IS NOT NULL THEN
        SELECT * INTO v_vendor FROM vendor WHERE id = v_request.supplier_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;

        -- Optimistic locking (chi kiem tra neu duoc truyen vao)
        IF p_expected_row_version IS NOT NULL AND v_vendor.row_version != p_expected_row_version THEN
            RAISE EXCEPTION 'Concurrent update detected. Expected row_version %, found %',
                p_expected_row_version, v_vendor.row_version;
        END IF;

        v_before_state := row_to_json(v_vendor)::jsonb;
    END IF;

    v_payload := v_request.proposed_payload;

    -- 5. Xu ly quyet dinh
    IF p_decision = 'Approve' THEN
        UPDATE sm_supplier_request SET status = 'Approved', updated_at = now() WHERE id = p_request_id;

        -- === Materialization theo tung loai request ===

        IF v_request.request_type IN ('Activate_Supplier','Suspend_Supplier','Reinstate_Supplier',
                                       'Disqualify_Supplier','Inactivate_Supplier','Submit_Onboarding') THEN
            -- Lifecycle transition
            SELECT * INTO v_transition_rule
            FROM sm_lifecycle_transition_rule
            WHERE from_status = v_vendor.lifecycle_status
              AND allowed_request_type = v_request.request_type
              AND is_active = true;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invalid transition from % via %', v_vendor.lifecycle_status, v_request.request_type;
            END IF;

            UPDATE vendor
            SET lifecycle_status = v_transition_rule.to_status,
                last_approved_at = now(),
                last_approved_by  = auth.uid()
            WHERE id = v_vendor.id;

            INSERT INTO sm_supplier_lifecycle_history
                (supplier_id, from_status, to_status, request_id, actor_id, reason)
            VALUES
                (v_vendor.id, v_vendor.lifecycle_status, v_transition_rule.to_status, p_request_id, auth.uid(), p_reason);

            -- Outbox event (P1-D)
            INSERT INTO sm_supplier_outbox (supplier_id, event_type, payload)
            VALUES (v_vendor.id, 'LIFECYCLE_CHANGED', jsonb_build_object(
                'from', v_vendor.lifecycle_status,
                'to', v_transition_rule.to_status,
                'request_id', p_request_id,
                'approved_by', auth.uid(),
                'approved_at', now()
            ));

        ELSIF v_request.request_type = 'Update_Profile' THEN
            -- Merge payload vao Golden Record
            UPDATE vendor SET
                vendor_name      = COALESCE(v_payload->>'vendor_name', vendor_name),
                tax_code         = COALESCE(v_payload->>'tax_code', tax_code),
                website          = COALESCE(v_payload->>'website', website),
                data_owner_email = COALESCE(v_payload->>'data_owner_email', data_owner_email),
                last_approved_at = now(),
                last_approved_by = auth.uid()
            WHERE id = v_vendor.id;

            -- Outbox
            INSERT INTO sm_supplier_outbox (supplier_id, event_type, payload)
            VALUES (v_vendor.id, 'PROFILE_UPDATED', jsonb_build_object(
                'changes', v_payload, 'request_id', p_request_id
            ));

        ELSIF v_request.request_type = 'Change_Bank_Account' THEN
            -- Ghi nhan vao snapshot, outbox notify ERP sync lai bank
            INSERT INTO sm_supplier_outbox (supplier_id, event_type, payload)
            VALUES (v_vendor.id, 'BANK_ACCOUNT_CHANGED', jsonb_build_object(
                'bank_name', v_payload->>'bank_name',
                'bank_branch', v_payload->>'bank_branch',
                'account_number', v_payload->>'account_number',
                'account_name', v_payload->>'account_name',
                'request_id', p_request_id,
                'approved_by', auth.uid()
            ));

        ELSIF v_request.request_type = 'Set_Qualification' THEN
            v_scope_id := (v_payload->>'scope_id')::uuid;

            -- Dong old qualification
            UPDATE sm_supplier_qualification
            SET valid_to = now()
            WHERE scope_id = v_scope_id AND (valid_to IS NULL OR valid_to > now());

            -- Tao moi
            INSERT INTO sm_supplier_qualification
                (scope_id, status, valid_from, valid_to, conditions, approved_by, approved_at)
            VALUES (
                v_scope_id,
                (v_payload->>'new_status')::qualification_status,
                COALESCE((v_payload->>'valid_from')::date, CURRENT_DATE),
                (v_payload->>'valid_to')::date,
                v_payload->>'conditions',
                auth.uid(), now()
            );

            INSERT INTO sm_supplier_scope_history
                (scope_id, event_type, before_state, after_state, actor_id, request_id)
            VALUES (
                v_scope_id, 'QUALIFICATION_UPDATED',
                jsonb_build_object('status', 'previous'),
                v_payload,
                auth.uid(), p_request_id
            );

        ELSIF v_request.request_type = 'Set_Classification' THEN
            v_scope_id := (v_payload->>'scope_id')::uuid;

            -- Dong old classification
            UPDATE sm_supplier_classification
            SET valid_to = now()
            WHERE scope_id = v_scope_id AND (valid_to IS NULL OR valid_to > now());

            -- Tao moi
            INSERT INTO sm_supplier_classification
                (scope_id, tier_id, valid_from, valid_to, rationale, approved_by, approved_at)
            VALUES (
                v_scope_id,
                v_payload->>'new_tier',
                COALESCE((v_payload->>'valid_from')::date, CURRENT_DATE),
                (v_payload->>'valid_to')::date,
                v_payload->>'rationale',
                auth.uid(), now()
            );

            INSERT INTO sm_supplier_scope_history
                (scope_id, event_type, before_state, after_state, actor_id, request_id)
            VALUES (
                v_scope_id, 'CLASSIFICATION_UPDATED',
                jsonb_build_object('tier', 'previous'),
                v_payload,
                auth.uid(), p_request_id
            );
        END IF;

        -- Change snapshot (cho moi loai request co vendor)
        IF v_vendor.id IS NOT NULL THEN
            SELECT row_to_json(v)::jsonb INTO v_after_json FROM vendor v WHERE id = v_vendor.id;
            INSERT INTO sm_supplier_change_snapshot
                (supplier_id, request_id, before_json, after_json, changed_fields)
            VALUES (
                v_vendor.id, p_request_id,
                v_before_state,
                v_after_json,
                ARRAY(SELECT key FROM jsonb_each_text(COALESCE(v_payload, '{}'::jsonb)))
            );
        END IF;

    ELSIF p_decision = 'Reject' THEN
        UPDATE sm_supplier_request SET status = 'Rejected', updated_at = now() WHERE id = p_request_id;

    ELSIF p_decision = 'Return_For_Edit' THEN
        UPDATE sm_supplier_request SET status = 'In_Review', updated_at = now() WHERE id = p_request_id;
    END IF;

    -- 6. Ghi decision
    INSERT INTO sm_supplier_request_decision (request_id, decision, reason, decided_by)
    VALUES (p_request_id, p_decision::supplier_decision_type, p_reason, auth.uid());

    RETURN true;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.sm_decide_supplier_request TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_qualification_request TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_classification_request TO authenticated;
