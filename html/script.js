/* ============================================================
   Snowman Killfeed Status — NUI logic
   Author: Snowman
   ============================================================ */

const RESOURCE =
    (window.location.hostname || '').replace('cfx-nui-', '') || 'snowman_killfeed';

const DEFAULT_AVATAR = 'https://cdn.discordapp.com/embed/avatars/0.png';

/* ---------- State ---------- */
let CONFIG = {};
let kills = [];           // newest-first
let selectedKillId = null;
let selectedSide = 'killer'; // which party shows as the main profile
let searchTerm = '';
let filterValue = 'all';

/* ---------- DOM ---------- */
const $ = (id) => document.getElementById(id);
const app = $('app');

/* ---------- NUI bridge ---------- */
function post(name, data = {}) {
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));
}

/* ---------- Helpers ---------- */
function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function timeAgo(unix) {
    const diff = Math.max(0, Math.floor(Date.now() / 1000) - (unix || 0));
    if (diff < 5) return 'just now';
    if (diff < 60) return `${diff}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
}

function fmtMoney(n) {
    return '$' + (Number(n) || 0).toLocaleString('en-US');
}

function fmtCoords(c) {
    if (!c) return '0, 0, 0';
    return `${c.x ?? 0}, ${c.y ?? 0}, ${c.z ?? 0}`;
}

function avatarOf(party) {
    if (party && party.discord && party.discord.avatarUrl) return party.discord.avatarUrl;
    return DEFAULT_AVATAR;
}

function iconFor(cat) {
    return (CONFIG.categoryIcons && CONFIG.categoryIcons[cat]) || 'fa-solid fa-skull';
}

/* ---------- Ripple ---------- */
function ripple(e) {
    const el = e.currentTarget;
    const r = el.getBoundingClientRect();
    const size = Math.max(r.width, r.height);
    const span = document.createElement('span');
    span.className = 'ripple';
    span.style.width = span.style.height = `${size}px`;
    span.style.left = `${e.clientX - r.left - size / 2}px`;
    span.style.top = `${e.clientY - r.top - size / 2}px`;
    el.appendChild(span);
    setTimeout(() => span.remove(), 500);
}

/* ---------- Toast ---------- */
function toast(msg) {
    let t = $('toast');
    if (!t) {
        t = document.createElement('div');
        t.id = 'toast';
        document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), 1600);
}

function copyText(text, label) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
    post('copy', { text });
    toast(`${label || 'Copied'} ✓`);
}

/* ============================================================
   FEED (left column)
   ============================================================ */

function killerLabel(k) {
    if (!k.killer) return 'Environment';
    return k.killer.name;
}

function matchesFilter(k) {
    if (filterValue === 'all') return true;
    if (filterValue === 'suicide') return !!k.suicide;
    if (filterValue === 'vehicle') return !!k.vehicleKill || k.category === 'vehicle';
    if (filterValue === 'explosion') return !!k.explosion || k.category === 'explosion';
    return k.category === filterValue;
}

function matchesSearch(k) {
    if (!searchTerm) return true;
    const t = searchTerm.toLowerCase();
    const parts = [
        k.weaponLabel,
        killerLabel(k),
        k.victim && k.victim.name,
        k.killer && k.killer.license,
        k.victim && k.victim.license,
        k.killer && k.killer.discordId,
        k.victim && k.victim.discordId,
        k.killer && k.killer.discord && k.killer.discord.username,
        k.victim && k.victim.discord && k.victim.discord.username,
    ];
    return parts.some((p) => p && String(p).toLowerCase().includes(t));
}

function badgeRow(k) {
    let html = '';
    if (k.headshot)    html += `<div class="b hs"  title="Headshot"><i class="fa-solid fa-bullseye"></i></div>`;
    if (k.vehicleKill) html += `<div class="b veh" title="Vehicle Kill"><i class="fa-solid fa-car-burst"></i></div>`;
    if (k.explosion)   html += `<div class="b exp" title="Explosion"><i class="fa-solid fa-bomb"></i></div>`;
    if (k.suicide)     html += `<div class="b sui" title="Suicide"><i class="fa-solid fa-skull"></i></div>`;
    return html ? `<div class="badge-row">${html}</div>` : '';
}

function killCard(k) {
    const killerAv = avatarOf(k.killer);
    const victimAv = avatarOf(k.victim);
    const active = k.id === selectedKillId ? 'active' : '';
    return `
    <div class="kcard ${active}" data-id="${k.id}">
        <span class="kid">#${k.id}</span>
        <div class="duo">
            <img class="av killer" src="${esc(killerAv)}" onerror="this.src='${DEFAULT_AVATAR}'" />
            <span class="vs"><i class="fa-solid fa-bolt"></i></span>
            <img class="av victim" src="${esc(victimAv)}" onerror="this.src='${DEFAULT_AVATAR}'" />
        </div>
        <div class="kmid">
            <div class="knames">
                <span class="k">${esc(killerLabel(k))}</span>
                <span class="arrow"><i class="fa-solid fa-skull"></i></span>
                <span class="v">${esc(k.victim ? k.victim.name : 'Unknown')}</span>
            </div>
            <div class="kmeta">
                <span class="chip weapon"><i class="${iconFor(k.category)}"></i> ${esc(k.weaponLabel)}</span>
                <span class="chip"><i class="fa-solid fa-ruler-horizontal"></i> ${k.distance}m</span>
                <span class="chip"><i class="fa-regular fa-clock"></i> ${timeAgo(k.time)}</span>
                ${badgeRow(k)}
            </div>
        </div>
    </div>`;
}

function renderFeed() {
    const feed = $('feed');
    const empty = $('feed-empty');
    const list = kills.filter((k) => matchesFilter(k) && matchesSearch(k));

    $('kill-count').textContent = list.length;

    if (list.length === 0) {
        feed.innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');
    feed.innerHTML = list.map(killCard).join('');

    feed.querySelectorAll('.kcard').forEach((el) => {
        el.addEventListener('click', () => selectKill(Number(el.dataset.id)));
    });
}

/* Prepend a single new kill with animation, respecting filters. */
function addKill(k) {
    kills.unshift(k);
    if (CONFIG.maxHistory && kills.length > CONFIG.maxHistory) kills.pop();

    // Refresh times on existing cards cheaply by re-rendering the visible list.
    renderFeed();
}

/* ============================================================
   PROFILE (right column)
   ============================================================ */

function statCard(icon, value, label) {
    return `<div class="stat"><div class="si"><i class="${icon}"></i></div>
        <div class="sv">${esc(value)}</div><div class="sl">${esc(label)}</div></div>`;
}

function infoCard(icon, label, value, copyVal) {
    const copy = copyVal
        ? `<i class="fa-regular fa-copy copy" data-copy="${esc(copyVal)}" data-label="${esc(label)}"></i>`
        : '';
    return `<div class="info"><div class="ii"><i class="${icon}"></i></div>
        <div class="it"><div class="il">${esc(label)}</div>
        <div class="iv"><span>${esc(value)}</span>${copy}</div></div></div>`;
}

function duelSide(side, party, kill) {
    const cls = side === 'killer' ? 'killer' : 'victim';
    const active = selectedSide === side ? ' active' : '';
    const title = side === 'killer'
        ? `<i class="fa-solid fa-crosshairs"></i> Killer`
        : `<i class="fa-solid fa-skull"></i> Victim`;
    if (!party) {
        return `<div class="duel-side ${cls}"><h4>${title}</h4>
            <div class="duel-row"><span class="dl">—</span><span class="dv">Environment</span></div></div>`;
    }
    const row = (l, v) => `<div class="duel-row"><span class="dl">${l}</span><span class="dv">${esc(v)}</span></div>`;
    return `<div class="duel-side ${cls}${active}" data-side="${side}"><h4>${title}</h4>
        ${row('Name', party.name)}
        ${row('ID', party.serverId ?? '—')}
        ${row('Weapon', side === 'killer' ? kill.weaponLabel : (party.weapon || '—'))}
        ${row('Distance', kill.distance + 'm')}
        ${row('Health', (party.health ?? 0) + '%')}
        ${row('Armor', (party.armor ?? 0) + '%')}
        ${row('Vehicle', party.vehicle || 'On Foot')}
        ${row('Job', party.job || '—')}
        ${row('Discord', (party.discord && party.discord.username) || '—')}
        ${row('Coords', fmtCoords(party.coords))}
    </div>`;
}

function renderDuel(kill) {
    const duel = $('duel');
    duel.innerHTML = `
        ${duelSide('killer', kill.suicide ? kill.victim : kill.killer, kill)}
        <div class="duel-mid"><i class="fa-solid fa-bolt"></i></div>
        ${duelSide('victim', kill.victim, kill)}`;

    // Clicking a side re-inspects that party's live profile.
    duel.querySelectorAll('.duel-side[data-side]').forEach((el) => {
        el.addEventListener('click', () => {
            const side = el.dataset.side;
            const target = side === 'victim' ? kill.victim : (kill.killer || kill.victim);
            if (target) selectKill(kill.id, side);
        });
    });
}

function renderTimeline(kill) {
    const items = kills
        .filter((k) => matchesFilter(k) && matchesSearch(k))
        .slice(0, 8);
    $('timeline').innerHTML = items.map((k) => {
        const current = k.id === kill.id ? ' current' : '';
        return `
        <div class="tl-item">
            <div class="tl-dot${current}"></div>
            <div class="tl-body">
                <div class="tl-time">${esc(k.timeString)}</div>
                <div class="tl-text">
                    <span class="k">${esc(killerLabel(k))}</span> killed
                    <span class="v">${esc(k.victim ? k.victim.name : 'Unknown')}</span>
                    using <span class="w">${esc(k.weaponLabel)}</span>
                </div>
                <div class="tl-meta">
                    <span class="chip">Distance ${k.distance}m</span>
                    <span class="chip">Headshot ${k.headshot ? 'YES' : 'NO'}</span>
                    <span class="chip">Vehicle ${k.vehicleKill ? 'YES' : 'NO'}</span>
                </div>
            </div>
        </div>`;
    }).join('');
}

function renderActions(kill) {
    const killerId = (kill.killer && kill.killer.serverId) || null;
    const victimId = (kill.victim && kill.victim.serverId) || null;
    const A = (CONFIG.adminActions || {});

    const btn = (cls, icon, label, action, targetId) =>
        targetId
            ? `<div class="act ${cls}" data-action="${action}" data-target="${targetId}">
                 <i class="${icon}"></i> ${label}</div>`
            : '';

    $('actions').innerHTML = [
        btn('blue',  'fa-solid fa-location-arrow', 'TP to Killer', 'teleportToKiller', killerId),
        btn('blue',  'fa-solid fa-location-crosshairs', 'TP to Victim', 'teleportToVictim', victimId),
        btn('gold',  'fa-solid fa-hand', 'Bring Killer', 'bringKiller', killerId),
        btn('gold',  'fa-solid fa-hand', 'Bring Victim', 'bringVictim', victimId),
        btn('green', 'fa-solid fa-kit-medical', 'Heal', 'heal', killerId || victimId),
        btn('green', 'fa-solid fa-heart-pulse', 'Revive', 'revive', victimId || killerId),
    ].filter(Boolean).join('');

    $('actions').querySelectorAll('.act').forEach((el) => {
        el.addEventListener('click', (e) => {
            ripple(e);
            post('adminAction', {
                action: el.dataset.action,
                targetId: Number(el.dataset.target),
            });
            toast('Action sent');
        });
    });
}

/* Renders the main Discord-style profile from a detailed profile object. */
function renderProfile(p, party, kill) {
    $('profile-empty').classList.add('hidden');
    $('profile').classList.remove('hidden');

    const d = (party && party.discord) || (p && p.discord) || {};
    const banner = $('profile-banner');
    if (d.bannerUrl) {
        banner.style.backgroundImage = `url('${d.bannerUrl}')`;
    } else if (d.bannerColor) {
        banner.style.backgroundImage = 'none';
        banner.style.background = d.bannerColor;
    } else {
        // Flat neutral header — no decorative gradient.
        banner.style.backgroundImage = 'none';
        banner.style.background = '#14161a';
    }

    const avatar = $('profile-avatar');
    avatar.src = (d.avatarUrl) || avatarOf(party);
    avatar.onerror = () => { avatar.src = DEFAULT_AVATAR; };

    $('p-display').textContent = d.displayName || d.username || p.characterName || p.name || 'Unknown';
    $('p-username').textContent = d.username ? `@${d.username}` : (p.name || '');

    // Status badges
    const status = p.status || 'Offline';
    const dot = $('status-dot');
    dot.className = 'profile-status-dot ' + (p.online ? (status === 'Dead' ? 'dead' : 'online') : '');
    $('p-badges').innerHTML = `
        <span class="tag ${status === 'Alive' ? 'alive' : status === 'Dead' ? 'dead' : 'offline'}">
            <i class="fa-solid fa-heart-pulse"></i> ${esc(status)}</span>
        <span class="tag ${p.online ? 'online' : 'offline'}">
            <i class="fa-solid fa-circle" style="font-size:8px"></i> ${p.online ? 'Online' : 'Offline'}</span>`;

    const s = p.stats || {};
    $('stats-grid').innerHTML = [
        statCard('fa-solid fa-crosshairs', s.kills ?? 0, 'Kills'),
        statCard('fa-solid fa-skull', s.deaths ?? 0, 'Deaths'),
        statCard('fa-solid fa-bullseye', s.headshots ?? 0, 'Headshots'),
    ].join('');

    // Death-location coords captured at the moment of the kill (not live).
    const killerCoords = kill.killer ? fmtCoords(kill.killer.coords) : '—';
    const victimCoords = kill.victim ? fmtCoords(kill.victim.coords) : '—';

    $('info-grid').innerHTML = [
        infoCard('fa-brands fa-discord', 'Discord ID', p.discordId || '—', p.discordId),
        infoCard('fa-solid fa-id-badge', 'License', p.license || '—', p.license),
        infoCard('fa-solid fa-signal', 'Ping', (p.ping ?? 0) + ' ms'),
        infoCard('fa-solid fa-briefcase', 'Job', `${p.job || '—'} ${p.jobGrade ? '(' + p.jobGrade + ')' : ''}`),
        infoCard('fa-solid fa-money-bill', 'Money', fmtMoney(p.money)),
        infoCard('fa-solid fa-building-columns', 'Bank', fmtMoney(p.bank)),
        infoCard('fa-solid fa-user', 'Character', p.characterName || '—'),
        infoCard('fa-solid fa-heart', 'Health', (p.health ?? 0) + '%'),
        infoCard('fa-solid fa-shield-halved', 'Armor', (p.armor ?? 0) + '%'),
        infoCard('fa-solid fa-car', 'Vehicle', p.vehicle || 'On Foot'),
        infoCard('fa-solid fa-gun', 'Weapon', p.weapon || 'Unarmed'),
        infoCard('fa-solid fa-location-crosshairs', 'Killer Coords', killerCoords, kill.killer ? killerCoords : null),
        infoCard('fa-solid fa-location-dot', 'Victim Coords', victimCoords, kill.victim ? victimCoords : null),
    ].join('');

    // Wire copy buttons
    $('info-grid').querySelectorAll('.copy').forEach((el) => {
        el.addEventListener('click', (e) => {
            e.stopPropagation();
            copyText(el.dataset.copy, el.dataset.label);
        });
    });

    renderDuel(kill);
    renderTimeline(kill);
    renderActions(kill);
}

/* Selects a kill, fetches the live profile for the chosen side. */
async function selectKill(id, side) {
    const kill = kills.find((k) => k.id === id);
    if (!kill) return;
    selectedKillId = id;
    selectedSide = side || 'killer';

    // Highlight the active card
    document.querySelectorAll('.kcard').forEach((el) =>
        el.classList.toggle('active', Number(el.dataset.id) === id));

    // Pick the party to profile: killer by default (victim on suicide / no killer)
    let party = selectedSide === 'victim' ? kill.victim : (kill.killer || kill.victim);
    if (kill.suicide) party = kill.victim;

    // Show stored data instantly, then refresh with a live fetch.
    const provisional = {
        online: party.online,
        status: party.online ? 'Alive' : 'Offline',
        name: party.name,
        characterName: party.name,
        discord: party.discord,
        discordId: party.discordId,
        license: party.license,
        ping: party.ping,
        job: party.job, jobGrade: party.jobGrade,
        money: 0, bank: 0,
        health: party.health, armor: party.armor,
        vehicle: party.vehicle, weapon: party.weapon,
        stats: {},
    };
    renderProfile(provisional, party, kill);

    const live = await post('fetchProfile', {
        serverId: party.serverId || null,
        fallback: party,
    });
    // Only apply if the user hasn't switched away meanwhile.
    if (selectedKillId === id && live && Object.keys(live).length) {
        renderProfile(live, party, kill);
    }
}

/* ============================================================
   ON-SCREEN KILLFEED (HUD overlay — independent of the admin panel)
   ============================================================ */

const KF_LEAVE_MS = 260;

function removeKfRow(row) {
    if (!row || row._removing) return;
    row._removing = true;
    clearTimeout(row._timer);
    row.classList.remove('kf-in');
    row.classList.add('kf-out');
    setTimeout(() => row.remove(), KF_LEAVE_MS);
}

function killfeedRow(entry) {
    const showAv = entry.showAvatars !== false;
    const icon = entry.icon || 'fa-solid fa-skull';

    let wClass = 'kf-weapon';
    if (entry.headshot) wClass += ' headshot';
    if (entry.explosion) wClass += ' explosion';
    if (entry.vehicleKill) wClass += ' vehicle';

    const nameEl = (party, cls) => {
        const av = (showAv && party && party.avatar)
            ? `<img class="kf-av" src="${esc(party.avatar)}" onerror="this.remove()" />`
            : '';
        const label = party ? party.name : 'Unknown';
        return `<span class="kf-name ${cls}">${av}<span class="kf-txt">${esc(label)}</span></span>`;
    };

    const weapon = `<span class="${wClass}"><i class="${esc(icon)}"></i> ${esc(entry.weaponLabel || '')}</span>`;
    const hs = entry.headshot
        ? '<span class="kf-flag hs" title="Headshot"><i class="fa-solid fa-bullseye"></i></span>'
        : '';
    const dist = (entry.showDistance !== false && entry.distance)
        ? `<span class="kf-dist">${esc(entry.distance)}m</span>`
        : '';

    const row = document.createElement('div');
    row.className = 'kf-row kf-in';
    if (entry.killer && !entry.suicide) {
        // Killer  →  [weapon]  →  Victim
        row.innerHTML = nameEl(entry.killer, 'killer') + weapon + nameEl(entry.victim, 'victim') + hs + dist;
    } else {
        // Suicide / environment: cause icon  →  Victim
        row.innerHTML = weapon + nameEl(entry.victim, 'victim') + hs;
    }
    return row;
}

const KF_POSITIONS = ['top-right', 'top-left', 'bottom-right', 'bottom-left'];

function addKillfeed(entry) {
    if (!entry) return;
    if (!KF_PREF.enabled) return;            // admin toggled the overlay off
    const kf = $('killfeed');
    if (!kf) return;

    // Admin's chosen position wins; fall back to the server/config default.
    const pos = KF_PREF.position
        || (KF_POSITIONS.includes(entry.position) ? entry.position : 'top-right');
    kf.className = `killfeed killfeed--${pos}`;

    const row = killfeedRow(entry);
    kf.insertBefore(row, kf.firstChild);   // newest first

    // Cap the number of simultaneous entries. Remove overflow rows IMMEDIATELY
    // (not via the animated remover) — otherwise the deferred removal keeps the
    // node in the DOM and this loop would never terminate, freezing the NUI.
    const max = Math.max(1, entry.maxShown || 5);
    while (kf.children.length > max) {
        const oldest = kf.lastElementChild;
        if (!oldest) break;
        clearTimeout(oldest._timer);
        oldest.remove();
    }

    row._timer = setTimeout(() => removeKfRow(row), entry.duration || 6000);
}

/* ---------- Killfeed preferences (per-admin, saved locally) ---------- */
const KF_PREF = { enabled: true, position: 'top-right' };

function loadKfPref() {
    try {
        const raw = localStorage.getItem('killfeedPref');
        if (raw) Object.assign(KF_PREF, JSON.parse(raw));
    } catch (e) {}
    if (!KF_POSITIONS.includes(KF_PREF.position)) KF_PREF.position = 'top-right';
}

function saveKfPref() {
    try { localStorage.setItem('killfeedPref', JSON.stringify(KF_PREF)); } catch (e) {}
}

function applyKfPref() {
    // Reflect state on the overlay container.
    $('killfeed').className = `killfeed killfeed--${KF_PREF.position}`;

    // Reflect state on the settings controls.
    const toggle = $('kf-toggle');
    if (toggle) {
        toggle.classList.toggle('is-on', KF_PREF.enabled);
        toggle.setAttribute('aria-checked', String(KF_PREF.enabled));
    }
    document.querySelectorAll('#kf-pos .pos-cell').forEach((c) => {
        const on = c.dataset.pos === KF_PREF.position;
        c.classList.toggle('active', on);
        c.setAttribute('aria-checked', String(on));
    });

    // If disabled, clear anything currently on screen.
    if (!KF_PREF.enabled) $('killfeed').innerHTML = '';
}

/* A sample entry so admins can see where the feed lands while configuring. */
function previewKillfeed() {
    const recent = kills.find((k) => k.killer && !k.suicide) || kills[0];
    const sample = recent ? {
        killer: recent.suicide ? null : (recent.killer && {
            name: recent.killer.name,
            avatar: recent.killer.discord && recent.killer.discord.avatarUrl,
        }),
        victim: recent.victim && {
            name: recent.victim.name,
            avatar: recent.victim.discord && recent.victim.discord.avatarUrl,
        },
        weaponLabel: recent.weaponLabel,
        icon: recent.categoryIcon,
        distance: recent.distance,
        headshot: recent.headshot,
        suicide: recent.suicide,
        explosion: recent.explosion,
        vehicleKill: recent.vehicleKill,
    } : {
        killer: { name: 'Admin' },
        victim: { name: 'Suspect' },
        weaponLabel: 'Combat Pistol',
        icon: 'fa-solid fa-gun',
        distance: 24,
        headshot: true,
    };

    // Force-show the preview even if the overlay is toggled off.
    const wasEnabled = KF_PREF.enabled;
    KF_PREF.enabled = true;
    addKillfeed({ ...sample, duration: 3000, maxShown: 5 });
    KF_PREF.enabled = wasEnabled;
}

function initKfSettings() {
    loadKfPref();
    applyKfPref();

    const btn = $('settings-btn');
    const menu = $('settings-menu');

    const openMenu = () => {
        menu.classList.remove('hidden');
        btn.classList.add('active');
        btn.setAttribute('aria-expanded', 'true');
    };
    const closeMenu = () => {
        menu.classList.add('hidden');
        btn.classList.remove('active');
        btn.setAttribute('aria-expanded', 'false');
    };

    btn.addEventListener('click', (e) => {
        e.stopPropagation();
        menu.classList.contains('hidden') ? openMenu() : closeMenu();
    });
    // Click anywhere outside closes the popover.
    document.addEventListener('click', (e) => {
        if (!menu.classList.contains('hidden') &&
            !menu.contains(e.target) && e.target !== btn) closeMenu();
    });

    $('kf-toggle').addEventListener('click', () => {
        KF_PREF.enabled = !KF_PREF.enabled;
        saveKfPref();
        applyKfPref();
    });

    $('kf-pos').querySelectorAll('.pos-cell').forEach((cell) => {
        cell.addEventListener('click', () => {
            KF_PREF.position = cell.dataset.pos;
            saveKfPref();
            applyKfPref();
            if (KF_PREF.enabled) previewKillfeed();   // show where it now lands
        });
    });

    $('kf-test').addEventListener('click', previewKillfeed);
}

/* ============================================================
   OPEN / CLOSE
   ============================================================ */

function openUI(data) {
    CONFIG = data.config || {};
    kills = (data.history || []).slice();

    // Apply theme overrides from config (optional)
    if (CONFIG.theme) {
        const r = document.documentElement.style;
        const t = CONFIG.theme;
        if (t.bg) r.setProperty('--bg', t.bg);
        if (t.panel) r.setProperty('--panel', t.panel);
        if (t.card) r.setProperty('--card', t.card);
        if (t.cardHover) r.setProperty('--card-hover', t.cardHover);
        if (t.accent) r.setProperty('--accent', t.accent);
        if (t.success) r.setProperty('--success', t.success);
        if (t.danger) r.setProperty('--danger', t.danger);
        if (t.warning) r.setProperty('--warning', t.warning);
    }

    selectedKillId = null;
    renderFeed();

    // Auto-select the newest kill for an instant populated view.
    if (kills.length) selectKill(kills[0].id);

    app.classList.remove('hidden', 'hide');
    app.classList.add('show');
}

function closeUI() {
    app.classList.remove('show');
    app.classList.add('hide');
    setTimeout(() => {
        app.classList.add('hidden');
        app.classList.remove('hide');
    }, 200);
    post('close');
}

/* ============================================================
   EVENTS
   ============================================================ */

window.addEventListener('message', (ev) => {
    const msg = ev.data || {};
    if (msg.action === 'killfeedAdd') { addKillfeed(msg.entry); return; }
    if (msg.action === 'open') openUI(msg);
    else if (msg.action === 'close') {
        app.classList.add('hidden');
        app.classList.remove('show', 'hide');
    } else if (msg.action === 'newKill') {
        addKill(msg.kill);
        // Refresh timeline if a profile is open.
        if (selectedKillId !== null) {
            const k = kills.find((x) => x.id === selectedKillId);
            if (k) renderTimeline(k);
        }
    }
});

document.addEventListener('keyup', (e) => {
    if (e.key !== 'Escape' || app.classList.contains('hidden')) return;
    // Close the settings popover first if it is open.
    const menu = $('settings-menu');
    if (menu && !menu.classList.contains('hidden')) {
        $('settings-btn').click();
        return;
    }
    closeUI();
});

$('close').addEventListener('click', closeUI);

$('search').addEventListener('input', (e) => {
    searchTerm = e.target.value.trim();
    renderFeed();
});

$('filter').addEventListener('change', (e) => {
    filterValue = e.target.value;
    renderFeed();
});

/* Live "time ago" refresh every 20s while open (cheap, only re-renders feed). */
setInterval(() => {
    if (!app.classList.contains('hidden')) renderFeed();
}, 20000);

/* Initialise killfeed settings (loads saved preference + wires the menu). */
initKfSettings();
