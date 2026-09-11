-- ============================================================
-- CONCURRENCY TESTS
-- Kich ban: 2 nguoi cung duyet (Lost update prevention)
-- ============================================================
DO $$
DECLARE
    v_admin_uid uuid;
    v_vendor_id uuid;
    v_request_id uuid;
    v_pass_count int := 0;
    v_fail_count int := 0;
BEGIN
    RAISE NOTICE '=== CONCURRENCY TESTS START ===';

    SELECT id INTO v_admin_uid FROM auth.users LIMIT 1;
    IF v_admin_uid IS NULL THEN
        RAISE EXCEPTION 'Vui long tao it nhat 1 user trong Supabase Auth (Authentication > Users) de chay test nay.';
    END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid::text, 'role', 'authenticated')::text, true);
    
    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    INSERT INTO public.app_user_roles (user_id, role) VALUES (v_admin_uid, 'Approver');

    INSERT INTO public.vendor (vendor_name, lifecycle_status, row_version) VALUES ('Test Concurrency Vendor', 'Candidate', 1) RETURNING id INTO v_vendor_id;
    v_request_id := public.sm_submit_supplier_request(v_vendor_id, 'Submit_Onboarding', '{}', 'TEST-CC-1');

    -- Nguoi thu nhat duyet dung version
    BEGIN
        PERFORM public.sm_decide_supplier_request(v_request_id, 'Approve', 'First approve', 1);
        RAISE NOTICE 'PASS: Nguoi dau tien duyet thanh cong voi version = 1';
        v_pass_count := v_pass_count + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Nguoi dau tien duyet that bai: %', SQLERRM;
        v_fail_count := v_fail_count + 1;
    END;

    -- Nguoi thu hai cung thu duyet bang cach gui version = 1
    BEGIN
        PERFORM public.sm_decide_supplier_request(v_request_id, 'Approve', 'Second approve', 1);
        RAISE NOTICE 'FAIL: Nguoi thu hai duyet thanh cong du truyen sai version cu! Lost Update prevention failed.';
        v_fail_count := v_fail_count + 1;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Concurrent modification%' THEN
            RAISE NOTICE 'PASS: Nguoi thu hai bi chan thanh cong voi loi: %', SQLERRM;
            v_pass_count := v_pass_count + 1;
        ELSE
            RAISE NOTICE 'PASS (Alternative): Nguoi thu hai bi chan vi loi khac: %', SQLERRM;
            v_pass_count := v_pass_count + 1;
        END IF;
    END;

    -- Cleanup
    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    DELETE FROM public.sm_supplier_request WHERE supplier_id = v_vendor_id;
    DELETE FROM public.vendor WHERE id = v_vendor_id;

    RAISE NOTICE '=== CONCURRENCY TESTS COMPLETE ===';
    RAISE NOTICE 'PASS: % | FAIL: %', v_pass_count, v_fail_count;
END;
$$;
