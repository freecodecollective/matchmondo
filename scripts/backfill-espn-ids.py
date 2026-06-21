#!/usr/bin/env python3
"""Backfill ESPN athlete ids into data/players.js.

The iOS app computes player stats (appearances / goals / assists) by matching
our key players against ESPN match-summary events. Name matching folds accents
but can't bridge transliteration spelling differences (e.g. our "Mousa
Al-Tamari" vs ESPN's, or "Andrew Robertson" vs ESPN "Andy Robertson"), which
would silently drop a player's stats. Storing each player's stable ESPN athlete
id makes that matching exact.

This script fetches every team's ESPN roster, matches each key player by
normalized name (+ a small manual-override table for the transliteration
cases), and inserts an "espnId" line after each player's "name" line. It is
idempotent: players that already have an espnId are left untouched, so it's
safe to re-run as ESPN firms up its rosters (a couple of players aren't in
ESPN's preliminary squads yet and keep name-fallback until they are).

Usage:  python3 scripts/backfill-espn-ids.py
"""
import json
import re
import ssl
import unicodedata
import urllib.request
from pathlib import Path

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

SITE_ROOT = Path(__file__).resolve().parent.parent
PLAYERS_JS = SITE_ROOT / "data" / "players.js"

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world"

# our players.js team name -> ESPN displayName (only where they differ)
TEAM_ALIAS = {
    "Korea Republic": "South Korea",
    "USA": "United States",
    "Bosnia and Herzegovina": "Bosnia-Herzegovina",
    "Cabo Verde": "Cape Verde",
    "Côte d'Ivoire": "Ivory Coast",
    "IR Iran": "Iran",
}

# (team, our player name) -> ESPN athlete id, for players whose ESPN spelling
# differs enough that name matching misses them. Verified by hand against the
# team's ESPN roster.
MANUAL_OVERRIDES = {
    ("Egypt", "Mohamed Abdelmonem"): 236957,       # ESPN "Mohamed Abdelmoneim"
    ("Ghana", "Abdul Fatawu Issahaku"): 318680,    # ESPN "Fatawu Issahaku"
    ("Panama", "Michael Amir Murillo"): 216420,    # ESPN "Amir Murillo"
    ("Scotland", "Andrew Robertson"): 104943,      # ESPN "Andy Robertson"
    ("Sweden", "Victor Nilsson Lindelöf"): 204679, # ESPN "Victor Lindelöf"
    ("Türkiye", "Kenan Yıldız"): 366509,           # ESPN "Kenan Yildiz"
    ("Saudi Arabia", "Firas Al-Buraikan"): 283331, # ESPN "Feras Al-Brikan"
}


def get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "MatchMondo-ids/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20, context=_ssl_ctx) as resp:
            return json.load(resp)
    except Exception as e:
        print(f"  request failed ({url}): {e}")
        return {}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    for ch in "'.-":
        s = s.replace(ch, " ")
    return " ".join(s.split())


def load_players() -> dict:
    raw = PLAYERS_JS.read_text()
    body = raw[raw.index("=") + 1:].strip().rstrip(";")
    return json.loads(body)["teams"]


def espn_team_ids() -> dict:
    """Scan tournament scoreboards -> {normalized ESPN team name: team id}."""
    dates = [f"202606{d:02d}" for d in range(11, 31)] + [f"202607{d:02d}" for d in range(1, 20)]
    by_norm = {}
    for d in dates:
        sb = get(f"{ESPN_BASE}/scoreboard?dates={d}")
        for ev in sb.get("events", []):
            for comp in (ev.get("competitions") or [{}])[0].get("competitors", []):
                t = comp.get("team", {})
                if t.get("id") and t.get("displayName"):
                    by_norm[norm(t["displayName"])] = t["id"]
    return by_norm


def build_mapping(teams: dict) -> tuple[dict, list]:
    espn_ids = espn_team_ids()
    mapping, unmatched = {}, []
    for team, players in teams.items():
        tid = espn_ids.get(norm(TEAM_ALIAS.get(team, team)))
        roster = []
        if tid:
            r = get(f"{ESPN_BASE}/teams/{tid}/roster")
            roster = [(norm(a.get("displayName", "")), a.get("id"))
                      for a in r.get("athletes", []) if a.get("id")]
        by_norm = {n: i for n, i in roster}
        tokmap = [(set(n.split()), i) for n, i in roster]
        m = {}
        for p in players:
            nm = p["name"]
            if (team, nm) in MANUAL_OVERRIDES:
                m[nm] = MANUAL_OVERRIDES[(team, nm)]
                continue
            nn = norm(nm)
            eid = by_norm.get(nn)
            if not eid:
                tset = set(nn.split())
                cands = [i for ts, i in tokmap if len(tset) >= 2 and ts == tset]
                eid = cands[0] if len(cands) == 1 else None
            if eid:
                m[nm] = int(eid)
            else:
                unmatched.append((team, nm))
        mapping[team] = m
    return mapping, unmatched


def write_players(mapping: dict) -> int:
    """Insert an espnId line after each player's name line. Idempotent."""
    lines = PLAYERS_JS.read_text().split("\n")
    team_re = re.compile(r'^  "(.+)": \[$')
    name_re = re.compile(r'^(    )"name": "(.*)",$')
    out, team, inserted = [], None, 0
    for i, ln in enumerate(lines):
        out.append(ln)
        tm = team_re.match(ln)
        if tm:
            team = tm.group(1)
        nm = name_re.match(ln)
        if nm and team:
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if '"espnId"' not in nxt:
                eid = mapping.get(team, {}).get(nm.group(2))
                if eid is not None:
                    out.append(f'{nm.group(1)}"espnId": {eid},')
                    inserted += 1
    PLAYERS_JS.write_text("\n".join(out))
    return inserted


def main():
    teams = load_players()
    mapping, unmatched = build_mapping(teams)
    matched = sum(len(v) for v in mapping.values())
    total = sum(len(v) for v in teams.values())
    inserted = write_players(mapping)
    print(f"matched {matched}/{total} players; inserted {inserted} new espnId line(s)")
    if unmatched:
        print(f"not in ESPN rosters yet ({len(unmatched)}) — keep name fallback:")
        for t, n in unmatched:
            print(f"  {t}: {n}")


if __name__ == "__main__":
    main()
