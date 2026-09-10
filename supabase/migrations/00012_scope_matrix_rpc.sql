-- Migration 00012: Scope Matrix and Qualification RPC

CREATE OR REPLACE FUNCTION public.sm_add_supplier_scope(
    p_supplier_id uuid,
    p_department_id varchar(50),
    p_region_id varchar(50),
    p_category_id varchar(50),
    p_qualification_status qualification_status,
    p_classification_tier varchar(50)
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_scope_id uuid;
    v_qual_id uuid;
    v_class_id uuid;
BEGIN
    -- 1. Create or Get Scope
    -- Check if scope already exists
    SELECT id INTO v_scope_id 
    FROM sm_supplier_scope 
    WHERE supplier_id = p_supplier_id 
      AND department_id = p_department_id 
      AND region_id = p_region_id 
      AND category_id = p_category_id;
      
    IF v_scope_id IS NULL THEN
        -- Insert new scope
        INSERT INTO sm_supplier_scope (supplier_id, department_id, region_id, category_id, owner_id)
        VALUES (p_supplier_id, p_department_id, p_region_id, p_category_id, auth.uid())
        RETURNING id INTO v_scope_id;
        
        -- Log history
        INSERT INTO sm_supplier_scope_history (scope_id, event_type, after_state, actor_id)
        VALUES (v_scope_id, 'SCOPE_CREATED', jsonb_build_object('department', p_department_id, 'region', p_region_id, 'category', p_category_id), auth.uid());
    END IF;

    -- 2. Add Qualification
    IF p_qualification_status IS NOT NULL THEN
        -- "Close" old active qualification if any
        UPDATE sm_supplier_qualification SET valid_to = now() WHERE scope_id = v_scope_id AND (valid_to IS NULL OR valid_to > now());
        
        -- Insert new qualification
        INSERT INTO sm_supplier_qualification (scope_id, status, valid_from, approved_by, approved_at)
        VALUES (v_scope_id, p_qualification_status, now(), auth.uid(), now())
        RETURNING id INTO v_qual_id;
        
        -- Log history
        INSERT INTO sm_supplier_scope_history (scope_id, event_type, after_state, actor_id)
        VALUES (v_scope_id, 'QUALIFICATION_UPDATED', jsonb_build_object('status', p_qualification_status), auth.uid());
    END IF;

    -- 3. Add Classification
    IF p_classification_tier IS NOT NULL AND p_classification_tier != '' THEN
        -- "Close" old active classification if any
        UPDATE sm_supplier_classification SET valid_to = now() WHERE scope_id = v_scope_id AND (valid_to IS NULL OR valid_to > now());
        
        -- Insert new classification
        INSERT INTO sm_supplier_classification (scope_id, tier_id, valid_from, approved_by, approved_at)
        VALUES (v_scope_id, p_classification_tier, now(), auth.uid(), now())
        RETURNING id INTO v_class_id;
        
        -- Log history
        INSERT INTO sm_supplier_scope_history (scope_id, event_type, after_state, actor_id)
        VALUES (v_scope_id, 'CLASSIFICATION_UPDATED', jsonb_build_object('tier', p_classification_tier), auth.uid());
    END IF;

    RETURN v_scope_id;
END;
$$;
