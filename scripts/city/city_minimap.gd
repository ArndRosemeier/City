## Top-down tactical minimap: buildings, undead, meteors within 100 m.
## Radar (U) paints every undead; beyond-range contacts sit on the rim (direction only).
extends CanvasLayer

const RANGE_M := 100.0
const MAP_SIZE_PX := 168.0
const REFRESH_SEC := 0.2

var _city: Node
var _panel: Control
var _map: Control
var _title: Label
var _accum: float = 0.0
var _snapshot: Dictionary = {}


func _ready() -> void:
	layer = UiLayers.HUD_MINIMAP
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = Control.new()
	_panel.name = "MinimapPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 14.0
	_panel.offset_top = -MAP_SIZE_PX - 52.0
	_panel.offset_right = 14.0 + MAP_SIZE_PX
	_panel.offset_bottom = -36.0
	root.add_child(_panel)

	var frame := ColorRect.new()
	frame.name = "Frame"
	frame.color = Color(0.04, 0.06, 0.08, 0.82)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(frame)

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.55, 0.85, 0.78, 0.55)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.offset_left = -1.0
	border.offset_top = -1.0
	border.offset_right = 1.0
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	_panel.add_child(border)
	_panel.move_child(border, 0)

	_map = Control.new()
	_map.name = "MapDraw"
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_on_map_draw)
	_panel.add_child(_map)

	_title = Label.new()
	_title.text = "100 m"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", Color(0.75, 0.9, 0.85, 0.85))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("outline_size", 2)
	_title.position = Vector2(6, 4)
	_panel.add_child(_title)

	set_process(true)


func bind_city(city: Node) -> void:
	_city = city
	_refresh()


func clear_display() -> void:
	_city = null
	_snapshot.clear()
	if _map != null:
		_map.queue_redraw()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_SEC:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	if _city == null or not is_instance_valid(_city) or not _city.has_method("get_minimap_snapshot"):
		_snapshot.clear()
		if _map != null:
			_map.queue_redraw()
		return
	_snapshot = _city.call("get_minimap_snapshot", RANGE_M) as Dictionary
	if _title != null:
		if bool(_snapshot.get("radar_active", false)):
			_title.text = "RADAR"
			_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.9, 1.0))
		else:
			_title.text = "100 m"
			_title.add_theme_color_override("font_color", Color(0.75, 0.9, 0.85, 0.85))
	if _map != null:
		_map.queue_redraw()


func _on_map_draw() -> void:
	if _map == null:
		return
	var size := _map.size
	if size.x < 8.0 or size.y < 8.0:
		return
	var half := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	var range_m := float(_snapshot.get("range_m", RANGE_M))
	if range_m < 1.0:
		range_m = RANGE_M
	var scale_px := half / range_m
	var yaw := float(_snapshot.get("yaw", 0.0))
	## Match CityWalker: forward = -basis.z, right = basis.x after Y rotation.
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var origin: Vector3 = _snapshot.get("origin", Vector3.ZERO) as Vector3
	var radar_on := bool(_snapshot.get("radar_active", false))
	var rim_m := range_m * 0.94

	## Soft ground disc.
	_map.draw_circle(center, half - 2.0, Color(0.08, 0.1, 0.12, 0.95))
	if radar_on:
		_map.draw_circle(center, half - 2.0, Color(0.12, 0.28, 0.26, 0.35))

	## Buildings — muted blocks; each footprint corner uses the same heading-up map as dots.
	var buildings: Array = _snapshot.get("buildings", []) as Array
	for raw in buildings:
		if not (raw is Dictionary):
			continue
		var b: Dictionary = raw
		var bcenter: Vector3 = b.get("center", Vector3.ZERO) as Vector3
		var bsize: Vector3 = b.get("size", Vector3(4, 4, 4)) as Vector3
		var hx := maxf(bsize.x * 0.5, 0.75)
		var hz := maxf(bsize.z * 0.5, 0.75)
		var corners_w := [
			Vector3(bcenter.x - hx, bcenter.y, bcenter.z - hz),
			Vector3(bcenter.x + hx, bcenter.y, bcenter.z - hz),
			Vector3(bcenter.x + hx, bcenter.y, bcenter.z + hz),
			Vector3(bcenter.x - hx, bcenter.y, bcenter.z + hz),
		]
		var pts := PackedVector2Array()
		pts.resize(4)
		var any_in := false
		for i in range(4):
			var map_xz := _offset_to_map_axes(corners_w[i] - origin, right, forward)
			if absf(map_xz.x) <= range_m and absf(map_xz.y) <= range_m:
				any_in = true
			## +ahead → up on screen (negative Y), so walking forward makes the world recede downward.
			pts[i] = Vector2(center.x + map_xz.x * scale_px, center.y - map_xz.y * scale_px)
		if not any_in:
			continue
		_map.draw_colored_polygon(pts, Color(0.42, 0.46, 0.5, 0.9))

	## Meteors — amber.
	var meteors: Array = _snapshot.get("meteors", []) as Array
	for m in meteors:
		var mp: Vector2 = _world_to_map(m as Vector3, origin, right, forward, center, scale_px, range_m, false)
		if mp.x < -999.0:
			continue
		_map.draw_circle(mp, 4.5, Color(1.0, 0.55, 0.15, 1.0))
		_map.draw_circle(mp, 2.0, Color(1.0, 0.9, 0.45, 1.0))

	## Undead — mage violet, minion teal, giant red. Edge = direction-only rim dots.
	var undead: Array = _snapshot.get("undead", []) as Array
	for raw in undead:
		if not (raw is Dictionary):
			continue
		var u: Dictionary = raw
		var on_edge := bool(u.get("edge", false))
		var up: Vector2 = _world_to_map(
			u.get("pos", Vector3.ZERO) as Vector3,
			origin,
			right,
			forward,
			center,
			scale_px,
			rim_m if on_edge else range_m,
			on_edge
		)
		if up.x < -999.0:
			continue
		var kind := str(u.get("kind", "mage"))
		var col := Color(0.7, 0.35, 1.0, 1.0)
		var rad := 3.0
		if kind == "minion":
			col = Color(0.35, 0.85, 0.55, 1.0)
			rad = 2.4
		elif kind == "giant":
			col = Color(1.0, 0.3, 0.25, 1.0)
			rad = 5.5
		if on_edge:
			## Rim contact: hollow ring so it reads as "bearing, not range".
			_map.draw_arc(up, rad + 1.2, 0.0, TAU, 16, col, 2.0, true)
			_map.draw_circle(up, rad * 0.55, col)
		else:
			_map.draw_circle(up, rad, col)

	## Player — cyan chevron facing up (heading-up map).
	var tip := center + Vector2(0.0, -7.0)
	var left := center + Vector2(-5.0, 6.0)
	var right_pt := center + Vector2(5.0, 6.0)
	_map.draw_colored_polygon(PackedVector2Array([tip, right_pt, left]), Color(0.35, 0.95, 1.0, 1.0))

	## Range ring.
	var ring_col := Color(0.45, 1.0, 0.9, 0.7) if radar_on else Color(0.55, 0.85, 0.78, 0.35)
	_map.draw_arc(center, half - 3.0, 0.0, TAU, 48, ring_col, 1.25 if radar_on else 1.0, true)


func _offset_to_map_axes(offset: Vector3, right: Vector3, forward: Vector3) -> Vector2:
	## x = right, y = ahead (both meters in player space).
	return Vector2(offset.dot(right), offset.dot(forward))


func _world_to_map(
	world: Vector3,
	origin: Vector3,
	right: Vector3,
	forward: Vector3,
	center: Vector2,
	scale_px: float,
	range_m: float,
	clamp_to_edge: bool
) -> Vector2:
	var map_xz := _offset_to_map_axes(world - origin, right, forward)
	var len := map_xz.length()
	if len <= range_m:
		return Vector2(center.x + map_xz.x * scale_px, center.y - map_xz.y * scale_px)
	if not clamp_to_edge:
		return Vector2(-1000.0, -1000.0)
	## Direction only — sit on the minimap rim.
	if len < 0.0001:
		return Vector2(-1000.0, -1000.0)
	var rim := map_xz * (range_m / len)
	return Vector2(center.x + rim.x * scale_px, center.y - rim.y * scale_px)
