"""
SmartGear Lua Generator — produces MetaData.lua from merged set data
"""
import datetime


def _escape_lua_string(s):
    """Escape a string for Lua."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _format_roles(roles):
    """Format roles list as Lua table."""
    parts = [f'"{r}"' for r in roles]
    return "{ " + ", ".join(parts) + " }"


def _emit_stat_targets(lines):
    """Emit StatTargets tables (context-aware, per role)."""
    # These are based on research from Alcast, Skinnycheeks, Hack The Minotaur, etc.
    targets = {
        "MagDD": {
            "solo":    {"weaponDamage": 4500, "critPercent": 50, "penetration": 14000, "maxResource": 30000, "maxHealth": 22000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "dungeon": {"weaponDamage": 5000, "critPercent": 60, "penetration": 7200,  "maxResource": 32000, "maxHealth": 18000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "trial":   {"weaponDamage": 4000, "critPercent": 60, "penetration": 1200,  "maxResource": 32000, "maxHealth": 17000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "pvp":     {"weaponDamage": 5500, "critPercent": 40, "penetration": 12000, "maxResource": 28000, "maxHealth": 28000, "resistance": 25000, "critResist": 2000, "healingDone": 0},
        },
        "StamDD": {
            "solo":    {"weaponDamage": 4500, "critPercent": 50, "penetration": 14000, "maxResource": 30000, "maxHealth": 22000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "dungeon": {"weaponDamage": 5000, "critPercent": 60, "penetration": 7200,  "maxResource": 32000, "maxHealth": 18000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "trial":   {"weaponDamage": 4000, "critPercent": 60, "penetration": 1200,  "maxResource": 32000, "maxHealth": 17000, "resistance": 0, "critResist": 0, "healingDone": 0},
            "pvp":     {"weaponDamage": 5500, "critPercent": 40, "penetration": 12000, "maxResource": 28000, "maxHealth": 28000, "resistance": 25000, "critResist": 2000, "healingDone": 0},
        },
        "Tank": {
            "solo":    {"weaponDamage": 2500, "critPercent": 15, "penetration": 9100,  "maxResource": 25000, "maxHealth": 35000, "resistance": 30000, "critResist": 0, "healingDone": 0},
            "dungeon": {"weaponDamage": 2000, "critPercent": 10, "penetration": 0,     "maxResource": 28000, "maxHealth": 35000, "resistance": 28000, "critResist": 0, "healingDone": 0},
            "trial":   {"weaponDamage": 2000, "critPercent": 10, "penetration": 0,     "maxResource": 30000, "maxHealth": 42000, "resistance": 33000, "critResist": 0, "healingDone": 0},
            "pvp":     {"weaponDamage": 3000, "critPercent": 15, "penetration": 8000,  "maxResource": 28000, "maxHealth": 35000, "resistance": 33000, "critResist": 3000, "healingDone": 0},
        },
        "Healer": {
            "solo":    {"weaponDamage": 4000, "critPercent": 45, "penetration": 9100,  "maxResource": 32000, "maxHealth": 22000, "resistance": 0, "critResist": 0, "healingDone": 10},
            "dungeon": {"weaponDamage": 3000, "critPercent": 50, "penetration": 0,     "maxResource": 35000, "maxHealth": 20000, "resistance": 0, "critResist": 0, "healingDone": 12},
            "trial":   {"weaponDamage": 3500, "critPercent": 55, "penetration": 0,     "maxResource": 38000, "maxHealth": 21000, "resistance": 0, "critResist": 0, "healingDone": 15},
            "pvp":     {"weaponDamage": 3500, "critPercent": 35, "penetration": 6000,  "maxResource": 30000, "maxHealth": 28000, "resistance": 25000, "critResist": 2000, "healingDone": 8},
        },
    }
    for role, contexts in targets.items():
        lines.append(f"SmartGear.StatTargets.{role} = {{")
        for ctx, stats in contexts.items():
            parts = [f"{k} = {v}" for k, v in stats.items()]
            lines.append(f'    {ctx} = {{ {", ".join(parts)} }},')
        lines.append("}")
        lines.append("")


def _emit_trait_stat_map(lines):
    """Emit TraitStatMap table."""
    lines.append("SmartGear.TraitStatMap = {")
    trait_map = [
        ("ITEM_TRAIT_TYPE_ARMOR_DIVINES",       "mundus",       1.0),
        ("ITEM_TRAIT_TYPE_ARMOR_INFUSED",       "enchant",      0.7),
        ("ITEM_TRAIT_TYPE_ARMOR_REINFORCED",    "resistance",   1.0),
        ("ITEM_TRAIT_TYPE_ARMOR_STURDY",        "blockCost",    1.0),
        ("ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE",  "critResist",   1.0),
        ("ITEM_TRAIT_TYPE_ARMOR_WELL_FITTED",   "dodge",        0.5),
        ("ITEM_TRAIT_TYPE_ARMOR_NIRNHONED",     "resistance",   0.8),
        ("ITEM_TRAIT_TYPE_ARMOR_TRAINING",      "none",         0.0),
        ("ITEM_TRAIT_TYPE_WEAPON_PRECISE",      "critPercent",  1.0),
        ("ITEM_TRAIT_TYPE_WEAPON_SHARPENED",    "penetration",  1.0),
        ("ITEM_TRAIT_TYPE_WEAPON_INFUSED",      "enchant",      0.8),
        ("ITEM_TRAIT_TYPE_WEAPON_CHARGED",      "statusEffect", 0.6),
        ("ITEM_TRAIT_TYPE_WEAPON_NIRNHONED",    "weaponDamage", 1.0),
        ("ITEM_TRAIT_TYPE_WEAPON_POWERED",      "healingDone",  1.0),
        ("ITEM_TRAIT_TYPE_WEAPON_DECISIVE",     "ultimateGen",  0.6),
        ("ITEM_TRAIT_TYPE_WEAPON_TRAINING",     "none",         0.0),
        ("ITEM_TRAIT_TYPE_JEWELRY_BLOODTHIRSTY", "executeDmg",  0.8),
        ("ITEM_TRAIT_TYPE_JEWELRY_ARCANE",       "maxResource", 0.8),
        ("ITEM_TRAIT_TYPE_JEWELRY_ROBUST",       "maxResource", 0.8),
        ("ITEM_TRAIT_TYPE_JEWELRY_INFUSED",      "enchant",     0.7),
        ("ITEM_TRAIT_TYPE_JEWELRY_PROTECTIVE",   "resistance",  0.8),
        ("ITEM_TRAIT_TYPE_JEWELRY_HARMONY",      "ultimateGen", 0.5),
        ("ITEM_TRAIT_TYPE_JEWELRY_TRIUNE",       "maxResource", 0.7),
        ("ITEM_TRAIT_TYPE_JEWELRY_SWIFT",        "none",        0.0),
    ]
    for const, stat, weight in trait_map:
        lines.append(f'    [{const}] = {{ stat = "{stat}", weight = {weight} }},')
    lines.append("}")


def generate_metadata_lua(sets, output_path):
    """Generate MetaData.lua from merged set data.

    Args:
        sets: list of set dicts from merger
        output_path: path to write MetaData.lua
    """
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    total = len(sets)

    lines = []
    lines.append("----------------------------------------------------------------------")
    lines.append("-- SmartGear — Meta Set Database")
    lines.append(f"-- AUTO-GENERATED by SmartGear Updater on {now}")
    lines.append(f"-- Total sets: {total}")
    lines.append("-- Do not edit manually — changes will be overwritten!")
    lines.append("-- Use overrides.json for manual adjustments.")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear = SmartGear or {}")
    lines.append("")

    # RoleConfig (static, not generated)
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Role definitions & optimal traits/weights")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear.RoleConfig = {")
    lines.append("    MagDD = {")
    lines.append("        optimalTraits = { [ITEM_TRAIT_TYPE_ARMOR_DIVINES] = true },")
    lines.append("        pvpTraits     = { [ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE] = true },")
    lines.append("        optimalWeights = { [ARMORTYPE_LIGHT] = true },")
    lines.append("        optimalJewelryTrait = { [ITEM_TRAIT_TYPE_JEWELRY_BLOODTHIRSTY] = true },")
    lines.append("        optimalWeaponTraits = {")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_PRECISE] = true,")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_INFUSED] = true,")
    lines.append("        },")
    lines.append('        description = "Magicka Damage Dealer",')
    lines.append("    },")
    lines.append("    StamDD = {")
    lines.append("        optimalTraits = { [ITEM_TRAIT_TYPE_ARMOR_DIVINES] = true },")
    lines.append("        pvpTraits     = { [ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE] = true },")
    lines.append("        optimalWeights = { [ARMORTYPE_MEDIUM] = true },")
    lines.append("        optimalJewelryTrait = { [ITEM_TRAIT_TYPE_JEWELRY_BLOODTHIRSTY] = true },")
    lines.append("        optimalWeaponTraits = {")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_PRECISE] = true,")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_INFUSED] = true,")
    lines.append("        },")
    lines.append('        description = "Stamina Damage Dealer",')
    lines.append("    },")
    lines.append("    Tank = {")
    lines.append("        optimalTraits = { [ITEM_TRAIT_TYPE_ARMOR_STURDY] = true },")
    lines.append("        pvpTraits     = { [ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE] = true },")
    lines.append("        optimalWeights = { [ARMORTYPE_HEAVY] = true },")
    lines.append("        optimalJewelryTrait = {")
    lines.append("            [ITEM_TRAIT_TYPE_JEWELRY_PROTECTIVE] = true,")
    lines.append("            [ITEM_TRAIT_TYPE_JEWELRY_TRIUNE] = true,")
    lines.append("        },")
    lines.append("        optimalWeaponTraits = {")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_INFUSED] = true,")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_DECISIVE] = true,")
    lines.append("        },")
    lines.append('        description = "Tank",')
    lines.append("    },")
    lines.append("    Healer = {")
    lines.append("        optimalTraits = { [ITEM_TRAIT_TYPE_ARMOR_DIVINES] = true },")
    lines.append("        pvpTraits     = { [ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE] = true },")
    lines.append("        optimalWeights = { [ARMORTYPE_LIGHT] = true },")
    lines.append("        optimalJewelryTrait = { [ITEM_TRAIT_TYPE_JEWELRY_ARCANE] = true },")
    lines.append("        optimalWeaponTraits = {")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_POWERED] = true,")
    lines.append("            [ITEM_TRAIT_TYPE_WEAPON_INFUSED] = true,")
    lines.append("        },")
    lines.append('        description = "Healer",')
    lines.append("    },")
    lines.append("}")
    lines.append("")

    # TraitNames (static)
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Trait display names")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear.TraitNames = {")
    trait_map = [
        ("ITEM_TRAIT_TYPE_ARMOR_DIVINES", "Divines"),
        ("ITEM_TRAIT_TYPE_ARMOR_IMPENETRABLE", "Impenetrable"),
        ("ITEM_TRAIT_TYPE_ARMOR_INFUSED", "Infused"),
        ("ITEM_TRAIT_TYPE_ARMOR_REINFORCED", "Reinforced"),
        ("ITEM_TRAIT_TYPE_ARMOR_STURDY", "Sturdy"),
        ("ITEM_TRAIT_TYPE_ARMOR_TRAINING", "Training"),
        ("ITEM_TRAIT_TYPE_ARMOR_WELL_FITTED", "Well-Fitted"),
        ("ITEM_TRAIT_TYPE_ARMOR_NIRNHONED", "Nirnhoned"),
        ("ITEM_TRAIT_TYPE_WEAPON_PRECISE", "Precise"),
        ("ITEM_TRAIT_TYPE_WEAPON_INFUSED", "Infused"),
        ("ITEM_TRAIT_TYPE_WEAPON_SHARPENED", "Sharpened"),
        ("ITEM_TRAIT_TYPE_WEAPON_CHARGED", "Charged"),
        ("ITEM_TRAIT_TYPE_WEAPON_POWERED", "Powered"),
        ("ITEM_TRAIT_TYPE_WEAPON_DECISIVE", "Decisive"),
        ("ITEM_TRAIT_TYPE_WEAPON_NIRNHONED", "Nirnhoned"),
        ("ITEM_TRAIT_TYPE_WEAPON_TRAINING", "Training"),
        ("ITEM_TRAIT_TYPE_JEWELRY_ARCANE", "Arcane"),
        ("ITEM_TRAIT_TYPE_JEWELRY_BLOODTHIRSTY", "Bloodthirsty"),
        ("ITEM_TRAIT_TYPE_JEWELRY_HARMONY", "Harmony"),
        ("ITEM_TRAIT_TYPE_JEWELRY_INFUSED", "Infused"),
        ("ITEM_TRAIT_TYPE_JEWELRY_PROTECTIVE", "Protective"),
        ("ITEM_TRAIT_TYPE_JEWELRY_ROBUST", "Robust"),
        ("ITEM_TRAIT_TYPE_JEWELRY_SWIFT", "Swift"),
        ("ITEM_TRAIT_TYPE_JEWELRY_TRIUNE", "Triune"),
    ]
    for const, name in trait_map:
        lines.append(f'    [{const}] = "{name}",')
    lines.append("}")
    lines.append("")

    # StatTargets (context-aware)
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Stat targets per role PER CONTEXT (for adaptive gap analysis)")
    lines.append("-- Auto-generated. Edit via overrides or re-run updater.")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear.StatTargets = {}")
    lines.append("")
    _emit_stat_targets(lines)
    lines.append("")

    # TraitStatMap
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Trait -> stat mapping (for adaptive trait scoring)")
    lines.append("----------------------------------------------------------------------")
    _emit_trait_stat_map(lines)
    lines.append("")

    # MetaSets (generated!)
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Meta Sets Database (auto-generated)")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear.MetaSets = {")
    lines.append("")

    # Group by category for readability
    categories_order = [
        "Trial", "Dungeon", "Arena", "Crafted", "Overland",
        "Monster Set", "Mythic", "PvP", "Unknown",
    ]

    sets_by_cat = {}
    for s in sets:
        cat = s.get("source", "Unknown")
        # Use a more meaningful grouping
        if s["is_mythic"]:
            cat = "Mythic"
        elif s["is_monster"]:
            cat = "Monster Set"
        elif s["is_pvp"]:
            cat = "PvP"
        sets_by_cat.setdefault(cat, []).append(s)

    for cat in categories_order:
        cat_sets = sets_by_cat.pop(cat, [])
        if not cat_sets:
            continue

        lines.append(f"    -- {cat.upper()} SETS")
        for s in cat_sets:
            name = _escape_lua_string(s["name"])
            roles = _format_roles(s["roles"])
            tier = s["tier"]
            source = _escape_lua_string(s.get("source", "Unknown"))
            notes = _escape_lua_string(s.get("notes", ""))

            lines.append(f'    ["{name}"] = {{')
            lines.append(f'        roles = {roles},')
            lines.append(f'        tier = "{tier}",')
            lines.append(f'        rating = {s.get("rating", 50)},')
            lines.append(f'        source = "{source}",')
            lines.append(f'        notes = "{notes}",')
            if s.get("is_monster"):
                lines.append(f'        isMonsterSet = true,')
            if s.get("is_mythic"):
                lines.append(f'        isMythic = true,')
            if s.get("is_pvp"):
                lines.append(f'        pvpOnly = true,')
            if s.get("context_tiers"):
                ct = s["context_tiers"]
                parts = []
                for ctx in ["solo", "dungeon", "trial", "pvp"]:
                    if ctx in ct:
                        parts.append(f'{ctx} = "{ct[ctx]}"')
                if parts:
                    lines.append(f'        contextTiers = {{ {", ".join(parts)} }},')
            if s.get("stat_contributions"):
                sc = s["stat_contributions"]
                parts = [f'{k} = {v}' for k, v in sorted(sc.items())]
                if parts:
                    lines.append(f'        statContributions = {{ {", ".join(parts)} }},')
            lines.append(f'    }},')

        lines.append("")

    # Remaining categories
    for cat, cat_sets in sets_by_cat.items():
        if not cat_sets:
            continue
        lines.append(f"    -- {cat.upper()} SETS")
        for s in cat_sets:
            name = _escape_lua_string(s["name"])
            roles = _format_roles(s["roles"])
            tier = s["tier"]
            source = _escape_lua_string(s.get("source", "Unknown"))
            notes = _escape_lua_string(s.get("notes", ""))

            lines.append(f'    ["{name}"] = {{')
            lines.append(f'        roles = {roles},')
            lines.append(f'        tier = "{tier}",')
            lines.append(f'        rating = {s.get("rating", 50)},')
            lines.append(f'        source = "{source}",')
            lines.append(f'        notes = "{notes}",')
            if s.get("is_monster"):
                lines.append(f'        isMonsterSet = true,')
            if s.get("is_mythic"):
                lines.append(f'        isMythic = true,')
            if s.get("is_pvp"):
                lines.append(f'        pvpOnly = true,')
            if s.get("context_tiers"):
                ct = s["context_tiers"]
                parts = []
                for ctx in ["solo", "dungeon", "trial", "pvp"]:
                    if ctx in ct:
                        parts.append(f'{ctx} = "{ct[ctx]}"')
                if parts:
                    lines.append(f'        contextTiers = {{ {", ".join(parts)} }},')
            if s.get("stat_contributions"):
                sc = s["stat_contributions"]
                parts = [f'{k} = {v}' for k, v in sorted(sc.items())]
                if parts:
                    lines.append(f'        statContributions = {{ {", ".join(parts)} }},')
            lines.append(f'    }},')
        lines.append("")

    lines.append("}")
    lines.append("")

    # StatCaps (static)
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Stat caps reference")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear.StatCaps = {")
    lines.append("    physicalPenetration = 18200,")
    lines.append("    spellPenetration    = 18200,")
    lines.append("    criticalChance      = 125,")
    lines.append("    criticalDamage      = 125,")
    lines.append("    weaponDamage        = 0,")
    lines.append("    spellDamage         = 0,")
    lines.append("}")
    lines.append("")

    # Write
    content = "\n".join(lines)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[lua-gen] Generated MetaData.lua with {total} sets -> {output_path}")
    return output_path


def generate_build_database(builds, output_path):
    """Generate BuildDatabase.lua from extracted build definitions."""
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    total = len(builds)

    lines = []
    lines.append("----------------------------------------------------------------------")
    lines.append("-- SmartGear -- Pre-Built Target Builds Database")
    lines.append(f"-- AUTO-GENERATED by SmartGear Updater on {now}")
    lines.append(f"-- Total builds: {total}")
    lines.append("-- Do not edit manually -- re-run updater to refresh.")
    lines.append("----------------------------------------------------------------------")
    lines.append("SmartGear = SmartGear or {}")
    lines.append("SmartGear.PreBuilds = {}")
    lines.append("")

    for build in builds:
        bid = _escape_lua_string(build["id"])
        name = _escape_lua_string(build["name"])
        role = build.get("role", "MagDD")
        context = build.get("context", "group")
        source = _escape_lua_string(build.get("source", "alcast"))

        lines.append(f'SmartGear.PreBuilds["{bid}"] = {{')
        lines.append(f'    name = "{name}",')
        lines.append(f'    role = "{role}",')
        lines.append(f'    context = "{context}",')
        lines.append(f'    source = "{source}",')
        lines.append(f'    slots = {{')

        slots = build.get("slots", {})
        for slot_const, slot_data in sorted(slots.items()):
            set_name = _escape_lua_string(slot_data["set"])
            parts = [f'set = "{set_name}"']
            if slot_data.get("trait"):
                parts.append(f'trait = {slot_data["trait"]}')
            if slot_data.get("weight"):
                parts.append(f'weight = {slot_data["weight"]}')
            lines.append(f'        [{slot_const}] = {{ {", ".join(parts)} }},')

        lines.append(f'    }},')
        lines.append(f'}}')
        lines.append("")

    content = "\n".join(lines)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[lua-gen] Generated BuildDatabase.lua with {total} builds -> {output_path}")
    return output_path
