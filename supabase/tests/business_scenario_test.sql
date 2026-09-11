-- ============================================================
-- BUSINESS SCENARIO TESTS
-- Kich ban: Tao vendor -> Nop form onboard -> Duyet -> Active
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
    RAISE NOTICE '=== BUSINESS SCENARIO TESTS START ===';

    SELECT id INTO v_admin_uid FROM auth.users LIMIT 1;
    IF v_admin_uid IS NULL THEN
        RAISE EXCEPTION 'Vui long tao it nhat 1 user trong Supabase Auth (Authentication > Users) de chay test nay.';
    END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid::text, 'role', 'authenticated')::text, true);

    BEGIN
        INSERT INTO public.vendor (vendor_name, lifecycle_status, source_system, tax_id, company_code)
        VALUES ('Test Scenario Vendor', 'Candidate', 'MANUAL', 'TAX-1234', 'COMP-01')
        RETURNING id INTO v_vendor_id;
        RAISE NOTICE 'PASS: Tao vendor Candidate thanh cong';
        v_pass_count := v_pass_count + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Tao vendor loi: %', SQLERRM;
        v_fail_count := v_fail_count + 1;
    END;

    BEGIN
        v_request_id := public.sm_submit_supplier_request(
            v_vendor_id,
            'Submit_Onboarding',
            '{"tax_id": "TAX-1234"}'::jsonb,
            'TEST-ONB-1'
        );
        RAISE NOTICE 'PASS: Submit_Onboarding request thanh cong';
        v_pass_count := v_pass_count + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Submit request loi: %', SQLERRM;
        v_fail_count := v_fail_count + 1;
    END;

    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    INSERT INTO public.app_user_roles (user_id, role) VALUES (v_admin_uid, 'Approver');
    
    BEGIN
        PERFORM public.sm_decide_supplier_request(
            v_request_id,
            'Approve',
            'OK to onboarding',
            NULL
        );
        
        SELECT lifecycle_status INTO v_status FROM public.vendor WHERE id = v_vendor_id;
        IF v_status = 'Pending_Review' THEN
            RAISE NOTICE 'PASS: Vendor chuyen status thanh Pending_Review sau khi duyet Onboarding';
            v_pass_count := v_pass_count + 1;
        ELSE
            RAISE NOTICE 'FAIL: Vendor status khong dung. Hien tai: %', v_status;
            v_fail_count := v_fail_count + 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Approve request loi: %', SQLERRM;
        v_fail_count := v_fail_count + 1;
    END;

    -- Cleanup
    DELETE FROM public.app_user_roles WHERE user_id = v_admin_uid AND role = 'Approver';
    DELETE FROM public.sm_supplier_request WHERE supplier_id = v_vendor_id;
    DELETE FROM public.vendor WHERE id = v_vendor_id;

    RAISE NOTICE '=== BUSINESS SCENARIO TESTS COMPLETE ===';
    RAISE NOTICE 'PASS: % | FAIL: %', v_pass_count, v_fail_count;
END;
$$;
