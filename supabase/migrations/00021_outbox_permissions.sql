-- =======================================================
-- MIGRATION: OUTBOX RLS PERMISSIONS
-- =======================================================

-- 1. Cấp quyền mức CSDL
GRANT ALL ON public.sm_supplier_outbox TO authenticated;
GRANT ALL ON public.sm_supplier_outbox TO anon;

-- 2. Tạo policy cho phép Authenticated (UI) thêm dữ liệu
DROP POLICY IF EXISTS "Allow authenticated insert outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Allow authenticated insert outbox" ON public.sm_supplier_outbox FOR INSERT TO authenticated WITH CHECK (true);

-- 3. Tạo policy cho phép đọc Outbox để hiển thị trên UI
DROP POLICY IF EXISTS "Allow authenticated read outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Allow authenticated read outbox" ON public.sm_supplier_outbox FOR SELECT TO authenticated USING (true);

-- 4. Tạo policy cho phép Worker (chạy nặc danh - anon) Đọc và Cập nhật
DROP POLICY IF EXISTS "Allow anon read outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Allow anon read outbox" ON public.sm_supplier_outbox FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Allow anon update outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Allow anon update outbox" ON public.sm_supplier_outbox FOR UPDATE TO anon USING (true) WITH CHECK (true);
