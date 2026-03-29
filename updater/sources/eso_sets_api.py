"""
ESO Sets API client — fetches all set data from UESP (primary) or eso-sets.com (fallback)
"""
import json
import os
import re
import time
import requests

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "cache")
CACHE_FILE = os.path.join(CACHE_DIR, "eso_sets.json")
CACHE_TTL = 86400 * 7  # 7 days

# UESP is the primary source (reliable, 712+ sets)
UESP_URL = "https://esolog.uesp.net/exportJson.php?table=setSummary"


def _is_cache_valid():
    if not os.path.exists(CACHE_FILE):
        return False
    age = time.time() - os.path.getmtime(CACHE_FILE)
    return age < CACHE_TTL


def fetch_all_sets(use_cache=True):
    """Fetch all ESO sets from UESP API.
    Returns list of set dicts with normalized fields.
    """
    if use_cache and _is_cache_valid():
        print("[eso-sets] Loading from cache...")
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)

    print("[eso-sets] Fetching all sets from UESP...")
    raw_sets = None

    try:
        resp = requests.get(UESP_URL, timeout=30, headers={
            "User-Agent": "SmartGear-Updater/1.0 (ESO Addon)"
        })
        resp.raise_for_status()
        data = resp.json()
        raw_sets = data.get("setSummary", [])
        print(f"[eso-sets] UESP returned {len(raw_sets)} sets")
    except Exception as e:
        print(f"[eso-sets] UESP failed: {e}")
        if os.path.exists(CACHE_FILE):
            print("[eso-sets] Falling back to stale cache")
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        return []

    # Normalize
    sets = []
    for s in raw_sets:
        normalized = normalize_set_uesp(s)
        if normalized:
            sets.append(normalized)

    # Cache
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(sets, f, indent=2, ensure_ascii=False)

    print(f"[eso-sets] Normalized {len(sets)} sets")
    return sets


def normalize_set_uesp(raw):
    """Normalize a set from the UESP API."""
    name = raw.get("setName", "").strip()
    if not name:
        return None

    # Skip prototype/test sets
    if "prototype" in name.lower() or "test" in name.lower():
        return None

    max_equip = int(raw.get("setMaxEquipCount", 5))
    item_slots = raw.get("itemSlots", "")
    bonuses_text = raw.get("setBonusDesc", "")

    # Determine category from max equip count and item slots
    is_mythic = (max_equip == 1)
    is_monster = (max_equip == 2 and "Head" in item_slots and "Shoulder" in item_slots)

    # Try to detect category from sources or type field
    sources = raw.get("sources", "").lower()
    raw_type = raw.get("type", "").lower()
    raw_category = raw.get("category", "").lower()

    category = _guess_category(name, sources, raw_type, raw_category,
                                item_slots, is_mythic, is_monster)

    is_pvp = category == "PvP"

    return {
        "name": name,
        "category": category,
        "source": raw.get("sources", "") or category,
        "bonuses": [],
        "bonuses_text": bonuses_text,
        "is_monster": is_monster,
        "is_mythic": is_mythic,
        "is_pvp": is_pvp,
        "max_equip": max_equip,
        "item_slots": item_slots,
    }


def _guess_category(name, sources, raw_type, raw_category, item_slots, is_mythic, is_monster):
    """Guess set category from available data."""
    if is_mythic:
        return "Mythic"
    if is_monster:
        return "Monster Set"

    # Check sources text for hints
    pvp_keywords = ["cyrodiil", "battleground", "imperial city", "rewards of the worthy", "pvp"]
    for kw in pvp_keywords:
        if kw in sources or kw in raw_category:
            return "PvP"

    trial_keywords = ["trial", "sunspire", "rockgrove", "cloudrest", "kyne", "dreadsail",
                       "sanity's edge", "lucent citadel"]
    for kw in trial_keywords:
        if kw in sources or kw in name.lower():
            return "Trial"

    arena_keywords = ["arena", "maelstrom", "dragonstar", "vateshran", "blackrose"]
    for kw in arena_keywords:
        if kw in sources or kw in name.lower():
            return "Arena"

    if "craftable" in raw_type or "crafted" in raw_type or "crafted" in raw_category:
        return "Crafted"

    if "overland" in raw_type or "overland" in raw_category:
        return "Overland"

    if "dungeon" in raw_type or "dungeon" in raw_category:
        return "Dungeon"

    # Default based on item slots
    if "Shield" in item_slots and "Weapons" in item_slots:
        return "Dungeon"  # most body+weapon sets are dungeon/trial

    return "Unknown"
