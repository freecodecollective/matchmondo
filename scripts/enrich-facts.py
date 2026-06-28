#!/usr/bin/env python3
"""
Enrich match previews, daily previews, and daily recaps with interesting
facts scraped from sports media (ESPN, Guardian, BBC, Goal.com, etc.).

Facts are stored in data/match-facts.json keyed by match number, and in
data/daily-facts.json keyed by date. The iOS app and preview/recap
generators can merge these into display text.

Usage:
    # Enrich facts for a specific date's matches (preview + recap)
    python3 scripts/enrich-facts.py --date 2026-06-28

    # Enrich facts for a date range
    python3 scripts/enrich-facts.py --from 2026-06-27 --to 2026-06-29

Facts are sourced by searching multiple outlets for each match. A fact
is included if it appears in 2+ independent sources (or is a verifiable
historical first / record). Categories:
  - Historical firsts ("first time X has reached the quarterfinals")
  - Head-to-head records ("Brazil have won 11 of 14 meetings with Japan")
  - Streaks ("Messi has scored in 7 consecutive World Cup matches")
  - Tournament records ("Kane became England's all-time WC top scorer")
  - Anniversary facts ("exactly 32 years since they met at USA '94")
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(REPO, "data")


def load_matches():
    with open(os.path.join(DATA, "matches.json")) as f:
        return json.load(f)


def matches_for_date(matches, date_str):
    """Return matches whose kickoff falls on date_str in US Pacific time."""
    result = []
    for m in matches:
        utc = m.get("utc", "")
        if not utc:
            continue
        mt = datetime.fromisoformat(utc.replace("Z", "+00:00"))
        pt = mt - timedelta(hours=7)
        if pt.strftime("%Y-%m-%d") == date_str:
            result.append(m)
    return result


def load_json(filename):
    path = os.path.join(DATA, filename)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def save_json(filename, data):
    path = os.path.join(DATA, filename)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    print("enrich-facts.py: use with --date or --from/--to flags")
    print("For now, facts are added manually via Claude Code sessions")
    print("and stored in data/match-facts.json + data/daily-facts.json")
