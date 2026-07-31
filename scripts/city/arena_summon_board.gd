## Wall-mounted Arena summon console — full side width, two portrait rows.
## Factions pack tightly (no spare columns), the block is centered, and mobs toggle
## selection. Summon / Clear sit in a middle faction-style section (same 2-row band).
class_name ArenaSummonBoard
extends "res://scripts/city/ui_3d.gd"

signal summon_batch_requested(monster_ids: PackedStringArray)
signal clear_requested()

const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")
const MonsterIconCacheScript := preload("res://scripts/city/monster_icon_cache.gd")

## Matches the straight outer face between corner fillets (~38 m at 0.5 m voxels).
const PANEL_W := 38.0
## Two portrait rows + faction name strip — same height as the original keypad.
const PANEL_H := 1.45
const GRID_ROWS := 2
## Fixed icon cell width in metres — content packs; unused side space stays empty.
const CELL_M := 0.95
## Control section is one column: Summon (top row) + Clear (bottom row).
const CONTROL_COLS := 1
const BTN_SUMMON := &"summon"
const BTN_CLEAR := &"clear"
const BTN_PREFIX := "mob_"
const HDR_PREFIX := "hdr_"
const DIV_PREFIX := "div_"
const IDLE_TINT := Color.WHITE
const IDLE_BG := Color(0.16, 0.13, 0.12, 1.0)
const SELECTED_BG := Color(0.95, 0.72, 0.18, 1.0)

var _groups: Array[Dictionary] = []
var _id_by_button: Dictionary = {}  ## StringName -> String
var _selected: Dictionary = {}  ## String monster_id -> true
var _icons_ready: bool = false
var _summon_tex: Texture2D = null
var _clear_tex: Texture2D = null


func setup_board(origin: Vector3, face_yaw: float) -> void:
	name = "ArenaSummonBoard"
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.10, 0.08, 0.07, 1.0)
	_summon_tex = _make_summon_texture()
	_clear_tex = _make_clear_texture()
	_groups = MonsterSummonPanelScript.summonable_groups()
	if _groups.is_empty():
		push_error("ArenaSummonBoard: no summonable monsters")
		assert(false, "ArenaSummonBoard: empty roster")
	_rebuild_face()
	begin(origin, face_yaw)
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	_bake_icons()


func _all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for group: Dictionary in _groups:
		out.append_array(group["ids"] as PackedStringArray)
	return out


func _bake_icons() -> void:
	await MonsterIconCacheScript.bake_ids(_all_ids(), self)
	if not is_instance_valid(self):
		return
	_icons_ready = true
	_rebuild_face()


func _rebuild_face() -> void:
	clear_buttons()
	_id_by_button.clear()

	var margin := 0.01
	var content_top := 0.985
	var content_bot := 0.015
	var name_h := 0.14
	var grid_top := content_top - name_h
	var grid_bot := content_bot
	var row_h := (grid_top - grid_bot) / float(GRID_ROWS)

	var col_counts: Array[int] = []
	var total_cols := CONTROL_COLS
	for group: Dictionary in _groups:
		var ids: PackedStringArray = group["ids"] as PackedStringArray
		var cols := maxi(ceili(float(ids.size()) / float(GRID_ROWS)), 1)
		col_counts.append(cols)
		total_cols += cols
	## Sections = factions + the middle control strip; dividers between each.
	var n_sections := _groups.size() + 1
	var n_div := maxi(n_sections - 1, 0)
	var div_w := 0.008
	var cell_w := CELL_M / PANEL_W
	var content_w := float(total_cols) * cell_w + float(n_div) * div_w
	var usable := 1.0 - 2.0 * margin
	if content_w > usable:
		cell_w = (usable - float(n_div) * div_w) / float(total_cols)
		content_w = usable

	## High UV-x reads as the viewer's left; place left half, then controls, then rest.
	var left_n := _groups.size() / 2
	var x_hi := 0.5 + content_w * 0.5
	var need_div := false
	for b: int in range(_groups.size() + 1):
		if need_div:
			var dx_lo := x_hi - div_w
			add_button(
				StringName("%s%d" % [DIV_PREFIX, b]),
				Rect2(dx_lo + 0.001, content_bot, div_w - 0.002, content_top - content_bot),
				"",
				Color(0.34, 0.30, 0.28, 1.0),
				true
			)
			x_hi = dx_lo
		need_div = true
		if b == left_n:
			x_hi = _place_control_section(x_hi, cell_w, grid_top, name_h, row_h)
			continue
		var gi := b if b < left_n else b - 1
		x_hi = _place_faction_section(
			_groups[gi], col_counts[gi], x_hi, cell_w, grid_top, name_h, row_h
		)

	rebuild_buttons()


func _place_control_section(
	x_hi: float, cell_w: float, grid_top: float, name_h: float, row_h: float
) -> float:
	var block_w := float(CONTROL_COLS) * cell_w
	var x_lo := x_hi - block_w
	add_button(
		StringName(HDR_PREFIX + "arena"),
		Rect2(x_lo, grid_top, block_w, name_h - 0.01),
		"Arena",
		Color(0.22, 0.20, 0.24, 1.0),
		true
	)
	## Top row = Summon, bottom row = Clear (same cell geometry as mob portraits).
	var pad := 0.06
	for row in range(GRID_ROWS):
		var ry_hi := grid_top - float(row) * row_h
		var ry_lo := ry_hi - row_h
		var rect := Rect2(
			x_lo + pad * cell_w,
			ry_lo + 0.02,
			cell_w * (1.0 - 2.0 * pad),
			row_h - 0.04
		)
		if row == 0:
			add_button(
				BTN_SUMMON,
				rect,
				"",
				Color(0.85, 0.72, 0.35, 1.0),
				true,
				_summon_tex
			)
		else:
			add_button(
				BTN_CLEAR,
				rect,
				"",
				Color(0.75, 0.28, 0.22, 1.0),
				true,
				_clear_tex
			)
	return x_lo


func _place_faction_section(
	group: Dictionary,
	gcols: int,
	x_hi: float,
	cell_w: float,
	grid_top: float,
	name_h: float,
	row_h: float
) -> float:
	var name: String = str(group["name"])
	var ids: PackedStringArray = group["ids"] as PackedStringArray
	var block_w := float(gcols) * cell_w
	var x_lo := x_hi - block_w
	add_button(
		StringName(HDR_PREFIX + name),
		Rect2(x_lo, grid_top, block_w, name_h - 0.01),
		name.capitalize(),
		Color(0.22, 0.20, 0.24, 1.0),
		true
	)
	for i in range(ids.size()):
		var col := i / GRID_ROWS
		var row := i % GRID_ROWS
		var cx_hi := x_hi - float(col) * cell_w
		var cx_lo := cx_hi - cell_w
		var ry_hi := grid_top - float(row) * row_h
		var ry_lo := ry_hi - row_h
		var rect := Rect2(
			cx_lo + 0.0015,
			ry_lo + 0.005,
			cell_w - 0.003,
			row_h - 0.01
		)
		var mid: String = ids[i]
		var id := StringName("%s%s_%d" % [BTN_PREFIX, name, i])
		_id_by_button[id] = mid
		var tex: Texture2D = MonsterIconCacheScript.texture_for(mid)
		var selected := _selected.has(mid)
		var bg := SELECTED_BG if selected else IDLE_BG
		var color := _color_for(mid) if tex == null else IDLE_TINT
		if tex == null and selected:
			color = SELECTED_BG
		add_button(id, rect, "", color, true, tex, bg)
	return x_lo


func _color_for(monster_id: String) -> Color:
	var h := float(monster_id.hash() & 0xffff) / 65535.0
	return Color.from_hsv(h, 0.45, 0.42, 1.0)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	if button_id == BTN_CLEAR:
		clear_requested.emit()
		return
	if button_id == BTN_SUMMON:
		_fire_summon()
		return
	var id_str := String(button_id)
	if id_str.begins_with(HDR_PREFIX) or id_str.begins_with(DIV_PREFIX):
		return
	if not _id_by_button.has(button_id):
		return
	var mid := String(_id_by_button[button_id])
	if _selected.has(mid):
		_selected.erase(mid)
	else:
		_selected[mid] = true
	_rebuild_face()


func _fire_summon() -> void:
	if _selected.is_empty():
		return
	var ids := PackedStringArray()
	for mid: Variant in _selected.keys():
		ids.append(str(mid))
	ids.sort()
	_selected.clear()
	_rebuild_face()
	summon_batch_requested.emit(ids)


## Stylized portal / summon sigil (no text).
static func _make_summon_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.10, 0.08, 0.0))
	var cx := float(s) * 0.5
	var cy := float(s) * 0.52
	_fill_disc(img, cx, cy, 54.0, Color(0.22, 0.16, 0.10, 1.0))
	_fill_ring(img, cx, cy, 50.0, 40.0, Color(0.92, 0.72, 0.28, 1.0))
	_fill_ring(img, cx, cy, 36.0, 28.0, Color(0.55, 0.38, 0.14, 1.0))
	_fill_disc(img, cx, cy, 22.0, Color(0.95, 0.82, 0.35, 1.0))
	_fill_disc(img, cx, cy - 2.0, 10.0, Color(1.0, 0.95, 0.7, 1.0))
	## Upward chevron — "rise from below".
	for y in range(18, 48):
		var t := float(y - 18) / 30.0
		var half := int(4.0 + t * 18.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			if x >= 0 and x < s:
				img.set_pixel(x, y, Color(0.98, 0.88, 0.45, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex


## Sweep / reset glyph for wipe + redecorate (no text).
static func _make_clear_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.08, 0.08, 0.0))
	var cx := float(s) * 0.5
	var cy := float(s) * 0.5
	_fill_disc(img, cx, cy, 54.0, Color(0.28, 0.10, 0.10, 1.0))
	_fill_ring(img, cx, cy, 50.0, 38.0, Color(0.85, 0.32, 0.26, 1.0))
	## Arc arrow (counter-clockwise sweep).
	for a in range(40, 300):
		var rad := deg_to_rad(float(a))
		var r := 28.0
		var x := int(cx + cos(rad) * r)
		var y := int(cy + sin(rad) * r)
		_fill_disc(img, float(x), float(y), 4.0, Color(0.95, 0.55, 0.4, 1.0))
	## Arrow head near the gap.
	_fill_disc(img, cx + 22.0, cy - 18.0, 7.0, Color(1.0, 0.7, 0.5, 1.0))
	_fill_disc(img, cx + 12.0, cy - 26.0, 5.0, Color(1.0, 0.7, 0.5, 1.0))
	return ImageTexture.create_from_image(img)


static func _fill_disc(img: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	var r2 := radius * radius
	var x0 := maxi(int(cx - radius) - 1, 0)
	var x1 := mini(int(cx + radius) + 1, img.get_width() - 1)
	var y0 := maxi(int(cy - radius) - 1, 0)
	var y1 := mini(int(cy + radius) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)


static func _fill_ring(
	img: Image, cx: float, cy: float, outer_r: float, inner_r: float, color: Color
) -> void:
	var o2 := outer_r * outer_r
	var i2 := inner_r * inner_r
	var x0 := maxi(int(cx - outer_r) - 1, 0)
	var x1 := mini(int(cx + outer_r) + 1, img.get_width() - 1)
	var y0 := maxi(int(cy - outer_r) - 1, 0)
	var y1 := mini(int(cy + outer_r) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var d2 := dx * dx + dy * dy
			if d2 <= o2 and d2 >= i2:
				img.set_pixel(x, y, color)
