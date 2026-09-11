-- Cấp quyền DELETE cho admin (Internal user) trên bảng Crosswalk và Outbox
-- Giúp người dùng dọn dẹp lịch sử rác trong quá trình testing

DROP POLICY IF EXISTS "Internal delete crosswalk" ON public.sm_supplier_crosswalk;
CREATE POLICY "Internal delete crosswalk" ON public.sm_supplier_crosswalk FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "Internal delete outbox" ON public.sm_supplier_outbox;
CREATE POLICY "Internal delete outbox" ON public.sm_supplier_outbox FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);
