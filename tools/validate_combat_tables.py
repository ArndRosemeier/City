#!/usr/bin/env python3
"""Validate shared attacks, behaviours, and monster combat table.

Checks combat slices in assets/gamedata.json:
  - attacks schema (required fields, kinds, optional monster_*)
  - behaviours (attack pool per behaviour)
  - templates/monsters against CreatureCatalog
  - every behaviour id used by templates/monsters exists
  - every attack id on a behaviour / template / monster exists
  - no leftover prey weighting anywhere: hostility is faction-only
  - golden sync fixture matches resolve output (tools/fixtures/combat_effective_stats.json)

Merge helpers live in tools/combat_resolve.py (mirrored by scripts/city/combat_table.gd).
Regenerate golden: python tools/sync_combat_resolve.py --write

Data-only — no Godot runtime, no combat wiring.

Run from repo root:
  python tools/validate_combat_tables.py
  python tools/validate_combat_tables.py --skip-sync
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_TOOLS_DIR = Path(__file__).resolve().parent
if str(_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOLS_DIR))

# Pure merge/resolve helpers — keep in sync with scripts/city/combat_table.gd
import combat_resolve as resolve_mod  # noqa: E402

import gamedata_io as gd  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
GAMEDATA_PATH = gd.GAMEDATA_PATH
## Legacy aliases so older tool imports keep working — all point at the unified file.
ATTACKS_PATH = GAMEDATA_PATH
BEHAVIOURS_PATH = GAMEDATA_PATH
TABLE_PATH = GAMEDATA_PATH
CATALOG_PATH = ROOT / "scripts" / "city" / "creature_catalog.gd"

SCALAR_KEYS = resolve_mod.SCALAR_KEYS
LIST_KEYS = resolve_mod.LIST_KEYS
LIST_EXTRA_KEYS = resolve_mod.LIST_EXTRA_KEYS
MERGE_SCALARS_USE_MAX = resolve_mod.MERGE_SCALARS_USE_MAX

# Prey selection is gone: mobs hunt every faction but their own. Any of these keys
# coming back means someone is re-authoring target priority as data.
FORBIDDEN_PREY_KEYS = frozenset({"prey", "prey_extra", "prey_weights"})

ALLOWED_BEHAVIOUR = frozenset({"skirmish", "chase", "guard", "wander_hunt", "ambient"})
ALLOWED_CROWD_ROLES = frozenset(
    {
        "wave_caster",
        "wave_hunter",
        "wave_boss",
        "convert_minion",
        "dungeon_guard",
        "ambient",
    }
)
## Allegiances an authored body may take. MonsterFaction also has `human`, which the player
## and pedestrians wear — no combat-table row may claim it. `siege_attacker` is a spawn-time
## override only. `siege_defender` is authored on meshless foundation-tower rows that have no
## CreatureCatalog entry (the voxel stamp is the visual).
ALLOWED_FACTIONS = frozenset(
    {
        "undead",
        "infernal",
        "horde",
        "beast",
        "grove",
        "arcane",
        "unique",
        "siege_defender",
    }
)

KNOWN_ATTACK_KINDS = frozenset(
    {
        "melee",
        "projectile_rapid",
        "projectile_single",
        "convert_projectile",
        "area",
        "area_blast",
    }
)

REQUIRED_ATTACK_FIELDS = (
    "id",
    "kind",
    "damage_vs_player",
    "damage_vs_mob",
    "cooldown_s",
    "energy_cost",
    "range_m",
)

OPTIONAL_NUMBER_FIELDS = (
    "speed_mps",
    "windup_s",
    "fire_interval_s",
    "radius_m",
    "monster_cooldown_s",
    "monster_range_m",
    "monster_windup_s",
    "monster_fire_interval_s",
)

OPTIONAL_INT_FIELDS = (
    "burst_count",
    "monster_burst_count",
)

# Re-export resolve API for editor / sync (import validate_combat_tables as before).
union_lists = resolve_mod.union_lists
attacks_from_behaviours = resolve_mod.attacks_from_behaviours
merge_template_scalars = resolve_mod.merge_template_scalars
merge_template_lists = resolve_mod.merge_template_lists
apply_body_list_overrides = resolve_mod.apply_body_list_overrides
effective_monster_combat = resolve_mod.effective_monster_combat
effective_attack_damage = resolve_mod.effective_attack_damage
effective_attack_damages = resolve_mod.effective_attack_damages


def fail(msg: str, errors: list[str]) -> None:
    errors.append(msg)


def _names_in_array_literal(block: str) -> list[str]:
    return re.findall(r'\["([^"]+)"\s*,', block)


def extract_catalog_ids(source: str) -> list[str]:
    """Rebuild CreatureCatalog ids from the GDScript source (same rows as `_build`)."""
    ids: list[str] = []

    for name in re.findall(r'_kaykit\(\s*"([^"]+)"', source):
        ids.append(f"kaykit/{name}")

    sections = re.split(r"## Quaternius (Big|Blob|Flying):", source)
    if len(sections) < 7:
        raise RuntimeError(
            "creature_catalog.gd: expected ## Quaternius Big/Blob/Flying section markers"
        )
    family_bodies = {"big": sections[2], "blob": sections[4], "flying": sections[6]}
    for family_dir, body in family_bodies.items():
        loop = re.search(r"for row: Array in \[([\s\S]*?)\]:", body)
        if loop is None:
            raise RuntimeError(
                f"creature_catalog.gd: no for-row list under Quaternius {family_dir}"
            )
        for name in _names_in_array_literal(loop.group(1)):
            ids.append(f"{family_dir}/{name}")

    blob_section = family_bodies["blob"]
    for name in re.findall(r'_quaternius\(\s*"blob"\s*,\s*"([^"]+)"', blob_section):
        ids.append(f"blob/{name}")

    for mid in re.findall(r'_alias_quaternius\(\s*"([^"]+)"', source):
        ids.append(mid)

    return ids


def require_number(obj: dict, key: str, where: str, errors: list[str]) -> None:
    if key not in obj:
        fail(f"{where}: missing scalar '{key}'", errors)
        return
    if not isinstance(obj[key], (int, float)) or isinstance(obj[key], bool):
        fail(f"{where}: '{key}' must be numeric, got {type(obj[key]).__name__}", errors)


def require_non_negative_number(
    obj: dict, key: str, where: str, errors: list[str]
) -> None:
    require_number(obj, key, where, errors)
    if key in obj and isinstance(obj[key], (int, float)) and not isinstance(
        obj[key], bool
    ):
        if float(obj[key]) < 0.0:
            fail(f"{where}: '{key}' must be >= 0, got {obj[key]}", errors)


def _require_positive_number(
    obj: dict, key: str, where: str, errors: list[str]
) -> None:
    if key not in obj or not isinstance(obj[key], (int, float)) or isinstance(
        obj[key], bool
    ):
        return
    if float(obj[key]) <= 0.0:
        fail(f"{where}: {key} must be > 0", errors)


def require_positive_int(obj: dict, key: str, where: str, errors: list[str]) -> None:
    if key not in obj:
        fail(f"{where}: missing '{key}'", errors)
        return
    value = obj[key]
    if isinstance(value, bool) or not isinstance(value, int):
        fail(f"{where}: '{key}' must be an int, got {type(value).__name__}", errors)
        return
    if value < 1:
        fail(f"{where}: '{key}' must be >= 1, got {value}", errors)


def require_string_list(obj: dict, key: str, where: str, errors: list[str]) -> list[str]:
    if key not in obj:
        fail(f"{where}: missing list '{key}'", errors)
        return []
    value = obj[key]
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        fail(f"{where}: '{key}' must be a list of strings", errors)
        return []
    return value


def optional_string_list(obj: dict, key: str, where: str, errors: list[str]) -> list[str]:
    if key not in obj:
        return []
    value = obj[key]
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        fail(f"{where}: '{key}' must be a list of strings when present", errors)
        return []
    return value


def validate_shared_attack(aid: str, atk: dict, errors: list[str]) -> None:
    where = f"attack '{aid}'"
    if not isinstance(atk, dict):
        fail(f"{where}: must be an object", errors)
        return

    for key in REQUIRED_ATTACK_FIELDS:
        if key not in atk:
            fail(f"{where}: missing required field '{key}'", errors)

    if "id" in atk:
        if not isinstance(atk["id"], str) or not atk["id"]:
            fail(f"{where}: 'id' must be a non-empty string", errors)
        elif atk["id"] != aid:
            fail(f"{where}: id field '{atk['id']}' must match object key '{aid}'", errors)

    kind = atk.get("kind")
    if not isinstance(kind, str):
        fail(f"{where}: missing string 'kind'", errors)
        kind = ""
    elif kind not in KNOWN_ATTACK_KINDS:
        fail(f"{where}: kind '{kind}' not in {sorted(KNOWN_ATTACK_KINDS)}", errors)

    for key in (
        "damage_vs_player",
        "damage_vs_mob",
        "cooldown_s",
        "energy_cost",
        "range_m",
    ):
        require_non_negative_number(atk, key, where, errors)

    for key in OPTIONAL_NUMBER_FIELDS:
        if key in atk:
            require_non_negative_number(atk, key, where, errors)

    for key in OPTIONAL_INT_FIELDS:
        if key in atk:
            require_positive_int(atk, key, where, errors)

    if "damage_source" in atk and atk["damage_source"] is not None:
        if not isinstance(atk["damage_source"], str):
            fail(f"{where}: damage_source must be string or null", errors)

    if "carves_voxels" in atk and not isinstance(atk["carves_voxels"], bool):
        fail(f"{where}: carves_voxels must be bool when present", errors)

    if "notes" in atk and not isinstance(atk["notes"], str):
        fail(f"{where}: notes must be a string when present", errors)

    is_projectile = kind in {
        "projectile_rapid",
        "projectile_single",
        "convert_projectile",
    }
    if is_projectile and kind != "convert_projectile":
        require_number(atk, "speed_mps", where, errors)
        require_number(atk, "windup_s", where, errors)
        _require_positive_number(atk, "speed_mps", where, errors)

    if kind == "convert_projectile":
        require_number(atk, "speed_mps", where, errors)
        _require_positive_number(atk, "speed_mps", where, errors)

    if kind == "projectile_rapid":
        require_positive_int(atk, "burst_count", where, errors)
        require_number(atk, "fire_interval_s", where, errors)
        _require_positive_number(atk, "fire_interval_s", where, errors)
    elif "burst_count" in atk or "fire_interval_s" in atk:
        fail(
            f"{where}: burst_count/fire_interval_s only valid for kind projectile_rapid",
            errors,
        )

    if kind == "area_blast":
        require_number(atk, "radius_m", where, errors)
        require_number(atk, "speed_mps", where, errors)
        require_number(atk, "windup_s", where, errors)
        _require_positive_number(atk, "radius_m", where, errors)
        _require_positive_number(atk, "speed_mps", where, errors)
    elif kind == "area":
        if atk.get("carves_voxels") is True:
            require_number(atk, "radius_m", where, errors)
            require_number(atk, "windup_s", where, errors)
            _require_positive_number(atk, "radius_m", where, errors)
        elif "radius_m" in atk:
            require_number(atk, "radius_m", where, errors)
            _require_positive_number(atk, "radius_m", where, errors)
    elif kind == "convert_projectile":
        if "radius_m" in atk:
            require_number(atk, "radius_m", where, errors)
            _require_positive_number(atk, "radius_m", where, errors)
    elif "radius_m" in atk:
        fail(
            f"{where}: radius_m only valid for kind area, area_blast, or convert_projectile",
            errors,
        )

    if "monster_burst_count" in atk or "monster_fire_interval_s" in atk:
        if kind != "projectile_rapid":
            fail(
                f"{where}: monster_burst_count/monster_fire_interval_s only valid "
                "for kind projectile_rapid",
                errors,
            )


def validate_behaviour(
    bid: str, row: dict, attack_ids: set[str], errors: list[str]
) -> None:
    where = f"behaviour '{bid}'"
    if not isinstance(row, dict):
        fail(f"{where}: must be an object", errors)
        return
    if bid not in ALLOWED_BEHAVIOUR:
        fail(f"{where}: id not in allowed set {sorted(ALLOWED_BEHAVIOUR)}", errors)
    if "id" in row:
        if not isinstance(row["id"], str) or row["id"] != bid:
            fail(f"{where}: id field must match object key '{bid}'", errors)
    reject_prey_fields(row, where, errors)
    attacks = require_string_list(row, "attacks", where, errors)
    for a in attacks:
        if a not in attack_ids:
            fail(f"{where}: attack '{a}' not defined in shared attacks table", errors)
    if "intent" in row and not isinstance(row["intent"], str):
        fail(f"{where}: intent must be a string when present", errors)
    if "notes" in row and not isinstance(row["notes"], str):
        fail(f"{where}: notes must be a string when present", errors)


def validate_behaviours_document(
    data: object, attack_ids: set[str], errors: list[str]
) -> dict[str, dict]:
    if not isinstance(data, dict):
        fail("behaviours.json: root must be an object", errors)
        return {}
    behaviours = data.get("behaviours")
    if not isinstance(behaviours, dict) or not behaviours:
        fail(
            f"{BEHAVIOURS_PATH.relative_to(ROOT)}: top-level 'behaviours' must be non-empty",
            errors,
        )
        return {}
    for bid, row in behaviours.items():
        if not isinstance(bid, str) or not bid:
            fail("behaviours table has a non-string behaviour key", errors)
            continue
        validate_behaviour(bid, row, attack_ids, errors)
    return behaviours


def reject_prey_fields(obj: dict, where: str, errors: list[str]) -> None:
    for key in FORBIDDEN_PREY_KEYS:
        if key in obj:
            fail(
                f"{where}: '{key}' is forbidden — a body hunts every faction but its own, "
                "so there is nothing to weight",
                errors,
            )


def validate_template(
    tid: str,
    tmpl: dict,
    attack_ids: set[str],
    behaviour_ids: set[str],
    errors: list[str],
) -> None:
    where = f"template '{tid}'"
    if not isinstance(tmpl, dict):
        fail(f"{where}: must be an object", errors)
        return
    reject_prey_fields(tmpl, where, errors)
    for key in SCALAR_KEYS:
        require_number(tmpl, key, where, errors)
    behaviour = require_string_list(tmpl, "behaviour", where, errors)
    attacks = optional_string_list(tmpl, "attacks", where, errors)
    require_string_list(tmpl, "tags", where, errors)
    crowd = require_string_list(tmpl, "crowd_roles", where, errors)
    for b in behaviour:
        if b not in ALLOWED_BEHAVIOUR:
            fail(f"{where}: behaviour '{b}' not in {sorted(ALLOWED_BEHAVIOUR)}", errors)
        elif b not in behaviour_ids:
            fail(f"{where}: behaviour '{b}' not defined in behaviours table", errors)
    for a in attacks:
        if a not in attack_ids:
            fail(f"{where}: attack '{a}' not defined in shared attacks table", errors)
    for c in crowd:
        if c not in ALLOWED_CROWD_ROLES:
            fail(f"{where}: crowd_role '{c}' not in {sorted(ALLOWED_CROWD_ROLES)}", errors)


def validate_boss_tier_parity(templates: dict, errors: list[str]) -> None:
    """melee_boss and ranged_boss share hp_mult / damage_mult by design."""
    ranged = templates.get("ranged_boss")
    melee = templates.get("melee_boss")
    if not isinstance(ranged, dict) or not isinstance(melee, dict):
        fail("templates must define both 'ranged_boss' and 'melee_boss'", errors)
        return
    for key in ("hp_mult", "damage_mult"):
        if ranged.get(key) != melee.get(key):
            fail(
                f"template melee_boss.{key} ({melee.get(key)}) must equal "
                f"ranged_boss.{key} ({ranged.get(key)})",
                errors,
            )


def validate_monster(
    mon: dict,
    template_ids: set[str],
    attack_ids: set[str],
    behaviour_ids: set[str],
    errors: list[str],
    aura_ids: set[str] | None = None,
) -> str | None:
    if not isinstance(mon, dict):
        fail("monster entry is not an object", errors)
        return None
    mid = mon.get("id")
    if not isinstance(mid, str) or not mid:
        fail("monster entry missing string 'id'", errors)
        return None
    where = f"monster '{mid}'"
    reject_prey_fields(mon, where, errors)
    faction = mon.get("faction")
    if not isinstance(faction, str) or not faction:
        fail(f"{where}: 'faction' must be a non-empty string", errors)
    elif faction not in ALLOWED_FACTIONS:
        fail(
            f"{where}: unknown faction '{faction}' "
            f"(allowed: {', '.join(sorted(ALLOWED_FACTIONS))})",
            errors,
        )
    templates = mon.get("templates")
    if not isinstance(templates, list) or not templates or not all(
        isinstance(t, str) for t in templates
    ):
        fail(f"{where}: 'templates' must be a non-empty list of strings", errors)
    else:
        for t in templates:
            if t not in template_ids:
                fail(f"{where}: unknown template '{t}'", errors)
    if "spawn_ready" in mon and not isinstance(mon["spawn_ready"], bool):
        fail(f"{where}: spawn_ready must be bool", errors)
    if "spawn_weight" in mon:
        require_number(mon, "spawn_weight", where, errors)
    for key in SCALAR_KEYS:
        if key in mon:
            require_number(mon, key, where, errors)
    for key in LIST_KEYS:
        if key in mon:
            values = require_string_list(mon, key, where, errors)
            _check_list_enums(
                where, key, values, attack_ids, behaviour_ids, errors, aura_ids
            )
    for key in LIST_EXTRA_KEYS:
        if key in mon:
            values = require_string_list(mon, key, where, errors)
            base = key.removesuffix("_extra")
            _check_list_enums(
                where, base, values, attack_ids, behaviour_ids, errors, aura_ids
            )
    return mid


def _check_list_enums(
    where: str,
    key: str,
    values: list[str],
    attack_ids: set[str],
    behaviour_ids: set[str],
    errors: list[str],
    aura_ids: set[str] | None = None,
) -> None:
    if key == "behaviour":
        for b in values:
            if b not in ALLOWED_BEHAVIOUR:
                fail(f"{where}: behaviour '{b}' not allowed", errors)
            elif b not in behaviour_ids:
                fail(f"{where}: behaviour '{b}' not defined in behaviours table", errors)
    elif key == "attacks":
        for a in values:
            if a not in attack_ids:
                fail(f"{where}: attack '{a}' not defined in shared attacks table", errors)
    elif key == "crowd_roles":
        for c in values:
            if c not in ALLOWED_CROWD_ROLES:
                fail(f"{where}: crowd_role '{c}' not allowed", errors)
    elif key == "auras":
        known = aura_ids or set()
        for aura in values:
            if aura not in known:
                fail(f"{where}: aura '{aura}' not defined in auras table", errors)


def validate_attacks_document(data: object, errors: list[str]) -> dict[str, dict]:
    """Validate an in-memory attacks.json document. Returns the attacks map."""
    if not isinstance(data, dict):
        fail("attacks.json: root must be an object", errors)
        return {}
    attacks = data.get("attacks")
    if not isinstance(attacks, dict) or not attacks:
        fail(
            f"{ATTACKS_PATH.relative_to(ROOT)}: top-level 'attacks' must be non-empty",
            errors,
        )
        return {}
    for aid, atk in attacks.items():
        if not isinstance(aid, str) or not aid:
            fail("shared attacks table has a non-string attack key", errors)
            continue
        validate_shared_attack(aid, atk, errors)
    return attacks


def load_shared_attacks(errors: list[str]) -> dict[str, dict]:
    if not ATTACKS_PATH.is_file():
        fail(f"missing {ATTACKS_PATH}", errors)
        return {}
    data = json.loads(ATTACKS_PATH.read_text(encoding="utf-8"))
    return validate_attacks_document(data, errors)


def validate_combat_table_document(
    table: object,
    attack_ids: set[str],
    behaviours: dict[str, dict],
    errors: list[str],
) -> dict[str, int]:
    """Validate an in-memory combat_table.json. Returns monster id → count."""
    if not isinstance(table, dict):
        fail("combat_table.json: root must be an object", errors)
        return {}

    if "attacks" in table:
        fail(
            f"{TABLE_PATH.relative_to(ROOT)}: inline 'attacks' block must be removed; "
            "use assets/gamedata.json attacks",
            errors,
        )

    if not CATALOG_PATH.is_file():
        fail(f"missing {CATALOG_PATH}", errors)
        catalog_set: set[str] = set()
    else:
        catalog_ids = extract_catalog_ids(CATALOG_PATH.read_text(encoding="utf-8"))
        catalog_set = set(catalog_ids)
        if len(catalog_ids) != len(catalog_set):
            fail("creature_catalog.gd produced duplicate ids", errors)

    templates = table.get("templates")
    monsters = table.get("monsters")
    if not isinstance(templates, dict) or not templates:
        fail("top-level 'templates' must be a non-empty object", errors)
        templates = {}
    if not isinstance(monsters, list) or not monsters:
        fail("top-level 'monsters' must be a non-empty list", errors)
        monsters = []

    behaviour_ids = set(behaviours.keys())
    template_ids = set(templates.keys())
    aura_ids: set[str] = set()
    if GAMEDATA_PATH.is_file():
        root = gd.load_gamedata()
        auras_raw = root.get("auras") if isinstance(root, dict) else None
        if isinstance(auras_raw, dict):
            aura_ids = {str(k) for k in auras_raw.keys()}
            for aid, row in auras_raw.items():
                if not isinstance(aid, str) or not aid:
                    fail("auras table has a non-string key", errors)
                elif not isinstance(row, dict):
                    fail(f"aura '{aid}' must be an object", errors)
        else:
            fail("gamedata.json: top-level 'auras' must be an object", errors)
    for tid, tmpl in templates.items():
        validate_template(tid, tmpl, attack_ids, behaviour_ids, errors)
        if isinstance(tmpl, dict):
            for aura in optional_string_list(tmpl, "auras", f"template '{tid}'", errors):
                if aura not in aura_ids:
                    fail(
                        f"template '{tid}': aura '{aura}' not defined in auras table",
                        errors,
                    )

    validate_boss_tier_parity(templates, errors)

    seen: dict[str, int] = {}
    for mon in monsters:
        mid = validate_monster(
            mon, template_ids, attack_ids, behaviour_ids, errors, aura_ids
        )
        if mid is None:
            continue
        seen[mid] = seen.get(mid, 0) + 1
        # Resolve effective combat — loud errors if behaviours missing mid-merge.
        if isinstance(mon, dict) and isinstance(mon.get("templates"), list):
            tids = [t for t in mon["templates"] if isinstance(t, str)]
            if tids and all(t in templates for t in tids):
                try:
                    eff = effective_monster_combat(tids, templates, mon, behaviours)
                    for a in eff["attacks"]:
                        if a not in attack_ids:
                            fail(
                                f"monster '{mid}': derived attack '{a}' not in shared table",
                                errors,
                            )
                except (KeyError, TypeError, RuntimeError) as exc:
                    fail(f"monster '{mid}': effective resolve failed: {exc}", errors)

    for mid, count in sorted(seen.items()):
        if count != 1:
            fail(f"monster id '{mid}' appears {count} times (want exactly once)", errors)
        ## Siege towers are combat rows without a creature mesh — skip the 1:1 catalog rule.
        if mid.startswith("siege/"):
            continue
        if catalog_set and mid not in catalog_set:
            fail(f"monster id '{mid}' is not in CreatureCatalog", errors)

    if catalog_set:
        for cid in sorted(catalog_set):
            if cid not in seen:
                fail(f"CreatureCatalog id '{cid}' missing from combat table", errors)

    return seen


def validate_combat_data(
    attacks_doc: object,
    table_doc: object,
    behaviours_doc: object | None = None,
) -> list[str]:
    """Validate in-memory combat JSON docs. Returns error strings (empty = OK)."""
    errors: list[str] = []
    shared_attacks = validate_attacks_document(attacks_doc, errors)
    attack_ids = set(shared_attacks.keys())
    if behaviours_doc is None:
        if not GAMEDATA_PATH.is_file():
            fail(f"missing {GAMEDATA_PATH}", errors)
            behaviours: dict[str, dict] = {}
        else:
            behaviours_doc = gd.behaviours_doc(gd.load_gamedata())
            behaviours = validate_behaviours_document(behaviours_doc, attack_ids, errors)
    else:
        behaviours = validate_behaviours_document(behaviours_doc, attack_ids, errors)
    validate_combat_table_document(table_doc, attack_ids, behaviours, errors)
    return errors


def main() -> int:
    skip_sync = "--skip-sync" in sys.argv

    if not CATALOG_PATH.is_file():
        print(f"FAIL: missing {CATALOG_PATH}", file=sys.stderr)
        return 1
    if not GAMEDATA_PATH.is_file():
        print(f"FAIL: missing {GAMEDATA_PATH}", file=sys.stderr)
        return 1

    root = gd.load_gamedata()
    attacks_doc = gd.attacks_doc(root)
    behaviours_doc = gd.behaviours_doc(root)
    table = gd.table_doc(root)
    errors = validate_combat_data(attacks_doc, table, behaviours_doc)

    shared_attacks = (
        attacks_doc.get("attacks") if isinstance(attacks_doc, dict) else {}
    )
    behaviours = (
        behaviours_doc.get("behaviours") if isinstance(behaviours_doc, dict) else {}
    )
    templates = table.get("templates") if isinstance(table, dict) else {}
    attack_ids = (
        set(shared_attacks.keys()) if isinstance(shared_attacks, dict) else set()
    )
    behaviour_ids = set(behaviours.keys()) if isinstance(behaviours, dict) else set()
    template_ids = set(templates.keys()) if isinstance(templates, dict) else set()
    monsters = table.get("monsters") if isinstance(table, dict) else []
    seen_count = len(monsters) if isinstance(monsters, list) else 0

    if errors:
        print(
            f"FAIL: {len(errors)} problem(s) in {GAMEDATA_PATH.relative_to(ROOT)}"
        )
        for err in errors:
            print(f"  - {err}")
        return 1

    print(
        "OK: shared attacks="
        f"{len(attack_ids)}, behaviours={len(behaviour_ids)}, "
        f"combat table covers {seen_count} catalog bodies, "
        f"{len(template_ids)} templates"
    )

    if not skip_sync:
        import sync_combat_resolve as sync_mod  # noqa: WPS433

        sync_diffs = sync_mod.check_golden()
        if sync_diffs:
            print(
                f"FAIL: {len(sync_diffs)} combat resolve sync drift(s) — "
                "python tools/sync_combat_resolve.py --write"
            )
            for d in sync_diffs[:40]:
                print(f"  - {d}")
            return 1
        print("OK: combat resolve golden fixture in sync")

    return 0


if __name__ == "__main__":
    sys.exit(main())
