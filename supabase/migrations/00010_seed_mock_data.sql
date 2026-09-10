-- 00010_seed_mock_data.sql
-- Run this in Supabase SQL Editor to seed mock data directly.

DO $$
DECLARE
    v_vendor_id uuid;
BEGIN
    -- 1. Get first vendor to attach mock data to
    SELECT id INTO v_vendor_id FROM public.vendor LIMIT 1;

    IF v_vendor_id IS NULL THEN
        RAISE NOTICE 'No vendor found. Cannot seed data.';
        RETURN;
    END IF;

    -- 2. Seed Scope
    IF NOT EXISTS (SELECT 1 FROM public.sm_supplier_scope WHERE supplier_id = v_vendor_id) THEN
        INSERT INTO public.sm_supplier_scope (supplier_id, department_id, region_id, category_id)
        VALUES 
            (v_vendor_id, 'ALL', 'ALL', 'ALL');
    END IF;

    -- 3. Seed Risks
    IF NOT EXISTS (SELECT 1 FROM public.sm_risk_issue WHERE supplier_id = v_vendor_id) THEN
        INSERT INTO public.sm_risk_issue (supplier_id, title, description, severity, status, due_date)
        VALUES 
            (v_vendor_id, 'Security', 'Chứng chỉ ISO 27001 sắp hết hạn', 'Medium', 'Open', null),
            (v_vendor_id, 'Financial', 'Chưa cập nhật BCTC 2025', 'High', 'Open', now() + interval '7 days');
    END IF;

    -- 4. Seed Documents (ensure 00006 was run)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sm_supplier_document') THEN
        IF NOT EXISTS (SELECT 1 FROM public.sm_supplier_document WHERE supplier_id = v_vendor_id) THEN
            INSERT INTO public.sm_supplier_document (supplier_id, document_type, storage_path, valid_to, status)
            VALUES 
                (v_vendor_id, 'Giấy phép kinh doanh', '#', null, 'Approved'),
                (v_vendor_id, 'ISO 27001', '#', now() - interval '1 day', 'Expired');
        END IF;
    END IF;

    -- 5. Seed History
    IF NOT EXISTS (SELECT 1 FROM public.sm_supplier_lifecycle_history WHERE supplier_id = v_vendor_id) THEN
        INSERT INTO public.sm_supplier_lifecycle_history (supplier_id, actor_id, reason, from_status, to_status)
        VALUES 
            (v_vendor_id, NULL, 'Onboarding_Submitted', 'Candidate', 'Onboarding'),
            (v_vendor_id, NULL, 'Lifecycle_Change', 'Onboarding', 'Active');
    END IF;

    -- 6. Seed Performance
    IF NOT EXISTS (SELECT 1 FROM public.sm_performance_evaluation WHERE supplier_id = v_vendor_id) THEN
        INSERT INTO public.sm_performance_evaluation (supplier_id, evaluation_period, total_score, grade, status)
        VALUES 
            (v_vendor_id, 'Q3/2026', 94, 'Excellent', 'Published');
    END IF;

    RAISE NOTICE 'Mock data seeding completed.';
END $$;
