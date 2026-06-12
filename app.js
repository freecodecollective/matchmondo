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
    showScores: document.getElementById("show-scores"),
    showRanking: document.getElementById("show-ranking"),
    showPlayers: document.getElementById("show-players"),
    players: document.getElementById("players"),
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
      showPlayers: els.showPlayers.checked,
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

    const visible = matches.filter((m) =>
      (stageFilter === "all" || m.stage === stageFilter) &&
      (!teamFilterActive || selectedTeams.has(m.home) || selectedTeams.has(m.away)) &&
      selectedVenues.has(m.venue)
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
      for (const m of g.items) {
        const label = m.group || m.stage;
        const trophy = m.stage === "Final" ? "🏆 " : "";
        const played = opts.showScores && hasScore(m);
        const homeWin = played && Number(m.scoreH) > Number(m.scoreA);
        const awayWin = played && Number(m.scoreA) > Number(m.scoreH);
        html += `
        <article class="match-card stage-${stageSlug(m.stage)}" data-blanks-slot data-match="${m.n}">
          <div>
            <div class="match-time">${esc(fmtTime(m.utc, tz))}</div>
            <div class="match-stage">Match ${m.n} · ${trophy}${esc(label)}</div>
          </div>
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
      html += `</section>`;
    }

    els.schedule.innerHTML = html || `<p>No matches found for this filter.</p>`;
    els.count.textContent = `${visible.length} match${visible.length === 1 ? "" : "es"}`;
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
    const teams = Object.keys(data.teams || {});
    if (!teams.length) {
      els.players.innerHTML = `<h2 class="players-title">Player Guide</h2>` +
        `<p class="players-intro">Player research is being compiled — check back shortly.</p>`;
      return;
    }

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
        html += `
        <div class="player-card">
          <div class="player-name">${esc(p.name)}</div>
          <div class="player-pos">${esc(p.position)} · <span class="player-club">${esc(p.club)}</span></div>
          <div class="player-from">📍 ${esc(p.hometown)}</div>
          <p class="player-why">${esc(p.why)}</p>
        </div>`;
      }
      html += `</div></div>`;
    }
    els.players.innerHTML = html;
  }

  function applyPlayersToggle() {
    const on = els.showPlayers.checked;
    if (on) renderPlayers();
    els.players.hidden = !on;
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
      "X-WR-CALNAME:World Cup 2026",
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
    if (els.showPlayers.checked) renderPlayers();
  });
  els.showPlayers.addEventListener("change", () => { savePrefs(); applyPlayersToggle(); });
  els.printBlanks.addEventListener("change", savePrefs);

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

  // If a flag image can't load (e.g. offline), swap to the neutral placeholder so no broken icon shows.
  els.schedule.addEventListener("error", (e) => {
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
  if (prefs.printBlanks != null) els.printBlanks.checked = prefs.printBlanks;
  if (prefs.showPlayers != null) els.showPlayers.checked = prefs.showPlayers;
  render();
  applyPlayersToggle();

  // Kick off live score polling: once shortly after load, then every 5 minutes,
  // plus an immediate check whenever the tab is refocused (if it's been a couple minutes).
  setTimeout(refreshScores, 1500);
  setInterval(refreshScores, 5 * 60 * 1000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && Date.now() - lastCheck > 120000) refreshScores();
  });
})();
