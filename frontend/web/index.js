// ==============================================================================
// Chisel Town 1855 - Surveillance Feed Client Engine
// Connects to WebSocket /ws and renders 2:1 Isometric Terrarium with Swarm Lattice
// ==============================================================================

(function() {
    'use strict';

    // 1. Dynamic WebSocket URL Resolution
    function getWebSocketUrl() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.has('ws')) {
            return urlParams.get('ws');
        }

        const isHttps = window.location.protocol === 'https:';
        const wsProto = isHttps ? 'wss:' : 'ws:';
        const hostname = window.location.hostname;

        // If on chisel.town or subdomain in production:
        if (hostname === 'chisel.town' || hostname.endsWith('.chisel.town')) {
            // First preference: bob.chisel.town
            return `${wsProto}//bob.chisel.town/ws`;
        }

        // If running locally:
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            return `ws://${hostname}:7770/ws`;
        }

        // Generic fallback to host on port 7770 or standard /ws
        return `${wsProto}//${window.location.host}/ws`;
    }

    // State Variables
    let ws = null;
    let reconnectDelay = 1000;
    let latestState = null;
    let carlCurrentPos = { x: 10.0, y: 10.0 };
    let carlTrail = [];

    // DOM Elements
    const statusBadge = document.getElementById('status-badge');
    const statusText = document.getElementById('status-text');
    const connectOverlay = document.getElementById('connect-overlay');
    const connectDesc = document.getElementById('connect-desc');
    const subQuoteText = document.getElementById('sub-quote-text');
    const valCohesion = document.getElementById('val-cohesion');
    const barCohesion = document.getElementById('bar-cohesion');
    const valParanoia = document.getElementById('val-paranoia');
    const barParanoia = document.getElementById('bar-paranoia');
    const valPressure = document.getElementById('val-pressure');
    const barPressure = document.getElementById('bar-pressure');
    const feedBob = document.getElementById('feed-bob');
    const feedChronicler = document.getElementById('feed-chronicler');
    const valElapsed = document.getElementById('val-elapsed');

    const stepDecanting = document.getElementById('step-decanting');
    const stepWandering = document.getElementById('step-wandering');
    const stepDig = document.getElementById('step-dig');
    const stepCollapse = document.getElementById('step-collapse');

    // Canvas Setup
    const canvas = document.getElementById('iso-canvas');
    const ctx = canvas.getContext('2d');

    function resizeCanvas() {
        const rect = canvas.parentElement.getBoundingClientRect();
        canvas.width = rect.width * window.devicePixelRatio;
        canvas.height = rect.height * window.devicePixelRatio;
        ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    // 2. SwarmLattice C++ Algorithm Parity in JS
    // Murmur3 32-bit finalizer hash
    function murmur3Finalize(h) {
        h = Math.imul(h ^ (h >>> 16), 0x85ebca6b);
        h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
        return (h ^ (h >>> 16)) >>> 0;
    }

    // Computes block displacement based on Cohesion decay and Pressure surge
    function computeMorphology(cohesion, pressure, blockId) {
        if (cohesion >= 1.0 && pressure <= 0.0) {
            return { offsetX: 0, offsetY: 0, heightWarp: 0 };
        }

        const decay = Math.max(0.0, Math.min(1.0, 1.0 - cohesion));
        const normPressure = Math.max(0.0, Math.min(1.0, pressure / 4.0));
        const stress = (decay * 0.7) + (normPressure * 0.3);

        const h1 = murmur3Finalize((blockId * 0x9e3779b9) >>> 0);
        const h2 = murmur3Finalize((h1 ^ 0x85ebca6b) >>> 0);
        const h3 = murmur3Finalize((h2 ^ 0xc2b2ae35) >>> 0);

        const u1 = h1 / 4294967295.0;
        const u2 = h2 / 4294967295.0;
        const u3 = h3 / 4294967295.0;

        const maxDisp = 18.0 * (stress * stress);
        const phi = u1 * 2.0 * Math.PI;
        const theta = (0.15 + 0.70 * u2) * Math.PI;

        return {
            offsetX: maxDisp * Math.sin(theta) * Math.cos(phi),
            offsetY: maxDisp * Math.sin(theta) * Math.sin(phi) * 0.5,
            heightWarp: maxDisp * Math.cos(theta) * 0.6 + (u3 - 0.5) * stress * 6.0
        };
    }

    // 2:1 Isometric Coordinate Projection
    const TILE_W = 44.0;
    const TILE_H = 22.0;

    function worldToIso(gx, gy) {
        return {
            x: (gx - gy) * (TILE_W / 2.0),
            y: (gx + gy) * (TILE_H / 2.0)
        };
    }

    // 3. WebSocket Connection & State Handling
    function connect() {
        const wsUrl = getWebSocketUrl();
        console.log(`[Chisel Town 1855] Connecting to WebSocket: ${wsUrl}`);
        if (connectDesc) connectDesc.textContent = `Connecting to ${wsUrl}...`;

        try {
            ws = new WebSocket(wsUrl);
        } catch (e) {
            console.error('[Chisel Town 1855] Failed to create WebSocket:', e);
            scheduleReconnect();
            return;
        }

        ws.onopen = function() {
            console.log('[Chisel Town 1855] WebSocket connected successfully!');
            reconnectDelay = 1000;
            statusBadge.className = 'status-badge';
            statusText.textContent = 'FEED: LIVE // CONNECTED';
            connectOverlay.classList.add('hidden');
        };

        ws.onmessage = function(event) {
            try {
                const data = JSON.parse(event.data);
                handleWorldState(data);
            } catch (err) {
                console.error('[Chisel Town 1855] Error parsing frame JSON:', err);
            }
        };

        ws.onclose = function(e) {
            console.warn('[Chisel Town 1855] WebSocket connection closed:', e.code, e.reason);
            statusBadge.className = 'status-badge connecting';
            statusText.textContent = 'DISCONNECTED // RECONNECTING';
            connectOverlay.classList.remove('hidden');
            if (connectDesc) connectDesc.textContent = `Connection lost. Reconnecting in ${Math.round(reconnectDelay / 1000)}s...`;
            scheduleReconnect();
        };

        ws.onerror = function(err) {
            console.error('[Chisel Town 1855] WebSocket error encountered:', err);
            ws.close();
        };
    }

    function scheduleReconnect() {
        setTimeout(connect, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 1.5, 10000);
    }

    function formatTime(seconds) {
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }

    function handleWorldState(state) {
        latestState = state;

        // Reset trail upon cycle renewal
        if (state.phase === 'ColdReset' || (state.phase === 'Decanting' && state.elapsed_seconds < 1.0)) {
            carlTrail = [];
            carlCurrentPos = { x: state.carl_position[0], y: state.carl_position[1] };
        }

        // Update DOM Telemetry
        valCohesion.textContent = `${(state.town_cohesion * 100).toFixed(1)}%`;
        barCohesion.style.width = `${Math.max(0, Math.min(100, state.town_cohesion * 100))}%`;

        valParanoia.textContent = `${(state.carl_paranoia * 100).toFixed(1)}%`;
        barParanoia.style.width = `${Math.max(0, Math.min(100, state.carl_paranoia * 100))}%`;
        if (state.carl_paranoia > 0.75) {
            valParanoia.style.color = 'var(--danger-red)';
            barParanoia.style.background = 'var(--danger-red)';
        } else if (state.carl_paranoia > 0.45) {
            valParanoia.style.color = 'var(--amber-accent)';
            barParanoia.style.background = 'var(--amber-accent)';
        } else {
            valParanoia.style.color = 'var(--cyan-accent)';
            barParanoia.style.background = 'var(--cyan-accent)';
        }

        valPressure.textContent = `${state.subterranean_pressure.toFixed(2)} MPa`;
        barPressure.style.width = `${Math.min(100, (state.subterranean_pressure / 4.5) * 100)}%`;

        if (feedBob && state.bob_transmission) feedBob.textContent = `"${state.bob_transmission}"`;
        if (feedChronicler && state.chronicler_log) feedChronicler.textContent = `"${state.chronicler_log}"`;
        if (subQuoteText && state.active_quote) subQuoteText.textContent = `"${state.active_quote}"`;
        if (valElapsed) valElapsed.textContent = formatTime(state.elapsed_seconds);

        // Update Phase Markers
        [stepDecanting, stepWandering, stepDig, stepCollapse].forEach(el => el.classList.remove('active'));
        if (state.phase === 'Decanting') stepDecanting.classList.add('active');
        else if (state.phase === 'MurkWandering') stepWandering.classList.add('active');
        else if (state.phase === 'TheDig') stepDig.classList.add('active');
        else stepCollapse.classList.add('active');
    }

    // 4. Drawing & Animation Loop
    function render() {
        const width = canvas.width / window.devicePixelRatio;
        const height = canvas.height / window.devicePixelRatio;

        ctx.clearRect(0, 0, width, height);

        // Origin at center-left
        const originX = width * 0.48;
        const originY = height * 0.22;

        const cohesion = latestState ? latestState.town_cohesion : 0.90;
        const pressure = latestState ? latestState.subterranean_pressure : 2.10;

        // 1. Draw Terrarium Floor Grid (40x40 Diamond)
        ctx.lineWidth = 1;
        ctx.strokeStyle = '#141d2b';

        for (let gx = 0; gx <= 60; gx += 5) {
            const p1 = worldToIso(gx, 0);
            const p2 = worldToIso(gx, 60);
            ctx.beginPath();
            ctx.moveTo(originX + p1.x, originY + p1.y);
            ctx.lineTo(originX + p2.x, originY + p2.y);
            ctx.stroke();
        }
        for (let gy = 0; gy <= 60; gy += 5) {
            const p1 = worldToIso(0, gy);
            const p2 = worldToIso(60, gy);
            ctx.beginPath();
            ctx.moveTo(originX + p1.x, originY + p1.y);
            ctx.lineTo(originX + p2.x, originY + p2.y);
            ctx.stroke();
        }

        // 2. Draw Landmark Structures with Swarm Morphology
        function drawSwarmBlock(gx, gy, w, h, heightExtrude, fillColor, strokeColor, blockId, label) {
            const morph = computeMorphology(cohesion, pressure, blockId);
            const base = worldToIso(gx, gy);
            const bx = originX + base.x + morph.offsetX;
            const by = originY + base.y + morph.offsetY;
            const z = heightExtrude + morph.heightWarp;

            const pTop = worldToIso(0, 0);
            const pRight = worldToIso(w, 0);
            const pBottom = worldToIso(w, h);
            const pLeft = worldToIso(0, h);

            // Roof Polygon
            ctx.fillStyle = fillColor;
            ctx.strokeStyle = strokeColor;
            ctx.beginPath();
            ctx.moveTo(bx + pTop.x, by + pTop.y - z);
            ctx.lineTo(bx + pRight.x, by + pRight.y - z);
            ctx.lineTo(bx + pBottom.x, by + pBottom.y - z);
            ctx.lineTo(bx + pLeft.x, by + pLeft.y - z);
            ctx.closePath();
            ctx.fill();
            ctx.stroke();

            // Front Left Wall
            ctx.fillStyle = 'rgba(10, 16, 26, 0.85)';
            ctx.beginPath();
            ctx.moveTo(bx + pLeft.x, by + pLeft.y);
            ctx.lineTo(bx + pLeft.x, by + pLeft.y - z);
            ctx.lineTo(bx + pBottom.x, by + pBottom.y - z);
            ctx.lineTo(bx + pBottom.x, by + pBottom.y);
            ctx.closePath();
            ctx.fill();
            ctx.stroke();

            // Front Right Wall
            ctx.fillStyle = 'rgba(18, 28, 44, 0.85)';
            ctx.beginPath();
            ctx.moveTo(bx + pBottom.x, by + pBottom.y);
            ctx.lineTo(bx + pBottom.x, by + pBottom.y - z);
            ctx.lineTo(bx + pRight.x, by + pRight.y - z);
            ctx.lineTo(bx + pRight.x, by + pRight.y);
            ctx.closePath();
            ctx.fill();
            ctx.stroke();

            if (label) {
                ctx.fillStyle = '#7e95b0';
                ctx.font = '10px monospace';
                ctx.textAlign = 'center';
                ctx.fillText(label, bx + pBottom.x * 0.5, by + pBottom.y * 0.5 - z - 6);
            }
        }

        // Decanting Lab (Bay-01)
        drawSwarmBlock(6, 6, 8, 8, 38, '#263b57', '#00f0ff', 101, 'DECANTING LAB [BAY-01]');

        // Rustbowl Hall (Timber & Cobblestone 1855)
        drawSwarmBlock(26, 16, 10, 10, 52, '#38485e', '#ffaa00', 102, 'RUSTBOWL HALL [SECTOR-B]');

        // Murk Hazard Pit (Subterranean Fissure)
        const murkBase = worldToIso(50, 50);
        const mx = originX + murkBase.x;
        const my = originY + murkBase.y;

        ctx.fillStyle = '#05070a';
        ctx.strokeStyle = '#ff3344';
        ctx.beginPath();
        ctx.ellipse(mx, my, 70, 35, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = 'rgba(255, 51, 68, 0.15)';
        ctx.beginPath();
        ctx.ellipse(mx, my, 45, 22, 0, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = '#ff3344';
        ctx.font = '10px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('SUBTERRANEAN HAZARD // CRUDE SEEPAGE', mx, my + 48);

        // 3. Draw Carl 01 and Smooth Movement
        if (latestState && latestState.carl_position) {
            const targetX = latestState.carl_position[0];
            const targetY = latestState.carl_position[1];

            carlCurrentPos.x += (targetX - carlCurrentPos.x) * 0.12;
            carlCurrentPos.y += (targetY - carlCurrentPos.y) * 0.12;

            // Trail Breadcrumbs
            if (carlTrail.length === 0 || Math.hypot(carlCurrentPos.x - carlTrail[carlTrail.length - 1].x, carlCurrentPos.y - carlTrail[carlTrail.length - 1].y) > 0.6) {
                carlTrail.push({ x: carlCurrentPos.x, y: carlCurrentPos.y });
                if (carlTrail.length > 50) carlTrail.shift();
            }

            // Draw Trail
            if (carlTrail.length > 1) {
                ctx.strokeStyle = 'rgba(0, 240, 255, 0.4)';
                ctx.lineWidth = 2;
                ctx.beginPath();
                for (let i = 0; i < carlTrail.length; i++) {
                    const tp = worldToIso(carlTrail[i].x, carlTrail[i].y);
                    if (i === 0) ctx.moveTo(originX + tp.x, originY + tp.y);
                    else ctx.lineTo(originX + tp.x, originY + tp.y);
                }
                ctx.stroke();
            }

            // Draw Carl Entity Dot & Reticle
            const cp = worldToIso(carlCurrentPos.x, carlCurrentPos.y);
            const cx = originX + cp.x;
            const cy = originY + cp.y;

            // Reticle Target Box
            ctx.strokeStyle = '#00f0ff';
            ctx.lineWidth = 1.5;
            ctx.strokeRect(cx - 10, cy - 10, 20, 20);

            // Blinking Center Dot
            ctx.fillStyle = '#00ff66';
            ctx.beginPath();
            ctx.arc(cx, cy, 4, 0, Math.PI * 2);
            ctx.fill();

            // Label
            ctx.fillStyle = '#00f0ff';
            ctx.font = '10px monospace';
            ctx.textAlign = 'center';
            ctx.fillText('CARL 01 [TRACKED]', cx, cy - 16);
        }

        requestAnimationFrame(render);
    }

    // Initialize
    connect();
    requestAnimationFrame(render);

})();
