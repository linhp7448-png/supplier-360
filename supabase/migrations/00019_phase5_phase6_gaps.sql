-- Migration 00019: Phase 5 and Phase 6 Missing RPCs

-- ============================================================
-- PHASE 5: PERFORMANCE RPCS
-- ============================================================

-- 1. sm_add_performance_score
CREATE OR REPLACE FUNCTION public.sm_add_performance_score(
    p_evaluation_id uuid,
    p_kpi_id integer,
    p_raw_value numeric,
    p_score numeric,
    p_source_evidence text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_score_id uuid;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Supplier_Manager or Approver can add performance scores';
    END IF;

    INSERT INTO public.sm_performance_score (evaluation_id, kpi_id, raw_value, score, source_evidence)
    VALUES (p_evaluation_id, p_kpi_id, p_raw_value, p_score, p_source_evidence)
    RETURNING id INTO v_score_id;

    RETURN v_score_id;
END;
$$;

-- ============================================================
-- Permissions
-- ============================================================
GRANT EXECUTE ON FUNCTION public.sm_add_performance_score TO authenticated;

