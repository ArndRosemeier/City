"""Reusable tkinter panels for non-combat slices of assets/gamedata.json."""

from __future__ import annotations

import json
import tkinter as tk
from collections.abc import Callable
from dataclasses import dataclass
from tkinter import messagebox, simpledialog, ttk
from typing import Any


@dataclass(frozen=True)
class FieldSpec:
    key: str
    label: str
    kind: str  # str | int | float | bool | csv_list | json
    required: bool = False
    default: Any = None
    width: int = 48
    height: int = 6  # json text rows


def _parse_json_text(raw: str, field: str) -> Any:
    text = raw.strip()
    if text == "":
        raise ValueError(f"{field}: required JSON is empty")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{field}: invalid JSON ({exc})") from exc


def _format_json(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False)


class IdMapPanel:
    """Left id list + right form for a dict[str, dict] section."""

    def __init__(
        self,
        parent: ttk.Frame,
        *,
        title: str,
        fields: tuple[FieldSpec, ...],
        on_dirty: Callable[[], None],
        new_row_factory: Callable[[str], dict[str, Any]],
        id_label: str = "id",
    ) -> None:
        self._fields = fields
        self._on_dirty = on_dirty
        self._new_row_factory = new_row_factory
        self._id_label = id_label
        self._data: dict[str, dict[str, Any]] = {}
        self._selected: str | None = None
        self._loading = False
        self._widgets: dict[str, tk.Variable | tk.Text] = {}

        paned = ttk.Panedwindow(parent, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=4)
        right = ttk.Frame(paned, padding=4)
        paned.add(left, weight=1)
        paned.add(right, weight=3)

        ttk.Label(left, text=title).pack(anchor="w")
        self._list = tk.Listbox(left, exportselection=False)
        self._list.pack(fill="both", expand=True)
        self._list.bind("<<ListboxSelect>>", self._on_select)
        btns = ttk.Frame(left)
        btns.pack(fill="x", pady=4)
        ttk.Button(btns, text="Add", command=self._add).pack(side="left", padx=2)
        ttk.Button(btns, text="Delete", command=self._delete).pack(side="left", padx=2)
        ttk.Button(btns, text="Rename", command=self._rename).pack(side="left", padx=2)

        form = ttk.Frame(right)
        form.pack(fill="both", expand=True)
        form.columnconfigure(1, weight=1)
        row = 0
        id_var = tk.StringVar()
        self._widgets["__id__"] = id_var
        ttk.Label(form, text=id_label).grid(row=row, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=id_var, state="readonly").grid(
            row=row, column=1, sticky="ew", pady=2
        )
        row += 1
        for spec in fields:
            ttk.Label(form, text=spec.label).grid(row=row, column=0, sticky="nw", pady=2)
            if spec.kind == "bool":
                var = tk.BooleanVar()
                self._widgets[spec.key] = var
                ttk.Checkbutton(form, variable=var, command=self._mark_dirty).grid(
                    row=row, column=1, sticky="w", pady=2
                )
            elif spec.kind == "json":
                text = tk.Text(form, height=spec.height, width=spec.width, wrap="none")
                self._widgets[spec.key] = text
                text.grid(row=row, column=1, sticky="nsew", pady=2)
                text.bind("<<Modified>>", self._on_text_modified)
                form.rowconfigure(row, weight=1)
            else:
                var = tk.StringVar()
                self._widgets[spec.key] = var
                var.trace_add("write", self._mark_dirty)
                ttk.Entry(form, textvariable=var, width=spec.width).grid(
                    row=row, column=1, sticky="ew", pady=2
                )
            row += 1

    def set_data(self, data: dict[str, Any]) -> None:
        self.flush()
        cleaned: dict[str, dict[str, Any]] = {}
        for key, value in data.items():
            if isinstance(key, str) and isinstance(value, dict):
                cleaned[key] = dict(value)
        self._data = cleaned
        self._selected = None
        self._refresh_list()
        if self._data:
            first = sorted(self._data.keys())[0]
            self._select_id(first)

    def get_data(self) -> dict[str, dict[str, Any]]:
        self.flush()
        return {k: dict(v) for k, v in sorted(self._data.items(), key=lambda kv: kv[0])}

    def flush(self) -> None:
        if self._selected is None:
            return
        row = self._read_form(self._selected)
        self._data[self._selected] = row

    def _mark_dirty(self, *_args: object) -> None:
        if self._loading:
            return
        self._on_dirty()

    def _on_text_modified(self, event: object) -> None:
        widget = event.widget  # type: ignore[attr-defined]
        if bool(widget.edit_modified()):
            widget.edit_modified(False)
            self._mark_dirty()

    def _refresh_list(self) -> None:
        self._list.delete(0, "end")
        for key in sorted(self._data.keys()):
            self._list.insert("end", key)

    def _select_id(self, key: str) -> None:
        keys = sorted(self._data.keys())
        if key not in keys:
            return
        idx = keys.index(key)
        self._list.selection_clear(0, "end")
        self._list.selection_set(idx)
        self._list.see(idx)
        self._load_form(key)

    def _on_select(self, _event: object | None = None) -> None:
        sel = self._list.curselection()
        if not sel:
            return
        key = self._list.get(sel[0])
        assert isinstance(key, str)
        try:
            self.flush()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc))
            if self._selected is not None:
                self._select_id(self._selected)
            return
        self._load_form(key)

    def _load_form(self, key: str) -> None:
        self._loading = True
        try:
            self._selected = key
            id_var = self._widgets["__id__"]
            assert isinstance(id_var, tk.StringVar)
            id_var.set(key)
            row = self._data.get(key, {})
            for spec in self._fields:
                widget = self._widgets[spec.key]
                value = row.get(spec.key, spec.default)
                if spec.kind == "bool":
                    assert isinstance(widget, tk.BooleanVar)
                    widget.set(bool(value))
                elif spec.kind == "json":
                    assert isinstance(widget, tk.Text)
                    widget.delete("1.0", "end")
                    widget.insert("1.0", _format_json(value if value is not None else spec.default))
                    widget.edit_modified(False)
                elif spec.kind == "csv_list":
                    assert isinstance(widget, tk.StringVar)
                    if isinstance(value, list):
                        widget.set(", ".join(str(x) for x in value))
                    else:
                        widget.set("" if value is None else str(value))
                else:
                    assert isinstance(widget, tk.StringVar)
                    if value is None:
                        widget.set("" if spec.default is None else str(spec.default))
                    else:
                        widget.set(str(value))
        finally:
            self._loading = False

    def _read_form(self, key: str) -> dict[str, Any]:
        row: dict[str, Any] = {}
        for spec in self._fields:
            widget = self._widgets[spec.key]
            if spec.kind == "bool":
                assert isinstance(widget, tk.BooleanVar)
                row[spec.key] = bool(widget.get())
                continue
            if spec.kind == "json":
                assert isinstance(widget, tk.Text)
                raw = widget.get("1.0", "end-1c")
                if raw.strip() == "" and not spec.required:
                    if spec.default is not None:
                        row[spec.key] = copy_default(spec.default)
                    continue
                parsed = _parse_json_text(raw, spec.key)
                row[spec.key] = parsed
                continue
            assert isinstance(widget, tk.StringVar)
            text = widget.get().strip()
            if text == "":
                if spec.required:
                    raise ValueError(f"{spec.key}: required")
                if spec.default is not None:
                    row[spec.key] = copy_default(spec.default)
                continue
            if spec.kind == "str":
                row[spec.key] = text
            elif spec.kind == "int":
                try:
                    row[spec.key] = int(text, 10)
                except ValueError as exc:
                    raise ValueError(f"{spec.key}: expected integer") from exc
            elif spec.kind == "float":
                try:
                    row[spec.key] = float(text)
                except ValueError as exc:
                    raise ValueError(f"{spec.key}: expected number") from exc
            elif spec.kind == "csv_list":
                parts = [p.strip() for p in text.split(",") if p.strip()]
                row[spec.key] = parts
            else:
                raise ValueError(f"unknown field kind {spec.kind}")
        return row

    def _add(self) -> None:
        try:
            self.flush()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc))
            return
        new_id = simpledialog.askstring("Add", f"New {self._id_label}:", parent=self._list)
        if not new_id:
            return
        new_id = new_id.strip()
        if not new_id:
            return
        if new_id in self._data:
            messagebox.showerror("Add failed", f"{new_id!r} already exists")
            return
        self._data[new_id] = self._new_row_factory(new_id)
        self._refresh_list()
        self._select_id(new_id)
        self._mark_dirty()

    def _delete(self) -> None:
        if self._selected is None:
            return
        key = self._selected
        if not messagebox.askyesno("Delete", f"Delete {key!r}?", parent=self._list):
            return
        del self._data[key]
        self._selected = None
        self._refresh_list()
        if self._data:
            self._select_id(sorted(self._data.keys())[0])
        else:
            self._clear_form()
        self._mark_dirty()

    def _rename(self) -> None:
        if self._selected is None:
            return
        old = self._selected
        try:
            self.flush()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc))
            return
        new_id = simpledialog.askstring(
            "Rename", f"Rename {old!r} to:", initialvalue=old, parent=self._list
        )
        if not new_id:
            return
        new_id = new_id.strip()
        if not new_id or new_id == old:
            return
        if new_id in self._data:
            messagebox.showerror("Rename failed", f"{new_id!r} already exists")
            return
        self._data[new_id] = self._data.pop(old)
        self._selected = new_id
        self._refresh_list()
        self._select_id(new_id)
        self._mark_dirty()

    def _clear_form(self) -> None:
        self._loading = True
        try:
            id_var = self._widgets["__id__"]
            assert isinstance(id_var, tk.StringVar)
            id_var.set("")
            for spec in self._fields:
                widget = self._widgets[spec.key]
                if spec.kind == "bool":
                    assert isinstance(widget, tk.BooleanVar)
                    widget.set(False)
                elif spec.kind == "json":
                    assert isinstance(widget, tk.Text)
                    widget.delete("1.0", "end")
                    widget.edit_modified(False)
                else:
                    assert isinstance(widget, tk.StringVar)
                    widget.set("")
        finally:
            self._loading = False


def copy_default(value: Any) -> Any:
    if isinstance(value, (dict, list)):
        return json.loads(json.dumps(value))
    return value


class NestedJsonPanel:
    """Edit a whole dict section as structured scalars + JSON blobs."""

    def __init__(
        self,
        parent: ttk.Frame,
        *,
        scalar_fields: tuple[FieldSpec, ...],
        json_fields: tuple[FieldSpec, ...],
        on_dirty: Callable[[], None],
    ) -> None:
        self._scalar_fields = scalar_fields
        self._json_fields = json_fields
        self._on_dirty = on_dirty
        self._loading = False
        self._scalars: dict[str, tk.Variable] = {}
        self._json_widgets: dict[str, tk.Text] = {}

        form = ttk.Frame(parent, padding=8)
        form.pack(fill="both", expand=True)
        form.columnconfigure(1, weight=1)
        row = 0
        for spec in scalar_fields:
            ttk.Label(form, text=spec.label).grid(row=row, column=0, sticky="w", pady=2)
            if spec.kind == "bool":
                var: tk.Variable = tk.BooleanVar()
                ttk.Checkbutton(form, variable=var, command=self._mark_dirty).grid(
                    row=row, column=1, sticky="w", pady=2
                )
            else:
                var = tk.StringVar()
                var.trace_add("write", self._mark_dirty)
                ttk.Entry(form, textvariable=var, width=spec.width).grid(
                    row=row, column=1, sticky="ew", pady=2
                )
            self._scalars[spec.key] = var
            row += 1
        for spec in json_fields:
            ttk.Label(form, text=spec.label).grid(row=row, column=0, sticky="nw", pady=2)
            text = tk.Text(form, height=spec.height, width=spec.width, wrap="none")
            text.grid(row=row, column=1, sticky="nsew", pady=2)
            text.bind("<<Modified>>", self._on_text_modified)
            self._json_widgets[spec.key] = text
            form.rowconfigure(row, weight=1)
            row += 1

    def set_data(self, data: dict[str, Any]) -> None:
        self._loading = True
        try:
            for spec in self._scalar_fields:
                var = self._scalars[spec.key]
                value = data.get(spec.key, spec.default)
                if spec.kind == "bool":
                    assert isinstance(var, tk.BooleanVar)
                    var.set(bool(value))
                else:
                    assert isinstance(var, tk.StringVar)
                    var.set("" if value is None else str(value))
            for spec in self._json_fields:
                text = self._json_widgets[spec.key]
                value = data.get(spec.key, spec.default)
                text.delete("1.0", "end")
                text.insert("1.0", _format_json(value if value is not None else {}))
                text.edit_modified(False)
        finally:
            self._loading = False

    def get_data(self) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for spec in self._scalar_fields:
            var = self._scalars[spec.key]
            if spec.kind == "bool":
                assert isinstance(var, tk.BooleanVar)
                out[spec.key] = bool(var.get())
                continue
            assert isinstance(var, tk.StringVar)
            text = var.get().strip()
            if text == "":
                if spec.required:
                    raise ValueError(f"{spec.key}: required")
                continue
            if spec.kind == "str":
                out[spec.key] = text
            elif spec.kind == "int":
                out[spec.key] = int(text, 10)
            elif spec.kind == "float":
                out[spec.key] = float(text)
            elif spec.kind == "csv_list":
                out[spec.key] = [p.strip() for p in text.split(",") if p.strip()]
            else:
                raise ValueError(f"unsupported scalar kind {spec.kind}")
        for spec in self._json_fields:
            text = self._json_widgets[spec.key].get("1.0", "end-1c")
            parsed = _parse_json_text(text, spec.key)
            if not isinstance(parsed, (dict, list)):
                raise ValueError(f"{spec.key}: expected object or array")
            out[spec.key] = parsed
        return out

    def _mark_dirty(self, *_args: object) -> None:
        if not self._loading:
            self._on_dirty()

    def _on_text_modified(self, event: object) -> None:
        widget = event.widget  # type: ignore[attr-defined]
        if bool(widget.edit_modified()):
            widget.edit_modified(False)
            self._mark_dirty()


class SpotsPanel:
    """Mandelbrot spots meta + spot list editor."""

    def __init__(self, parent: ttk.Frame, *, on_dirty: Callable[[], None]) -> None:
        self._on_dirty = on_dirty
        self._loading = False
        self._spots: list[dict[str, Any]] = []
        self._selected: int | None = None

        outer = ttk.Panedwindow(parent, orient="vertical")
        outer.pack(fill="both", expand=True)
        meta = ttk.Frame(outer, padding=6)
        body = ttk.Frame(outer, padding=4)
        outer.add(meta, weight=1)
        outer.add(body, weight=4)

        self._scale_max = tk.StringVar()
        self._scale_min = tk.StringVar()
        self._view_cx = tk.StringVar()
        self._view_cy = tk.StringVar()
        self._view_half = tk.StringVar()
        for var in (
            self._scale_max,
            self._scale_min,
            self._view_cx,
            self._view_cy,
            self._view_half,
        ):
            var.trace_add("write", self._mark_dirty)

        grid = ttk.Frame(meta)
        grid.pack(fill="x")
        for i, (label, var) in enumerate(
            (
                ("scale_max", self._scale_max),
                ("scale_min", self._scale_min),
                ("view.cx", self._view_cx),
                ("view.cy", self._view_cy),
                ("view.half", self._view_half),
            )
        ):
            ttk.Label(grid, text=label).grid(row=0, column=i * 2, sticky="w", padx=2)
            ttk.Entry(grid, textvariable=var, width=16).grid(
                row=0, column=i * 2 + 1, sticky="ew", padx=2
            )

        paned = ttk.Panedwindow(body, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=4)
        right = ttk.Frame(paned, padding=4)
        paned.add(left, weight=2)
        paned.add(right, weight=3)

        ttk.Label(left, text="Spots").pack(anchor="w")
        self._list = tk.Listbox(left, exportselection=False)
        self._list.pack(fill="both", expand=True)
        self._list.bind("<<ListboxSelect>>", self._on_select)
        btns = ttk.Frame(left)
        btns.pack(fill="x", pady=4)
        ttk.Button(btns, text="Add", command=self._add).pack(side="left", padx=2)
        ttk.Button(btns, text="Delete", command=self._delete).pack(side="left", padx=2)

        form = ttk.Frame(right)
        form.pack(fill="both", expand=True)
        form.columnconfigure(1, weight=1)
        self._name = tk.StringVar()
        self._cx = tk.StringVar()
        self._cy = tk.StringVar()
        self._scale = tk.StringVar()
        for i, (label, var) in enumerate(
            (("name", self._name), ("cx", self._cx), ("cy", self._cy), ("scale", self._scale))
        ):
            var.trace_add("write", self._mark_dirty)
            ttk.Label(form, text=label).grid(row=i, column=0, sticky="w", pady=2)
            ttk.Entry(form, textvariable=var).grid(row=i, column=1, sticky="ew", pady=2)
        self._count = tk.StringVar(value="0 spots")
        ttk.Label(form, textvariable=self._count).grid(row=4, column=0, columnspan=2, sticky="w")

    def set_data(self, data: dict[str, Any]) -> None:
        self._loading = True
        try:
            self._scale_max.set(str(data.get("scale_max", "")))
            self._scale_min.set(str(data.get("scale_min", "")))
            view = data.get("default_view", {})
            if not isinstance(view, dict):
                view = {}
            self._view_cx.set(str(view.get("cx", "")))
            self._view_cy.set(str(view.get("cy", "")))
            self._view_half.set(str(view.get("half", "")))
            spots = data.get("spots", [])
            self._spots = [dict(s) for s in spots if isinstance(s, dict)]
            self._selected = None
            self._refresh_list()
            if self._spots:
                self._select_index(0)
            else:
                self._clear_form()
        finally:
            self._loading = False

    def get_data(self) -> dict[str, Any]:
        self.flush()
        return {
            "scale_max": float(self._scale_max.get().strip()),
            "scale_min": float(self._scale_min.get().strip()),
            "default_view": {
                "cx": float(self._view_cx.get().strip()),
                "cy": float(self._view_cy.get().strip()),
                "half": float(self._view_half.get().strip()),
            },
            "spots": [dict(s) for s in self._spots],
        }

    def flush(self) -> None:
        if self._selected is None:
            return
        name = self._name.get().strip()
        if not name:
            raise ValueError("spot name: required")
        self._spots[self._selected] = {
            "name": name,
            "cx": self._cx.get().strip(),
            "cy": self._cy.get().strip(),
            "scale": self._scale.get().strip(),
        }
        self._refresh_list(keep_selected=True)

    def _mark_dirty(self, *_args: object) -> None:
        if not self._loading:
            self._on_dirty()

    def _refresh_list(self, keep_selected: bool = False) -> None:
        sel = self._selected if keep_selected else None
        self._list.delete(0, "end")
        for i, spot in enumerate(self._spots):
            self._list.insert("end", f"{i:03d}  {spot.get('name', '?')}")
        self._count.set(f"{len(self._spots)} spots")
        if sel is not None and 0 <= sel < len(self._spots):
            self._list.selection_set(sel)
            self._list.see(sel)

    def _select_index(self, idx: int) -> None:
        self._list.selection_clear(0, "end")
        self._list.selection_set(idx)
        self._list.see(idx)
        self._load_form(idx)

    def _on_select(self, _event: object | None = None) -> None:
        sel = self._list.curselection()
        if not sel:
            return
        idx = int(sel[0])
        try:
            self.flush()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc))
            if self._selected is not None:
                self._select_index(self._selected)
            return
        self._load_form(idx)

    def _load_form(self, idx: int) -> None:
        self._loading = True
        try:
            self._selected = idx
            spot = self._spots[idx]
            self._name.set(str(spot.get("name", "")))
            self._cx.set(str(spot.get("cx", "")))
            self._cy.set(str(spot.get("cy", "")))
            self._scale.set(str(spot.get("scale", "")))
        finally:
            self._loading = False

    def _clear_form(self) -> None:
        self._loading = True
        try:
            self._selected = None
            self._name.set("")
            self._cx.set("")
            self._cy.set("")
            self._scale.set("")
        finally:
            self._loading = False

    def _add(self) -> None:
        try:
            self.flush()
        except ValueError as exc:
            messagebox.showerror("Invalid fields", str(exc))
            return
        self._spots.append({"name": "New Spot", "cx": "0.0", "cy": "0.0", "scale": "0.001"})
        self._refresh_list()
        self._select_index(len(self._spots) - 1)
        self._mark_dirty()

    def _delete(self) -> None:
        if self._selected is None:
            return
        idx = self._selected
        if not messagebox.askyesno("Delete", f"Delete spot #{idx}?", parent=self._list):
            return
        del self._spots[idx]
        self._selected = None
        self._refresh_list()
        if self._spots:
            self._select_index(min(idx, len(self._spots) - 1))
        else:
            self._clear_form()
        self._mark_dirty()


ITEM_FIELDS = (
    FieldSpec("display_name", "display_name", "str", required=True),
    FieldSpec("stack_max", "stack_max", "int", required=True, default=99),
    FieldSpec("gem_mat_id", "gem_mat_id", "int"),
    FieldSpec("flags", "flags (csv)", "csv_list", default=[]),
)

CRAFT_FIELDS = (
    FieldSpec("display_name", "display_name", "str", required=True),
    FieldSpec("inputs", "inputs (JSON object)", "json", required=True, default={}, height=8),
    FieldSpec("output_id", "output_id", "str", required=True),
    FieldSpec("output_count", "output_count", "int", required=True, default=1),
)

BUILD_FIELDS = (
    FieldSpec("display_name", "display_name", "str", required=True),
    FieldSpec("hint", "hint", "str", required=True),
    FieldSpec("voxels", "voxels (JSON [[x,y,z,mat],…])", "json", required=True, default=[], height=18),
)

ABILITY_FIELDS = (
    FieldSpec("display_name", "display_name", "str", required=True),
    FieldSpec("kind", "kind", "str", required=True),
    FieldSpec("unlock_cost", "unlock_cost (JSON object)", "json", required=True, default={}, height=6),
    FieldSpec("energy_cost", "energy_cost", "float", required=True, default=0.0),
    FieldSpec("gated", "gated", "bool", default=True),
    FieldSpec("hint", "hint", "str", required=True),
)

DISTRICT_SCALARS = (
    FieldSpec("explore_score", "explore_score", "int", required=True, default=50),
)
DISTRICT_JSON = (
    FieldSpec("theme_totals", "theme_totals (JSON object)", "json", required=True, default={}, height=14),
    FieldSpec(
        "rarity_weights", "rarity_weights (JSON object)", "json", required=True, default={}, height=10
    ),
)

CONSTANTS_SCALARS = (
    FieldSpec("trap_hostile_score", "trap_hostile_score", "int", required=True),
    FieldSpec("boost_duration_sec", "boost_duration_sec", "float", required=True),
    FieldSpec("grow_shrink_duration_sec", "grow_shrink_duration_sec", "float", required=True),
    FieldSpec("shield_drain_per_sec", "shield_drain_per_sec", "float", required=True),
    FieldSpec("minion_max", "minion_max", "int", required=True),
    FieldSpec("minion_duration_sec", "minion_duration_sec", "float", required=True),
)
CONSTANTS_JSON = (
    FieldSpec(
        "starter_unlocks", "starter_unlocks (JSON array)", "json", required=True, default=[], height=4
    ),
    FieldSpec(
        "default_sandbox_builds",
        "default_sandbox_builds (JSON array)",
        "json",
        required=True,
        default=[],
        height=6,
    ),
)

CHEST_SCALARS = (
    FieldSpec("gems_min", "gems_min", "int", required=True),
    FieldSpec("gems_max", "gems_max", "int", required=True),
)
CHEST_JSON = (
    FieldSpec(
        "place_chance_pct",
        "place_chance_pct (JSON object)",
        "json",
        required=True,
        default={},
        height=8,
    ),
)

RECIPE_SITE_SCALARS = (FieldSpec("per_district_max", "per_district_max", "int", required=True),)
RECIPE_SITE_JSON = (
    FieldSpec("chance_pct", "chance_pct (JSON object)", "json", required=True, default={}, height=12),
    FieldSpec(
        "fallback_gems", "fallback_gems (JSON array)", "json", required=True, default=[], height=4
    ),
)

ZOO_SCALARS = (
    FieldSpec("cloak_duration_sec", "cloak_duration_sec", "float", required=True, default=120.0),
    FieldSpec(
        "plate_damage_interval_sec",
        "plate_damage_interval_sec",
        "float",
        required=True,
        default=1.0,
    ),
    FieldSpec(
        "base_spawn_interval_sec",
        "base_spawn_interval_sec",
        "float",
        required=True,
        default=14.0,
    ),
    FieldSpec("spawn_pressure_k", "spawn_pressure_k", "float", required=True, default=0.9),
    FieldSpec("per_territory_cap", "per_territory_cap", "int", required=True, default=2),
    FieldSpec("district_alive_cap", "district_alive_cap", "int", required=True, default=34),
)
ZOO_JSON: tuple[FieldSpec, ...] = ()

CRYPT_SCALARS = (
    FieldSpec("spawn_lift_m", "spawn_lift_m", "float", required=True, default=0.2),
    FieldSpec(
        "base_spawn_interval_sec",
        "base_spawn_interval_sec",
        "float",
        required=True,
        default=30.0,
    ),
    FieldSpec("spawn_pressure_k", "spawn_pressure_k", "float", required=True, default=0.9),
    FieldSpec("alive_cap", "alive_cap", "int", required=True, default=20),
    FieldSpec(
        "first_spawn_fraction",
        "first_spawn_fraction",
        "float",
        required=True,
        default=0.25,
    ),
    FieldSpec("faction", "faction", "str", required=True, default="undead"),
)
CRYPT_JSON: tuple[FieldSpec, ...] = ()
