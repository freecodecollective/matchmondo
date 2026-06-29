#!/usr/bin/env python3
"""Patch matches.json with live/final scores from ESPN when fixturedownload.com is slow.

Run after update-data.py in the GitHub Actions workflow. Queries ESPN for
yesterday/today/tomorrow UTC and fills in any null scores for matches that
ESPN reports as live or finished.
"""
import json
import os
import ssl
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import match_resolver

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

SITE_ROOT = Path(__file__).resolve().parent.parent
MATCHES_JSON = SITE_ROOT / "data" / "matches.json"
MATCHES_JS = SITE_ROOT / "data" / "matches.js"

ESPN_API = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"

ESPN_TEAM_MAP = {
    "South Korea": "Korea Republic",
    "United States": "USA",
    "Bosnia-Herzegovina": "Bosnia and Herzegovina",
    "Cape Verde": "Cabo Verde",
    "Ivory Coast": "Côte d'Ivoire",
    "Iran": "IR Iran",
}


def fetch_espn(date_str: str) -> list:
    url = f"{ESPN_API}?dates={date_str}"
    req = urllib.request.Request(url, headers={"User-Agent": "MatchMondo-scores/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10, context=_ssl_ctx) as resp:
            return json.load(resp).get("events", [])
    except Exception as e:
        print(f"  ESPN query for {date_str} failed: {e}")
        return []


def parse_espn_date(s: str) -> datetime | None:
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%MZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


import re

_PLACEHOLDER_RE = re.compile(
    r"^[123][A-L]+$"                    # our compact codes: 1I, 2H, 3ABCDF
    r"|^To be announced$"
    r"|Group .+ Winner$"                # ESPN: "Group L Winner"
    r"|Group .+ \d+\w* Place$"          # ESPN: "Group J 2nd Place"
    r"|Third Place Group"               # ESPN: "Third Place Group C/E/F/H/I"
    r"|Round of \d+ .+ Winner$"         # ESPN: "Round of 32 1 Winner"
    r"|Quarterfinal .+ Winner$"
    r"|Semifinal .+ (Winner|Loser)$"
)


def _is_placeholder(name: str) -> bool:
    return bool(_PLACEHOLDER_RE.search(name))


def _espn_to_our_name(espn_name: str) -> str:
    return ESPN_TEAM_MAP.get(espn_name, espn_name)


def resolve_teams(matches: list, all_events: list) -> int:
    """Replace placeholder team names (1I, 3ABCDF, etc.) with real names from ESPN."""
    resolved = 0
    for event in all_events:
        comps = event.get("competitions", [])
        if not comps:
            continue
        comp = comps[0]
        competitors = comp.get("competitors", [])
        home = next((c for c in competitors if c.get("homeAway") == "home"), None)
        away = next((c for c in competitors if c.get("homeAway") == "away"), None)
        if not home or not away:
            continue

        espn_home = _espn_to_our_name(home.get("team", {}).get("displayName", ""))
        espn_away = _espn_to_our_name(away.get("team", {}).get("displayName", ""))

        kickoff = parse_espn_date(event.get("date", ""))
        if not kickoff:
            continue

        idx = match_resolver.resolve(matches, espn_home, espn_away, kickoff.timestamp())
        if idx is None:
            continue
        m = matches[idx]
        changed = False
        if _is_placeholder(m["home"]) and not _is_placeholder(espn_home):
            print(f"  RESOLVE: Match {m['n']} home {m['home']} -> {espn_home}")
            m["home"] = espn_home
            changed = True
        if _is_placeholder(m["away"]) and not _is_placeholder(espn_away):
            print(f"  RESOLVE: Match {m['n']} away {m['away']} -> {espn_away}")
            m["away"] = espn_away
            changed = True
        if changed:
            resolved += 1
    return resolved


PROXY_URL = "https://trivia-proxy-702476544925.us-central1.run.app"


def notify_ft(match_n: int) -> None:
    """Tell the proxy a match just went FT so it can fan out APNs pushes.
    Idempotent on the proxy side; safe to call from re-runs."""
    secret = (os.environ.get("PROXY_INTERNAL_SECRET") or "").strip()
    if not secret:
        return  # secret not configured — skip silently in local runs
    body = json.dumps({"secret": secret, "matchN": int(match_n)}).encode()
    req = urllib.request.Request(
        f"{PROXY_URL}/api/internal/notify-ft",
        data=body, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            print(f"  NOTIFY-FT Match {match_n}: {r.status}")
    except Exception as e:
        print(f"  NOTIFY-FT Match {match_n} failed: {e}")


BRACKET_FEEDERS = {
    # R16: winner of R32 pair
    89: (74, 77), 90: (73, 75), 93: (83, 84), 94: (81, 82),
    91: (76, 78), 92: (79, 80), 95: (86, 88), 96: (85, 87),
    # QF: winner of R16 pair
    97: (89, 90), 98: (93, 94), 99: (91, 92), 100: (95, 96),
    # SF: winner of QF pair
    101: (97, 98), 102: (99, 100),
    # Final: winner of SF pair
    104: (101, 102),
    # 3rd place: loser of SF pair
}
THIRD_PLACE_FEEDERS = {103: (101, 102)}


def _match_winner(m: dict) -> str | None:
    if m.get("scoreH") is None or m.get("scoreA") is None:
        return None
    if m["scoreH"] > m["scoreA"]:
        return m["home"]
    if m["scoreA"] > m["scoreH"]:
        return m["away"]
    # Tied on aggregate — check penalty shootout
    pkH, pkA = m.get("pkH"), m.get("pkA")
    if pkH is not None and pkA is not None:
        if pkH > pkA:
            return m["home"]
        if pkA > pkH:
            return m["away"]
    return None


def _match_loser(m: dict) -> str | None:
    if m.get("scoreH") is None or m.get("scoreA") is None:
        return None
    if m["scoreH"] > m["scoreA"]:
        return m["away"]
    if m["scoreA"] > m["scoreH"]:
        return m["home"]
    # Tied on aggregate — check penalty shootout
    pkH, pkA = m.get("pkH"), m.get("pkA")
    if pkH is not None and pkA is not None:
        if pkH > pkA:
            return m["away"]
        if pkA > pkH:
            return m["home"]
    return None


def propagate_bracket_winners(matches: list) -> int:
    by_n = {m["n"]: m for m in matches}
    resolved = 0
    for target_n, (feeder_a, feeder_b) in BRACKET_FEEDERS.items():
        target = by_n.get(target_n)
        fa, fb = by_n.get(feeder_a), by_n.get(feeder_b)
        if not target or not fa or not fb:
            continue
        wa = _match_winner(fa)
        wb = _match_winner(fb)
        if wa and _is_placeholder(target["home"]):
            print(f"  BRACKET: M{target_n} home <- {wa} (winner of M{feeder_a})")
            target["home"] = wa
            resolved += 1
        if wb and _is_placeholder(target["away"]):
            print(f"  BRACKET: M{target_n} away <- {wb} (winner of M{feeder_b})")
            target["away"] = wb
            resolved += 1
    for target_n, (sf_a, sf_b) in THIRD_PLACE_FEEDERS.items():
        target = by_n.get(target_n)
        sa, sb = by_n.get(sf_a), by_n.get(sf_b)
        if not target or not sa or not sb:
            continue
        la = _match_loser(sa)
        lb = _match_loser(sb)
        if la and _is_placeholder(target["home"]):
            print(f"  BRACKET: M{target_n} home <- {la} (loser of M{sf_a})")
            target["home"] = la
            resolved += 1
        if lb and _is_placeholder(target["away"]):
            print(f"  BRACKET: M{target_n} away <- {lb} (loser of M{sf_b})")
            target["away"] = lb
            resolved += 1
    return resolved


def main():
    with open(MATCHES_JSON) as f:
        matches = json.load(f)

    now = datetime.now(timezone.utc)

    # Collect ESPN events: yesterday/today/tomorrow for scores, plus all
    # knockout dates (June 28 – July 19) for resolving placeholder teams.
    knockout_matches = [m for m in matches if m["n"] >= 73]
    ko_dates = set()
    for m in knockout_matches:
        dt = datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        ko_dates.add(dt.strftime("%Y%m%d"))

    score_dates = {
        (now - timedelta(days=1)).strftime("%Y%m%d"),
        now.strftime("%Y%m%d"),
        (now + timedelta(days=1)).strftime("%Y%m%d"),
    }

    all_dates = score_dates | ko_dates

    all_events = []
    seen_ids = set()
    for d in sorted(all_dates):
        for e in fetch_espn(d):
            eid = e.get("id", "")
            if eid not in seen_ids:
                seen_ids.add(eid)
                all_events.append(e)

    teams_resolved = resolve_teams(matches, all_events)
    print(f"ESPN team resolve: {teams_resolved} matches updated")

    # Track which matches transition to FT in this run so we can fire push
    # notifications. We treat any match that ESPN reports as STATUS_FULL_TIME
    # here as a candidate; the proxy dedupes via /pushed-ft/{n} so a re-run
    # won't double-fire even though the script may re-detect FT every 15 min.
    newly_ft: list[int] = []

    patched = 0
    for event in all_events:
        comps = event.get("competitions", [])
        if not comps:
            continue
        comp = comps[0]
        status_name = comp.get("status", {}).get("type", {}).get("name", "")

        is_live = any(s in status_name for s in ("IN_PROGRESS", "HALF", "EXTRA", "PENALT"))
        is_finished = status_name in ("STATUS_FULL_TIME", "STATUS_FINAL_AET", "STATUS_FINAL_PEN")
        if not (is_live or is_finished):
            continue

        competitors = comp.get("competitors", [])
        home = next((c for c in competitors if c.get("homeAway") == "home"), None)
        away = next((c for c in competitors if c.get("homeAway") == "away"), None)
        if not home or not away:
            continue

        home_score = int(home.get("score") or "0")
        away_score = int(away.get("score") or "0")

        kickoff = parse_espn_date(event.get("date", ""))
        if not kickoff:
            continue
        kickoff_ts = kickoff.timestamp()

        home_name = ESPN_TEAM_MAP.get(home.get("team", {}).get("displayName", ""), home.get("team", {}).get("displayName", ""))
        away_name = ESPN_TEAM_MAP.get(away.get("team", {}).get("displayName", ""), away.get("team", {}).get("displayName", ""))

        # Match-resolution logic lives in match_resolver.resolve so the same
        # rule (and the same tests) cover both Python and the iOS Swift
        # implementation. See scripts/test_match_resolver.py for edge cases,
        # most importantly the two-fixtures-at-the-same-kickoff case that
        # bit Bosnia v Qatar on 2026-06-23 and Morocco v Haiti on 2026-06-24.
        idx = match_resolver.resolve(matches, home_name, away_name, kickoff_ts)
        matched_m = matches[idx] if idx is not None else None
        if matched_m is not None:
            needs_patch = (matched_m["scoreH"] is None or matched_m["scoreA"] is None
                           or is_live
                           or (is_finished and (matched_m["scoreH"] != home_score or matched_m["scoreA"] != away_score)))
            if needs_patch:
                matched_m["scoreH"] = home_score
                matched_m["scoreA"] = away_score
                tag = "LIVE" if is_live else "FT"
                print(f"  PATCH: Match {matched_m['n']} {matched_m['home']} vs {matched_m['away']} -> {home_score}-{away_score} ({tag})")
                patched += 1

            if is_live:
                matched_m["isLive"] = True
            elif is_finished:
                matched_m.pop("isLive", None)

            # Store result type and PK scores for finished matches
            if is_finished:
                if status_name == "STATUS_FINAL_PEN":
                    pk_home = int(home.get("shootoutScore", 0))
                    pk_away = int(away.get("shootoutScore", 0))
                    matched_m["pkH"] = pk_home
                    matched_m["pkA"] = pk_away
                    matched_m["result"] = "PEN"
                    print(f"  PEN: Match {matched_m['n']} penalties {pk_home}-{pk_away}")
                elif status_name == "STATUS_FINAL_AET":
                    matched_m["result"] = "AET"
                elif matched_m["n"] >= 73:
                    # FT result tag only for knockout matches
                    matched_m["result"] = "FT"

                newly_ft.append(int(matched_m["n"]))

    bracket_resolved = propagate_bracket_winners(matches)

    if patched or teams_resolved or bracket_resolved:
        body = json.dumps(matches, indent=2, ensure_ascii=False)
        MATCHES_JSON.write_text(body + "\n")
        MATCHES_JS.write_text(
            "// Football 2026 — all matches. Kickoffs in UTC.\n"
            f"// Regenerated {now.strftime('%Y-%m-%d %H:%M UTC')} by scripts/update-espn-scores.py\n"
            f"window.WC_MATCHES = {body};\n"
        )

    print(f"ESPN score patch: {patched} matches updated")
    print(f"Bracket propagation: {bracket_resolved} slots filled")

    # Fan out FT push notifications. The proxy is the source of truth on
    # whether a given match has already been pushed — we just hand off every
    # FT we saw this run.
    for n in sorted(set(newly_ft)):
        notify_ft(n)


if __name__ == "__main__":
    main()
