-- =======================================================
-- MIGRATION: FIX DELETE PERMISSIONS AND CONSTRAINTS
-- =======================================================

-- 1. Cấp quyền mức Cơ sở dữ liệu (Database Privileges)
-- Hệ thống bảo mật (Security Hardening) có thể đã rút quyền DELETE của User.
GRANT DELETE ON public.vendor TO authenticated;
GRANT DELETE ON public.sm_supplier_request TO authenticated;

-- 2. Xóa chính sách (Policy) cũ để tránh lỗi "already exists" và tạo lại
DROP POLICY IF EXISTS "Allow delete on vendor" ON public.vendor;
CREATE POLICY "Allow delete on vendor" ON public.vendor FOR DELETE USING (true);

DROP POLICY IF EXISTS "Allow delete on requests" ON public.sm_supplier_request;
CREATE POLICY "Allow delete on requests" ON public.sm_supplier_request FOR DELETE USING (true);

-- 3. Sửa lỗi "violates foreign key constraint" (thêm ON DELETE CASCADE)
ALTER TABLE public.sm_supplier_request 
DROP CONSTRAINT IF EXISTS sm_supplier_request_supplier_id_fkey;

ALTER TABLE public.sm_supplier_request 
ADD CONSTRAINT sm_supplier_request_supplier_id_fkey 
FOREIGN KEY (supplier_id) REFERENCES public.vendor(id) ON DELETE CASCADE;
