-- =======================================================
-- MIGRATION 99999: CLEANUP DEMO & TEST DATA
-- =======================================================

-- Cảnh báo: Lệnh này sẽ xóa toàn bộ các nhà cung cấp có chứa chữ 'test' hoặc 'demo' trong tên.
-- Nhờ tính năng ON DELETE CASCADE, tất cả các dữ liệu liên quan ở bảng con (Rủi ro, Tài liệu, Đánh giá, Lịch sử...)
-- của các nhà cung cấp này cũng sẽ bị xóa sạch, trả lại một môi trường tinh tươm.

DELETE FROM public.vendor 
WHERE vendor_name ILIKE '%test%' 
   OR vendor_name ILIKE '%demo%';

-- Xóa các Sự kiện Outbox mồ côi (nếu có) do lúc nãy chúng ta dùng nút giả lập Push
DELETE FROM public.sm_supplier_outbox
WHERE payload->>'supplier_id' IS NULL;

-- Có thể bạn muốn reset lại chuỗi ID của một số bảng nếu cần thiết, 
-- nhưng UUID thì không cần reset.
