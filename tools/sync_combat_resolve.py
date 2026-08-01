#!/usr/bin/env python3
"""Keep Python combat resolve and GDScript CombatTable in lockstep via a golden file.

Writes / checks tools/fixtures/combat_effective_stats.json — every monster id mapped to
its effective scalars, behaviours, sorted attacks (with vs_player/vs_mob damage ×
damage_mult), tags, and crowd_roles.

When merge rules change:
  1. Update tools/combat_resolve.py AND scripts/city/combat_table.gd identically
  2. Regenerate:  python tools/sync_combat_resolve.py --write
  3. Verify:      python tools/sync_combat_resolve.py
                  powershell -File tools/run_test.ps1 test_combat_table_sync -KeepLog

Also invoked from validate_combat_tables.py (check mode) after schema validation succeeds.

Run from repo root:
  python tools/sync_combat_resolve.py           # check golden matches current data
  python tools/sync_combat_resolve.py --write   # regenerate golden fixture
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[0]
sys.path.insert(0, str(TOOLS))

import combat_resolve as resolve_mod  # noqa: E402
import validate_combat_tables as validate_mod  # noqa: E402

FIXTURE_PATH = TOOLS / "fixtures" / "combat_effective_stats.json"


def _load_docs() -> tuple[dict, dict, dict]:
    attacks_doc = json.loads(validate_mod.ATTACKS_PATH.read_text(encoding="utf-8"))
    behaviours_doc = json.loads(validate_mod.BEHAVIOURS_PATH.read_text(encoding="utf-8"))
    table_doc = json.loads(validate_mod.TABLE_PATH.read_text(encoding="utf-8"))
    if not isinstance(attacks_doc, dict):
        raise TypeError("attacks.json root must be an object")
    if not isinstance(behaviours_doc, dict):
        raise TypeError("behaviours.json root must be an object")
    if not isinstance(table_doc, dict):
        raise TypeError("combat_table.json root must be an object")
    return attacks_doc, behaviours_doc, table_doc


def build_golden_from_disk() -> dict:
    attacks_doc, behaviours_doc, table_doc = _load_docs()
    attacks = attacks_doc.get("attacks")
    behaviours = behaviours_doc.get("behaviours")
    templates = table_doc.get("templates")
    monsters = table_doc.get("monsters")
    if not isinstance(attacks, dict):
        raise TypeError("attacks.json: 'attacks' must be an object")
    if not isinstance(behaviours, dict):
        raise TypeError("behaviours.json: 'behaviours' must be an object")
    if not isinstance(templates, dict):
        raise TypeError("combat_table.json: 'templates' must be an object")
    if not isinstance(monsters, list):
        raise TypeError("combat_table.json: 'monsters' must be a list")
    return resolve_mod.build_golden_document(templates, monsters, behaviours, attacks)


def write_golden(path: Path = FIXTURE_PATH) -> dict:
    doc = build_golden_from_disk()
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")
    return doc


def _diff_payloads(
    expected: dict, actual: dict, prefix: str, diffs: list[str]
) -> None:
    exp_keys = set(expected.keys())
    act_keys = set(actual.keys())
    for key in sorted(exp_keys - act_keys):
        diffs.append(f"{prefix}: missing key '{key}' in actual")
    for key in sorted(act_keys - exp_keys):
        diffs.append(f"{prefix}: unexpected key '{key}' in actual")
    for key in sorted(exp_keys & act_keys):
        ev = expected[key]
        av = actual[key]
        if isinstance(ev, dict) and isinstance(av, dict):
            _diff_payloads(ev, av, f"{prefix}.{key}", diffs)
        elif ev != av:
            diffs.append(f"{prefix}.{key}: expected {ev!r}, got {av!r}")


def check_golden(path: Path = FIXTURE_PATH) -> list[str]:
    """Return loud diff strings; empty list means match."""
    if not path.is_file():
        return [
            f"missing golden fixture {path.relative_to(ROOT)} — run "
            "python tools/sync_combat_resolve.py --write"
        ]
    try:
        on_disk = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"golden fixture is not valid JSON: {exc}"]
    if not isinstance(on_disk, dict):
        return ["golden fixture root must be an object"]

    computed = build_golden_from_disk()
    diffs: list[str] = []
    if on_disk.get("schema_version") != computed.get("schema_version"):
        diffs.append(
            f"schema_version: expected {computed.get('schema_version')!r}, "
            f"got {on_disk.get('schema_version')!r}"
        )
    exp_monsters = on_disk.get("monsters")
    act_monsters = computed.get("monsters")
    if not isinstance(exp_monsters, dict):
        diffs.append("golden 'monsters' must be an object")
        return diffs
    if not isinstance(act_monsters, dict):
        diffs.append("computed 'monsters' must be an object")
        return diffs
    exp_ids = set(exp_monsters.keys())
    act_ids = set(act_monsters.keys())
    for mid in sorted(exp_ids - act_ids):
        diffs.append(f"monster '{mid}': in golden but not in current combat table resolve")
    for mid in sorted(act_ids - exp_ids):
        diffs.append(
            f"monster '{mid}': resolved from current data but missing from golden — "
            "run python tools/sync_combat_resolve.py --write"
        )
    for mid in sorted(exp_ids & act_ids):
        ev = exp_monsters[mid]
        av = act_monsters[mid]
        if not isinstance(ev, dict) or not isinstance(av, dict):
            diffs.append(f"monster '{mid}': payload must be an object")
            continue
        _diff_payloads(ev, av, f"monster '{mid}'", diffs)
    return diffs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="regenerate tools/fixtures/combat_effective_stats.json",
    )
    args = parser.parse_args()

    # Schema must be valid before trusting resolve output.
    errors = validate_mod.validate_combat_data(
        json.loads(validate_mod.ATTACKS_PATH.read_text(encoding="utf-8")),
        json.loads(validate_mod.TABLE_PATH.read_text(encoding="utf-8")),
        json.loads(validate_mod.BEHAVIOURS_PATH.read_text(encoding="utf-8")),
    )
    if errors:
        print(f"FAIL: combat tables invalid ({len(errors)} error(s)); fix before sync")
        for err in errors[:20]:
            print(f"  - {err}")
        return 1

    if args.write:
        doc = write_golden()
        n = len(doc["monsters"])
        print(
            f"OK: wrote {FIXTURE_PATH.relative_to(ROOT)} "
            f"({n} monsters). Update CombatTable.gd if merge rules changed."
        )
        return 0

    diffs = check_golden()
    if diffs:
        print(
            f"FAIL: {len(diffs)} sync drift(s) vs {FIXTURE_PATH.relative_to(ROOT)}"
        )
        for d in diffs[:60]:
            print(f"  - {d}")
        if len(diffs) > 60:
            print(f"  … ({len(diffs) - 60} more)")
        print("Regenerate with: python tools/sync_combat_resolve.py --write")
        print(
            "If merge rules changed, update scripts/city/combat_table.gd to match "
            "tools/combat_resolve.py, then regenerate."
        )
        return 1

    computed = build_golden_from_disk()
    print(
        f"OK: golden sync matches ({len(computed['monsters'])} monsters) — "
        f"{FIXTURE_PATH.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
