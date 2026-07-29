#!/usr/bin/env python3
"""Pure combat-table merge / resolve helpers shared by validator, editor, and sync.

GDScript mirror: scripts/city/combat_table.gd (class_name CombatTable).
Function names and merge rules must stay in lockstep — see tools/sync_combat_resolve.py
and tools/fixtures/combat_effective_stats.json.

Merge rules:
  - Scalars: max across templates; body scalar keys replace
  - Lists: union across templates; *_extra adds; bare list on body hard-replaces
  - Prey weights: mean across effective behaviours (missing key = 0); not from templates
  - Attacks: union from effective behaviours, then body overrides:
      hard body `attacks` → full effective list (drops behaviour-derived)
      else → behaviour pool ∪ template specialty ∪ body `attacks_extra`
"""

from __future__ import annotations

from typing import Any

SCALAR_KEYS = (
    "hp_mult",
    "damage_mult",
    "speed_mult",
    "aggro_range_m",
    "leash_m",
    "preferred_range_m",
    "armor_mult",
    "score_mult",
)

# Prey is not a template/monster list field — it lives on behaviours.
LIST_KEYS = ("behaviour", "attacks", "tags", "crowd_roles")
LIST_EXTRA_KEYS = (
    "behaviour_extra",
    "attacks_extra",
    "tags_extra",
    "crowd_roles_extra",
)

ALLOWED_PREY = frozenset({"player", "ped", "building", "monsters"})

# Multi-template scalar merge: highest value wins (never average).
MERGE_SCALARS_USE_MAX = True
# Prey weights: mean across behaviours; missing keys count as 0.
PREY_MISSING_COUNTS_AS_ZERO = True

# Golden / sync float rounding — keep Python and Godot comparisons stable.
SYNC_FLOAT_DECIMALS = 6


def union_lists(*lists: list[str]) -> list[str]:
    """Order-stable union of string lists.  # GDScript: CombatTable.union_lists"""
    seen: set[str] = set()
    out: list[str] = []
    for lst in lists:
        for item in lst:
            if item in seen:
                continue
            seen.add(item)
            out.append(item)
    return out


def average_prey_weights(
    behaviour_ids: list[str],
    behaviours: dict[str, dict],
) -> dict[str, float]:
    """Mean prey weight per key across behaviours; missing keys count as 0.

    Empty behaviour_ids → all zeros. Raises KeyError if a behaviour id is unknown.
    # GDScript: CombatTable.average_prey_weights
    """
    if not PREY_MISSING_COUNTS_AS_ZERO:
        raise RuntimeError("PREY_MISSING_COUNTS_AS_ZERO must stay True")
    out: dict[str, float] = {key: 0.0 for key in sorted(ALLOWED_PREY)}
    if not behaviour_ids:
        return out
    n = float(len(behaviour_ids))
    for bid in behaviour_ids:
        row = behaviours.get(bid)
        if not isinstance(row, dict):
            raise KeyError(f"unknown behaviour '{bid}'")
        weights = row.get("prey_weights")
        if not isinstance(weights, dict):
            weights = {}
        for key in ALLOWED_PREY:
            raw = weights.get(key, 0.0)
            if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                raise TypeError(
                    f"behaviour '{bid}' prey_weights.{key} must be numeric"
                )
            out[key] += float(raw)
    for key in out:
        out[key] /= n
    return out


def attacks_from_behaviours(
    behaviour_ids: list[str],
    behaviours: dict[str, dict],
) -> list[str]:
    """Order-stable union of attack ids listed on each behaviour.
    # GDScript: CombatTable.attacks_from_behaviours
    """
    pools: list[list[str]] = []
    for bid in behaviour_ids:
        row = behaviours.get(bid)
        if not isinstance(row, dict):
            raise KeyError(f"unknown behaviour '{bid}'")
        attacks = row.get("attacks", [])
        if not isinstance(attacks, list) or not all(isinstance(a, str) for a in attacks):
            raise TypeError(f"behaviour '{bid}' attacks must be a list of strings")
        pools.append(attacks)
    return union_lists(*pools)


def merge_template_scalars(template_ids: list[str], templates: dict) -> dict[str, float]:
    """Scalar merge rule: maximum across templates (never average).
    # GDScript: CombatTable.merge_template_scalars
    """
    if not MERGE_SCALARS_USE_MAX:
        raise RuntimeError("MERGE_SCALARS_USE_MAX must stay True — averaging is forbidden")
    out: dict[str, float] = {}
    for key in SCALAR_KEYS:
        values: list[float] = []
        for tid in template_ids:
            tmpl = templates.get(tid)
            if not isinstance(tmpl, dict):
                raise RuntimeError(f"merge_template_scalars: missing template '{tid}'")
            raw = tmpl.get(key)
            if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                raise RuntimeError(
                    f"merge_template_scalars: template '{tid}' scalar '{key}' not numeric"
                )
            values.append(float(raw))
        out[key] = max(values)
    return out


def merge_template_lists(template_ids: list[str], templates: dict) -> dict[str, list[str]]:
    """Union list fields across templates (behaviour, attacks, tags, crowd_roles).
    # GDScript: CombatTable.merge_template_lists
    """
    out: dict[str, list[str]] = {k: [] for k in LIST_KEYS}
    for tid in template_ids:
        tmpl = templates.get(tid)
        if not isinstance(tmpl, dict):
            raise RuntimeError(f"merge_template_lists: missing template '{tid}'")
        for key in LIST_KEYS:
            raw = tmpl.get(key)
            if raw is None:
                continue
            if not isinstance(raw, list) or not all(isinstance(x, str) for x in raw):
                raise RuntimeError(
                    f"merge_template_lists: template '{tid}' '{key}' must be string list"
                )
            out[key] = union_lists(out[key], raw)
    return out


def apply_body_list_overrides(
    merged_lists: dict[str, list[str]], body: dict
) -> dict[str, list[str]]:
    """Apply body hard-replace / *_extra list overrides.
    # GDScript: CombatTable.apply_body_list_overrides
    """
    lists: dict[str, list[str]] = {k: list(v) for k, v in merged_lists.items()}
    for key in LIST_KEYS:
        extra_key = f"{key}_extra"
        if key in body:
            raw = body[key]
            if not isinstance(raw, list) or not all(isinstance(x, str) for x in raw):
                raise TypeError(f"body list override '{key}' must be a list of strings")
            lists[key] = list(raw)
            continue
        if extra_key in body:
            raw = body[extra_key]
            if not isinstance(raw, list) or not all(isinstance(x, str) for x in raw):
                raise TypeError(f"body '{extra_key}' must be a list of strings")
            lists[key] = union_lists(lists[key], raw)
    return lists


def effective_monster_combat(
    template_ids: list[str],
    templates: dict,
    body: dict,
    behaviours: dict[str, dict],
) -> dict[str, Any]:
    """Resolve scalars, lists, averaged prey weights, and derived attacks for a body.
    # GDScript: CombatTable.effective_monster_combat / CombatTable.resolve
    """
    scalars = merge_template_scalars(template_ids, templates)
    for key in SCALAR_KEYS:
        if key in body:
            raw = body[key]
            if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                raise TypeError(f"body scalar '{key}' must be numeric")
            scalars[key] = float(raw)

    lists = apply_body_list_overrides(merge_template_lists(template_ids, templates), body)
    behaviour_ids = lists["behaviour"]
    prey = average_prey_weights(behaviour_ids, behaviours)
    derived = attacks_from_behaviours(behaviour_ids, behaviours)
    # lists["attacks"] already includes template specialty and body attacks_extra
    # (via apply_body_list_overrides). Hard body `attacks` replaces the entire
    # effective attack list; otherwise union behaviour-derived with that specialty pool.
    if "attacks" in body:
        attacks = list(lists["attacks"])
    else:
        attacks = union_lists(derived, lists["attacks"])
    return {
        "scalars": scalars,
        "lists": lists,
        "behaviour": behaviour_ids,
        "prey_weights": prey,
        "attacks": attacks,
    }


def _round_sync_float(value: float) -> float:
    return round(float(value), SYNC_FLOAT_DECIMALS)


def sync_payload(eff: dict[str, Any]) -> dict[str, Any]:
    """Normalize an effective_monster_combat result for the golden sync fixture.

    Attacks / behaviour / tags / crowd_roles are sorted; prey keys sorted; scalars
    rounded. Runtime list order in resolve() is unchanged — only the sync export sorts.
    """
    scalars = eff["scalars"]
    lists = eff["lists"]
    prey = eff["prey_weights"]
    out: dict[str, Any] = {}
    for key in SCALAR_KEYS:
        out[key] = _round_sync_float(float(scalars[key]))
    out["behaviour"] = sorted(eff["behaviour"])
    out["attacks"] = sorted(eff["attacks"])
    out["prey_weights"] = {
        key: _round_sync_float(float(prey[key])) for key in sorted(ALLOWED_PREY)
    }
    out["tags"] = sorted(lists["tags"])
    out["crowd_roles"] = sorted(lists["crowd_roles"])
    return out


def resolve_all_monsters(
    templates: dict,
    monsters: list,
    behaviours: dict[str, dict],
) -> dict[str, dict[str, Any]]:
    """Resolve every monster row → sync_payload, keyed by monster id (sorted keys)."""
    out: dict[str, dict[str, Any]] = {}
    for mon in monsters:
        if not isinstance(mon, dict):
            raise TypeError("monster entry must be an object")
        mid = mon.get("id")
        if not isinstance(mid, str) or not mid:
            raise ValueError("monster entry missing string id")
        tids = mon.get("templates")
        if not isinstance(tids, list) or not tids or not all(isinstance(t, str) for t in tids):
            raise ValueError(f"monster '{mid}': templates must be a non-empty list of strings")
        eff = effective_monster_combat(tids, templates, mon, behaviours)
        out[mid] = sync_payload(eff)
    return dict(sorted(out.items()))


def build_golden_document(
    templates: dict,
    monsters: list,
    behaviours: dict[str, dict],
) -> dict[str, Any]:
    """Full golden fixture document written to tools/fixtures/combat_effective_stats.json."""
    return {
        "schema_version": 1,
        "note": (
            "AUTO-GENERATED by tools/sync_combat_resolve.py — do not edit by hand. "
            "Regenerate after changing merge rules or combat JSON. "
            "GDScript mirror: scripts/city/combat_table.gd"
        ),
        "monsters": resolve_all_monsters(templates, monsters, behaviours),
    }
