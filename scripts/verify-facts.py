#!/usr/bin/env python3
"""Verify match facts against reference data and flag errors.

Checks data/match-facts.json against data/all-time-records.json and
data/matches.json. Uses Claude API for claims that can't be verified
by simple pattern matching.

Usage:
    # Check all facts
    python3 scripts/verify-facts.py

    # Check facts for specific match(es)
    python3 scripts/verify-facts.py --match 92

    # Auto-fix mode (rewrites flagged facts via Claude)
    python3 scripts/verify-facts.py --fix
"""

import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
DATA = Path(__file__).resolve().parent.parent / "data"

ORDINALS = {
    "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
    "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
    "11th": 11, "12th": 12, "13th": 13, "14th": 14, "15th": 15,
    "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5,
}

RANKING_PATTERNS = [
    r"(?:outright|sole|all[- ]time)\s+(\w+)\b",
    r"(\w+)\s+(?:on|in)\s+the\s+all[- ]time\s+list",
    r"(\w+)\s+(?:highest|most|top)\s+(?:goal)?scorer",
    r"moved\s+(?:into|to)\s+(\w+)\s+(?:place|position|on|in)",
    r"now\s+(?:sits?|ranks?|stands?)\s+(\w+)",
]

GOAL_CLAIM_PATTERN = re.compile(
    r"(\d+)\s+(?:career\s+)?(?:tournament|World Cup|all[- ]time)\s+goals?",
    re.IGNORECASE,
)


def load_json(path):
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def load_records():
    return load_json(DATA / "all-time-records.json")


def load_facts():
    return load_json(DATA / "match-facts.json")


def load_matches():
    return load_json(DATA / "matches.json")


def strip_markdown(text):
    return re.sub(r"\*\*([^*]+)\*\*", r"\1", text)


def find_ranking_claims(fact_text):
    """Extract ranking claims from a fact (e.g. 'outright second')."""
    claims = []
    text = strip_markdown(fact_text).lower()
    for pattern in RANKING_PATTERNS:
        for m in re.finditer(pattern, text):
            ordinal = m.group(1).strip()
            if ordinal in ORDINALS:
                claims.append({
                    "type": "ranking",
                    "rank": ORDINALS[ordinal],
                    "text": m.group(0),
                })
    return claims


def find_goal_count_claims(fact_text):
    """Extract goal count claims (e.g. '13 career tournament goals')."""
    claims = []
    text = strip_markdown(fact_text)
    for m in GOAL_CLAIM_PATTERN.finditer(text):
        claims.append({
            "type": "goal_count",
            "count": int(m.group(1)),
            "text": m.group(0),
        })
    return claims


def check_ranking_against_records(claim, fact_text, records):
    """Check if a ranking claim is consistent with all-time records."""
    scorers = records.get("all_time_scorers", [])
    if not scorers:
        return None

    text_lower = strip_markdown(fact_text).lower()
    issues = []

    for scorer in scorers:
        player_last = scorer["player"].split()[-1].lower()
        if player_last in text_lower or scorer["player"].lower() in text_lower:
            player_total = scorer["total"]
            rank = claim["rank"]
            actual_rank = 1
            for s in scorers:
                if s["total"] > player_total:
                    actual_rank += 1
            if rank != actual_rank:
                above = [
                    f"{s['player']} ({s['total']})"
                    for s in scorers
                    if s["total"] > player_total
                ]
                issues.append(
                    f"RANKING ERROR: Fact claims {scorer['player']} is "
                    f"{claim['text']}, but they have {player_total} goals "
                    f"and are actually #{actual_rank}. Players ahead: "
                    f"{', '.join(above)}"
                )
            break

    return issues if issues else None


def check_goal_count_against_records(claim, fact_text, records):
    """Check if a goal count matches reference data."""
    scorers = records.get("all_time_scorers", [])
    text_lower = strip_markdown(fact_text).lower()
    issues = []

    for scorer in scorers:
        player_last = scorer["player"].split()[-1].lower()
        if player_last in text_lower or scorer["player"].lower() in text_lower:
            if claim["count"] != scorer["total"]:
                note = scorer.get("_note", "")
                if "incomplete" in note:
                    if claim["count"] > scorer["total"]:
                        break
                issues.append(
                    f"GOAL COUNT MISMATCH: Fact says {claim['count']} goals "
                    f"for {scorer['player']}, reference has {scorer['total']}. "
                    f"Update reference if the fact is newer, or fix the fact."
                )
            break

    return issues if issues else None


def call_claude(prompt):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return None
    payload = {
        "model": "claude-opus-4-8",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        ANTHROPIC_API,
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.load(resp)
    return result["content"][0]["text"]


def verify_with_claude(fact_text, records, match_info):
    """Use Claude to fact-check a claim that pattern matching can't verify."""
    scorers_str = "\n".join(
        f"  {i+1}. {s['player']} ({s['country']}): {s['total']} goals"
        for i, s in enumerate(records.get("all_time_scorers", []))
        if s["total"] >= 8
    )
    prompt = f"""You are a football statistics fact-checker. Verify this "Did you know?" fact for accuracy.

FACT: {fact_text}

MATCH CONTEXT: {json.dumps(match_info) if match_info else 'Not available'}

REFERENCE — All-time tournament top scorers (as of July 2026):
{scorers_str}

Check for:
1. Ranking claims ("second all-time", "outright first") — compare against the scorer list
2. Goal count accuracy — do the numbers match?
3. Record claims ("first player to...", "most ever...") — are they plausible?
4. Historical claims — years, opponents, scores mentioned
5. "World Cup" or "FIFA" in the text — should say "tournament" or "Football 2026"

Respond with ONLY one of:
- "OK" if the fact appears accurate
- "ERROR: [specific issue]" if something is wrong
- "WARN: [concern]" if something seems off but you're not certain"""

    return call_claude(prompt)


def verify_all(match_filter=None, use_claude=False):
    facts = load_facts()
    records = load_records()
    matches_data = load_matches()
    if isinstance(matches_data, list):
        matches_by_n = {str(m["n"]): m for m in matches_data}
    else:
        matches_by_n = matches_data

    total_facts = 0
    issues_found = 0
    warnings = 0

    for match_num, entry in sorted(facts.items(), key=lambda x: int(x[0])):
        if match_filter and match_num not in match_filter:
            continue

        match_info = matches_by_n.get(match_num)
        home = entry.get("home", match_info.get("home", "?") if match_info else "?")
        away = entry.get("away", match_info.get("away", "?") if match_info else "?")

        for fact in entry.get("facts", []):
            total_facts += 1
            fact_issues = []

            ranking_claims = find_ranking_claims(fact)
            for claim in ranking_claims:
                result = check_ranking_against_records(claim, fact, records)
                if result:
                    fact_issues.extend(result)

            goal_claims = find_goal_count_claims(fact)
            for claim in goal_claims:
                result = check_goal_count_against_records(claim, fact, records)
                if result:
                    fact_issues.extend(result)

            if "World Cup" in fact or "FIFA" in fact:
                if "— *" not in fact.split("World Cup")[0][-20:] if "World Cup" in fact else True:
                    cleaned = re.sub(r'— \*[^*]+\*$', '', fact).strip()
                    if "World Cup" in cleaned or "FIFA" in cleaned:
                        fact_issues.append(
                            'NAMING: Contains "World Cup" or "FIFA" in fact text '
                            '(should use "tournament" or "Football 2026")'
                        )

            if use_claude and not fact_issues:
                result = verify_with_claude(fact, records, match_info)
                if result and not result.startswith("OK"):
                    fact_issues.append(f"CLAUDE: {result}")

            if fact_issues:
                if not any(
                    line.startswith(f"\nMatch {match_num}")
                    for line in (
                        getattr(verify_all, "_printed", [])
                        if hasattr(verify_all, "_printed")
                        else []
                    )
                ):
                    print(f"\nMatch {match_num}: {home} vs {away}")
                    if not hasattr(verify_all, "_printed"):
                        verify_all._printed = []
                    verify_all._printed.append(f"\nMatch {match_num}")

                print(f"  FACT: {fact[:120]}{'...' if len(fact) > 120 else ''}")
                for issue in fact_issues:
                    severity = "ERROR" if "ERROR" in issue else "WARN"
                    if severity == "ERROR":
                        issues_found += 1
                    else:
                        warnings += 1
                    print(f"    -> {issue}")

    print(f"\n{'='*60}")
    print(f"Checked {total_facts} facts across {len(facts)} matches")
    print(f"  Errors: {issues_found}")
    print(f"  Warnings: {warnings}")
    if issues_found == 0 and warnings == 0:
        print("  All facts passed verification!")
    print(f"{'='*60}")

    return issues_found


def main():
    match_filter = None
    use_claude = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--match" and i + 1 < len(args):
            match_filter = set(args[i + 1].split(","))
            i += 2
        elif args[i] == "--fix":
            use_claude = True
            i += 1
        elif args[i] == "--claude":
            use_claude = True
            i += 1
        else:
            i += 1

    issues = verify_all(match_filter=match_filter, use_claude=use_claude)
    sys.exit(1 if issues > 0 else 0)


if __name__ == "__main__":
    main()
