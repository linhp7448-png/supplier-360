-- Cấp quyền cho Bot ngầm (anon) ghi vào bảng Crosswalk
GRANT ALL ON public.sm_supplier_crosswalk TO anon;

DROP POLICY IF EXISTS "Allow anon upsert crosswalk" ON public.sm_supplier_crosswalk;
CREATE POLICY "Allow anon upsert crosswalk" ON public.sm_supplier_crosswalk FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anon select crosswalk" ON public.sm_supplier_crosswalk;
CREATE POLICY "Allow anon select crosswalk" ON public.sm_supplier_crosswalk FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Allow anon update crosswalk" ON public.sm_supplier_crosswalk;
CREATE POLICY "Allow anon update crosswalk" ON public.sm_supplier_crosswalk FOR UPDATE TO anon USING (true) WITH CHECK (true);
