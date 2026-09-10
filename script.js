document.addEventListener('DOMContentLoaded', () => {
    // --- 1. Tab Switching Logic ---
    const tabs = document.querySelectorAll('.tab');
    const dashboardGrid = document.querySelector('.dashboard-grid');
    
    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            // Remove active class from all tabs
            tabs.forEach(t => t.classList.remove('active'));
            // Add active class to clicked tab
            tab.classList.add('active');
            
            // Add a small fade animation effect to the content area
            dashboardGrid.classList.remove('animate-fade-in');
            // Trigger reflow to restart animation
            void dashboardGrid.offsetWidth;
            dashboardGrid.classList.add('animate-fade-in');
            
            console.log(`Switched to tab: ${tab.innerText}`);
            // In a real app, this is where you'd show/hide different content sections based on the active tab
        });
    });

    // --- 2. Modal Popup Logic ---
    const modal = document.getElementById('requestModal');
    // Find the Request Update button (it's the outline button in the header)
    const updateBtn = Array.from(document.querySelectorAll('.btn-outline')).find(btn => btn.innerText.includes('Request Update'));
    const closeBtns = document.querySelectorAll('.close-modal, .close-btn');

    // Open Modal
    if (updateBtn) {
        updateBtn.addEventListener('click', () => {
            modal.classList.add('show');
        });
    }

    // Close Modal when clicking close buttons
    closeBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            modal.classList.remove('show');
        });
    });

    // Close Modal when clicking outside the modal content
    window.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.remove('show');
        }
    });

    // --- 3. Sidebar Navigation Interactions (Cosmetic) ---
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
        item.addEventListener('click', function(e) {
            // Only handle click if it's not a real link (has href="#")
            if (this.getAttribute('href') === '#') {
                e.preventDefault();
                navItems.forEach(nav => nav.classList.remove('active'));
                this.classList.add('active');
            }
        });
    });
});
