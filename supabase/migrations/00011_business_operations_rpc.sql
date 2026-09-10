-- Migration 00011: Business Operations RPCs for Web Input
-- These RPCs allow authenticated users to input data via the Web UI
-- while strictly adhering to the architectural principle of not allowing direct DML.

-- 1. Create Risk Issue
CREATE OR REPLACE FUNCTION public.sm_create_risk_issue(
    p_supplier_id uuid,
    p_title text,
    p_description text,
    p_severity text,
    p_due_date timestamptz
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_issue_id uuid;
BEGIN
    INSERT INTO public.sm_risk_issue (supplier_id, title, description, severity, status, due_date, assignee_id)
    VALUES (p_supplier_id, p_title, p_description, p_severity::risk_severity, 'Open', p_due_date, auth.uid())
    RETURNING id INTO v_issue_id;
    RETURN v_issue_id;
END;
$$;

-- 2. Add Document
CREATE OR REPLACE FUNCTION public.sm_add_document(
    p_supplier_id uuid,
    p_document_type text,
    p_valid_to timestamptz
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doc_id uuid;
BEGIN
    INSERT INTO public.sm_supplier_document (supplier_id, document_type, storage_path, valid_to, status)
    VALUES (p_supplier_id, p_document_type, '#', p_valid_to, 'Approved')
    RETURNING id INTO v_doc_id;
    RETURN v_doc_id;
END;
$$;

-- 3. Create Performance Evaluation
CREATE OR REPLACE FUNCTION public.sm_create_performance_evaluation(
    p_supplier_id uuid,
    p_evaluation_period text,
    p_total_score numeric,
    p_grade text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_eval_id uuid;
BEGIN
    INSERT INTO public.sm_performance_evaluation (supplier_id, evaluation_period, total_score, grade, status, evaluator_id)
    VALUES (p_supplier_id, p_evaluation_period, p_total_score, p_grade, 'Published', auth.uid())
    RETURNING id INTO v_eval_id;
    RETURN v_eval_id;
END;
$$;
