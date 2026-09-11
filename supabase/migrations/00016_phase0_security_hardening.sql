-- Migration 00016: Phase 0 — Security Hardening & RLS Completion
-- Muc tieu:
--   1. Revoke direct DML tu authenticated tren canonical tables
--   2. Hoan thien RLS Supplier Portal (app_supplier_users -> vendor isolation)
--   3. RLS cho Risk_Reviewer, Accounting co scope dung
--   4. Admin co the quan ly app_supplier_users
--   5. Supplier_User khong doc duoc sm_risk_decision, sm_supplier_request cua NCC khac

-- ============================================================
-- SECTION 1: REVOKE DIRECT DML FROM authenticated
-- Cac table canonical lifecycle, qualification, classification,
-- risk decision va audit khong cho authenticated ghi truc tiep.
-- Chi SECURITY DEFINER RPCs moi duoc write.
-- ============================================================

-- Vendor (Golden Record) — khong co INSERT/UPDATE/DELETE policy
-- => authenticated khong co RLS policy cho mutation = tuy nhien van co
--    the write neu RLS off. Dam bao RLS on va khong co permissive mutation policy.
-- Tat ca INSERT/UPDATE/DELETE bang FROM khong qua RPC se bi RLS block
-- vi khong co policy nao cho phep mutation (fail closed theo default Postgres).

-- Xac nhan RLS dang BAT tren tat ca canonical tables:
ALTER TABLE public.vendor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_request_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_lifecycle_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_change_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_qualification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_classification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_assessment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_factor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_issue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_audit_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_crosswalk ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_change_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_response ENABLE ROW LEVEL SECURITY;

-- REVOKE truc tiep tren authenticated role cho cac canonical tables
-- (Belt-and-suspenders: RLS block + REVOKE)
REVOKE INSERT, UPDATE, DELETE ON public.vendor FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sm_supplier_lifecycle_history FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sm_supplier_change_snapshot FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sm_supplier_audit_event FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sm_risk_decision FROM authenticated;

-- sm_supplier_request: chi duoc INSERT qua RPC, khong duoc UPDATE/DELETE
REVOKE UPDATE, DELETE ON public.sm_supplier_request FROM authenticated;

-- sm_supplier_request_decision: khong duoc viet truc tiep
REVOKE INSERT, UPDATE, DELETE ON public.sm_supplier_request_decision FROM authenticated;

-- Grant lai SELECT de RLS policies van hoat dong dung
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

-- ============================================================
-- SECTION 2: SUPPLIER PORTAL ISOLATION (Supplier_User)
-- Supplier_User chi doc duoc du lieu cua NCC minh, khong thay NCC khac.
-- ============================================================

-- 2a. Admin co the ghi vao app_supplier_users (giao NCC cho user)
DROP POLICY IF EXISTS "Admin can manage supplier user mappings" ON public.app_supplier_users;
CREATE POLICY "Admin can manage supplier user mappings"
    ON public.app_supplier_users
    FOR ALL
    USING (
        EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid() AND role = 'Admin')
    )
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid() AND role = 'Admin')
    );

-- 2b. sm_supplier_document: Supplier_User chi xem doc cua NCC minh
DROP POLICY IF EXISTS "Supplier users can read own documents" ON public.sm_supplier_document;
CREATE POLICY "Supplier users can read own documents"
    ON public.sm_supplier_document
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_supplier_users
            WHERE user_id = auth.uid() AND supplier_id = sm_supplier_document.supplier_id
        )
    );

-- Internal users doc tat ca documents
DROP POLICY IF EXISTS "Internal users can read all documents" ON public.sm_supplier_document;
CREATE POLICY "Internal users can read all documents"
    ON public.sm_supplier_document
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Viewer', 'Buyer', 'Supplier_Manager', 'Risk_Reviewer', 'Accounting', 'Approver', 'Admin')
        )
    );

-- 2c. sm_questionnaire_instance: Supplier_User chi xem cua minh
DROP POLICY IF EXISTS "Supplier users can read own questionnaires" ON public.sm_questionnaire_instance;
CREATE POLICY "Supplier users can read own questionnaires"
    ON public.sm_questionnaire_instance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_supplier_users
            WHERE user_id = auth.uid() AND supplier_id = sm_questionnaire_instance.supplier_id
        )
    );

DROP POLICY IF EXISTS "Internal users can read all questionnaires" ON public.sm_questionnaire_instance;
CREATE POLICY "Internal users can read all questionnaires"
    ON public.sm_questionnaire_instance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Viewer', 'Buyer', 'Supplier_Manager', 'Risk_Reviewer', 'Approver', 'Admin')
        )
    );

-- 2d. sm_questionnaire_response: Supplier_User INSERT cau tra loi cua minh
DROP POLICY IF EXISTS "Supplier users can submit own questionnaire responses" ON public.sm_questionnaire_response;
CREATE POLICY "Supplier users can submit own questionnaire responses"
    ON public.sm_questionnaire_response
    FOR INSERT
    WITH CHECK (
        auth.uid() = respondent_id
        AND EXISTS (
            SELECT 1 FROM public.sm_questionnaire_instance qi
            JOIN public.app_supplier_users asu ON asu.supplier_id = qi.supplier_id
            WHERE qi.id = sm_questionnaire_response.instance_id
              AND asu.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Supplier users can read own responses" ON public.sm_questionnaire_response;
CREATE POLICY "Supplier users can read own responses"
    ON public.sm_questionnaire_response
    FOR SELECT
    USING (auth.uid() = respondent_id);

DROP POLICY IF EXISTS "Internal users can read all responses" ON public.sm_questionnaire_response;
CREATE POLICY "Internal users can read all responses"
    ON public.sm_questionnaire_response
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Supplier_Manager', 'Risk_Reviewer', 'Approver', 'Admin')
        )
    );

-- ============================================================
-- SECTION 3: TIGHTENED RLS FOR SENSITIVE TABLES
-- Risk Decision va Audit Event: chi internal roles moi doc duoc
-- ============================================================

-- sm_risk_decision: Supplier_User KHONG doc duoc
DROP POLICY IF EXISTS "Users can read decisions" ON public.sm_risk_decision;
CREATE POLICY "Internal users can read risk decisions"
    ON public.sm_risk_decision
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Risk_Reviewer', 'Supplier_Manager', 'Approver', 'Admin', 'Buyer')
        )
    );

-- sm_supplier_audit_event: chi Admin, Approver, Supplier_Manager doc duoc
DROP POLICY IF EXISTS "Users can read audit events" ON public.sm_supplier_audit_event;
CREATE POLICY "Privileged users can read audit events"
    ON public.sm_supplier_audit_event
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Admin', 'Approver', 'Supplier_Manager', 'Risk_Reviewer')
        )
    );

-- sm_supplier_outbox: chi Admin doc/retry
DROP POLICY IF EXISTS "Users can read outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Admin can read outbox"
    ON public.sm_supplier_outbox
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid() AND role IN ('Admin', 'Approver')
        )
    );

-- sm_supplier_crosswalk: internal roles
DROP POLICY IF EXISTS "Users can read crosswalk" ON public.sm_supplier_crosswalk;
CREATE POLICY "Internal users can read crosswalk"
    ON public.sm_supplier_crosswalk
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_user_roles
            WHERE user_id = auth.uid()
            AND role IN ('Admin', 'Approver', 'Supplier_Manager')
        )
    );

-- ============================================================
-- SECTION 4: HELPER FUNCTION — Get current user roles
-- Dung trong RLS va RPC de kiem tra quyen
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_roles()
RETURNS text[]
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT COALESCE(array_agg(role::text), '{}')
    FROM app_user_roles
    WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_my_roles TO authenticated;

-- ============================================================
-- SECTION 5: HELPER FUNCTION — Check if current user is supplier of given vendor
-- Dung trong RLS Supplier Portal
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_my_supplier(p_supplier_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM app_supplier_users
        WHERE user_id = auth.uid() AND supplier_id = p_supplier_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_my_supplier TO authenticated;

-- ============================================================
-- SECTION 6: APP_SUPPLIER_USERS RPC — Admin grants supplier access
-- ============================================================
CREATE OR REPLACE FUNCTION public.sm_grant_supplier_access(
    p_target_user_id uuid,
    p_supplier_id uuid
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
    IF v_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can grant supplier portal access';
    END IF;

    INSERT INTO app_supplier_users (user_id, supplier_id)
    VALUES (p_target_user_id, p_supplier_id)
    ON CONFLICT (user_id, supplier_id) DO NOTHING;

    -- Ensure target user has Supplier_User role
    INSERT INTO app_user_roles (user_id, role)
    VALUES (p_target_user_id, 'Supplier_User')
    ON CONFLICT (user_id, role) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.sm_revoke_supplier_access(
    p_target_user_id uuid,
    p_supplier_id uuid
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
    IF v_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can revoke supplier portal access';
    END IF;

    DELETE FROM app_supplier_users
    WHERE user_id = p_target_user_id AND supplier_id = p_supplier_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sm_grant_supplier_access TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_revoke_supplier_access TO authenticated;
