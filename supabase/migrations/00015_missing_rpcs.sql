-- Migration 00015: Missing RPCs (Risk Decision, CAPA, Crosswalk, Work Queue, Profile/Bank Change)

-- ============================================================
-- 1. sm_record_risk_decision
--    Role: Risk_Reviewer or Approver only
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_record_risk_decision(
    p_supplier_id uuid,
    p_scope_id uuid,
    p_decision text,  -- 'Acceptable', 'Accept_With_Controls', 'Pending_Review', 'Blocked'
    p_rationale text,
    p_valid_until timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_decision_id uuid;
BEGIN
    -- Role check
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Risk_Reviewer', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Risk_Reviewer or Approver can record risk decisions';
    END IF;

    INSERT INTO sm_risk_decision (
        supplier_id, scope_id, decision, rationale, decided_by, decided_at, valid_until
    ) VALUES (
        p_supplier_id, p_scope_id, p_decision::risk_decision_type, p_rationale, auth.uid(), now(), p_valid_until
    ) RETURNING id INTO v_decision_id;

    -- Write audit event
    INSERT INTO sm_supplier_audit_event (entity_type, entity_id, action, after_state, actor_id)
    VALUES ('RISK_DECISION', v_decision_id, 'CREATE',
        jsonb_build_object('decision', p_decision, 'rationale', p_rationale, 'supplier_id', p_supplier_id),
        auth.uid());

    RETURN v_decision_id;
END;
$$;

-- NOTE: sm_create_risk_issue already defined in 00011_business_operations_rpc.sql
-- (5-param version: supplier_id, title, description, severity, due_date)
-- We add GRANT here to ensure consistency.

-- ============================================================
-- 3. sm_update_risk_action
--    Update or create a CAPA action on a risk issue
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_update_risk_action(
    p_issue_id uuid,
    p_action_description text,
    p_status text DEFAULT 'Open',
    p_due_date timestamptz DEFAULT NULL,
    p_completion_evidence text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action_id uuid;
BEGIN
    -- Upsert action
    INSERT INTO sm_risk_action (
        issue_id, action_description, owner_id, status, due_date, completion_evidence,
        completed_at
    ) VALUES (
        p_issue_id, p_action_description, auth.uid(), p_status::risk_status,
        p_due_date, p_completion_evidence,
        CASE WHEN p_status = 'Closed' THEN now() ELSE NULL END
    ) RETURNING id INTO v_action_id;

    RETURN v_action_id;
END;
$$;

-- ============================================================
-- 4. sm_upsert_supplier_crosswalk
--    Map internal supplier_id <-> external ERP ID
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_upsert_supplier_crosswalk(
    p_supplier_id uuid,
    p_external_system text,  -- e.g., 'NAV', 'VISTA'
    p_external_id text,
    p_external_site_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Admin', 'Approver') THEN
        RAISE EXCEPTION 'Only Admin or Approver can manage ERP crosswalk mappings';
    END IF;

    INSERT INTO sm_supplier_crosswalk (
        supplier_id, external_system, external_id, external_site_id, last_synced_at
    ) VALUES (
        p_supplier_id, p_external_system, p_external_id, p_external_site_id, now()
    )
    ON CONFLICT (supplier_id, external_system) DO UPDATE
        SET external_id = EXCLUDED.external_id,
            external_site_id = EXCLUDED.external_site_id,
            last_synced_at = now();
END;
$$;

-- ============================================================
-- 5. sm_retry_supplier_sync_event
--    Retry a failed outbox event
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_retry_supplier_sync_event(
    p_outbox_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Admin') THEN
        RAISE EXCEPTION 'Only Admin can retry sync events';
    END IF;

    UPDATE sm_supplier_outbox
    SET status = 'Pending',
        retry_count = retry_count + 1,
        updated_at = now()
    WHERE id = p_outbox_id AND status = 'Failed';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Outbox event not found or not in Failed status';
    END IF;
END;
$$;

-- ============================================================
-- 6. sm_get_work_queue
--    Returns a work queue: pending requests + expiring docs + overdue risks
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_get_work_queue()
RETURNS TABLE (
    item_type text,
    item_id uuid,
    title text,
    supplier_name text,
    severity text,
    due_date timestamptz,
    status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Pending approval requests
    RETURN QUERY
    SELECT
        'PENDING_REQUEST'::text,
        r.id,
        ('Request: ' || r.request_type::text)::text,
        v.vendor_name,
        'Medium'::text,
        r.created_at + interval '3 days',
        r.status::text
    FROM sm_supplier_request r
    JOIN vendor v ON v.id = r.supplier_id
    WHERE r.status IN ('Submitted', 'In_Review');

    -- Documents expiring in 30 days
    RETURN QUERY
    SELECT
        'EXPIRING_DOCUMENT'::text,
        d.id,
        ('Doc expiring: ' || d.document_type)::text,
        v.vendor_name,
        'High'::text,
        d.valid_to,
        d.status::text
    FROM sm_supplier_document d
    JOIN vendor v ON v.id = d.supplier_id
    WHERE d.valid_to BETWEEN now() AND now() + interval '30 days'
      AND d.status = 'Approved';

    -- Overdue risk issues
    RETURN QUERY
    SELECT
        'OVERDUE_RISK'::text,
        ri.id,
        ('Risk issue: ' || ri.title)::text,
        v.vendor_name,
        ri.severity::text,
        ri.due_date,
        ri.status::text
    FROM sm_risk_issue ri
    JOIN vendor v ON v.id = ri.supplier_id
    WHERE ri.due_date < now()
      AND ri.status IN ('Open', 'In_Progress');
END;
$$;

-- ============================================================
-- 7. sm_submit_profile_change
--    Submit Update_Profile request (Maker-Checker)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_submit_profile_change(
    p_supplier_id uuid,
    p_proposed_payload jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_request_id uuid;
    v_submission_key text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Buyer', 'Admin') THEN
        RAISE EXCEPTION 'Only Supplier_Manager or Buyer can submit profile changes';
    END IF;

    v_submission_key := 'UPD-' || p_supplier_id::text || '-' || extract(epoch from now())::bigint::text;

    v_request_id := public.sm_submit_supplier_request(
        p_supplier_id,
        'Update_Profile',
        p_proposed_payload,
        v_submission_key
    );

    RETURN v_request_id;
END;
$$;

-- ============================================================
-- 8. sm_submit_bank_change
--    Submit Change_Bank_Account request (Maker-Checker)
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_submit_bank_change(
    p_supplier_id uuid,
    p_proposed_payload jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_request_id uuid;
    v_submission_key text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Accounting', 'Admin') THEN
        RAISE EXCEPTION 'Only Supplier_Manager or Accounting can submit bank changes';
    END IF;

    v_submission_key := 'BANK-' || p_supplier_id::text || '-' || extract(epoch from now())::bigint::text;

    v_request_id := public.sm_submit_supplier_request(
        p_supplier_id,
        'Change_Bank_Account',
        p_proposed_payload,
        v_submission_key
    );

    RETURN v_request_id;
END;
$$;

-- ============================================================
-- 9. Grant execute permissions to authenticated users
-- ============================================================
GRANT EXECUTE ON FUNCTION public.sm_record_risk_decision TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_create_risk_issue TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_update_risk_action TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_upsert_supplier_crosswalk TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_retry_supplier_sync_event TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_get_work_queue TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_profile_change TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_bank_change TO authenticated;
