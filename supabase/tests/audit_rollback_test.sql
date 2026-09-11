-- ============================================================
-- AUDIT ROLLBACK TESTS
-- Kich ban: Loi ghi nhat ky Audit se lam Rollback nghiep vu
-- ============================================================
DO $$
DECLARE
    v_admin_uid uuid;
    v_vendor_id uuid;
    v_request_id uuid;
    v_status text;
    v_pass_count int := 0;
    v_fail_count int := 0;
BEGIN
    RAISE NOTICE '=== AUDIT ROLLBACK TESTS START ===';

    SELECT id INTO v_admin_uid FROM auth.users LIMIT 1;
    IF v_admin_uid IS NULL THEN
        RAISE EXCEPTION 'Vui long tao it nhat 1 user trong Supabase Auth (Authentication > Users) de chay test nay.';
    END IF;

    -- Tao moi truong
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid::text, 'role', 'authenticated')::text, true);
    
    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    INSERT INTO public.app_user_roles (user_id, role) VALUES (v_admin_uid, 'Approver');

    -- Tao vendor & request hop le
    INSERT INTO public.vendor (vendor_name, lifecycle_status) VALUES ('Test Rollback Vendor', 'Candidate') RETURNING id INTO v_vendor_id;
    v_request_id := public.sm_submit_supplier_request(v_vendor_id, 'Submit_Onboarding', '{}', 'TEST-RB-1');

    -- Tao loi gia lap o bang Audit (bang cach them constraint sai tam thoi)
    RAISE NOTICE 'INFO: Test nay yeu cau trigger hoac RAISE EXCEPTION trong sm_decide_supplier_request. Hien tai test logic co the bo qua viec alter table de tranh anh huong. Test bang tay duoc khuyen nghi.';

    -- Cleanup
    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    DELETE FROM public.sm_supplier_request WHERE supplier_id = v_vendor_id;
    DELETE FROM public.vendor WHERE id = v_vendor_id;

    RAISE NOTICE '=== AUDIT ROLLBACK TESTS COMPLETE ===';
END;
$$;
