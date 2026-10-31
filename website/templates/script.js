/* --- START OF FILE script.js --- */
document.addEventListener('DOMContentLoaded', () => {
    // --- GSAP & ScrollTrigger Initialization ---
    if (typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined') {
        gsap.registerPlugin(ScrollTrigger);
    }

    // --- Blip cinematic demo: play at 2.5x speed ---
    const blipVideo = document.querySelector('.blip-video-element');
    if (blipVideo) {
        blipVideo.defaultPlaybackRate = 2.5;
        blipVideo.playbackRate = 2.5;
    }

    // --- Universal Lenis Smooth Scrolling ---
    let lenis = null;
    if (typeof Lenis !== 'undefined') {
        lenis = new Lenis({
            lerp: 0.085,
            wheelMultiplier: 1.0,
            smoothWheel: true,
            orientation: 'vertical'
        });

        if (typeof ScrollTrigger !== 'undefined') {
            lenis.on('scroll', ScrollTrigger.update);
        }

        function raf(time) {
            lenis.raf(time);
            requestAnimationFrame(raf);
        }
        requestAnimationFrame(raf);

        if (typeof gsap !== 'undefined') {
            gsap.ticker.lagSmoothing(0);
        }
    }

    // --- DOM Elements & Theme Controls ---
    const header = document.getElementById('main-header');
    const themeRadios = document.querySelectorAll('.switch-radio');
    const darkGradient = document.getElementById('dark-mode-gradient');
    const sapphireIcon = document.getElementById('sapphire-icon');
    const footerLogo = document.getElementById('footer-logo');
    const cursor = document.getElementById('custom-cursor');
    const dotContainer = document.getElementById('dot-container');
    const sectionDock = document.getElementById('section-dock');
    const dockPills = document.querySelectorAll('.dock-pill');

    let mouse = { x: -100, y: -100 };
    let cursorSmoothed = { x: -100, y: -100 };
    const CURSOR_TOGGLE_THRESHOLD = 5;
    let backgroundClickCount = 0;
    let backgroundClickTimer = null;
    let isCursorActive = localStorage.getItem('sapphire-custom-cursor') === 'true';

    // --- Robust Theme System ---
    function applyTheme(theme) {
        document.documentElement.className = `theme-${theme}`;
        localStorage.setItem('sapphire-theme', theme);

        document.querySelectorAll('.switch-radio').forEach(radio => {
            radio.checked = (radio.value === theme);
        });

        if (darkGradient) {
            darkGradient.style.opacity = '1';
        }
        const newIconSrc = theme === 'light' ? './sapphire-dark.png' : './sapphire-light.png';
        if (sapphireIcon) sapphireIcon.src = newIconSrc;
        if (footerLogo) footerLogo.src = newIconSrc;
    }

    const savedTheme = localStorage.getItem('sapphire-theme') || 'dark';
    applyTheme(savedTheme);

    document.querySelectorAll('.switch-radio').forEach(radio => {
        radio.addEventListener('change', e => {
            if (e.target.checked) {
                applyTheme(e.target.value);
            }
        });
    });

    document.querySelectorAll('.switch-label').forEach(label => {
        label.addEventListener('click', () => {
            const forId = label.getAttribute('for');
            const targetRadio = document.getElementById(forId);
            if (targetRadio) {
                targetRadio.checked = true;
                applyTheme(targetRadio.value);
            }
        });
    });

    // --- EASTER EGG: 5-CLICK BACKGROUND CUSTOM DOT CURSOR TOGGLE ---
    function setCursorState(active) {
        isCursorActive = active;
        localStorage.setItem('sapphire-custom-cursor', isCursorActive.toString());
        document.body.classList.toggle('custom-cursor-active', isCursorActive);
        if (cursor) {
            cursor.style.opacity = isCursorActive ? '1' : '0';
        }
    }

    if (isCursorActive) {
        setCursorState(true);
    }

    window.addEventListener('click', (e) => {
        if (e.target.closest('a, button, input, label, select, textarea, #theme-switcher, .dock-pill, .app-card-vertical, video, #main-header')) {
            return;
        }

        backgroundClickCount++;
        clearTimeout(backgroundClickTimer);

        if (backgroundClickCount >= CURSOR_TOGGLE_THRESHOLD) {
            setCursorState(!isCursorActive);
            backgroundClickCount = 0;
        } else {
            backgroundClickTimer = setTimeout(() => {
                backgroundClickCount = 0;
            }, 450);
        }
    });

    // --- Mouse Tracking & Custom Cursor Follower Loop ---
    window.addEventListener('mousemove', e => {
        mouse.x = e.clientX;
        mouse.y = e.clientY;
        document.documentElement.style.setProperty('--mouse-x', `${mouse.x}px`);
        document.documentElement.style.setProperty('--mouse-y', `${mouse.y}px`);
    }, { passive: true });

    function cursorLoop() {
        if (isCursorActive && cursor) {
            cursorSmoothed.x += (mouse.x - cursorSmoothed.x) * 0.2;
            cursorSmoothed.y += (mouse.y - cursorSmoothed.y) * 0.2;
            cursor.style.transform = `translate3d(${cursorSmoothed.x}px, ${cursorSmoothed.y}px, 0) translate(-50%, -50%)`;
        }
        requestAnimationFrame(cursorLoop);
    }
    requestAnimationFrame(cursorLoop);

    function attachCursorHoverListeners() {
        document.querySelectorAll('a, button, input, label, select, textarea, .dock-pill, .app-card-vertical, .security-pillar-card, .header-btn').forEach(el => {
            el.addEventListener('mouseenter', () => {
                if (cursor && isCursorActive) cursor.classList.add('cursor-hover');
            });
            el.addEventListener('mouseleave', () => {
                if (cursor && isCursorActive) cursor.classList.remove('cursor-hover');
            });
        });
    }
    attachCursorHoverListeners();

    // --- Check Current Page Types ---
    const isHomepage = document.getElementById('hero-section');
    const isIssuesPage = document.getElementById('issues-list');
    const isChangelogPage = document.getElementById('changelog-container');

    // ==========================================
    // 1. HOMEPAGE LOGIC & ANIMATIONS
    // ==========================================
    if (isHomepage && typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined') {
        document.querySelectorAll('.apple-scrub-text').forEach(el => {
            const text = el.innerText.trim();
            const words = text.split(/\s+/);
            el.innerHTML = words.map(w => `<span class="apple-word">${w}</span>`).join(' ');
        });

        const appMatrixContainer = document.getElementById('blip-apps-showcase-matrix');
        if (appMatrixContainer) {
            const appIcons = [
                { icon: "/assets/app-icons/safari.svg", name: "Safari" },
                { icon: "/assets/app-icons/chrome.svg", name: "Chrome" },
                { icon: "/assets/app-icons/firefox.svg", name: "Firefox" },
                { icon: "/assets/app-icons/mail.png", name: "Mail" },
                { icon: "/assets/app-icons/calendar.png", name: "Calendar" },
                { icon: "/assets/app-icons/notes.svg", name: "Notes" },
                { icon: "/assets/app-icons/finder.png", name: "Finder" },
                { icon: "/assets/app-icons/maps.svg", name: "Maps" },
                { icon: "/assets/app-icons/music.svg", name: "Music" },
                { icon: "/assets/app-icons/spotify.svg", name: "Spotify" },
                { icon: "/assets/app-icons/netflix.svg", name: "Netflix" },
                { icon: "/assets/app-icons/youtube.png", name: "YouTube" },
                { icon: "/assets/app-icons/discord.svg", name: "Discord" },
                { icon: "/assets/app-icons/slack.svg", name: "Slack" },
                { icon: "/assets/app-icons/notion.svg", name: "Notion" },
                { icon: "/assets/app-icons/photoshop.svg", name: "Photoshop" },
                { icon: "/assets/app-icons/illustrator.svg", name: "Illustrator" },
                { icon: "/assets/app-icons/figma.svg", name: "Figma" },
                { icon: "/assets/app-icons/excel.svg", name: "Excel" },
                { icon: "/assets/app-icons/blender.svg", name: "Blender" },
                { icon: "/assets/app-icons/finalcut.png", name: "Final Cut" },
                { icon: "/assets/app-icons/logicpro.png", name: "Logic Pro" },
                { icon: "/assets/app-icons/voicememos.png", name: "Voice Memos" },
                { icon: "/assets/app-icons/shortcuts.png", name: "Shortcuts" },
                { icon: "/assets/app-icons/xcode.svg", name: "Xcode" },
                { icon: "/assets/app-icons/appstore.svg", name: "App Store" },
                { icon: "/assets/app-icons/settings.png", name: "Settings" },
                { icon: "/assets/app-icons/photos.svg", name: "Photos" },
                { icon: "/assets/app-icons/messages.svg", name: "Messages" },
                { icon: "/assets/app-icons/facetime.svg", name: "FaceTime" }
            ];

            const masterAppList = appIcons;

            const createCardHTML = (app) => `
                <div class="app-card-vertical">
                    <div class="w-10 h-10 rounded-xl flex items-center justify-center border border-white/5 shrink-0 overflow-hidden">
                        <img src="${app.icon}" alt="${app.name}" class="w-full h-full object-contain rounded-xl" loading="lazy">
                    </div>
                    <span class="text-sm font-bold text-white tracking-wide truncate">${app.name}</span>
                </div>
            `;

            const col1 = document.getElementById('app-col-1');
            const col2 = document.getElementById('app-col-2');
            const col3 = document.getElementById('app-col-3');

            if(col1 && col2 && col3) {
                col1.innerHTML = masterAppList.slice(0, 10).map(createCardHTML).join('');
                col2.innerHTML = masterAppList.slice(10, 20).map(createCardHTML).join('');
                col3.innerHTML = masterAppList.slice(20, 30).map(createCardHTML).join('');
            }
            attachCursorHoverListeners();
        }

        ScrollTrigger.create({
            start: 'top top',
            end: '+=200',
            onUpdate: (self) => {
                if (dotContainer) {
                    dotContainer.style.opacity = (1 - self.progress).toString();
                }
            }
        });

        const heroTl = gsap.timeline({ defaults: { ease: 'power3.out', duration: 1 } });
        heroTl.fromTo('.hero-tag', { opacity: 0, y: -20 }, { opacity: 1, y: 0, delay: 0.1 })
              .fromTo('.hero-title', { opacity: 0, y: 30 }, { opacity: 1, y: 0 }, '-=0.8')
              .fromTo('.hero-desc', { opacity: 0, y: 20 }, { opacity: 1, y: 0 }, '-=0.8')
              .fromTo('.hero-cta', { opacity: 0, y: 20 }, { opacity: 1, y: 0 }, '-=0.8')
              .fromTo('.hero-video-frame', { opacity: 0, scale: 0.94, y: 40 }, { opacity: 1, scale: 1, y: 0 }, '-=0.7');

        const squigglyPath = document.querySelector('.animated-squiggly-path');
        const runwayTrack = document.getElementById('blip-runway-track');

        const blipMasterTl = gsap.timeline({
            scrollTrigger: {
                trigger: '#feature-blip-agent',
                start: 'top top',
                end: '+=600%',
                pin: '.blip-sticky-stage',
                scrub: 1,
                onEnter: () => {
                    if (squigglyPath) {
                        squigglyPath.classList.remove('is-drawn');
                        void squigglyPath.offsetWidth;
                    }
                },
                onEnterBack: () => {
                    if (squigglyPath) {
                        squigglyPath.classList.remove('is-drawn');
                        void squigglyPath.offsetWidth;
                    }
                }
            }
        });

        const getRunwayDistance = () => {
            return runwayTrack ? -(runwayTrack.scrollWidth - window.innerWidth + 180) : -2200;
        };

        blipMasterTl
            .fromTo('.blip-runway-viewport', { opacity: 1 }, { opacity: 1, duration: 3.5, ease: 'none' })
            .fromTo('#blip-runway-track', { x: window.innerWidth * 0.4 }, { x: () => getRunwayDistance(), duration: 3.5, ease: 'none' }, '<')
            .to('.bg-shape-square', { rotation: 360, rotationX: 180, duration: 3.5, ease: 'none' }, '<')
            .to('.bg-shape-triangle', { rotation: -360, scale: 1.25, duration: 3.5, ease: 'none' }, '<')
            .to('.bg-shape-circle', { scale: 1.3, duration: 3.5, ease: 'none' }, '<')
            .to('.bg-shape-diamond', { rotation: 270, rotationY: 180, duration: 3.5, ease: 'none' }, '<')
            .to('.blip-runway-viewport', { opacity: 0, scale: 0.96, duration: 0.8 })
            .fromTo('.blip-intro-text', 
                { opacity: 0, y: 40, filter: 'blur(12px)' }, 
                { opacity: 1, y: 0, filter: 'blur(0px)', duration: 1.2, onComplete: () => { if (squigglyPath) squigglyPath.classList.add('is-drawn'); } }
            )
            .to('.blip-intro-text', { opacity: 0, y: -30, filter: 'blur(8px)', duration: 0.8 }, '+=1.0')
            .fromTo('.blip-85vw-video-frame', { opacity: 0, scale: 0.55, y: '50%' }, { opacity: 1, scale: 1, y: '0%', duration: 1.8, ease: 'power2.out' })
            .fromTo('.blip-video-caption', { opacity: 0 }, { opacity: 1, duration: 0.8, ease: 'power2.out' }, '-=1.2')
            .to('.blip-85vw-video-frame', { scale: 0.88, borderRadius: '40px', opacity: 0.8, duration: 1.4, ease: 'power3.out' }, '+=1.0');

        const slotActionsList = [
            "organize messy download folders", "remove backgrounds from photos", "summarize open browser tabs",
            "add onto your notes", "clean up duplicate files", "send urgent emails",
            "convert HEIC photos to PNG", "batch-rename vacation photos", "sync family calendar schedules",
            "optimize your workflow", "generate quick meeting summaries", "clear out junk storage & caches",
            "track household monthly budgets", "convert video clips to GIFs", "draft quick email replies",
            "translate PDF documents", "compress large PDF files", "extract text from images",
            "send out party invitations", "find lost documents on your Mac", "rescale images for social media",
            "send automated text reminders", "create a weekly meal planner", "schedule social media posts",
            "organize receipts for taxes", "assist with math problems", "monitor home internet speed",
            "unzip files", "assist with video editing", "scan documents using phone camera",
            "delete spam emails out of inbox", "generate travel itineraries", "track package deliveries",
            "convert audio files to MP3", "create a book summaries", "convert currency & measurements",
            "generate recipes from fridge ingredients", "organize digital photo albums", "mute notifications during focus time",
            "create a Word document", "set up smart home routines", "format Excel spreadsheets automatically",
            "find missing files", "create Blender 3D Models", "integrate into your workflow."
        ];

        const slotStripEl = document.getElementById('slot-reel-strip');
        const ITEM_HEIGHT = 90;

        if (slotStripEl) {
            slotStripEl.innerHTML = slotActionsList.map((action, i) => `
                <div class="slot-item ${i === 0 ? 'is-active' : i === 1 ? 'is-adjacent' : ''}" data-index="${i}">
                    ${action}
                </div>
            `).join('');
        }

        let isDrumRunning = false;
        let drumTimeout = null;

        function runSlotDrumEngine() {
            if (!slotStripEl || isDrumRunning) return;
            isDrumRunning = true;

            const items = slotStripEl.querySelectorAll('.slot-item');
            let currentIdx = 0;
            const totalItems = slotActionsList.length;

            function getStepDelay(idx) {
                if (idx < 6) return 650 - (idx * 60);
                if (idx < 22) return 290 - ((idx - 6) * 16);
                if (idx < totalItems - 12) return 35;
                const remaining = totalItems - idx;
                const decelFactor = (12 - remaining);
                return 35 + Math.pow(decelFactor, 2.3) * 2.5;
            }

            function stepDrum() {
                currentIdx++;
                const targetY = 90 - (currentIdx * ITEM_HEIGHT);
                
                items.forEach((item, idx) => {
                    item.classList.remove('is-active', 'is-adjacent');
                    if (idx === currentIdx) {
                        item.classList.add('is-active');
                    } else if (idx === currentIdx - 1 || idx === currentIdx + 1) {
                        item.classList.add('is-adjacent');
                    }
                });

                const currentDelay = getStepDelay(currentIdx);

                gsap.to(slotStripEl, {
                    y: targetY,
                    duration: Math.max(0.025, currentDelay / 1000 * 0.75),
                    ease: currentDelay > 120 ? 'back.out(1.4)' : 'none'
                });

                if (currentIdx < totalItems - 1) {
                    drumTimeout = setTimeout(stepDrum, currentDelay);
                }
            }

            drumTimeout = setTimeout(stepDrum, 500);
        }

        const actionsShowcaseTl = gsap.timeline({
            scrollTrigger: {
                trigger: '#feature-blip-actions-showcase',
                start: 'top top',
                end: '+=400%',
                pin: '.blip-actions-sticky-stage',
                scrub: 1,
                onEnter: () => { if (!isDrumRunning) runSlotDrumEngine(); },
                onLeaveBack: () => {
                    isDrumRunning = false;
                    clearTimeout(drumTimeout);
                    if (slotStripEl) gsap.set(slotStripEl, { y: 90 });
                }
            }
        });

        actionsShowcaseTl
            .to('.slot-reel-stage-center', { opacity: 1, duration: 1.5 })
            .to('.slot-reel-stage-center', { opacity: 0, y: -40, scale: 0.95, duration: 0.8 })
            .to('#blip-apps-showcase-matrix', { opacity: 1, pointerEvents: 'auto', duration: 0.8 }, '-=0.4')
            .fromTo('.col-up', { y: '0%' }, { y: '-30%', duration: 4, ease: 'none' }, '+=0')
            .fromTo('.col-down', { y: '-30%' }, { y: '0%', duration: 4, ease: 'none' }, '<')
            .to('#blip-apps-showcase-matrix', { opacity: 0, duration: 0.6 });

        ScrollTrigger.create({
            trigger: '#feature-blip-actions-showcase',
            start: 'bottom 85%',
            endTrigger: '#final-cta-section',
            end: 'top 95%',
            onEnter: () => { if (sectionDock) sectionDock.classList.add('is-dock-visible'); },
            onLeave: () => { if (sectionDock) sectionDock.classList.remove('is-dock-visible'); },
            onEnterBack: () => { if (sectionDock) sectionDock.classList.add('is-dock-visible'); },
            onLeaveBack: () => { if (sectionDock) sectionDock.classList.remove('is-dock-visible'); }
        });

        const featureSections = document.querySelectorAll('section[id^="feature-"]:not(#feature-blip-agent):not(#feature-blip-actions-showcase):not(#feature-more)');
        
        featureSections.forEach((section, idx) => {
            const isEven = idx % 2 === 0;
            const textBlock = section.querySelector('.space-y-6, .space-y-12, .space-y-16, .max-w-4xl');
            const videoBlock = section.querySelector('.apple-glass, .aspect-video, .clean-video-frame');

            if (textBlock) {
                gsap.fromTo(textBlock,
                    { opacity: 0, y: 50, filter: 'blur(8px)' },
                    {
                        opacity: 1,
                        y: 0,
                        filter: 'blur(0px)',
                        duration: 1.2,
                        ease: 'power3.out',
                        scrollTrigger: {
                            trigger: section,
                            start: 'top 85%',
                            toggleActions: 'play none none reverse'
                        }
                    }
                );
            }

            if (videoBlock) {
                gsap.fromTo(videoBlock,
                    { opacity: 0, scale: 0.88, x: isEven ? 40 : -40, filter: 'brightness(0.7)' },
                    {
                        opacity: 1,
                        scale: 1,
                        x: 0,
                        filter: 'brightness(1)',
                        duration: 1.2,
                        ease: 'power3.out',
                        scrollTrigger: {
                            trigger: section,
                            start: 'top 70%',
                            toggleActions: 'play none none reverse'
                        }
                    }
                );
            }
        });

        document.querySelectorAll('.apple-scrub-text').forEach(el => {
            const wordSpans = el.querySelectorAll('.apple-word');

            gsap.fromTo(wordSpans, 
                { opacity: 0.15 },
                {
                    opacity: 1,
                    stagger: 0.1,
                    ease: 'none',
                    scrollTrigger: {
                        trigger: el,
                        start: 'top 80%',
                        end: 'center 50%',
                        scrub: 1 
                    }
                }
            );
        });

        ScrollTrigger.refresh();
        window.addEventListener('load', () => ScrollTrigger.refresh());

        const trackedSections = document.querySelectorAll('section[id]');
        function updateActiveDock() {
            const scrollPos = window.scrollY + (window.innerHeight / 3);

            trackedSections.forEach(section => {
                const top = section.offsetTop;
                const height = section.offsetHeight;
                const id = section.getAttribute('id');

                if (scrollPos >= top && scrollPos < top + height) {
                    dockPills.forEach(pill => {
                        if (pill.getAttribute('data-section') === id) {
                            pill.classList.add('is-active');
                        } else {
                            pill.classList.remove('is-active');
                        }
                    });
                }
            });
        }

        window.addEventListener('scroll', updateActiveDock, { passive: true });

        dockPills.forEach(pill => {
            pill.addEventListener('click', (e) => {
                e.preventDefault();
                const targetId = pill.getAttribute('href');
                const targetEl = document.querySelector(targetId);
                if (targetEl && lenis) {
                    lenis.scrollTo(targetEl, { offset: -20, duration: 1.2 });
                }
            });
        });
    }

    // ==========================================
    // 2. ISSUES PAGE LOGIC (100% SERVERLESS)
    // ==========================================
    if (isIssuesPage) {
        const issuesList = document.getElementById('issues-list');
        const issueForm = document.getElementById('issue-form');
        const feedbackDiv = document.getElementById('form-feedback');
        const submitBtn = document.getElementById('submit-issue-btn');
        const openModalBtn = document.getElementById('open-issue-modal-btn');
        const closeModalBtn = document.getElementById('close-issue-modal-btn');
        const modalOverlay = document.getElementById('issue-modal-overlay');
        const modalContent = document.getElementById('issue-modal-content');

        const REPO_URL = 'https://api.github.com/repos/cshariq/Sapphire';

        // GitHub's API does not expose which issues are pinned, so the repo's pinned
        // issues are mirrored here (including closed ones — GitHub keeps closed issues
        // pinned). An issue is also treated as pinned when it carries a "pinned" label,
        // which takes effect without any code change.
        const PINNED_ISSUE_NUMBERS = new Set([12, 53]);
        const isPinnedIssue = (issue) =>
            PINNED_ISSUE_NUMBERS.has(issue.number) ||
            (issue.labels || []).some(label => label.name.toLowerCase() === 'pinned');

        let issuesView = 'open'; // 'open' | 'closed'
        let cachedIssues = { open: [], closed: [] };

        const sortByNewest = (a, b) => new Date(b.created_at) - new Date(a.created_at);

        async function fetchIssues() {
            try {
                const [openRes, closedRes] = await Promise.all([
                    fetch(`${REPO_URL}/issues?state=open&per_page=50`),
                    fetch(`${REPO_URL}/issues?state=closed&per_page=100`)
                ]);
                if (!openRes.ok || !closedRes.ok) throw new Error('GitHub API response failed');

                cachedIssues.open = (await openRes.json()).filter(issue => !issue.pull_request);
                cachedIssues.closed = (await closedRes.json()).filter(issue => !issue.pull_request);
                renderIssues();
            } catch (error) {
                console.warn('GitHub API fetch fallback:', error);
                issuesList.innerHTML = `
                    <div class="p-8 text-center space-y-3 issues-glass-panel">
                        <p class="text-xs font-medium text-[var(--color-text-secondary)]">Unable to load live issue stream (API rate limit or offline).</p>
                        <a href="https://github.com/cshariq/Sapphire/issues" target="_blank" rel="noopener noreferrer" class="inline-flex items-center gap-1.5 text-xs font-bold text-blue-400 hover:underline">
                            View issues directly on GitHub <span class="material-symbols-outlined text-sm">open_in_new</span>
                        </a>
                    </div>
                `;
            }
        }

        function renderIssues() {
            issuesList.innerHTML = '';
            const { open, closed } = cachedIssues;

            // Pinned issues (open or closed) always lead the list
            const pinnedOpen = open.filter(isPinnedIssue).sort(sortByNewest);
            const pinnedClosed = closed.filter(isPinnedIssue).sort(sortByNewest);

            const visible = issuesView === 'closed'
                ? [...pinnedClosed, ...closed.filter(issue => !isPinnedIssue(issue)).sort(sortByNewest)]
                : [...pinnedOpen, ...pinnedClosed, ...open.filter(issue => !isPinnedIssue(issue)).sort(sortByNewest)];

            if (visible.length === 0) {
                const emptyMsg = issuesView === 'open'
                    ? 'No open issues found. Everything is running smoothly!'
                    : 'No closed issues found.';
                issuesList.innerHTML = `<div class="p-10 text-center text-xs font-medium text-[var(--color-text-secondary)] issues-glass-panel">${emptyMsg}</div>`;
                return;
            }

            visible.forEach(issue => {
                const pinned = isPinnedIssue(issue);
                const isClosed = issue.state === 'closed';

                const issueCard = document.createElement('a');
                issueCard.href = issue.html_url;
                issueCard.target = '_blank';
                issueCard.rel = 'noopener noreferrer';
                issueCard.className = `issue-card${pinned ? ' issue-card-pinned' : ''}${isClosed ? ' issue-card-closed' : ''}`;

                const labelsHtml = (issue.labels || []).map(label => {
                    const color = label.color || '888888';
                    return `<span class="label-badge" style="background-color: #${color}22; color: #${color}; border: 1px solid #${color}44;">${escapeHtml(label.name)}</span>`;
                }).join(' ');

                const updatedDate = new Date(issue.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

                const badges = [
                    pinned ? `<span class="inline-flex items-center gap-1 text-[9px] font-bold uppercase tracking-wider text-amber-400 bg-amber-400/10 border border-amber-400/30 px-2 py-0.5 rounded-full shrink-0"><span class="material-symbols-outlined text-[11px]">push_pin</span> Pinned</span>` : '',
                    isClosed ? `<span class="inline-flex items-center gap-1 text-[9px] font-bold uppercase tracking-wider text-purple-400 bg-purple-400/10 border border-purple-400/30 px-2 py-0.5 rounded-full shrink-0"><span class="material-symbols-outlined text-[11px]">check_circle</span> Closed</span>` : ''
                ].filter(Boolean).join(' ');

                issueCard.innerHTML = `
                    <div class="flex justify-between items-start gap-4">
                        <div class="min-w-0 flex-1">
                            <h3 class="font-bold text-sm text-[var(--color-text-primary)] hover:text-blue-400 transition-colors tracking-tight truncate">${escapeHtml(issue.title)}</h3>
                            <p class="text-xs text-[var(--color-text-secondary)] mt-1 font-medium">#${issue.number} opened on ${updatedDate} by ${escapeHtml(issue.user.login)}</p>
                        </div>
                        ${badges}
                        <span class="text-xs font-mono font-bold text-[var(--color-text-secondary)] shrink-0">#${issue.number}</span>
                    </div>
                    ${labelsHtml ? `<div class="flex gap-1.5 mt-3 flex-wrap">${labelsHtml}</div>` : ''}
                `;
                issuesList.appendChild(issueCard);
            });
        }

        function setIssuesView(view) {
            issuesView = view;
            const openBtn = document.getElementById('issues-view-open');
            const closedBtn = document.getElementById('issues-view-closed');
            const title = document.getElementById('issues-list-title');

            const activeCls = 'px-3.5 py-1.5 rounded-lg text-[9px] font-bold uppercase tracking-wider transition-colors bg-[var(--color-text-primary)] text-[var(--color-background)]';
            const inactiveCls = 'px-3.5 py-1.5 rounded-lg text-[9px] font-bold uppercase tracking-wider transition-colors text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)]';
            if (openBtn) openBtn.className = view === 'open' ? activeCls : inactiveCls;
            if (closedBtn) closedBtn.className = view === 'closed' ? activeCls : inactiveCls;
            if (title) title.textContent = view === 'open' ? 'Open GitHub Issues' : 'Closed Issues';
            renderIssues();
        }
        
        async function fetchRepoStats() {
            try {
                const response = await fetch(REPO_URL);
                if (!response.ok) throw new Error('Repository stats fetch failed');
                const repo = await response.json();
                
                const starsFormatted = repo.stargazers_count >= 1000 ? (repo.stargazers_count / 1000).toFixed(1) + 'k' : repo.stargazers_count;
                const forksFormatted = repo.forks_count >= 1000 ? (repo.forks_count / 1000).toFixed(1) + 'k' : repo.forks_count;

                ['stats-stars', 'stats-stars-mobile'].forEach(id => {
                    const el = document.getElementById(id);
                    if (el) el.textContent = starsFormatted;
                });
                ['stats-forks', 'stats-forks-mobile'].forEach(id => {
                    const el = document.getElementById(id);
                    if (el) el.textContent = forksFormatted;
                });
                ['stats-issues', 'stats-issues-mobile'].forEach(id => {
                    const el = document.getElementById(id);
                    if (el) el.textContent = repo.open_issues_count;
                });

                const releaseResponse = await fetch(`${REPO_URL}/releases/latest`);
                if (releaseResponse.ok) {
                    const latestRelease = await releaseResponse.json();
                    ['stats-latest-release', 'stats-latest-release-mobile'].forEach(id => {
                        const el = document.getElementById(id);
                        if (el) {
                            el.textContent = latestRelease.tag_name || 'v2.0.0';
                            el.href = latestRelease.html_url || 'https://github.com/cshariq/Sapphire/releases/latest';
                        }
                    });
                }
            } catch (error) {
                ['stats-stars', 'stats-stars-mobile'].forEach(id => { const el = document.getElementById(id); if (el) el.textContent = '100+'; });
                ['stats-forks', 'stats-forks-mobile'].forEach(id => { const el = document.getElementById(id); if (el) el.textContent = '12'; });
                ['stats-issues', 'stats-issues-mobile'].forEach(id => { const el = document.getElementById(id); if (el) el.textContent = '0'; });
                ['stats-latest-release', 'stats-latest-release-mobile'].forEach(id => { const el = document.getElementById(id); if (el) el.textContent = 'v2.0.0'; });
            }
        }

        // Serverless GitHub Issue URL Redirection
        if (issueForm) {
            issueForm.addEventListener('submit', (e) => {
                e.preventDefault();
                const title = document.getElementById('issue-title').value.trim();
                const body = document.getElementById('issue-body').value.trim();

                if (!title || !body) return;

                submitBtn.disabled = true;
                submitBtn.textContent = 'Opening GitHub...';
                feedbackDiv.textContent = 'Opening GitHub with your issue details...';

                const githubIssueUrl = `https://github.com/cshariq/Sapphire/issues/new?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`;

                setTimeout(() => {
                    window.open(githubIssueUrl, '_blank', 'noopener,noreferrer');
                    closeModal();
                    issueForm.reset();
                    submitBtn.disabled = false;
                    submitBtn.textContent = 'Continue to GitHub';
                    feedbackDiv.textContent = '';
                }, 600);
            });
        }

        function openModal() {
            if (!modalOverlay || !modalContent) return;
            modalOverlay.classList.remove('pointer-events-none');
            modalOverlay.style.opacity = '1';
            modalContent.style.opacity = '1';
            modalContent.style.transform = 'scale(1)';
            document.body.style.overflow = 'hidden';
        }

        function closeModal() {
            if (!modalOverlay || !modalContent) return;
            modalOverlay.style.opacity = '0';
            modalContent.style.opacity = '0';
            modalContent.style.transform = 'scale(0.95)';
            setTimeout(() => {
                modalOverlay.classList.add('pointer-events-none');
                document.body.style.overflow = '';
            }, 300);
        }

        if (openModalBtn) openModalBtn.addEventListener('click', openModal);
        if (closeModalBtn) closeModalBtn.addEventListener('click', closeModal);
        if (modalOverlay) {
            modalOverlay.addEventListener('click', (e) => {
                if (e.target === modalOverlay) closeModal();
            });
        }

        function escapeHtml(str) {
            const div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }

        const issuesViewOpenBtn = document.getElementById('issues-view-open');
        const issuesViewClosedBtn = document.getElementById('issues-view-closed');
        if (issuesViewOpenBtn) issuesViewOpenBtn.addEventListener('click', () => setIssuesView('open'));
        if (issuesViewClosedBtn) issuesViewClosedBtn.addEventListener('click', () => setIssuesView('closed'));

        fetchIssues();
        fetchRepoStats();
    }

    // ==========================================
    // 3. CHANGELOG PAGE LOGIC (SEPARATES STABLE VS BETA)
    // ==========================================
    if (isChangelogPage) {
        async function fetchReleases() {
            const latestReleaseContainer = document.getElementById('latest-release');
            const betaReleaseContainer = document.getElementById('beta-release-container');
            const betaReleaseSlot = document.getElementById('beta-release');
            const previousReleasesContainer = document.querySelector('#previous-releases .space-y-6');

            try {
                const response = await fetch('https://api.github.com/repos/cshariq/Sapphire/releases');
                if (!response.ok) throw new Error('Network response was not ok');
                const releases = await response.json();
                
                if (!Array.isArray(releases) || releases.length === 0) {
                    latestReleaseContainer.innerHTML = '<div class="changelog-glass-panel p-12 text-center text-xs font-medium text-[var(--color-text-secondary)]">No releases found.</div>';
                    document.getElementById('previous-releases').style.display = 'none';
                    return;
                }

                const formatBytes = (bytes, decimals = 2) => {
                    if (bytes === 0) return '0 Bytes';
                    const k = 1024;
                    const dm = decimals < 0 ? 0 : decimals;
                    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
                    const i = Math.floor(Math.log(bytes) / Math.log(k));
                    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
                };

                const renderRelease = (release, isBeta = false) => {
                    const releaseDate = new Date(release.published_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
                    const assets = (release.assets || []).map(asset => `
                        <a href="${asset.browser_download_url}" class="asset-link">
                            <span class="material-symbols-outlined text-base">download</span>
                            <span>${asset.name}</span>
                            <span class="text-[var(--color-text-secondary)] text-[10px]">(${formatBytes(asset.size)})</span>
                        </a>`).join('');

                    const betaNoticeHtml = isBeta ? `
                        <div class="bg-cyan-500/10 border border-cyan-500/20 rounded-2xl p-4 mb-5 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
                            <div class="flex items-center gap-2.5 text-xs text-cyan-300 font-semibold">
                                <span class="material-symbols-outlined text-base">lock_open</span>
                                <span>Beta builds are available exclusively to Basic, Pro & Ultra subscribers</span>
                            </div>
                            <a href="/subscribe" class="apple-cta-btn !py-1.5 !px-3 text-[11px] font-bold uppercase tracking-wider shrink-0">
                                Upgrade Plan
                            </a>
                        </div>
                    ` : '';

                    return `
                        <div class="release-item space-y-4 ${isBeta ? 'is-beta-item' : ''}">
                            ${betaNoticeHtml}
                            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-4 border-b border-[var(--color-card-border)]">
                                <div class="flex items-center gap-3 flex-wrap">
                                    <h2 class="text-2xl font-extrabold text-[var(--color-text-primary)] tracking-tight">${release.name || release.tag_name}</h2>
                                    ${isBeta ? '<span class="tier-pill-basic text-[9px]">Beta Build</span>' : ''}
                                </div>
                                <span class="text-xs font-mono text-[var(--color-text-secondary)]">${releaseDate}</span>
                            </div>
                            <div class="release-body">${marked.parse(release.body || '')}</div>
                            ${assets ? `<div class="flex gap-3 pt-4 flex-wrap border-t border-[var(--color-card-border)]">${assets}</div>` : ''}
                        </div>`;
                };

                // Find Latest Stable Release (not marked as prerelease and not containing 'beta' tag)
                let stableRelease = releases.find(r => !r.prerelease && !r.tag_name?.toLowerCase().includes('beta') && !r.name?.toLowerCase().includes('beta'));
                if (!stableRelease) stableRelease = releases[0];

                // Find Latest Beta Release
                const betaRelease = releases.find(r => r.prerelease || r.tag_name?.toLowerCase().includes('beta') || r.name?.toLowerCase().includes('beta'));

                // Render Latest Stable
                latestReleaseContainer.innerHTML = renderRelease(stableRelease, false);

                // Render Beta if available and distinct from stable
                if (betaRelease && betaRelease.id !== stableRelease.id) {
                    betaReleaseSlot.innerHTML = renderRelease(betaRelease, true);
                    betaReleaseContainer.classList.remove('hidden');
                }

                // Filter & Render Previous Releases
                const previousReleases = releases.filter(r => r.id !== stableRelease.id && (!betaRelease || r.id !== betaRelease.id));
                if (previousReleases.length > 0) {
                    previousReleasesContainer.innerHTML = previousReleases.map(r => renderRelease(r, r.prerelease)).join('');
                } else {
                    document.getElementById('previous-releases').style.display = 'none';
                }

            } catch (error) {
                latestReleaseContainer.innerHTML = '<div class="changelog-glass-panel p-12 text-center text-xs font-semibold text-red-400">Failed to load releases from GitHub.</div>';
                document.getElementById('previous-releases').style.display = 'none';
            }
        }
        fetchReleases();
    }

    // ==========================================
    // 4. GITHUB HOME STATS FETCHER
    // ==========================================
    async function fetchHomeStats() {
        const starsEl = document.getElementById('hero-stats-stars');
        const downloadsEl = document.getElementById('hero-stats-downloads');
        const statsContainer = document.getElementById('hero-stats');

        if (!starsEl || !downloadsEl || !statsContainer) return;

        try {
            const repoUrl = 'https://api.github.com/repos/cshariq/Sapphire';
            
            const [repoRes, releasesRes] = await Promise.all([
                fetch(repoUrl),
                fetch(`${repoUrl}/releases`)
            ]);

            if (repoRes.ok) {
                const repo = await repoRes.json();
                const stars = repo.stargazers_count;
                starsEl.textContent = stars >= 1000 ? (stars / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : stars;
            }

            if (releasesRes.ok) {
                const releases = await releasesRes.json();
                let totalDownloads = 0;
                releases.forEach(r => {
                    r.assets.forEach(a => { totalDownloads += a.download_count; });
                });
                downloadsEl.textContent = totalDownloads >= 1000 ? (totalDownloads / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : totalDownloads;
            }

            statsContainer.classList.remove('hidden');
            statsContainer.classList.add('flex');
        } catch (e) {
            console.error('Failed to load GitHub stats:', e);
        }
    }
    fetchHomeStats();
});
/* --- END OF FILE script.js --- */