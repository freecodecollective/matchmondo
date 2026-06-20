#!/usr/bin/env python3
"""Scrape Fox Sports YouTube channel for highlight videos and update data/highlights.json.

Scrapes https://www.youtube.com/@foxsports/videos for recent uploads, plus the
RSS feed for fast pickup of brand-new videos. Maps highlight titles to matches
in data/matches.json by team-name matching.
"""
import json
import re
import ssl
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

SITE_ROOT = Path(__file__).resolve().parent.parent
MATCHES_JSON = SITE_ROOT / "data" / "matches.json"
OUT = SITE_ROOT / "data" / "highlights.json"

FOX_CHANNEL_ID = "UCwNqHDsnBCKT-olwJwIFyfg"
RSS_URL = f"https://www.youtube.com/feeds/videos.xml?channel_id={FOX_CHANNEL_ID}"
VIDEOS_URL = "https://www.youtube.com/@foxsports/videos"

# Strict pattern for Fox Sports titles
HIGHLIGHT_RE = re.compile(
    r"^(.+?)\s+vs?\s+(.+?)\s+(Extended\s+)?Highlights\s+.+2026 FIFA World Cup",
    re.IGNORECASE,
)

TEAM_ALIASES = {
    "United States": "USA",
    "Turkey": "Türkiye",
    "Turkiye": "Türkiye",
    "South Korea": "Korea Republic",
    "Ivory Coast": "Côte d'Ivoire",
    "Cote d'Ivoire": "Côte d'Ivoire",
    "Iran": "IR Iran",
    "Cape Verde": "Cabo Verde",
    "Czech Republic": "Czechia",
    "DR Congo": "Congo DR",
}

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE


def normalize(name: str) -> str:
    name = name.strip()
    return TEAM_ALIASES.get(name, name)


def load_matches() -> tuple[dict[str, int], list[dict]]:
    with open(MATCHES_JSON) as f:
        matches = json.load(f)
    lookup = {}
    for m in matches:
        h, a = m["home"], m["away"]
        lookup[f"{h} vs {a}"] = m["n"]
        lookup[f"{a} vs {h}"] = m["n"]
    return lookup, matches


def fetch_rss() -> list[dict]:
    req = urllib.request.Request(RSS_URL, headers={"User-Agent": "MatchMondo-highlights/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=15, context=_ssl_ctx) as resp:
            tree = ET.parse(resp)
    except Exception as e:
        print(f"  RSS feed failed: {e}")
        return []
    ns = {"atom": "http://www.w3.org/2005/Atom", "yt": "http://www.youtube.com/xml/schemas/2015"}
    entries = []
    for entry in tree.findall(".//atom:entry", ns):
        title = entry.findtext("atom:title", "", ns)
        video_id = entry.findtext("yt:videoId", "", ns)
        if title and video_id:
            entries.append({"title": title, "videoId": video_id})
    return entries


def fetch_videos_page() -> list[dict]:
    """Scrape https://www.youtube.com/@foxsports/videos for recent uploads."""
    req = urllib.request.Request(VIDEOS_URL, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    })
    try:
        with urllib.request.urlopen(req, timeout=15, context=_ssl_ctx) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  Videos page failed: {e}")
        return []

    pattern = r'"videoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})".*?"title":\{"runs":\[\{"text":"([^"]+?)"'
    seen = set()
    entries = []
    for vid, title in re.findall(pattern, html):
        if vid not in seen and "Highlights" in title and "2026" in title:
            seen.add(vid)
            entries.append({"title": title, "videoId": vid})
    return entries


def process_entries(entries: list[dict], match_lookup: dict, highlights: dict) -> int:
    """Process Fox Sports entries — always preferred over fallback sources."""
    added = 0
    for entry in entries:
        m = HIGHLIGHT_RE.match(entry["title"])
        if not m:
            continue

        team_a = normalize(m.group(1))
        team_b = normalize(m.group(2))
        is_extended = bool(m.group(3))
        video_id = entry["videoId"]

        key = f"{team_a} vs {team_b}"
        match_n = match_lookup.get(key)
        if not match_n:
            print(f"  SKIP: no match found for '{key}'")
            continue

        n_str = str(match_n)
        if n_str not in highlights:
            highlights[n_str] = {}

        field = "extended" if is_extended else "short"
        if highlights[n_str].get(field) != video_id:
            was_fallback = highlights[n_str].get(f"{field}_fallback", False)
            old = highlights[n_str].get(field)
            highlights[n_str][field] = video_id
            highlights[n_str].pop(f"{field}_fallback", None)
            label = "UPGRADE" if was_fallback else ("UPDATE" if old else "ADD")
            print(f"  {label}: Match {match_n} {field} = {video_id}")
            added += 1
    return added



def main() -> None:
    match_lookup, all_matches = load_matches()

    if OUT.exists():
        with open(OUT) as f:
            highlights = json.load(f)
    else:
        highlights = {}

    print("Checking RSS feed...")
    rss_entries = fetch_rss()
    added = process_entries(rss_entries, match_lookup, highlights)

    print("Checking @foxsports/videos page...")
    page_entries = fetch_videos_page()
    added += process_entries(page_entries, match_lookup, highlights)

    OUT.write_text(json.dumps(highlights, indent=2, sort_keys=True) + "\n")
    print(f"\nWrote {len(highlights)} matches to {OUT} ({added} new/updated)")


if __name__ == "__main__":
    main()
