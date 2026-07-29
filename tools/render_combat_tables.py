#!/usr/bin/env python3
"""Build a self-contained HTML report from combat JSON tables.

Reads:
  assets/combat/attacks.json
  assets/combat/behaviours.json
  assets/monsters/combat_table.json

Merge / derive (implemented in validate_combat_tables.py):
  1) max scalars / union lists across assigned templates
  2) effective prey weights = mean across behaviours (missing key = 0)
  3) effective attacks = union of behaviour pools (+ specialty / body overrides)
  4) body overrides: bare list replaces; `*_extra` appends; scalar replaces

Usage (from repo root):
  python tools/render_combat_tables.py
"""

from __future__ import annotations

import html
import json
import os
import sys
import webbrowser
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_combat_tables as validate_mod  # noqa: E402

ATTACKS_PATH = validate_mod.ATTACKS_PATH
BEHAVIOURS_PATH = validate_mod.BEHAVIOURS_PATH
COMBAT_TABLE_PATH = validate_mod.TABLE_PATH
OUT_PATH = Path(__file__).resolve().parent / "combat_tables.html"

SCALAR_KEYS = validate_mod.SCALAR_KEYS
LIST_KEYS = validate_mod.LIST_KEYS
PREY_KEYS = tuple(sorted(validate_mod.ALLOWED_PREY))

ATTACK_CORE_COLS = (
    "id",
    "kind",
    "damage_vs_player",
    "damage_vs_mob",
    "cooldown_s",
    "energy_cost",
    "range_m",
)

ATTACK_EXTRA_COLS = (
    "radius_m",
    "speed_mps",
    "windup_s",
    "burst_count",
    "fire_interval_s",
    "monster_cooldown_s",
    "monster_range_m",
    "monster_windup_s",
    "monster_burst_count",
    "monster_fire_interval_s",
    "carves_voxels",
    "damage_source",
)


def load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required JSON: {path}")
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"Expected object at root of {path}, got {type(data).__name__}")
    return data


def esc(value: Any) -> str:
    if value is None:
        return ""
    return html.escape(str(value), quote=True)


def fmt_num(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        if value == int(value):
            return str(int(value))
        return f"{value:g}"
    return esc(value)


def fmt_list(items: list[Any] | None) -> str:
    if not items:
        return ""
    return ", ".join(esc(x) for x in items)


def fmt_prey_weights(weights: dict[str, float]) -> str:
    parts = [f"{key}={fmt_num(weights.get(key, 0.0))}" for key in PREY_KEYS]
    return ", ".join(parts)


def cell(text: str, css: str = "") -> str:
    cls = f' class="{css}"' if css else ""
    return f"<td{cls}>{text}</td>"


def th(text: str) -> str:
    return f"<th>{esc(text)}</th>"


def build_html(
    attacks: dict[str, dict[str, Any]],
    behaviours: dict[str, dict[str, Any]],
    templates: dict[str, dict[str, Any]],
    monsters: list[dict[str, Any]],
    merged_rows: list[dict[str, Any]],
) -> str:
    attack_ids = sorted(attacks.keys())
    behaviour_ids = sorted(behaviours.keys())
    template_ids = sorted(templates.keys())

    attack_rows_html: list[str] = []
    for aid in attack_ids:
        a = attacks[aid]
        cols = [cell(esc(aid), "id")]
        for key in ATTACK_CORE_COLS[1:]:
            cols.append(cell(fmt_num(a.get(key))))
        for key in ATTACK_EXTRA_COLS:
            cols.append(cell(fmt_num(a.get(key))))
        attack_rows_html.append("<tr>" + "".join(cols) + "</tr>")

    behaviour_rows_html: list[str] = []
    for bid in behaviour_ids:
        b = behaviours[bid]
        weights = b.get("prey_weights", {})
        if not isinstance(weights, dict):
            weights = {}
        cols = [
            cell(esc(bid), "id"),
            cell(esc(b.get("intent", "")), "wrap"),
            cell(fmt_list(b.get("attacks") or []), "wrap list"),
        ]
        for key in PREY_KEYS:
            cols.append(cell(fmt_num(weights.get(key, 0.0))))
        behaviour_rows_html.append("<tr>" + "".join(cols) + "</tr>")

    template_rows_html: list[str] = []
    for tid in template_ids:
        t = templates[tid]
        cols = [
            cell(esc(tid), "id"),
            cell(esc(t.get("intent", "")), "wrap"),
        ]
        for key in SCALAR_KEYS:
            cols.append(cell(fmt_num(t.get(key))))
        for key in LIST_KEYS:
            cols.append(cell(fmt_list(t.get(key) or []), "wrap list"))
        template_rows_html.append("<tr>" + "".join(cols) + "</tr>")

    monster_rows_html: list[str] = []
    for row in merged_rows:
        body = row["body"]
        eff = row["effective"]
        cols = [
            cell(esc(body["id"]), "id"),
            cell(fmt_list(body.get("templates") or []), "wrap list"),
            cell(fmt_list(eff.get("behaviour") or []), "wrap list"),
        ]
        for key in SCALAR_KEYS:
            cols.append(cell(fmt_num(eff["scalars"].get(key))))
        cols.append(cell(fmt_prey_weights(eff["prey_weights"]), "wrap list"))
        cols.append(cell(fmt_list(eff.get("attacks") or []), "wrap list"))
        for key in LIST_KEYS:
            if key in ("behaviour", "attacks"):
                continue
            cols.append(cell(fmt_list(eff["lists"].get(key) or []), "wrap list"))
        spawn = body.get("spawn_ready")
        if spawn is None:
            spawn_txt = ""
        else:
            spawn_txt = "true" if spawn else "false"
        cols.append(cell(spawn_txt))
        weight = body.get("spawn_weight")
        cols.append(cell(fmt_num(weight) if weight is not None else ""))
        notes = body.get("notes")
        cols.append(cell(esc(notes) if notes else "", "wrap"))
        monster_rows_html.append("<tr>" + "".join(cols) + "</tr>")

    attack_header = "".join(th(c) for c in ATTACK_CORE_COLS + ATTACK_EXTRA_COLS)
    behaviour_header = "".join(
        th(c) for c in ("id", "intent", "attacks") + PREY_KEYS
    )
    template_header = "".join(
        th(c) for c in ("id", "intent") + SCALAR_KEYS + LIST_KEYS
    )
    monster_header = "".join(
        th(c)
        for c in (
            ("id", "templates", "behaviour")
            + SCALAR_KEYS
            + ("prey_weights (avg)", "attacks (derived)")
            + tuple(k for k in LIST_KEYS if k not in ("behaviour", "attacks"))
            + ("spawn_ready", "spawn_weight", "notes")
        )
    )

    css = """
:root {
  --bg: #f6f4ef;
  --fg: #1a1a1a;
  --muted: #5a564e;
  --line: #c9c2b4;
  --head: #ebe6dc;
  --accent: #2c4a3e;
  --row-alt: #f0ebe3;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 1.25rem 1.5rem 3rem;
  font: 14px/1.45 "Segoe UI", Tahoma, sans-serif;
  color: var(--fg);
  background: var(--bg);
}
h1 {
  margin: 0 0 0.25rem;
  font-size: 1.6rem;
  color: var(--accent);
}
h2 {
  margin: 2rem 0 0.6rem;
  font-size: 1.2rem;
  border-bottom: 2px solid var(--accent);
  padding-bottom: 0.25rem;
}
.meta {
  color: var(--muted);
  margin-bottom: 1rem;
}
.meta code { font-family: Consolas, "Courier New", monospace; }
.toc a {
  color: var(--accent);
  margin-right: 1rem;
}
.table-wrap {
  overflow-x: auto;
  border: 1px solid var(--line);
  border-radius: 4px;
  background: #fff;
}
table {
  border-collapse: collapse;
  width: 100%;
  min-width: 720px;
}
th, td {
  border-bottom: 1px solid var(--line);
  padding: 0.4rem 0.55rem;
  text-align: left;
  vertical-align: top;
}
thead th {
  position: sticky;
  top: 0;
  background: var(--head);
  z-index: 1;
  font-weight: 600;
  white-space: nowrap;
}
tbody tr:nth-child(even) { background: var(--row-alt); }
td.id, th:first-child {
  font-family: Consolas, "Courier New", monospace;
  white-space: nowrap;
}
td.wrap { max-width: 28rem; white-space: normal; word-break: break-word; }
td.list { font-family: Consolas, "Courier New", monospace; font-size: 12px; }
.count { font-weight: 600; color: var(--accent); }
"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Combat Tables Report</title>
<style>{css}</style>
</head>
<body>
<h1>Combat Tables Report</h1>
<p class="meta">
  Generated from
  <code>assets/combat/attacks.json</code>,
  <code>assets/combat/behaviours.json</code>, and
  <code>assets/monsters/combat_table.json</code>.
  Prey lives on behaviours (averaged per mob). Attacks prefer behaviour pools.
  Scalars: <strong>max</strong> across templates. Prey weights: <strong>mean</strong>
  across behaviours (missing key = 0).
</p>
<p class="meta toc">
  <a href="#attacks">Attacks (<span class="count">{len(attack_ids)}</span>)</a>
  <a href="#behaviours">Behaviours (<span class="count">{len(behaviour_ids)}</span>)</a>
  <a href="#templates">Templates (<span class="count">{len(template_ids)}</span>)</a>
  <a href="#monsters">Monsters (<span class="count">{len(monsters)}</span>)</a>
</p>

<h2 id="attacks">Attacks</h2>
<div class="table-wrap">
<table>
<thead><tr>{attack_header}</tr></thead>
<tbody>
{"".join(attack_rows_html)}
</tbody>
</table>
</div>

<h2 id="behaviours">Behaviours</h2>
<div class="table-wrap">
<table>
<thead><tr>{behaviour_header}</tr></thead>
<tbody>
{"".join(behaviour_rows_html)}
</tbody>
</table>
</div>

<h2 id="templates">Templates</h2>
<div class="table-wrap">
<table>
<thead><tr>{template_header}</tr></thead>
<tbody>
{"".join(template_rows_html)}
</tbody>
</table>
</div>

<h2 id="monsters">Monsters (effective merged stats)</h2>
<div class="table-wrap">
<table>
<thead><tr>{monster_header}</tr></thead>
<tbody>
{"".join(monster_rows_html)}
</tbody>
</table>
</div>
</body>
</html>
"""


def open_in_browser(path: Path) -> None:
    abs_path = str(path.resolve())
    if sys.platform == "win32":
        try:
            os.startfile(abs_path)  # type: ignore[attr-defined]
            return
        except OSError:
            pass
    webbrowser.open(path.resolve().as_uri())


def main() -> int:
    attacks_doc = load_json(ATTACKS_PATH)
    behaviours_doc = load_json(BEHAVIOURS_PATH)
    combat_doc = load_json(COMBAT_TABLE_PATH)

    if "attacks" not in attacks_doc or not isinstance(attacks_doc["attacks"], dict):
        raise ValueError(f"{ATTACKS_PATH}: missing object key 'attacks'")
    if "behaviours" not in behaviours_doc or not isinstance(
        behaviours_doc["behaviours"], dict
    ):
        raise ValueError(f"{BEHAVIOURS_PATH}: missing object key 'behaviours'")
    if "templates" not in combat_doc or not isinstance(combat_doc["templates"], dict):
        raise ValueError(f"{COMBAT_TABLE_PATH}: missing object key 'templates'")
    if "monsters" not in combat_doc or not isinstance(combat_doc["monsters"], list):
        raise ValueError(f"{COMBAT_TABLE_PATH}: missing list key 'monsters'")

    attacks: dict[str, dict[str, Any]] = attacks_doc["attacks"]
    behaviours: dict[str, dict[str, Any]] = behaviours_doc["behaviours"]
    templates: dict[str, dict[str, Any]] = combat_doc["templates"]
    monsters: list[dict[str, Any]] = combat_doc["monsters"]

    for aid, row in attacks.items():
        if not isinstance(row, dict):
            raise TypeError(f"Attack {aid!r} must be an object")
        for req in ATTACK_CORE_COLS:
            if req not in row:
                raise KeyError(f"Attack {aid!r} missing required field {req!r}")

    merged_rows: list[dict[str, Any]] = []
    for body in monsters:
        if not isinstance(body, dict):
            raise TypeError("Each monster row must be an object")
        if "id" not in body:
            raise KeyError("Monster row missing 'id'")
        tids = body.get("templates")
        if not isinstance(tids, list) or not tids:
            raise ValueError(f"Monster {body['id']!r} needs a non-empty templates list")
        effective = validate_mod.effective_monster_combat(
            tids, templates, body, behaviours
        )
        for aid in effective["attacks"]:
            if aid not in attacks:
                raise KeyError(
                    f"Monster {body['id']!r} derived unknown attack id {aid!r}"
                )
        merged_rows.append({"body": body, "effective": effective})

    html_text = build_html(attacks, behaviours, templates, monsters, merged_rows)
    OUT_PATH.write_text(html_text, encoding="utf-8")
    print(OUT_PATH.resolve())
    open_in_browser(OUT_PATH)
    print(
        f"rows: attacks={len(attacks)} behaviours={len(behaviours)} "
        f"templates={len(templates)} monsters={len(monsters)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, KeyError, TypeError, OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
