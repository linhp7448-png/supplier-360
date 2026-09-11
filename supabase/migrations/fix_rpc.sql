CREATE OR REPLACE FUNCTION public.sm_check_supplier_eligibility(
    p_supplier_id uuid,
    p_scope_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_eligible boolean := true;
    v_reasons jsonb := '[]'::jsonb;
    
    v_risk_decision risk_decision_type;
    v_qualification_status qualification_status;
    v_doc_pending_count integer;
    v_vendor_status global_lifecycle_status;
BEGIN
    -- 1. Check Global Lifecycle Status
    SELECT lifecycle_status INTO v_vendor_status
    FROM public.vendor
    WHERE id = p_supplier_id;
    
    IF v_vendor_status NOT IN ('Active') THEN
        v_is_eligible := false;
        v_reasons := v_reasons || jsonb_build_object('type', 'LIFECYCLE', 'message', 'Supplier is not globally Active', 'current_status', v_vendor_status);
    END IF;

    -- 2. Check Risk Decision
    SELECT decision INTO v_risk_decision
    FROM public.sm_risk_decision
    WHERE supplier_id = p_supplier_id 
      AND (scope_id = p_scope_id OR scope_id IS NULL)
      AND (valid_until IS NULL OR valid_until > now())
    ORDER BY decided_at DESC LIMIT 1;
    
    IF v_risk_decision = 'Blocked' THEN
        v_is_eligible := false;
        v_reasons := v_reasons || jsonb_build_object('type', 'RISK', 'message', 'Supplier is blocked due to high risk');
    END IF;

    -- 3. Check Scope Qualification
    IF p_scope_id IS NOT NULL THEN
        SELECT q.status INTO v_qualification_status
        FROM public.sm_supplier_qualification q
        JOIN public.sm_supplier_scope s ON q.scope_id = s.id
        WHERE s.supplier_id = p_supplier_id 
          AND q.scope_id = p_scope_id
          AND (q.valid_to IS NULL OR q.valid_to > now())
        ORDER BY q.approved_at DESC NULLS LAST LIMIT 1;
        
        IF v_qualification_status IS NULL OR v_qualification_status NOT IN ('Qualified', 'Conditional') THEN
             v_is_eligible := false;
             v_reasons := v_reasons || jsonb_build_object('type', 'QUALIFICATION', 'message', 'Supplier is not qualified for this specific scope', 'current_status', v_qualification_status);
        END IF;
    END IF;

    -- 4. Check Missing/Pending Documents
    SELECT count(*) INTO v_doc_pending_count
    FROM public.sm_supplier_document
    WHERE supplier_id = p_supplier_id
      AND status NOT IN ('Approved');
      
    IF v_doc_pending_count > 0 THEN
         v_is_eligible := false;
         v_reasons := v_reasons || jsonb_build_object('type', 'COMPLIANCE', 'message', 'Supplier has missing, pending, or expired mandatory documents');
    END IF;

    RETURN jsonb_build_object(
        'eligible', v_is_eligible,
        'blocking_reasons', v_reasons
    );
END;
$$;
