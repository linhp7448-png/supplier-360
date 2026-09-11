-- Migration 00018: Phase 3 and Phase 4 Missing RPCs

-- ============================================================
-- PHASE 3: RISK MANAGEMENT RPCS
-- ============================================================

-- 1. sm_create_risk_assessment
CREATE OR REPLACE FUNCTION public.sm_create_risk_assessment(
    p_supplier_id uuid,
    p_scope_id uuid DEFAULT NULL,
    p_model_version_id integer DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_assessment_id uuid;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Risk_Reviewer', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Risk_Reviewer or Approver can create Risk Assessments';
    END IF;

    INSERT INTO public.sm_risk_assessment (supplier_id, scope_id, model_version_id, assessed_by)
    VALUES (p_supplier_id, p_scope_id, p_model_version_id, auth.uid())
    RETURNING id INTO v_assessment_id;

    RETURN v_assessment_id;
END;
$$;

-- 2. sm_add_risk_factor
CREATE OR REPLACE FUNCTION public.sm_add_risk_factor(
    p_assessment_id uuid,
    p_category_id varchar(50),
    p_observation text,
    p_probability numeric DEFAULT NULL,
    p_impact numeric DEFAULT NULL,
    p_evidence_url text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_factor_id uuid;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Risk_Reviewer', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Risk_Reviewer or Approver can add risk factors';
    END IF;

    INSERT INTO public.sm_risk_factor (assessment_id, category_id, observation, probability, impact, evidence_url)
    VALUES (p_assessment_id, p_category_id, p_observation, p_probability, p_impact, p_evidence_url)
    RETURNING id INTO v_factor_id;

    RETURN v_factor_id;
END;
$$;

-- 3. sm_add_risk_control
CREATE OR REPLACE FUNCTION public.sm_add_risk_control(
    p_assessment_id uuid,
    p_control_description text,
    p_review_date timestamptz DEFAULT NULL,
    p_expiry_date timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_control_id uuid;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Risk_Reviewer', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Risk_Reviewer or Approver can add risk controls';
    END IF;

    INSERT INTO public.sm_risk_control (assessment_id, control_description, owner_id, review_date, expiry_date)
    VALUES (p_assessment_id, p_control_description, auth.uid(), p_review_date, p_expiry_date)
    RETURNING id INTO v_control_id;

    RETURN v_control_id;
END;
$$;

-- ============================================================
-- PHASE 4: DOCUMENT & QUESTIONNAIRE RPCS
-- ============================================================

-- 4. sm_assign_questionnaire
CREATE OR REPLACE FUNCTION public.sm_assign_questionnaire(
    p_supplier_id uuid,
    p_template_id integer,
    p_due_date timestamptz DEFAULT NULL,
    p_assigned_to uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
    v_instance_id uuid;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Buyer', 'Admin') THEN
        RAISE EXCEPTION 'Only Supplier_Manager or Buyer can assign questionnaires';
    END IF;

    INSERT INTO public.sm_questionnaire_instance (supplier_id, template_id, status, assigned_to, due_date)
    VALUES (p_supplier_id, p_template_id, 'Assigned', p_assigned_to, p_due_date)
    RETURNING id INTO v_instance_id;

    RETURN v_instance_id;
END;
$$;

-- 5. sm_submit_questionnaire
CREATE OR REPLACE FUNCTION public.sm_submit_questionnaire(
    p_instance_id uuid,
    p_responses jsonb -- Array of {question_id, answer_text, answer_number, answer_boolean, attachment_path}
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_instance sm_questionnaire_instance%ROWTYPE;
    v_elem jsonb;
BEGIN
    -- Check access (must be supplier user or manager)
    SELECT * INTO v_instance FROM public.sm_questionnaire_instance WHERE id = p_instance_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Instance not found'; END IF;

    -- Update instance status
    UPDATE public.sm_questionnaire_instance
    SET status = 'Submitted', submitted_at = now()
    WHERE id = p_instance_id;

    -- Insert responses
    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_responses)
    LOOP
        INSERT INTO public.sm_questionnaire_response (
            instance_id, question_id, answer_text, answer_number, answer_boolean, attachment_path, respondent_id
        ) VALUES (
            p_instance_id,
            (v_elem->>'question_id')::integer,
            v_elem->>'answer_text',
            (v_elem->>'answer_number')::numeric,
            (v_elem->>'answer_boolean')::boolean,
            v_elem->>'attachment_path',
            auth.uid()
        )
        ON CONFLICT (instance_id, question_id) DO UPDATE SET
            answer_text = EXCLUDED.answer_text,
            answer_number = EXCLUDED.answer_number,
            answer_boolean = EXCLUDED.answer_boolean,
            attachment_path = EXCLUDED.attachment_path,
            respondent_id = EXCLUDED.respondent_id;
    END LOOP;
END;
$$;

-- 6. sm_review_questionnaire
CREATE OR REPLACE FUNCTION public.sm_review_questionnaire(
    p_instance_id uuid,
    p_decision text, -- 'Approved' or 'Rejected'
    p_score numeric DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Manager or Approver can review questionnaires';
    END IF;

    UPDATE public.sm_questionnaire_instance
    SET status = p_decision::questionnaire_status,
        score = p_score,
        reviewer_id = auth.uid(),
        reviewed_at = now()
    WHERE id = p_instance_id;
END;
$$;

-- 7. sm_submit_document
CREATE OR REPLACE FUNCTION public.sm_submit_document(
    p_supplier_id uuid,
    p_document_type text,
    p_document_number text,
    p_issuer text,
    p_valid_from timestamptz,
    p_valid_to timestamptz,
    p_storage_path text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doc_id uuid;
BEGIN
    -- Both supplier and manager can submit documents
    INSERT INTO public.sm_supplier_document (
        supplier_id, document_type, document_number, issuer, valid_from, valid_to, storage_path, status
    ) VALUES (
        p_supplier_id, p_document_type, p_document_number, p_issuer, p_valid_from, p_valid_to, p_storage_path, 'Pending_Review'
    )
    RETURNING id INTO v_doc_id;

    RETURN v_doc_id;
END;
$$;

-- 8. sm_review_document
CREATE OR REPLACE FUNCTION public.sm_review_document(
    p_document_id uuid,
    p_decision text -- 'Approved' or 'Rejected'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role::text INTO v_role FROM app_user_roles WHERE user_id = auth.uid() LIMIT 1;
    IF v_role NOT IN ('Supplier_Manager', 'Approver', 'Admin') THEN
        RAISE EXCEPTION 'Only Manager or Approver can review documents';
    END IF;

    UPDATE public.sm_supplier_document
    SET status = p_decision::document_status,
        approved_by = auth.uid(),
        approved_at = now()
    WHERE id = p_document_id;
END;
$$;

-- ============================================================
-- Permissions
-- ============================================================
GRANT EXECUTE ON FUNCTION public.sm_create_risk_assessment TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_add_risk_factor TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_add_risk_control TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_assign_questionnaire TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_questionnaire TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_review_questionnaire TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_submit_document TO authenticated;
GRANT EXECUTE ON FUNCTION public.sm_review_document TO authenticated;

