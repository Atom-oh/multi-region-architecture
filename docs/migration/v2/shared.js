// === Shared JS for Deep Dive pages ===
// These pages use <aside class="sidebar" id="sidebar"></aside> and load sidebar via JS

(function() {
    const currentPage = location.pathname.split('/').pop() || 'index.html';

    function isActive(href) {
        return currentPage === href ? ' active' : '';
    }

    function stepNum(n) {
        const active = isActive('step-' + n + '.html');
        return `<span class="step-num">${n}</span>`;
    }

    const sidebarHTML = `
        <div class="sidebar-header">
            <div class="sidebar-logo">On-Prem to AWS<br>Multi-Region Migration<small>1-Hour Technical Session</small></div>
        </div>
        <nav class="sidebar-nav">
            <div class="sidebar-section">
                <div class="sidebar-section-title">Overview</div>
                <a href="index.html" class="sidebar-link${isActive('index.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
                    소개
                </a>
            </div>
            <div class="sidebar-section">
                <div class="sidebar-section-title">Migration Steps</div>
                <a href="step-0.html" class="sidebar-link${isActive('step-0.html')}"><span class="step-num">0</span> 초기 상태</a>
                <a href="step-1.html" class="sidebar-link${isActive('step-1.html')}"><span class="step-num">1</span> us-west-2 배포</a>
                <a href="step-2.html" class="sidebar-link${isActive('step-2.html')}"><span class="step-num">2</span> us-east-1 배포</a>
                <a href="step-3.html" class="sidebar-link${isActive('step-3.html')}"><span class="step-num">3</span> 리전간 동기화</a>
                <a href="step-4.html" class="sidebar-link${isActive('step-4.html')}"><span class="step-num">4</span> 트래픽 분산</a>
                <a href="step-5.html" class="sidebar-link${isActive('step-5.html')}"><span class="step-num">5</span> AWS 확대</a>
                <a href="step-6.html" class="sidebar-link${isActive('step-6.html')}"><span class="step-num">6</span> Full AWS</a>
            </div>
            <div class="sidebar-section">
                <div class="sidebar-section-title">Deep Dive</div>
                <a href="multi-region.html" class="sidebar-link${isActive('multi-region.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>
                    CCS Multi-Region
                </a>
                <a href="data-sync.html" class="sidebar-link${isActive('data-sync.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>
                    CCDI Data Sync
                </a>
                <a href="connected-car.html" class="sidebar-link${isActive('connected-car.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 17h2m10 0h2M12 17h.01"/><path d="M3 9l2-4h14l2 4M3 9v8h18V9"/></svg>
                    Connected Car Latency
                </a>
                <a href="route-cache.html" class="sidebar-link${isActive('route-cache.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/></svg>
                    GIS Route Cache
                </a>
                <a href="eks-operations.html" class="sidebar-link${isActive('eks-operations.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8m-4-4v4"/></svg>
                    EKS Operations
                </a>
                <a href="msk-operations.html" class="sidebar-link${isActive('msk-operations.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
                    MSK Operations
                </a>
                <a href="availability.html" class="sidebar-link${isActive('availability.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                    Availability
                </a>
                <a href="ccs-data-architecture.html" class="sidebar-link${isActive('ccs-data-architecture.html')}">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>
                    CCS Data Architecture
                </a>
            </div>
        </nav>
        <div class="sidebar-footer">
            <button class="lang-toggle" onclick="toggleLang()">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>
                <span class="lang-label">KO</span>
            </button>
            <button class="theme-toggle" onclick="toggleTheme()">
                <svg class="sun-icon" viewBox="0 0 24 24" style="display:none"><path d="M12 7a5 5 0 100 10 5 5 0 000-10zm0-5a1 1 0 011 1v2a1 1 0 11-2 0V3a1 1 0 011-1zm0 18a1 1 0 011 1v2a1 1 0 11-2 0v-2a1 1 0 011-1zm9-9a1 1 0 01-1 1h-2a1 1 0 110-2h2a1 1 0 011 1zM6 12a1 1 0 01-1 1H3a1 1 0 110-2h2a1 1 0 011 1z"/></svg>
                <svg class="moon-icon" viewBox="0 0 24 24"><path d="M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z"/></svg>
                <span class="theme-label">Dark</span>
            </button>
        </div>
    `;

    // Inject sidebar
    const sidebarEl = document.getElementById('sidebar');
    if (sidebarEl) {
        sidebarEl.innerHTML = sidebarHTML;
    }

    // === Shared functions ===
    window.toggleTechCard = function(header) {
        const body = header.nextElementSibling;
        const chevron = header.querySelector('.chevron-icon');
        body.classList.toggle('open');
        if (chevron) chevron.classList.toggle('open');
    };

    window.toggleTheme = function() {
        const t = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', t);
        localStorage.setItem('theme', t);
        updateThemeIcon();
    };

    function updateThemeIcon() {
        const dark = document.documentElement.getAttribute('data-theme') === 'dark';
        const sun = document.querySelector('.sun-icon');
        const moon = document.querySelector('.moon-icon');
        const label = document.querySelector('.theme-label');
        if (sun) sun.style.display = dark ? 'none' : 'block';
        if (moon) moon.style.display = dark ? 'block' : 'none';
        if (label) label.textContent = dark ? 'Dark' : 'Light';
    }

    window.toggleSidebar = function() {
        document.querySelector('.sidebar').classList.toggle('open');
        document.querySelector('.sidebar-overlay').classList.toggle('open');
    };

    function initScrollSpy() {
        const links = document.querySelectorAll('.doc-toc .toc-link');
        const sections = [];
        links.forEach(l => {
            const el = document.getElementById(l.getAttribute('href').slice(1));
            if (el) sections.push({ el, link: l });
        });
        const obs = new IntersectionObserver(entries => {
            entries.forEach(e => {
                if (e.isIntersecting) {
                    links.forEach(l => l.classList.remove('active'));
                    const m = sections.find(s => s.el === e.target);
                    if (m) m.link.classList.add('active');
                }
            });
        }, { rootMargin: '-20% 0px -70% 0px' });
        sections.forEach(s => obs.observe(s.el));
    }

    // === Language Toggle ===
    window.toggleLang = function() {
        const current = document.documentElement.getAttribute('data-lang') || 'en';
        const next = current === 'ko' ? 'en' : 'ko';
        document.documentElement.setAttribute('data-lang', next);
        localStorage.setItem('lang', next);
        updateLangLabel();
    };

    function updateLangLabel() {
        const lang = document.documentElement.getAttribute('data-lang') || 'en';
        const label = document.querySelector('.lang-label');
        if (label) label.textContent = lang === 'en' ? 'KO' : 'EN';
    }

    // Init
    const savedLang = localStorage.getItem('lang') || 'en';
    document.documentElement.setAttribute('data-lang', savedLang);

    const saved = localStorage.getItem('theme');
    if (saved) document.documentElement.setAttribute('data-theme', saved);
    updateThemeIcon();
    updateLangLabel();
    initScrollSpy();
})();
