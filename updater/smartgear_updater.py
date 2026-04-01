#!/usr/bin/env python3
"""
SmartGear Updater — Online meta parser for ESO SmartGear addon.

Fetches set data from ESO APIs and meta build sites,
generates an updated MetaData.lua for the SmartGear addon.

Usage:
    python smartgear_updater.py                     # Full update
    python smartgear_updater.py --cache             # Use cached data
    python smartgear_updater.py --output path.lua   # Custom output path
    python smartgear_updater.py --sources alcast    # Only specific sources
    python smartgear_updater.py --list              # List cached sets
"""
import argparse
import json
import os
import sys

# Add parent to path for imports
sys.path.insert(0, os.path.dirname(__file__))

from sources.eso_sets_api import fetch_all_sets
from sources.alcast_parser import parse_alcast_builds, extract_full_builds
from sources.skinnycheeks_parser import parse_skinnycheeks
from sources.eso_hub_parser import parse_eso_hub_sets
from merger import merge_all
from lua_generator import generate_metadata_lua, generate_build_database

# Default paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.dirname(SCRIPT_DIR)  # SmartGear addon root
DEFAULT_OUTPUT = os.path.join(ADDON_DIR, "MetaData.lua")
OVERRIDES_FILE = os.path.join(SCRIPT_DIR, "overrides.json")


def load_overrides():
    """Load manual overrides from overrides.json"""
    if not os.path.exists(OVERRIDES_FILE):
        print("[updater] No overrides.json found, using defaults")
        return {}
    with open(OVERRIDES_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    # Filter out comments
    return {k: v for k, v in data.items() if not k.startswith("_")}


def main():
    parser = argparse.ArgumentParser(
        description="SmartGear Updater — fetch ESO meta data and generate MetaData.lua"
    )
    parser.add_argument(
        "--output", "-o",
        default=DEFAULT_OUTPUT,
        help=f"Output path for MetaData.lua (default: {DEFAULT_OUTPUT})"
    )
    parser.add_argument(
        "--cache", "-c",
        action="store_true",
        help="Use cached data (don't re-fetch from web)"
    )
    parser.add_argument(
        "--sources", "-s",
        default="all",
        help="Comma-separated sources: all, api, alcast, skinnycheeks, esohub"
    )
    parser.add_argument(
        "--max-builds",
        type=int,
        default=80,
        help="Max build pages to parse across all categories (default: 80)"
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List cached sets and exit"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and merge but don't write output file"
    )

    args = parser.parse_args()
    sources = args.sources.lower().split(",")
    use_all = "all" in sources

    print("=" * 60)
    print("  SmartGear Updater v1.0")
    print("  ESO Meta Set Database Generator")
    print("=" * 60)
    print()

    # Step 1: Fetch all sets from API
    api_sets = []
    if use_all or "api" in sources:
        api_sets = fetch_all_sets(use_cache=args.cache)
        print(f"  API sets loaded: {len(api_sets)}")
    print()

    if args.list:
        print("\n--- Cached API Sets ---")
        for s in sorted(api_sets, key=lambda x: x["name"]):
            print(f"  [{s['category']:15}] {s['name']}")
        print(f"\nTotal: {len(api_sets)} sets")
        return

    # Step 2: Parse meta build sites
    alcast_data = []
    skinny_data = []
    esohub_data = []

    if use_all or "alcast" in sources:
        alcast_data = parse_alcast_builds(
            use_cache=args.cache,
            max_builds=args.max_builds,
        )
    print()

    if use_all or "skinnycheeks" in sources:
        skinny_data = parse_skinnycheeks(use_cache=args.cache)
    print()

    if use_all or "esohub" in sources:
        esohub_data = parse_eso_hub_sets(use_cache=args.cache)
    print()

    # Step 3: Load overrides
    overrides = load_overrides()
    print(f"  Overrides loaded: {len(overrides)} sets")
    print()

    # Step 4: Merge all data
    final_sets = merge_all(
        api_sets=api_sets,
        alcast_mentions=alcast_data,
        skinny_mentions=skinny_data,
        eso_hub_data=esohub_data,
        overrides=overrides,
    )
    print()

    if args.dry_run:
        print("--- DRY RUN: Final set list ---")
        for s in final_sets:
            roles = ", ".join(s["roles"])
            print(f"  [{s['tier']}] {s['name']:40} ({roles})")
        print(f"\nTotal: {len(final_sets)} sets")
        return

    # Step 5: Generate Lua
    output_path = os.path.abspath(args.output)
    generate_metadata_lua(final_sets, output_path)

    # Step 6: Extract full builds and generate BuildDatabase.lua
    print()
    full_builds = extract_full_builds(use_cache=args.cache, max_builds=args.max_builds)
    if full_builds:
        builds_output = os.path.join(os.path.dirname(output_path), "BuildDatabase.lua")
        generate_build_database(full_builds, builds_output)

    print()
    print("=" * 60)
    print(f"  Done! MetaData.lua generated with {len(final_sets)} sets")
    if full_builds:
        print(f"  BuildDatabase.lua generated with {len(full_builds)} builds")
    print(f"  Output: {output_path}")
    print()
    print("  Next steps:")
    print("  1. In ESO, type /reloadui to reload addons")
    print("  2. Hover over items to see updated SmartGear ratings")
    print("=" * 60)


if __name__ == "__main__":
    main()
