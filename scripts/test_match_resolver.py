"""Tests for match_resolver.resolve — the cross-language match-resolution rule.

Run: `python3 -m unittest scripts.test_match_resolver -v`
"""

import unittest
from datetime import datetime, timezone

from match_resolver import resolve


def ts(iso_z: str) -> float:
    """Convert "YYYY-MM-DDTHH:MM:SSZ" to a unix timestamp."""
    return (
        datetime.strptime(iso_z, "%Y-%m-%dT%H:%M:%SZ")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )


# A representative sample of the same-slot scenario that motivated the
# extraction: matches 49 and 50 both at 22:00 UTC on Matchday 14.
SAME_SLOT_MATCHES = [
    {"home": "Morocco",  "away": "Haiti",  "utc": "2026-06-24T22:00:00Z"},
    {"home": "Scotland", "away": "Brazil", "utc": "2026-06-24T22:00:00Z"},
]


class TestResolve(unittest.TestCase):
    # ---- Name match wins -------------------------------------------------
    def test_exact_name_match_returns_index(self):
        idx = resolve(SAME_SLOT_MATCHES, "Morocco", "Haiti", ts("2026-06-24T22:00:00Z"))
        self.assertEqual(idx, 0)

    def test_exact_name_match_for_second_fixture(self):
        idx = resolve(SAME_SLOT_MATCHES, "Scotland", "Brazil", ts("2026-06-24T22:00:00Z"))
        self.assertEqual(idx, 1)

    def test_name_match_wins_even_if_time_drifts(self):
        # Same fixture, ESPN reports kickoff a few seconds off — name still wins.
        idx = resolve(SAME_SLOT_MATCHES, "Morocco", "Haiti", ts("2026-06-24T22:00:00Z") + 90)
        self.assertEqual(idx, 0)

    # ---- The bug it was extracted to fix ---------------------------------
    def test_same_slot_no_name_match_returns_none(self):
        # Misspelled names — both fixtures share the slot, so we refuse to
        # guess. Pre-fix this would have grabbed the first one by time.
        idx = resolve(SAME_SLOT_MATCHES, "Marocco", "Haïti", ts("2026-06-24T22:00:00Z"))
        self.assertIsNone(idx)

    def test_same_slot_name_match_against_second_fixture_picks_second(self):
        # Verifies pre-fix bug: when the order in matches[] puts Scotland-Brazil
        # first, an event for Morocco-Haiti would have erroneously picked
        # Scotland-Brazil by time. With the fix, the name match wins.
        reversed_order = list(reversed(SAME_SLOT_MATCHES))
        idx = resolve(reversed_order, "Morocco", "Haiti", ts("2026-06-24T22:00:00Z"))
        self.assertEqual(reversed_order[idx]["home"], "Morocco")

    # ---- Time fallback (only when unique) --------------------------------
    def test_unique_slot_time_match_returns_index(self):
        matches = [
            {"home": "Mexico",   "away": "Argentina", "utc": "2026-07-01T20:00:00Z"},
            {"home": "Germany",  "away": "France",    "utc": "2026-07-01T23:00:00Z"},
        ]
        # ESPN reports the second fixture's slot with names we don't recognize
        # (e.g. drift in our team-name map) — single match in the slot, so
        # time fallback wins.
        idx = resolve(matches, "Deutschland", "France", ts("2026-07-01T23:00:00Z"))
        self.assertEqual(idx, 1)

    def test_no_name_no_time_returns_none(self):
        matches = [
            {"home": "Mexico", "away": "Argentina", "utc": "2026-07-01T20:00:00Z"},
        ]
        idx = resolve(matches, "Korea Republic", "Japan", ts("2026-07-02T09:00:00Z"))
        self.assertIsNone(idx)

    def test_empty_matches_returns_none(self):
        self.assertIsNone(resolve([], "Anywhere", "Anywhere", ts("2026-06-24T22:00:00Z")))

    # ---- Time tolerance boundary ----------------------------------------
    def test_time_match_inside_tolerance(self):
        matches = [{"home": "X", "away": "Y", "utc": "2026-06-24T22:00:00Z"}]
        # 119 seconds off — inside 120s window, should match.
        idx = resolve(matches, "Foo", "Bar", ts("2026-06-24T22:00:00Z") + 119)
        self.assertEqual(idx, 0)

    def test_time_match_outside_tolerance(self):
        matches = [{"home": "X", "away": "Y", "utc": "2026-06-24T22:00:00Z"}]
        # 121 seconds off — outside the window, no match.
        idx = resolve(matches, "Foo", "Bar", ts("2026-06-24T22:00:00Z") + 121)
        self.assertIsNone(idx)


if __name__ == "__main__":
    unittest.main()
