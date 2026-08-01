#!/usr/bin/env python3
"""Tighten within-tier monster power by rewriting combat scalars in gamedata.json.

Goals (open-field 1v1 scores from simulate_monster_duels.py):
  - same tier should not have a clear always-better body
  - keep between-tier identity (boss > brute > minion)

Changes:
  1) Template kit / scalar soft-nerfs so stacked templates stop creating kings
  2) Per-body hp_mult so effective HP hugs a tier target (cancels mesh-size drift)
  3) Kit parity fixes (rogue blaster; demolisher minion outlier)

Run:
  python tools/balance_monster_tiers.py
  python tools/sync_combat_resolve.py --write
  python tools/simulate_monster_duels.py --all-pairs --duels 6
"""

from __future__ import annotations

import sys
from pathlib import Path

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

import combat_resolve as resolve_mod  # noqa: E402
import gamedata_io as gd  # noqa: E402
from simulate_monster_duels import (  # noqa: E402
    base_hp,
    parse_catalog_bodies,
    _tier_from_templates,
)

# Target effective HP (CreatureHealth base × hp_mult) per balance tier.
TIER_HP_TARGET = {
    "boss": 200.0,
    "brute": 145.0,
    "minion": 22.0,
    "minion_brute": 70.0,
    "other": 42.0,  # rangestriker
}

# Soft clamp: do not write hp_mult outside this band (catches bad targets).
HP_MULT_MIN = 0.35
# Small flying bases need a high mult to hit boss HP targets.
HP_MULT_MAX = 8.0


def _apply_template_tweaks(templates: dict) -> None:
    # Validator requires melee_boss and ranged_boss to share hp_mult / damage_mult.
    for key in ("melee_boss", "ranged_boss"):
        templates[key]["hp_mult"] = 2.0
        templates[key]["damage_mult"] = 2.0
    templates["boss"]["damage_mult"] = 2.0
    # Pure boss bodies were melee-only fodder vs artillery — give them a close burst.
    templates["boss"]["attacks"] = ["stomp"]
    # Demolisher must not promote a minion into a mid-brute via max-merge.
    templates["demolisher"]["hp_mult"] = 0.55
    templates["demolisher"]["armor_mult"] = 0.95
    templates["demolisher"]["damage_mult"] = 0.9


def _apply_kit_parity(monsters: list[dict]) -> None:
    by_id = {m["id"]: m for m in monsters}
    # Rogue hard-replaces attacks (so attacks_extra is ignored) and stood too close.
    rogue = by_id["kaykit/Skeleton_Rogue"]
    rogue["attacks"] = ["blaster", "eye_laser", "melee", "orb_convert"]
    rogue.pop("attacks_extra", None)
    rogue["preferred_range_m"] = 24.0
    # Cactoro was minion+demolisher with huge max-merge HP; keep flavor tag only.
    cactoro = by_id["blob/Cactoro"]
    cactoro["templates"] = ["minion"]
    tags = list(cactoro.get("tags_extra") or [])
    if "relentless" not in tags:
        tags.append("relentless")
    cactoro["tags_extra"] = tags
    # Drop the old Yeti hand-tuned hp_mult; tier HP pass will rewrite it.
    yeti = by_id.get("big/Yeti")
    if yeti is not None:
        yeti.pop("hp_mult", None)
    # Ninja speed edge made it the perpetual brute winner in open field.
    ninja = by_id.get("big/Ninja")
    if ninja is not None:
        ninja.pop("speed_mult", None)


def _normalize_hp(monsters: list[dict], templates: dict, behaviours: dict) -> None:
    catalog = parse_catalog_bodies()
    for mon in monsters:
        mid = mon["id"]
        tids = list(mon["templates"])
        tier = _tier_from_templates(tids)
        target = TIER_HP_TARGET[tier]
        body_base = base_hp(catalog[mid])
        # Preview merge without body hp_mult so we know what to replace toward.
        preview = {k: v for k, v in mon.items() if k != "hp_mult"}
        eff = resolve_mod.effective_monster_combat(tids, templates, preview, behaviours)
        # We always hard-set body hp_mult = target / base (replaces merged scalar).
        hp_mult = target / body_base
        hp_mult = max(HP_MULT_MIN, min(HP_MULT_MAX, hp_mult))
        mon["hp_mult"] = round(hp_mult, 4)
        _ = eff


def _boss_kit_parity(monsters: list[dict], templates: dict, behaviours: dict) -> None:
    """Open-field sims favor artillery; buff pure-melee bosses toward the boss band."""
    ranged = {"blaster", "eye_laser", "charged_blast"}
    for mon in monsters:
        tids = list(mon["templates"])
        if _tier_from_templates(tids) != "boss":
            continue
        preview = {k: v for k, v in mon.items() if k not in ("damage_mult", "armor_mult")}
        eff = resolve_mod.effective_monster_combat(tids, templates, preview, behaviours)
        attacks = set(eff["attacks"])
        if attacks & ranged:
            # Artillery wins open-field trades; soft-nerf so melee bosses stay peers.
            mon["damage_mult"] = 1.85
            mon["armor_mult"] = 1.4
        else:
            mon["damage_mult"] = 2.55
            mon["armor_mult"] = 1.85


def main() -> int:
    root = gd.load_gamedata()
    templates = root["templates"]
    monsters = root["monsters"]
    behaviours = root["behaviours"]
    assert isinstance(templates, dict) and isinstance(monsters, list)

    _apply_template_tweaks(templates)
    _apply_kit_parity(monsters)
    _normalize_hp(monsters, templates, behaviours)
    _boss_kit_parity(monsters, templates, behaviours)

    gd.save_gamedata(root)
    print(f"OK: wrote {gd.GAMEDATA_PATH.relative_to(gd.ROOT)}")
    print("Tier HP targets:", TIER_HP_TARGET)
    print("Next: python tools/sync_combat_resolve.py --write")
    print("      python tools/simulate_monster_duels.py --all-pairs --duels 6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
