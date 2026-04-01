"""
Alcast build parser v2 — precise extraction from gear tables
Only extracts set names from actual gear recommendation tables,
not from random text on the page.
"""
import json
import os
import re
import time
import requests
from bs4 import BeautifulSoup

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "cache")
BASE_URL = "https://alcasthq.com"
REQUEST_DELAY = 1.5

# Build index pages — multiple categories for different contexts
BUILD_INDEX_URLS = {
    "group":  f"{BASE_URL}/category/eso-builds-classes/",
    "solo":   f"{BASE_URL}/category/eso-solo-builds/",
    "pvp":    f"{BASE_URL}/category/eso-pvp-builds/",
    "trial":  f"{BASE_URL}/category/pve-group-builds/",
}
# Legacy single URL (used by parse_alcast_builds for set mentions)
BUILD_INDEX_URL = f"{BASE_URL}/category/eso-builds-classes/"

# Role detection from URL/title
ROLE_PATTERNS = [
    (re.compile(r"tank", re.I), "Tank"),
    (re.compile(r"healer|heal\b", re.I), "Healer"),
    (re.compile(r"magicka|mag[\s-]", re.I), "MagDD"),
    (re.compile(r"stamina|stam[\s-]", re.I), "StamDD"),
    (re.compile(r"pet\s+sorc", re.I), "MagDD"),
    (re.compile(r"2h\s+stam|bow\s+", re.I), "StamDD"),
]

# Class detection from URL/title
CLASS_PATTERNS = [
    (re.compile(r"dragonknight|dragon.knight|\bdk\b", re.I), "Dragonknight"),
    (re.compile(r"sorcerer|\bsorc\b", re.I), "Sorcerer"),
    (re.compile(r"nightblade|\bnb\b|stamblade|magblade", re.I), "Nightblade"),
    (re.compile(r"warden", re.I), "Warden"),
    (re.compile(r"necromancer|necro\b", re.I), "Necromancer"),
    (re.compile(r"templar|\btemplar\b|stamplar|magplar", re.I), "Templar"),
    (re.compile(r"arcanist", re.I), "Arcanist"),
]

# ESO class ID mapping (for addon-side filtering)
CLASS_IDS = {
    "Dragonknight": 1, "Sorcerer": 2, "Nightblade": 3,
    "Warden": 4, "Necromancer": 5, "Templar": 6, "Arcanist": 117,
}

# Content context detection from URL/title
CONTEXT_PATTERNS = [
    (re.compile(r"solo|maelstrom|vateshran|overland|one.?bar", re.I), "solo"),
    (re.compile(r"pvp|battleground|cyrodiil|imperial.?city", re.I), "pvp"),
    (re.compile(r"trial|raid|12.?man|sunspire|rockgrove|asylum|cloudrest|hel.?ra|aetherian", re.I), "trial"),
    # Everything else = group (dungeon) by default
]

# Setup priority: lower = better (primary gear > beginner)
SETUP_PRIORITY = {
    "1": 1.0,     # Primary/endgame
    "2": 0.7,     # Advanced alternative
    "3": 0.4,     # Beginner
    "beginner": 0.4,
}


def _get_cached_or_fetch(url, cache_name, use_cache=True):
    cache_path = os.path.join(CACHE_DIR, f"alcast_{cache_name}.html")
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
        print(f"  [alcast] Error fetching {url}: {e}")
        if os.path.exists(cache_path):
            with open(cache_path, "r", encoding="utf-8") as f:
                return f.read()
        return None


def _detect_role(url, title):
    text = f"{url} {title}"
    for pattern, role in ROLE_PATTERNS:
        if pattern.search(text):
            return role
    # Default: DPS (most builds on Alcast are DPS)
    return "MagDD"


def _detect_context(url, title):
    """Detect content context from build URL/title."""
    text = f"{url} {title}"
    for pattern, context in CONTEXT_PATTERNS:
        if pattern.search(text):
            return context
    return "group"


def _detect_class(url, title):
    """Detect ESO class from build URL/title."""
    text = f"{url} {title}"
    for pattern, cls in CLASS_PATTERNS:
        if pattern.search(text):
            return cls
    return None  # unknown class


def _get_build_links(html):
    """Extract build page links from index."""
    soup = BeautifulSoup(html, "lxml")
    links = []
    seen = set()

    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "/eso-" in href and "build" in href and href.startswith("http"):
            if href not in seen:
                seen.add(href)
                title = a.get_text(strip=True)
                if title:
                    links.append((href, title))

    return links


def _determine_setup_weight(heading_text):
    """Determine weight multiplier for a gear setup based on heading."""
    lower = heading_text.lower()
    for key, weight in SETUP_PRIORITY.items():
        if key in lower:
            return weight
    return 0.8  # default for unnamed setups


def _extract_sets_from_gear_tables(html):
    """
    Precise extraction: only from <table> inside <div class="table-2">
    within gear sections. Returns list of:
    {name, slot, weight_type, trait, setup_priority, is_alternative, slot_count}
    """
    soup = BeautifulSoup(html, "lxml")
    all_sets = []

    # Find all gear tables (div.table-2 > table)
    gear_tables = soup.select("div.table-2 table")

    if not gear_tables:
        # Fallback: try tables near "Gear" headings
        gear_tables = []
        for h in soup.find_all(["h3", "h4"]):
            if "gear" in h.get_text(strip=True).lower():
                # Find next table after this heading
                sibling = h.find_next("table")
                if sibling:
                    gear_tables.append(sibling)

    # Determine setup priority for each table
    for table in gear_tables:
        # Find the nearest heading before this table
        setup_weight = 0.8
        prev_heading = table.find_previous(["h3", "h4"])
        if prev_heading:
            setup_weight = _determine_setup_weight(prev_heading.get_text(strip=True))

        rows = table.select("tbody tr")
        if not rows:
            rows = table.select("tr")[1:]  # skip header

        for row in rows:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue

            slot_name = cells[0].get_text(strip=True)
            set_cell = cells[1]

            # Extract trait and weight from remaining cells
            # Column order varies between pages! Detect by content.
            raw_col2 = cells[2].get_text(strip=True) if len(cells) > 2 else ""
            raw_col3 = cells[3].get_text(strip=True) if len(cells) > 3 else ""
            raw_col4 = cells[4].get_text(strip=True) if len(cells) > 4 else ""

            # Detect which column is trait vs weight by keywords
            weight_keywords = {"light", "medium", "heavy"}
            trait_text = ""
            weight_text = ""
            for col in [raw_col2, raw_col3, raw_col4]:
                col_lower = col.lower().strip()
                if col_lower in weight_keywords:
                    weight_text = col
                elif col_lower and col_lower not in {"", "jewelry", "weapon", "shield"}:
                    if not trait_text:
                        trait_text = col

            # Extract set names from eso-hub links (most reliable)
            eso_hub_links = set_cell.find_all("a", href=re.compile(r"eso-hub\.com/en/sets/"))
            if eso_hub_links:
                for i, link in enumerate(eso_hub_links):
                    name = link.get_text(strip=True)
                    if name and len(name) > 2:
                        all_sets.append({
                            "name": name,
                            "slot": slot_name,
                            "trait": trait_text,
                            "weight": weight_text,
                            "setup_priority": setup_weight,
                            "is_alternative": i > 0,  # first = primary, rest = alternatives
                        })
            else:
                # No eso-hub links — try plain text in cell
                name = set_cell.get_text(strip=True)
                # Clean up "or" alternatives
                names = re.split(r"\s+or\s+", name, flags=re.I)
                for i, n in enumerate(names):
                    n = n.strip().strip("()")
                    if n and len(n) > 2 and not n.lower().startswith("any"):
                        all_sets.append({
                            "name": n,
                            "slot": slot_name,
                            "trait": trait_text,
                            "weight": weight_text,
                            "setup_priority": setup_weight,
                            "is_alternative": i > 0,
                        })

    return all_sets


def _extract_noteworthy_sets(html):
    """Extract from 'Other noteworthy Sets' accordion (lower priority)."""
    soup = BeautifulSoup(html, "lxml")
    sets = []

    # Look for accordion sections about noteworthy sets
    for toggle in soup.find_all("span", class_="fusion-toggle-heading"):
        if "noteworthy" in toggle.get_text(strip=True).lower():
            panel = toggle.find_parent("div", class_=re.compile(r"fusion-panel"))
            if not panel:
                panel = toggle.find_next("div")
            if panel:
                for link in panel.find_all("a", href=re.compile(r"eso-hub\.com/en/sets/")):
                    name = link.get_text(strip=True)
                    if name and len(name) > 2:
                        sets.append(name)

    return sets


def _compute_set_scores(raw_sets, noteworthy_sets, role):
    """
    Compute a weighted score for each set based on:
    - How many slots it occupies (5pc body > 2pc monster > 1pc)
    - Setup priority (endgame > beginner)
    - Primary vs alternative
    """
    set_data = {}  # name -> {total_weight, slot_count, ...}

    for entry in raw_sets:
        name = entry["name"]
        if name not in set_data:
            set_data[name] = {
                "total_weight": 0,
                "slot_count": 0,
                "max_setup_priority": 0,
                "is_ever_primary": False,
            }

        # Weight per slot appearance
        slot_weight = entry["setup_priority"]
        if entry["is_alternative"]:
            slot_weight *= 0.5

        set_data[name]["total_weight"] += slot_weight
        set_data[name]["slot_count"] += 1
        set_data[name]["max_setup_priority"] = max(
            set_data[name]["max_setup_priority"],
            entry["setup_priority"]
        )
        if not entry["is_alternative"]:
            set_data[name]["is_ever_primary"] = True

    # Add noteworthy sets with low weight
    for name in noteworthy_sets:
        if name not in set_data:
            set_data[name] = {
                "total_weight": 0.3,
                "slot_count": 0,
                "max_setup_priority": 0.3,
                "is_ever_primary": False,
            }

    # Convert to output format
    results = []
    for name, data in set_data.items():
        # Final weight: combines slot count importance + setup priority
        weight = data["total_weight"]

        # Bonus for being primary (not alternative)
        if data["is_ever_primary"]:
            weight *= 1.2

        # Map weight to integer score (1-5)
        if weight >= 3.0:
            score = 5  # Core set (5pc in primary setup)
        elif weight >= 1.5:
            score = 4  # Important set (multiple slots or high priority)
        elif weight >= 0.8:
            score = 3  # Used set (single setup or alternative)
        elif weight >= 0.3:
            score = 2  # Mentioned (noteworthy or beginner only)
        else:
            score = 1

        results.append({
            "set_name": name,
            "role": role,
            "source": "alcast",
            "weight": score,
            "raw_weight": round(weight, 2),
            "slot_count": data["slot_count"],
        })

    return results


def parse_alcast_builds(use_cache=True, max_builds=30):
    """Parse Alcast builds from ALL categories with precise table extraction.
    Returns: list of {"set_name", "role", "source", "weight", "context"}
    """
    print("[alcast] Parsing builds (v2 precise mode, all categories)...")
    all_results = []
    seen_urls = set()

    # Parse all category index pages
    all_build_links = []
    for category_ctx, index_url in BUILD_INDEX_URLS.items():
        cache_key = f"index_{category_ctx}"
        index_html = _get_cached_or_fetch(index_url, cache_key, use_cache=use_cache)
        if not index_html:
            continue
        links = _get_build_links(index_html)
        for url, title in links:
            if url not in seen_urls:
                seen_urls.add(url)
                all_build_links.append((url, title, category_ctx))

    print(f"[alcast] Found {len(all_build_links)} unique build links across all categories")

    parsed = 0
    total_sets = 0
    for url, title, category_ctx in all_build_links[:max_builds]:
        role = _detect_role(url, title)
        context = _detect_context(url, title)
        if context == "group" and category_ctx != "group":
            context = category_ctx

        cache_name = re.sub(r"[^a-z0-9]", "_", url.split("/")[-2] if "/" in url else title)[:50]
        html = _get_cached_or_fetch(url, cache_name, use_cache=use_cache)
        if not html:
            continue

        # Extract from gear tables (precise)
        raw_sets = _extract_sets_from_gear_tables(html)
        noteworthy = _extract_noteworthy_sets(html)

        # Compute weighted scores
        results = _compute_set_scores(raw_sets, noteworthy, role)
        # Tag each result with content context
        for r in results:
            r["context"] = context
        all_results.extend(results)
        total_sets += len(results)

        parsed += 1
        if parsed % 5 == 0:
            print(f"  [alcast] Parsed {parsed}/{min(len(all_build_links), max_builds)} builds "
                  f"({total_sets} set entries so far)")

    # Summary
    unique_sets = len(set(r["set_name"] for r in all_results))
    print(f"[alcast] Done: {parsed} builds, {total_sets} entries, {unique_sets} unique sets")

    return all_results


# ====================================================================
# FULL BUILD EXTRACTION (for Target Build system)
# ====================================================================

SLOT_MAP = {
    "head": "EQUIP_SLOT_HEAD", "helm": "EQUIP_SLOT_HEAD",
    "shoulder": "EQUIP_SLOT_SHOULDERS", "shoulders": "EQUIP_SLOT_SHOULDERS",
    "chest": "EQUIP_SLOT_CHEST", "body": "EQUIP_SLOT_CHEST",
    "waist": "EQUIP_SLOT_WAIST", "belt": "EQUIP_SLOT_WAIST",
    "legs": "EQUIP_SLOT_LEGS", "leg": "EQUIP_SLOT_LEGS",
    "feet": "EQUIP_SLOT_FEET", "boot": "EQUIP_SLOT_FEET", "boots": "EQUIP_SLOT_FEET",
    "shoes": "EQUIP_SLOT_FEET", "shoe": "EQUIP_SLOT_FEET",
    "pants": "EQUIP_SLOT_LEGS", "pant": "EQUIP_SLOT_LEGS",
    "hands": "EQUIP_SLOT_HAND", "hand": "EQUIP_SLOT_HAND", "gloves": "EQUIP_SLOT_HAND",
    "neck": "EQUIP_SLOT_NECK", "necklace": "EQUIP_SLOT_NECK", "amulet": "EQUIP_SLOT_NECK",
    "ring 1": "EQUIP_SLOT_RING1", "ring1": "EQUIP_SLOT_RING1",
    "ring 2": "EQUIP_SLOT_RING2", "ring2": "EQUIP_SLOT_RING2",
    "ring": "EQUIP_SLOT_RING1",
    "main hand": "EQUIP_SLOT_MAIN_HAND", "mainhand": "EQUIP_SLOT_MAIN_HAND",
    "weapon 1": "EQUIP_SLOT_MAIN_HAND", "front bar": "EQUIP_SLOT_MAIN_HAND",
    "off hand": "EQUIP_SLOT_OFF_HAND", "offhand": "EQUIP_SLOT_OFF_HAND",
    "shield": "EQUIP_SLOT_OFF_HAND",
    "backup main": "EQUIP_SLOT_BACKUP_MAIN", "backbar": "EQUIP_SLOT_BACKUP_MAIN",
    "weapon 2": "EQUIP_SLOT_BACKUP_MAIN", "back bar": "EQUIP_SLOT_BACKUP_MAIN",
    "backup off": "EQUIP_SLOT_BACKUP_OFF",
}

WEAPON_TRAIT_MAP = {
    "precise": "ITEM_TRAIT_TYPE_WEAPON_PRECISE",
    "infused": "ITEM_TRAIT_TYPE_WEAPON_INFUSED",
    "sharpened": "ITEM_TRAIT_TYPE_WEAPON_SHARPENED",
    "charged": "ITEM_TRAIT_TYPE_WEAPON_CHARGED",
    "powered": "ITEM_TRAIT_TYPE_WEAPON_POWERED",
    "decisive": "ITEM_TRAIT_TYPE_WEAPON_DECISIVE",
    "nirnhoned": "ITEM_TRAIT_TYPE_WEAPON_NIRNHONED",
    "training": "ITEM_TRAIT_TYPE_WEAPON_TRAINING",
}

JEWELRY_TRAIT_MAP = {
    "bloodthirsty": "ITEM_TRAIT_TYPE_JEWELRY_BLOODTHIRSTY",
    "arcane": "ITEM_TRAIT_TYPE_JEWELRY_ARCANE",
    "robust": "ITEM_TRAIT_TYPE_JEWELRY_ROBUST",
    "infused": "ITEM_TRAIT_TYPE_JEWELRY_INFUSED",
    "harmony": "ITEM_TRAIT_TYPE_JEWELRY_HARMONY",
    "protective": "ITEM_TRAIT_TYPE_JEWELRY_PROTECTIVE",
    "swift": "ITEM_TRAIT_TYPE_JEWELRY_SWIFT",
    "triune": "ITEM_TRAIT_TYPE_JEWELRY_TRIUNE",
}

ARMOR_TRAIT_MAP = {
    "divines": "ITEM_TRAIT_TYPE_ARMOR_DIVINES",
    "impenetrable": "ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE",
    "infused": "ITEM_TRAIT_TYPE_ARMOR_INFUSED",
    "reinforced": "ITEM_TRAIT_TYPE_ARMOR_REINFORCED",
    "sturdy": "ITEM_TRAIT_TYPE_ARMOR_STURDY",
    "training": "ITEM_TRAIT_TYPE_ARMOR_TRAINING",
    "well-fitted": "ITEM_TRAIT_TYPE_ARMOR_WELL_FITTED",
    "nirnhoned": "ITEM_TRAIT_TYPE_ARMOR_NIRNHONED",
}

WEIGHT_MAP = {
    "light": "ARMORTYPE_LIGHT", "medium": "ARMORTYPE_MEDIUM", "heavy": "ARMORTYPE_HEAVY",
}

# Weapon type from Alcast table -> ESO WEAPONTYPE constant
WEAPON_TYPE_MAP = {
    "dagger":          "WEAPONTYPE_DAGGER",
    "sword":           "WEAPONTYPE_SWORD",
    "axe":             "WEAPONTYPE_AXE",
    "mace":            "WEAPONTYPE_HAMMER",
    "2h sword":        "WEAPONTYPE_TWO_HANDED_SWORD",
    "2h axe":          "WEAPONTYPE_TWO_HANDED_AXE",
    "2h hammer":       "WEAPONTYPE_TWO_HANDED_HAMMER",
    "2h maul":         "WEAPONTYPE_TWO_HANDED_HAMMER",
    "2h":              "WEAPONTYPE_TWO_HANDED_SWORD",
    "bow":             "WEAPONTYPE_BOW",
    "fire staff":      "WEAPONTYPE_FIRE_STAFF",
    "fire":            "WEAPONTYPE_FIRE_STAFF",
    "inferno staff":   "WEAPONTYPE_FIRE_STAFF",
    "inferno":         "WEAPONTYPE_FIRE_STAFF",
    "lightning staff":  "WEAPONTYPE_LIGHTNING_STAFF",
    "lightning":       "WEAPONTYPE_LIGHTNING_STAFF",
    "shock staff":     "WEAPONTYPE_LIGHTNING_STAFF",
    "shock":           "WEAPONTYPE_LIGHTNING_STAFF",
    "frost staff":     "WEAPONTYPE_ICE_STAFF",
    "frost":           "WEAPONTYPE_ICE_STAFF",
    "ice staff":       "WEAPONTYPE_ICE_STAFF",
    "resto staff":     "WEAPONTYPE_RESTORATION_STAFF",
    "resto":           "WEAPONTYPE_RESTORATION_STAFF",
    "restoration staff": "WEAPONTYPE_RESTORATION_STAFF",
    "healing staff":   "WEAPONTYPE_RESTORATION_STAFF",
    "shield":          "WEAPONTYPE_SHIELD",
    "1h weap":         None,  # generic 1H, no specific type
    "1h-weap":         None,
}


def _map_weapon_type(text):
    """Map weapon type text to ESO constant."""
    lower = text.lower().strip()
    if lower in WEAPON_TYPE_MAP:
        return WEAPON_TYPE_MAP[lower]
    # Partial match
    for key, val in WEAPON_TYPE_MAP.items():
        if key in lower:
            return val
    return None

WEAPON_SLOTS = {"EQUIP_SLOT_MAIN_HAND", "EQUIP_SLOT_OFF_HAND", "EQUIP_SLOT_BACKUP_MAIN", "EQUIP_SLOT_BACKUP_OFF"}
JEWELRY_SLOTS = {"EQUIP_SLOT_NECK", "EQUIP_SLOT_RING1", "EQUIP_SLOT_RING2"}


def _map_slot(slot_text):
    lower = slot_text.lower().strip()
    if lower in SLOT_MAP:
        return SLOT_MAP[lower]
    for key, val in SLOT_MAP.items():
        if key in lower:
            return val
    return None


def _map_trait(trait_text, slot_const):
    lower = trait_text.lower().strip()
    if not lower:
        return None
    if slot_const in WEAPON_SLOTS:
        return WEAPON_TRAIT_MAP.get(lower)
    elif slot_const in JEWELRY_SLOTS:
        return JEWELRY_TRAIT_MAP.get(lower)
    return ARMOR_TRAIT_MAP.get(lower)


def _map_weight(weight_text):
    lower = weight_text.lower().strip()
    for key, val in WEIGHT_MAP.items():
        if key in lower:
            return val
    return None


def _make_build_id(role, context, title):
    clean = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")[:40]
    return f"{role.lower()}_{context}_{clean}"


def _detect_table_context(heading_text):
    """Detect context from a gear table heading. Returns (context, label, skip)."""
    lower = heading_text.lower()

    # Skip non-gear tables
    if "skill" in lower and "gear" not in lower:
        return None, None, True
    if "outfit" in lower or "showcase" in lower or "style" in lower:
        return None, None, True

    # Detect specific contexts
    if any(kw in lower for kw in ["vateshran", "maelstrom"]):
        return "solo", "Arena", False
    if "infinite archive" in lower:
        return "solo", "Infinite Archive", False
    if any(kw in lower for kw in ["solo"]):
        return "solo", "Solo", False
    if any(kw in lower for kw in ["pvp", "battleground", "cyrodiil"]):
        return "pvp", "PvP", False
    if any(kw in lower for kw in ["trial", "raid"]):
        return "trial", "Trial", False
    if "beginner" in lower:
        return "group", "Beginner", False  # keep beginner builds too
    if "setup 1" in lower:
        return None, "Endgame", False  # context from page
    if "setup 2" in lower:
        return None, "Alternative", False
    if "setup 3" in lower:
        return None, "Advanced", False

    return None, None, False  # context from page, no special label


def _extract_builds_from_page(html, url, title, role):
    """Extract MULTIPLE builds from a single page — one build per gear table."""
    soup = BeautifulSoup(html, "lxml")
    gear_tables = soup.select("div.table-2 table")
    if not gear_tables:
        return []

    page_context = _detect_context(url, title)
    builds = []
    build_num = 0

    for table in gear_tables:
        prev_heading = table.find_previous(["h2", "h3", "h4"])
        heading_text = prev_heading.get_text(strip=True) if prev_heading else ""

        table_ctx, table_label, skip = _detect_table_context(heading_text)
        if skip:
            continue

        # Resolve context: table-specific > page-level > "group"
        if not table_ctx:
            table_ctx = page_context

        rows = table.select("tbody tr")
        if not rows:
            rows = table.select("tr")[1:]

        slot_entries = []
        for row in rows:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue

            slot_name = cells[0].get_text(strip=True)
            set_cell = cells[1]

            # Detect trait/weight from remaining columns
            raw_col2 = cells[2].get_text(strip=True) if len(cells) > 2 else ""
            raw_col3 = cells[3].get_text(strip=True) if len(cells) > 3 else ""
            raw_col4 = cells[4].get_text(strip=True) if len(cells) > 4 else ""

            weight_keywords = {"light", "medium", "heavy"}
            weapon_type_text = ""
            trait_text = ""
            weight_text = ""
            for col in [raw_col2, raw_col3, raw_col4]:
                col_lower = col.lower().strip()
                if col_lower in weight_keywords:
                    weight_text = col
                elif _map_weapon_type(col_lower):
                    weapon_type_text = col
                elif col_lower and col_lower not in {"", "jewelry", "weapon"}:
                    if not trait_text:
                        trait_text = col

            # Extract set name
            eso_hub_links = set_cell.find_all("a", href=re.compile(r"eso-hub\.com/en/sets/"))
            if eso_hub_links:
                name = eso_hub_links[0].get_text(strip=True)
            else:
                name = set_cell.get_text(strip=True).split(" or ")[0].strip().strip("()")

            if not name or len(name) < 3:
                continue

            slot_entries.append({
                "name": name, "slot": slot_name,
                "trait": trait_text, "weight": weight_text,
                "weaponType": weapon_type_text,
            })

        # Build slot mapping
        slots = {}
        for entry in slot_entries:
            slot_const = _map_slot(entry.get("slot", ""))
            if not slot_const:
                continue
            if slot_const == "EQUIP_SLOT_RING1" and slot_const in slots:
                slot_const = "EQUIP_SLOT_RING2"
            if slot_const in slots:
                continue

            trait_const = _map_trait(entry.get("trait", ""), slot_const)
            weight_const = _map_weight(entry.get("weight", ""))
            weapon_const = _map_weapon_type(entry.get("weaponType", ""))

            slot_data = {"set": entry["name"]}
            if trait_const:
                slot_data["trait"] = trait_const
            if weight_const:
                slot_data["weight"] = weight_const
            if weapon_const:
                slot_data["weaponType"] = weapon_const
            slots[slot_const] = slot_data

        if len(slots) < 4:
            continue

        # Auto-fill missing off-hand slots for DW builds
        # Alcast often shows only "Weapon 1" without separate off-hand
        if "EQUIP_SLOT_MAIN_HAND" in slots and "EQUIP_SLOT_OFF_HAND" not in slots:
            mh = slots["EQUIP_SLOT_MAIN_HAND"]
            slots["EQUIP_SLOT_OFF_HAND"] = {"set": mh["set"]}
            if mh.get("trait"):
                # Off-hand typically gets a different trait (Precise if main is Nirnhoned)
                if mh["trait"] == "ITEM_TRAIT_TYPE_WEAPON_NIRNHONED":
                    slots["EQUIP_SLOT_OFF_HAND"]["trait"] = "ITEM_TRAIT_TYPE_WEAPON_PRECISE"
                else:
                    slots["EQUIP_SLOT_OFF_HAND"]["trait"] = mh.get("trait")

        build_num += 1

        # Build name: append label from table heading
        build_name = title
        if table_label:
            build_name = title + " [" + table_label + "]"
        elif build_num > 1:
            build_name = title + " [Setup " + str(build_num) + "]"

        builds.append({
            "id": _make_build_id(role, table_ctx, build_name),
            "name": build_name,
            "role": role,
            "context": table_ctx,
            "source": "alcast",
            "sourceUrl": url,
            "className": _detect_class(url, title),
            "classId": CLASS_IDS.get(_detect_class(url, title)),
            "slots": slots,
        })

    return builds


def extract_full_builds(use_cache=True, max_builds=80):
    """Extract complete build definitions from Alcast — multiple setups per page."""
    print("[alcast] Extracting full build definitions (multi-setup per page)...")
    builds = []
    seen_urls = set()

    # Use group index as primary (all builds are there)
    index_url = BUILD_INDEX_URLS["group"]
    index_html = _get_cached_or_fetch(index_url, "index_group", use_cache=use_cache)
    if not index_html:
        return builds

    build_links = _get_build_links(index_html)
    print(f"  Found {len(build_links)} build links")

    for url, title in build_links[:max_builds]:
        if url in seen_urls:
            continue
        seen_urls.add(url)

        role = _detect_role(url, title)
        cache_name = re.sub(r"[^a-z0-9]", "_", url.split("/")[-2] if "/" in url else title)[:50]
        html = _get_cached_or_fetch(url, cache_name, use_cache=use_cache)
        if not html:
            continue

        page_builds = _extract_builds_from_page(html, url, title, role)
        builds.extend(page_builds)

    # Count by context
    ctx_counts = {}
    for b in builds:
        ctx_counts[b["context"]] = ctx_counts.get(b["context"], 0) + 1

    print(f"[alcast] Extracted {len(builds)} builds: " +
          ", ".join(f"{ctx}={cnt}" for ctx, cnt in sorted(ctx_counts.items())))
    return builds
