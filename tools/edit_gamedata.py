#!/usr/bin/env python3
"""Windowed tkinter editor for assets/gamedata.json.

Edits every authored section: combat (attacks / behaviours / templates / monsters),
items, craft/build recipes, district gems, abilities + constants, chest loot,
recipe sites, Monster Zoo / crypt spawn tuning, and Mandelbrot spots.

Combat validation uses tools/validate_combat_tables.py. Non-combat tabs use light
schema checks in this module. The Monsters tab shows live EFFECTIVE STATS from
combat_resolve (same rules as scripts/city/combat_table.gd) and can run open-field
1v1 duels via simulate_monster_duels (vs all / vs same tier). After combat changes,
regenerate the sync golden with: python tools/sync_combat_resolve.py --write

Run from repo root:
  python tools/edit_gamedata.py
  python tools/edit_gamedata.py --smoke
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk
from collections.abc import Callable
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import gamedata_io as gd  # noqa: E402
import gamedata_editor_panels as panels  # noqa: E402
import simulate_monster_duels as duel_sim  # noqa: E402
import validate_combat_tables as validate_mod  # noqa: E402

GAMEDATA_PATH = gd.GAMEDATA_PATH
ATTACKS_PATH = GAMEDATA_PATH
BEHAVIOURS_PATH = GAMEDATA_PATH
TABLE_PATH = GAMEDATA_PATH
HTML_PATH = TOOLS / "combat_tables.html"
RENDER_SCRIPT = TOOLS / "render_combat_tables.py"

SCALAR_KEYS = validate_mod.SCALAR_KEYS
LIST_KEYS = validate_mod.LIST_KEYS  # behaviour, attacks, tags, crowd_roles
LIST_EXTRA_KEYS = validate_mod.LIST_EXTRA_KEYS
KNOWN_ATTACK_KINDS = sorted(validate_mod.KNOWN_ATTACK_KINDS)
ALLOWED_BEHAVIOUR = sorted(validate_mod.ALLOWED_BEHAVIOUR)

ATTACK_REQUIRED_NUMS = (
    "damage_vs_player",
    "damage_vs_mob",
    "cooldown_s",
    "energy_cost",
    "range_m",
)
ATTACK_OPTIONAL_NUMS = (
    "speed_mps",
    "windup_s",
    "fire_interval_s",
    "radius_m",
    "monster_cooldown_s",
    "monster_range_m",
    "monster_windup_s",
    "monster_fire_interval_s",
)
ATTACK_OPTIONAL_INTS = (
    "burst_count",
    "monster_burst_count",
)

ATTACK_FIELD_ORDER = (
    "id",
    "kind",
    *ATTACK_REQUIRED_NUMS,
    *ATTACK_OPTIONAL_NUMS,
    *ATTACK_OPTIONAL_INTS,
    "carves_voxels",
    "damage_source",
    "notes",
)

BEHAVIOUR_FIELD_ORDER = (
    "id",
    "intent",
    "attacks",
    "notes",
)

TEMPLATE_FIELD_ORDER = (
    "intent",
    *SCALAR_KEYS,
    *LIST_KEYS,
)

ALLOWED_FACTIONS = tuple(sorted(validate_mod.ALLOWED_FACTIONS))

MONSTER_CORE_ORDER = (
    "id",
    "faction",
    "templates",
    "spawn_ready",
    "spawn_weight",
    *SCALAR_KEYS,
    *LIST_KEYS,
    *LIST_EXTRA_KEYS,
    "notes",
)


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required JSON: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError(f"Expected object at root of {path}, got {type(data).__name__}")
    return data


def _dump_json(path: Path, data: dict[str, Any]) -> None:
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")


def _reorder_keys(obj: dict[str, Any], preferred: tuple[str, ...]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key in preferred:
        if key in obj:
            out[key] = obj[key]
    for key, value in obj.items():
        if key not in out:
            out[key] = value
    return out


def _parse_optional_float(raw: str, field: str) -> float | None:
    text = raw.strip()
    if text == "":
        return None
    try:
        return float(text)
    except ValueError as exc:
        raise ValueError(f"{field}: expected a number, got {raw!r}") from exc


def _parse_required_float(raw: str, field: str) -> float:
    value = _parse_optional_float(raw, field)
    if value is None:
        raise ValueError(f"{field}: required number is empty")
    return value


def _parse_optional_int(raw: str, field: str) -> int | None:
    text = raw.strip()
    if text == "":
        return None
    try:
        value = int(text, 10)
    except ValueError as exc:
        raise ValueError(f"{field}: expected an integer, got {raw!r}") from exc
    return value


def _behaviours_map(doc: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = doc.get("behaviours", {})
    if not isinstance(raw, dict):
        return {}
    return {k: v for k, v in raw.items() if isinstance(k, str) and isinstance(v, dict)}


def _enum_options(
    attacks_doc: dict[str, Any],
    behaviours_doc: dict[str, Any],
) -> dict[str, list[str]]:
    """Checklist options from validator constants + keys present in live tables."""
    attacks = attacks_doc.get("attacks", {})
    attack_ids = sorted(attacks.keys()) if isinstance(attacks, dict) else []
    behaviour_ids = sorted(_behaviours_map(behaviours_doc).keys())
    return {
        "behaviour": sorted(set(ALLOWED_BEHAVIOUR) | set(behaviour_ids)),
        "crowd_roles": sorted(validate_mod.ALLOWED_CROWD_ROLES),
        "attacks": attack_ids,
        "kind": list(KNOWN_ATTACK_KINDS),
    }


class Checklist(ttk.Frame):
    """Scrollable checklist of string options."""

    def __init__(
        self,
        master: tk.Misc,
        options: list[str] | None = None,
        height: int = 8,
    ) -> None:
        super().__init__(master)
        self._vars: dict[str, tk.BooleanVar] = {}
        self._change_callback: Callable[..., None] | None = None
        self._trace_ids: list[tuple[tk.BooleanVar, str]] = []
        self._canvas = tk.Canvas(self, borderwidth=0, highlightthickness=0, height=height * 22)
        self._inner = ttk.Frame(self._canvas)
        self._scroll = ttk.Scrollbar(self, orient="vertical", command=self._canvas.yview)
        self._canvas.configure(yscrollcommand=self._scroll.set)
        self._scroll.pack(side="right", fill="y")
        self._canvas.pack(side="left", fill="both", expand=True)
        self._window = self._canvas.create_window((0, 0), window=self._inner, anchor="nw")
        self._inner.bind(
            "<Configure>",
            lambda _e: self._canvas.configure(scrollregion=self._canvas.bbox("all")),
        )
        self._canvas.bind(
            "<Configure>",
            lambda e: self._canvas.itemconfigure(self._window, width=e.width),
        )
        if options:
            self.set_options(options)

    def set_change_callback(self, callback: Callable[..., None] | None) -> None:
        """Idempotent: (re)wire write traces on current and future option vars."""
        self._change_callback = callback
        self._rewire_change_traces()

    def _clear_change_traces(self) -> None:
        for var, tid in self._trace_ids:
            try:
                var.trace_remove("write", tid)
            except tk.TclError:
                pass
        self._trace_ids.clear()

    def _rewire_change_traces(self) -> None:
        self._clear_change_traces()
        if self._change_callback is None:
            return
        for var in self._vars.values():
            tid = var.trace_add("write", self._change_callback)
            self._trace_ids.append((var, tid))

    def set_options(self, options: list[str]) -> None:
        selected = set(self.get_selected())
        self._clear_change_traces()
        for child in self._inner.winfo_children():
            child.destroy()
        self._vars.clear()
        for opt in options:
            var = tk.BooleanVar(value=opt in selected)
            self._vars[opt] = var
            ttk.Checkbutton(self._inner, text=opt, variable=var).pack(anchor="w")
        self._rewire_change_traces()

    def get_selected(self) -> list[str]:
        return [name for name, var in self._vars.items() if var.get()]

    def set_selected(self, values: list[str]) -> None:
        wanted = set(values)
        for name, var in self._vars.items():
            var.set(name in wanted)
        missing = [v for v in values if v not in self._vars]
        if missing:
            opts = list(self._vars.keys()) + missing
            self.set_options(opts)
            for name, var in self._vars.items():
                var.set(name in wanted)

    def clear(self) -> None:
        for var in self._vars.values():
            var.set(False)


class GameDataEditor(tk.Tk):
    """Windowed editor for every section of assets/gamedata.json."""

    def __init__(self) -> None:
        super().__init__()
        self.title("Game Data Editor")
        self.geometry("1280x860")
        self.minsize(960, 680)

        self.attacks_doc: dict[str, Any] = {}
        self.behaviours_doc: dict[str, Any] = {}
        self.table_doc: dict[str, Any] = {}
        self._gamedata_root: dict[str, Any] = {}
        self._dirty = False
        self._loading = False
        self._selected_attack: str | None = None
        self._selected_behaviour: str | None = None
        self._selected_template: str | None = None
        self._selected_monster: str | None = None

        self._attack_entries: dict[str, tk.Variable | tk.Text] = {}
        self._behaviour_intent = tk.StringVar()
        self._behaviour_notes: tk.Text | None = None
        self._behaviour_attacks: Checklist | None = None
        self._template_scalar_entries: dict[str, tk.StringVar] = {}
        self._template_intent = tk.StringVar()
        self._template_checklists: dict[str, Checklist] = {}
        self._monster_template_check: Checklist | None = None
        self._monster_faction = tk.StringVar(value=ALLOWED_FACTIONS[0])
        self._monster_spawn_ready = tk.BooleanVar(value=False)
        self._monster_spawn_weight = tk.StringVar()
        self._monster_notes: tk.Text | None = None
        self._monster_scalar_vars: dict[str, tk.StringVar] = {}
        self._monster_list_modes: dict[str, tk.StringVar] = {}
        self._monster_list_checks: dict[str, Checklist] = {}
        self._monster_preview: tk.Text | None = None
        self._monster_form_canvas: tk.Canvas | None = None
        self._monster_paned: ttk.Panedwindow | None = None
        self._monster_preview_wrap: ttk.Frame | None = None
        self._monster_preview_expanded = False
        self._monster_preview_toggle_btn: ttk.Button | None = None
        self._status = tk.StringVar(value="Ready")

        self._items_panel: panels.IdMapPanel | None = None
        self._craft_panel: panels.IdMapPanel | None = None
        self._build_panel: panels.IdMapPanel | None = None
        self._abilities_panel: panels.IdMapPanel | None = None
        self._district_panel: panels.NestedJsonPanel | None = None
        self._constants_panel: panels.NestedJsonPanel | None = None
        self._chest_panel: panels.NestedJsonPanel | None = None
        self._recipe_sites_panel: panels.NestedJsonPanel | None = None
        self._zoo_panel: panels.NestedJsonPanel | None = None
        self._crypt_panel: panels.NestedJsonPanel | None = None
        self._dungeon_summoner_panel: panels.NestedJsonPanel | None = None
        self._spots_panel: panels.SpotsPanel | None = None

        self._build_chrome()
        self._build_notebook()
        self.protocol("WM_DELETE_WINDOW", self._on_quit)
        self.reload_from_disk(confirm_dirty=False)

    # --- chrome ----------------------------------------------------------------

    def _build_chrome(self) -> None:
        bar = ttk.Frame(self, padding=6)
        bar.pack(side="top", fill="x")
        ttk.Button(bar, text="Save", command=self.save_to_disk).pack(side="left", padx=2)
        ttk.Button(bar, text="Reload", command=lambda: self.reload_from_disk(True)).pack(
            side="left", padx=2
        )
        ttk.Button(bar, text="Validate", command=self.validate_now).pack(side="left", padx=2)
        ttk.Button(bar, text="HTML report", command=self.open_html_report).pack(
            side="left", padx=2
        )
        ttk.Label(bar, textvariable=self._status).pack(side="right", padx=8)

    def _build_notebook(self) -> None:
        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=6, pady=6)
        self._nb = nb
        self._tab_attacks = ttk.Frame(nb)
        self._tab_behaviours = ttk.Frame(nb)
        self._tab_templates = ttk.Frame(nb)
        self._tab_monsters = ttk.Frame(nb)
        self._tab_items = ttk.Frame(nb)
        self._tab_craft = ttk.Frame(nb)
        self._tab_build = ttk.Frame(nb)
        self._tab_districts = ttk.Frame(nb)
        self._tab_abilities = ttk.Frame(nb)
        self._tab_constants = ttk.Frame(nb)
        self._tab_discovery = ttk.Frame(nb)
        self._tab_world = ttk.Frame(nb)
        self._tab_spots = ttk.Frame(nb)
        nb.add(self._tab_attacks, text="Attacks")
        nb.add(self._tab_behaviours, text="Behaviours")
        nb.add(self._tab_templates, text="Templates")
        nb.add(self._tab_monsters, text="Monsters")
        nb.add(self._tab_items, text="Items")
        nb.add(self._tab_craft, text="Craft")
        nb.add(self._tab_build, text="Build")
        nb.add(self._tab_districts, text="Districts")
        nb.add(self._tab_abilities, text="Abilities")
        nb.add(self._tab_constants, text="Constants")
        nb.add(self._tab_discovery, text="Discovery")
        nb.add(self._tab_world, text="World")
        nb.add(self._tab_spots, text="Spots")
        self._build_attacks_tab()
        self._build_behaviours_tab()
        self._build_templates_tab()
        self._build_monsters_tab()
        self._build_noncombat_tabs()
        nb.bind("<<NotebookTabChanged>>", self._on_tab_changed)

    def _build_noncombat_tabs(self) -> None:
        self._items_panel = panels.IdMapPanel(
            self._tab_items,
            title="Item ids",
            fields=panels.ITEM_FIELDS,
            on_dirty=self._mark_dirty,
            new_row_factory=lambda _id: {
                "display_name": _id,
                "stack_max": 99,
                "flags": [],
            },
        )
        self._craft_panel = panels.IdMapPanel(
            self._tab_craft,
            title="Craft recipe ids",
            fields=panels.CRAFT_FIELDS,
            on_dirty=self._mark_dirty,
            new_row_factory=lambda _id: {
                "display_name": _id,
                "inputs": {},
                "output_id": "",
                "output_count": 1,
            },
        )
        self._build_panel = panels.IdMapPanel(
            self._tab_build,
            title="Build recipe ids",
            fields=panels.BUILD_FIELDS,
            on_dirty=self._mark_dirty,
            new_row_factory=lambda _id: {
                "display_name": _id,
                "hint": "",
                "voxels": [],
            },
        )
        self._abilities_panel = panels.IdMapPanel(
            self._tab_abilities,
            title="Ability ids",
            fields=panels.ABILITY_FIELDS,
            on_dirty=self._mark_dirty,
            new_row_factory=lambda _id: {
                "display_name": _id,
                "kind": "utility",
                "unlock_cost": {},
                "energy_cost": 0.0,
                "gated": True,
                "hint": "",
            },
        )
        self._district_panel = panels.NestedJsonPanel(
            self._tab_districts,
            scalar_fields=panels.DISTRICT_SCALARS,
            json_fields=panels.DISTRICT_JSON,
            on_dirty=self._mark_dirty,
        )
        self._constants_panel = panels.NestedJsonPanel(
            self._tab_constants,
            scalar_fields=panels.CONSTANTS_SCALARS,
            json_fields=panels.CONSTANTS_JSON,
            on_dirty=self._mark_dirty,
        )

        discovery = ttk.Panedwindow(self._tab_discovery, orient="vertical")
        discovery.pack(fill="both", expand=True)
        chest_frame = ttk.LabelFrame(discovery, text="chest_loot", padding=4)
        sites_frame = ttk.LabelFrame(discovery, text="recipe_sites", padding=4)
        discovery.add(chest_frame, weight=1)
        discovery.add(sites_frame, weight=1)
        self._chest_panel = panels.NestedJsonPanel(
            chest_frame,
            scalar_fields=panels.CHEST_SCALARS,
            json_fields=panels.CHEST_JSON,
            on_dirty=self._mark_dirty,
        )
        self._recipe_sites_panel = panels.NestedJsonPanel(
            sites_frame,
            scalar_fields=panels.RECIPE_SITE_SCALARS,
            json_fields=panels.RECIPE_SITE_JSON,
            on_dirty=self._mark_dirty,
        )

        world = ttk.Panedwindow(self._tab_world, orient="vertical")
        world.pack(fill="both", expand=True)
        zoo_frame = ttk.LabelFrame(world, text="zoo (Monster Zoo forever-war)", padding=4)
        crypt_frame = ttk.LabelFrame(
            world, text="crypt (Graveyard chapel undead station)", padding=4
        )
        dungeon_frame = ttk.LabelFrame(
            world, text="dungeon_summoner (Castle dungeon pads)", padding=4
        )
        world.add(zoo_frame, weight=1)
        world.add(crypt_frame, weight=1)
        world.add(dungeon_frame, weight=1)
        self._zoo_panel = panels.NestedJsonPanel(
            zoo_frame,
            scalar_fields=panels.ZOO_SCALARS,
            json_fields=panels.ZOO_JSON,
            on_dirty=self._mark_dirty,
        )
        self._crypt_panel = panels.NestedJsonPanel(
            crypt_frame,
            scalar_fields=panels.CRYPT_SCALARS,
            json_fields=panels.CRYPT_JSON,
            on_dirty=self._mark_dirty,
        )
        self._dungeon_summoner_panel = panels.NestedJsonPanel(
            dungeon_frame,
            scalar_fields=panels.DUNGEON_SUMMONER_SCALARS,
            json_fields=panels.DUNGEON_SUMMONER_JSON,
            on_dirty=self._mark_dirty,
        )

        self._spots_panel = panels.SpotsPanel(self._tab_spots, on_dirty=self._mark_dirty)

    def _mark_dirty(self, *_args: object) -> None:
        if self._loading:
            return
        self._dirty = True
        self._status.set("Modified — unsaved changes")

    def _set_clean(self) -> None:
        self._dirty = False
        self._status.set("Loaded from disk")

    def _wire_checklist_dirty(self, check: Checklist) -> None:
        check.set_change_callback(self._mark_dirty)

    def _wire_checklist_monster_preview(self, check: Checklist) -> None:
        # Marks dirty and rebuilds EFFECTIVE STATS from the live form draft.
        check.set_change_callback(self._on_monster_field_change)

    # --- Attacks tab -----------------------------------------------------------

    def _build_attacks_tab(self) -> None:
        paned = ttk.Panedwindow(self._tab_attacks, orient="horizontal")
        paned.pack(fill="both", expand=True)

        left = ttk.Frame(paned, padding=4)
        right = ttk.Frame(paned, padding=4)
        paned.add(left, weight=1)
        paned.add(right, weight=3)

        ttk.Label(left, text="Attack ids").pack(anchor="w")
        self._attack_list = tk.Listbox(left, exportselection=False)
        self._attack_list.pack(fill="both", expand=True)
        self._attack_list.bind("<<ListboxSelect>>", self._on_attack_select)
        btns = ttk.Frame(left)
        btns.pack(fill="x", pady=4)
        ttk.Button(btns, text="Add", command=self._add_attack).pack(side="left", padx=2)
        ttk.Button(btns, text="Delete", command=self._delete_attack).pack(side="left", padx=2)

        form = ttk.Frame(right)
        form.pack(fill="both", expand=True)
        form.columnconfigure(1, weight=1)

        row = 0
        id_var = tk.StringVar()
        kind_var = tk.StringVar()
        self._attack_entries["id"] = id_var
        self._attack_entries["kind"] = kind_var
        ttk.Label(form, text="id").grid(row=row, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=id_var).grid(row=row, column=1, sticky="ew", pady=2)
        id_var.trace_add("write", self._mark_dirty)
        row += 1

        ttk.Label(form, text="kind").grid(row=row, column=0, sticky="w", pady=2)
        ttk.Combobox(
            form, textvariable=kind_var, values=KNOWN_ATTACK_KINDS, state="readonly"
        ).grid(row=row, column=1, sticky="ew", pady=2)
        kind_var.trace_add("write", self._mark_dirty)
        row += 1

        for key in ATTACK_REQUIRED_NUMS + ATTACK_OPTIONAL_NUMS + ATTACK_OPTIONAL_INTS:
            var = tk.StringVar()
            self._attack_entries[key] = var
            ttk.Label(form, text=key).grid(row=row, column=0, sticky="w", pady=2)
            ttk.Entry(form, textvariable=var).grid(row=row, column=1, sticky="ew", pady=2)
            var.trace_add("write", self._mark_dirty)
            row += 1

        carve_var = tk.StringVar(value="")
        self._attack_entries["carves_voxels"] = carve_var
        ttk.Label(form, text="carves_voxels").grid(row=row, column=0, sticky="w", pady=2)
        ttk.Combobox(
            form,
            textvariable=carve_var,
            values=("", "true", "false"),
            state="readonly",
            width=12,
        ).grid(row=row, column=1, sticky="w", pady=2)
        carve_var.trace_add("write", self._mark_dirty)
        row += 1

        ds_var = tk.StringVar()
        self._attack_entries["damage_source"] = ds_var
        ttk.Label(form, text="damage_source").grid(row=row, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=ds_var).grid(row=row, column=1, sticky="ew", pady=2)
        ds_var.trace_add("write", self._mark_dirty)
        row += 1

        ttk.Label(form, text="notes").grid(row=row, column=0, sticky="nw", pady=2)
        notes = tk.Text(form, height=8, wrap="word")
        notes.grid(row=row, column=1, sticky="nsew", pady=2)
        notes.bind("<<Modified>>", self._on_attack_notes_modified)
        self._attack_entries["notes"] = notes
        form.rowconfigure(row, weight=1)

    def _on_attack_notes_modified(self, _event: object | None = None) -> None:
        notes = self._attack_entries["notes"]
        assert isinstance(notes, tk.Text)
        if notes.edit_modified():
            self._mark_dirty()
            notes.edit_modified(False)

    def _refresh_attack_list(self, select: str | None = None) -> None:
        attacks = self.attacks_doc.get("attacks", {})
        assert isinstance(attacks, dict)
        ids = sorted(attacks.keys())
        self._attack_list.delete(0, "end")
        for aid in ids:
            self._attack_list.insert("end", aid)
        target = select if select in ids else (ids[0] if ids else None)
        if target is None:
            self._selected_attack = None
            return
        idx = ids.index(target)
        self._attack_list.selection_clear(0, "end")
        self._attack_list.selection_set(idx)
        self._attack_list.see(idx)
        self._load_attack_form(target)

    def _on_attack_select(self, _event: object | None = None) -> None:
        sel = self._attack_list.curselection()
        if not sel:
            return
        new_id = self._attack_list.get(sel[0])
        if new_id == self._selected_attack:
            return
        try:
            self._flush_attack_form()
        except ValueError as exc:
            messagebox.showerror("Invalid attack fields", str(exc), parent=self)
            self._refresh_attack_list(self._selected_attack)
            return
        self._load_attack_form(new_id)

    def _load_attack_form(self, aid: str) -> None:
        attacks = self.attacks_doc["attacks"]
        assert isinstance(attacks, dict)
        atk = attacks[aid]
        if not isinstance(atk, dict):
            raise TypeError(f"Attack {aid!r} must be an object")
        self._loading = True
        self._selected_attack = aid
        try:
            for key, widget in self._attack_entries.items():
                if key == "notes":
                    assert isinstance(widget, tk.Text)
                    widget.delete("1.0", "end")
                    widget.insert("1.0", str(atk.get("notes", "")))
                    widget.edit_modified(False)
                    continue
                assert isinstance(widget, (tk.StringVar, tk.Variable))
                if key == "carves_voxels":
                    if "carves_voxels" not in atk:
                        widget.set("")
                    else:
                        widget.set("true" if atk["carves_voxels"] else "false")
                elif key == "damage_source":
                    ds = atk.get("damage_source", "")
                    widget.set("" if ds is None else str(ds))
                elif key in atk:
                    widget.set(str(atk[key]))
                else:
                    widget.set("")
        finally:
            self._loading = False

    def _flush_attack_form(self) -> None:
        if self._selected_attack is None:
            return
        attacks = self.attacks_doc["attacks"]
        assert isinstance(attacks, dict)
        old_id = self._selected_attack
        if old_id not in attacks:
            return
        existing = attacks[old_id]
        assert isinstance(existing, dict)
        row = copy.deepcopy(existing)

        id_var = self._attack_entries["id"]
        kind_var = self._attack_entries["kind"]
        assert isinstance(id_var, tk.StringVar)
        assert isinstance(kind_var, tk.StringVar)
        new_id = id_var.get().strip()
        if not new_id:
            raise ValueError("Attack id must be non-empty")
        kind = kind_var.get().strip()
        if kind not in KNOWN_ATTACK_KINDS:
            raise ValueError(f"kind must be one of {KNOWN_ATTACK_KINDS}")

        row["id"] = new_id
        row["kind"] = kind
        for key in ATTACK_REQUIRED_NUMS:
            var = self._attack_entries[key]
            assert isinstance(var, tk.StringVar)
            row[key] = _parse_required_float(var.get(), key)
        for key in ATTACK_OPTIONAL_NUMS:
            var = self._attack_entries[key]
            assert isinstance(var, tk.StringVar)
            value = _parse_optional_float(var.get(), key)
            if value is None:
                row.pop(key, None)
            else:
                row[key] = value
        for key in ATTACK_OPTIONAL_INTS:
            var = self._attack_entries[key]
            assert isinstance(var, tk.StringVar)
            value = _parse_optional_int(var.get(), key)
            if value is None:
                row.pop(key, None)
            else:
                row[key] = value

        carve = self._attack_entries["carves_voxels"]
        assert isinstance(carve, tk.StringVar)
        carve_raw = carve.get()
        if carve_raw == "":
            row.pop("carves_voxels", None)
        else:
            row["carves_voxels"] = carve_raw == "true"

        ds_var = self._attack_entries["damage_source"]
        assert isinstance(ds_var, tk.StringVar)
        ds_raw = ds_var.get().strip()
        if ds_raw == "":
            row["damage_source"] = None
        else:
            row["damage_source"] = ds_raw

        notes_w = self._attack_entries["notes"]
        assert isinstance(notes_w, tk.Text)
        notes = notes_w.get("1.0", "end-1c")
        if notes.strip() == "":
            row.pop("notes", None)
        else:
            row["notes"] = notes

        ordered = _reorder_keys(row, ATTACK_FIELD_ORDER)
        if new_id != old_id:
            if new_id in attacks:
                raise ValueError(f"Attack id {new_id!r} already exists")
            del attacks[old_id]
            self._selected_attack = new_id
            self._rewrite_attack_refs(old_id, new_id)
        attacks[new_id] = ordered
        if new_id != old_id:
            self._refresh_attack_list(new_id)
            self._refresh_behaviour_attack_options()
            self._refresh_template_list_options()
            self._refresh_monster_list_options()

    def _rewrite_attack_refs(self, old_id: str, new_id: str) -> None:
        for row in _behaviours_map(self.behaviours_doc).values():
            vals = row.get("attacks")
            if isinstance(vals, list):
                row["attacks"] = [new_id if x == old_id else x for x in vals]
        templates = self.table_doc.get("templates", {})
        assert isinstance(templates, dict)
        for tmpl in templates.values():
            if not isinstance(tmpl, dict):
                continue
            vals = tmpl.get("attacks")
            if isinstance(vals, list):
                tmpl["attacks"] = [new_id if x == old_id else x for x in vals]
        monsters = self.table_doc.get("monsters", [])
        assert isinstance(monsters, list)
        for mon in monsters:
            if not isinstance(mon, dict):
                continue
            for key in ("attacks", "attacks_extra"):
                vals = mon.get(key)
                if isinstance(vals, list):
                    mon[key] = [new_id if x == old_id else x for x in vals]

    def _add_attack(self) -> None:
        try:
            self._flush_attack_form()
        except ValueError as exc:
            messagebox.showerror("Invalid attack fields", str(exc), parent=self)
            return
        attacks = self.attacks_doc["attacks"]
        assert isinstance(attacks, dict)
        base = "new_attack"
        name = base
        n = 2
        while name in attacks:
            name = f"{base}_{n}"
            n += 1
        attacks[name] = {
            "id": name,
            "kind": "melee",
            "damage_vs_player": 0.0,
            "damage_vs_mob": 0.0,
            "cooldown_s": 1.0,
            "energy_cost": 0.0,
            "range_m": 1.0,
            "carves_voxels": False,
            "damage_source": None,
            "notes": "",
        }
        self._mark_dirty()
        self._refresh_attack_list(name)
        self._refresh_behaviour_attack_options()
        self._refresh_template_list_options()
        self._refresh_monster_list_options()

    def _delete_attack(self) -> None:
        if self._selected_attack is None:
            return
        aid = self._selected_attack
        if not messagebox.askyesno(
            "Delete attack",
            f"Delete attack {aid!r}? References in behaviours/templates/monsters "
            "will break until updated.",
            parent=self,
        ):
            return
        attacks = self.attacks_doc["attacks"]
        assert isinstance(attacks, dict)
        del attacks[aid]
        self._selected_attack = None
        self._mark_dirty()
        self._refresh_attack_list()
        self._refresh_behaviour_attack_options()
        self._refresh_template_list_options()
        self._refresh_monster_list_options()

    # --- Behaviours tab --------------------------------------------------------

    def _build_behaviours_tab(self) -> None:
        paned = ttk.Panedwindow(self._tab_behaviours, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=4)
        right = ttk.Frame(paned, padding=4)
        paned.add(left, weight=1)
        paned.add(right, weight=3)

        ttk.Label(left, text="Behaviour ids").pack(anchor="w")
        self._behaviour_list = tk.Listbox(left, exportselection=False)
        self._behaviour_list.pack(fill="both", expand=True)
        self._behaviour_list.bind("<<ListboxSelect>>", self._on_behaviour_select)
        btns = ttk.Frame(left)
        btns.pack(fill="x", pady=4)
        ttk.Button(btns, text="Add", command=self._add_behaviour).pack(side="left", padx=2)
        ttk.Button(btns, text="Delete", command=self._delete_behaviour).pack(
            side="left", padx=2
        )

        form = ttk.Frame(right)
        form.pack(fill="both", expand=True)
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="id (rename)").grid(row=0, column=0, sticky="w", pady=2)
        self._behaviour_id_var = tk.StringVar()
        ttk.Entry(form, textvariable=self._behaviour_id_var).grid(
            row=0, column=1, sticky="ew", pady=2
        )
        self._behaviour_id_var.trace_add("write", self._mark_dirty)

        ttk.Label(form, text="intent").grid(row=1, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=self._behaviour_intent).grid(
            row=1, column=1, sticky="ew", pady=2
        )
        self._behaviour_intent.trace_add("write", self._mark_dirty)

        ttk.Label(form, text="attacks").grid(row=2, column=0, sticky="nw", pady=4)
        self._behaviour_attacks = Checklist(form, height=12)
        self._behaviour_attacks.grid(row=2, column=1, sticky="nsew", pady=4)

        ttk.Label(form, text="notes").grid(row=4, column=0, sticky="nw", pady=2)
        self._behaviour_notes = tk.Text(form, height=5, wrap="word")
        self._behaviour_notes.grid(row=4, column=1, sticky="nsew", pady=2)
        self._behaviour_notes.bind("<<Modified>>", self._on_behaviour_notes_modified)
        form.rowconfigure(2, weight=1)
        form.rowconfigure(4, weight=1)

    def _on_behaviour_notes_modified(self, _event: object | None = None) -> None:
        assert self._behaviour_notes is not None
        if self._behaviour_notes.edit_modified():
            self._mark_dirty()
            self._behaviour_notes.edit_modified(False)

    def _refresh_behaviour_list(self, select: str | None = None) -> None:
        behaviours = _behaviours_map(self.behaviours_doc)
        ids = sorted(behaviours.keys())
        self._behaviour_list.delete(0, "end")
        for bid in ids:
            self._behaviour_list.insert("end", bid)
        target = select if select in ids else (ids[0] if ids else None)
        if target is None:
            self._selected_behaviour = None
            return
        idx = ids.index(target)
        self._behaviour_list.selection_clear(0, "end")
        self._behaviour_list.selection_set(idx)
        self._behaviour_list.see(idx)
        self._load_behaviour_form(target)

    def _refresh_behaviour_attack_options(self) -> None:
        assert self._behaviour_attacks is not None
        enums = _enum_options(self.attacks_doc, self.behaviours_doc)
        selected = self._behaviour_attacks.get_selected()
        self._behaviour_attacks.set_options(enums["attacks"])
        self._behaviour_attacks.set_selected(selected)
        self._wire_checklist_dirty(self._behaviour_attacks)

    def _on_behaviour_select(self, _event: object | None = None) -> None:
        sel = self._behaviour_list.curselection()
        if not sel:
            return
        new_id = self._behaviour_list.get(sel[0])
        if new_id == self._selected_behaviour:
            return
        try:
            self._flush_behaviour_form()
        except ValueError as exc:
            messagebox.showerror("Invalid behaviour fields", str(exc), parent=self)
            self._refresh_behaviour_list(self._selected_behaviour)
            return
        self._load_behaviour_form(new_id)

    def _load_behaviour_form(self, bid: str) -> None:
        behaviours = _behaviours_map(self.behaviours_doc)
        row = behaviours[bid]
        self._loading = True
        self._selected_behaviour = bid
        try:
            self._behaviour_id_var.set(bid)
            self._behaviour_intent.set(str(row.get("intent", "")))
            assert self._behaviour_attacks is not None
            attacks = row.get("attacks", [])
            if not isinstance(attacks, list):
                attacks = []
            self._behaviour_attacks.set_selected(
                [a for a in attacks if isinstance(a, str)]
            )
            self._wire_checklist_dirty(self._behaviour_attacks)
            assert self._behaviour_notes is not None
            self._behaviour_notes.delete("1.0", "end")
            self._behaviour_notes.insert("1.0", str(row.get("notes", "")))
            self._behaviour_notes.edit_modified(False)
        finally:
            self._loading = False

    def _flush_behaviour_form(self) -> None:
        if self._selected_behaviour is None:
            return
        behaviours = self.behaviours_doc.setdefault("behaviours", {})
        if not isinstance(behaviours, dict):
            raise TypeError("behaviours_doc.behaviours must be an object")
        old_id = self._selected_behaviour
        if old_id not in behaviours:
            return
        existing = behaviours[old_id]
        assert isinstance(existing, dict)
        row = copy.deepcopy(existing)
        new_id = self._behaviour_id_var.get().strip()
        if not new_id:
            raise ValueError("Behaviour id must be non-empty")
        row["id"] = new_id
        intent = self._behaviour_intent.get().strip()
        if intent:
            row["intent"] = intent
        else:
            row.pop("intent", None)
        assert self._behaviour_attacks is not None
        row["attacks"] = self._behaviour_attacks.get_selected()
        for forbidden in validate_mod.FORBIDDEN_PREY_KEYS:
            row.pop(forbidden, None)
        assert self._behaviour_notes is not None
        notes = self._behaviour_notes.get("1.0", "end-1c")
        if notes.strip() == "":
            row.pop("notes", None)
        else:
            row["notes"] = notes
        ordered = _reorder_keys(row, BEHAVIOUR_FIELD_ORDER)
        if new_id != old_id:
            if new_id in behaviours:
                raise ValueError(f"Behaviour id {new_id!r} already exists")
            del behaviours[old_id]
            self._selected_behaviour = new_id
            self._rewrite_behaviour_refs(old_id, new_id)
        behaviours[new_id] = ordered
        if new_id != old_id:
            self._refresh_behaviour_list(new_id)
            self._refresh_template_list_options()
            self._refresh_monster_list_options()

    def _rewrite_behaviour_refs(self, old_id: str, new_id: str) -> None:
        templates = self.table_doc.get("templates", {})
        assert isinstance(templates, dict)
        for tmpl in templates.values():
            if not isinstance(tmpl, dict):
                continue
            vals = tmpl.get("behaviour")
            if isinstance(vals, list):
                tmpl["behaviour"] = [new_id if x == old_id else x for x in vals]
        monsters = self.table_doc.get("monsters", [])
        assert isinstance(monsters, list)
        for mon in monsters:
            if not isinstance(mon, dict):
                continue
            for key in ("behaviour", "behaviour_extra"):
                vals = mon.get(key)
                if isinstance(vals, list):
                    mon[key] = [new_id if x == old_id else x for x in vals]

    def _add_behaviour(self) -> None:
        try:
            self._flush_behaviour_form()
        except ValueError as exc:
            messagebox.showerror("Invalid behaviour fields", str(exc), parent=self)
            return
        behaviours = self.behaviours_doc.setdefault("behaviours", {})
        assert isinstance(behaviours, dict)
        base = "new_behaviour"
        name = base
        n = 2
        while name in behaviours:
            name = f"{base}_{n}"
            n += 1
        behaviours[name] = {
            "id": name,
            "intent": "",
            "attacks": [],
        }
        self._mark_dirty()
        self._refresh_behaviour_list(name)
        self._refresh_template_list_options()
        self._refresh_monster_list_options()

    def _delete_behaviour(self) -> None:
        if self._selected_behaviour is None:
            return
        bid = self._selected_behaviour
        if not messagebox.askyesno(
            "Delete behaviour",
            f"Delete behaviour {bid!r}? Templates/monsters referencing it will "
            "become invalid until updated.",
            parent=self,
        ):
            return
        behaviours = self.behaviours_doc.get("behaviours", {})
        assert isinstance(behaviours, dict)
        del behaviours[bid]
        self._selected_behaviour = None
        self._mark_dirty()
        self._refresh_behaviour_list()
        self._refresh_template_list_options()
        self._refresh_monster_list_options()

    # --- Templates tab ---------------------------------------------------------

    def _build_templates_tab(self) -> None:
        paned = ttk.Panedwindow(self._tab_templates, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=4)
        right = ttk.Frame(paned, padding=4)
        paned.add(left, weight=1)
        paned.add(right, weight=3)

        ttk.Label(left, text="Templates").pack(anchor="w")
        self._template_list = tk.Listbox(left, exportselection=False)
        self._template_list.pack(fill="both", expand=True)
        self._template_list.bind("<<ListboxSelect>>", self._on_template_select)
        btns = ttk.Frame(left)
        btns.pack(fill="x", pady=4)
        ttk.Button(btns, text="Add", command=self._add_template).pack(side="left", padx=2)
        ttk.Button(btns, text="Delete", command=self._delete_template).pack(
            side="left", padx=2
        )

        canvas = tk.Canvas(right, highlightthickness=0)
        scroll = ttk.Scrollbar(right, orient="vertical", command=canvas.yview)
        form = ttk.Frame(canvas)
        form.bind(
            "<Configure>",
            lambda _e: canvas.configure(scrollregion=canvas.bbox("all")),
        )
        canvas.create_window((0, 0), window=form, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)

        ttk.Label(form, text="id (rename)").grid(row=0, column=0, sticky="w", pady=2)
        self._template_id_var = tk.StringVar()
        ttk.Entry(form, textvariable=self._template_id_var).grid(
            row=0, column=1, sticky="ew", pady=2
        )
        self._template_id_var.trace_add("write", self._mark_dirty)

        ttk.Label(form, text="intent").grid(row=1, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=self._template_intent, width=60).grid(
            row=1, column=1, sticky="ew", pady=2
        )
        self._template_intent.trace_add("write", self._mark_dirty)

        row = 2
        for key in SCALAR_KEYS:
            var = tk.StringVar()
            self._template_scalar_entries[key] = var
            ttk.Label(form, text=key).grid(row=row, column=0, sticky="w", pady=2)
            ttk.Entry(form, textvariable=var).grid(row=row, column=1, sticky="ew", pady=2)
            var.trace_add("write", self._mark_dirty)
            row += 1

        lists_frame = ttk.LabelFrame(
            form,
            text=(
                "Lists — behaviour required; attacks optional template specialty "
                "(prefer behaviours.json + per-monster body attacks)"
            ),
            padding=4,
        )
        lists_frame.grid(row=row, column=0, columnspan=2, sticky="nsew", pady=6)
        form.columnconfigure(1, weight=1)
        for i, key in enumerate(LIST_KEYS):
            col = ttk.Frame(lists_frame)
            col.grid(row=0, column=i, sticky="nsew", padx=4)
            label = key
            if key == "attacks":
                label = "attacks (legacy specialty; prefer Monsters tab)"
            ttk.Label(col, text=label).pack(anchor="w")
            check = Checklist(col, height=10)
            check.pack(fill="both", expand=True)
            self._template_checklists[key] = check

    def _refresh_template_list(self, select: str | None = None) -> None:
        templates = self.table_doc.get("templates", {})
        assert isinstance(templates, dict)
        ids = sorted(templates.keys())
        self._template_list.delete(0, "end")
        for tid in ids:
            self._template_list.insert("end", tid)
        target = select if select in ids else (ids[0] if ids else None)
        if target is None:
            self._selected_template = None
            return
        idx = ids.index(target)
        self._template_list.selection_clear(0, "end")
        self._template_list.selection_set(idx)
        self._template_list.see(idx)
        self._load_template_form(target)

    def _refresh_template_list_options(self) -> None:
        enums = _enum_options(self.attacks_doc, self.behaviours_doc)
        tags = self._collect_known_tags()
        option_map = {
            "behaviour": enums["behaviour"],
            "crowd_roles": enums["crowd_roles"],
            "attacks": enums["attacks"],
            "tags": tags,
            "auras": self._collect_known_auras(),
        }
        for key, check in self._template_checklists.items():
            selected = check.get_selected()
            check.set_options(option_map[key])
            check.set_selected(selected)
            self._wire_checklist_dirty(check)

    def _collect_known_auras(self) -> list[str]:
        auras = self._gamedata_root.get("auras")
        if not isinstance(auras, dict):
            return []
        return sorted(str(k) for k in auras.keys())

    def _collect_known_tags(self) -> list[str]:
        tags: set[str] = set()
        templates = self.table_doc.get("templates", {})
        assert isinstance(templates, dict)
        for tmpl in templates.values():
            if isinstance(tmpl, dict):
                for t in tmpl.get("tags", []):
                    if isinstance(t, str):
                        tags.add(t)
        monsters = self.table_doc.get("monsters", [])
        assert isinstance(monsters, list)
        for mon in monsters:
            if not isinstance(mon, dict):
                continue
            for key in ("tags", "tags_extra"):
                for t in mon.get(key, []) if isinstance(mon.get(key), list) else []:
                    if isinstance(t, str):
                        tags.add(t)
        return sorted(tags)

    def _on_template_select(self, _event: object | None = None) -> None:
        sel = self._template_list.curselection()
        if not sel:
            return
        new_id = self._template_list.get(sel[0])
        if new_id == self._selected_template:
            return
        try:
            self._flush_template_form()
        except ValueError as exc:
            messagebox.showerror("Invalid template fields", str(exc), parent=self)
            self._refresh_template_list(self._selected_template)
            return
        self._load_template_form(new_id)

    def _load_template_form(self, tid: str) -> None:
        templates = self.table_doc["templates"]
        assert isinstance(templates, dict)
        tmpl = templates[tid]
        if not isinstance(tmpl, dict):
            raise TypeError(f"Template {tid!r} must be an object")
        self._loading = True
        self._selected_template = tid
        try:
            self._template_id_var.set(tid)
            self._template_intent.set(str(tmpl.get("intent", "")))
            for key in SCALAR_KEYS:
                self._template_scalar_entries[key].set(str(tmpl.get(key, "")))
            for key, check in self._template_checklists.items():
                vals = tmpl.get(key, [])
                if not isinstance(vals, list):
                    vals = []
                check.set_selected([x for x in vals if isinstance(x, str)])
                self._wire_checklist_dirty(check)
        finally:
            self._loading = False

    def _flush_template_form(self) -> None:
        if self._selected_template is None:
            return
        templates = self.table_doc["templates"]
        assert isinstance(templates, dict)
        old_id = self._selected_template
        if old_id not in templates:
            return
        existing = templates[old_id]
        assert isinstance(existing, dict)
        row = copy.deepcopy(existing)
        for forbidden in validate_mod.FORBIDDEN_PREY_KEYS:
            row.pop(forbidden, None)
        new_id = self._template_id_var.get().strip()
        if not new_id:
            raise ValueError("Template id must be non-empty")
        intent = self._template_intent.get().strip()
        if intent:
            row["intent"] = intent
        else:
            row.pop("intent", None)
        for key in SCALAR_KEYS:
            row[key] = _parse_required_float(self._template_scalar_entries[key].get(), key)
        for key, check in self._template_checklists.items():
            selected = check.get_selected()
            if key == "attacks" and not selected:
                row.pop("attacks", None)
            else:
                row[key] = selected
        if "behaviour" not in row or not row["behaviour"]:
            raise ValueError("Template behaviour list must be non-empty")
        ordered = _reorder_keys(row, TEMPLATE_FIELD_ORDER)
        if new_id != old_id:
            if new_id in templates:
                raise ValueError(f"Template id {new_id!r} already exists")
            del templates[old_id]
            self._selected_template = new_id
            self._rewrite_template_refs(old_id, new_id)
        templates[new_id] = ordered
        if new_id != old_id:
            self._refresh_template_list(new_id)
            self._refresh_monster_template_options()

    def _rewrite_template_refs(self, old_id: str, new_id: str) -> None:
        monsters = self.table_doc.get("monsters", [])
        assert isinstance(monsters, list)
        for mon in monsters:
            if not isinstance(mon, dict):
                continue
            tids = mon.get("templates")
            if isinstance(tids, list):
                mon["templates"] = [new_id if x == old_id else x for x in tids]

    def _add_template(self) -> None:
        try:
            self._flush_template_form()
        except ValueError as exc:
            messagebox.showerror("Invalid template fields", str(exc), parent=self)
            return
        templates = self.table_doc["templates"]
        assert isinstance(templates, dict)
        base = "new_template"
        name = base
        n = 2
        while name in templates:
            name = f"{base}_{n}"
            n += 1
        templates[name] = {
            "intent": "",
            "hp_mult": 1.0,
            "damage_mult": 1.0,
            "speed_mult": 1.0,
            "aggro_range_m": 30.0,
            "leash_m": 40.0,
            "preferred_range_m": 2.0,
            "armor_mult": 1.0,
            "score_mult": 1.0,
            "behaviour": ["chase"],
            "tags": [],
            "crowd_roles": ["wave_hunter"],
        }
        self._mark_dirty()
        self._refresh_template_list(name)
        self._refresh_monster_template_options()

    def _delete_template(self) -> None:
        if self._selected_template is None:
            return
        tid = self._selected_template
        if tid in {"melee_boss", "ranged_boss"}:
            messagebox.showerror(
                "Cannot delete",
                f"Template {tid!r} is required for boss tier parity validation.",
                parent=self,
            )
            return
        if not messagebox.askyesno(
            "Delete template",
            f"Delete template {tid!r}? Monsters referencing it will become invalid.",
            parent=self,
        ):
            return
        templates = self.table_doc["templates"]
        assert isinstance(templates, dict)
        del templates[tid]
        self._selected_template = None
        self._mark_dirty()
        self._refresh_template_list()
        self._refresh_monster_template_options()

    # --- Monsters tab ----------------------------------------------------------

    def _build_monsters_tab(self) -> None:
        # Left: body list. Center: editable settings (scroll). Right: foldable
        # effective-stats panel (hidden by default for horizontal room).
        outer = ttk.Panedwindow(self._tab_monsters, orient="horizontal")
        outer.pack(fill="both", expand=True)
        self._monster_paned = outer
        left = ttk.Frame(outer, padding=4)
        center = ttk.Frame(outer, padding=4)
        preview_wrap = ttk.Frame(outer, padding=4)
        self._monster_preview_wrap = preview_wrap
        outer.add(left, weight=1)
        outer.add(center, weight=4)
        # preview_wrap is added only when expanded (folded by default).

        ttk.Label(left, text="Bodies (CreatureCatalog)").pack(anchor="w")
        self._monster_list = tk.Listbox(left, exportselection=False)
        self._monster_list.pack(fill="both", expand=True)
        self._monster_list.bind("<<ListboxSelect>>", self._on_monster_select)

        # Scrollable form: vertical + horizontal so wide checklist rows don't clip.
        canvas = tk.Canvas(center, highlightthickness=0)
        vscroll = ttk.Scrollbar(center, orient="vertical", command=canvas.yview)
        hscroll = ttk.Scrollbar(center, orient="horizontal", command=canvas.xview)
        form = ttk.Frame(canvas)
        win = canvas.create_window((0, 0), window=form, anchor="nw")

        def _sync_scrollregion(_event: object | None = None) -> None:
            canvas.configure(scrollregion=canvas.bbox("all"))

        def _on_canvas_configure(event: tk.Event) -> None:  # type: ignore[type-arg]
            # Grow the form to at least the viewport width; allow wider content + h-scroll.
            min_w = int(event.width)
            req_w = int(form.winfo_reqwidth())
            canvas.itemconfigure(win, width=max(min_w, req_w))
            _sync_scrollregion()

        form.bind("<Configure>", _sync_scrollregion)
        canvas.configure(yscrollcommand=vscroll.set, xscrollcommand=hscroll.set)
        canvas.bind("<Configure>", _on_canvas_configure)

        def _on_mousewheel(event: tk.Event) -> None:  # type: ignore[type-arg]
            delta = int(getattr(event, "delta", 0))
            if delta == 0:
                return
            canvas.yview_scroll(int(-1 * (delta / 120)), "units")

        canvas.bind("<Enter>", lambda _e: canvas.bind_all("<MouseWheel>", _on_mousewheel))
        canvas.bind("<Leave>", lambda _e: canvas.unbind_all("<MouseWheel>"))

        center.rowconfigure(0, weight=1)
        center.columnconfigure(0, weight=1)
        canvas.grid(row=0, column=0, sticky="nsew")
        vscroll.grid(row=0, column=1, sticky="ns")
        hscroll.grid(row=1, column=0, sticky="ew")
        self._monster_form_canvas = canvas

        ttk.Label(form, text="id").grid(row=0, column=0, sticky="w")
        self._monster_id_label = ttk.Label(form, text="")
        self._monster_id_label.grid(row=0, column=1, sticky="w")

        duel_bar = ttk.Frame(form)
        duel_bar.grid(row=0, column=2, sticky="e", padx=(8, 0))
        self._monster_preview_toggle_btn = ttk.Button(
            duel_bar,
            text="Show effective stats",
            command=self._toggle_monster_preview_pane,
        )
        self._monster_preview_toggle_btn.pack(side="left", padx=2)
        ttk.Button(
            duel_bar,
            text="Duel vs all",
            command=lambda: self._run_monster_duels(same_tier_only=False),
        ).pack(side="left", padx=2)
        ttk.Button(
            duel_bar,
            text="Duel vs same tier",
            command=lambda: self._run_monster_duels(same_tier_only=True),
        ).pack(side="left", padx=2)

        ttk.Label(form, text="faction").grid(row=1, column=0, sticky="w", pady=2)
        faction_box = ttk.Combobox(
            form,
            textvariable=self._monster_faction,
            values=ALLOWED_FACTIONS,
            state="readonly",
        )
        faction_box.grid(row=1, column=1, sticky="w", pady=2)
        self._monster_faction.trace_add("write", self._on_monster_field_change)
        ttk.Label(
            form,
            text="Same-faction monsters do not hunt or hurt each other.",
            foreground="#666666",
        ).grid(row=2, column=1, sticky="w", pady=(0, 4))

        ttk.Label(form, text="templates").grid(row=3, column=0, sticky="nw", pady=4)
        self._monster_template_check = Checklist(form, height=8)
        self._monster_template_check.grid(row=3, column=1, sticky="ew", pady=4)
        self._wire_checklist_monster_preview(self._monster_template_check)

        ttk.Checkbutton(
            form, text="spawn_ready", variable=self._monster_spawn_ready
        ).grid(row=4, column=1, sticky="w")
        self._monster_spawn_ready.trace_add("write", self._on_monster_field_change)

        ttk.Label(form, text="spawn_weight").grid(row=5, column=0, sticky="w")
        ttk.Entry(form, textvariable=self._monster_spawn_weight).grid(
            row=5, column=1, sticky="ew"
        )
        self._monster_spawn_weight.trace_add("write", self._on_monster_field_change)

        ttk.Label(form, text="notes").grid(row=6, column=0, sticky="nw")
        self._monster_notes = tk.Text(form, height=3, wrap="word")
        self._monster_notes.grid(row=6, column=1, sticky="ew")
        self._monster_notes.bind("<<Modified>>", self._on_monster_notes_modified)

        scalars = ttk.LabelFrame(
            form, text="Scalar overrides (blank = inherit merged max)", padding=4
        )
        scalars.grid(row=7, column=0, columnspan=3, sticky="ew", pady=6)
        for i, key in enumerate(SCALAR_KEYS):
            var = tk.StringVar()
            self._monster_scalar_vars[key] = var
            ttk.Label(scalars, text=key).grid(row=i // 2, column=(i % 2) * 2, sticky="w")
            e = ttk.Entry(scalars, textvariable=var, width=12)
            e.grid(row=i // 2, column=(i % 2) * 2 + 1, sticky="w", padx=4, pady=2)
            var.trace_add("write", self._on_monster_field_change)

        # Body attacks get a dedicated panel (primary authoring surface). Other list
        # overrides stay in the compact Inherit/Extra/Replace row.
        body_attacks = ttk.LabelFrame(
            form,
            text=(
                "Body attacks — Extra (attacks_extra) adds to behaviour-derived; "
                "Replace (attacks) hard-replaces the full effective list"
            ),
            padding=4,
        )
        body_attacks.grid(row=8, column=0, columnspan=3, sticky="nsew", pady=6)
        ttk.Label(
            body_attacks,
            text=(
                "Default: Extra — checklist unions onto attacks from effective behaviours "
                "(and any template specialty). Replace drops behaviour-derived attacks "
                "and uses only the checked ids. Inherit = no body override."
            ),
            wraplength=420,
        ).pack(anchor="w", pady=(0, 4))
        atk_modes = ttk.Frame(body_attacks)
        atk_modes.pack(anchor="w")
        atk_mode = tk.StringVar(value="inherit")
        self._monster_list_modes["attacks"] = atk_mode
        for label, value in (
            ("Inherit", "inherit"),
            ("Extra (add)", "extra"),
            ("Replace (hard)", "replace"),
        ):
            ttk.Radiobutton(
                atk_modes,
                text=label,
                value=value,
                variable=atk_mode,
                command=self._on_monster_field_change,
            ).pack(side="left", padx=(0, 8))
        atk_check = Checklist(body_attacks, height=10)
        atk_check.pack(fill="both", expand=True)
        self._monster_list_checks["attacks"] = atk_check
        self._wire_checklist_monster_preview(atk_check)
        atk_mode.trace_add("write", self._on_monster_field_change)

        lists = ttk.LabelFrame(
            form,
            text=(
                "Other list overrides — Inherit / Extra (*_extra) / Replace (hard)  "
                "[attacks above]"
            ),
            padding=4,
        )
        lists.grid(row=9, column=0, columnspan=3, sticky="nsew", pady=6)
        # Stack vertically — side-by-side checklists overflow the center pane.
        other_list_keys = tuple(k for k in LIST_KEYS if k != "attacks")
        for i, key in enumerate(other_list_keys):
            row = ttk.LabelFrame(lists, text=key, padding=4)
            row.grid(row=i, column=0, sticky="ew", pady=4)
            lists.columnconfigure(0, weight=1)
            mode = tk.StringVar(value="inherit")
            self._monster_list_modes[key] = mode
            modes = ttk.Frame(row)
            modes.pack(anchor="w")
            for label, value in (
                ("Inherit", "inherit"),
                ("Extra", "extra"),
                ("Replace", "replace"),
            ):
                ttk.Radiobutton(
                    modes,
                    text=label,
                    value=value,
                    variable=mode,
                    command=self._on_monster_field_change,
                ).pack(side="left", padx=(0, 8))
            check = Checklist(row, height=6)
            check.pack(fill="both", expand=True)
            self._monster_list_checks[key] = check
            self._wire_checklist_monster_preview(check)
            mode.trace_add("write", self._on_monster_field_change)

        form.columnconfigure(1, weight=1)
        form.columnconfigure(2, weight=0)

        preview = ttk.LabelFrame(
            preview_wrap,
            text=(
                "EFFECTIVE STATS (resolved) — updates live from templates + overrides"
            ),
            padding=6,
        )
        preview.pack(fill="both", expand=True)
        ttk.Label(
            preview,
            text=(
                "Same merge as game code (CombatTable / combat_resolve.py): "
                "max scalars · union lists · behaviour attacks "
                "+ body attacks_extra / hard attacks"
            ),
            wraplength=360,
        ).pack(anchor="w", pady=(0, 4))
        self._monster_preview = tk.Text(
            preview,
            height=28,
            wrap="word",
            state="disabled",
            font=("Consolas", 10),
            background="#1e1e1e",
            foreground="#e8e8e8",
            insertbackground="#e8e8e8",
            relief="flat",
            padx=8,
            pady=8,
        )
        self._monster_preview.pack(fill="both", expand=True)
        self._monster_preview.tag_configure(
            "heading", foreground="#9cdcfe", font=("Consolas", 10, "bold")
        )
        self._monster_preview.tag_configure("accent", foreground="#dcdcaa")
        self._monster_preview.tag_configure("muted", foreground="#808080")
        self._monster_preview_expanded = False

    def _toggle_monster_preview_pane(self) -> None:
        paned = self._monster_paned
        wrap = self._monster_preview_wrap
        btn = self._monster_preview_toggle_btn
        if paned is None or wrap is None or btn is None:
            return
        if self._monster_preview_expanded:
            try:
                paned.forget(wrap)
            except tk.TclError:
                pass
            self._monster_preview_expanded = False
            btn.configure(text="Show effective stats")
        else:
            paned.add(wrap, weight=3)
            self._monster_preview_expanded = True
            btn.configure(text="Hide effective stats")
            self._update_monster_preview()

    def _on_monster_notes_modified(self, _event: object | None = None) -> None:
        assert self._monster_notes is not None
        if self._monster_notes.edit_modified():
            self._mark_dirty()
            self._monster_notes.edit_modified(False)
            self._update_monster_preview()

    def _on_monster_field_change(self, *_args: object) -> None:
        self._mark_dirty()
        if self._loading:
            return
        self._sync_selected_monster_list_label()
        self._update_monster_preview()

    def _sync_selected_monster_list_label(self) -> None:
        if self._selected_monster is None:
            return
        sel = self._monster_list.curselection()
        if not sel:
            return
        idx = int(sel[0])
        fac = self._monster_faction.get().strip() or "?"
        label = self._monster_list_label(self._selected_monster, fac)
        if self._monster_list.get(idx) == label:
            return
        was_loading = self._loading
        self._loading = True
        try:
            self._monster_list.delete(idx)
            self._monster_list.insert(idx, label)
            self._monster_list.selection_set(idx)
        finally:
            self._loading = was_loading

    def _monster_list_label(self, mid: str, faction: str | None = None) -> str:
        fac = faction
        if fac is None:
            try:
                fac = str(self._find_monster(mid).get("faction", "?"))
            except KeyError:
                fac = "?"
        return f"{mid}  ·  {fac}"

    def _monster_id_from_list_label(self, label: str) -> str:
        if "  ·  " in label:
            return label.split("  ·  ", 1)[0]
        return label

    def _refresh_monster_list(self, select: str | None = None) -> None:
        monsters = self.table_doc.get("monsters", [])
        assert isinstance(monsters, list)
        rows: list[tuple[str, str]] = []
        for mon in monsters:
            if not isinstance(mon, dict) or not isinstance(mon.get("id"), str):
                continue
            mid = mon["id"]
            fac = mon.get("faction")
            fac_s = fac if isinstance(fac, str) and fac else "?"
            rows.append((mid, fac_s))
        self._monster_list.delete(0, "end")
        for mid, fac in rows:
            self._monster_list.insert("end", self._monster_list_label(mid, fac))
        ids = [mid for mid, _fac in rows]
        target = select if select in ids else (ids[0] if ids else None)
        if target is None:
            self._selected_monster = None
            return
        idx = ids.index(target)
        self._monster_list.selection_clear(0, "end")
        self._monster_list.selection_set(idx)
        self._monster_list.see(idx)
        self._load_monster_form(target)

    def _refresh_monster_template_options(self) -> None:
        assert self._monster_template_check is not None
        templates = self.table_doc.get("templates", {})
        assert isinstance(templates, dict)
        selected = self._monster_template_check.get_selected()
        self._monster_template_check.set_options(sorted(templates.keys()))
        self._monster_template_check.set_selected(selected)
        self._wire_checklist_monster_preview(self._monster_template_check)

    def _refresh_monster_list_options(self) -> None:
        enums = _enum_options(self.attacks_doc, self.behaviours_doc)
        tags = self._collect_known_tags()
        option_map = {
            "behaviour": enums["behaviour"],
            "crowd_roles": enums["crowd_roles"],
            "attacks": enums["attacks"],
            "tags": tags,
            "auras": self._collect_known_auras(),
        }
        for key, check in self._monster_list_checks.items():
            selected = check.get_selected()
            check.set_options(option_map[key])
            check.set_selected(selected)
            self._wire_checklist_monster_preview(check)

    def _on_monster_select(self, _event: object | None = None) -> None:
        sel = self._monster_list.curselection()
        if not sel:
            return
        new_id = self._monster_id_from_list_label(self._monster_list.get(sel[0]))
        if new_id == self._selected_monster:
            return
        try:
            self._flush_monster_form()
        except ValueError as exc:
            messagebox.showerror("Invalid monster fields", str(exc), parent=self)
            self._refresh_monster_list(self._selected_monster)
            return
        self._load_monster_form(new_id)

    def _find_monster(self, mid: str) -> dict[str, Any]:
        monsters = self.table_doc["monsters"]
        assert isinstance(monsters, list)
        for mon in monsters:
            if isinstance(mon, dict) and mon.get("id") == mid:
                return mon
        raise KeyError(f"Monster {mid!r} not found")

    def _load_monster_form(self, mid: str) -> None:
        mon = self._find_monster(mid)
        self._loading = True
        self._selected_monster = mid
        try:
            self._monster_id_label.configure(text=mid)
            fac = mon.get("faction")
            if isinstance(fac, str) and fac in ALLOWED_FACTIONS:
                self._monster_faction.set(fac)
            elif ALLOWED_FACTIONS:
                self._monster_faction.set(ALLOWED_FACTIONS[0])
            assert self._monster_template_check is not None
            tids = mon.get("templates", [])
            if not isinstance(tids, list):
                tids = []
            self._monster_template_check.set_selected(
                [t for t in tids if isinstance(t, str)]
            )
            self._wire_checklist_monster_preview(self._monster_template_check)
            self._monster_spawn_ready.set(bool(mon.get("spawn_ready", False)))
            if "spawn_weight" in mon:
                self._monster_spawn_weight.set(str(mon["spawn_weight"]))
            else:
                self._monster_spawn_weight.set("")
            assert self._monster_notes is not None
            self._monster_notes.delete("1.0", "end")
            self._monster_notes.insert("1.0", str(mon.get("notes", "")))
            self._monster_notes.edit_modified(False)
            for key in SCALAR_KEYS:
                if key in mon:
                    self._monster_scalar_vars[key].set(str(mon[key]))
                else:
                    self._monster_scalar_vars[key].set("")
            for key in LIST_KEYS:
                if key in mon and isinstance(mon[key], list):
                    self._monster_list_modes[key].set("replace")
                    self._monster_list_checks[key].set_selected(
                        [x for x in mon[key] if isinstance(x, str)]
                    )
                elif f"{key}_extra" in mon and isinstance(mon[f"{key}_extra"], list):
                    self._monster_list_modes[key].set("extra")
                    self._monster_list_checks[key].set_selected(
                        [x for x in mon[f"{key}_extra"] if isinstance(x, str)]
                    )
                else:
                    self._monster_list_modes[key].set("inherit")
                    self._monster_list_checks[key].clear()
                self._wire_checklist_monster_preview(self._monster_list_checks[key])
        finally:
            self._loading = False
        self._update_monster_preview()

    def _flush_monster_form(self) -> None:
        if self._selected_monster is None:
            return
        mid = self._selected_monster
        mon = self._find_monster(mid)
        existing = copy.deepcopy(mon)
        assert self._monster_template_check is not None
        tids = self._monster_template_check.get_selected()
        if not tids:
            raise ValueError(f"Monster {mid}: templates must be a non-empty selection")

        row = existing
        for forbidden in validate_mod.FORBIDDEN_PREY_KEYS:
            row.pop(forbidden, None)
        row["id"] = mid
        faction = self._monster_faction.get().strip()
        if faction not in ALLOWED_FACTIONS:
            raise ValueError(
                f"Monster {mid}: faction must be one of {', '.join(ALLOWED_FACTIONS)}"
            )
        row["faction"] = faction
        row["templates"] = tids
        row["spawn_ready"] = bool(self._monster_spawn_ready.get())

        weight_raw = self._monster_spawn_weight.get().strip()
        if weight_raw == "":
            row.pop("spawn_weight", None)
        else:
            row["spawn_weight"] = _parse_required_float(weight_raw, "spawn_weight")

        assert self._monster_notes is not None
        notes = self._monster_notes.get("1.0", "end-1c")
        if notes.strip() == "":
            row.pop("notes", None)
        else:
            row["notes"] = notes

        for key in SCALAR_KEYS:
            value = _parse_optional_float(self._monster_scalar_vars[key].get(), key)
            if value is None:
                row.pop(key, None)
            else:
                row[key] = value

        for key in LIST_KEYS:
            mode = self._monster_list_modes[key].get()
            selected = self._monster_list_checks[key].get_selected()
            extra_key = f"{key}_extra"
            if mode == "inherit":
                row.pop(key, None)
                row.pop(extra_key, None)
            elif mode == "extra":
                row.pop(key, None)
                if selected:
                    row[extra_key] = selected
                else:
                    row.pop(extra_key, None)
            elif mode == "replace":
                row.pop(extra_key, None)
                row[key] = selected
            else:
                raise ValueError(f"Unknown list mode {mode!r} for {key}")

        ordered = _reorder_keys(row, MONSTER_CORE_ORDER)
        monsters = self.table_doc["monsters"]
        assert isinstance(monsters, list)
        for i, cur in enumerate(monsters):
            if isinstance(cur, dict) and cur.get("id") == mid:
                monsters[i] = ordered
                break

    def _update_monster_preview(self) -> None:
        assert self._monster_preview is not None
        self._monster_preview.configure(state="normal")
        self._monster_preview.delete("1.0", "end")

        if self._selected_monster is None:
            self._monster_preview.insert("1.0", "(no monster selected)", "muted")
            self._monster_preview.configure(state="disabled")
            return

        try:
            body = self._preview_body_from_form()
            templates = self.table_doc.get("templates", {})
            assert isinstance(templates, dict)
            tids = body.get("templates", [])
            if not isinstance(tids, list) or not tids:
                self._monster_preview.insert("1.0", "Select at least one template.")
                self._monster_preview.configure(state="disabled")
                return

            behaviours = _behaviours_map(self.behaviours_doc)
            eff = validate_mod.effective_monster_combat(
                tids, templates, body, behaviours
            )
            self._insert_preview_heading("BODY")
            self._monster_preview.insert("end", f"  {body['id']}\n", "accent")
            faction = str(body.get("faction", "?"))
            self._monster_preview.insert("end", "  faction: ", "muted")
            self._monster_preview.insert("end", f"{faction}\n", "accent")
            self._monster_preview.insert("end", f"  templates: {', '.join(tids)}\n\n")

            self._insert_preview_heading("BEHAVIOURS (effective)")
            beh = eff["behaviour"]
            self._monster_preview.insert(
                "end",
                f"  {', '.join(beh) if beh else '(none)'}\n\n",
                "accent",
            )

            self._insert_preview_heading("SCALARS (max across templates, then body)")
            for key in SCALAR_KEYS:
                val = eff["scalars"].get(key, "—")
                self._monster_preview.insert("end", f"  {key:<18} ", "muted")
                self._monster_preview.insert("end", f"{val:g}\n" if isinstance(val, float) else f"{val}\n", "accent")
            self._monster_preview.insert("end", "\n")

            self._insert_preview_heading("ATTACKS (resolved)")
            derived = validate_mod.attacks_from_behaviours(list(beh), behaviours)
            specialty = list(eff["lists"].get("attacks", []))
            body_mode = self._monster_list_modes["attacks"].get()
            body_selected = self._monster_list_checks["attacks"].get_selected()
            self._monster_preview.insert("end", "  from behaviours: ", "muted")
            self._monster_preview.insert(
                "end",
                f"{', '.join(derived) if derived else '(none)'}\n",
                "accent",
            )
            if body_mode == "replace":
                self._monster_preview.insert("end", "  body: ", "muted")
                self._monster_preview.insert(
                    "end",
                    f"Replace → {', '.join(body_selected) if body_selected else '(empty)'}\n",
                    "accent",
                )
            elif body_mode == "extra":
                self._monster_preview.insert("end", "  body: ", "muted")
                self._monster_preview.insert(
                    "end",
                    f"Extra + {', '.join(body_selected) if body_selected else '(none)'}\n",
                    "accent",
                )
                if specialty and specialty != list(body_selected):
                    # Template specialty (or extras already folded into specialty list).
                    tmpl_only = [a for a in specialty if a not in body_selected]
                    if tmpl_only:
                        self._monster_preview.insert(
                            "end", "  template specialty: ", "muted"
                        )
                        self._monster_preview.insert(
                            "end", f"{', '.join(tmpl_only)}\n", "accent"
                        )
            else:
                self._monster_preview.insert("end", "  body: ", "muted")
                self._monster_preview.insert("end", "Inherit\n", "accent")
                if specialty:
                    self._monster_preview.insert(
                        "end", "  template specialty: ", "muted"
                    )
                    self._monster_preview.insert(
                        "end", f"{', '.join(specialty)}\n", "accent"
                    )
            atk = list(eff["attacks"])
            dmg_mult = float(eff["scalars"]["damage_mult"])
            attacks_map = self.attacks_doc.get("attacks", {})
            assert isinstance(attacks_map, dict)
            self._monster_preview.insert(
                "end",
                "  effective (damage = base × damage_mult):\n",
                "muted",
            )
            if not atk:
                self._monster_preview.insert("end", "  (empty)\n", "muted")
            else:
                for a in atk:
                    dmg = validate_mod.effective_attack_damage(
                        a, dmg_mult, attacks_map
                    )
                    self._monster_preview.insert("end", f"  • {a}\n", "accent")
                    self._monster_preview.insert("end", "      vs player ", "muted")
                    self._monster_preview.insert(
                        "end", f"{dmg['vs_player']:g}", "accent"
                    )
                    self._monster_preview.insert("end", "  vs mob ", "muted")
                    self._monster_preview.insert(
                        "end", f"{dmg['vs_mob']:g}\n", "accent"
                    )
            self._monster_preview.insert("end", "\n")

            self._insert_preview_heading("TAGS / CROWD ROLES")
            for key in ("tags", "crowd_roles"):
                vals = eff["lists"].get(key, [])
                self._monster_preview.insert("end", f"  {key}: ", "muted")
                self._monster_preview.insert(
                    "end",
                    f"{', '.join(vals) if vals else '(empty)'}\n",
                    "accent",
                )
        except (KeyError, TypeError, ValueError, RuntimeError) as exc:
            self._monster_preview.insert("1.0", f"Preview error: {exc}")

        self._monster_preview.configure(state="disabled")

    def _insert_preview_heading(self, title: str) -> None:
        assert self._monster_preview is not None
        self._monster_preview.insert("end", f"{title}\n", "heading")

    def _preview_body_from_form(self) -> dict[str, Any]:
        if self._selected_monster is None:
            raise RuntimeError("no monster selected")
        mid = self._selected_monster
        assert self._monster_template_check is not None
        body: dict[str, Any] = {
            "id": mid,
            "faction": self._monster_faction.get().strip(),
            "templates": self._monster_template_check.get_selected(),
            "spawn_ready": bool(self._monster_spawn_ready.get()),
        }
        weight_raw = self._monster_spawn_weight.get().strip()
        if weight_raw != "":
            body["spawn_weight"] = _parse_required_float(weight_raw, "spawn_weight")
        for key in SCALAR_KEYS:
            value = _parse_optional_float(self._monster_scalar_vars[key].get(), key)
            if value is not None:
                body[key] = value
        for key in LIST_KEYS:
            mode = self._monster_list_modes[key].get()
            selected = self._monster_list_checks[key].get_selected()
            if mode == "extra" and selected:
                body[f"{key}_extra"] = selected
            elif mode == "replace":
                body[key] = selected
        return body

    # --- duel sim (open-field 1v1) ---------------------------------------------

    def _assemble_sim_root(self) -> dict[str, Any]:
        """Current editor docs as a gamedata root (unsaved form values included)."""
        self._flush_all_forms()
        root = copy.deepcopy(self._gamedata_root) if self._gamedata_root else {}
        root["schema_version"] = int(root.get("schema_version", gd.SCHEMA_VERSION))
        root["attacks"] = copy.deepcopy(self.attacks_doc.get("attacks") or {})
        root["behaviours"] = copy.deepcopy(
            _behaviours_map(self.behaviours_doc)
        )
        root["templates"] = copy.deepcopy(self.table_doc.get("templates") or {})
        root["monsters"] = copy.deepcopy(self.table_doc.get("monsters") or [])
        return root

    def _run_monster_duels(self, *, same_tier_only: bool) -> None:
        if self._selected_monster is None:
            messagebox.showinfo("Duel sim", "Select a monster first.", parent=self)
            return
        mid = self._selected_monster
        try:
            root = self._assemble_sim_root()
            fighters, attack_rows = duel_sim.load_fighter_defs_from_root(root)
            report = duel_sim.format_fighter_report(
                mid,
                fighters,
                attack_rows,
                duels=8,
                same_tier_only=same_tier_only,
            )
        except (KeyError, TypeError, ValueError, RuntimeError, AssertionError) as exc:
            messagebox.showerror("Duel sim failed", str(exc), parent=self)
            return

        scope = "same tier" if same_tier_only else "all others"
        win = tk.Toplevel(self)
        win.title(f"Duel sim — {mid} vs {scope}")
        win.geometry("920x640")
        win.minsize(640, 400)
        bar = ttk.Frame(win, padding=6)
        bar.pack(side="top", fill="x")
        ttk.Label(
            bar,
            text=(
                f"{mid}  |  open-field 1v1  |  8 duels/pair  |  "
                "uses current (possibly unsaved) editor data"
            ),
        ).pack(side="left")
        ttk.Button(bar, text="Close", command=win.destroy).pack(side="right")

        text_frame = ttk.Frame(win, padding=(6, 0, 6, 6))
        text_frame.pack(fill="both", expand=True)
        text_frame.rowconfigure(0, weight=1)
        text_frame.columnconfigure(0, weight=1)
        yscroll = ttk.Scrollbar(text_frame, orient="vertical")
        xscroll = ttk.Scrollbar(text_frame, orient="horizontal")
        out = tk.Text(
            text_frame,
            wrap="none",
            font=("Consolas", 10),
            background="#1e1e1e",
            foreground="#e8e8e8",
            insertbackground="#e8e8e8",
            relief="flat",
            padx=8,
            pady=8,
        )
        out.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        yscroll.config(command=out.yview)
        xscroll.config(command=out.xview)
        out.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)
        out.insert("1.0", report)
        out.configure(state="disabled")
        self._status.set(f"Duel sim finished for {mid} ({scope})")

    # --- persistence / validation ---------------------------------------------

    def _flush_all_forms(self) -> None:
        self._flush_attack_form()
        self._flush_behaviour_form()
        self._flush_template_form()
        self._flush_monster_form()
        if self._items_panel is not None:
            self._items_panel.flush()
        if self._craft_panel is not None:
            self._craft_panel.flush()
        if self._build_panel is not None:
            self._build_panel.flush()
        if self._abilities_panel is not None:
            self._abilities_panel.flush()
        if self._spots_panel is not None:
            self._spots_panel.flush()

    def _on_tab_changed(self, _event: object | None = None) -> None:
        try:
            self._flush_all_forms()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc), parent=self)
            return
        # Refresh monster preview when switching tabs (behaviours may have changed).
        if not self._loading:
            self._update_monster_preview()

    def reload_from_disk(self, confirm_dirty: bool = True) -> None:
        if confirm_dirty and self._dirty:
            if not messagebox.askyesno(
                "Reload",
                "Discard unsaved changes and reload from disk?",
                parent=self,
            ):
                return
        try:
            self._gamedata_root = gd.load_gamedata()
            self.attacks_doc = gd.attacks_doc(self._gamedata_root)
            self.behaviours_doc = gd.behaviours_doc(self._gamedata_root)
            self.table_doc = gd.table_doc(self._gamedata_root)
        except (OSError, json.JSONDecodeError, TypeError, FileNotFoundError, ValueError) as exc:
            messagebox.showerror("Reload failed", str(exc), parent=self)
            raise
        self._selected_attack = None
        self._selected_behaviour = None
        self._selected_template = None
        self._selected_monster = None
        self._refresh_behaviour_attack_options()
        self._refresh_template_list_options()
        self._refresh_monster_template_options()
        self._refresh_monster_list_options()
        self._refresh_attack_list()
        self._refresh_behaviour_list()
        self._refresh_template_list()
        self._refresh_monster_list()
        self._load_noncombat_panels()
        self._set_clean()

    def _load_noncombat_panels(self) -> None:
        root = self._gamedata_root
        assert self._items_panel is not None
        assert self._craft_panel is not None
        assert self._build_panel is not None
        assert self._abilities_panel is not None
        assert self._district_panel is not None
        assert self._constants_panel is not None
        assert self._chest_panel is not None
        assert self._recipe_sites_panel is not None
        assert self._zoo_panel is not None
        assert self._crypt_panel is not None
        assert self._dungeon_summoner_panel is not None
        assert self._spots_panel is not None
        self._items_panel.set_data(root.get("items") or {})
        self._craft_panel.set_data(root.get("craft_recipes") or {})
        self._build_panel.set_data(root.get("build_recipes") or {})
        self._abilities_panel.set_data(root.get("abilities") or {})
        self._district_panel.set_data(root.get("district_gems") or {})
        self._constants_panel.set_data(root.get("ability_constants") or {})
        self._chest_panel.set_data(root.get("chest_loot") or {})
        self._recipe_sites_panel.set_data(root.get("recipe_sites") or {})
        self._zoo_panel.set_data(root.get("zoo") or {})
        self._crypt_panel.set_data(root.get("crypt") or {})
        self._dungeon_summoner_panel.set_data(root.get("dungeon_summoner") or {})
        self._spots_panel.set_data(root.get("mandelbrot_spots") or {})

    def _collect_noncombat(self) -> dict[str, Any]:
        assert self._items_panel is not None
        assert self._craft_panel is not None
        assert self._build_panel is not None
        assert self._abilities_panel is not None
        assert self._district_panel is not None
        assert self._constants_panel is not None
        assert self._chest_panel is not None
        assert self._recipe_sites_panel is not None
        assert self._zoo_panel is not None
        assert self._crypt_panel is not None
        assert self._dungeon_summoner_panel is not None
        assert self._spots_panel is not None
        return {
            "items": self._items_panel.get_data(),
            "craft_recipes": self._craft_panel.get_data(),
            "build_recipes": self._build_panel.get_data(),
            "abilities": self._abilities_panel.get_data(),
            "district_gems": self._district_panel.get_data(),
            "ability_constants": self._constants_panel.get_data(),
            "chest_loot": self._chest_panel.get_data(),
            "recipe_sites": self._recipe_sites_panel.get_data(),
            "zoo": self._zoo_panel.get_data(),
            "crypt": self._crypt_panel.get_data(),
            "dungeon_summoner": self._dungeon_summoner_panel.get_data(),
            "mandelbrot_spots": self._spots_panel.get_data(),
        }

    def _validate_noncombat(self, sections: dict[str, Any]) -> list[str]:
        errors: list[str] = []
        items = sections["items"]
        if not isinstance(items, dict) or not items:
            errors.append("items: must be a non-empty object")
        for iid, row in items.items() if isinstance(items, dict) else []:
            if not isinstance(row, dict):
                errors.append(f"items.{iid}: must be an object")
                continue
            if not str(row.get("display_name", "")).strip():
                errors.append(f"items.{iid}: display_name required")
            if int(row.get("stack_max", 0)) < 1:
                errors.append(f"items.{iid}: stack_max must be >= 1")

        crafts = sections["craft_recipes"]
        if not isinstance(crafts, dict):
            errors.append("craft_recipes: must be an object")
        for rid, row in crafts.items() if isinstance(crafts, dict) else []:
            if not isinstance(row, dict):
                errors.append(f"craft_recipes.{rid}: must be an object")
                continue
            inputs = row.get("inputs")
            if not isinstance(inputs, dict):
                errors.append(f"craft_recipes.{rid}: inputs must be an object")
            elif items and any(k not in items for k in inputs):
                missing = [k for k in inputs if k not in items]
                errors.append(f"craft_recipes.{rid}: unknown input item(s) {missing}")
            out_id = str(row.get("output_id", ""))
            if not out_id:
                errors.append(f"craft_recipes.{rid}: output_id required")

        builds = sections["build_recipes"]
        if not isinstance(builds, dict) or len(builds) < 1:
            errors.append("build_recipes: must be a non-empty object")
        for bid, row in builds.items() if isinstance(builds, dict) else []:
            if not isinstance(row, dict):
                errors.append(f"build_recipes.{bid}: must be an object")
                continue
            voxels = row.get("voxels")
            if not isinstance(voxels, list) or not voxels:
                errors.append(f"build_recipes.{bid}: voxels must be a non-empty array")
            else:
                for i, cell in enumerate(voxels):
                    if not (isinstance(cell, list) and len(cell) == 4):
                        errors.append(f"build_recipes.{bid}: voxels[{i}] must be [x,y,z,mat]")
                        break

        abilities = sections["abilities"]
        if not isinstance(abilities, dict) or not abilities:
            errors.append("abilities: must be a non-empty object")

        constants = sections["ability_constants"]
        if not isinstance(constants, dict):
            errors.append("ability_constants: must be an object")
        else:
            starters = constants.get("starter_unlocks")
            if not isinstance(starters, list):
                errors.append("ability_constants.starter_unlocks must be an array")
            elif abilities and any(a not in abilities for a in starters):
                missing = [a for a in starters if a not in abilities]
                errors.append(f"ability_constants.starter_unlocks: unknown {missing}")
            builds_default = constants.get("default_sandbox_builds")
            if not isinstance(builds_default, list):
                errors.append("ability_constants.default_sandbox_builds must be an array")
            elif builds and any(b not in builds for b in builds_default):
                missing = [b for b in builds_default if b not in builds]
                errors.append(
                    f"ability_constants.default_sandbox_builds: unknown {missing}"
                )

        districts = sections["district_gems"]
        if not isinstance(districts, dict):
            errors.append("district_gems: must be an object")
        else:
            totals = districts.get("theme_totals")
            weights = districts.get("rarity_weights")
            if not isinstance(totals, dict) or not totals:
                errors.append("district_gems.theme_totals must be a non-empty object")
            if not isinstance(weights, dict) or not weights:
                errors.append("district_gems.rarity_weights must be a non-empty object")
            elif items and any(k not in items for k in weights):
                missing = [k for k in weights if k not in items]
                errors.append(f"district_gems.rarity_weights: unknown item(s) {missing}")

        chest = sections["chest_loot"]
        if not isinstance(chest, dict):
            errors.append("chest_loot: must be an object")
        else:
            if int(chest.get("gems_min", -1)) < 0 or int(chest.get("gems_max", -1)) < 0:
                errors.append("chest_loot: gems_min/max must be >= 0")
            if int(chest.get("gems_min", 0)) > int(chest.get("gems_max", 0)):
                errors.append("chest_loot: gems_min cannot exceed gems_max")

        sites = sections["recipe_sites"]
        if not isinstance(sites, dict):
            errors.append("recipe_sites: must be an object")
        else:
            if not isinstance(sites.get("chance_pct"), dict):
                errors.append("recipe_sites.chance_pct must be an object")
            fallback = sites.get("fallback_gems")
            if not isinstance(fallback, list) or not fallback:
                errors.append("recipe_sites.fallback_gems must be a non-empty array")
            elif items and any(g not in items for g in fallback):
                missing = [g for g in fallback if g not in items]
                errors.append(f"recipe_sites.fallback_gems: unknown {missing}")

        errors.extend(
            _validate_forever_war_section(
                "zoo",
                sections.get("zoo"),
                {
                    "cloak_duration_sec": float,
                    "plate_damage_interval_sec": float,
                    "base_spawn_interval_sec": float,
                    "spawn_pressure_k": float,
                    "per_territory_cap": int,
                    "district_alive_cap": int,
                },
            )
        )
        errors.extend(
            _validate_forever_war_section(
                "crypt",
                sections.get("crypt"),
                {
                    "spawn_lift_m": float,
                    "base_spawn_interval_sec": float,
                    "spawn_pressure_k": float,
                    "alive_cap": int,
                    "first_spawn_fraction": float,
                    "faction": str,
                },
            )
        )
        crypt = sections.get("crypt")
        if isinstance(crypt, dict):
            frac = crypt.get("first_spawn_fraction")
            if isinstance(frac, (int, float)) and not (0.0 < float(frac) <= 1.0):
                errors.append("crypt.first_spawn_fraction must be in (0, 1]")
            faction = str(crypt.get("faction", "")).strip()
            if faction and faction not in ALLOWED_FACTIONS:
                errors.append(f"crypt.faction: unknown '{faction}'")
        errors.extend(
            _validate_forever_war_section(
                "dungeon_summoner",
                sections.get("dungeon_summoner"),
                {
                    "spawn_lift_m": float,
                    "base_spawn_interval_sec": float,
                    "spawn_pressure_k": float,
                    "alive_cap": int,
                    "first_spawn_fraction": float,
                    "max_height_m": float,
                },
            )
        )
        dungeon_summoner = sections.get("dungeon_summoner")
        if isinstance(dungeon_summoner, dict):
            frac = dungeon_summoner.get("first_spawn_fraction")
            if isinstance(frac, (int, float)) and not (0.0 < float(frac) <= 1.0):
                errors.append("dungeon_summoner.first_spawn_fraction must be in (0, 1]")
            tall = dungeon_summoner.get("max_height_m")
            if isinstance(tall, (int, float)) and float(tall) <= 0.0:
                errors.append("dungeon_summoner.max_height_m must be positive")

        spots = sections["mandelbrot_spots"]
        if not isinstance(spots, dict):
            errors.append("mandelbrot_spots: must be an object")
        else:
            spot_list = spots.get("spots")
            if not isinstance(spot_list, list) or len(spot_list) < 1:
                errors.append("mandelbrot_spots.spots must be a non-empty array")
            else:
                for i, spot in enumerate(spot_list):
                    if not isinstance(spot, dict) or not str(spot.get("name", "")).strip():
                        errors.append(f"mandelbrot_spots.spots[{i}]: name required")
                        break
        return errors

    def _validate_docs(self) -> list[str]:
        errors = validate_mod.validate_combat_data(
            self.attacks_doc, self.table_doc, self.behaviours_doc
        )
        try:
            sections = self._collect_noncombat()
        except (ValueError, TypeError) as exc:
            errors.append(str(exc))
            return errors
        errors.extend(self._validate_noncombat(sections))
        return errors

    def validate_now(self) -> bool:
        try:
            self._flush_all_forms()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc), parent=self)
            return False
        errors = self._validate_docs()
        if errors:
            msg = f"{len(errors)} problem(s):\n\n" + "\n".join(f"• {e}" for e in errors[:40])
            if len(errors) > 40:
                msg += f"\n… and {len(errors) - 40} more"
            messagebox.showerror("Validation failed", msg, parent=self)
            self._status.set(f"Validation failed ({len(errors)} errors)")
            return False
        messagebox.showinfo("Validation", "OK — gamedata is valid.", parent=self)
        self._status.set("Validation OK")
        return True

    def save_to_disk(self) -> None:
        try:
            self._flush_all_forms()
        except ValueError as exc:
            messagebox.showerror("Cannot save", str(exc), parent=self)
            return

        self._normalize_docs_for_save()
        try:
            noncombat = self._collect_noncombat()
        except (ValueError, TypeError) as exc:
            messagebox.showerror("Cannot save", str(exc), parent=self)
            return

        errors = self._validate_docs()
        if errors:
            msg = (
                "Refusing to save — validation failed:\n\n"
                + "\n".join(f"• {e}" for e in errors[:40])
            )
            if len(errors) > 40:
                msg += f"\n… and {len(errors) - 40} more"
            messagebox.showerror("Save refused", msg, parent=self)
            self._status.set(f"Save refused ({len(errors)} errors)")
            return

        try:
            attacks_out: dict[str, Any] = {
                "attacks": {
                    aid: _reorder_keys(atk, ATTACK_FIELD_ORDER)
                    if isinstance(atk, dict)
                    else atk
                    for aid, atk in sorted(
                        self.attacks_doc["attacks"].items(), key=lambda kv: kv[0]
                    )
                },
            }
            for key, value in self.attacks_doc.items():
                if key in ("_docs",) or key in attacks_out:
                    continue
                attacks_out[key] = value

            bmap = _behaviours_map(self.behaviours_doc)
            behaviours_out: dict[str, Any] = {
                "behaviours": {
                    bid: _reorder_keys(row, BEHAVIOUR_FIELD_ORDER)
                    for bid, row in sorted(bmap.items(), key=lambda kv: kv[0])
                },
            }
            for key, value in self.behaviours_doc.items():
                if key in ("_docs",) or key in behaviours_out:
                    continue
                behaviours_out[key] = value

            templates = self.table_doc.get("templates", {})
            assert isinstance(templates, dict)
            cleaned_templates: dict[str, Any] = {}
            for tid, tmpl in templates.items():
                if not isinstance(tmpl, dict):
                    cleaned_templates[tid] = tmpl
                    continue
                row = {
                    k: v
                    for k, v in tmpl.items()
                    if k not in validate_mod.FORBIDDEN_PREY_KEYS
                }
                cleaned_templates[tid] = _reorder_keys(row, TEMPLATE_FIELD_ORDER)
            monsters = self.table_doc.get("monsters", [])
            assert isinstance(monsters, list)
            cleaned_monsters: list[Any] = []
            for m in monsters:
                if not isinstance(m, dict):
                    cleaned_monsters.append(m)
                    continue
                row = {
                    k: v
                    for k, v in m.items()
                    if k not in validate_mod.FORBIDDEN_PREY_KEYS
                }
                cleaned_monsters.append(_reorder_keys(row, MONSTER_CORE_ORDER))
            table_out: dict[str, Any] = {
                "templates": cleaned_templates,
                "monsters": cleaned_monsters,
            }
            for key, value in self.table_doc.items():
                if key in ("_docs",) or key in table_out:
                    continue
                table_out[key] = value

            root: dict[str, Any] = {
                "schema_version": int(
                    self._gamedata_root.get("schema_version", gd.SCHEMA_VERSION)
                ),
                "attacks": attacks_out["attacks"],
                "behaviours": behaviours_out["behaviours"],
                "templates": table_out["templates"],
                "monsters": table_out["monsters"],
                **noncombat,
            }
            # Preserve any unknown top-level keys from the prior document.
            for key, value in self._gamedata_root.items():
                if key not in root:
                    root[key] = value

            gd.save_gamedata(root)
            self._gamedata_root = root
            self.attacks_doc = attacks_out
            self.behaviours_doc = behaviours_out
            self.table_doc = table_out
        except (OSError, ValueError, TypeError) as exc:
            messagebox.showerror("Save failed", str(exc), parent=self)
            raise

        disk_root = gd.load_gamedata()
        disk_errors = validate_mod.validate_combat_data(
            gd.attacks_doc(disk_root),
            gd.table_doc(disk_root),
            gd.behaviours_doc(disk_root),
        )
        disk_errors.extend(
            self._validate_noncombat(
                {
                    "items": disk_root.get("items") or {},
                    "craft_recipes": disk_root.get("craft_recipes") or {},
                    "build_recipes": disk_root.get("build_recipes") or {},
                    "abilities": disk_root.get("abilities") or {},
                    "district_gems": disk_root.get("district_gems") or {},
                    "ability_constants": disk_root.get("ability_constants") or {},
                    "chest_loot": disk_root.get("chest_loot") or {},
                    "recipe_sites": disk_root.get("recipe_sites") or {},
                    "zoo": disk_root.get("zoo") or {},
                    "crypt": disk_root.get("crypt") or {},
                    "dungeon_summoner": disk_root.get("dungeon_summoner") or {},
                    "mandelbrot_spots": disk_root.get("mandelbrot_spots") or {},
                }
            )
        )
        if disk_errors:
            messagebox.showerror(
                "Post-save validation failed",
                "File was written but validation failed:\n\n"
                + "\n".join(f"• {e}" for e in disk_errors[:40]),
                parent=self,
            )
            self._status.set("Saved but post-save validation failed")
            return

        self._dirty = False
        self._status.set(f"Saved → {GAMEDATA_PATH.name}")
        messagebox.showinfo("Saved", "gamedata.json saved and validated.", parent=self)

    def _normalize_docs_for_save(self) -> None:
        attacks = self.attacks_doc.get("attacks", {})
        assert isinstance(attacks, dict)
        for aid, atk in list(attacks.items()):
            if isinstance(atk, dict):
                atk["id"] = aid
        for bid, row in _behaviours_map(self.behaviours_doc).items():
            row["id"] = bid

    def open_html_report(self) -> None:
        if self._dirty:
            if not messagebox.askyesno(
                "Unsaved changes",
                "There are unsaved changes. Generate HTML from the last saved "
                "files on disk anyway?",
                parent=self,
            ):
                return
        try:
            proc = subprocess.run(
                [sys.executable, str(RENDER_SCRIPT)],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            messagebox.showerror("HTML report failed", str(exc), parent=self)
            return
        if proc.returncode != 0:
            messagebox.showerror(
                "HTML report failed",
                (proc.stderr or proc.stdout or "render_combat_tables.py failed").strip(),
                parent=self,
            )
            return
        self._status.set(f"HTML report → {HTML_PATH}")

    def _on_quit(self) -> None:
        if self._dirty:
            if not messagebox.askyesno(
                "Quit",
                "Discard unsaved changes and quit?",
                parent=self,
            ):
                return
        self.destroy()


def _smoke_assert_preview_live_refresh(app: GameDataEditor) -> None:
    """Assert EFFECTIVE STATS rebuilds from in-memory form edits (no save/reselect)."""
    assert app._monster_preview is not None
    assert app._monster_template_check is not None
    if app._selected_monster is None:
        raise RuntimeError("smoke: expected a monster to be selected after load")

    def preview_text() -> str:
        assert app._monster_preview is not None
        return app._monster_preview.get("1.0", "end-1c")

    if "faction:" not in preview_text():
        raise RuntimeError("smoke: EFFECTIVE STATS missing faction line")
    start_faction = app._monster_faction.get()
    alt_faction = next(
        (f for f in ALLOWED_FACTIONS if f != start_faction),
        None,
    )
    if alt_faction is None:
        raise RuntimeError("smoke: need at least two factions to toggle")
    app._monster_faction.set(alt_faction)
    app.update_idletasks()
    if f"faction: {alt_faction}" not in preview_text():
        raise RuntimeError(
            f"smoke: changing faction to {alt_faction!r} did not update EFFECTIVE STATS"
        )
    list_sel = app._monster_list.curselection()
    if not list_sel:
        raise RuntimeError("smoke: monster list lost selection after faction edit")
    list_label = app._monster_list.get(list_sel[0])
    if alt_faction not in list_label:
        raise RuntimeError(
            f"smoke: monster list label did not show faction {alt_faction!r}: {list_label!r}"
        )
    app._monster_faction.set(start_faction)
    app.update_idletasks()

    app.update_idletasks()
    before = preview_text()
    if "BODY" not in before:
        raise RuntimeError(f"smoke: expected resolved preview, got:\n{before[:400]}")

    # Scalar override (Entry / StringVar trace → _on_monster_field_change).
    sentinel = 9.87654321
    app._monster_scalar_vars["hp_mult"].set(str(sentinel))
    app.update_idletasks()
    after_scalar = preview_text()
    if f"{sentinel:g}" not in after_scalar:
        raise RuntimeError(
            "smoke: hp_mult override did not update EFFECTIVE STATS live"
        )

    # Template checklist toggle must also refresh (was the main regression).
    templates = app.table_doc.get("templates", {})
    assert isinstance(templates, dict)
    selected = app._monster_template_check.get_selected()
    if not selected:
        raise RuntimeError("smoke: selected monster has no templates")
    candidates = [t for t in templates if t not in selected]
    if not candidates:
        raise RuntimeError("smoke: need an unselected template to toggle")
    toggle = candidates[0]
    before_templates_line = [
        line for line in after_scalar.splitlines() if line.strip().startswith("templates:")
    ]
    app._monster_template_check._vars[toggle].set(True)
    app.update_idletasks()
    after_templates = preview_text()
    after_templates_line = [
        line for line in after_templates.splitlines() if line.strip().startswith("templates:")
    ]
    if not after_templates_line or toggle not in after_templates_line[0]:
        raise RuntimeError(
            f"smoke: toggling template {toggle!r} did not update EFFECTIVE STATS live"
        )
    if before_templates_line == after_templates_line:
        raise RuntimeError("smoke: templates line unchanged after checklist toggle")

    # Body attacks_extra must change effective attacks live.
    attacks_doc = app.attacks_doc.get("attacks", {})
    assert isinstance(attacks_doc, dict)
    attack_ids = sorted(attacks_doc.keys())
    if not attack_ids:
        raise RuntimeError("smoke: gamedata has no attack ids")
    atk_check = app._monster_list_checks["attacks"]
    atk_mode = app._monster_list_modes["attacks"]
    # Reset to Inherit so behaviour-derived baseline is visible, then Extra-add.
    atk_mode.set("inherit")
    atk_check.clear()
    app.update_idletasks()
    baseline_preview = preview_text()
    baseline_effective = _smoke_effective_attack_ids(baseline_preview)
    # Prefer an attack not already in the behaviour-derived effective set.
    extra_candidate = next(
        (aid for aid in attack_ids if aid not in baseline_effective),
        attack_ids[0],
    )
    atk_mode.set("extra")
    if extra_candidate not in atk_check._vars:
        atk_check.set_options(list(atk_check._vars.keys()) + [extra_candidate])
        app._wire_checklist_monster_preview(atk_check)
    atk_check._vars[extra_candidate].set(True)
    app.update_idletasks()
    after_extra = preview_text()
    after_effective = _smoke_effective_attack_ids(after_extra)
    if extra_candidate not in after_effective:
        raise RuntimeError(
            f"smoke: attacks_extra {extra_candidate!r} did not appear in EFFECTIVE STATS"
        )
    if after_effective == baseline_effective and extra_candidate not in baseline_effective:
        raise RuntimeError("smoke: effective attacks unchanged after attacks_extra toggle")
    if "body: Extra +" not in after_extra:
        raise RuntimeError("smoke: preview missing body Extra annotation")

    # Selection switch must show the newly selected monster's preview.
    monsters = app.table_doc.get("monsters", [])
    assert isinstance(monsters, list)
    ids = [
        m["id"]
        for m in monsters
        if isinstance(m, dict) and isinstance(m.get("id"), str)
    ]
    if len(ids) < 2:
        raise RuntimeError("smoke: need at least two monsters to test selection switch")
    other = next(mid for mid in ids if mid != app._selected_monster)
    app._flush_monster_form()
    app._load_monster_form(other)
    app.update_idletasks()
    switched = preview_text()
    if app._selected_monster != other or f"  {other}\n" not in switched:
        raise RuntimeError(
            f"smoke: selecting monster {other!r} did not update EFFECTIVE STATS"
        )


def _smoke_effective_attack_ids(preview: str) -> list[str]:
    """Parse attack ids under the effective-attacks block in the monster preview text."""
    lines = preview.splitlines()
    collecting = False
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("effective") and "damage" in stripped and stripped.endswith(":"):
            collecting = True
            continue
        if collecting:
            if stripped.startswith("• "):
                # "• melee" — ignore the following "vs player / vs mob" detail lines.
                out.append(stripped[2:].strip())
                continue
            if stripped.startswith("TAGS") or stripped.startswith("ATTACKS"):
                break
            if stripped.startswith("vs "):
                continue
            if stripped and not stripped.startswith("("):
                # Next heading or unrelated block.
                if stripped.endswith(":") or stripped.isupper():
                    break
    return out


def _smoke_assert_duel_buttons(app: GameDataEditor) -> None:
    monsters = app.table_doc.get("monsters") or []
    if not isinstance(monsters, list) or not monsters:
        raise RuntimeError("smoke: no monsters loaded")
    mid = str(monsters[0]["id"])
    app._refresh_monster_list(mid)
    app.update()
    root = app._assemble_sim_root()
    fighters, attack_rows = duel_sim.load_fighter_defs_from_root(root)
    report = duel_sim.format_fighter_report(
        mid, fighters, attack_rows, duels=2, same_tier_only=True
    )
    if "AGGREGATE" not in report:
        raise RuntimeError("smoke: duel report missing AGGREGATE")
    if mid not in report:
        raise RuntimeError("smoke: duel report missing fighter id")


def _smoke_assert_noncombat_loaded(app: GameDataEditor) -> None:
    assert app._items_panel is not None
    assert app._craft_panel is not None
    assert app._build_panel is not None
    assert app._abilities_panel is not None
    assert app._district_panel is not None
    assert app._constants_panel is not None
    assert app._chest_panel is not None
    assert app._recipe_sites_panel is not None
    assert app._zoo_panel is not None
    assert app._crypt_panel is not None
    assert app._dungeon_summoner_panel is not None
    assert app._spots_panel is not None
    items = app._items_panel.get_data()
    if "gem_quartz" not in items:
        raise RuntimeError("smoke: items panel missing gem_quartz")
    builds = app._build_panel.get_data()
    if "cottage" not in builds:
        raise RuntimeError("smoke: build panel missing cottage")
    districts = app._district_panel.get_data()
    if "theme_totals" not in districts:
        raise RuntimeError("smoke: district panel missing theme_totals")
    zoo = app._zoo_panel.get_data()
    if float(zoo.get("base_spawn_interval_sec", 0.0)) <= 0.0:
        raise RuntimeError("smoke: zoo panel missing base_spawn_interval_sec")
    crypt = app._crypt_panel.get_data()
    if int(crypt.get("alive_cap", 0)) < 1:
        raise RuntimeError("smoke: crypt panel missing alive_cap")
    if str(crypt.get("faction", "")) != "undead":
        raise RuntimeError("smoke: crypt faction should be undead")
    dungeon_summoner = app._dungeon_summoner_panel.get_data()
    if int(dungeon_summoner.get("alive_cap", 0)) < 1:
        raise RuntimeError("smoke: dungeon_summoner panel missing alive_cap")
    spots = app._spots_panel.get_data()
    spot_list = spots.get("spots")
    if not isinstance(spot_list, list) or len(spot_list) < 80:
        raise RuntimeError("smoke: expected >= 80 mandelbrot spots in editor")
    errors = app._validate_docs()
    if errors:
        raise RuntimeError(
            "smoke: full gamedata validation failed:\n" + "\n".join(errors[:20])
        )


def _validate_forever_war_section(
    name: str,
    section: Any,
    schema: dict[str, type],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(section, dict) or not section:
        errors.append(f"{name}: must be a non-empty object")
        return errors
    for key, kind in schema.items():
        if key not in section:
            errors.append(f"{name}.{key}: required")
            continue
        value = section[key]
        if kind is float:
            if not isinstance(value, (int, float)):
                errors.append(f"{name}.{key}: must be a number")
            elif float(value) < 0.0:
                errors.append(f"{name}.{key}: must be >= 0")
        elif kind is int:
            if not isinstance(value, int) or isinstance(value, bool):
                errors.append(f"{name}.{key}: must be an integer")
            elif int(value) < 0:
                errors.append(f"{name}.{key}: must be >= 0")
        elif kind is str:
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{name}.{key}: must be a non-empty string")
        else:
            errors.append(f"{name}.{key}: unsupported schema type")
    return errors


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    smoke = "--smoke" in args
    try:
        app = GameDataEditor()
    except (OSError, json.JSONDecodeError, TypeError, FileNotFoundError, ValueError) as exc:
        print(f"ERROR: failed to start editor: {exc}", file=sys.stderr)
        return 1
    if smoke:
        app.update()
        try:
            _smoke_assert_preview_live_refresh(app)
            _smoke_assert_noncombat_loaded(app)
            _smoke_assert_duel_buttons(app)
        except (RuntimeError, KeyError, AssertionError, ValueError, TypeError) as exc:
            print(f"SMOKE_FAIL: {exc}", file=sys.stderr)
            app.destroy()
            return 1
        print(
            "SMOKE_OK: gamedata editor created; combat preview + non-combat + duels OK"
        )
        app.after(200, app.destroy)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
