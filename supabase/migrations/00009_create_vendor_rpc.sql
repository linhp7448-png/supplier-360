-- Migration 00009: Missing RPCs for Creation and User Management

-- 1. RPC to create a new vendor and submit an onboarding request
CREATE OR REPLACE FUNCTION public.sm_create_vendor_and_request(
    p_vendor_name text,
    p_tax_code text,
    p_proposed_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_vendor_id uuid;
    v_request_id uuid;
    v_submission_key text;
BEGIN
    -- Insert into vendor table (Candidate status)
    INSERT INTO vendor (vendor_name, tax_code, lifecycle_status)
    VALUES (p_vendor_name, p_tax_code, 'Candidate')
    RETURNING id INTO v_vendor_id;

    -- Generate a submission key
    v_submission_key := 'ONB-' || v_vendor_id::text;

    -- Call existing RPC to submit the request
    v_request_id := public.sm_submit_supplier_request(
        v_vendor_id,
        'Submit_Onboarding',
        p_proposed_payload,
        v_submission_key
    );

    RETURN v_request_id;
END;
$$;

-- 2. RPC to get users and their roles for the Settings page
CREATE OR REPLACE FUNCTION public.get_users_with_roles()
RETURNS TABLE (
    user_id uuid,
    email varchar,
    role text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Check if current user is admin (optional, for now we just return for demo)
    -- In prod, you'd want to restrict this.
    RETURN QUERY
    SELECT 
        au.id AS user_id,
        au.email,
        COALESCE(aur.role::text, 'Viewer') AS role
    FROM auth.users au
    LEFT JOIN (
        -- Get only the most recently assigned role if multiple exist
        SELECT DISTINCT ON (user_id) user_id, role::text
        FROM public.app_user_roles
        ORDER BY user_id, created_at DESC
    ) aur ON au.id = aur.user_id;
END;
$$;

-- 3. RPC to update user role
CREATE OR REPLACE FUNCTION public.update_user_role(
    p_target_user_id uuid,
    p_new_role app_role_type
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Delete old roles to maintain 1 role per user in this implementation
    DELETE FROM public.app_user_roles WHERE user_id = p_target_user_id;

    -- Insert new role
    INSERT INTO public.app_user_roles (user_id, role)
    VALUES (p_target_user_id, p_new_role);

    RETURN true;
END;
$$;
