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

# Build index pages
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

            # Extract set names from eso-hub links (most reliable)
            eso_hub_links = set_cell.find_all("a", href=re.compile(r"eso-hub\.com/en/sets/"))
            if eso_hub_links:
                for i, link in enumerate(eso_hub_links):
                    name = link.get_text(strip=True)
                    if name and len(name) > 2:
                        all_sets.append({
                            "name": name,
                            "slot": slot_name,
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
    """Parse Alcast builds with precise table extraction.
    Returns: list of {"set_name", "role", "source", "weight"}
    """
    print("[alcast] Parsing builds (v2 precise mode)...")
    all_results = []

    # Fetch build index
    index_html = _get_cached_or_fetch(BUILD_INDEX_URL, "index", use_cache=use_cache)
    if not index_html:
        print("[alcast] Could not fetch build index")
        return all_results

    build_links = _get_build_links(index_html)
    print(f"[alcast] Found {len(build_links)} build links")

    parsed = 0
    total_sets = 0
    for url, title in build_links[:max_builds]:
        role = _detect_role(url, title)

        cache_name = re.sub(r"[^a-z0-9]", "_", url.split("/")[-2] if "/" in url else title)[:50]
        html = _get_cached_or_fetch(url, cache_name, use_cache=use_cache)
        if not html:
            continue

        # Extract from gear tables (precise)
        raw_sets = _extract_sets_from_gear_tables(html)
        noteworthy = _extract_noteworthy_sets(html)

        # Compute weighted scores
        results = _compute_set_scores(raw_sets, noteworthy, role)
        all_results.extend(results)
        total_sets += len(results)

        parsed += 1
        if parsed % 5 == 0:
            print(f"  [alcast] Parsed {parsed}/{min(len(build_links), max_builds)} builds "
                  f"({total_sets} set entries so far)")

    # Summary
    unique_sets = len(set(r["set_name"] for r in all_results))
    print(f"[alcast] Done: {parsed} builds, {total_sets} entries, {unique_sets} unique sets")

    return all_results
