#!/usr/bin/env python3
"""Generate per-match recaps using the Anthropic API.

Runs hourly via GitHub Actions. For each completed match that ended 3+ hours
ago and doesn't already have a recap, generates a narrative recap in the same
style as the daily recaps.
"""

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
DATA = Path(__file__).resolve().parent.parent / "data"
MATCHES_PATH = DATA / "matches.json"
RECAPS_PATH = DATA / "match-recaps.json"
FACTS_PATH = DATA / "match-facts.json"

GAME_DURATION_HOURS = 2
POST_MATCH_DELAY_HOURS = 3
TOTAL_DELAY = GAME_DURATION_HOURS + POST_MATCH_DELAY_HOURS
MAX_PER_RUN = 10

# Stage names for display
STAGE_LABELS = {
    "Group Stage": "group stage",
    "Round of 32": "Round of 32",
    "Round of 16": "Round of 16",
    "Quarter-finals": "quarterfinals",
    "Semi-finals": "semifinals",
    "Third-place Match": "third-place match",
    "Final": "final",
}

NEXT_STAGE = {
    "Round of 32": "Round of 16",
    "Round of 16": "Quarter-finals",
    "Quarter-finals": "Semi-finals",
    "Semi-finals": "Final",
}

# Bracket mapping: winner of match N plays in match M (and which side).
# FIFA 2026 bracket: R32 (73-88) → R16 (89-96) → QF (97-100) → SF (101-102) → F (104)
BRACKET = {
    73: (90, "home"), 76: (90, "away"),
    74: (89, "home"), 75: (89, "away"),
    78: (91, "home"), 77: (91, "away"),
    79: (92, "home"), 80: (92, "away"),
    82: (93, "home"), 81: (93, "away"),
    84: (94, "home"), 83: (94, "away"),
    85: (95, "home"), 88: (95, "away"),
    86: (96, "home"), 87: (96, "away"),
    89: (97, "home"), 90: (97, "away"),
    91: (98, "home"), 92: (98, "away"),
    93: (99, "home"), 94: (99, "away"),
    95: (100, "home"), 96: (100, "away"),
    97: (101, "home"), 98: (101, "away"),
    99: (102, "home"), 100: (102, "away"),
    101: (104, "home"), 102: (104, "away"),
}


def call_claude(prompt):
    payload = {
        "model": "claude-opus-4-8",
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        ANTHROPIC_API,
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": os.environ["ANTHROPIC_API_KEY"],
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.load(resp)
    return result["content"][0]["text"]


def load_json(path):
    if not path.exists():
        return {} if path.suffix == ".json" else []
    with open(path) as f:
        return json.load(f)


def matches_needing_recaps(matches, existing_recaps):
    """Find completed matches that ended 3+ hours ago without recaps.

    Returns newest matches first so recent games get recaps before
    the historical backlog.
    """
    now = datetime.now(timezone.utc)
    need = []
    for m in matches:
        n = str(m["n"])
        if n in existing_recaps:
            continue
        if m.get("scoreH") is None:
            continue
        kickoff = datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        ended_approx = kickoff + timedelta(hours=TOTAL_DELAY)
        if now >= ended_approx:
            need.append(m)
    need.sort(key=lambda m: m["utc"], reverse=True)
    return need


def find_next_match_info(match, all_matches):
    """For knockout matches, describe who the winner plays next."""
    n = match["n"]
    if n not in BRACKET:
        return None
    next_n, side = BRACKET[n]
    next_match = next(
        (m for m in all_matches if m["n"] == next_n), None
    )
    if not next_match:
        return None

    other_side = "away" if side == "home" else "home"
    opponent = next_match.get(other_side, "To be announced")

    kickoff = datetime.strptime(next_match["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    # Format: "Monday, June 29 at 10:00 AM PT"
    pt = kickoff - timedelta(hours=7)
    day_str = pt.strftime("%A, %B %-d")
    time_str = pt.strftime("%-I:%M %p PT").replace(" 0", " ")

    if opponent == "To be announced":
        # Find which match feeds into the other side
        other_feeder = None
        for src_n, (dst_n, dst_side) in BRACKET.items():
            if dst_n == next_n and dst_side == other_side:
                other_feeder = next(
                    (m for m in all_matches if m["n"] == src_n), None
                )
                break
        if other_feeder:
            opponent_desc = f"the winner of {other_feeder['home']} vs {other_feeder['away']}"
        else:
            opponent_desc = "an opponent still to be determined"
    else:
        opponent_desc = opponent

    return {
        "stage": next_match["stage"],
        "opponent": opponent_desc,
        "date": day_str,
        "time": time_str,
        "venue": next_match["venue"],
        "city": next_match["city"],
    }


def group_standings_context(match, all_matches):
    """For group stage matches, compute current group standings."""
    if match.get("stage") != "Group Stage" or not match.get("group"):
        return None
    group = match["group"]
    group_matches = [
        m
        for m in all_matches
        if m.get("group") == group and m.get("scoreH") is not None
    ]
    teams = {}
    for m in group_matches:
        for side, opp_side in [("home", "away"), ("away", "home")]:
            t = m[side]
            if t not in teams:
                teams[t] = {"pts": 0, "gf": 0, "ga": 0, "w": 0, "d": 0, "l": 0, "gp": 0}
            s = teams[t]
            s["gp"] += 1
            s["gf"] += m[f"score{'H' if side == 'home' else 'A'}"]
            s["ga"] += m[f"score{'A' if side == 'home' else 'H'}"]
            gs = m[f"score{'H' if side == 'home' else 'A'}"]
            gc = m[f"score{'A' if side == 'home' else 'H'}"]
            if gs > gc:
                s["w"] += 1
                s["pts"] += 3
            elif gs == gc:
                s["d"] += 1
                s["pts"] += 1
            else:
                s["l"] += 1

    standings = sorted(
        teams.items(), key=lambda x: (-x[1]["pts"], -(x[1]["gf"] - x[1]["ga"]), -x[1]["gf"])
    )
    lines = [f"{group} standings after this match:"]
    for i, (t, s) in enumerate(standings, 1):
        gd = s["gf"] - s["ga"]
        gd_str = f"+{gd}" if gd > 0 else str(gd)
        lines.append(f"  {i}. {t} - {s['pts']}pts ({s['w']}W {s['d']}D {s['l']}L, GD {gd_str})")

    total_group_matches = len([m for m in all_matches if m.get("group") == group])
    completed = len(group_matches)
    if completed < total_group_matches:
        lines.append(f"  ({completed}/{total_group_matches} matches played)")
    else:
        lines.append("  (All group matches complete)")
        lines.append("  Top 2 advance to the Round of 32, plus the best 8 third-placed teams")
    return "\n".join(lines)


def build_prompt(match, all_matches, facts):
    """Build the prompt for Claude to write a match recap."""
    n = str(match["n"])
    home, away = match["home"], match["away"]
    sh, sa = match["scoreH"], match["scoreA"]
    stage_label = STAGE_LABELS.get(match["stage"], match["stage"])

    kickoff = datetime.strptime(match["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    date_str = kickoff.strftime("%B %-d, %Y")

    result = match.get("result")
    pkH, pkA = match.get("pkH"), match.get("pkA")

    # Build score line with ET/PK detail
    score_line = f"Match {match['n']}: {home} {sh}-{sa} {away}"
    if result == "PEN" and pkH is not None and pkA is not None:
        score_line += f" (after extra time; penalty shootout: {home} {pkH}-{pkA} {away})"
    elif result == "AET":
        score_line += " (after extra time)"

    context_parts = [
        score_line,
        f"Stage: {stage_label}" + (f" ({match['group']})" if match.get("group") else ""),
        f"Date: {date_str}",
        f"Venue: {match['venue']}, {match['city']}",
    ]

    # Add extra time / penalty context
    if result == "PEN" and pkH is not None and pkA is not None:
        pk_winner = home if pkH > pkA else away
        pk_loser = away if pkH > pkA else home
        context_parts.append(
            f"\nThis match went to penalties after extra time. "
            f"The score was level at {sh}-{sa} after 120 minutes. "
            f"Penalty shootout: {home} {pkH}-{pkA} {away}. "
            f"{pk_winner} win on penalties, {pk_loser} eliminated."
        )
    elif result == "AET":
        context_parts.append(
            f"\nThis match was decided in extra time (120 minutes). "
            f"The match could not be settled in regular 90 minutes."
        )

    # Add match facts if available
    match_facts = facts.get(n, {}).get("facts", [])
    if match_facts:
        context_parts.append("\nKey facts about this match:")
        for fact in match_facts:
            context_parts.append(f"  - {fact}")

    # Add group standings context
    standings = group_standings_context(match, all_matches)
    if standings:
        context_parts.append(f"\n{standings}")

    # Add next match info for knockout stages
    is_knockout = match["stage"] != "Group Stage"
    if is_knockout:
        if sh > sa:
            winner, loser = home, away
        elif sa > sh:
            winner, loser = away, home
        elif pkH is not None and pkA is not None:
            # Tied after ET, decided by penalties
            if pkH > pkA:
                winner, loser = home, away
            else:
                winner, loser = away, home
        else:
            winner, loser = None, None

        next_info = find_next_match_info(match, all_matches)
        if next_info and winner:
            context_parts.append(
                f"\n{winner} advance to the {next_info['stage']} "
                f"and will face {next_info['opponent']} on {next_info['date']} "
                f"at {next_info['time']} at {next_info['venue']}, {next_info['city']}."
            )
            context_parts.append(f"{loser} are eliminated from the tournament.")
    else:
        # For group stage, figure out remaining matches
        group = match.get("group")
        if group:
            remaining = [
                m for m in all_matches
                if m.get("group") == group and m.get("scoreH") is None
            ]
            if remaining:
                context_parts.append(f"\nRemaining {group} matches:")
                for rm in remaining:
                    rk = datetime.strptime(rm["utc"], "%Y-%m-%dT%H:%M:%SZ").replace(
                        tzinfo=timezone.utc
                    )
                    pt = rk - timedelta(hours=7)
                    context_parts.append(
                        f"  - {rm['home']} vs {rm['away']} "
                        f"({pt.strftime('%A, %B %-d at %-I:%M %p PT')})"
                    )
            else:
                context_parts.append(f"\nAll {group} matches are complete.")
                context_parts.append(
                    "Top 2 teams qualify for Round of 32, plus the best 8 third-placed teams."
                )

    # Sample daily recap for style reference
    sample = (
        '**Argentina** put the group stage to bed in style, romping to a 3-1 win over '
        '**Jordan** in **Group J** at AT&T Stadium to book their place in the knockouts. '
        'Lionel Messi came off the bench to become the first player in history to score in '
        'seven consecutive tournament matches — a streak dating back to the 2022 round of 16 '
        'against Australia — extending his all-time record to 19 goals.'
    )

    prompt = f"""Write a match recap for this football match. Here is the match data:

{chr(10).join(context_parts)}

STYLE GUIDE — write EXACTLY like this example from the daily recaps:
"{sample}"

Rules:
- Bold team names with **Team Name** markdown
- Narrative third-person tone, factual but with personality
- 2-3 paragraphs, 150-300 words total
- Include the score and key match facts/trivia naturally in the text
- NEVER use "World Cup" or "FIFA" — say "the tournament" or "Football 2026" instead
- NEVER use "tie" to mean a match/fixture (Americans read it as a draw) — say "match", "game", or "matchup"
- Be explicit about what the result means: does a team advance, is a team eliminated, what do they need, who do they play next (include day, time in PT, and venue)?
- For group stage: explain what each team needs going forward, or if the group is decided
- For knockouts: state clearly who advances and who is eliminated, and who/when/where is the next match
- Don't start with the team name — vary your sentence openers
- Include the venue name naturally in the text
- If there are interesting facts or records, weave them in (don't just list them)
- Do NOT add a title or heading — just the recap text

Return ONLY the recap text, no quotes or markdown code blocks."""

    return prompt


def main():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ANTHROPIC_API_KEY not set, skipping recap generation.")
        sys.exit(0)

    matches = load_json(MATCHES_PATH)
    if isinstance(matches, dict):
        matches = list(matches.values())
    recaps = load_json(RECAPS_PATH)
    facts = load_json(FACTS_PATH)

    need = matches_needing_recaps(matches, recaps)
    if not need:
        print("No matches need recaps right now.")
        return

    print(f"{len(need)} match(es) need recaps.")
    if len(need) > MAX_PER_RUN:
        print(f"  Capping to {MAX_PER_RUN} per run; remainder will be picked up next run.")
        need = need[:MAX_PER_RUN]
    changed = False
    for match in need:
        n = str(match["n"])
        print(f"  Generating recap for match {n}: {match['home']} vs {match['away']}...")
        try:
            prompt = build_prompt(match, matches, facts)
            recap_text = call_claude(prompt)
            recap_text = recap_text.strip().strip('"').strip("```").strip()
            recaps[n] = recap_text
            changed = True
            print(f"    Done ({len(recap_text)} chars)")
        except Exception as e:
            print(f"    ERROR: {e}")
            continue

    if changed:
        ordered = dict(sorted(recaps.items(), key=lambda x: int(x[0])))
        with open(RECAPS_PATH, "w") as f:
            json.dump(ordered, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Wrote {len(ordered)} recaps to {RECAPS_PATH.name}")


if __name__ == "__main__":
    main()
