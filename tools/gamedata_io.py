"""Load / save the single authored game-data document.

Every Python tool that needs combat, items, recipes, districts, abilities, or
Mandelbrot spots goes through this module so the on-disk shape can change in one place.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
GAMEDATA_PATH = ROOT / "assets" / "gamedata.json"

SCHEMA_VERSION = 1


def load_gamedata(path: Path | None = None) -> dict[str, Any]:
    p = path or GAMEDATA_PATH
    raw = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"{p}: root must be an object")
    return raw


def save_gamedata(doc: dict[str, Any], path: Path | None = None) -> None:
    p = path or GAMEDATA_PATH
    p.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    p.write_text(text, encoding="utf-8")


def attacks_doc(doc: dict[str, Any]) -> dict[str, Any]:
    return {"attacks": dict(doc.get("attacks") or {})}


def behaviours_doc(doc: dict[str, Any]) -> dict[str, Any]:
    return {"behaviours": dict(doc.get("behaviours") or {})}


def table_doc(doc: dict[str, Any]) -> dict[str, Any]:
    return {
        "templates": dict(doc.get("templates") or {}),
        "monsters": list(doc.get("monsters") or []),
    }


def apply_combat_docs(
    root: dict[str, Any],
    attacks: dict[str, Any],
    behaviours: dict[str, Any],
    table: dict[str, Any],
) -> dict[str, Any]:
    """Write combat slices into a full gamedata root (preserves non-combat keys)."""
    root["attacks"] = dict(attacks.get("attacks") or {})
    root["behaviours"] = dict(behaviours.get("behaviours") or {})
    root["templates"] = dict(table.get("templates") or {})
    root["monsters"] = list(table.get("monsters") or [])
    return root
