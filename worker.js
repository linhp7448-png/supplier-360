// ==========================================
// BACKGROUND WORKER (Tiến trình ngầm)
// ==========================================
// File này giả lập các hệ thống chạy ngầm của máy chủ (như Cron Job hoặc Message Queue)
// Nó sẽ đọc bảng Outbox và giả vờ bắn API sang hệ thống ERP (SAP/Oracle)

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://dauliufojymbcjkeegzt.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_PvBly6YX-WPjY4bO3aDjvw_7gtUlutV';

const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

console.log("🚀 Đã khởi động Background Worker");
console.log("🔄 Đang theo dõi bảng Outbox...");

async function processOutbox() {
    try {
        // 1. Lấy tất cả sự kiện Pending
        const { data: pendingEvents, error: fetchError } = await db
            .from('sm_supplier_outbox')
            .select('*')
            .eq('status', 'Pending')
            .order('created_at', { ascending: true });

        if (fetchError) throw fetchError;

        if (pendingEvents && pendingEvents.length > 0) {
            console.log(`\n📥 Phát hiện ${pendingEvents.length} sự kiện mới cần xử lý:`);
            
            for (const event of pendingEvents) {
                console.log(`   -> [${event.event_type}] Mã nhà cung cấp: ${event.payload ? event.payload.supplier_id : 'Unknown'}`);
                
                // Giả lập độ trễ khi gọi API ra bên ngoài (1.5 giây)
                await new Promise(resolve => setTimeout(resolve, 1500));

                let resultStatus = 'Success';
                let errorMessage = null;

                // Xử lý logic giả lập tùy loại sự kiện
                if (event.event_type === 'SEND_EMAIL') {
                    console.log(`      📧 Đã gửi Email tới: ${event.payload.request_no} - Message: ${event.payload.message}`);
                } else if (event.event_type === 'SYNC_ERP_PROFILE') {
                    console.log(`      🌐 Đã bắn API tới SAP Ariba ERP cho profile!`);
                } else {
                    console.log(`      🛠 Đã xử lý sự kiện mặc định!`);
                }

                // Tỉ lệ thất bại giả lập (10%)
                if (Math.random() < 0.1) {
                    resultStatus = 'Failed';
                    errorMessage = 'ERP API Timeout (Giả lập lỗi)';
                    console.log(`      ❌ Lỗi xử lý! (Giả lập)`);
                } else {
                    console.log(`      ✅ Thành công!`);
                    
                    // Nếu đẩy ERP thành công, giả lập việc ERP trả về 1 ID (Crosswalk)
                    if (event.event_type === 'MANUAL_PUSH_TO_ERP' && event.payload && event.payload.target_system) {
                        const erpId = `${event.payload.target_system}-${Math.floor(Math.random() * 90000) + 10000}`;
                        console.log(`      🔗 Đã nhận mã ERP ID: ${erpId}, tiến hành lưu Crosswalk...`);
                        
                        const targetSupplierId = event.supplier_id || (event.payload ? event.payload.supplier_id : null);
                        console.log(`      📝 Dữ liệu Crosswalk: targetSupplierId=${targetSupplierId}, targetSys=${event.payload.target_system}`);
                        if (targetSupplierId) {
                            const { error: cwError } = await db.from('sm_supplier_crosswalk').upsert({
                                supplier_id: targetSupplierId,
                                target_system: event.payload.target_system,
                                external_id: erpId
                            }, { onConflict: 'supplier_id, target_system' });
                            if (cwError) {
                                console.error(`      ❌ Lỗi lưu Crosswalk:`, cwError.message);
                            } else {
                                console.log(`      ✅ Đã lưu Crosswalk thành công!`);
                            }
                        }
                    }
                }

                // 2. Cập nhật trạng thái lại vào DB
                const { error: updateError } = await db
                    .from('sm_supplier_outbox')
                    .update({ 
                        status: resultStatus, 
                        error_message: errorMessage,
                        processed_at: new Date().toISOString()
                    })
                    .eq('id', event.id);

                if (updateError) console.error("Lỗi cập nhật CSDL:", updateError.message);
            }
        }
    } catch (err) {
        console.error("Lỗi Worker:", err.message);
    }
}

// Chạy vòng lặp mỗi 5 giây
setInterval(processOutbox, 5000);
