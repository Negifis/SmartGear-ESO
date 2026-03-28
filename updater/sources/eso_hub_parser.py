"""
ESO-Hub parser — fetches set data from eso-hub.com
"""
import json
import os
import re
import time
import requests
from bs4 import BeautifulSoup

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "cache")
BASE_URL = "https://eso-hub.com"
REQUEST_DELAY = 1.5

# Set category pages on ESO-Hub
SET_CATEGORIES = [
    {"url": "/en/sets?categories=Dungeon", "cache": "sets_dungeon", "category": "Dungeon"},
    {"url": "/en/sets?categories=Trial", "cache": "sets_trial", "category": "Trial"},
    {"url": "/en/sets?categories=Arena", "cache": "sets_arena", "category": "Arena"},
    {"url": "/en/sets?categories=Overland", "cache": "sets_overland", "category": "Overland"},
    {"url": "/en/sets?categories=Craftable", "cache": "sets_crafted", "category": "Crafted"},
    {"url": "/en/sets?categories=Monster", "cache": "sets_monster", "category": "Monster Set"},
    {"url": "/en/sets?categories=Mythics", "cache": "sets_mythic", "category": "Mythic"},
    {"url": "/en/sets?categories=PvP", "cache": "sets_pvp", "category": "PvP"},
]


def _get_cached_or_fetch(url, cache_name, use_cache=True):
    cache_path = os.path.join(CACHE_DIR, f"esohub_{cache_name}.html")
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
        print(f"[eso-hub] Error fetching {url}: {e}")
        if os.path.exists(cache_path):
            with open(cache_path, "r", encoding="utf-8") as f:
                return f.read()
        return None


def _extract_set_names(html, category):
    """Extract set names from a category listing page."""
    soup = BeautifulSoup(html, "lxml")
    sets = []

    # ESO-Hub lists sets as cards/links
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "/en/sets/" in href and href != "/en/sets":
            name = a.get_text(strip=True)
            if name and len(name) > 2 and len(name) < 60:
                # Skip navigation text
                if name.lower() not in ("sets", "home", "builds", "guides"):
                    sets.append({
                        "name": name,
                        "category": category,
                        "url": href if href.startswith("http") else f"{BASE_URL}{href}",
                    })

    return sets


def parse_eso_hub_sets(use_cache=True):
    """Parse ESO-Hub set listings.
    Returns: list of {"set_name": str, "category": str, "source": "eso-hub", "weight": 1}
    """
    print("[eso-hub] Parsing set categories...")
    results = []

    for cat in SET_CATEGORIES:
        url = f"{BASE_URL}{cat['url']}"
        html = _get_cached_or_fetch(url, cat["cache"], use_cache=use_cache)
        if not html:
            continue

        sets = _extract_set_names(html, cat["category"])
        for s in sets:
            results.append({
                "set_name": s["name"],
                "category": s["category"],
                "source": "eso-hub",
                "weight": 1,
            })

        print(f"[eso-hub] {cat['category']}: {len(sets)} sets")

    print(f"[eso-hub] Total: {len(results)} set entries")
    return results
