#!/usr/bin/env python3
"""Fetch the latest Football 2026 fixtures (incl. scores) and regenerate data/matches.js.

Source: fixturedownload.com JSON feed (UTC kickoff times).
Run any time during the tournament to pull in new scores:

    python3 scripts/update-data.py
"""
import json
import re
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

FEED = "https://fixturedownload.com/feed/json/fifa-world-cup-2026"
SITE_ROOT = Path(__file__).resolve().parent.parent
OUT = SITE_ROOT / "data" / "matches.js"
OUT_JSON = SITE_ROOT / "data" / "matches.json"  # polled by the page for live score updates
OUT_ICS = SITE_ROOT / "world-cup-2026.ics"  # static file people subscribe to in Google Calendar

# Venue/location cleanup: feed location string -> (stadium, city). Unknown keys pass through as-is.
VENUES = {
    "Mexico City Stadium": ("Estadio Azteca", "Mexico City, Mexico"),
    "Guadalajara Stadium": ("Estadio Akron", "Guadalajara, Mexico"),
    "Monterrey Stadium": ("Estadio BBVA", "Monterrey, Mexico"),
    "Toronto Stadium": ("BMO Field", "Toronto, Canada"),
    "BC Place Vancouver": ("BC Place", "Vancouver, Canada"),
    "Atlanta Stadium": ("Mercedes-Benz Stadium", "Atlanta, GA"),
    "Boston Stadium": ("Gillette Stadium", "Foxborough (Boston), MA"),
    "Dallas Stadium": ("AT&T Stadium", "Arlington (Dallas), TX"),
    "Houston Stadium": ("NRG Stadium", "Houston, TX"),
    "Kansas City Stadium": ("Arrowhead Stadium", "Kansas City, MO"),
    "Los Angeles Stadium": ("SoFi Stadium", "Inglewood (Los Angeles), CA"),
    "Miami Stadium": ("Hard Rock Stadium", "Miami Gardens, FL"),
    "New York/New Jersey Stadium": ("MetLife Stadium", "East Rutherford, NJ"),
    "Philadelphia Stadium": ("Lincoln Financial Field", "Philadelphia, PA"),
    "San Francisco Bay Area Stadium": ("Levi's Stadium", "Santa Clara (SF Bay Area), CA"),
    "Seattle Stadium": ("Lumen Field", "Seattle, WA"),
}

# US broadcast rights: English on FOX/FS1, Spanish on Telemundo/Universo. FIFA has not published
# the exact FOX-vs-FS1 split for every match, so we use the rights-holder family as an honest label
# and flag the marquee windows (openers / knockouts / final) that are confirmed for the main networks.
TV_DEFAULT = "FOX or FS1 · Telemundo (ES)"
TV_MARQUEE = "FOX · Telemundo (ES)"


def stage_for(match_number: int) -> str:
    """FIFA 2026 match numbering: 1-72 group, 73-88 R32, 89-96 R16, 97-100 QF, 101-102 SF, 103 3rd place, 104 final."""
    n = match_number
    if n <= 72:
        return "Group Stage"
    if n <= 88:
        return "Round of 32"
    if n <= 96:
        return "Round of 16"
    if n <= 100:
        return "Quarter-finals"
    if n <= 102:
        return "Semi-finals"
    if n == 103:
        return "Third-place Match"
    return "Final"


def fetch_feed(url: str, retries: int = 3, backoff: float = 5.0) -> list:
    """Fetch the JSON feed with retries and exponential backoff."""
    import time
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "wc2026-fan-schedule"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except Exception as e:
            if attempt < retries - 1:
                wait = backoff * (2 ** attempt)
                print(f"Attempt {attempt + 1} failed ({e}), retrying in {wait}s...")
                time.sleep(wait)
            else:
                raise


def main() -> None:
    feed = fetch_feed(FEED)

    rows = []
    for f in feed:
        # Feed fields: MatchNumber, RoundNumber, DateUtc ("2026-06-11 19:00:00Z" or "... UTC"),
        # Location, HomeTeam, AwayTeam, Group ("Group A" or null), HomeTeamScore, AwayTeamScore
        raw_dt = f["DateUtc"].replace(" UTC", "").replace("Z", "").strip()
        dt = datetime.strptime(raw_dt, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        loc = (f.get("Location") or "").strip()
        venue, city = VENUES.get(loc, (loc or "TBD", loc or "TBD"))
        n = int(f["MatchNumber"])
        group = f.get("Group") or None
        # Marquee windows (host opener + all knockout rounds) air on the main FOX network.
        tv = TV_MARQUEE if (n == 1 or n >= 73) else TV_DEFAULT
        rows.append({
            "n": n,
            "utc": dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "stage": "Group Stage" if group else stage_for(n),
            "group": group,
            "home": (f.get("HomeTeam") or "TBD").strip() or "TBD",
            "away": (f.get("AwayTeam") or "TBD").strip() or "TBD",
            "venue": venue,
            "city": city,
            "tv": tv,  # US rights-holder label; hand overrides preserved from existing file below
            "scoreH": f.get("HomeTeamScore"),
            "scoreA": f.get("AwayTeamScore"),
        })

    rows.sort(key=lambda r: (r["utc"], r["n"]))

    # Preserve score facts that update-espn-scores.py layers on (pkH/pkA/result),
    # and never let a feed hiccup null-out a score we already have. This file is
    # REGENERATED from the fixture feed every run, so anything not carried over
    # here is lost as soon as the match ages out of ESPN's scoreboard window —
    # that's how the R32 shootout results (and every result:"FT") vanished on
    # 2026-07-06 and the knockout bracket stopped advancing PK winners.
    # isLive/liveDetail are deliberately NOT preserved: the ESPN step re-derives
    # them every run, and dropping them here auto-clears stale live flags.
    if OUT_JSON.exists():
        try:
            prev_by_n = {r["n"]: r for r in json.loads(OUT_JSON.read_text())}
        except (json.JSONDecodeError, KeyError, TypeError):
            prev_by_n = {}
        for r in rows:
            prev = prev_by_n.get(r["n"])
            if not prev:
                continue
            for key in ("pkH", "pkA", "result"):
                if key in prev and key not in r:
                    r[key] = prev[key]
            for key in ("scoreH", "scoreA"):
                if r.get(key) is None and prev.get(key) is not None:
                    r[key] = prev[key]

    # Preserve hand-maintained US TV assignments from the existing file.
    if OUT.exists():
        m = re.search(r"window\.WC_MATCHES\s*=\s*(\[.*\]);", OUT.read_text(), re.S)
        if m:
            try:
                tv_by_match = {r["n"]: r.get("tv") for r in json.loads(m.group(1))}
                for r in rows:
                    if tv_by_match.get(r["n"]):
                        r["tv"] = tv_by_match[r["n"]]
            except json.JSONDecodeError:
                pass

    body = json.dumps(rows, indent=2, ensure_ascii=False)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "// Football 2026 — all matches. Kickoffs in UTC.\n"
        f"// Regenerated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} by scripts/update-data.py\n"
        f"window.WC_MATCHES = {body};\n"
    )
    print(f"Wrote {len(rows)} matches to {OUT}")

    # Same data as plain JSON, for the page to poll for live score updates (same-origin, no CORS).
    OUT_JSON.write_text(body + "\n")
    print(f"Wrote {len(rows)} matches to {OUT_JSON}")

    OUT_ICS.write_text(build_ics(rows))
    print(f"Wrote {len(rows)} events to {OUT_ICS}")


def ics_escape(s: str) -> str:
    return str(s).replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def ics_dt(iso_utc: str) -> str:
    # "2026-06-11T19:00:00Z" -> "20260611T190000Z"
    return iso_utc.replace("-", "").replace(":", "")


def build_ics(rows: list[dict]) -> str:
    """Mirror of the client-side buildIcs(): a subscribable VCALENDAR with all matches in UTC.
    REFRESH-INTERVAL / X-PUBLISHED-TTL ask Google to re-fetch periodically so scores stay current."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//WC2026 Fan Schedule//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:MatchMondo — Football 2026",
        "X-WR-CALDESC:Football 2026 — all 104 matches (UTC; your calendar shows them in your local time zone)",
        "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
        "X-PUBLISHED-TTL:PT6H",
    ]
    for m in rows:
        start = datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        end = start + timedelta(hours=2)
        suffix = f" ({m['group']})" if m.get("group") else f" ({m['stage']})"
        summary = f"⚽ {m['home']} vs {m['away']}{suffix}"
        lines += [
            "BEGIN:VEVENT",
            f"UID:wc2026-match-{m['n']}@wc2026-fan-schedule",
            f"DTSTAMP:{stamp}",
            f"DTSTART:{ics_dt(m['utc'])}",
            f"DTEND:{end.strftime('%Y%m%dT%H%M%SZ')}",
            f"SUMMARY:{ics_escape(summary)}",
            f"LOCATION:{ics_escape(m['venue'] + ', ' + m['city'])}",
            f"DESCRIPTION:{ics_escape('Match ' + str(m['n']) + ' — ' + m['stage'])}",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"


if __name__ == "__main__":
    main()
