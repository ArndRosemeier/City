## Debug minimap + minimizable streamer overlay for the endless city.
class_name CityDebugHud
extends CanvasLayer

const MAP_SIZE := 168.0
const MAP_RADIUS_TILES := 3  # show 7×7 around player

var _streamer: Node
var _terrain: VoxelTerrain
var _panel: PanelContainer
var _body: VBoxContainer
var _toggle_btn: Button
var _stats_label: Label
var _warn_label: Label
var _minimap: Control
var _collapsed: bool = false
var _accum: float = 0.0
var _snapshot: Dictionary = {}


func setup(streamer: Node, terrain: VoxelTerrain) -> void:
	_streamer = streamer
	_terrain = terrain
	layer = 20
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	## —— Overlay (top-left, minimizable) ——
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 48)
	_panel.custom_minimum_size = Vector2(280, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	panel_sb.set_corner_radius_all(6)
	panel_sb.content_margin_left = 10
	panel_sb.content_margin_right = 10
	panel_sb.content_margin_top = 8
	panel_sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", panel_sb)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Streamer Debug"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	header.add_child(title)
	_toggle_btn = Button.new()
	_toggle_btn.text = "—"
	_toggle_btn.custom_minimum_size = Vector2(28, 24)
	_toggle_btn.pressed.connect(_on_toggle)
	header.add_child(_toggle_btn)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_body)

	_warn_label = Label.new()
	_warn_label.visible = false
	_warn_label.add_theme_font_size_override("font_size", 13)
	_warn_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_warn_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body.add_child(_stats_label)

	var hint := Label.new()
	hint.text = "F3 toggle · face shells · far=impostors · commit ≤3ms/frame · stalled = free capacity"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	_body.add_child(hint)

	## —— Minimap (bottom-right) ——
	var map_wrap := PanelContainer.new()
	map_wrap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_wrap.offset_left = -MAP_SIZE - 20
	map_wrap.offset_top = -MAP_SIZE - 20
	map_wrap.offset_right = -12
	map_wrap.offset_bottom = -12
	map_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	var map_sb := StyleBoxFlat.new()
	map_sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	map_sb.set_corner_radius_all(6)
	map_sb.content_margin_left = 6
	map_sb.content_margin_right = 6
	map_sb.content_margin_top = 6
	map_sb.content_margin_bottom = 6
	map_wrap.add_theme_stylebox_override("panel", map_sb)
	root.add_child(map_wrap)

	var map_col := VBoxContainer.new()
	map_col.add_theme_constant_override("separation", 4)
	map_wrap.add_child(map_col)
	var map_title := Label.new()
	map_title.text = "Districts"
	map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_title.add_theme_font_size_override("font_size", 11)
	map_title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	map_col.add_child(map_title)

	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	_minimap.draw.connect(_on_minimap_draw)
	map_col.add_child(_minimap)

	var legend := Label.new()
	legend.text = "■ ready  ■ ground  ■ busy  ■ queued"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 9)
	legend.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	map_col.add_child(legend)


func _on_toggle() -> void:
	_collapsed = not _collapsed
	_body.visible = not _collapsed
	_toggle_btn.text = "+" if _collapsed else "—"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _streamer == null or not is_instance_valid(_streamer):
		return
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	_snapshot = _streamer.call("debug_snapshot")
	_refresh_stats()
	if _minimap != null:
		_minimap.queue_redraw()


func _refresh_stats() -> void:
	if _stats_label == null:
		return
	var worker: String = str(_snapshot.get("worker", "?"))
	var in_works: int = int(_snapshot.get("in_works", 0))
	var pending_g: int = int(_snapshot.get("pending_ground", 0))
	var pending_d: int = int(_snapshot.get("pending_detail", 0))
	var busy: int = int(_snapshot.get("busy", 0))
	var cells_ps: float = float(_snapshot.get("cells_per_sec", 0.0))
	var jobs_pm: float = float(_snapshot.get("jobs_per_min", 0.0))
	var w_max: int = int(_snapshot.get("workers_max", 1))
	var w_act: int = int(_snapshot.get("workers_active", 0))
	var loaded: int = int(_snapshot.get("loaded", 0))
	var ready: int = int(_snapshot.get("ready", 0))
	var player_c: Vector2i = _snapshot.get("player_coord", Vector2i.ZERO)
	var active_jobs: Array = _snapshot.get("active_jobs", [])

	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"In works: %d  (busy %d · groundQ %d · detailQ %d)" % [in_works, busy, pending_g, pending_d]
	)
	var worker_line := "Workers: %d/%d  %s" % [w_act, w_max, worker.to_upper()]
	if worker == "stalled":
		worker_line += "  ← idle but queue has work"
	elif worker == "underfilled":
		worker_line += "  ← free slot while queue has work"
	lines.append(worker_line)
	if active_jobs.is_empty():
		lines.append("  (no active stamp job)")
	else:
		for j: Variant in active_jobs:
			if typeof(j) != TYPE_DICTIONARY:
				continue
			var jd: Dictionary = j
			var jc: Vector2i = jd.get("coord", Vector2i.ZERO)
			lines.append(
				"  • %s @ (%d,%d)  %.1fs"
				% [str(jd.get("kind", "?")), jc.x, jc.y, float(jd.get("age_sec", 0.0))]
			)
	lines.append("Throughput: %.0f cells/s · %.1f jobs/min" % [cells_ps, jobs_pm])
	lines.append("Loaded %d · ready %d · you (%d,%d)" % [loaded, ready, player_c.x, player_c.y])
	lines.append(_terrain_line())
	_stats_label.text = "\n".join(lines)

	if worker == "stalled":
		_warn_label.visible = true
		_warn_label.text = "STALLED: worker idle while %d district(s) still need work" % in_works
	elif worker == "underfilled":
		_warn_label.visible = true
		_warn_label.text = "UNDERFILLED: %d/%d workers active, queue still has work" % [w_act, w_max]
	else:
		var hung := false
		for j2: Variant in active_jobs:
			if typeof(j2) != TYPE_DICTIONARY:
				continue
			if float(j2.get("age_sec", 0.0)) > 90.0:
				hung = true
				var jd2: Dictionary = j2
				var jc2: Vector2i = jd2.get("coord", Vector2i.ZERO)
				_warn_label.text = (
					"Job >90s — still committing/setup on %s (%d,%d)"
					% [str(jd2.get("kind", "?")), jc2.x, jc2.y]
				)
				break
		_warn_label.visible = hung


func _terrain_line() -> String:
	if _terrain == null or not is_instance_valid(_terrain) or not _terrain.has_method("get_statistics"):
		return "Terrain: —"
	var stats: Variant = _terrain.get_statistics()
	if typeof(stats) != TYPE_DICTIONARY:
		return "Terrain: (stats)"
	var d: Dictionary = stats
	var updated := int(d.get("updated_blocks", 0))
	var dropped_m := int(d.get("dropped_block_meshs", 0))
	var dropped_l := int(d.get("dropped_block_loads", 0))
	return "Terrain: updated_blocks=%d  dropped_mesh=%d  dropped_load=%d" % [updated, dropped_m, dropped_l]


func _on_minimap_draw() -> void:
	if _minimap == null:
		return
	var size := _minimap.size
	_minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12, 1.0), true)

	var player_c: Vector2i = _snapshot.get("player_coord", Vector2i.ZERO)
	var tiles: Array = _snapshot.get("tiles", [])
	var by_coord: Dictionary = {}
	for t: Variant in tiles:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		by_coord[td.get("coord", Vector2i.ZERO)] = str(td.get("state", "queued"))

	var cells := MAP_RADIUS_TILES * 2 + 1
	var cell_w := size.x / float(cells)
	var cell_h := size.y / float(cells)
	var gap := 2.0

	for dz in range(-MAP_RADIUS_TILES, MAP_RADIUS_TILES + 1):
		for dx in range(-MAP_RADIUS_TILES, MAP_RADIUS_TILES + 1):
			var c := Vector2i(player_c.x + dx, player_c.y + dz)
			var ix := dx + MAP_RADIUS_TILES
			var iy := dz + MAP_RADIUS_TILES
			var rect := Rect2(
				float(ix) * cell_w + gap * 0.5,
				float(iy) * cell_h + gap * 0.5,
				cell_w - gap,
				cell_h - gap
			)
			var state := str(by_coord.get(c, ""))
			var col := Color(0.15, 0.17, 0.2, 1.0)  # unloaded / outside bubble
			match state:
				"ready":
					col = Color(0.28, 0.62, 0.38)
				"ground":
					col = Color(0.75, 0.68, 0.28)
				"busy":
					col = Color(0.9, 0.45, 0.2)
				"pending", "queued":
					col = Color(0.35, 0.4, 0.55)
			_minimap.draw_rect(rect, col, true)
			if c == player_c:
				_minimap.draw_rect(rect.grow(-2.0), Color(1, 1, 1, 0.95), false, 2.0)

	## Player marker
	var px := (float(MAP_RADIUS_TILES) + 0.5) * cell_w
	var py := (float(MAP_RADIUS_TILES) + 0.5) * cell_h
	_minimap.draw_circle(Vector2(px, py), 4.0, Color(1.0, 0.95, 0.4))
