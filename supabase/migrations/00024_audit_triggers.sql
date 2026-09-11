-- 1. Cấp quyền đọc cho bảng Audit Event
GRANT SELECT ON public.sm_supplier_audit_event TO authenticated;
GRANT SELECT ON public.sm_supplier_audit_event TO anon;

DROP POLICY IF EXISTS "Allow read audit" ON public.sm_supplier_audit_event;
CREATE POLICY "Allow read audit" ON public.sm_supplier_audit_event FOR SELECT USING (true);

-- 2. Tạo Trigger tự động ghi log thay đổi trạng thái của Nhà cung cấp
CREATE OR REPLACE FUNCTION sm_log_supplier_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.sm_supplier_audit_event (
            entity_type,
            entity_id,
            action,
            before_state,
            after_state,
            actor_id,
            source_system
        ) VALUES (
            'VENDOR',
            NEW.id,
            'STATUS_CHANGE',
            jsonb_build_object('status', OLD.status),
            jsonb_build_object('status', NEW.status),
            auth.uid(),
            'SUPPLIER_PORTAL'
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sm_trigger_audit_status ON public.sm_supplier_request;
CREATE TRIGGER sm_trigger_audit_status
    AFTER UPDATE ON public.sm_supplier_request
    FOR EACH ROW
    EXECUTE FUNCTION sm_log_supplier_status_change();
