#!/usr/bin/env python3
"""Compare our knockout bracket against ESPN's and flag any mismatches.

Run after update-espn-scores.py in the GitHub Actions workflow. Fetches
every knockout date from ESPN, matches events to our data by kickoff
time, and verifies team names agree (ignoring placeholder names on
either side). Exits non-zero and files a GitHub issue if a real team
name disagrees.
"""
import json
import os
import re
import ssl
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

SITE_ROOT = Path(__file__).resolve().parent.parent
MATCHES_JSON = SITE_ROOT / "data" / "matches.json"

ESPN_API = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"

ESPN_TEAM_MAP = {
    "South Korea": "Korea Republic",
    "United States": "USA",
    "Bosnia-Herzegovina": "Bosnia and Herzegovina",
    "Cape Verde": "Cabo Verde",
    "Ivory Coast": "Côte d'Ivoire",
    "Iran": "IR Iran",
}

_PLACEHOLDER_RE = re.compile(
    r"^[123][A-L]+$"
    r"|^To be announced$"
    r"|^TBD$"
    r"|Group .+ Winner$"
    r"|Group .+ \d+\w* Place$"
    r"|Third Place Group"
    r"|Round of \d+ .+ Winner$"
    r"|Quarterfinal .+ Winner$"
    r"|Semifinal .+ (Winner|Loser)$"
)

KICKOFF_TOLERANCE = 120  # seconds


def is_placeholder(name: str) -> bool:
    return bool(_PLACEHOLDER_RE.search(name))


def espn_name(raw: str) -> str:
    return ESPN_TEAM_MAP.get(raw, raw)


def fetch_espn(date_str: str) -> list:
    url = f"{ESPN_API}?dates={date_str}"
    req = urllib.request.Request(url, headers={"User-Agent": "MatchMondo-verify/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10, context=_ssl_ctx) as resp:
            return json.load(resp).get("events", [])
    except Exception as e:
        print(f"  ESPN query for {date_str} failed: {e}")
        return []


def parse_date(s: str) -> datetime | None:
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%MZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def main():
    with open(MATCHES_JSON) as f:
        matches = json.load(f)

    knockout = [m for m in matches if m["n"] >= 73]
    ko_dates = set()
    for m in knockout:
        dt = datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        ko_dates.add(dt.strftime("%Y%m%d"))

    # Build lookup by kickoff timestamp
    by_ts: dict[int, list] = {}
    for m in knockout:
        ts = int(datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ")
                 .replace(tzinfo=timezone.utc).timestamp())
        by_ts.setdefault(ts, []).append(m)

    all_events = []
    seen_ids = set()
    for d in sorted(ko_dates):
        for e in fetch_espn(d):
            eid = e.get("id", "")
            if eid not in seen_ids:
                seen_ids.add(eid)
                all_events.append(e)

    mismatches = []

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

        espn_home = espn_name(home.get("team", {}).get("displayName", ""))
        espn_away = espn_name(away.get("team", {}).get("displayName", ""))

        kickoff = parse_date(event.get("date", ""))
        if not kickoff:
            continue
        kickoff_ts = int(kickoff.timestamp())

        # Find our match by kickoff time
        candidates = []
        for ts, ms in by_ts.items():
            if abs(ts - kickoff_ts) <= KICKOFF_TOLERANCE:
                candidates.extend(ms)

        if not candidates:
            continue

        # If exact name match exists, use it; otherwise use time-only if unambiguous
        matched = None
        for m in candidates:
            if m["home"] == espn_home and m["away"] == espn_away:
                matched = m
                break
        if not matched and len(candidates) == 1:
            matched = candidates[0]

        if not matched:
            # Multi-game slot, can't confidently match — skip
            continue

        # Compare: only flag if BOTH sides have a real team name and they disagree
        for side, our_name, their_name in [
            ("home", matched["home"], espn_home),
            ("away", matched["away"], espn_away),
        ]:
            if is_placeholder(our_name) or is_placeholder(their_name):
                continue
            if our_name != their_name:
                msg = f"Match {matched['n']} {side}: ours={our_name}, ESPN={their_name}"
                mismatches.append(msg)
                print(f"  MISMATCH: {msg}")

    if mismatches:
        print(f"\n❌ {len(mismatches)} bracket mismatch(es) found!")
        # Write summary for the GitHub Actions step to pick up
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            with open(summary_path, "a") as f:
                f.write("## ❌ Bracket mismatches\n\n")
                for m in mismatches:
                    f.write(f"- {m}\n")
        sys.exit(1)
    else:
        print("✅ All bracket teams match ESPN")


if __name__ == "__main__":
    main()
