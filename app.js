/* World Cup 2026 schedule app.
 * Match data lives in data/matches.js as window.WC_MATCHES:
 *   { n: matchNumber, utc: "2026-06-11T19:00:00Z", stage, group,
 *     home, away, venue, city, tv, scoreH, scoreA }
 * All kickoffs are stored in UTC; rendering converts to the chosen zone.
 */
(function () {
  "use strict";

  const matches = (window.WC_MATCHES || []).slice().sort((a, b) => new Date(a.utc) - new Date(b.utc) || a.n - b.n);

  const els = {
    tzInput: document.getElementById("tz-input"),
    tzList: document.getElementById("tz-listbox"),
    stage: document.getElementById("stage-filter"),
    teamBtn: document.getElementById("team-btn"),
    teamList: document.getElementById("team-list"),
    teamOptions: document.getElementById("team-options"),
    teamAll: document.getElementById("team-all"),
    teamNone: document.getElementById("team-none"),
    teamSearch: document.getElementById("team-search"),
    venueBtn: document.getElementById("venue-btn"),
    venueList: document.getElementById("venue-list"),
    venueOptions: document.getElementById("venue-options"),
    venueAll: document.getElementById("venue-all"),
    venueNone: document.getElementById("venue-none"),
    venueSearch: document.getElementById("venue-search"),
    controls: document.getElementById("controls"),
    showScores: document.getElementById("show-scores"),
    showRanking: document.getElementById("show-ranking"),
    showLocation: document.getElementById("show-location"),
    showPast: document.getElementById("show-past"),
    showRoster: document.getElementById("show-roster"),
    sidebar: document.getElementById("sidebar"),
    players: document.getElementById("players"),
    standings: document.getElementById("standings"),
    rules: document.getElementById("rules"),
    main: document.querySelector("main"),
    upcoming: document.getElementById("upcoming"),
    upcomingCount: document.getElementById("upcoming-count"),
    upcomingBody: document.getElementById("upcoming-body"),
    printBtn: document.getElementById("print-btn"),
    printBlanks: document.getElementById("print-blanks"),
    subscribeBtn: document.getElementById("subscribe-btn"),
    downloadIcsBtn: document.getElementById("download-ics-btn"),
    gcalDialog: document.getElementById("gcal-dialog"),
    icsUrlInput: document.getElementById("ics-url"),
    copyUrlBtn: document.getElementById("copy-url"),
    subscribeLink: document.getElementById("subscribe-link"),
    localWarning: document.getElementById("local-warning"),
    schedule: document.getElementById("schedule"),
    count: document.getElementById("match-count"),
    tzLabel: document.getElementById("tz-label"),
    updateNote: document.getElementById("update-note"),
  };

  // ---------- Preferences (persisted) ----------
  const PREFS_KEY = "wc2026-prefs";
  function loadPrefs() {
    try { return JSON.parse(localStorage.getItem(PREFS_KEY)) || {}; } catch { return {}; }
  }
  function savePrefs() {
    localStorage.setItem(PREFS_KEY, JSON.stringify({
      tz: currentTz,
      showScores: els.showScores.checked,
      showRanking: els.showRanking.checked,
      showLocation: els.showLocation.checked,
      showPast: els.showPast.checked,
      showRoster: els.showRoster.checked,
      activeTab: activeTab,
      upcomingOpen: els.upcoming.open,
      controlsOpen: els.controls.open,
      printBlanks: els.printBlanks.checked,
    }));
  }
  const prefs = loadPrefs();

  // ---------- Time zone selector (searchable combobox) ----------
  const deviceTz = Intl.DateTimeFormat().resolvedOptions().timeZone;

  // Curated, friendly labels. US zones are explicitly prefixed "USA" so they're
  // unmistakable among the many "America/…" entries (which also include Canada,
  // Mexico, Brazil, etc.). Order here defines the "Common" group order.
  const TZ_LABELS = {
    "America/New_York": "USA — New York · Eastern",
    "America/Chicago": "USA — Chicago · Central",
    "America/Denver": "USA — Denver · Mountain",
    "America/Phoenix": "USA — Phoenix · Arizona (no DST)",
    "America/Los_Angeles": "USA — Los Angeles · Pacific",
    "America/Anchorage": "USA — Anchorage · Alaska",
    "Pacific/Honolulu": "USA — Honolulu · Hawaii",
    "America/Toronto": "Canada — Toronto · Eastern",
    "America/Vancouver": "Canada — Vancouver · Pacific",
    "America/Edmonton": "Canada — Edmonton · Mountain",
    "America/Mexico_City": "Mexico — Mexico City",
    "America/Monterrey": "Mexico — Monterrey",
    "America/Sao_Paulo": "Brazil — São Paulo",
    "America/Bogota": "Colombia — Bogotá",
    "America/Lima": "Peru — Lima",
    "America/Santiago": "Chile — Santiago",
    "America/Argentina/Buenos_Aires": "Argentina — Buenos Aires",
    "Europe/London": "UK — London",
    "Europe/Dublin": "Ireland — Dublin",
    "Europe/Paris": "France — Paris",
    "Europe/Berlin": "Germany — Berlin",
    "Europe/Madrid": "Spain — Madrid",
    "Europe/Rome": "Italy — Rome",
    "Europe/Amsterdam": "Netherlands — Amsterdam",
    "Europe/Lisbon": "Portugal — Lisbon",
    "Europe/Zurich": "Switzerland — Zurich",
    "Europe/Moscow": "Russia — Moscow",
    "Africa/Lagos": "Nigeria — Lagos",
    "Africa/Cairo": "Egypt — Cairo",
    "Africa/Casablanca": "Morocco — Casablanca",
    "Africa/Johannesburg": "South Africa — Johannesburg",
    "Asia/Riyadh": "Saudi Arabia — Riyadh",
    "Asia/Dubai": "UAE — Dubai",
    "Asia/Tehran": "Iran — Tehran",
    "Asia/Karachi": "Pakistan — Karachi",
    "Asia/Kolkata": "India — Kolkata",
    "Asia/Shanghai": "China — Shanghai",
    "Asia/Tokyo": "Japan — Tokyo",
    "Asia/Seoul": "South Korea — Seoul",
    "Australia/Sydney": "Australia — Sydney",
    "Pacific/Auckland": "New Zealand — Auckland",
  };
  const COMMON_TZS = Object.keys(TZ_LABELS);

  function allZones() {
    if (typeof Intl.supportedValuesOf === "function") {
      try { return Intl.supportedValuesOf("timeZone"); } catch { /* fall through */ }
    }
    return COMMON_TZS;
  }

  // Current UTC offset string (e.g. "GMT-7"), computed once per zone.
  const REF_DATE = new Date();
  function offsetOf(tz) {
    try {
      const part = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "shortOffset" })
        .formatToParts(REF_DATE).find((p) => p.type === "timeZoneName");
      return part ? part.value.replace("GMT", "UTC") : "";
    } catch { return ""; }
  }

  // Build the option model: {value, label, search, offset, common}
  const TZ_OPTIONS = (() => {
    const seen = new Set();
    const opts = [];
    const add = (value, common) => {
      if (!value || seen.has(value)) return;
      seen.add(value);
      const label = TZ_LABELS[value] || value.replace(/_/g, " ").replace(/\//g, " / ");
      opts.push({
        value,
        label,
        offset: offsetOf(value),
        common,
        search: (label + " " + value).toLowerCase().replace(/_/g, " "),
      });
    };
    COMMON_TZS.forEach((z) => add(z, true));
    allZones().forEach((z) => add(z, false));
    return opts;
  })();

  let currentTz = prefs.tz || deviceTz;
  if (!TZ_OPTIONS.some((o) => o.value === currentTz)) {
    // Device/saved zone not in IANA list (rare) — show it anyway.
    TZ_OPTIONS.unshift({
      value: currentTz, label: currentTz.replace(/_/g, " "),
      offset: offsetOf(currentTz), common: false, search: currentTz.toLowerCase(),
    });
  }

  function labelFor(tz) {
    const o = TZ_OPTIONS.find((x) => x.value === tz);
    return o ? o.label : tz.replace(/_/g, " ");
  }

  // -- combobox behavior --
  let tzActiveIndex = -1;
  let tzFiltered = [];

  function renderTzList(query) {
    const q = query.trim().toLowerCase();
    const matches = q
      ? TZ_OPTIONS.filter((o) => o.search.includes(q))
      : TZ_OPTIONS;

    // When no query, show a "Common" header + common zones, then "All".
    let html = "";
    tzFiltered = [];
    const pushItem = (o) => {
      const i = tzFiltered.length;
      tzFiltered.push(o);
      const active = i === tzActiveIndex ? ' aria-selected="true"' : "";
      const cur = o.value === currentTz ? " ✓" : "";
      html += `<li role="option" data-i="${i}"${active}>` +
        `<span class="tz-name">${esc(o.label)}${cur}</span>` +
        `<span class="tz-off">${esc(o.offset)}</span></li>`;
    };

    if (!q) {
      html += `<li class="tz-group-head" aria-disabled="true">Common</li>`;
      matches.filter((o) => o.common).forEach(pushItem);
      html += `<li class="tz-group-head" aria-disabled="true">All time zones</li>`;
      matches.filter((o) => !o.common).forEach(pushItem);
    } else {
      matches.forEach(pushItem);
    }
    if (!matches.length) html = `<li class="tz-empty" aria-disabled="true">No time zone matches “${esc(query)}”</li>`;

    els.tzList.innerHTML = html;
    els.tzList.hidden = false;
    els.tzInput.setAttribute("aria-expanded", "true");
  }

  function openTzList() {
    tzActiveIndex = -1;
    els.tzInput.value = "";
    renderTzList("");
  }
  function closeTzList() {
    els.tzList.hidden = true;
    els.tzInput.setAttribute("aria-expanded", "false");
    els.tzInput.value = labelFor(currentTz);
    tzActiveIndex = -1;
  }
  function chooseTz(opt) {
    if (!opt) return;
    currentTz = opt.value;
    closeTzList();
    savePrefs();
    render();
  }
  function moveActive(delta) {
    if (els.tzList.hidden) { renderTzList(els.tzInput.value); return; }
    if (!tzFiltered.length) return;
    tzActiveIndex = (tzActiveIndex + delta + tzFiltered.length) % tzFiltered.length;
    const items = [...els.tzList.querySelectorAll('li[role="option"]')];
    items.forEach((li, i) => li.setAttribute("aria-selected", i === tzActiveIndex ? "true" : "false"));
    const el = items[tzActiveIndex];
    if (el) el.scrollIntoView({ block: "nearest" });
  }

  function initTzCombo() {
    els.tzInput.value = labelFor(currentTz);

    els.tzInput.addEventListener("focus", openTzList);
    els.tzInput.addEventListener("click", () => { if (els.tzList.hidden) openTzList(); });
    els.tzInput.addEventListener("input", () => { tzActiveIndex = -1; renderTzList(els.tzInput.value); });

    els.tzInput.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") { e.preventDefault(); moveActive(1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); moveActive(-1); }
      else if (e.key === "Enter") {
        e.preventDefault();
        if (tzActiveIndex >= 0 && tzFiltered[tzActiveIndex]) chooseTz(tzFiltered[tzActiveIndex]);
        else if (tzFiltered.length === 1) chooseTz(tzFiltered[0]);
      } else if (e.key === "Escape") { closeTzList(); els.tzInput.blur(); }
    });

    els.tzList.addEventListener("mousedown", (e) => {
      // mousedown (not click) so it fires before input blur closes the list
      const li = e.target.closest('li[data-i]');
      if (!li) return;
      e.preventDefault();
      chooseTz(tzFiltered[Number(li.dataset.i)]);
    });

    document.addEventListener("click", (e) => {
      if (!document.getElementById("tz-combo").contains(e.target)) closeTzList();
    });
  }

  // ---------- Sidebar tabs ----------
  let activeTab = "schedule";

  function switchTab(tab) {
    activeTab = tab;
    document.querySelectorAll(".sidebar-tab").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.tab === tab);
    });
    document.querySelectorAll(".tab-panel").forEach(panel => {
      panel.classList.toggle("active", panel.id === "panel-" + tab);
    });
    if (tab === "standings") renderStandings();
    if (tab === "rules") renderRules();
    if (tab === "players") renderPlayers();
    savePrefs();
  }

  // ---------- Filters ----------
  let ALL_VENUES = [], ALL_TEAMS = [];
  const selectedVenues = new Set();
  const selectedTeams = new Set();

  // Generic multi-select checklist dropdown: search box + Select all / Clear all + per-item checkboxes.
  function createChecklistFilter(cfg) {
    const { btn, list, optionsEl, allBtn, noneBtn, searchEl, comboId, items, selected, noun, onChange } = cfg;
    const total = items.length;
    function label() {
      const n = selected.size;
      btn.textContent = n === total ? `All ${noun}` : n === 0 ? `No ${noun}` : `${n} of ${total} ${noun}`;
    }
    optionsEl.innerHTML = items.map((it) =>
      `<li data-search="${esc((it.name + " " + (it.sub || "")).toLowerCase())}">` +
      `<label class="venue-opt"><input type="checkbox" value="${esc(it.value)}" checked>` +
      `<span class="venue-opt-text"><span class="venue-opt-name">${it.icon || ""}${esc(it.name)}</span>` +
      (it.sub ? `<span class="venue-opt-city">${esc(it.sub)}</span>` : "") +
      `</span></label></li>`
    ).join("");
    selected.clear();
    items.forEach((it) => selected.add(it.value));
    label();

    optionsEl.addEventListener("change", (e) => {
      const cb = e.target;
      if (cb.type !== "checkbox") return;
      if (cb.checked) selected.add(cb.value); else selected.delete(cb.value);
      label();
      onChange();
    });
    function setAll(on) {
      optionsEl.querySelectorAll('input[type="checkbox"]').forEach((cb) => { cb.checked = on; });
      selected.clear();
      if (on) items.forEach((it) => selected.add(it.value));
      label();
      onChange();
    }
    allBtn.addEventListener("click", () => setAll(true));
    noneBtn.addEventListener("click", () => setAll(false));
    if (searchEl) {
      searchEl.addEventListener("input", () => {
        const q = searchEl.value.trim().toLowerCase();
        optionsEl.querySelectorAll("li").forEach((li) => {
          li.hidden = q && !li.dataset.search.includes(q);
        });
      });
    }
    btn.addEventListener("click", () => {
      const open = list.hidden;
      list.hidden = !open;
      btn.setAttribute("aria-expanded", String(open));
      if (open && searchEl) {
        searchEl.value = "";
        optionsEl.querySelectorAll("li").forEach((li) => { li.hidden = false; });
        setTimeout(() => searchEl.focus(), 0);
      }
    });
    document.addEventListener("click", (e) => {
      if (!document.getElementById(comboId).contains(e.target)) {
        list.hidden = true;
        btn.setAttribute("aria-expanded", "false");
      }
    });
  }

  function buildFilters() {
    const stages = [...new Set(matches.map((m) => m.stage))];
    stages.forEach((s) => {
      const o = document.createElement("option");
      o.value = s;
      o.textContent = s;
      els.stage.appendChild(o);
    });

    // Venue filter
    ALL_VENUES = [...new Set(matches.map((m) => m.venue))].sort((a, b) => a.localeCompare(b));
    const venueCity = {};
    matches.forEach((m) => { if (!venueCity[m.venue]) venueCity[m.venue] = m.city; });
    createChecklistFilter({
      btn: els.venueBtn, list: els.venueList, optionsEl: els.venueOptions,
      allBtn: els.venueAll, noneBtn: els.venueNone, searchEl: els.venueSearch, comboId: "venue-combo",
      items: ALL_VENUES.map((v) => ({ value: v, name: v, sub: venueCity[v] })),
      selected: selectedVenues, noun: "venues", onChange: render,
    });

    // Team filter — real teams only (present in the flag map), so knockout placeholders
    // like "1A", "3ABCDF" and "To be announced" are excluded.
    ALL_TEAMS = [...new Set(matches.flatMap((m) => [m.home, m.away]))]
      .filter((t) => FLAGS[t]).sort((a, b) => a.localeCompare(b));
    createChecklistFilter({
      btn: els.teamBtn, list: els.teamList, optionsEl: els.teamOptions,
      allBtn: els.teamAll, noneBtn: els.teamNone, searchEl: els.teamSearch, comboId: "team-combo",
      items: ALL_TEAMS.map((t) => ({ value: t, name: t, icon: flagImg(t) })),
      selected: selectedTeams, noun: "teams", onChange: render,
    });
  }

  // ---------- Rendering ----------
  function fmtTime(iso, tz) {
    return new Intl.DateTimeFormat(undefined, {
      hour: "numeric", minute: "2-digit", timeZone: tz,
    }).format(new Date(iso));
  }
  function fmtDayKey(iso, tz) {
    return new Intl.DateTimeFormat("en-CA", {
      year: "numeric", month: "2-digit", day: "2-digit", timeZone: tz,
    }).format(new Date(iso));
  }
  function fmtDayHeading(iso, tz) {
    return new Intl.DateTimeFormat(undefined, {
      weekday: "long", month: "long", day: "numeric", year: "numeric", timeZone: tz,
    }).format(new Date(iso));
  }

  function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
  }

  // Team name -> ISO 3166-1 code (flagcdn). England/Scotland use GB sub-national flags.
  const FLAGS = {
    "Algeria": "dz", "Argentina": "ar", "Australia": "au", "Austria": "at", "Belgium": "be",
    "Bosnia and Herzegovina": "ba", "Brazil": "br", "Cabo Verde": "cv", "Canada": "ca",
    "Colombia": "co", "Congo DR": "cd", "Croatia": "hr", "Curaçao": "cw", "Czechia": "cz",
    "Côte d'Ivoire": "ci", "Ecuador": "ec", "Egypt": "eg", "England": "gb-eng", "France": "fr",
    "Germany": "de", "Ghana": "gh", "Haiti": "ht", "IR Iran": "ir", "Iraq": "iq", "Japan": "jp",
    "Jordan": "jo", "Korea Republic": "kr", "Mexico": "mx", "Morocco": "ma", "Netherlands": "nl",
    "New Zealand": "nz", "Norway": "no", "Panama": "pa", "Paraguay": "py", "Portugal": "pt",
    "Qatar": "qa", "Saudi Arabia": "sa", "Scotland": "gb-sct", "Senegal": "sn", "South Africa": "za",
    "Spain": "es", "Sweden": "se", "Switzerland": "ch", "Tunisia": "tn", "Türkiye": "tr",
    "USA": "us", "Uruguay": "uy", "Uzbekistan": "uz",
  };
  function flagImg(team) {
    const code = FLAGS[team];
    if (!code) return `<span class="flag flag-tbd" aria-hidden="true"></span>`;
    return `<img class="flag" src="https://flagcdn.com/${code}.svg" alt="" width="22" height="16" loading="lazy">`;
  }

  // FIFA world ranking lookup (data/rankings.js).
  const RANKINGS = (window.WC_RANKINGS && window.WC_RANKINGS.ranks) || {};
  function rankOf(team) {
    return RANKINGS[team] || null;
  }
  // Small "#N" badge shown next to a team when the ranking toggle is on.
  function rankBadge(team) {
    if (!els.showRanking.checked) return "";
    const r = rankOf(team);
    return r ? `<span class="rank-badge" title="FIFA world ranking (${(window.WC_RANKINGS || {}).asOf || ""})">#${r}</span>` : "";
  }

  // Stage -> slug for the colored left-edge accent.
  function stageSlug(stage) {
    return ({
      "Group Stage": "group", "Round of 32": "r32", "Round of 16": "r16",
      "Quarter-finals": "qf", "Semi-finals": "sf", "Third-place Match": "third", "Final": "final",
    })[stage] || "group";
  }

  function hasScore(m) {
    return m.scoreH != null && m.scoreA != null;
  }

  function scoreHtml(m, opts) {
    if (opts.blanks) {
      return `<span class="score blank-box">&nbsp;</span><span class="vs">–</span><span class="score blank-box">&nbsp;</span>`;
    }
    if (opts.showScores && hasScore(m)) {
      return `<span class="score">${esc(m.scoreH)}</span><span class="vs">–</span><span class="score">${esc(m.scoreA)}</span>`;
    }
    return `<span class="vs">vs</span>`;
  }

  // One match card — shared by the schedule and the Today/Tomorrow panel.
  function matchCardHTML(m, tz, opts) {
    const label = m.group || m.stage;
    const trophy = m.stage === "Final" ? "🏆 " : "";
    const played = opts.showScores && hasScore(m);
    const homeWin = played && Number(m.scoreH) > Number(m.scoreA);
    const awayWin = played && Number(m.scoreA) > Number(m.scoreH);
    return `
        <article class="match-card stage-${stageSlug(m.stage)}" data-blanks-slot data-match="${m.n}">
          <div class="match-time">${esc(fmtTime(m.utc, tz))}</div>
          <div class="match-stage">Match ${m.n} · ${trophy}${esc(label)}</div>
          <div class="match-teams">
            <span class="team${homeWin ? " winner" : ""}">${flagImg(m.home)}<span class="team-name">${esc(m.home)}</span>${rankBadge(m.home)}</span>
            <span class="score-slot">${scoreHtml(m, opts)}</span>
            <span class="team${awayWin ? " winner" : ""}">${flagImg(m.away)}<span class="team-name">${esc(m.away)}</span>${rankBadge(m.away)}</span>
          </div>
          <div class="match-meta">
            <span class="match-venue">${esc(m.venue)}</span> · ${esc(m.city)}
          </div>
        </article>`;
  }

  // Today / Tomorrow quick-glance panel (screen only). Respects the active filters.
  function renderUpcoming(list, tz, opts) {
    const now = new Date();
    const todayKey = fmtDayKey(now.toISOString(), tz);
    const tomorrowKey = fmtDayKey(new Date(now.getTime() + 86400000).toISOString(), tz);
    const today = list.filter((m) => fmtDayKey(m.utc, tz) === todayKey);
    const tomorrow = list.filter((m) => fmtDayKey(m.utc, tz) === tomorrowKey);
    const n = today.length + tomorrow.length;
    els.upcomingCount.textContent = n ? `${n} match${n === 1 ? "" : "es"}` : "no matches";

    if (!n) {
      els.upcomingBody.innerHTML = `<p class="upcoming-empty">No matches today or tomorrow.</p>`;
      return;
    }
    const block = (label, arr) => arr.length
      ? `<h3 class="upcoming-day">${esc(label)} — ${esc(fmtDayHeading(arr[0].utc, tz))}</h3>` +
        arr.map((m) => matchCardHTML(m, tz, opts)).join("")
      : "";
    els.upcomingBody.innerHTML = block("Today", today) + block("Tomorrow", tomorrow);
  }

  function render() {
    const tz = currentTz;
    const stageFilter = els.stage.value;
    // Team filter only narrows when the user has deselected some teams (all selected = show everything,
    // including knockout matches whose teams are still TBD).
    const teamFilterActive = selectedTeams.size !== ALL_TEAMS.length;
    const opts = {
      showScores: els.showScores.checked,
      blanks: false,
    };
    // "Past games" off → hide matches that have almost certainly finished (kicked off > 2.5h ago).
    const hidePast = !els.showPast.checked;
    const pastCutoff = Date.now() - 2.5 * 60 * 60 * 1000;

    const visible = matches.filter((m) =>
      (stageFilter === "all" || m.stage === stageFilter) &&
      (!teamFilterActive || selectedTeams.has(m.home) || selectedTeams.has(m.away)) &&
      selectedVenues.has(m.venue) &&
      (!hidePast || new Date(m.utc).getTime() >= pastCutoff)
    );

    const groups = new Map();
    visible.forEach((m) => {
      const key = fmtDayKey(m.utc, tz);
      if (!groups.has(key)) groups.set(key, { key, heading: fmtDayHeading(m.utc, tz), items: [] });
      groups.get(key).items.push(m);
    });

    const todayKey = fmtDayKey(new Date().toISOString(), tz);

    let html = "";
    for (const [, g] of [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
      const isToday = g.key === todayKey;
      const todayPill = isToday ? `<span class="today-pill">Today</span>` : "";
      html += `<section class="day-group${isToday ? " is-today" : ""}">` +
        `<h2 class="day-heading">${esc(g.heading)}${todayPill}</h2>`;
      for (const m of g.items) html += matchCardHTML(m, tz, opts);
      html += `</section>`;
    }

    els.schedule.innerHTML = html || `<p>No matches found for this filter.</p>`;
    renderUpcoming(matches, tz, opts);
    const total = matches.length;
    const played = matches.filter(hasScore).length;
    const filterActive = stageFilter !== "all" || teamFilterActive ||
      selectedVenues.size !== ALL_VENUES.length || hidePast;
    els.count.textContent = filterActive
      ? `${visible.length} of ${total} matches shown · ${played} played`
      : `${played} of ${total} matches played`;
    els.tzLabel.textContent = labelFor(tz);
  }

  // Swap score cells to blank boxes (or back) for printing.
  function applyPrintBlanks(on) {
    const opts = { showScores: els.showScores.checked, blanks: on };
    document.querySelectorAll(".match-card").forEach((card) => {
      const n = Number(card.dataset.match);
      const m = matches.find((x) => x.n === n);
      if (!m) return;
      card.querySelector(".score-slot").innerHTML = scoreHtml(m, opts);
    });
  }

  // ---------- Player guide ----------
  function renderPlayers() {
    const data = window.WC_PLAYERS || { teams: {} };
    const rosters = window.WC_ROSTERS || {};
    const teams = Object.keys(data.teams || {});
    if (!teams.length) {
      els.players.innerHTML = `<h2 class="players-title">Player Guide</h2>` +
        `<p class="players-intro">Player research is being compiled — check back shortly.</p>`;
      return;
    }

    const showRoster = els.showRoster.checked;
    const hasRosters = Object.keys(rosters).length > 0;

    // Order by FIFA world ranking (best first); any unranked teams fall to the end alphabetically.
    const ordered = teams.slice().sort((a, b) => {
      const ra = rankOf(a), rb = rankOf(b);
      if (ra && rb) return ra - rb;
      if (ra) return -1;
      if (rb) return 1;
      return a.localeCompare(b);
    });

    let html = `<h2 class="players-title">⭐ Player Guide — Top Players by Team</h2>` +
      `<p class="players-intro">The standout players to watch on every team — 5 for the FIFA top-10 sides, 3 for everyone else, ` +
      `ordered by FIFA world ranking. Clubs and details reflect the 2025–26 season.</p>`;

    for (const team of ordered) {
      html += `<div class="team-block">` +
        `<h3 class="team-block-head">${flagImg(team)}<span>${esc(team)}</span>${rankBadge(team)}</h3>` +
        `<div class="player-grid">`;
      for (const p of data.teams[team]) {
        const numBadge = p.number ? `<span class="jersey-num">#${p.number}</span> ` : "";
        html += `
        <div class="player-card">
          <div class="player-name">${numBadge}${esc(p.name)}</div>
          <div class="player-pos">${esc(p.position)} · <span class="player-club">${esc(p.club)}</span></div>
          <div class="player-from">📍 ${esc(p.hometown)}</div>
          <p class="player-why">${esc(p.why)}</p>
        </div>`;
      }
      html += `</div>`;

      // Full roster table (toggleable)
      if (showRoster && rosters[team] && rosters[team].length) {
        const roster = rosters[team].slice().sort((a, b) => {
          const posOrder = { GK: 0, DF: 1, MF: 2, FW: 3 };
          const pa = posOrder[a.position] ?? 9, pb = posOrder[b.position] ?? 9;
          return pa - pb || a.number - b.number;
        });
        html += `<table class="roster-table">` +
          `<thead><tr><th class="rt-num">#</th><th class="rt-name">Name</th><th>Pos</th><th>Age</th><th>Club</th></tr></thead><tbody>`;
        for (const r of roster) {
          html += `<tr>` +
            `<td class="rt-num">${r.number}</td>` +
            `<td class="rt-name">${esc(r.name)}</td>` +
            `<td class="rt-pos">${esc(r.position)}</td>` +
            `<td class="rt-age">${r.age}</td>` +
            `<td class="rt-club">${esc(r.club)}</td>` +
            `</tr>`;
        }
        html += `</tbody></table>`;
      }
      html += `</div>`;
    }
    els.players.innerHTML = html;
  }

  function applyPlayersToggle() {
    if (activeTab === "players") renderPlayers();
  }

  // ---------- Location (stadium + city) show/hide ----------
  function applyLocation() {
    els.main.classList.toggle("hide-location", !els.showLocation.checked);
  }

  // ---------- Group standings ----------
  function computeStandings() {
    const groups = {};
    matches.forEach((m) => {
      if (!/^Group /.test(m.group || "")) return;
      const g = (groups[m.group] ||= {});
      for (const t of [m.home, m.away]) {
        if (FLAGS[t] && !g[t]) g[t] = { team: t, P: 0, W: 0, D: 0, L: 0, GF: 0, GA: 0, Pts: 0 };
      }
      if (m.scoreH != null && m.scoreA != null && g[m.home] && g[m.away]) {
        const h = g[m.home], a = g[m.away], sh = Number(m.scoreH), sa = Number(m.scoreA);
        h.P++; a.P++; h.GF += sh; h.GA += sa; a.GF += sa; a.GA += sh;
        if (sh > sa) { h.W++; a.L++; h.Pts += 3; }
        else if (sh < sa) { a.W++; h.L++; a.Pts += 3; }
        else { h.D++; a.D++; h.Pts++; a.Pts++; }
      }
    });
    return groups;
  }

  function renderStandings() {
    const groups = computeStandings();
    const names = Object.keys(groups).sort();
    let html = `<h2 class="section-title">📊 Group Standings</h2>` +
      `<p class="section-intro">Live points and goal difference, updated as scores come in. The top 2 of each group ` +
      `advance, plus the 8 best third-placed teams. Rows are sorted by points → goal difference → goals for; ` +
      `the official <button type="button" class="linklike" data-open-rules>tiebreakers</button> add head-to-head and fair-play.</p>` +
      `<div class="standings-grid">`;
    for (const g of names) {
      const rows = Object.values(groups[g]).sort((a, b) =>
        b.Pts - a.Pts || (b.GF - b.GA) - (a.GF - a.GA) || b.GF - a.GF || a.team.localeCompare(b.team));
      html += `<div class="standings-group"><h3 class="standings-head">${esc(g)}</h3>` +
        `<table class="standings-table"><thead><tr>` +
        `<th>#</th><th class="st-team">Team</th><th title="Played">P</th><th>W</th><th>D</th><th>L</th>` +
        `<th title="Goals for">GF</th><th title="Goals against">GA</th><th title="Goal difference">GD</th><th>Pts</th>` +
        `</tr></thead><tbody>`;
      rows.forEach((r, i) => {
        const gd = r.GF - r.GA, pos = i + 1;
        const cls = pos <= 2 ? "q1" : pos === 3 ? "q3" : "";
        html += `<tr class="${cls}"><td class="st-pos">${pos}</td>` +
          `<td class="st-team">${flagImg(r.team)}<span>${esc(r.team)}</span></td>` +
          `<td>${r.P}</td><td>${r.W}</td><td>${r.D}</td><td>${r.L}</td>` +
          `<td>${r.GF}</td><td>${r.GA}</td><td>${gd > 0 ? "+" : ""}${gd}</td><td class="st-pts">${r.Pts}</td></tr>`;
      });
      html += `</tbody></table></div>`;
    }
    html += `</div><p class="standings-legend"><span class="swatch q1"></span> Advances (top 2) ` +
      `<span class="swatch q3"></span> In the hunt for a best-third-place spot</p>`;
    els.standings.innerHTML = html;
  }

  function applyStandingsToggle() {
    if (activeTab === "standings") renderStandings();
  }

  // ---------- Rules ----------
  let rulesRendered = false;
  function renderRules() {
    if (rulesRendered) return;
    els.rules.innerHTML = `
      <h2 class="section-title">📋 Rules &amp; How It Works</h2>
      <p class="section-intro">A fan's guide to the laws and tournament rules you'll see most during the 2026 World Cup.</p>
      <div class="rules-grid">

        <div class="rule-card">
          <h3>⏱️ Match format</h3>
          <p>Two 45-minute halves plus stoppage (added) time. Group-stage matches can end in a draw.
          From the Round of 32 on, a tie after 90 minutes goes to <strong>two 15-minute periods of extra time</strong>,
          and if still level, a <strong>penalty shootout</strong> decides it.</p>
        </div>

        <div class="rule-card">
          <h3>🟨 Yellow card (caution)</h3>
          <p>A warning for offenses such as unsporting behavior, dissent, persistent fouling,
          <strong>delaying the restart of play / time-wasting</strong>, not respecting the required distance at a
          free kick or corner, or entering/leaving the field without permission.</p>
        </div>

        <div class="rule-card">
          <h3>🟥 Red card (sending-off)</h3>
          <p>Shown for serious foul play, violent conduct, spitting, denying an obvious goal-scoring opportunity,
          offensive language, or <strong>two yellow cards in the same match</strong>. The player leaves and
          <strong>cannot be replaced</strong> — the team plays a player short — and is suspended for at least the next match.</p>
        </div>

        <div class="rule-card">
          <h3>🔁 Suspensions &amp; yellow-card amnesty</h3>
          <ul>
            <li><strong>Two yellows in different matches</strong> → a one-match suspension.</li>
            <li><strong>Two yellows in one match</strong> (a red) → miss the next match.</li>
            <li><strong>Single yellows are wiped after the group stage</strong>, so no one carries cautions into the Round of 32.</li>
            <li>They're wiped <strong>again after the quarter-finals</strong>, so an early yellow can't cause a player to miss the final.</li>
          </ul>
        </div>

        <div class="rule-card">
          <h3>📊 Group tiebreakers</h3>
          <p>If teams are level on points, they're ranked by:</p>
          <ol>
            <li>Goal difference (all group matches)</li>
            <li>Goals scored (all group matches)</li>
            <li>Head-to-head: points among the tied teams</li>
            <li>Head-to-head: goal difference</li>
            <li>Head-to-head: goals scored</li>
            <li>Fair-play score (fewest yellow/red cards)</li>
            <li>Drawing of lots by FIFA</li>
          </ol>
        </div>

        <div class="rule-card">
          <h3>➡️ Who advances</h3>
          <p>This is a 48-team, 12-group tournament. The <strong>top two from each group</strong> (24 teams) advance,
          plus the <strong>8 best third-placed teams</strong> across all groups — 32 teams into the Round of 32.
          Third-place teams are ranked by points, then goal difference, then goals scored, then fair-play score.</p>
        </div>

      </div>
      <p class="rules-note">Unofficial summary for fans. The full Laws of the Game and FIFA regulations are the official source.</p>`;
    rulesRendered = true;
  }

  function applyRulesToggle() {
    if (activeTab === "rules") renderRules();
  }

  // ---------- ICS generation ----------
  function icsEscape(s) {
    return String(s).replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
  }
  function icsDate(iso) {
    return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  }
  function buildIcs() {
    const lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//WC2026 Fan Schedule//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "X-WR-CALNAME:MatchMondo — World Cup 2026",
      "X-WR-CALDESC:FIFA World Cup 2026 — all 104 matches (times in UTC; your calendar shows them in your local time zone)",
    ];
    matches.forEach((m) => {
      const start = new Date(m.utc);
      const end = new Date(start.getTime() + 2 * 60 * 60 * 1000); // 2h block
      const summary = `⚽ ${m.home} vs ${m.away}` + (m.group ? ` (${m.group})` : ` (${m.stage})`);
      const descParts = [`Match ${m.n} — ${m.stage}`];
      lines.push(
        "BEGIN:VEVENT",
        `UID:wc2026-match-${m.n}@wc2026-fan-schedule`,
        `DTSTAMP:${icsDate(matches[0].utc)}`,
        `DTSTART:${icsDate(start.toISOString())}`,
        `DTEND:${icsDate(end.toISOString())}`,
        `SUMMARY:${icsEscape(summary)}`,
        `LOCATION:${icsEscape(`${m.venue}, ${m.city}`)}`,
        `DESCRIPTION:${icsEscape(descParts.join("\n"))}`,
        "END:VEVENT"
      );
    });
    lines.push("END:VCALENDAR");
    // RFC 5545: CRLF line endings
    return lines.join("\r\n");
  }
  function downloadIcs() {
    const blob = new Blob([buildIcs()], { type: "text/calendar;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "world-cup-2026.ics";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  // ---------- Google Calendar subscription ----------
  // The hosted, static world-cup-2026.ics (regenerated by scripts/update-data.py) sits next to
  // index.html. Subscribing points Google at that URL so it appears as its own toggleable calendar.
  const ICS_URL = new URL("world-cup-2026.ics", location.href).href;
  const IS_LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname) || location.protocol === "file:";

  function openSubscribeDialog() {
    els.icsUrlInput.value = ICS_URL;
    // Google Calendar "add by URL" deep link. webcal:// signals subscription (toggleable calendar)
    // rather than a one-time import.
    const webcal = ICS_URL.replace(/^https?:/, "webcal:");
    els.subscribeLink.href = "https://calendar.google.com/calendar/r?cid=" + encodeURIComponent(webcal);
    els.localWarning.hidden = !IS_LOCAL;
    els.gcalDialog.showModal();
  }

  function copyIcsUrl() {
    const done = () => { els.copyUrlBtn.textContent = "Copied ✓"; setTimeout(() => (els.copyUrlBtn.textContent = "Copy"), 1500); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(ICS_URL).then(done).catch(() => { els.icsUrlInput.select(); document.execCommand("copy"); done(); });
    } else {
      els.icsUrlInput.select();
      document.execCommand("copy");
      done();
    }
  }

  // ---------- Live score auto-refresh ----------
  // The page loads data/matches.js for the initial paint, then polls data/matches.json
  // (kept current by the scheduled GitHub Action) so an open tab updates without a reload.
  function matchesSig(arr) {
    return arr.slice().sort((a, b) => a.n - b.n)
      .map((m) => `${m.n}:${m.scoreH}:${m.scoreA}:${m.home}:${m.away}`).join("|");
  }
  let lastSig = matchesSig(matches);
  let lastCheck = 0;

  function applyMatches(arr) {
    arr.sort((a, b) => new Date(a.utc) - new Date(b.utc) || a.n - b.n);
    matches.length = 0;
    arr.forEach((m) => matches.push(m));
  }
  function fmtClock() {
    return new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit", timeZone: currentTz }).format(new Date());
  }
  async function refreshScores() {
    lastCheck = Date.now();
    try {
      const res = await fetch(`data/matches.json?t=${Date.now()}`, { cache: "no-store" });
      if (!res.ok) throw new Error("fetch failed");
      const arr = await res.json();
      if (!Array.isArray(arr) || !arr.length) throw new Error("bad data");
      const sig = matchesSig(arr);
      if (sig !== lastSig) {
        applyMatches(arr);
        lastSig = sig;
        render();
        if (activeTab === "standings") renderStandings();
        els.updateNote.textContent = `Scores updated at ${fmtClock()}. Refreshes automatically.`;
      } else {
        els.updateNote.textContent = `Scores up to date (checked ${fmtClock()}). Refreshes automatically.`;
      }
    } catch {
      // Offline or opened as a local file — keep whatever is already shown.
      els.updateNote.textContent = "Scores update automatically when online.";
    }
  }

  // ---------- Events ----------
  els.stage.addEventListener("change", render);
  els.showScores.addEventListener("change", () => { savePrefs(); render(); });
  els.showRanking.addEventListener("change", () => {
    savePrefs();
    render();
    if (activeTab === "players") renderPlayers();
    if (activeTab === "standings") renderStandings();
  });
  els.showLocation.addEventListener("change", () => { savePrefs(); applyLocation(); });
  els.showPast.addEventListener("change", () => { savePrefs(); render(); });
  els.controls.addEventListener("toggle", savePrefs);
  els.showRoster.addEventListener("change", () => {
    if (els.showRoster.checked && activeTab !== "players") switchTab("players");
    savePrefs();
    if (activeTab === "players") renderPlayers();
  });
  els.sidebar.addEventListener("click", (e) => {
    const btn = e.target.closest(".sidebar-tab");
    if (btn) switchTab(btn.dataset.tab);
  });
  els.printBlanks.addEventListener("change", savePrefs);

  els.standings.addEventListener("click", (e) => {
    if (e.target.closest("[data-open-rules]")) switchTab("rules");
  });

  els.printBtn.addEventListener("click", () => {
    if (els.printBlanks.checked) applyPrintBlanks(true);
    window.print();
  });
  window.addEventListener("afterprint", () => {
    if (els.printBlanks.checked) applyPrintBlanks(false);
  });

  els.subscribeBtn.addEventListener("click", openSubscribeDialog);
  els.downloadIcsBtn.addEventListener("click", downloadIcs);
  els.copyUrlBtn.addEventListener("click", copyIcsUrl);

  // Persist the Today/Tomorrow panel's open/closed state.
  els.upcoming.addEventListener("toggle", savePrefs);

  // If a flag image can't load (e.g. offline), swap to the neutral placeholder so no broken icon shows.
  els.main.addEventListener("error", (e) => {
    const img = e.target;
    if (img.tagName === "IMG" && img.classList.contains("flag")) {
      const span = document.createElement("span");
      span.className = "flag flag-tbd";
      span.setAttribute("aria-hidden", "true");
      img.replaceWith(span);
    }
  }, true);

  // ---------- Init ----------
  initTzCombo();
  buildFilters();
  if (prefs.showScores != null) els.showScores.checked = prefs.showScores;
  if (prefs.showRanking != null) els.showRanking.checked = prefs.showRanking;
  if (prefs.showLocation != null) els.showLocation.checked = prefs.showLocation;
  if (prefs.showPast != null) els.showPast.checked = prefs.showPast;
  if (prefs.printBlanks != null) els.printBlanks.checked = prefs.printBlanks;
  if (prefs.showRoster != null) els.showRoster.checked = prefs.showRoster;
  if (prefs.upcomingOpen != null) els.upcoming.open = prefs.upcomingOpen;
  if (prefs.controlsOpen != null) els.controls.open = prefs.controlsOpen;
  render();
  applyLocation();
  if (prefs.activeTab) switchTab(prefs.activeTab);

  // Kick off live score polling: once shortly after load, then every 5 minutes,
  // plus an immediate check whenever the tab is refocused (if it's been a couple minutes).
  setTimeout(refreshScores, 1500);
  setInterval(refreshScores, 5 * 60 * 1000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && Date.now() - lastCheck > 120000) refreshScores();
  });
})();
