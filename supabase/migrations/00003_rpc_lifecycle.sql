-- Migration 00003: RPC Lifecycle Functions

-- 1. sm_submit_supplier_request
CREATE OR REPLACE FUNCTION public.sm_submit_supplier_request(
    p_supplier_id uuid,
    p_request_type supplier_request_type,
    p_proposed_payload jsonb,
    p_submission_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request_id uuid;
    v_new_request_no text;
BEGIN
    -- Idempotency check
    SELECT id INTO v_request_id FROM sm_supplier_request WHERE submission_key = p_submission_key;
    IF v_request_id IS NOT NULL THEN
        RETURN v_request_id;
    END IF;

    -- Generate request number (simple sequence for demo, use robust generator in prod)
    v_new_request_no := 'REQ-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substring(md5(random()::text) from 1 for 4);

    -- Insert Request
    INSERT INTO sm_supplier_request (
        request_no,
        supplier_id,
        request_type,
        status,
        proposed_payload,
        submission_key,
        requested_by
    ) VALUES (
        v_new_request_no,
        p_supplier_id,
        p_request_type,
        'Submitted',
        p_proposed_payload,
        p_submission_key,
        auth.uid()
    ) RETURNING id INTO v_request_id;

    RETURN v_request_id;
END;
$$;

-- 2. sm_decide_supplier_request
CREATE OR REPLACE FUNCTION public.sm_decide_supplier_request(
    p_request_id uuid,
    p_decision supplier_decision_type,
    p_reason text,
    p_expected_row_version integer
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request sm_supplier_request%ROWTYPE;
    v_vendor vendor%ROWTYPE;
    v_transition_rule sm_lifecycle_transition_rule%ROWTYPE;
    v_user_role text;
BEGIN
    -- 1. Get request
    SELECT * INTO v_request FROM sm_supplier_request WHERE id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found';
    END IF;

    -- 2. Get vendor
    SELECT * INTO v_vendor FROM vendor WHERE id = v_request.supplier_id;
    IF NOT FOUND THEN
         RAISE EXCEPTION 'Supplier not found';
    END IF;

    -- 3. Concurrency check (lost update)
    IF v_vendor.row_version != p_expected_row_version THEN
        RAISE EXCEPTION 'Concurrent update detected. Expected version %, found %', p_expected_row_version, v_vendor.row_version;
    END IF;
    
    -- 4. Maker-Checker validation: Requester cannot approve their own request
    IF v_request.requested_by = auth.uid() THEN
        RAISE EXCEPTION 'Requester cannot decide their own request';
    END IF;

    -- 5. Role check for transitions (Simplified for now)
    -- In a full implementation, query `sm_lifecycle_transition_rule` and `app_user_roles`
    -- SELECT role::text INTO v_user_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    -- For simplicity, we bypass complex dynamic role checks here and focus on state changes

    -- 6. Process decision
    IF p_decision = 'Approve' THEN
        -- Find transition
        SELECT * INTO v_transition_rule 
        FROM sm_lifecycle_transition_rule 
        WHERE from_status = v_vendor.lifecycle_status AND allowed_request_type = v_request.request_type;

        IF NOT FOUND THEN
             RAISE EXCEPTION 'Invalid transition from % via %', v_vendor.lifecycle_status, v_request.request_type;
        END IF;

        -- Update Request
        UPDATE sm_supplier_request SET status = 'Approved', updated_at = now() WHERE id = p_request_id;

        -- Save snapshot
        INSERT INTO sm_supplier_change_snapshot (supplier_id, request_id, before_json, after_json)
        VALUES (v_vendor.id, p_request_id, row_to_json(v_vendor)::jsonb, v_request.proposed_payload);

        -- Update Lifecycle History
        INSERT INTO sm_supplier_lifecycle_history (supplier_id, from_status, to_status, request_id, actor_id, reason)
        VALUES (v_vendor.id, v_vendor.lifecycle_status, v_transition_rule.to_status, p_request_id, auth.uid(), p_reason);

        -- Materialize change to Golden Record
        -- In reality, we'd merge the payload. For lifecycle transitions, we update the status.
        UPDATE vendor 
        SET lifecycle_status = v_transition_rule.to_status,
            last_approved_at = now(),
            last_approved_by = auth.uid()
        WHERE id = v_vendor.id;

    ELSIF p_decision = 'Reject' THEN
        UPDATE sm_supplier_request SET status = 'Rejected', updated_at = now() WHERE id = p_request_id;
    ELSIF p_decision = 'Return_For_Edit' THEN
        UPDATE sm_supplier_request SET status = 'In_Review', updated_at = now() WHERE id = p_request_id;
    END IF;

    -- Record decision
    INSERT INTO sm_supplier_request_decision (request_id, decision, reason, decided_by)
    VALUES (p_request_id, p_decision, p_reason, auth.uid());

    RETURN true;
END;
$$;
