#!/usr/bin/env python3
"""Scrape Fox Sports YouTube channel for highlight and preview videos.

Sources:
  1. RSS feed (15 most recent — catches new uploads quickly)
  2. @foxsports/videos page (all visible recent uploads via ytInitialData)
  3. @foxsports/search for preview videos

Maps video titles to matches in data/matches.json by team-name matching.
Stores highlight and preview video IDs in data/highlights.json.
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
PREVIEW_SEARCH_URL = "https://www.youtube.com/@foxsports/search?query=preview+2026+world+cup"

HIGHLIGHT_RE = re.compile(
    r"^(.+?)\s+vs?\s+(.+?)\s+(Extended\s+)?Highlights\s+.+2026 FIFA World Cup",
    re.IGNORECASE,
)

PREVIEW_RE = re.compile(
    r"^(.+?)\s+vs?\s+(.+?)[:\s]+Preview",
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

_YT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept-Language": "en-US,en;q=0.9",
}


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


def _parse_yt_initial_data(html: str) -> dict | None:
    m = re.search(r'var ytInitialData\s*=\s*(\{.+?\});\s*</script>', html, re.DOTALL)
    if m:
        return json.loads(m.group(1))
    return None


def _extract_lockup_videos(data: dict) -> list[dict]:
    """Extract videos from lockupViewModel structure (used on /videos page)."""
    entries = []
    try:
        tabs = data['contents']['twoColumnBrowseResultsRenderer']['tabs']
        grid = tabs[1]['tabRenderer']['content']['richGridRenderer']['contents']
        for item in grid:
            ri = item.get('richItemRenderer', {})
            if not ri:
                continue
            lockup = ri.get('content', {}).get('lockupViewModel', {})
            vid = (lockup.get('rendererContext', {}).get('commandContext', {})
                   .get('onTap', {}).get('innertubeCommand', {})
                   .get('watchEndpoint', {}).get('videoId', ''))
            title = (lockup.get('metadata', {}).get('lockupMetadataViewModel', {})
                     .get('title', {}).get('content', ''))
            if vid and title and '2026' in title:
                entries.append({"title": title, "videoId": vid})
    except (KeyError, IndexError):
        pass
    return entries


def _extract_video_renderers(data: dict) -> list[dict]:
    """Extract videos from videoRenderer structure (used on /search page)."""
    results = []

    def walk(obj, depth=0):
        if depth > 25:
            return
        if isinstance(obj, dict):
            if 'videoRenderer' in obj:
                vr = obj['videoRenderer']
                vid = vr.get('videoId', '')
                title_runs = vr.get('title', {}).get('runs', [])
                title = ''.join(r.get('text', '') for r in title_runs)
                if vid and title and '2026' in title:
                    results.append({"title": title, "videoId": vid})
                return
            for v in obj.values():
                walk(v, depth + 1)
        elif isinstance(obj, list):
            for item in obj:
                walk(item, depth + 1)

    walk(data)
    return results


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
    """Scrape https://www.youtube.com/@foxsports/videos via ytInitialData."""
    req = urllib.request.Request(VIDEOS_URL, headers=_YT_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15, context=_ssl_ctx) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  Videos page failed: {e}")
        return []
    data = _parse_yt_initial_data(html)
    if not data:
        print("  Videos page: no ytInitialData found")
        return []
    return _extract_lockup_videos(data)


def fetch_preview_search() -> list[dict]:
    """Search Fox Sports channel for preview videos."""
    req = urllib.request.Request(PREVIEW_SEARCH_URL, headers=_YT_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15, context=_ssl_ctx) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  Preview search failed: {e}")
        return []
    data = _parse_yt_initial_data(html)
    if not data:
        print("  Preview search: no ytInitialData found")
        return []
    return _extract_video_renderers(data)


def process_entries(entries: list[dict], match_lookup: dict, highlights: dict) -> int:
    added = 0
    for entry in entries:
        title = entry["title"]
        video_id = entry["videoId"]

        # Try highlight pattern
        m = HIGHLIGHT_RE.match(title)
        if m:
            team_a = normalize(m.group(1))
            team_b = normalize(m.group(2))
            is_extended = bool(m.group(3))
            key = f"{team_a} vs {team_b}"
            match_n = match_lookup.get(key)
            if not match_n:
                continue
            n_str = str(match_n)
            if n_str not in highlights:
                highlights[n_str] = {}
            field = "extended" if is_extended else "short"
            if highlights[n_str].get(field) != video_id:
                old = highlights[n_str].get(field)
                highlights[n_str][field] = video_id
                label = "UPDATE" if old else "ADD"
                print(f"  {label}: Match {match_n} {field} = {video_id}")
                added += 1
            continue

        # Try preview pattern
        m = PREVIEW_RE.match(title)
        if m:
            team_a = normalize(m.group(1))
            team_b = normalize(m.group(2))
            key = f"{team_a} vs {team_b}"
            match_n = match_lookup.get(key)
            if not match_n:
                continue
            n_str = str(match_n)
            if n_str not in highlights:
                highlights[n_str] = {}
            if highlights[n_str].get("preview") != video_id:
                old = highlights[n_str].get("preview")
                highlights[n_str]["preview"] = video_id
                label = "UPDATE" if old else "ADD"
                print(f"  {label}: Match {match_n} preview = {video_id}")
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

    print("Checking @foxsports for preview videos...")
    preview_entries = fetch_preview_search()
    added += process_entries(preview_entries, match_lookup, highlights)

    OUT.write_text(json.dumps(highlights, indent=2, sort_keys=True) + "\n")
    print(f"\nWrote {len(highlights)} matches to {OUT} ({added} new/updated)")


if __name__ == "__main__":
    main()
