"""
SmartGear Merger — combines data from all sources, assigns tiers and roles
"""
import json
import os
import re
from collections import defaultdict

# Fuzzy matching threshold (Levenshtein-like)
SIMILARITY_THRESHOLD = 0.85


def _normalize_name(name):
    """Normalize a set name for matching."""
    name = name.strip()
    name = name.replace("\u2019", "'").replace("\u2018", "'")  # curly quotes
    name = name.replace("\u201c", '"').replace("\u201d", '"')
    name = re.sub(r"[`\u00b4\u02bc]", "'", name)  # other apostrophe forms
    name = re.sub(r"\s+", " ", name)  # collapse whitespace
    # Remove trailing " Set" (e.g. "Harpooner's Wading Kilt Set" -> "Harpooner's Wading Kilt")
    name = re.sub(r"\s+Set$", "", name, flags=re.I)
    return name


def _name_key(name):
    """Create a lowercase key for fuzzy matching."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


# Words/patterns that indicate a parsed string is NOT a set name
JUNK_PATTERNS = [
    r"^update\s+log", r"^video$", r"^setup\b", r"^trials?\s*&", r"^why\s",
    r"^with\s", r"^the\s+lord\s+mundus", r"mundus\s+stone", r"^how\s+to",
    r"\bbuild\s+for\b", r"\bbuild\s+eso\b", r"\bguide\b", r"\btutorial\b",
    r"^champion\s+point", r"^skill\s+bar", r"^race\b", r"^food\b",
    r"^potion", r"^attribute", r"^passive", r"^rotation", r"^changelog",
    r"^update\s+log", r"^crazy\s+high", r"^extra\s+damage", r"^great\s+",
    r"^very\s+strong", r"^most\s+popular", r"^unique\s+armor",
    r"^keep\s+the", r"^healing\s+and\s+", r"^e\s+domain",
    r"^\w+:$",  # single word with colon (like "Skills:")
    r"^unstable\s+wall", r"^unstable\s+clannfear", r"^twilight\s+matriarch",
    r"^unnerving\s+boneyard", r"^unbreakable$",
    r"\bsetup\b.*\b(?:arcanist|sorcerer|dragonknight|templar|warden|necro|nightblade)\b",
    r"^\w{1,3}$",  # too short (1-3 chars)
]
_junk_re = [re.compile(p, re.IGNORECASE) for p in JUNK_PATTERNS]


def _is_junk_name(name):
    """Check if a parsed name is obviously not a set name."""
    if len(name) < 4 or len(name) > 45:
        return True
    if name.count(" ") > 5:
        return True
    # Starts with number (like "1236 Champion...")
    if re.match(r"^\d", name):
        return True
    # Contains common non-set patterns
    lower = name.lower()
    junk_words = [
        "champion point", "setup", "allocation", "build", "about",
        "author", "alcast", "website", "cookie", "privacy", "contact",
        "search", "menu", "home", "beginner", "advanced", "bar ",
        "backbar", "frontbar", "weapon:", "script", "blog", "news",
        "comment", "video", "log ", "area of effect", "single target",
        ".com", "http", "www.", "copyright", "affiliate",
        "dragonknight", "sorcerer", "templar", "warden", "necromancer",
        "nightblade", "arcanist",  # class names aren't sets
        "healer build", "tank build", "dps build", "bow build",
        "magicka build", "stamina build",
    ]
    for jw in junk_words:
        if jw in lower:
            return True
    # Check junk regexes
    for pat in _junk_re:
        if pat.search(name):
            return True
    # Must contain at least one capital letter (set names are proper nouns)
    if not re.search(r"[A-Z]", name):
        return True
    # Must start with a letter
    if not re.match(r"[A-Za-z]", name):
        return True
    # Filter known skill/ability names that are NOT sets
    known_skills = [
        # Skills / abilities (NOT sets)
        "aggressive warhorn", "anti-cavalry caltrops", "avid boneyard",
        "blighted blastbones", "bound aegis", "camouflaged hunter",
        "combat prayer", "concentrated force", "critical surge",
        "crystal weapon", "dark convergence", "degeneration",
        "elemental blockade", "endless fury", "evolving corruption",
        "heroic slash", "inner light", "merciless resolve",
        "mystic guard", "race against time", "radiating regeneration",
        "restoring focus", "scalding rune", "silver leash",
        "stampede", "stalking blastbones", "structured entropy",
        "unstable wall", "venom skull", "volatile armor",
        "wall of elements", "whirling blades", "power of the light",
        "twilight matriarch", "blood craze", "carve",
        "deadly cloak", "rapid strikes", "steel tornado",
        "pierce armor", "puncture", "inner fire", "balance",
        "channeled focus", "ritual of retribution",
        "caustic arrow", "executioner's blade", "stinging slashes",
        "rapid fire", "snipe", "focused aim", "poison injection",
        "arrow barrage", "endless hail", "draining shot",
        "soul strike", "soul assault", "meteor", "shooting star",
        "flawless dawnbreaker", "incapacitating strike",
        "toxic barrage", "ballista", "pestilent colossus",
        "thunderous volley",  # this is a skill morph, not a set
        "perfect spectral cloak", "perfected spectral cloak",
        "spectral cloak",  # this is a skill
        "puncturing remedy",  # this is a skill morph
        "monster set", "monster",  # generic term, not a real set name
        # Food / mundus / generic terms
        "buff-food", "agility", "bloody smash",
        "crimson desert", "dubious camoran throne",
        "artaeum takeaway broth", "lava foot soup",
        "ghastly eye bowl", "witchmother's potent brew",
        "ring of the wild hunt",  # actually a mythic, handled by overrides
        "gaze of sithis",  # mythic, handled by overrides
        "crushing weapon", "destructive impact", "bahsei",
        "fulminating rune", "echoing vigor", "inspired scholarship",
        "hurricane", "resolving vigor", "greater storm atronach",
        "shifting standard", "elemental blockade",
        "seducer",  # just a 3-letter prefix match for "Seducers" set
    ]
    if lower.rstrip(":") in known_skills:
        return True
    # Ends with colon — likely a label, not a set name
    if name.endswith(":"):
        return True
    # Starts with "Slot N:" or "Ultimate:" — skill bar entry, not a set
    if re.match(r"^(Slot\s+\d|Ultimate|Skill|Bar\s)", name, re.I):
        return True
    # "Motif" items are crafting styles, not gear sets
    if "motif" in lower:
        return True
    # "Random" / "Any" / "Flex" — placeholder, not a set
    if lower in ("random", "any", "flex", "none", "empty", "willpower", "agility") or lower.startswith("random "):
        return True
    # Starts with "Perf." or "Perfected" followed by a skill name
    perfected_skills = [
        "caustic arrow", "executioner's blade", "stinging slashes",
        "thunderous volley", "spectral cloak",
    ]
    stripped = re.sub(r"^(?:Perf\.?|Perfected)\s+", "", name, flags=re.I)
    if stripped.lower().rstrip(":") in known_skills or stripped.lower() in perfected_skills:
        return True
    return False


def _similarity(a, b):
    """Simple similarity ratio between two strings."""
    a, b = a.lower(), b.lower()
    if a == b:
        return 1.0
    if a in b or b in a:
        return 0.9
    # Jaccard on character bigrams
    def bigrams(s):
        return set(s[i:i+2] for i in range(len(s)-1))
    ba, bb = bigrams(a), bigrams(b)
    if not ba or not bb:
        return 0.0
    return len(ba & bb) / len(ba | bb)


def _role_from_bonuses(bonuses_text):
    """Try to guess set roles from bonus descriptions."""
    text = bonuses_text.lower()
    roles = set()

    # DPS indicators
    dps_keywords = [
        "weapon damage", "spell damage", "critical", "penetration",
        "damage dealt", "damage over time", "direct damage",
        "weapon critical", "spell critical", "max magicka",
        "max stamina",
    ]
    tank_keywords = [
        "block", "health recovery", "max health", "resistance",
        "taunt", "armor", "shield", "damage taken",
        "minor protection", "major protection",
    ]
    healer_keywords = [
        "healing done", "healing taken", "magicka recovery",
        "restore.*magicka", "minor courage", "major courage",
        "allies", "group members",
    ]

    for kw in dps_keywords:
        if kw in text:
            roles.add("MagDD")
            roles.add("StamDD")
            break

    for kw in tank_keywords:
        if kw in text:
            roles.add("Tank")
            break

    for kw in healer_keywords:
        if re.search(kw, text):
            roles.add("Healer")
            break

    return list(roles) if roles else ["MagDD", "StamDD"]  # default to DPS


def _extract_stat_contributions(bonuses_lower):
    """Extract stat contributions from set bonus description text.
    Returns dict of {stat: weight} or empty dict."""
    contribs = {}

    # Weapon/Spell Damage
    if any(kw in bonuses_lower for kw in ["weapon and spell damage", "weapon damage", "spell damage"]):
        contribs["weaponDamage"] = 0.10
    # Critical
    if any(kw in bonuses_lower for kw in ["critical chance", "weapon critical", "spell critical"]):
        contribs["critPercent"] = 0.10
    if "critical damage" in bonuses_lower:
        contribs["critDamage"] = 0.08
    # Penetration
    if "penetration" in bonuses_lower:
        contribs["penetration"] = 0.10
    # Max resources
    if "max magicka" in bonuses_lower or "max stamina" in bonuses_lower:
        contribs["maxResource"] = 0.08
    if "max health" in bonuses_lower:
        contribs["maxHealth"] = 0.06
    # Resistance
    if any(kw in bonuses_lower for kw in ["physical resistance", "spell resistance", "armor"]):
        contribs["resistance"] = 0.08
    # Healing
    if "healing done" in bonuses_lower or "healing taken" in bonuses_lower:
        contribs["healingDone"] = 0.08
    # Generic damage (procs, % damage)
    if any(kw in bonuses_lower for kw in ["damage dealt", "direct damage", "damage over time",
                                           "additional damage", "deals.*damage"]):
        contribs["damage"] = 0.10

    return contribs


def merge_all(api_sets, alcast_mentions, skinny_mentions, eso_hub_data, overrides):
    """
    Merge all data sources into a final set database.

    Args:
        api_sets: list of dicts from eso_sets_api
        alcast_mentions: list of {"set_name", "role", "weight"} from alcast
        skinny_mentions: list of {"set_name", "role", "weight"} from skinnycheeks
        eso_hub_data: list of {"set_name", "category"} from eso-hub
        overrides: dict of manual overrides

    Returns:
        list of final set entries ready for Lua generation
    """
    # Build master set registry from API
    master = {}
    api_keys = {}  # name_key -> normalized name

    for s in api_sets:
        key = _name_key(s["name"])
        master[key] = {
            "name": s["name"],
            "category": s.get("category", "Unknown"),
            "source": s.get("source", "Unknown"),
            "is_monster": s.get("is_monster", False),
            "is_mythic": s.get("is_mythic", False),
            "is_pvp": s.get("is_pvp", False),
            "bonuses_text": s.get("bonuses_text", ""),
            "roles": set(),
            "mention_score": 0,
            "notes": "",
        }
        api_keys[key] = s["name"]

    # Also add ESO-Hub data for category enrichment
    for item in eso_hub_data:
        key = _name_key(item["set_name"])
        if key in master:
            # Update category if more specific
            if item.get("category") and master[key]["category"] == "Unknown":
                master[key]["category"] = item["category"]
            if item["category"] == "Monster Set":
                master[key]["is_monster"] = True
            elif item["category"] == "Mythic":
                master[key]["is_mythic"] = True
            elif item["category"] == "PvP":
                master[key]["is_pvp"] = True

    # Process meta mentions (Alcast + Skinnycheeks)
    all_mentions = alcast_mentions + skinny_mentions

    for mention in all_mentions:
        set_name = _normalize_name(mention["set_name"])
        key = _name_key(set_name)

        if not key or len(key) < 3 or _is_junk_name(set_name):
            continue

        # Try exact match first
        if key not in master:
            # Try fuzzy match against existing entries
            best_match = None
            best_sim = 0
            for mk in master:
                sim = _similarity(key, mk)
                if sim > best_sim and sim >= SIMILARITY_THRESHOLD:
                    best_sim = sim
                    best_match = mk
            if best_match:
                key = best_match
            else:
                # Not in API database — create entry from mention
                # (allows working without API)
                master[key] = {
                    "name": set_name,
                    "category": mention.get("category", "Unknown"),
                    "source": "Parsed from builds",
                    "is_monster": False,
                    "is_mythic": False,
                    "is_pvp": False,
                    "bonuses_text": "",
                    "roles": set(),
                    "mention_score": 0,
                    "context_scores": {"solo": 0, "group": 0, "trial": 0, "pvp": 0},
                    "notes": "",
                }

        # Initialize context_scores if missing
        if "context_scores" not in master[key]:
            master[key]["context_scores"] = {"solo": 0, "group": 0, "trial": 0, "pvp": 0}

        master[key]["mention_score"] += mention.get("weight", 1)
        if mention.get("role"):
            master[key]["roles"].add(mention["role"])

        # Track per-context scores
        ctx = mention.get("context", "group")
        if ctx == "trial":
            # Trial mentions count for both trial and group (dungeon)
            master[key]["context_scores"]["trial"] += mention.get("weight", 1)
            master[key]["context_scores"]["group"] += mention.get("weight", 1) * 0.5
        elif ctx == "group":
            # Group mentions count for both dungeon and trial (less for trial)
            master[key]["context_scores"]["group"] += mention.get("weight", 1)
            master[key]["context_scores"]["trial"] += mention.get("weight", 1) * 0.7
        else:
            master[key]["context_scores"][ctx] += mention.get("weight", 1)

    # Assign tiers and internal rating based on mention score
    # With precise table parsing, weights are much more meaningful:
    #   weight 5 = core set (5pc in primary endgame setup)
    #   weight 4 = important set
    #   weight 3 = used set
    #   weight 2 = mentioned/noteworthy
    #   weight 1 = minor mention
    # A set appearing in multiple builds accumulates score.
    # E.g. set with weight 5 in 4 builds = score 20
    max_score = max((d["mention_score"] for d in master.values()), default=1)

    for key, data in master.items():
        score = data["mention_score"]

        # Tier thresholds (calibrated for precise parser weights)
        if score >= 12:
            data["tier"] = "S"
        elif score >= 6:
            data["tier"] = "A"
        elif score >= 2:
            data["tier"] = "B"
        elif score >= 1:
            data["tier"] = "C"
        else:
            data["tier"] = None

        # Internal rating: 0-100, relative to max score in this dataset
        # This allows comparing sets WITHIN the same tier
        if max_score > 0 and data["tier"]:
            data["rating"] = min(100, round((score / max_score) * 100))
        else:
            data["rating"] = 0

        # Generate context-specific tiers from per-context scores
        ctx_scores = data.get("context_scores", {})
        context_tiers = {}
        for ctx in ["solo", "group", "trial", "pvp"]:
            cs = ctx_scores.get(ctx, 0)
            if cs >= 12:
                context_tiers[ctx] = "S"
            elif cs >= 6:
                context_tiers[ctx] = "A"
            elif cs >= 2:
                context_tiers[ctx] = "B"
            elif cs >= 1:
                context_tiers[ctx] = "C"
            # else: no tier for this context (use base tier)

        # Apply heuristics for sets with no context-specific mentions:
        # - PvP sets: boost in pvp, penalize in pve
        if data.get("is_pvp") and "pvp" not in context_tiers:
            context_tiers["pvp"] = data["tier"] or "B"
            # PvP-only sets are bad in PvE
            for pve_ctx in ["solo", "group", "trial"]:
                if pve_ctx not in context_tiers:
                    context_tiers[pve_ctx] = "C"

        # - Pen sets: great solo, worse in trials
        bonuses_lower = data.get("bonuses_text", "").lower()
        has_pen_bonus = "penetration" in bonuses_lower and "physical" in bonuses_lower
        if has_pen_bonus and data["tier"] in ("S", "A"):
            if "solo" not in context_tiers:
                context_tiers["solo"] = "S"
            if "trial" not in context_tiers:
                context_tiers["trial"] = "C"

        # - Self-heal/sustain-on-kill sets: great solo, bad in group
        has_self_heal = any(kw in bonuses_lower for kw in [
            "restore.*health.*killing", "heal.*kill", "when you kill",
            "killing a target", "killing blow",
        ])
        if has_self_heal and data["tier"] in ("S", "A"):
            if "solo" not in context_tiers:
                context_tiers["solo"] = "S"
            if "trial" not in context_tiers:
                context_tiers["trial"] = "C"

        # Only store if any context differs from base tier
        if context_tiers:
            data["context_tiers"] = context_tiers
        # "group" context maps to "dungeon" in the addon
        if "group" in context_tiers:
            data.setdefault("context_tiers", {})["dungeon"] = context_tiers["group"]

        # Extract statContributions from bonuses_text
        stat_contribs = _extract_stat_contributions(bonuses_lower)
        if stat_contribs:
            data["stat_contributions"] = stat_contribs

        # If no roles from mentions, try guessing from bonuses
        if not data["roles"] and data["tier"]:
            data["roles"] = set(_role_from_bonuses(data["bonuses_text"]))

        # Default notes from category
        if not data["notes"]:
            data["notes"] = f"{data['category']} set"

    # Apply overrides
    for set_name, override in overrides.items():
        key = _name_key(set_name)
        if key in master:
            if "tier" in override:
                master[key]["tier"] = override["tier"]
            if "roles" in override:
                master[key]["roles"] = set(override["roles"])
            if "notes" in override:
                master[key]["notes"] = override["notes"]
            if "is_monster" in override:
                master[key]["is_monster"] = override["is_monster"]
            if "is_mythic" in override:
                master[key]["is_mythic"] = override["is_mythic"]
            if "is_pvp" in override:
                master[key]["is_pvp"] = override["is_pvp"]
        else:
            # Override adds a new set not in API
            master[key] = {
                "name": set_name,
                "tier": override.get("tier", "B"),
                "roles": set(override.get("roles", ["MagDD", "StamDD"])),
                "source": override.get("source", "Override"),
                "notes": override.get("notes", ""),
                "is_monster": override.get("is_monster", False),
                "is_mythic": override.get("is_mythic", False),
                "is_pvp": override.get("is_pvp", False),
                "category": override.get("category", "Unknown"),
                "mention_score": 0,
                "bonuses_text": "",
            }

    # Filter: only include sets with a tier (mentioned in meta or overridden)
    final = []
    for key, data in master.items():
        if data.get("tier"):
            entry = {
                "name": data["name"],
                "roles": sorted(list(data["roles"])),
                "tier": data["tier"],
                "rating": data.get("rating", 50),
                "source": data.get("source", "Unknown"),
                "notes": data.get("notes", ""),
                "is_monster": data.get("is_monster", False),
                "is_mythic": data.get("is_mythic", False),
                "is_pvp": data.get("is_pvp", False),
            }
            if data.get("context_tiers"):
                entry["context_tiers"] = data["context_tiers"]
            if data.get("stat_contributions"):
                entry["stat_contributions"] = data["stat_contributions"]
            final.append(entry)

    # Sort: S tier first, then A, B, C; within tier by rating (highest first)
    tier_order = {"S": 0, "A": 1, "B": 2, "C": 3}
    final.sort(key=lambda x: (tier_order.get(x["tier"], 9), -x.get("rating", 0), x["name"]))

    print(f"[merger] Final database: {len(final)} sets "
          f"(S={sum(1 for s in final if s['tier']=='S')}, "
          f"A={sum(1 for s in final if s['tier']=='A')}, "
          f"B={sum(1 for s in final if s['tier']=='B')}, "
          f"C={sum(1 for s in final if s['tier']=='C')})")

    return final
