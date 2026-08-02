#!/usr/bin/env python3
"""Assemble assets/gamedata.json from legacy combat JSON + in-repo constants.

Safe to re-run after the first migration if legacy files still exist; prefers
existing gamedata.json slices when legacy paths are gone.

  python tools/build_gamedata.py
"""

from __future__ import annotations

import ast
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import gamedata_io as gd  # noqa: E402

LEGACY_ATTACKS = ROOT / "assets" / "combat" / "attacks.json"
LEGACY_BEHAVIOURS = ROOT / "assets" / "combat" / "behaviours.json"
LEGACY_TABLE = ROOT / "assets" / "monsters" / "combat_table.json"
SPOTS_GD = ROOT / "scripts" / "city" / "mandelbrot_spots.gd"
GODOT = ROOT / "tools" / "godot" / "Godot_v4.6-voxel_win64.exe"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_mandelbrot_spots() -> dict:
    text = SPOTS_GD.read_text(encoding="utf-8")
    m = re.search(r"const SPOTS: Array\[Dictionary\] = (\[[\s\S]*?\n\])", text)
    if not m:
        raise RuntimeError("could not find SPOTS array in mandelbrot_spots.gd")
    # Make Python-literal friendly: true/false not needed; keys are already quoted.
    literal = m.group(1)
    spots = ast.literal_eval(literal)
    return {
        "scale_max": 1.0e-4,
        "scale_min": 1.0e-8,
        "default_view": {"cx": -0.5, "cy": 0.0, "half": 1.5},
        "spots": spots,
    }


def _dump_build_recipes() -> dict:
    if not GODOT.is_file():
        raise FileNotFoundError(f"Godot binary missing: {GODOT}")
    proc = subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "-s",
            "res://tools/dump_build_recipes.gd",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    out = proc.stdout or ""
    if "BUILD_RECIPES_JSON_BEGIN" not in out:
        sys.stderr.write(proc.stderr or "")
        raise RuntimeError(
            f"dump_build_recipes failed (exit {proc.returncode}); no JSON marker"
        )
    chunk = out.split("BUILD_RECIPES_JSON_BEGIN", 1)[1]
    chunk = chunk.split("BUILD_RECIPES_JSON_END", 1)[0].strip()
    data = json.loads(chunk)
    if not isinstance(data, dict) or not data:
        raise RuntimeError("dump_build_recipes returned empty object")
    return data


def _items() -> dict:
    return {
        "gem_quartz": {
            "display_name": "Quartz",
            "stack_max": 99,
            "gem_mat_id": 49,
            "flags": ["gem"],
        },
        "gem_amber": {
            "display_name": "Amber",
            "stack_max": 99,
            "gem_mat_id": 50,
            "flags": ["gem"],
        },
        "gem_topaz": {
            "display_name": "Topaz",
            "stack_max": 99,
            "gem_mat_id": 51,
            "flags": ["gem"],
        },
        "gem_sapphire": {
            "display_name": "Sapphire",
            "stack_max": 99,
            "gem_mat_id": 52,
            "flags": ["gem"],
        },
        "gem_emerald": {
            "display_name": "Emerald",
            "stack_max": 99,
            "gem_mat_id": 53,
            "flags": ["gem"],
        },
        "gem_diamond": {
            "display_name": "Diamond",
            "stack_max": 99,
            "gem_mat_id": 54,
            "flags": ["gem"],
        },
        "trap": {"display_name": "Trap", "stack_max": 99, "flags": ["trap"]},
        "boost_speed": {
            "display_name": "Speed tonic",
            "stack_max": 99,
            "flags": ["boost"],
        },
        "boost_regen": {
            "display_name": "Regen tonic",
            "stack_max": 99,
            "flags": ["boost"],
        },
    }


def _craft_recipes() -> dict:
    return {
        "trap_from_quartz": {
            "display_name": "Trap",
            "inputs": {"gem_quartz": 5},
            "output_id": "trap",
            "output_count": 1,
        },
        "boost_speed_craft": {
            "display_name": "Speed tonic",
            "inputs": {"gem_amber": 3, "gem_quartz": 4},
            "output_id": "boost_speed",
            "output_count": 1,
        },
        "boost_regen_craft": {
            "display_name": "Regen tonic",
            "inputs": {"gem_topaz": 3, "gem_amber": 2},
            "output_id": "boost_regen",
            "output_count": 1,
        },
    }


def _district_gems() -> dict:
    return {
        "explore_score": 50,
        "theme_totals": {
            "hill": 800,
            "castle": 40,
            "core_highrise": 35,
            "old_town": 30,
            "civic_quarter": 30,
            "waterfront_industrial": 28,
            "garden_residential": 25,
            "lake": 25,
            "graveyard": 22,
            "fractal": 20,
            "arena": 15,
            "zoo": 12,
        },
        "rarity_weights": {
            "gem_quartz": 48,
            "gem_amber": 24,
            "gem_topaz": 14,
            "gem_sapphire": 8,
            "gem_emerald": 4,
            "gem_diamond": 2,
        },
    }


def _abilities() -> tuple[dict, dict]:
    abilities = {
        "blaster": {
            "display_name": "Blaster",
            "kind": "weapon",
            "unlock_cost": {},
            "energy_cost": 1.0,
            "gated": True,
            "hint": "Hold primary fire — starter weapon",
        },
        "laser": {
            "display_name": "Laser",
            "kind": "weapon",
            "unlock_cost": {"gem_quartz": 8, "gem_topaz": 3},
            "energy_cost": 1.0,
            "gated": True,
            "hint": "Eye beam",
        },
        "charged_blast": {
            "display_name": "Charged blast",
            "kind": "weapon",
            "unlock_cost": {
                "gem_amber": 6,
                "gem_topaz": 4,
                "gem_sapphire": 2,
            },
            "energy_cost": 20.0,
            "gated": True,
            "hint": "Hold Alt fire, release to throw",
        },
        "stomp": {
            "display_name": "Stomp",
            "kind": "weapon",
            "unlock_cost": {"gem_quartz": 10, "gem_emerald": 2},
            "energy_cost": 10.0,
            "gated": True,
            "hint": "Ground slam",
        },
        "shield": {
            "display_name": "Shield",
            "kind": "power",
            "unlock_cost": {"gem_sapphire": 5, "gem_topaz": 4},
            "energy_cost": 0.0,
            "gated": True,
            "hint": "Toggle — drains energy while up and blunts hits",
        },
        "grow": {
            "display_name": "Grow",
            "kind": "power",
            "unlock_cost": {"gem_emerald": 3, "gem_amber": 4},
            "energy_cost": 12.0,
            "gated": True,
            "hint": "Temporary size up",
        },
        "shrink": {
            "display_name": "Shrink",
            "kind": "power",
            "unlock_cost": {"gem_emerald": 2, "gem_amber": 4},
            "energy_cost": 12.0,
            "gated": True,
            "hint": "Temporary size down",
        },
        "minion": {
            "display_name": "Minion",
            "kind": "power",
            "unlock_cost": {"gem_emerald": 4, "gem_quartz": 12},
            "energy_cost": 40.0,
            "gated": True,
            "hint": "Summon a half-strength ally (replaces the previous)",
        },
        "district_hop": {
            "display_name": "District hop",
            "kind": "power",
            "unlock_cost": {"gem_amber": 3, "gem_quartz": 6},
            "energy_cost": 0.0,
            "gated": True,
            "hint": "Teleport to a known district",
        },
        "tetris": {
            "display_name": "Tetris",
            "kind": "power",
            "unlock_cost": {"gem_amber": 2, "gem_quartz": 8},
            "energy_cost": 0.0,
            "gated": True,
            "hint": "Summon a cabinet",
        },
        "use_trap": {
            "display_name": "Throw trap",
            "kind": "consumable",
            "unlock_cost": {},
            "energy_cost": 0.0,
            "gated": False,
            "hint": "Aim at a world voxel and lob a hold trap there",
        },
        "use_boost_speed": {
            "display_name": "Speed boost",
            "kind": "consumable",
            "unlock_cost": {},
            "energy_cost": 0.0,
            "gated": False,
            "hint": "Drink a speed tonic",
        },
        "use_boost_regen": {
            "display_name": "Regen boost",
            "kind": "consumable",
            "unlock_cost": {},
            "energy_cost": 0.0,
            "gated": False,
            "hint": "Drink a regen tonic",
        },
        "hardness_reinforced": {
            "display_name": "Hardness: Reinforced",
            "kind": "meta",
            "unlock_cost": {"gem_diamond": 2, "gem_quartz": 20},
            "energy_cost": 0.0,
            "gated": True,
            "hint": "Carve concrete and steel",
        },
        "hardness_exotic": {
            "display_name": "Hardness: Exotic",
            "kind": "meta",
            "unlock_cost": {
                "gem_diamond": 4,
                "gem_sapphire": 4,
                "gem_quartz": 15,
            },
            "energy_cost": 0.0,
            "gated": True,
            "hint": "Carve meteor rock and infection",
        },
    }
    constants = {
        "starter_unlocks": [
            "blaster",
            "hardness_reinforced",
            "hardness_exotic",
        ],
        "trap_hostile_score": 25,
        "boost_duration_sec": 20.0,
        "grow_shrink_duration_sec": 25.0,
        "shield_drain_per_sec": 8.0,
        "minion_max": 1,
        "minion_duration_sec": 60.0,
        "default_sandbox_builds": [
            "cottage",
            "pool",
            "hot_tub",
            "dog",
            "cat",
            "duck",
        ],
    }
    return abilities, constants


def _chest_loot() -> dict:
    return {
        "gems_min": 1,
        "gems_max": 3,
        "place_chance_pct": {
            "storage": 34,
            "ordinary": 7,
            "corridor": 0,
        },
    }


def _recipe_sites() -> dict:
    return {
        "per_district_max": 2,
        "chance_pct": {
            "summit": 100,
            "castle-tower": 100,
            "arena-tower": 100,
            "gazebo": 100,
            "island": 45,
            "fractal-peak": 100,
            "crypt": 25,
            "roof": 8,
            "chest": 6,
        },
        "fallback_gems": ["gem_emerald", "gem_diamond"],
    }


def _zoo() -> dict:
    """Monster Zoo forever-war tuning: the war runs on these, not on player input."""
    return {
        "cloak_duration_sec": 120.0,
        "plate_damage_interval_sec": 1.0,
        "base_spawn_interval_sec": 14.0,
        "spawn_pressure_k": 0.9,
        "per_territory_cap": 2,
        "district_alive_cap": 34,
    }


def main() -> int:
    if LEGACY_ATTACKS.is_file():
        attacks = _load(LEGACY_ATTACKS)["attacks"]
        behaviours = _load(LEGACY_BEHAVIOURS)["behaviours"]
        table = _load(LEGACY_TABLE)
        templates = table["templates"]
        monsters = table["monsters"]
    elif gd.GAMEDATA_PATH.is_file():
        existing = gd.load_gamedata()
        attacks = existing["attacks"]
        behaviours = existing["behaviours"]
        templates = existing["templates"]
        monsters = existing["monsters"]
    else:
        raise SystemExit("no combat sources found")

    abilities, ability_constants = _abilities()
    doc = {
        "schema_version": gd.SCHEMA_VERSION,
        "attacks": attacks,
        "behaviours": behaviours,
        "templates": templates,
        "monsters": monsters,
        "items": _items(),
        "craft_recipes": _craft_recipes(),
        "build_recipes": _dump_build_recipes(),
        "district_gems": _district_gems(),
        "zoo": _zoo(),
        "abilities": abilities,
        "ability_constants": ability_constants,
        "chest_loot": _chest_loot(),
        "recipe_sites": _recipe_sites(),
        "mandelbrot_spots": _parse_mandelbrot_spots(),
    }
    gd.save_gamedata(doc)
    print(f"Wrote {gd.GAMEDATA_PATH} ({gd.GAMEDATA_PATH.stat().st_size} bytes)")
    print(
        f"  attacks={len(attacks)} behaviours={len(behaviours)} "
        f"templates={len(templates)} monsters={len(monsters)} "
        f"build={len(doc['build_recipes'])} spots={len(doc['mandelbrot_spots']['spots'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
