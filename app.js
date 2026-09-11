// ==========================================
// THIẾT LẬP KẾT NỐI SUPABASE
// ==========================================
// BẠN CẦN THAY THẾ 2 BIẾN NÀY BẰNG THÔNG TIN TỪ SUPABASE PROJECT CỦA BẠN
const SUPABASE_URL = 'https://dauliufojymbcjkeegzt.supabase.co'; 
const SUPABASE_ANON_KEY = 'sb_publishable_PvBly6YX-WPjY4bO3aDjvw_7gtUlutV';

let db;
let isConnected = false;
let isRealtimeSubscribed = false;

// ==========================================
// LOGIC GIAO DIỆN & DỮ LIỆU
// ==========================================

document.addEventListener('DOMContentLoaded', () => {
    // Khởi tạo Supabase Client
    if (SUPABASE_URL && SUPABASE_ANON_KEY) {
        if (window.supabase) {
            db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
            isConnected = true;
        } else {
            document.getElementById('loginError').innerHTML = '<i class="ph ph-warning-circle"></i> Lỗi kết nối mạng: Không tải được thư viện Supabase.';
            document.getElementById('loginError').style.display = 'block';
            return;
        }
    }

    if (!isConnected) {
        document.getElementById('loginError').innerHTML = '<i class="ph ph-warning-circle"></i> Vui lòng nhập API Keys vào file app.js';
        document.getElementById('loginError').style.display = 'block';
        return;
    }
    
    // Auth Listener
    db.auth.onAuthStateChange(async (event, session) => {
        if (session) {
            document.getElementById('loginOverlay').classList.remove('active');
            document.getElementById('mainApp').style.display = 'flex';
            
            // Set User Info
            const userEmail = session.user.email;
            document.getElementById('currentUserEmail').textContent = userEmail;
            document.getElementById('accountEmail').value = userEmail;
            
            // Load custom avatar if exists
            const savedAvatar = localStorage.getItem('user_avatar_' + session.user.id);
            const avatarUrl = savedAvatar || `https://ui-avatars.com/api/?name=${userEmail.charAt(0)}&background=0D8ABC&color=fff`;
            document.getElementById('headerAvatar').src = avatarUrl;
            
            // Fetch User Role
            const { data: roleData } = await db
                .from('app_user_roles')
                .select('role')
                .eq('user_id', session.user.id)
                .single();
                
            let displayRole = 'Viewer';
            if (roleData) {
                if (roleData.role === 'Approver') displayRole = 'Người phê duyệt';
                else if (roleData.role === 'Supplier_Manager') displayRole = 'Quản lý NCC';
                else displayRole = roleData.role;
            }
            document.getElementById('currentUserRole').textContent = displayRole;
            window.currentUserRole = roleData ? roleData.role : 'Viewer';

            // RBAC Enforcement on UI
            let rbacStyle = document.getElementById('rbac-style');
            if (!rbacStyle) {
                rbacStyle = document.createElement('style');
                rbacStyle.id = 'rbac-style';
                document.head.appendChild(rbacStyle);
            }
            
            if (window.currentUserRole === 'Viewer') {
                rbacStyle.innerHTML = `
                    .primary-btn, 
                    .action-btn,
                    button[onclick^="openNewSupplierModal"], 
                    button[onclick^="handleDecision"], 
                    button[onclick^="handleWithdraw"], 
                    button[onclick^="document.getElementById('riskModal')"], 
                    button[onclick^="document.getElementById('performanceModal')"], 
                    button[onclick^="document.getElementById('scopeModal')"], 
                    button[onclick^="document.getElementById('documentModal')"] {
                        display: none !important;
                    }
                    /* Ngoại trừ nút Login */
                    #loginForm .primary-btn { display: flex !important; }
                `;
            } else {
                rbacStyle.innerHTML = '';
            }

            // Load Initial Data
            // await seedMockDataIfEmpty(); // Temporarily disabled due to RLS policies
            fetchSuppliers();
            fetchDashboardStats();
            fetchRequests(); // Lấy danh sách Requests
            fetchRiskDashboard();
            fetchPerformance();
            fetchWorkQueue();
            fetchExpiringQualifications();

            // Đăng ký nhận thông báo Realtime từ Supabase khi có Request mới
            if (!isRealtimeSubscribed) {
                db.channel('public:sm_supplier_request')
                  .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'sm_supplier_request' }, payload => {
                      showToast('New request submitted: ' + payload.new.request_no);
                      fetchRequests(); // Tự động reload danh sách và badge
                      fetchDashboardStats();
                  })
                  .subscribe();
                isRealtimeSubscribed = true;
            }

        } else {
            document.getElementById('loginOverlay').classList.add('active');
            document.getElementById('mainApp').style.display = 'none';
        }
    });

    // Login Form Submit
    document.getElementById('loginForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = document.getElementById('loginEmail').value;
        const password = document.getElementById('loginPassword').value;
        const btn = document.getElementById('loginBtn');
        const err = document.getElementById('loginError');
        
        btn.innerHTML = '<div class="spinner" style="width:16px; height:16px; border-width:2px; display:inline-block; margin:0 5px 0 0; border-left-color: white;"></div> Đang đăng nhập...';
        btn.disabled = true;
        err.style.display = 'none';

        const { error } = await db.auth.signInWithPassword({ email, password });
        
        if (error) {
            err.textContent = error.message;
            err.style.display = 'block';
            btn.innerHTML = 'Sign In';
            btn.disabled = false;
        }
    });
    
    // Thiết lập logic chuyển tab (Sidebar Navigation)
    setupNavigation();
});

// Logout
async function handleLogout() {
    await db.auth.signOut();
}

// Hàm xử lý chuyển đổi giữa các trang (Views)
function setupNavigation() {
    const navItems = document.querySelectorAll('.sidebar .nav-item');
    const viewSections = document.querySelectorAll('.view-section');

    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            
            // Xóa class active ở tất cả các nút
            navItems.forEach(nav => nav.classList.remove('active'));
            // Thêm class active cho nút vừa bấm
            item.classList.add('active');

            // Lấy ID của trang cần hiển thị
            const targetId = item.getAttribute('data-target');

            // Ẩn tất cả các trang
            viewSections.forEach(section => {
                section.style.display = '';
                section.classList.remove('active');
            });
            
            // Hiển thị trang được chọn
            const targetSection = document.getElementById(targetId);
            if (targetSection) {
                targetSection.style.display = '';
                targetSection.classList.add('active');
            }
        });
    });
}

// Hàm lấy dữ liệu thống kê từ database
async function fetchDashboardStats() {
    try {
        // Lấy số lượng yêu cầu đang chờ duyệt (Pending)
        const { count: pendingCount, error: reqError } = await db
            .from('sm_supplier_request')
            .select('*', { count: 'exact', head: true })
            .in('status', ['Submitted', 'In_Review']);

        if (!reqError) {
            document.getElementById('pending-requests-count').textContent = pendingCount || 0;
        }

        // Lấy số lượng rủi ro cao (High/Critical Risk)
        const { count: riskCount, error: riskError } = await db
            .from('sm_risk_assessment')
            .select('*', { count: 'exact', head: true })
            .in('overall_severity', ['High', 'Critical'])
            .eq('status', 'Open');

        if (!riskError) {
            const riskCountEl = document.getElementById('high-risk-count');
            riskCountEl.textContent = riskCount || 0;
            
            // Tinh chỉnh độ tương phản của thẻ "High Risk Alerts"
            const riskCard = riskCountEl.closest('.stat-card');
            if (riskCard) {
                if (riskCount > 0) {
                    riskCard.style.background = 'rgba(255, 77, 79, 0.05)'; 
                    riskCard.style.borderColor = 'var(--danger)'; 
                    riskCard.style.boxShadow = '0 0 20px rgba(255, 77, 79, 0.15)';
                    riskCountEl.style.color = 'var(--danger)';
                } else {
                    riskCard.style.background = '';
                    riskCard.style.borderColor = '';
                    riskCard.style.boxShadow = '';
                    riskCountEl.style.color = '';
                }
            }
        }
        
        // --- DRAW DASHBOARD CHART ---
        const { data: allRisks, error: chartError } = await db
            .from('sm_risk_assessment')
            .select('overall_severity')
            .eq('status', 'Open');
            
        if (!chartError && allRisks) {
            const riskCounts = {
                'Critical': 0,
                'High': 0,
                'Medium': 0,
                'Low': 0
            };
            allRisks.forEach(r => {
                if (riskCounts[r.overall_severity] !== undefined) {
                    riskCounts[r.overall_severity]++;
                }
            });

            const ctx = document.getElementById('dashboardRiskChart');
            if (ctx) {
                if (window.dashboardRiskChartInstance) {
                    window.dashboardRiskChartInstance.destroy();
                }
                
                Chart.defaults.color = 'rgba(255, 255, 255, 0.7)';
                
                window.dashboardRiskChartInstance = new Chart(ctx, {
                    type: 'bar',
                    data: {
                        labels: ['Critical', 'High', 'Medium', 'Low'],
                        datasets: [{
                            label: 'Số lượng Rủi ro (Đang mở)',
                            data: [riskCounts['Critical'], riskCounts['High'], riskCounts['Medium'], riskCounts['Low']],
                            backgroundColor: [
                                '#7F1D1D', // Critical (Dark Red)
                                '#DC2626', // High (Red)
                                '#F59E0B', // Medium (Amber)
                                '#10B981'  // Low (Green)
                            ],
                            borderWidth: 0,
                            borderRadius: 6
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            legend: {
                                display: false
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: true,
                                grid: {
                                    color: 'rgba(255, 255, 255, 0.1)',
                                    drawBorder: false,
                                },
                                ticks: {
                                    precision: 0
                                }
                            },
                            x: {
                                grid: {
                                    display: false
                                }
                            }
                        }
                    }
                });
            }
        }
        // -----------------------------

    } catch (error) {
        console.error("Lỗi khi tải thống kê:", error);
    }
}

// Hàm lấy danh sách nhà cung cấp từ bảng `vendor`
async function fetchSuppliers() {
    try {
        // Lấy tất cả Supplier (bao gồm Onboarding, Active, Candidate...)
        const { data, error } = await db
            .from('vendor')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) throw error;

        renderSuppliers(data);
        
        // Cập nhật số lượng
        document.getElementById('total-suppliers-count').textContent = data.length;
        
    } catch (error) {
        console.error('Error fetching suppliers:', error.message);
        document.getElementById('supplier-table-body').innerHTML = `
            <tr><td colspan="6" class="text-center" style="color: var(--danger)">Lỗi tải dữ liệu: ${error.message}</td></tr>
        `;
    }
}

// Export suppliers to different formats
window.exportToFile = async function(type) {
    document.getElementById('exportDropdown').style.display = 'none'; // hide dropdown
    try {
        const { data, error } = await db
            .from('vendor')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) throw error;
        
        if (!data || data.length === 0) {
            alert('Không có dữ liệu để xuất!');
            return;
        }

        const dateStr = new Date().toISOString().split('T')[0];

        if (type === 'excel') {
            // Excel (CSV)
            let csvContent = "Tên NCC,Mã ERP,Trạng thái,Quốc gia,Ngày tạo\n";
            data.forEach(v => {
                const name = `"${(v.vendor_name || '').replace(/"/g, '""')}"`;
                const erpId = v.erp_vendor_id || '';
                const status = v.lifecycle_status || '';
                const country = v.country || '';
                const date = v.created_at ? new Date(v.created_at).toLocaleDateString() : '';
                csvContent += `${name},${erpId},${status},${country},${date}\n`;
            });

            const blob = new Blob(["\uFEFF" + csvContent], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement("a");
            link.href = url;
            link.download = `Suppliers_${dateStr}.csv`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            
        } else if (type === 'pdf') {
            // PDF Export using jsPDF
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF();
            
            doc.setFontSize(16);
            doc.text("Danh sach Nha cung cap (Supplier List)", 14, 20);
            
            const tableColumn = ["Ten NCC", "Ma ERP", "Trang thai", "Quoc gia", "Ngay tao"];
            const tableRows = [];

            data.forEach(v => {
                const rowData = [
                    v.vendor_name || '',
                    v.erp_vendor_id || 'N/A',
                    v.lifecycle_status || 'N/A',
                    v.country || 'N/A',
                    v.created_at ? new Date(v.created_at).toLocaleDateString() : 'N/A'
                ];
                tableRows.push(rowData);
            });

            doc.autoTable({
                head: [tableColumn],
                body: tableRows,
                startY: 30,
            });

            doc.save(`Suppliers_${dateStr}.pdf`);
            
        } else if (type === 'word') {
            // Word Export using HTML table
            let tableHtml = `
                <html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'>
                <head><meta charset='utf-8'><title>Export HTML To Doc</title></head><body>
                <h2>Danh sách Nhà cung cấp</h2>
                <table border="1" style="width:100%; border-collapse:collapse;">
                    <thead>
                        <tr style="background-color:#f2f2f2;">
                            <th>Tên NCC</th>
                            <th>Mã ERP</th>
                            <th>Trạng thái</th>
                            <th>Quốc gia</th>
                            <th>Ngày tạo</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            
            data.forEach(v => {
                tableHtml += `
                    <tr>
                        <td>${v.vendor_name || ''}</td>
                        <td>${v.erp_vendor_id || ''}</td>
                        <td>${v.lifecycle_status || ''}</td>
                        <td>${v.country || ''}</td>
                        <td>${v.created_at ? new Date(v.created_at).toLocaleDateString() : ''}</td>
                    </tr>
                `;
            });
            
            tableHtml += `</tbody></table></body></html>`;
            
            const blob = new Blob(['\ufeff', tableHtml], { type: 'application/msword' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `Suppliers_${dateStr}.doc`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

    } catch (err) {
        console.error("Lỗi xuất file:", err);
        alert("Lỗi xuất file: " + err.message);
    }
}

// Hàm render dữ liệu ra bảng HTML
function renderSuppliers(suppliers) {
    const tbody = document.getElementById('supplier-table-body');
    
    if (suppliers.length === 0) {
        tbody.innerHTML = `
        <tr>
            <td colspan="6" class="text-center" style="padding: 60px 0; border: none;">
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; color: var(--text-muted);">
                    <i class="ph ph-folder-open" style="font-size: 3.5rem; color: #cbd5e1; opacity: 0.6;"></i>
                    <p style="margin: 0; font-size: 0.95rem;">Chưa có nhà cung cấp nào. Bắt đầu bằng cách tạo mới.</p>
                    <button class="primary-btn" onclick="openNewSupplierModal()" style="margin-top: 8px; background: transparent; border: 1px solid var(--primary); color: var(--primary); padding: 8px 16px; font-size: 0.85rem; font-weight: 500;">
                        <i class="ph ph-plus"></i> Thêm nhà cung cấp
                    </button>
                </div>
            </td>
        </tr>`;
        return;
    }

    tbody.innerHTML = suppliers.map(supplier => `
        <tr>
            <td style="text-align: center;">
                <input type="checkbox" class="supplier-checkbox" value="${supplier.id}">
            </td>
            <td>
                <strong>${supplier.vendor_name}</strong>
            </td>
            <td>${supplier.tax_code || '<span style="color:#999">N/A</span>'}</td>
            <td>
                <span class="status-badge status-${supplier.lifecycle_status.toLowerCase()}">
                    ${supplier.lifecycle_status.replace('_', ' ')}
                </span>
            </td>
            <td>Global</td>
            <td>${new Date(supplier.created_at).toLocaleDateString()}</td>
            <td>
                <button class="icon-btn" title="View Details" onclick="openSupplier360('${supplier.id}')"><i class="ph ph-eye"></i></button>
                <button class="icon-btn" title="Edit" onclick="openEditSupplierModal('${supplier.id}')"><i class="ph ph-pencil-simple"></i></button>
                <button class="icon-btn" title="Delete" style="color: var(--danger);" onclick="deleteSupplier('${supplier.id}')"><i class="ph ph-trash"></i></button>
            </td>
        </tr>
    `).join('');
}

// ==========================================
// BULK & SINGLE DELETE
// ==========================================

window.toggleAllSuppliers = function(source) {
    const checkboxes = document.querySelectorAll('.supplier-checkbox');
    checkboxes.forEach(cb => cb.checked = source.checked);
}

window.searchSuppliers = async function() {
    // ... search function inside 
}

// ============================================================
// PROFILE & ACCOUNT SETTINGS
// ============================================================
window.toggleProfileDropdown = function() {
    const dropdown = document.getElementById('profileDropdown');
    dropdown.style.display = dropdown.style.display === 'block' ? 'none' : 'block';
};

// Close dropdown when clicking outside
document.addEventListener('click', function(event) {
    const profileMenu = document.querySelector('.user-profile');
    const dropdown = document.getElementById('profileDropdown');
    if (profileMenu && dropdown && !profileMenu.contains(event.target) && !dropdown.contains(event.target)) {
        dropdown.style.display = 'none';
    }
});

let currentTempAvatar = '';

window.openAccountModal = function(focusField) {
    document.getElementById('accountModal').classList.add('active');
    
    // Set current avatar preview
    const session = db.auth.getSession ? undefined : null; // Hacky way to get current avatar
    const currentSrc = document.getElementById('headerAvatar').src;
    document.getElementById('accountAvatarPreview').src = currentSrc;
    currentTempAvatar = currentSrc;
    
    if (focusField === 'password') {
        setTimeout(() => document.getElementById('accountNewPassword').focus(), 100);
    }
};

window.closeAccountModal = function() {
    document.getElementById('accountModal').classList.remove('active');
    document.getElementById('accountNewPassword').value = '';
};

window.changeAvatar = function() {
    const colors = ['0D8ABC', '10B981', 'EF4444', 'F59E0B', '8B5CF6', 'EC4899'];
    const randomColor = colors[Math.floor(Math.random() * colors.length)];
    const email = document.getElementById('accountEmail').value || 'User';
    
    currentTempAvatar = `https://ui-avatars.com/api/?name=${email.charAt(0)}&background=${randomColor}&color=fff`;
    document.getElementById('accountAvatarPreview').src = currentTempAvatar;
};

window.saveAccountSettings = async function() {
    const btn = document.querySelector('#accountModal .primary-btn');
    btn.innerHTML = 'Đang lưu...';
    btn.disabled = true;
    
    try {
        const newPassword = document.getElementById('accountNewPassword').value;
        const { data: { session } } = await db.auth.getSession();
        
        // Save Avatar locally
        if (session && currentTempAvatar) {
            localStorage.setItem('user_avatar_' + session.user.id, currentTempAvatar);
            document.getElementById('headerAvatar').src = currentTempAvatar;
        }

        // Save password if provided
        if (newPassword) {
            const { error } = await db.auth.updateUser({
                password: newPassword
            });
            if (error) throw error;
        }

        showToast("Lưu thông tin thành công!");
        closeAccountModal();
        
    } catch (err) {
        console.error(err);
        alert("Lỗi: " + err.message);
    } finally {
        btn.innerHTML = 'Lưu thay đổi';
        btn.disabled = false;
    }
};

window.deleteSupplier = async function(id) {
    if (!confirm('Bạn có chắc chắn muốn xóa Nhà cung cấp này? Mọi dữ liệu liên quan sẽ bị xóa.')) return;
    
    try {
        const { error } = await db.from('vendor').delete().eq('id', id);
        if (error) throw error;
        showToast('Đã xóa nhà cung cấp.');
        fetchSuppliers();
    } catch (err) {
        alert("Lỗi khi xóa: " + err.message);
    }
}

window.deleteSelectedSuppliers = async function() {
    const checkboxes = document.querySelectorAll('.supplier-checkbox:checked');
    if (checkboxes.length === 0) {
        alert("Vui lòng chọn ít nhất 1 Nhà cung cấp để xóa.");
        return;
    }
    
    if (!confirm(`Bạn có chắc muốn xóa ${checkboxes.length} Nhà cung cấp đã chọn?`)) return;
    
    const ids = Array.from(checkboxes).map(cb => cb.value);
    
    try {
        const { error } = await db.from('vendor').delete().in('id', ids);
        if (error) throw error;
        
        showToast(`Đã xóa ${ids.length} Nhà cung cấp.`);
        document.getElementById('selectAllSuppliers').checked = false;
        fetchSuppliers();
    } catch (err) {
        alert("Lỗi khi xóa nhiều: " + err.message);
    }
}
// ==========================================
// XỬ LÝ MODAL (TẠO NHÀ CUNG CẤP MỚI)
// ==========================================

const modal = document.getElementById('newSupplierModal');

function openNewSupplierModal() {
    modal.classList.add('active');
}

function closeNewSupplierModal() {
    modal.classList.remove('active');
    document.getElementById('newSupplierForm').reset();
}

async function submitNewSupplier() {
    if (!isConnected) {
        alert("Vui lòng nhập API Keys trước khi thao tác!");
        return;
    }

    const name = document.getElementById('supplierName').value;
    const taxCode = document.getElementById('taxCode').value;
    const country = document.getElementById('country').value;
    const website = document.getElementById('website').value;

    if (!name || !country) {
        alert("Vui lòng nhập Tên và Quốc gia!");
        return;
    }

    const btn = document.querySelector('.modal-footer .primary-btn');
    btn.innerHTML = '<div class="spinner" style="width:16px; height:16px; border-width:2px; display:inline-block; margin:0 5px 0 0;"></div> Đang lưu...';
    btn.disabled = true;

    try {
        // Build payload
        const payload = {
            country: country,
            website: website
        };

        // Gọi RPC an toàn (Security Definer) để tạo Vendor và Request
        const { data: requestId, error } = await db.rpc('sm_create_vendor_and_request', {
            p_vendor_name: name,
            p_tax_code: taxCode || null,
            p_proposed_payload: payload
        });

        if (error) throw error;

        // Thành công -> Đóng modal và tải lại bảng
        closeNewSupplierModal();
        fetchSuppliers();
        fetchDashboardStats();
        fetchRequests();
        
    } catch (error) {
        alert('Lỗi khi tạo nhà cung cấp: ' + error.message);
    } finally {
        btn.innerHTML = 'Create Record';
        btn.disabled = false;
    }
}

// ==========================================
// MAKER-CHECKER (REQUESTS)
// ==========================================

// Helper tạo Toast Notification đẹp mắt
function showToast(message) {
    const container = document.getElementById('toastContainer');
    if (!container) return;
    const toast = document.createElement('div');
    toast.style.cssText = 'background: rgba(17, 19, 21, 0.9); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); padding: 16px 20px; border-left: 4px solid var(--primary); border-radius: 8px; color: white; display: flex; align-items: center; gap: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); transform: translateX(120%); transition: transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);';
    toast.innerHTML = `<i class="ph-fill ph-bell-ringing" style="color: var(--primary); font-size: 1.25rem;"></i> <span style="font-size: 0.9rem; font-weight: 500;">${message}</span>`;
    container.appendChild(toast);
    
    // Trigger animation
    requestAnimationFrame(() => {
        toast.style.transform = 'translateX(0)';
    });
    
    setTimeout(() => {
        toast.style.transform = 'translateX(120%)';
        setTimeout(() => toast.remove(), 400);
    }, 5000);
}

async function fetchRequests() {
    try {
        const { data, error } = await db
            .from('sm_supplier_request')
            .select(`
                *,
                vendor ( vendor_name )
            `)
            .order('created_at', { ascending: false });

        if (error) throw error;
        
        // Cập nhật Badge số lượng Pending
        const pendingCount = data.filter(r => r.status === 'Pending_Review' || r.status === 'Submitted').length;
        const badge = document.getElementById('requestsBadge');
        const bellBadge = document.querySelector('.header-actions .badge');
        
        if (badge) {
            if (pendingCount > 0) {
                badge.textContent = pendingCount;
                badge.style.display = 'inline-block';
            } else {
                badge.style.display = 'none';
            }
        }
        
        // Cập nhật luôn chuông thông báo trên Header
        if (bellBadge) {
            if (pendingCount > 0) {
                bellBadge.textContent = pendingCount;
                bellBadge.style.display = 'inline-block';
            } else {
                bellBadge.style.display = 'none';
            }
        }
        
        // Populate notification list
        const notifList = document.getElementById('notificationList');
        if (notifList) {
            const pendingRequests = data.filter(r => r.status === 'Pending_Review' || r.status === 'Submitted');
            if (pendingRequests.length > 0) {
                notifList.innerHTML = pendingRequests.map(req => `
                    <div style="padding: 10px 16px; border-bottom: 1px solid rgba(255,255,255,0.02); display: flex; align-items: start; gap: 10px; cursor: pointer;" onmouseover="this.style.background='rgba(255,255,255,0.05)'" onmouseout="this.style.background='transparent'" onclick="document.querySelector('[data-target=\\'view-requests\\']').click(); toggleNotificationDropdown();">
                        <div style="background: rgba(13,138,188,0.2); padding: 8px; border-radius: 50%; color: var(--primary);">
                            <i class="ph-fill ph-file-text"></i>
                        </div>
                        <div style="text-align: left;">
                            <div style="font-size: 0.85rem; font-weight: 600; color: #1e293b;">${req.vendor?.vendor_name || 'Nhà cung cấp mới'}</div>
                            <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 2px;">Yêu cầu duyệt hồ sơ ${req.request_type === 'Submit_Onboarding' ? 'gia nhập' : req.request_type.replace(/_/g, ' ')}</div>
                            <div style="font-size: 0.7rem; color: #94a3b8; margin-top: 4px;">${new Date(req.created_at).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>
                        </div>
                    </div>
                `).join('');
            } else {
                notifList.innerHTML = `<div style="padding: 16px; text-align: center; color: var(--text-muted); font-size: 0.85rem;">Không có thông báo mới</div>`;
            }
        }

        renderRequests(data);
    } catch (error) {
        console.error("Lỗi lấy danh sách Requests:", error);
    }
}

function renderRequests(requests) {
    const tbody = document.getElementById('requests-table-body');
    if (!requests || requests.length === 0) {
        tbody.innerHTML = `<tr><td colspan="6" class="text-center">Không có yêu cầu nào chờ duyệt.</td></tr>`;
        return;
    }

    const translateType = (type) => {
        if (type === 'Submit_Onboarding') return 'Gửi hồ sơ gia nhập';
        return type.replace(/_/g, ' ');
    };

    const translateStatus = (status) => {
        if (status === 'Submitted') return 'Đã gửi';
        if (status === 'Pending_Review') return 'Chờ duyệt';
        if (status === 'Approved') return 'Đã duyệt';
        if (status === 'Rejected') return 'Đã từ chối';
        return status.replace(/_/g, ' ');
    };

    tbody.innerHTML = requests.map(req => `
        <tr>
            <td><strong>${req.request_no}</strong></td>
            <td>${req.vendor?.vendor_name || 'N/A'}</td>
            <td>${translateType(req.request_type)}</td>
            <td>
                <span class="status-badge status-${req.status.toLowerCase()}">${translateStatus(req.status)}</span>
            </td>
            <td>${req.requested_by ? 'Người dùng' : 'Hệ thống'}</td>
            <td>
                ${req.status === 'Pending_Review' || req.status === 'Submitted' ? `
                    <div style="display: flex; flex-direction: row; gap: 8px; align-items: center; justify-content: flex-start;">
                        <button style="padding: 4px 12px; font-size: 0.8rem; background: #10b981; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: 500;" onclick="handleDecision('${req.id}', 'Approve')">Duyệt</button>
                        <button style="padding: 4px 12px; font-size: 0.8rem; color: var(--danger); background: transparent; border: 1px solid rgba(255, 77, 79, 0.4); border-radius: 6px; cursor: pointer; font-weight: 500;" onclick="handleDecision('${req.id}', 'Reject')">Từ chối</button>
                        <button style="padding: 4px 12px; font-size: 0.8rem; color: #f59e0b; background: transparent; border: 1px solid rgba(245, 158, 11, 0.4); border-radius: 6px; cursor: pointer; font-weight: 500;" onclick="handleWithdraw('${req.id}')">Hủy / Xóa</button>
                        <button class="icon-btn" title="Xóa hẳn Yêu cầu" style="color: var(--danger); font-size: 1.1rem; margin-left: 4px;" onclick="deleteRequest('${req.id}')"><i class="ph ph-trash"></i></button>
                    </div>
                ` : `<div style="display: flex; align-items: center; gap: 10px;">
                        <span style="color:var(--text-muted)">Đã xử lý</span>
                        <button class="icon-btn" title="Xóa hẳn Yêu cầu" style="color: var(--danger); font-size: 1.1rem;" onclick="deleteRequest('${req.id}')"><i class="ph ph-trash"></i></button>
                     </div>`}
            </td>
        </tr>
    `).join('');
}

async function handleWithdraw(requestId) {
    const reason = prompt("Lý do hủy yêu cầu này?");
    if (reason === null) return; // User cancelled
    
    try {
        const { error } = await db.rpc('sm_withdraw_supplier_request', {
            p_request_id: requestId,
        });

        if (error) throw error;
        
        showToast("Đã hủy yêu cầu thành công!", "success");
        fetchRequests();
        fetchSuppliers();
        fetchDashboardStats();
    } catch (err) {
        alert("Lỗi khi hủy yêu cầu: " + err.message);
    }
}

window.deleteRequest = async function(requestId) {
    if (!confirm('Bạn có chắc chắn muốn xóa hẳn Yêu cầu này khỏi hệ thống? Dữ liệu không thể khôi phục.')) return;
    
    try {
        const { error } = await db.from('sm_supplier_request').delete().eq('id', requestId);
        if (error) throw error;
        showToast('Đã xóa Yêu cầu.');
        fetchRequests();
    } catch (err) {
        alert("Lỗi khi xóa: " + err.message);
    }
}

async function handleDecision(requestId, decisionStr) {
    if (!confirm(`Bạn có chắc chắn muốn ${decisionStr} yêu cầu này?`)) return;
    
    try {
        // Lấy supplier_id từ request
        const { data: reqData, error: reqErr } = await db.from('sm_supplier_request').select('supplier_id').eq('id', requestId).single();
        if (reqErr) throw reqErr;

        if (!reqData.supplier_id) {
            throw new Error("Yêu cầu này không được gắn với Nhà cung cấp nào (supplier_id = null), dữ liệu rác không thể duyệt.");
        }

        // Lấy row_version từ vendor
        const { data: vendorData, error: venErr } = await db.from('vendor').select('row_version').eq('id', reqData.supplier_id).single();
        if (venErr) throw venErr;

        // Gọi RPC (Hàm Postgres)
        const { data, error } = await db.rpc('sm_decide_supplier_request', {
            p_request_id: requestId,
            p_decision: decisionStr,
            p_reason: decisionStr + ' via Portal',
            p_expected_row_version: vendorData.row_version
        });

        if (error) throw error;
        
        showToast("Xử lý thành công!", "success");
        fetchRequests();
        fetchSuppliers();
        fetchDashboardStats();
    } catch (err) {
        alert("Error: " + err.message);
    }
}

// ==========================================
// THÔNG BÁO (NOTIFICATION DROPDOWN)
// ==========================================

window.toggleNotificationDropdown = function() {
    const dropdown = document.getElementById('notificationDropdown');
    if (dropdown.style.display === 'none' || dropdown.style.display === '') {
        dropdown.style.display = 'block';
    } else {
        dropdown.style.display = 'none';
    }
}

// Close dropdown if clicked outside
document.addEventListener('click', function(event) {
    const dropdown = document.getElementById('notificationDropdown');
    const bellBtn = document.querySelector('.icon-btn[title="View Notifications"]');
    if (dropdown && dropdown.style.display === 'block') {
        if (!dropdown.contains(event.target) && !bellBtn.contains(event.target)) {
            dropdown.style.display = 'none';
        }
    }
});

// ==========================================
// SUPPLIER 360 VIEW
// ==========================================

window.openSupplier360 = async function(supplierId) {
    window.currentSupplierId = supplierId;
    try {
        // Fetch specific supplier details
        const { data, error } = await db
            .from('vendor')
            .select('*')
            .eq('id', supplierId)
            .single();

        if (error) throw error;

        // Switch View
        document.querySelectorAll('.view-section').forEach(v => {
            v.style.display = '';
            v.classList.remove('active');
        });
        document.getElementById('view-supplier-360').style.display = '';
        document.getElementById('view-supplier-360').classList.add('active');
        
        // Remove active class from sidebar navigation to show we are in a sub-view
        document.querySelectorAll('.sidebar .nav-item').forEach(n => n.classList.remove('active'));

        // Update Header
        document.getElementById('s360-name').textContent = data.vendor_name;
        document.getElementById('s360-id').textContent = 'Mã: ' + (data.erp_vendor_code || 'Chưa cấp');
        
        // Format status for display
        let displayStatus = data.lifecycle_status.replace('_', ' ');
        if (displayStatus === 'Onboarding') displayStatus = 'Đang tiếp nhận';
        else if (displayStatus === 'Candidate') displayStatus = 'Ứng viên';
        
        let badgesHtml = `<span class="status-badge status-${data.lifecycle_status.toLowerCase()}">${displayStatus}</span>`;
        if (data.tax_code) {
             badgesHtml += `<span class="status-badge" style="background: #fffbeb; color: #b45309; border: 1px solid #fde68a; margin-left: 8px;">Rủi ro trung bình</span>`;
        }
        document.getElementById('s360-badges').innerHTML = badgesHtml;

        // Update Summary Tab
        let sumDisplay = data.lifecycle_status.replace('_', ' ');
        if (sumDisplay === 'Onboarding') sumDisplay = 'Đang tiếp nhận';
        else if (sumDisplay === 'Candidate') sumDisplay = 'Ứng viên';
        document.getElementById('s360-sum-lifecycle').textContent = sumDisplay;

        // Update Organization Tab
        document.getElementById('s360-org-name').textContent = data.vendor_name;
        document.getElementById('s360-org-country').textContent = 'Global';
        document.getElementById('s360-org-tax').textContent = data.tax_code || 'N/A';
        document.getElementById('s360-org-email').textContent = data.data_owner_email || 'N/A';
        document.getElementById('s360-org-phone').textContent = 'N/A';
        document.getElementById('s360-org-address').textContent = 'N/A';
        
        // Fetch Scope
        const { data: scopeData, error: scopeErr } = await db.from('sm_supplier_scope')
            .select(`
                id,
                sm_department ( name ),
                sm_region ( name ),
                mdm_category ( name ),
                sm_supplier_qualification ( status, valid_to ),
                sm_supplier_classification ( tier_id )
            `)
            .eq('supplier_id', supplierId);
        
        const scopeBody = document.getElementById('s360-scope-body');
        if (!scopeData || scopeData.length === 0) {
            scopeBody.innerHTML = '<tr><td colspan="6" class="text-center" style="color:var(--text-muted)">Không có dữ liệu phạm vi</td></tr>';
        } else {
            scopeBody.innerHTML = scopeData.map(s => {
                // Get active qualification/classification (assuming the last one or only active one is returned)
                // Note: Supabase returns arrays for one-to-many relationships
                const qual = s.sm_supplier_qualification && s.sm_supplier_qualification.length > 0 ? s.sm_supplier_qualification[0] : null;
                const classif = s.sm_supplier_classification && s.sm_supplier_classification.length > 0 ? s.sm_supplier_classification[0] : null;
                
                const deptName = s.sm_department ? s.sm_department.name : 'N/A';
                const regionName = s.sm_region ? s.sm_region.name : 'N/A';
                const catName = s.mdm_category ? s.mdm_category.name : 'N/A';
                const qualStatus = qual ? qual.status : 'Not_Assessed';
                const classTier = classif ? classif.tier_id : 'N/A';
                const expiry = qual && qual.valid_to ? new Date(qual.valid_to).toLocaleDateString() : 'Không thời hạn';
                
                return `
                <tr>
                    <td>${deptName}</td>
                    <td>${regionName}</td>
                    <td>${catName}</td>
                    <td><span class="status-badge" style="background: #D1FAE5; color: #059669;">${qualStatus.replace('_', ' ')}</span></td>
                    <td><strong>${classTier}</strong></td>
                    <td>${expiry}</td>
                </tr>
            `}).join('');
        }

        // Fetch Risks
        const { data: riskData } = await db.from('sm_risk_issue').select('*').eq('supplier_id', supplierId).eq('status', 'Open');
        const riskUl = document.getElementById('s360-risk-issues');
        if (!riskData || riskData.length === 0) {
            riskUl.innerHTML = '<li>Không có rủi ro nào đang mở</li>';
        } else {
            riskUl.innerHTML = riskData.map(r => `
                <li style="margin-bottom: 8px;">${r.description || r.title} <span class="status-badge" style="background: ${r.severity === 'High' || r.severity === 'Critical' ? '#FEE2E2' : '#FEF3C7'}; color: ${r.severity === 'High' || r.severity === 'Critical' ? '#DC2626' : '#D97706'}; padding: 2px 6px; font-size: 0.7rem;">${r.severity}</span></li>
            `).join('');
        }

        // Fetch Documents
        const { data: docData } = await db.from('sm_supplier_document').select('*').eq('supplier_id', supplierId);
        const docBody = document.getElementById('s360-docs-body');
        if (!docData || docData.length === 0) {
            docBody.innerHTML = '<tr><td colspan="4" class="text-center" style="color:var(--text-muted)">Chưa có tài liệu</td></tr>';
        } else {
            docBody.innerHTML = docData.map(d => {
                const isExpired = d.valid_to && new Date(d.valid_to) < new Date();
                return `
                <tr>
                    <td>${d.document_type}</td>
                    <td>${d.valid_to ? new Date(d.valid_to).toLocaleDateString() : 'Không thời hạn'}</td>
                    <td><span class="status-badge" style="background: ${isExpired ? '#FEE2E2' : '#D1FAE5'}; color: ${isExpired ? '#DC2626' : '#059669'};">${isExpired ? 'Hết hạn' : 'Hợp lệ'}</span></td>
                    <td><button class="icon-btn"><i class="ph ph-download-simple"></i></button></td>
                </tr>`;
            }).join('');
        }

        // Fetch History
        const { data: historyData } = await db.from('sm_supplier_lifecycle_history').select('*').eq('supplier_id', supplierId).order('effective_date', { ascending: false });
        const histDiv = document.getElementById('s360-history-timeline');
        if (!historyData || historyData.length === 0) {
            histDiv.innerHTML = '<p style="color:var(--text-muted)">Chưa có nhật ký</p>';
        } else {
            histDiv.innerHTML = historyData.map(h => `
                <div style="position: relative; margin-bottom: 25px;">
                    <div style="position: absolute; left: -27px; top: 0; width: 12px; height: 12px; border-radius: 50%; background: var(--primary); border: 2px solid white;"></div>
                    <div style="font-size: 0.85rem; color: var(--text-muted); margin-bottom: 5px;">${new Date(h.effective_date).toLocaleString()} • <strong>System</strong></div>
                    <div style="background: rgba(255, 255, 255, 0.05); padding: 15px; border-radius: 8px; border: 1px solid var(--border-color);">
                        <strong>${(h.reason || 'Update').replace(/_/g, ' ')}</strong>
                        <p style="margin: 5px 0 0 0; font-size: 0.9rem; color: var(--text-muted);">Trạng thái: <span style="text-decoration: line-through;">${h.from_status || ''}</span> ➔ <span style="color: #10b981;">${h.to_status || ''}</span></p>
                    </div>
                </div>
            `).join('');
        }

        // Fetch Performance
        const { data: perfData } = await db.from('sm_performance_evaluation').select('*').eq('supplier_id', supplierId).order('created_at', { ascending: false });
        const perfBody = document.getElementById('s360-performance-body');
        if (!perfData || perfData.length === 0) {
            perfBody.innerHTML = '<tr><td colspan="4" class="text-center" style="color:var(--text-muted)">Chưa có đánh giá hiệu suất</td></tr>';
        } else {
            perfBody.innerHTML = perfData.map(p => `
                <tr>
                    <td><strong>${p.evaluation_period}</strong></td>
                    <td><span style="color: ${p.total_score >= 80 ? '#10b981' : p.total_score >= 50 ? '#f59e0b' : '#ef4444'}; font-weight: bold;">${p.total_score}</span> / 100</td>
                    <td>${p.grade}</td>
                    <td>${new Date(p.created_at).toLocaleDateString()}</td>
                </tr>
            `).join('');
        }

        if (typeof window.fetchQuestionnaires === 'function') {
            window.fetchQuestionnaires(supplierId);
        }

        if (typeof window.fetchIntegrationStatus === 'function') {
            window.fetchIntegrationStatus(supplierId);
        }

        if (typeof window.fetchAuditHistory === 'function') {
            window.fetchAuditHistory(supplierId);
        }

        // Ensure Summary Tab is active by default
        document.querySelector('.tab-nav .tab-item').click();

    } catch (err) {
        if(typeof showToast === 'function') {
            showToast('Lỗi khi tải chi tiết: ' + err.message);
        } else {
            alert('Lỗi khi tải chi tiết: ' + err.message);
        }
    }
}

window.switchTab = function(tabId, btnElement) {
    // Hide all tabs
    document.querySelectorAll('.tab-content').forEach(tab => {
        tab.classList.remove('active');
    });
    // Remove active state from all buttons
    document.querySelectorAll('.tab-item').forEach(btn => {
        btn.classList.remove('active');
    });

    // Show selected tab and activate button
    document.getElementById(tabId).classList.add('active');
    btnElement.classList.add('active');
}

// ==========================================
// RISK & PERFORMANCE VIEWS
// ==========================================

window.fetchRiskDashboard = async function() {
    try {
        const { data, error } = await db.from('sm_risk_issue').select(`*, vendor(vendor_name)`).eq('status', 'Open');
        if (error) throw error;
        
        // Update metric cards
        const highRiskCount = data ? data.filter(r => r.severity === 'High' || r.severity === 'Critical').length : 0;
        const openCount = data ? data.length : 0;
        const overdueCount = data ? data.filter(r => r.due_date && new Date(r.due_date) < new Date()).length : 0;
        
        document.getElementById('risk-high-count').textContent = highRiskCount;
        document.getElementById('risk-open-count').textContent = openCount;
        document.getElementById('risk-overdue-count').textContent = overdueCount;

        const riskBody = document.getElementById('risk-table-body');
        if (!data || data.length === 0) {
            riskBody.innerHTML = '<tr><td colspan="7" class="text-center" style="color:var(--text-muted)">Không có rủi ro nào đang mở</td></tr>';
            return;
        }

        riskBody.innerHTML = data.map(r => `
            <tr>
                <td>${r.supplier_id.substring(0,8)}</td>
                <td><strong>${r.vendor ? r.vendor.vendor_name : 'Unknown'}</strong></td>
                <td>${r.description || r.title}</td>
                <td><span class="status-badge" style="background: ${r.severity === 'High' || r.severity === 'Critical' ? '#FEE2E2' : '#FEF3C7'}; color: ${r.severity === 'High' || r.severity === 'Critical' ? '#B91C1C' : '#B45309'};">${r.severity}</span></td>
                <td>Risk Team</td>
                <td>${r.due_date ? new Date(r.due_date).toLocaleDateString() : 'N/A'}</td>
                <td><button class="secondary-btn" style="padding: 4px 8px; font-size: 0.8rem;" onclick="openSupplier360('${r.supplier_id}')">Xử lý</button></td>
            </tr>
        `).join('');
        
    } catch (err) {
        console.error('Error fetching risk:', err);
    }
}

window.fetchPerformance = async function() {
    try {
        const { data, error } = await db.from('sm_performance_evaluation').select(`*, vendor(vendor_name)`);
        if (error) throw error;
        
        const perfBody = document.getElementById('performance-table-body');
        if (!data || data.length === 0) {
            perfBody.innerHTML = '<tr><td colspan="7" class="text-center" style="color:var(--text-muted)">Không có dữ liệu đánh giá hiệu suất</td></tr>';
            return;
        }

        perfBody.innerHTML = data.map(p => `
            <tr>
                <td><strong>${p.vendor ? p.vendor.vendor_name : 'Unknown'}</strong></td>
                <td>Strategic</td>
                <td><span style="font-size: 1.1rem; font-weight: 700; color: ${p.total_score >= 80 ? '#10B981' : '#F59E0B'};">${p.total_score || 0}</span> / 100</td>
                <td>98%</td>
                <td>0.5%</td>
                <td><i class="ph ph-trend-up" style="color: #10B981; font-weight: bold;"></i></td>
                <td><button class="icon-btn" title="Xem chi tiết Scorecard" onclick="openSupplier360('${p.supplier_id}')"><i class="ph ph-chart-bar"></i></button></td>
            </tr>
        `).join('');
        
    } catch (err) {
        console.error('Error fetching performance:', err);
    }
}

// Attach these to sidebar clicks
document.addEventListener('DOMContentLoaded', () => {
    document.querySelector('a[data-target="view-risk"]').addEventListener('click', () => {
        fetchRiskDashboard();
    });
    document.querySelector('a[data-target="view-performance"]').addEventListener('click', () => {
        fetchPerformance();
    });
});

// ==========================================
// MODAL & FORM HANDLING (Web Input)
// ==========================================

// Risk Modal
window.openRiskModal = function() {
    const supplierId = document.getElementById('s360-id').textContent.replace('Mã: ', '').trim();
    // Use the actual internal supplier ID which was passed to openSupplier360. We can get it from the button or store it globally.
    // Wait, s360-id shows the ERP code, not the UUID. We should store the UUID.
    const internalId = window.currentSupplierId;
    if(!internalId) return alert("Không tìm thấy ID nhà cung cấp.");
    
    document.getElementById('riskSupplierId').value = internalId;
    document.getElementById('riskIssueForm').reset();
    document.getElementById('riskIssueModal').classList.add('active');
}
window.closeRiskModal = function() {
    document.getElementById('riskIssueModal').classList.remove('active');
}
window.submitRiskIssue = async function() {
    const supplierId = document.getElementById('riskSupplierId').value;
    const title = document.getElementById('riskTitle').value;
    const desc = document.getElementById('riskDesc').value;
    const severity = document.getElementById('riskSeverity').value;
    const dueDate = document.getElementById('riskDueDate').value;

    if (!title || !severity || !dueDate) return alert("Vui lòng điền đầy đủ thông tin.");

    try {
        const { error } = await db.rpc('sm_create_risk_issue', {
            p_supplier_id: supplierId,
            p_title: title,
            p_description: desc,
            p_severity: severity,
            p_due_date: new Date(dueDate).toISOString()
        });
        if (error) throw error;
        
        showToast('Đã ghi nhận rủi ro thành công!');
        closeRiskModal();
        openSupplier360(supplierId); // Refresh data
        fetchRiskDashboard(); // Refresh dashboard if needed
    } catch (err) {
        alert("Lỗi khi thêm rủi ro: " + err.message);
    }
}

// Edit Supplier Modal Logic
window.openEditSupplierModal = async function(id) {
    try {
        const { data: supplier, error } = await db
            .from('vendor')
            .select('*')
            .eq('id', id)
            .single();
            
        if (error) throw error;
        if (!supplier) return;
        
        document.getElementById('editSupplierId').value = id;
        document.getElementById('editSupplierName').value = supplier.vendor_name;
        document.getElementById('editTaxCode').value = supplier.tax_code || '';
        
        // Parse extra payload for website if exists
        let website = '';
        if (supplier.proposed_payload && supplier.proposed_payload.website) {
            website = supplier.proposed_payload.website;
        }
        document.getElementById('editWebsite').value = website;
        
        document.getElementById('editSupplierModal').classList.add('active');
    } catch (err) {
        alert("Lỗi khi tải thông tin: " + err.message);
    }
}

window.closeEditSupplierModal = function() {
    document.getElementById('editSupplierModal').classList.remove('active');
}

window.submitEditSupplier = async function() {
    const id = document.getElementById('editSupplierId').value;
    const name = document.getElementById('editSupplierName').value;
    const taxCode = document.getElementById('editTaxCode').value;
    const website = document.getElementById('editWebsite').value;

    if (!name) {
        alert("Vui lòng nhập Tên pháp lý!");
        return;
    }

    try {
        const { data, error } = await db.from('vendor').update({
            vendor_name: name,
            tax_code: taxCode || null,
            proposed_payload: { website: website }
        }).eq('id', id);

        if (error) throw error;
        
        showToast('Cập nhật thành công!');
        closeEditSupplierModal();
        fetchSuppliers(); // Refresh the table
    } catch (err) {
        alert("Lỗi khi cập nhật: " + err.message);
    }
}

// Document Modal
window.openDocumentModal = function() {
    const internalId = window.currentSupplierId;
    if(!internalId) return alert("Không tìm thấy ID nhà cung cấp.");
    document.getElementById('docSupplierId').value = internalId;
    document.getElementById('documentForm').reset();
    document.getElementById('documentModal').classList.add('active');
}
window.closeDocumentModal = function() {
    document.getElementById('documentModal').classList.remove('active');
}
window.submitDocument = async function() {
    const supplierId = document.getElementById('docSupplierId').value;
    const docType = document.getElementById('docType').value;
    const validTo = document.getElementById('docValidTo').value;
    const fileInput = document.getElementById('fakeFileInput');

    if (!docType) return alert("Vui lòng nhập loại tài liệu.");
    if (fileInput.files.length === 0) return alert("Vui lòng chọn 1 file để tải lên.");

    const file = fileInput.files[0];
    const fileExt = file.name.split('.').pop();
    const fileName = `${supplierId}/${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;

    try {
        // 1. Upload to Supabase Storage
        const { data: uploadData, error: uploadError } = await db.storage
            .from('supplier_documents')
            .upload(fileName, file);

        if (uploadError) {
            console.error(uploadError);
            throw new Error("Lỗi tải lên file: " + uploadError.message);
        }

        // Lấy URL công khai
        const { data: publicUrlData } = db.storage.from('supplier_documents').getPublicUrl(fileName);
        const fileUrl = publicUrlData.publicUrl;

        // 2. Lưu vào CSDL với ghi chú là URL
        const { error } = await db.rpc('sm_add_document', {
            p_supplier_id: supplierId,
            p_document_type: docType + " (" + fileUrl + ")", // Nối URL vào type tạm thời để demo (hoặc bạn có thể tự thêm cột url vào bảng sm_supplier_document)
            p_valid_to: validTo ? new Date(validTo).toISOString() : null
        });
        if (error) throw error;
        
        showToast('Đã tải lên tài liệu thành công!');
        closeDocumentModal();
        openSupplier360(supplierId); // Refresh data
    } catch (err) {
        alert("Lỗi khi tải tài liệu: " + err.message);
    }
}

// Performance Modal
window.openPerformanceModal = function() {
    const internalId = window.currentSupplierId;
    if(!internalId) return alert("Không tìm thấy ID nhà cung cấp.");
    document.getElementById('perfSupplierId').value = internalId;
    document.getElementById('performanceForm').reset();
    document.getElementById('performanceModal').classList.add('active');
}
window.closePerformanceModal = function() {
    document.getElementById('performanceModal').classList.remove('active');
}
window.submitPerformance = async function() {
    const supplierId = document.getElementById('perfSupplierId').value;
    const period = document.getElementById('perfPeriod').value;
    const score = document.getElementById('perfScore').value;
    const grade = document.getElementById('perfGrade').value;

    if (!period || !score || !grade) return alert("Vui lòng điền đầy đủ thông tin đánh giá.");

    try {
        const { error } = await db.rpc('sm_create_performance_evaluation', {
            p_supplier_id: supplierId,
            p_evaluation_period: period,
            p_total_score: parseFloat(score),
            p_grade: grade
        });
        if (error) throw error;
        
        showToast('Đã đánh giá hiệu suất thành công!');
        closePerformanceModal();
        openSupplier360(supplierId); // Refresh data
        fetchPerformance(); // Refresh dashboard
    } catch (err) {
        alert("Lỗi khi lưu đánh giá: " + err.message);
    }
}

// ==========================================
// SCOPE & ELIGIBILITY MODALS
// ==========================================

window.openScopeModal = async function() {
    const internalId = window.currentSupplierId;
    if(!internalId) return alert("Không tìm thấy ID nhà cung cấp.");
    document.getElementById('scopeSupplierId').value = internalId;
    
    try {
        // Load Departments
        const { data: depts } = await db.from('sm_department').select('id, name').eq('is_active', true);
        const deptSelect = document.getElementById('scopeDept');
        deptSelect.innerHTML = depts.map(d => `<option value="${d.id}">${d.name}</option>`).join('');
        
        // Load Regions
        const { data: regions } = await db.from('sm_region').select('id, name').eq('is_active', true);
        const regionSelect = document.getElementById('scopeRegion');
        regionSelect.innerHTML = regions.map(r => `<option value="${r.id}">${r.name}</option>`).join('');
        
        // Load Categories
        const { data: cats } = await db.from('mdm_category').select('id, name').eq('is_active', true);
        const catSelect = document.getElementById('scopeCategory');
        catSelect.innerHTML = cats.map(c => `<option value="${c.id}">${c.name}</option>`).join('');
        
        document.getElementById('scopeModal').classList.add('active');
    } catch (err) {
        alert("Lỗi khi load dữ liệu phạm vi: " + err.message);
    }
}
window.closeScopeModal = function() {
    document.getElementById('scopeModal').classList.remove('active');
}
window.submitScope = async function() {
    const payload = {
        p_supplier_id: document.getElementById('scopeSupplierId').value,
        p_department_id: document.getElementById('scopeDept').value,
        p_region_id: document.getElementById('scopeRegion').value,
        p_category_id: document.getElementById('scopeCategory').value,
        p_qualification_status: document.getElementById('scopeQualStatus').value,
        p_classification_tier: document.getElementById('scopeClassTier').value
    };
    
    try {
        const { error } = await db.rpc('sm_add_supplier_scope', payload);
        if (error) throw error;
        
        showToast('Thêm phạm vi thành công!');
        closeScopeModal();
        openSupplier360(payload.p_supplier_id); // Refresh data
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

window.checkEligibility = async function() {
    const internalId = window.currentSupplierId;
    if(!internalId) return alert("Không tìm thấy ID nhà cung cấp.");
    
    try {
        const { data, error } = await db.rpc('sm_check_supplier_eligibility', {
            p_supplier_id: internalId,
            p_scope_id: null
        });
        
        if (error) throw error;
        
        const body = document.getElementById('eligibilityBody');
        if (data.eligible) {
            body.innerHTML = `
                <div style="text-align: center; padding: 20px;">
                    <i class="ph-fill ph-check-circle" style="font-size: 4rem; color: #10b981;"></i>
                    <h3 style="color: #10b981; margin: 15px 0;">ĐƯỢC PHÉP GIAO DỊCH</h3>
                    <p style="color: var(--text-muted);">Nhà cung cấp đáp ứng đủ điều kiện trong phạm vi Global (ALL).</p>
                </div>
            `;
        } else {
            const reasonsHtml = data.blocking_reasons && data.blocking_reasons.length > 0 
                ? data.blocking_reasons.map(r => `<li><b>${r.type || 'Lỗi'}:</b> ${r.message || JSON.stringify(r)}</li>`).join('') 
                : '<li>Không xác định (Unknown Block)</li>';
                
            body.innerHTML = `
                <div style="text-align: center; padding: 20px;">
                    <i class="ph-fill ph-warning-circle" style="font-size: 4rem; color: #ef4444;"></i>
                    <h3 style="color: #ef4444; margin: 15px 0;">BỊ CHẶN (BLOCKED)</h3>
                    <p style="color: var(--text-muted);">Không đủ điều kiện giao dịch.</p>
                    <div style="background: rgba(239, 68, 68, 0.1); border-left: 4px solid #ef4444; padding: 10px; margin-top: 15px; text-align: left;">
                        <strong style="color: #ef4444;">Lý do chặn:</strong>
                        <ul style="margin: 5px 0 0 20px; color: #ef4444;">
                            ${reasonsHtml}
                        </ul>
                    </div>
                </div>
            `;
        }
        document.getElementById('eligibilityModal').classList.add('active');
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}
window.closeEligibilityModal = function() {
    document.getElementById('eligibilityModal').classList.remove('active');
}

// ============================================================
// WORK QUEUE
// ============================================================
async function fetchWorkQueue() {
    try {
        const { data, error } = await db.rpc('sm_get_work_queue');
        if (error) throw error;
        renderWorkQueue(data || []);
    } catch (err) {
        console.error('Work queue error:', err.message);
    }
}

function renderWorkQueue(items) {
    const container = document.getElementById('workQueueList');
    if (!container) return;
    if (items.length === 0) {
        container.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px;">Không có việc cần xử lý. Xuất sắc!</p>';
        return;
    }
    const iconMap = {
        'PENDING_REQUEST': { icon: 'ph-file-text', color: '#3b82f6' },
        'EXPIRING_DOCUMENT': { icon: 'ph-warning', color: '#f59e0b' },
        'OVERDUE_RISK': { icon: 'ph-shield-warning', color: '#ef4444' }
    };
    container.innerHTML = items.map(item => {
        const cfg = iconMap[item.item_type] || { icon: 'ph-circle', color: '#64748b' };
        const due = item.due_date ? new Date(item.due_date).toLocaleDateString('vi-VN') : 'N/A';
        return `
        <div style="display:flex; align-items:center; gap:12px; padding:12px 0; border-bottom:1px solid rgba(255,255,255,0.05);">
            <div style="background:${cfg.color}22; padding:8px; border-radius:8px; color:${cfg.color}; font-size:1.2rem;">
                <i class="ph ${cfg.icon}"></i>
            </div>
            <div style="flex:1;">
                <div style="font-size:0.875rem; font-weight:600;">${item.title}</div>
                <div style="font-size:0.75rem; color:var(--text-muted);">${item.supplier_name} · Hạn: ${due}</div>
            </div>
            <span style="font-size:0.7rem; background:${cfg.color}22; color:${cfg.color}; padding:2px 8px; border-radius:999px;">${item.severity}</span>
        </div>`;
    }).join('');
    // Update badge
    const badge = document.getElementById('workQueueBadge');
    if (badge) { badge.textContent = items.length; badge.style.display = items.length > 0 ? 'inline-block' : 'none'; }
}

// ============================================================
// UPDATE PROFILE — Maker-Checker
// ============================================================
window.openUpdateProfileModal = function(supplierId) {
    document.getElementById('updateProfileSupplierId').value = supplierId;
    document.getElementById('updateProfileModal').classList.add('active');
}
window.closeUpdateProfileModal = function() {
    document.getElementById('updateProfileModal').classList.remove('active');
    document.getElementById('updateProfileForm').reset();
}
window.submitUpdateProfile = async function() {
    const supplierId = document.getElementById('updateProfileSupplierId').value;
    const newName = document.getElementById('updateProfileName').value;
    const newTaxCode = document.getElementById('updateProfileTaxCode').value;
    const newWebsite = document.getElementById('updateProfileWebsite').value;
    const reason = document.getElementById('updateProfileReason').value;

    if (!reason) { alert('Vui lòng nhập lý do thay đổi!'); return; }

    const payload = { vendor_name: newName, tax_code: newTaxCode, website: newWebsite, change_reason: reason };
    try {
        const { data, error } = await db.rpc('sm_submit_profile_change', {
            p_supplier_id: supplierId,
            p_proposed_payload: payload
        });
        if (error) throw error;
        showToast('Yêu cầu sửa hồ sơ đã được gửi đi chờ duyệt!');
        closeUpdateProfileModal();
        fetchRequests();
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

// ============================================================
// CHANGE BANK ACCOUNT — Maker-Checker
// ============================================================
window.openChangeBankModal = function(supplierId) {
    document.getElementById('changeBankSupplierId').value = supplierId;
    document.getElementById('changeBankModal').classList.add('active');
}
window.closeChangeBankModal = function() {
    document.getElementById('changeBankModal').classList.remove('active');
    document.getElementById('changeBankForm').reset();
}
window.submitBankChange = async function() {
    const supplierId = document.getElementById('changeBankSupplierId').value;
    const bankName = document.getElementById('bankName').value;
    const accountNumber = document.getElementById('bankAccountNumber').value;
    const accountName = document.getElementById('bankAccountName').value;
    const branch = document.getElementById('bankBranch').value;
    const reason = document.getElementById('bankChangeReason').value;

    if (!bankName || !accountNumber || !accountName || !reason) {
        alert('Vui lòng nhập đầy đủ thông tin ngân hàng và lý do!');
        return;
    }
    const payload = { bank_name: bankName, account_number: accountNumber, account_name: accountName, branch, change_reason: reason };
    try {
        const { data, error } = await db.rpc('sm_submit_bank_change', {
            p_supplier_id: supplierId,
            p_proposed_payload: payload
        });
        if (error) throw error;
        showToast('Yêu cầu thay đổi tài khoản ngân hàng đã được gửi chờ duyệt!');
        closeChangeBankModal();
        fetchRequests();
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

// ============================================================
// RISK DECISION — Acceptable / Conditional / Blocked
// ============================================================
window.openRiskDecisionModal = function(supplierId) {
    document.getElementById('riskDecisionSupplierId').value = supplierId;
    document.getElementById('riskDecisionModal').classList.add('active');
}
window.closeRiskDecisionModal = function() {
    document.getElementById('riskDecisionModal').classList.remove('active');
}
window.submitRiskDecision = async function() {
    const supplierId = document.getElementById('riskDecisionSupplierId').value;
    const decision = document.getElementById('riskDecisionType').value;
    const rationale = document.getElementById('riskDecisionRationale').value;
    const validUntil = document.getElementById('riskDecisionValidUntil').value;

    if (!decision || !rationale) { alert('Vui lòng chọn quyết định và nhập lý do!'); return; }

    try {
        const { error } = await db.rpc('sm_record_risk_decision', {
            p_supplier_id: supplierId,
            p_scope_id: null,
            p_decision: decision,
            p_rationale: rationale,
            p_valid_until: validUntil || null
        });
        if (error) throw error;
        showToast('Đã ghi nhận quyết định rủi ro: ' + decision);
        closeRiskDecisionModal();
        openSupplier360(supplierId);
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

// ============================================================
// RISK ACTION / CAPA
// ============================================================
window.openRiskActionModal = function(issueId) {
    document.getElementById('riskActionIssueId').value = issueId;
    document.getElementById('riskActionModal').classList.add('active');
}
window.closeRiskActionModal = function() {
    document.getElementById('riskActionModal').classList.remove('active');
}
window.submitRiskAction = async function() {
    const issueId = document.getElementById('riskActionIssueId').value;
    const description = document.getElementById('riskActionDescription').value;
    const dueDate = document.getElementById('riskActionDueDate').value;
    const evidence = document.getElementById('riskActionEvidence').value;

    if (!description) { alert('Vui lòng nhập mô tả hành động!'); return; }

    try {
        const { error } = await db.rpc('sm_update_risk_action', {
            p_issue_id: issueId,
            p_action_description: description,
            p_status: 'Open',
            p_due_date: dueDate || null,
            p_completion_evidence: evidence || null
        });
        if (error) throw error;
        showToast('Đã tạo kế hoạch xử lý (CAPA) thành công!');
        closeRiskActionModal();
        if (window.currentSupplierId) openSupplier360(window.currentSupplierId);
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

// ============================================================
// QUESTIONNAIRE TAB
// ============================================================
async function fetchQuestionnaires(supplierId) {
    const container = document.getElementById('questionnaireList');
    if (!container) return;
    try {
        const { data, error } = await db
            .from('sm_questionnaire_instance')
            .select('*, sm_questionnaire_template(title, version)')
            .eq('supplier_id', supplierId)
            .order('created_at', { ascending: false });
        if (error) throw error;
        if (!data || data.length === 0) {
            container.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:40px 0;">Chưa có bộ câu hỏi nào được giao.</p>';
            return;
        }
        const statusColor = { Assigned: '#3b82f6', In_Progress: '#f59e0b', Submitted: '#10b981', Approved: '#22c55e', Rejected: '#ef4444', Under_Review: '#8b5cf6' };
        container.innerHTML = data.map(q => {
            const sc = statusColor[q.status] || '#64748b';
            const tmpl = q.sm_questionnaire_template;
            return `
            <div class="glass-panel" style="padding:16px; margin-bottom:12px; display:flex; align-items:center; justify-content:space-between;">
                <div>
                    <div style="font-weight:600;">${tmpl ? tmpl.title : 'N/A'} <span style="font-size:0.75rem; color:var(--text-muted);">v${tmpl ? tmpl.version : ''}</span></div>
                    <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Hạn: ${q.due_date ? new Date(q.due_date).toLocaleDateString('vi-VN') : 'Không giới hạn'}</div>
                </div>
                <span style="background:${sc}22; color:${sc}; padding:4px 12px; border-radius:999px; font-size:0.8rem; font-weight:600;">${q.status.replace('_', ' ')}</span>
            </div>`;
        }).join('');
    } catch (err) {
        container.innerHTML = '<p style="color:var(--danger);">Lỗi tải questionnaire: ' + err.message + '</p>';
    }
}

// ============================================================
// INTEGRATION TAB — Crosswalk + Outbox
// ============================================================
async function fetchIntegrationStatus(supplierId) {
    const crosswalkEl = document.getElementById('crosswalkList');
    const outboxEl = document.getElementById('outboxList');
    if (!crosswalkEl || !outboxEl) return;

    try {
        const { data: crosswalks } = await db.from('sm_supplier_crosswalk').select('*').eq('supplier_id', supplierId);
        if (!crosswalks || crosswalks.length === 0) {
            crosswalkEl.innerHTML = '<p style="color:var(--text-muted);">Chưa có mapping ERP nào.</p>';
        } else {
            crosswalkEl.innerHTML = crosswalks.map(cw => `
                <div style="display:flex; justify-content:space-between; padding:10px; background:rgba(255,255,255,0.03); border-radius:8px; margin-bottom:8px;">
                    <span style="font-weight:600;">${cw.external_system}</span>
                    <span style="font-family:monospace; color:var(--primary);">${cw.external_id}</span>
                    <span style="font-size:0.75rem; color:var(--text-muted);">${cw.last_synced_at ? new Date(cw.last_synced_at).toLocaleString('vi-VN') : 'N/A'}</span>
                </div>`).join('');
        }

        const { data: outboxItems } = await db.from('sm_supplier_outbox').select('*').eq('supplier_id', supplierId).order('created_at', { ascending: false }).limit(10);
        if (!outboxItems || outboxItems.length === 0) {
            outboxEl.innerHTML = '<p style="color:var(--text-muted);">Không có sự kiện đồng bộ nào.</p>';
        } else {
            const statusColor = { Pending: '#3b82f6', Sent: '#10b981', Failed: '#ef4444', Skipped: '#64748b' };
            outboxEl.innerHTML = outboxItems.map(ev => {
                const sc = statusColor[ev.status] || '#64748b';
                return `
                <div style="display:flex; align-items:center; justify-content:space-between; padding:10px; background:rgba(255,255,255,0.03); border-radius:8px; margin-bottom:8px;">
                    <div>
                        <span style="font-weight:600;">${ev.event_type || 'SYNC'}</span>
                        <span style="font-size:0.75rem; color:var(--text-muted); margin-left:8px;">${new Date(ev.created_at).toLocaleString('vi-VN')}</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span style="background:${sc}22; color:${sc}; padding:2px 10px; border-radius:999px; font-size:0.75rem;">${ev.status}</span>
                        ${ev.status === 'Failed' ? `<button onclick="retrySyncEvent('${ev.id}')" style="background:#ef444422; color:#ef4444; border:1px solid #ef444440; padding:4px 10px; border-radius:6px; cursor:pointer; font-size:0.75rem;"><i class="ph ph-arrow-clockwise"></i> Retry</button>` : ''}
                    </div>
                </div>`;
            }).join('');
        }
    } catch (err) {
        crosswalkEl.innerHTML = '<p style="color:var(--danger);">Lỗi: ' + err.message + '</p>';
    }
}

window.retrySyncEvent = async function(outboxId) {
    try {
        const { error } = await db.rpc('sm_retry_supplier_sync_event', { p_outbox_id: outboxId });
        if (error) throw error;
        showToast('Đã đặt lại trạng thái sự kiện để thử lại!');
        if (window.currentSupplierId) fetchIntegrationStatus(window.currentSupplierId);
    } catch (err) {
        alert('Lỗi retry: ' + err.message);
    }
}

// ============================================================
// EXPIRING QUALIFICATIONS WARNING
// ============================================================
async function fetchExpiringQualifications() {
    try {
        const thirtyDaysFromNow = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
        const { data, error } = await db
            .from('sm_supplier_qualification')
            .select('*, sm_supplier_scope(supplier_id, vendor(vendor_name))')
            .eq('status', 'Qualified')
            .lte('valid_to', thirtyDaysFromNow)
            .gte('valid_to', new Date().toISOString());
        if (error || !data || data.length === 0) return;

        const expiringEl = document.getElementById('expiringQualificationsAlert');
        if (expiringEl) {
            expiringEl.style.display = 'block';
            expiringEl.innerHTML = `
            <div style="background:rgba(245,158,11,0.1); border:1px solid rgba(245,158,11,0.3); border-radius:10px; padding:12px 16px; margin-bottom:16px; display:flex; align-items:center; gap:12px;">
                <i class="ph ph-warning" style="color:#f59e0b; font-size:1.5rem;"></i>
                <div>
                    <strong style="color:#f59e0b;">Cảnh báo:</strong> Có <strong>${data.length}</strong> qualification sắp hết hạn trong 30 ngày.
                    <span style="font-size:0.8rem; color:var(--text-muted); margin-left:8px;">${data.map(q => q.sm_supplier_scope?.vendor?.vendor_name || 'N/A').join(', ')}</span>
                </div>
            </div>`;
        }
    } catch (err) {
        console.warn('Expiring qualifications check failed:', err.message);
    }
}

// ============================================================
// SETTINGS — Supplier Portal Access Management
// ============================================================
async function fetchSupplierAccessList() {
    const container = document.getElementById('supplierAccessList');
    if (!container) return;
    try {
        const { data, error } = await db
            .from('app_supplier_users')
            .select('user_id, supplier_id, created_at, vendor(vendor_name)');
        if (error) throw error;
        if (!data || data.length === 0) {
            container.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px;">Chưa có Supplier User nào được cấp quyền.</p>';
            return;
        }
        container.innerHTML = `
        <table class="modern-table">
            <thead><tr>
                <th>User ID</th><th>Nhà cung cấp</th><th>Ngày cấp</th><th>Thao tác</th>
            </tr></thead>
            <tbody>${data.map(r => `
                <tr>
                    <td style="font-family:monospace; font-size:0.75rem;">${r.user_id.substring(0,8)}...</td>
                    <td>${r.vendor?.vendor_name || r.supplier_id}</td>
                    <td>${new Date(r.created_at).toLocaleDateString('vi-VN')}</td>
                    <td>
                        <button onclick="revokeSupplierAccess('${r.user_id}','${r.supplier_id}')" 
                            style="background:rgba(239,68,68,0.15); color:#ef4444; border:1px solid rgba(239,68,68,0.3); padding:4px 10px; border-radius:6px; cursor:pointer; font-size:0.75rem;">
                            <i class="ph ph-trash"></i> Thu hồi
                        </button>
                    </td>
                </tr>`).join('')}
            </tbody>
        </table>`;
    } catch (err) {
        container.innerHTML = '<p style="color:var(--danger);">Lỗi: ' + err.message + '</p>';
    }
}

async function fetchUserRoles() {
    const container = document.getElementById('userRolesList');
    if (!container) return;
    try {
        const { data, error } = await db
            .from('app_user_roles')
            .select('user_id, role, created_at')
            .order('created_at', { ascending: false });
        if (error) throw error;
        if (!data || data.length === 0) {
            container.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px;">Không có dữ liệu.</p>';
            return;
        }
        const roleColors = {
            Admin: '#ef4444', Approver: '#f59e0b', Supplier_Manager: '#10b981',
            Risk_Reviewer: '#8b5cf6', Buyer: '#3b82f6', Viewer: '#64748b',
            Accounting: '#06b6d4', Supplier_User: '#ec4899'
        };
        container.innerHTML = `
        <table class="modern-table">
            <thead><tr><th>User ID</th><th>Role</th><th>Ngày gán</th></tr></thead>
            <tbody>${data.map(r => {
                const color = roleColors[r.role] || '#64748b';
                return `<tr>
                    <td style="font-family:monospace; font-size:0.75rem;">${r.user_id.substring(0,8)}...</td>
                    <td><span style="background:${color}22; color:${color}; padding:3px 10px; border-radius:999px; font-size:0.75rem; font-weight:600;">${r.role}</span></td>
                    <td>${new Date(r.created_at).toLocaleDateString('vi-VN')}</td>
                </tr>`;
            }).join('')}
            </tbody>
        </table>`;
    } catch (err) {
        container.innerHTML = '<p style="color:var(--danger);">Lỗi: ' + err.message + '</p>';
    }
}

window.openGrantSupplierAccessModal = function() {
    document.getElementById('grantAccessModal').classList.add('active');
}
window.closeGrantAccessModal = function() {
    document.getElementById('grantAccessModal').classList.remove('active');
    document.getElementById('grantAccessForm').reset();
}
window.submitGrantAccess = async function() {
    const targetUserId = document.getElementById('grantAccessUserId').value.trim();
    const supplierId = document.getElementById('grantAccessSupplierId').value;
    if (!targetUserId || !supplierId) { alert('Vui lòng nhập đầy đủ thông tin!'); return; }
    try {
        const { error } = await db.rpc('sm_grant_supplier_access', {
            p_target_user_id: targetUserId,
            p_supplier_id: supplierId
        });
        if (error) throw error;
        showToast('Đã cấp quyền Supplier Portal thành công!');
        closeGrantAccessModal();
        fetchSupplierAccessList();
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}
window.revokeSupplierAccess = async function(userId, supplierId) {
    if (!confirm('Xác nhận thu hồi quyền Supplier Portal của user này?')) return;
    try {
        const { error } = await db.rpc('sm_revoke_supplier_access', {
            p_target_user_id: userId,
            p_supplier_id: supplierId
        });
        if (error) throw error;
        showToast('Đã thu hồi quyền thành công!');
        fetchSupplierAccessList();
    } catch (err) {
        alert('Lỗi: ' + err.message);
    }
}

// Load settings data khi click vao tab Settings
document.addEventListener('DOMContentLoaded', () => {
    const settingsNav = document.querySelector('[data-target="view-settings"]');
    if (settingsNav) {
        settingsNav.addEventListener('click', () => {
            fetchSupplierAccessList();
            fetchUserRoles();
        });
    }
});

// ============================================================
// PHASE 1+2: Qualification & Classification Maker-Checker
// ============================================================

// --- Qualification Request Modal ---
window.openQualRequestModal = async function() {
    const supplierId = window.currentSupplierId;
    if (!supplierId) { alert('Chon NCC truoc!'); return; }
    document.getElementById('qualRequestSupplierId').value = supplierId;

    // Load scopes for this supplier
    const { data } = await db.from('sm_supplier_scope')
        .select('id, department_id, region_id, category_id')
        .eq('supplier_id', supplierId);
    const sel = document.getElementById('qualRequestScopeId');
    sel.innerHTML = '<option value="">-- Chon scope --</option>' +
        (data || []).map(s => `<option value="${s.id}">${s.department_id} x ${s.region_id} x ${s.category_id}</option>`).join('');

    // Default valid_from to today
    document.getElementById('qualRequestValidFrom').value = new Date().toISOString().split('T')[0];
    document.getElementById('qualRequestModal').classList.add('active');
}
window.closeQualRequestModal = function() {
    document.getElementById('qualRequestModal').classList.remove('active');
}
window.submitQualRequest = async function() {
    const supplierId = document.getElementById('qualRequestSupplierId').value;
    const scopeId    = document.getElementById('qualRequestScopeId').value;
    const newStatus  = document.getElementById('qualRequestNewStatus').value;
    const validFrom  = document.getElementById('qualRequestValidFrom').value;
    const validTo    = document.getElementById('qualRequestValidTo').value || null;
    const conditions = document.getElementById('qualRequestConditions').value || null;
    const rationale  = document.getElementById('qualRequestRationale').value;

    if (!scopeId || !newStatus || !validFrom || !rationale) {
        alert('Vui long dien day du cac truong bat buoc!');
        return;
    }
    try {
        const { data, error } = await db.rpc('sm_submit_qualification_request', {
            p_supplier_id: supplierId,
            p_scope_id: scopeId,
            p_new_status: newStatus,
            p_valid_from: validFrom,
            p_valid_to: validTo,
            p_conditions: conditions,
            p_rationale: rationale
        });
        if (error) throw error;
        showToast('Yeu cau thay doi Qualification da duoc gui! Ma: ' + (data || ''));
        closeQualRequestModal();
        fetchPendingScopeRequests(supplierId);
    } catch (err) {
        alert('Loi: ' + err.message);
    }
}

// --- Classification Request Modal ---
window.openClassRequestModal = async function() {
    const supplierId = window.currentSupplierId;
    if (!supplierId) { alert('Chon NCC truoc!'); return; }
    document.getElementById('classRequestSupplierId').value = supplierId;

    const { data } = await db.from('sm_supplier_scope')
        .select('id, department_id, region_id, category_id')
        .eq('supplier_id', supplierId);
    const sel = document.getElementById('classRequestScopeId');
    sel.innerHTML = '<option value="">-- Chon scope --</option>' +
        (data || []).map(s => `<option value="${s.id}">${s.department_id} x ${s.region_id} x ${s.category_id}</option>`).join('');

    document.getElementById('classRequestValidFrom').value = new Date().toISOString().split('T')[0];
    document.getElementById('classRequestModal').classList.add('active');
}
window.closeClassRequestModal = function() {
    document.getElementById('classRequestModal').classList.remove('active');
}
window.submitClassRequest = async function() {
    const supplierId = document.getElementById('classRequestSupplierId').value;
    const scopeId    = document.getElementById('classRequestScopeId').value;
    const newTier    = document.getElementById('classRequestNewTier').value;
    const validFrom  = document.getElementById('classRequestValidFrom').value;
    const validTo    = document.getElementById('classRequestValidTo').value || null;
    const rationale  = document.getElementById('classRequestRationale').value;

    if (!scopeId || !newTier || !rationale) {
        alert('Vui long dien day du cac truong bat buoc!');
        return;
    }
    try {
        const { data, error } = await db.rpc('sm_submit_classification_request', {
            p_supplier_id: supplierId,
            p_scope_id: scopeId,
            p_new_tier: newTier,
            p_rationale: rationale,
            p_valid_from: validFrom || null,
            p_valid_to: validTo
        });
        if (error) throw error;
        showToast('Yeu cau thay doi Classification da duoc gui! Ma: ' + (data || ''));
        closeClassRequestModal();
        fetchPendingScopeRequests(supplierId);
    } catch (err) {
        alert('Loi: ' + err.message);
    }
}

// --- Pending Scope Requests (hien thi trong tab Qualification) ---
async function fetchPendingScopeRequests(supplierId) {
    const container = document.getElementById('pendingScopeRequests');
    if (!container || !supplierId) return;
    try {
        const { data, error } = await db
            .from('sm_supplier_request')
            .select('id, request_no, request_type, status, proposed_payload, created_at')
            .eq('supplier_id', supplierId)
            .in('request_type', ['Set_Qualification', 'Set_Classification'])
            .in('status', ['Submitted', 'In_Review'])
            .order('created_at', { ascending: false });

        if (error) throw error;
        if (!data || data.length === 0) {
            container.innerHTML = '<p style="color:var(--text-muted); font-size:0.85rem;">Khong co yeu cau nao dang cho duyet.</p>';
            return;
        }
        const typeLabel = { Set_Qualification: 'Qualification', Set_Classification: 'Classification' };
        const statusColor = { Submitted: '#f59e0b', In_Review: '#3b82f6' };
        container.innerHTML = data.map(r => `
            <div style="background:var(--card-bg); border:1px solid var(--border-color); border-radius:8px; padding:12px 16px; margin-bottom:8px; display:flex; justify-content:space-between; align-items:center;">
                <div>
                    <span style="font-weight:600; font-size:0.85rem;">${r.request_no}</span>
                    <span style="background:rgba(59,130,246,0.15); color:#3b82f6; padding:2px 8px; border-radius:999px; font-size:0.75rem; margin-left:8px;">${typeLabel[r.request_type] || r.request_type}</span>
                    <span style="background:${statusColor[r.status] || '#64748b'}22; color:${statusColor[r.status] || '#64748b'}; padding:2px 8px; border-radius:999px; font-size:0.75rem; margin-left:4px;">${r.status}</span>
                    <div style="font-size:0.75rem; color:var(--text-muted); margin-top:4px;">
                        ${r.proposed_payload?.new_status || r.proposed_payload?.new_tier || ''} — ${new Date(r.created_at).toLocaleDateString('vi-VN')}
                    </div>
                </div>
                <button onclick="openDecideRequestModal('${r.id}')"
                    style="background:rgba(245,158,11,0.15); color:#f59e0b; border:1px solid rgba(245,158,11,0.3); padding:5px 12px; border-radius:6px; cursor:pointer; font-size:0.8rem;">
                    <i class="ph ph-check-circle"></i> Phe duyet
                </button>
            </div>`).join('');
    } catch (err) {
        container.innerHTML = '<p style="color:var(--danger); font-size:0.85rem;">Loi: ' + err.message + '</p>';
    }
}

// Hook: fetch pending khi mo tab qualification
document.addEventListener('DOMContentLoaded', () => {
    // Patch: khi switchTab goi tab-qualification, fetch pending
    const origSwitchTab = window.switchTab;
    if (origSwitchTab) {
        window.switchTab = function(tabId, btn) {
            origSwitchTab(tabId, btn);
            if (tabId === 'tab-qualification' && window.currentSupplierId) {
                fetchPendingScopeRequests(window.currentSupplierId);
            }
        };
    }
});

// ============================================================
// PHASE 3: RISK MANAGEMENT UI
// ============================================================

window.openRiskModal = function() {
    if (!window.currentSupplierId) {
        alert("Vui lòng chọn một nhà cung cấp trước.");
        return;
    }
    document.getElementById('riskSupplierId').value = window.currentSupplierId;
    document.getElementById('riskTitle').value = '';
    document.getElementById('riskDesc').value = '';
    document.getElementById('riskSeverity').value = 'Medium';
    document.getElementById('riskDueDate').value = '';
    document.getElementById('riskIssueModal').classList.add('active');
}

window.closeRiskModal = function() {
    document.getElementById('riskIssueModal').classList.remove('active');
}

window.submitRiskIssue = async function() {
    const supplier_id = document.getElementById('riskSupplierId').value;
    const title = document.getElementById('riskTitle').value;
    const description = document.getElementById('riskDesc').value;
    const severity = document.getElementById('riskSeverity').value;
    const due_date = document.getElementById('riskDueDate').value;

    if (!title || !severity) {
        alert("Vui lòng điền tiêu đề và mức độ nghiêm trọng.");
        return;
    }

    try {
        const { data, error } = await db.from('sm_risk_issue').insert([
            {
                supplier_id,
                title,
                description,
                severity,
                due_date: due_date || null
            }
        ]);

        if (error) throw error;
        
        showToast('Đã ghi nhận rủi ro thành công!');
        closeRiskModal();
        
        openSupplier360(supplier_id);
    } catch (err) {
        alert("Lỗi khi lưu rủi ro: " + err.message);
    }
}

// ============================================================
// PHASE 4: DOCUMENT & QUESTIONNAIRE UI
// ============================================================



window.openQuestionnaireModal = function() {
    const supplierId = window.currentSupplierId;
    if (!supplierId) return alert("Vui lòng chọn nhà cung cấp trước.");
    
    document.getElementById('questSupplierId').value = supplierId;
    document.getElementById('questionnaireForm').reset();
    document.getElementById('questionnaireModal').classList.add('active');
}

window.closeQuestionnaireModal = function() {
    document.getElementById('questionnaireModal').classList.remove('active');
}

window.submitQuestionnaire = async function() {
    const supplierId = document.getElementById('questSupplierId').value;
    const templateId = document.getElementById('questTemplateId').value;
    
    if (!templateId) return alert("Vui lòng nhập ID Bộ câu hỏi.");

    try {
        const { data, error } = await db.rpc('sm_assign_questionnaire', {
            p_supplier_id: supplierId,
            p_template_id: parseInt(templateId)
        });
        if (error) throw error;
        
        showToast("Đã gán bộ câu hỏi thành công! ID: " + data);
        closeQuestionnaireModal();
        if (typeof window.fetchQuestionnaires === 'function') {
            window.fetchQuestionnaires(supplierId);
        }
    } catch (err) {
        alert("Lỗi gán bộ câu hỏi: " + err.message);
    }
}

window.fetchQuestionnaires = async function(supplierId) {
    const container = document.getElementById('questionnaireList');
    if (!container || !supplierId) return;
    
    try {
        const { data, error } = await db
            .from('sm_questionnaire_instance')
            .select(`
                id, status, due_date, score,
                sm_questionnaire_template(title, version)
            `)
            .eq('supplier_id', supplierId)
            .order('created_at', { ascending: false });
            
        if (error) throw error;
        
        if (!data || data.length === 0) {
            container.innerHTML = `
                <div style="text-align: center; padding: 40px 0; color: var(--text-muted);">
                    <i class="ph ph-file-text" style="font-size: 3rem; color: rgba(255,255,255,0.1); margin-bottom: 10px;"></i>
                    <p style="margin: 0;">Chưa có bộ câu hỏi nào được gán cho nhà cung cấp này.</p>
                </div>
            `;
            return;
        }

        let listHtml = data.map(q => `
            <div style="background:var(--card-bg); border:1px solid var(--border-color); border-radius:8px; padding:12px 16px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;">
                <div>
                    <strong>${q.sm_questionnaire_template?.title || 'Unknown'} (v${q.sm_questionnaire_template?.version})</strong>
                    <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">
                        Trạng thái: <span style="color:var(--primary);">${q.status}</span> | 
                        Hạn chót: ${q.due_date ? new Date(q.due_date).toLocaleDateString() : 'N/A'}
                    </div>
                </div>
                <button class="secondary-btn" onclick="alert('Mở form trả lời câu hỏi cho ' + '${q.id}')">Chi tiết</button>
            </div>
        `).join('');

        container.innerHTML = listHtml;
    } catch (err) {
        container.innerHTML = '<p style="color:var(--danger);">Lỗi: ' + err.message + '</p>';
    }
}

// ============================================================
// PHASE 5: PERFORMANCE UI
// ============================================================

// Performance modal logic is already implemented globally at line 963.
// We just remove the duplicate prompt-based one here.

// ============================================================
// PHASE 6: INTEGRATION & AUDIT UI
// ============================================================

window.fetchIntegrationStatus = async function(supplierId) {
    const cwContainer = document.getElementById('crosswalkList');
    const outboxContainer = document.getElementById('outboxList');
    if (!cwContainer || !outboxContainer || !supplierId) return;

    try {
        // Fetch crosswalk
        const { data: cwData, error: cwErr } = await db
            .from('sm_supplier_crosswalk')
            .select('*')
            .eq('supplier_id', supplierId);
        
        // Render crosswalk
        if (!cwData || cwData.length === 0) {
            cwContainer.innerHTML = '<p style="color: var(--text-muted);">Không có dữ liệu Crosswalk (Chưa đồng bộ hệ thống ngoài).</p>';
        } else {
            cwContainer.innerHTML = cwData.map(c => `
                <div style="background: rgba(255,255,255,0.05); border: 1px solid var(--border-color); padding: 10px; border-radius: 6px; margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center;">
                    <div><strong>Hệ thống: ${c.target_system}</strong> - ID: ${c.external_id}</div>
                    <button onclick="deleteCrosswalk('${c.id}')" style="background: transparent; border: none; color: #EF4444; cursor: pointer; padding: 4px;" title="Xóa">🗑️</button>
                </div>
            `).join('');
        }

        // Fetch outbox
        const { data: outboxData, error: outboxErr } = await db
            .from('sm_supplier_outbox')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(5); // In real app, filter by payload->>supplier_id if possible, or create an RPC for it
        
        if (!outboxData || outboxData.length === 0) {
            outboxContainer.innerHTML = '<p style="color: var(--text-muted);">Không có sự kiện đồng bộ gần đây.</p>';
        } else {
            outboxContainer.innerHTML = outboxData.map(o => `
                <div style="background: rgba(255,255,255,0.05); border: 1px solid var(--border-color); padding: 10px; border-radius: 6px; margin-bottom: 8px;">
                    <div style="display: flex; justify-content: space-between;">
                        <strong>${o.event_type}</strong>
                        <span class="status-badge" style="background: ${o.status === 'Pending' ? '#FEF3C7' : '#D1FAE5'}; color: ${o.status === 'Pending' ? '#D97706' : '#059669'};">${o.status}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; align-items: center; font-size: 0.8rem; color: var(--text-muted); margin-top: 5px;">
                        <div>Ngày tạo: ${new Date(o.created_at).toLocaleString()}</div>
                        <button onclick="deleteOutbox('${o.id}')" style="background: transparent; border: none; color: #EF4444; cursor: pointer; padding: 4px;" title="Xóa">🗑️</button>
                    </div>
                </div>
            `).join('');
        }

        // Auto-refresh logic: Nếu có yêu cầu đang Pending, tự động gọi lại sau 2 giây
        const hasPending = outboxData && outboxData.some(o => o.status === 'Pending');
        if (hasPending) {
            setTimeout(() => {
                // Chỉ gọi lại nếu đang ở đúng nhà cung cấp đó
                if (window.currentSupplierId === supplierId) {
                    fetchIntegrationStatus(supplierId);
                }
            }, 2000);
        }
    } catch (err) {
        console.error("Lỗi Integration:", err.message);
    }
}

window.deleteCrosswalk = async function(id) {
    if (!confirm("Bạn có chắc chắn muốn xóa Crosswalk này?")) return;
    try {
        const { error } = await db.from('sm_supplier_crosswalk').delete().eq('id', id);
        if (error) throw error;
        fetchIntegrationStatus(window.currentSupplierId);
    } catch (err) {
        console.error("Lỗi xóa Crosswalk:", err.message);
        alert("Lỗi: " + err.message);
    }
};

window.deleteOutbox = async function(id) {
    if (!confirm("Bạn có chắc chắn muốn xóa lịch sử đồng bộ này?")) return;
    try {
        const { error } = await db.from('sm_supplier_outbox').delete().eq('id', id);
        if (error) throw error;
        fetchIntegrationStatus(window.currentSupplierId);
    } catch (err) {
        console.error("Lỗi xóa Outbox:", err.message);
        alert("Lỗi: " + err.message);
    }
}

// Fetch Audit History
window.fetchAuditHistory = async function(supplierId) {
    const container = document.getElementById('s360-history-timeline');
    if (!container) return;

    try {
        const { data, error } = await db
            .from('sm_supplier_audit_event')
            .select('*')
            .eq('entity_id', supplierId)
            .order('timestamp', { ascending: false });
        
        if (error) throw error;

        if (!data || data.length === 0) {
            return; // Just return, don't clear the lifecycle history
        }

        const auditHtml = data.map(item => {
            const oldStatus = item.before_state && item.before_state.status ? item.before_state.status : 'N/A';
            const newStatus = item.after_state && item.after_state.status ? item.after_state.status : 'N/A';
            const date = new Date(item.timestamp).toLocaleString();
            
            return `
                <div style="position: relative; margin-bottom: 20px;">
                    <div style="position: absolute; left: -26px; top: 4px; width: 12px; height: 12px; border-radius: 50%; background: #F59E0B; border: 2px solid white;"></div>
                    <h4 style="margin: 0; color: #fff; font-size: 0.95rem;">${item.action}</h4>
                    <p style="margin: 4px 0 8px 0; font-size: 0.85rem; color: var(--text-muted);">${date} - Bởi: Admin</p>
                    <div style="background: rgba(255,255,255,0.05); padding: 10px; border-radius: 6px; font-size: 0.85rem; border-left: 3px solid #F59E0B;">
                        <span style="color: #EF4444; text-decoration: line-through;">${oldStatus}</span> 
                        <i class="ph ph-arrow-right" style="margin: 0 8px;"></i> 
                        <span style="color: #10B981; font-weight: bold;">${newStatus}</span>
                    </div>
                </div>
            `;
        }).join('');
        
        // Remove the "Chưa có nhật ký" message if it exists
        if (container.innerHTML.includes('Chưa có nhật ký')) {
            container.innerHTML = auditHtml;
        } else {
            container.innerHTML = auditHtml + container.innerHTML;
        }
    } catch (err) {
        console.error("Lỗi fetchAuditHistory:", err.message);
        container.innerHTML = `<p style="color: var(--danger); font-size: 0.9rem;">Không thể tải lịch sử: ${err.message}</p>`;
    }
}

window.pushToERP = async function() {
    const supplierId = window.currentSupplierId;
    if (!supplierId) return alert("Vui lòng chọn nhà cung cấp trước.");

    const targetSys = prompt("Nhập hệ thống đích (ví dụ: SAP, Oracle):", "SAP");
    if (!targetSys) return;

    try {
        // Insert a manual Outbox event
        const { error } = await db.from('sm_supplier_outbox').insert([
            {
                event_type: 'MANUAL_PUSH_TO_ERP',
                payload: { supplier_id: supplierId, target_system: targetSys },
                status: 'Pending'
            }
        ]);
        if (error) throw error;

        showToast("Đã đưa yêu cầu đồng bộ vào hàng đợi (Outbox)!");
        fetchIntegrationStatus(supplierId);
    } catch (err) {
        alert("Lỗi đẩy sang ERP: " + err.message);
    }
}

window.upsertCrosswalk = async function() {
    const supplierId = window.currentSupplierId;
    if (!supplierId) return;

    const sys = prompt("Nhập tên hệ thống ERP (ví dụ: NAV, VISTA):", "NAV");
    if (!sys) return;
    const extId = prompt("Nhập mã NCC trên ERP:", "V-12345");
    if (!extId) return;

    try {
        const { error } = await db.rpc('sm_upsert_supplier_crosswalk', {
            p_supplier_id: supplierId,
            p_external_system: sys,
            p_external_id: extId
        });
        if (error) throw error;
        showToast("Cập nhật mã ERP thành công!");
        fetchIntegrationStatus(supplierId);
    } catch (err) {
        alert("Lỗi: " + err.message);
    }
}
