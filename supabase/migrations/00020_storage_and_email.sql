-- =======================================================
-- MIGRATION: STORAGE BUCKET AND EMAIL NOTIFICATION TRIGGER
-- =======================================================

-- 1. TẠO BUCKET LƯU TRỮ CHỨNG CHỈ (STORAGE)
-- Đảm bảo bạn đã cài đặt Supabase Storage, lệnh này sẽ tạo bucket nếu chưa có
INSERT INTO storage.buckets (id, name, public)
VALUES ('supplier_documents', 'supplier_documents', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Mở quyền cho mọi người được tải lên (Insert) và tải xuống (Select) file
-- Trong thực tế bạn nên giới hạn quyền theo authenticated user, nhưng đây là demo
DROP POLICY IF EXISTS "Public View Document" ON storage.objects;
CREATE POLICY "Public View Document" ON storage.objects FOR SELECT USING (bucket_id = 'supplier_documents');

DROP POLICY IF EXISTS "Public Upload Document" ON storage.objects;
CREATE POLICY "Public Upload Document" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'supplier_documents');


-- 2. TẠO TRIGGER TỰ ĐỘNG GỬI EMAIL KHI DUYỆT YÊU CẦU
-- Mỗi khi bảng sm_supplier_request chuyển sang Approved hoặc Rejected, chèn 1 dòng vào outbox

CREATE OR REPLACE FUNCTION sm_trigger_email_on_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Chỉ kích hoạt khi trạng thái thay đổi thành Approved hoặc Rejected
    IF NEW.status IN ('Approved', 'Rejected') AND OLD.status != NEW.status THEN
        INSERT INTO public.sm_supplier_outbox (
            supplier_id,
            event_type,
            payload,
            status,
            created_by
        ) VALUES (
            NEW.supplier_id,
            'SEND_EMAIL',
            jsonb_build_object(
                'request_id', NEW.id,
                'request_no', NEW.request_no,
                'new_status', NEW.status,
                'message', 'Your supplier request has been ' || NEW.status
            ),
            'Pending',
            NEW.requested_by
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_email_on_decision ON public.sm_supplier_request;

CREATE TRIGGER trg_email_on_decision
AFTER UPDATE ON public.sm_supplier_request
FOR EACH ROW
EXECUTE FUNCTION sm_trigger_email_on_decision();
