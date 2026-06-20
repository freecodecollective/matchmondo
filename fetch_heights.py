#!/usr/bin/env python3
"""
Fetch player heights from ESPN's site API and add them to rosters.js.

ESPN heights are in inches; this script converts to integer cm.
Matching is diacritic-insensitive and handles common name variations.
"""

import json
import re
import ssl
import time
import unicodedata
import urllib.request
from pathlib import Path

ROSTERS_PATH = Path(__file__).parent / "data" / "rosters.js"

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world"

# Our team name -> ESPN displayName
TEAM_NAME_MAP = {
    "Korea Republic": "South Korea",
    "USA": "United States",
    "Bosnia and Herzegovina": "Bosnia-Herzegovina",
    "Cabo Verde": "Cape Verde",
    "Côte d'Ivoire": "Ivory Coast",
    "IR Iran": "Iran",
}

INCHES_TO_CM = 2.54

# Players not found on ESPN's tournament roster API -- heights sourced from
# ESPN individual athlete pages, Wikipedia, and Transfermarkt (June 2026).
MANUAL_HEIGHTS = {
    "Marcos Senesi": 185,
    "Christoph Baumgartner": 180,
    "Arjan Malić": 185,
    "Nabil Emad": 179,
    "Tino Livramento": 183,
    "Garven Metusala": 185,
    "Hossein Kanaanizadegan": 188,
    "Shuto Machino": 185,
    "Marwane Saadane": 188,
    "Amine Sbai": 175,
    "Mohamed Al-Mannai": 189,
    "Maximiliano Araujo": 176,
}


def normalize(name: str) -> str:
    """Strip diacritics, lowercase, collapse whitespace, remove punctuation."""
    # Handle chars that NFKD doesn't decompose to ASCII
    # Turkish dotless-i, Polish ł, etc.
    SPECIAL_MAP = str.maketrans({
        "ı": "i", "İ": "I",
        "ł": "l", "Ł": "L",
        "ø": "o", "Ø": "O",
        "đ": "d", "Đ": "D",
        "ß": "ss",
    })
    name = name.translate(SPECIAL_MAP)
    # NFD decompose, strip combining marks
    nfkd = unicodedata.normalize("NFKD", name)
    ascii_name = "".join(c for c in nfkd if not unicodedata.combining(c))
    # lowercase, strip punctuation except spaces/hyphens
    ascii_name = ascii_name.lower()
    ascii_name = re.sub(r"[^a-z\s-]", "", ascii_name)
    ascii_name = re.sub(r"\s+", " ", ascii_name).strip()
    return ascii_name


def name_tokens(name: str) -> set:
    """Split a normalized name into token set for fuzzy matching."""
    return set(normalize(name).replace("-", " ").split())


def _ssl_context() -> ssl.SSLContext:
    """Create an SSL context that works on macOS with stock Python."""
    # Try certifi first, fall back to unverified if certs not installed
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    ctx = ssl.create_default_context()
    try:
        ctx.load_default_certs()
        return ctx
    except Exception:
        ctx = ssl._create_unverified_context()
        return ctx


_SSL_CTX = _ssl_context()


def fetch_json(url: str) -> dict:
    """Fetch JSON from a URL with basic error handling."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15, context=_SSL_CTX) as resp:
        return json.loads(resp.read())


def get_espn_teams() -> dict:
    """Return {espn_display_name: team_id} for all teams in the tournament."""
    data = fetch_json(f"{ESPN_BASE}/teams")
    teams = {}
    for t in data["sports"][0]["leagues"][0]["teams"]:
        team = t["team"]
        teams[team["displayName"]] = team["id"]
    return teams


def get_espn_roster(team_id: str) -> list:
    """Return list of {name, height_cm} for a team's ESPN roster."""
    data = fetch_json(f"{ESPN_BASE}/teams/{team_id}/roster")
    players = []
    for a in data.get("athletes", []):
        height_inches = a.get("height")
        height_cm = None
        if height_inches and height_inches > 0:
            height_cm = round(height_inches * INCHES_TO_CM)
        players.append({
            "name": a.get("fullName", a.get("displayName", "")),
            "height_cm": height_cm,
        })
    return players


def match_height(player_name: str, espn_players: list) -> int | None:
    """Find the best height match for a player name from ESPN data.

    Matching strategy (in order):
    1. Exact normalized name match
    2. One name is a substring of the other (normalized)
    3. Token overlap >= 2 tokens (handles name ordering differences)
    4. Last-name match when only one ESPN player shares that last name
    """
    norm_player = normalize(player_name)

    # Strategy 1: exact match
    for ep in espn_players:
        if normalize(ep["name"]) == norm_player:
            return ep["height_cm"]

    # Strategy 2: substring match
    for ep in espn_players:
        norm_espn = normalize(ep["name"])
        if norm_espn in norm_player or norm_player in norm_espn:
            return ep["height_cm"]

    # Strategy 3: token overlap (at least 2 shared tokens)
    player_tokens = name_tokens(player_name)
    if len(player_tokens) >= 2:
        best_match = None
        best_overlap = 0
        for ep in espn_players:
            espn_tokens = name_tokens(ep["name"])
            overlap = len(player_tokens & espn_tokens)
            if overlap >= 2 and overlap > best_overlap:
                best_overlap = overlap
                best_match = ep
        if best_match:
            return best_match["height_cm"]

    # Strategy 4: last-name match (only if unambiguous)
    player_last = norm_player.split()[-1] if norm_player.split() else ""
    if player_last and len(player_last) > 2:
        last_matches = [
            ep for ep in espn_players
            if normalize(ep["name"]).split()[-1] == player_last
        ]
        if len(last_matches) == 1:
            return last_matches[0]["height_cm"]

    # Strategy 5: fuzzy edit distance for transliteration variants
    # Only trigger for names long enough to tolerate edits
    if len(norm_player) >= 8:
        best_dist = 999
        best_ep = None
        for ep in espn_players:
            norm_espn = normalize(ep["name"])
            d = _edit_distance(norm_player, norm_espn)
            # Allow up to 3 edits for long names, 2 for shorter
            max_edits = 3 if len(norm_player) >= 12 else 2
            if d <= max_edits and d < best_dist:
                best_dist = d
                best_ep = ep
        if best_ep:
            return best_ep["height_cm"]

    return None


def _edit_distance(a: str, b: str) -> int:
    """Compute Levenshtein edit distance between two strings."""
    if len(a) < len(b):
        return _edit_distance(b, a)
    if len(b) == 0:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            cost = 0 if ca == cb else 1
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + cost))
        prev = curr
    return prev[-1]


def read_rosters_js() -> tuple[str, dict]:
    """Read rosters.js and parse the JSON object. Return (header, rosters_dict)."""
    text = ROSTERS_PATH.read_text(encoding="utf-8")

    # Find the assignment: window.WC_ROSTERS = {
    match = re.search(r"(window\.WC_ROSTERS\s*=\s*)", text)
    if not match:
        raise ValueError("Could not find 'window.WC_ROSTERS =' in rosters.js")

    start = match.end()  # position of the opening {
    end = text.rindex("};")
    json_text = text[start : end + 1]

    header = text[: match.start()].rstrip()
    rosters = json.loads(json_text)
    return header, rosters


def write_rosters_js(header: str, rosters: dict):
    """Write rosters.js back with the same structure."""
    # Build JSON with 2-space indent
    json_text = json.dumps(rosters, indent=2, ensure_ascii=False)

    # Write with the original header
    with open(ROSTERS_PATH, "w", encoding="utf-8") as f:
        if header:
            f.write(header + "\n")
        f.write("window.WC_ROSTERS = ")
        f.write(json_text)
        f.write(";\n")


def main():
    print("Reading rosters.js...")
    header, rosters = read_rosters_js()
    total_players = sum(len(v) for v in rosters.values())
    print(f"  {len(rosters)} teams, {total_players} players")

    print("\nFetching ESPN team list...")
    espn_teams = get_espn_teams()
    print(f"  {len(espn_teams)} ESPN teams found")

    matched = 0
    unmatched = 0
    missing_teams = []

    for our_team, players in rosters.items():
        # Map our team name to ESPN's
        espn_name = TEAM_NAME_MAP.get(our_team, our_team)
        espn_id = espn_teams.get(espn_name)

        if not espn_id:
            print(f"\n  WARNING: No ESPN team found for '{our_team}' (tried '{espn_name}')")
            missing_teams.append(our_team)
            for p in players:
                p["height"] = None
                unmatched += 1
            continue

        # Fetch ESPN roster
        try:
            espn_roster = get_espn_roster(espn_id)
        except Exception as e:
            print(f"\n  ERROR fetching roster for {our_team}: {e}")
            for p in players:
                p["height"] = None
                unmatched += 1
            continue

        # Small delay to be polite to the API
        time.sleep(0.15)

        team_matched = 0
        team_unmatched = 0
        unmatched_names = []

        for p in players:
            height = match_height(p["name"], espn_roster)
            # Fallback to manual heights for players missing from ESPN roster
            if height is None:
                height = MANUAL_HEIGHTS.get(p["name"])
            p["height"] = height
            if height is not None:
                team_matched += 1
                matched += 1
            else:
                team_unmatched += 1
                unmatched += 1
                unmatched_names.append(p["name"])

        status = f"  {our_team}: {team_matched}/{len(players)} matched"
        if team_unmatched:
            status += f" (missing: {', '.join(unmatched_names)})"
        print(status)

    print(f"\n{'='*60}")
    print(f"TOTAL: {matched}/{total_players} players matched ({unmatched} missing)")
    if missing_teams:
        print(f"Teams not found on ESPN: {missing_teams}")

    print("\nWriting updated rosters.js...")
    write_rosters_js(header, rosters)
    print("Done!")

    # Quick verification
    verify_text = ROSTERS_PATH.read_text(encoding="utf-8")
    if "height" in verify_text:
        # Count heights
        import re as _re
        height_values = _re.findall(r'"height":\s*(\d+|null)', verify_text)
        non_null = sum(1 for v in height_values if v != "null")
        null_count = sum(1 for v in height_values if v == "null")
        print(f"Verification: {len(height_values)} height entries ({non_null} with values, {null_count} null)")


if __name__ == "__main__":
    main()
