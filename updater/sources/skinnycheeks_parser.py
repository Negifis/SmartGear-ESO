"""
Skinnycheeks parser — extracts DPS set tier lists from skinnycheeks.gg
"""
import json
import os
import re
import time
import requests
from bs4 import BeautifulSoup

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "cache")
BASE_URL = "https://www.skinnycheeks.gg"
REQUEST_DELAY = 1.5

# Key pages to parse
PAGES = [
    {"url": "/top-dps-sets", "cache": "top_sets", "default_role": "StamDD"},
    {"url": "/build-basics", "cache": "basics", "default_role": None},
]

# Class build pages
CLASS_PAGES = [
    {"url": "/sorcerer", "cache": "sorc"},
    {"url": "/nightblade", "cache": "nb"},
    {"url": "/dragonknight", "cache": "dk"},
    {"url": "/templar", "cache": "templar"},
    {"url": "/warden", "cache": "warden"},
    {"url": "/necromancer", "cache": "necro"},
    {"url": "/arcanist", "cache": "arcanist"},
]


def _get_cached_or_fetch(url, cache_name, use_cache=True):
    cache_path = os.path.join(CACHE_DIR, f"skinny_{cache_name}.html")
    os.makedirs(CACHE_DIR, exist_ok=True)

    if use_cache and os.path.exists(cache_path):
        age = time.time() - os.path.getmtime(cache_path)
        if age < 86400 * 3:
            with open(cache_path, "r", encoding="utf-8") as f:
                return f.read()

    try:
        time.sleep(REQUEST_DELAY)
        resp = requests.get(url, timeout=20, headers={
            "User-Agent": "SmartGear-Updater/1.0 (ESO Addon Meta Parser)",
        })
        resp.raise_for_status()
        html = resp.text
        with open(cache_path, "w", encoding="utf-8") as f:
            f.write(html)
        return html
    except Exception as e:
        print(f"[skinnycheeks] Error fetching {url}: {e}")
        if os.path.exists(cache_path):
            with open(cache_path, "r", encoding="utf-8") as f:
                return f.read()
        return None


def _extract_sets_from_tier_page(html):
    """Extract set names from a tier list page.
    Skinnycheeks often organizes sets in sections or lists.
    """
    soup = BeautifulSoup(html, "lxml")
    sets = []

    # Look for set names in headings, bold, links
    for tag in soup.find_all(["h1", "h2", "h3", "h4", "strong", "b", "a"]):
        text = tag.get_text(strip=True)
        if not text or len(text) < 4 or len(text) > 60:
            continue

        # Skip navigation/UI text
        if re.match(r"^(home|about|builds?|guide|menu|contact|search|cookie|privacy)", text, re.IGNORECASE):
            continue

        # Check for set-like names (capitalized words, common set patterns)
        if re.match(r"^[A-Z][a-z]", text) and "'" in text or len(text.split()) >= 2:
            sets.append(text)

    # Look for list items with set patterns
    for li in soup.find_all("li"):
        text = li.get_text(strip=True)
        # "Set Name – description" or "Set Name: description"
        match = re.match(r"^([A-Z][A-Za-z'\s\-]+?)(?:\s*[-–:]\s|$)", text)
        if match and len(match.group(1).strip()) > 4:
            sets.append(match.group(1).strip())

    return list(set(sets))


def _extract_sets_from_class_page(html):
    """Extract gear set names from a class build page."""
    soup = BeautifulSoup(html, "lxml")
    sets = []

    # Skinnycheeks uses gear setup sections with lettered configs (Setup A, Setup B, etc.)
    text = soup.get_text(" ", strip=True)

    # Pattern: common set name mentions near "setup" or "gear" keywords
    # Look for "5pc X" or "X (5pc)" patterns
    for match in re.finditer(r"(\d)\s*(?:pc|piece)\s+([A-Z][A-Za-z'\s\-]+?)(?:\s*[,\.\(\)]|$)", text):
        sets.append(match.group(2).strip())

    # Also try reverse: "Set Name (5pc)"
    for match in re.finditer(r"([A-Z][A-Za-z'\s\-]{3,40}?)\s*\(\s*(\d)\s*(?:pc|piece)", text):
        sets.append(match.group(1).strip())

    # Links to ESO set databases
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "eso-hub.com/en/sets/" in href or "eso-sets.com" in href:
            name = a.get_text(strip=True)
            if name and len(name) > 3:
                sets.append(name)

    return list(set(sets))


def parse_skinnycheeks(use_cache=True):
    """Parse Skinnycheeks pages for set data.
    Returns: list of {"set_name": str, "role": str, "source": "skinnycheeks", "weight": 2}
    """
    print("[skinnycheeks] Parsing tier lists and builds...")
    results = []

    # Parse top DPS sets page
    for page in PAGES:
        url = f"{BASE_URL}{page['url']}"
        html = _get_cached_or_fetch(url, page["cache"], use_cache=use_cache)
        if not html:
            continue

        sets = _extract_sets_from_tier_page(html)
        for sn in sets:
            # Top DPS sets are for both MagDD and StamDD
            for role in ["MagDD", "StamDD"]:
                results.append({
                    "set_name": sn,
                    "role": role,
                    "source": "skinnycheeks",
                    "weight": 2,
                })

    # Parse class pages
    for page in CLASS_PAGES:
        url = f"{BASE_URL}{page['url']}"
        html = _get_cached_or_fetch(url, page["cache"], use_cache=use_cache)
        if not html:
            continue

        sets = _extract_sets_from_class_page(html)
        for sn in sets:
            # Class pages are DPS-focused
            for role in ["MagDD", "StamDD"]:
                results.append({
                    "set_name": sn,
                    "role": role,
                    "source": "skinnycheeks",
                    "weight": 2,
                })

    print(f"[skinnycheeks] Extracted {len(results)} set mentions")
    return results
