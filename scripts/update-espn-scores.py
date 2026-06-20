#!/usr/bin/env python3
"""Patch matches.json with live/final scores from ESPN when fixturedownload.com is slow.

Run after update-data.py in the GitHub Actions workflow. Queries ESPN for
yesterday/today/tomorrow UTC and fills in any null scores for matches that
ESPN reports as live or finished.
"""
import json
import ssl
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

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


def main():
    with open(MATCHES_JSON) as f:
        matches = json.load(f)

    now = datetime.now(timezone.utc)
    dates = [
        (now - timedelta(days=1)).strftime("%Y%m%d"),
        now.strftime("%Y%m%d"),
        (now + timedelta(days=1)).strftime("%Y%m%d"),
    ]

    all_events = []
    seen_ids = set()
    for d in dates:
        for e in fetch_espn(d):
            eid = e.get("id", "")
            if eid not in seen_ids:
                seen_ids.add(eid)
                all_events.append(e)

    patched = 0
    for event in all_events:
        comps = event.get("competitions", [])
        if not comps:
            continue
        comp = comps[0]
        status_name = comp.get("status", {}).get("type", {}).get("name", "")

        is_live = any(s in status_name for s in ("IN_PROGRESS", "HALF", "EXTRA", "PENALT"))
        is_finished = status_name == "STATUS_FULL_TIME"
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

        for m in matches:
            m_dt = datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            name_match = m["home"] == home_name and m["away"] == away_name
            time_match = abs(m_dt.timestamp() - kickoff_ts) < 120
            if name_match or time_match:
                if m["scoreH"] is None or m["scoreA"] is None:
                    m["scoreH"] = home_score
                    m["scoreA"] = away_score
                    tag = "LIVE" if is_live else "FT"
                    print(f"  PATCH: Match {m['n']} {m['home']} vs {m['away']} -> {home_score}-{away_score} ({tag})")
                    patched += 1
                break

    if patched:
        body = json.dumps(matches, indent=2, ensure_ascii=False)
        MATCHES_JSON.write_text(body + "\n")
        MATCHES_JS.write_text(
            "// Football 2026 — all matches. Kickoffs in UTC.\n"
            f"// Regenerated {now.strftime('%Y-%m-%d %H:%M UTC')} by scripts/update-espn-scores.py\n"
            f"window.WC_MATCHES = {body};\n"
        )

    print(f"ESPN score patch: {patched} matches updated")


if __name__ == "__main__":
    main()
