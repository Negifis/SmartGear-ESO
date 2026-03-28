"""
ESO-Sets API client — fetches all set data from eso-sets.com
"""
import json
import os
import time
import requests

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "cache")
CACHE_FILE = os.path.join(CACHE_DIR, "eso_sets.json")
# Multiple API URLs to try (primary, fallbacks)
API_URLS = [
    "https://eso-sets.herokuapp.com/sets",
    "https://eso-sets.com/api/sets",
    "https://esosets.com/api/sets",
]
CACHE_TTL = 86400 * 7  # 7 days


def _is_cache_valid():
    if not os.path.exists(CACHE_FILE):
        return False
    age = time.time() - os.path.getmtime(CACHE_FILE)
    return age < CACHE_TTL


def fetch_all_sets(use_cache=True):
    """Fetch all ESO sets from eso-sets.com API.
    Returns list of set dicts with normalized fields.
    """
    if use_cache and _is_cache_valid():
        print("[eso-sets] Loading from cache...")
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)

    print("[eso-sets] Fetching all sets from API...")
    raw_sets = None
    for api_url in API_URLS:
        try:
            print(f"[eso-sets] Trying {api_url}...")
            resp = requests.get(api_url, timeout=15, headers={
                "User-Agent": "SmartGear-Updater/1.0"
            })
            resp.raise_for_status()
            raw_sets = resp.json()
            print(f"[eso-sets] Success from {api_url}")
            break
        except Exception as e:
            print(f"[eso-sets] Failed: {e}")
            continue

    if raw_sets is None:
        print("[eso-sets] All API endpoints failed")
        if os.path.exists(CACHE_FILE):
            print("[eso-sets] Falling back to stale cache")
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        return []

    # Normalize
    sets = []
    for s in raw_sets:
        normalized = normalize_set(s)
        if normalized:
            sets.append(normalized)

    # Cache
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(sets, f, indent=2, ensure_ascii=False)

    print(f"[eso-sets] Fetched {len(sets)} sets")
    return sets


def normalize_set(raw):
    """Normalize a set from the API into our internal format."""
    name = raw.get("name", "").strip()
    if not name:
        return None

    set_type = raw.get("type", "").lower().strip()

    # Map API types to our categories
    type_map = {
        "dungeon": "Dungeon",
        "trial": "Trial",
        "arena": "Arena",
        "overland": "Overland",
        "craftable": "Crafted",
        "crafted": "Crafted",
        "monster set": "Monster Set",
        "monster": "Monster Set",
        "mythic": "Mythic",
        "pvp": "PvP",
        "battleground": "PvP",
        "cyrodiil": "PvP",
        "imperial city": "PvP",
        "rewards of the worthy": "PvP",
    }

    category = "Unknown"
    for key, val in type_map.items():
        if key in set_type:
            category = val
            break

    # Extract bonuses text
    bonuses = []
    for bonus in raw.get("bonuses", []):
        if isinstance(bonus, dict):
            bonuses.append(bonus.get("description", ""))
        elif isinstance(bonus, str):
            bonuses.append(bonus)

    return {
        "name": name,
        "category": category,
        "type_raw": raw.get("type", ""),
        "bonuses": bonuses,
        "bonuses_text": " | ".join(bonuses),
        "is_monster": category == "Monster Set",
        "is_mythic": category == "Mythic",
        "is_pvp": category == "PvP",
        "source": _guess_source(raw),
    }


def _guess_source(raw):
    """Try to extract source/location from set data."""
    # Different API versions may have different fields
    for field in ["location", "source", "dlc", "zone"]:
        val = raw.get(field, "")
        if val:
            return str(val)
    return raw.get("type", "Unknown")
