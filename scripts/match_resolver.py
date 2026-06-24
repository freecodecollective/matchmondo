"""Pure logic for "given an ESPN event (home/away/kickoff), which fixture in
our matches list does it correspond to?"

Mirror of MatchMondo/Services/MatchResolver.swift on the iOS side. Keep the
two implementations in lockstep — when one changes, change the other.

History: this used to be inlined inside each caller as "first match where
name OR time matches." That looks fine until two fixtures share a kickoff
slot — then the OR-rule grabs the wrong one and silently drops the right
one's score. Bit Bosnia v Qatar on 2026-06-23 and Morocco v Haiti on
2026-06-24 (Haiti showed "Full Time" mid-game; standings marked them
"out" as a side effect). Tests live in test_match_resolver.py.
"""

from datetime import datetime, timezone

# Maximum kickoff-time delta we treat as "same slot" when falling back to
# time-only matching. Two minutes covers small ESPN/fixture-feed drift
# without spilling into the adjacent kickoff slot (~30 min away).
KICKOFF_SLOT_TOLERANCE_SECONDS = 120


def resolve(matches, home_name, away_name, kickoff_ts):
    """Return the matches[] index for the ESPN event, or None.

    Resolution rule:
      1. Exact name match wins — `m["home"] == home_name && m["away"] == away_name`.
      2. If no name match, fall back to kickoff time match — but ONLY when the
         slot contains exactly one fixture. Multi-game slots without a name
         match are skipped (returns None) — better no patch than the wrong one.

    Args:
      matches: list of dicts with at least keys "home", "away", "utc"
        (ISO-8601 string like "2026-06-24T19:00:00Z").
      home_name: the ESPN event's home team name, normalized for our schema.
      away_name: ditto, away.
      kickoff_ts: the ESPN event's kickoff as a unix timestamp (seconds).

    Returns:
      Integer index into `matches`, or None if no confident match exists.
    """
    for i, m in enumerate(matches):
        if m["home"] == home_name and m["away"] == away_name:
            return i

    slot_candidates = []
    for i, m in enumerate(matches):
        m_ts = (
            datetime.strptime(m["utc"], "%Y-%m-%dT%H:%M:%SZ")
            .replace(tzinfo=timezone.utc)
            .timestamp()
        )
        if abs(m_ts - kickoff_ts) < KICKOFF_SLOT_TOLERANCE_SECONDS:
            slot_candidates.append(i)
    if len(slot_candidates) == 1:
        return slot_candidates[0]
    return None
