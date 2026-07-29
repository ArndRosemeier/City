## Navigation debug overlay: the span field, sector portals, live corridors and dynamic
## blocks, drawn near the followed node only.
##
## A baked district holds well over a million spans, so no layer here ever draws a whole
## field: every layer is a radius query around the followed node, re-run only when that
## node moves, the nav version changes, or a corridor is replaced. Drawing is
## immediate-mode — three MultiMeshes and one ImmediateMesh, never a node per span — so the
## cost is a handful of draw calls at any span count, and switching the overlay off stops
## `_process` instead of merely hiding meshes.
##
## Nothing here keeps its own copy of nav state: the block layer draws NavService's live
## blocked-column set, so a block written by an agent shows up as readily as one this overlay
## wrote itself.
class_name NavDebugOverlay
extends Node3D

## How the span field is tinted. Clearance answers "where does a wide body fit", headroom
## "where does a tall body fit", component "what is connected to what inside its sector".
enum SpanColour {
	CLEARANCE = 0,
	HEADROOM = 1,
	COMPONENT = 2,
}

## NativeNavWorld.debug_spans clamps its query to 96 cells, so a larger radius would draw
## a smaller ring than the HUD claims.
const MAX_RADIUS_M := 48.0
## Instances the span layer will draw. A street at 18 m is a few thousand spans, a building
## interior several times that, so this is headroom rather than a budget.
const MAX_SPANS := 80000
const MAX_PORTALS := 4096
const MAX_BLOCKS := 1024

## Floats one MultiMesh instance occupies with TRANSFORM_3D and colours: twelve for the
## row-major transform, four for the colour.
const INSTANCE_FLOATS := 16

## Corridor id the built-in aim probe writes to. NavAgent corridors use their own ids.
const PROBE_CORRIDOR := &"aim_probe"

## Clearance and headroom saturate well below their byte range; tinting against the raw
## 0..255 would leave every span the same blue.
const CLEARANCE_FULL := 8.0
const HEADROOM_FULL := 12.0

## Spans sit exactly on the collision surface, so the quads need lifting off it.
const SPAN_LIFT_M := 0.06
const CORRIDOR_LIFT_M := 0.35
## Corridors are drawn as a ribbon rather than a line: a one pixel path is unreadable at
## the distance a reviewer actually looks at a route from.
const CORRIDOR_WIDTH_M := 0.5
const CORRIDOR_TICK_M := 1.2
const PORTAL_HEIGHT_M := 2.4
const BLOCK_HEIGHT_M := 4.0

## Only reached when something asks for a block before NavService exists, which is a bug
## the caller hears about — the value just keeps the column from landing at the origin.
const FALLBACK_VOXEL_SIZE := 0.5

## Outline the counter line is drawn with, matching the other HUD surfaces.
const HUD_OUTLINE_PX := 4


## Radius of every layer's query, in metres.
var radius_m: float = 18.0:
	set(value):
		if value > MAX_RADIUS_M:
			push_error(
				"NavDebugOverlay: radius %.1f m exceeds the %.1f m debug_spans limit"
				% [value, MAX_RADIUS_M]
			)
		radius_m = clampf(value, 1.0, MAX_RADIUS_M)
		_cap_reported = false
		_dirty_field = true

var span_colour: SpanColour = SpanColour.CLEARANCE:
	set(value):
		span_colour = value
		_dirty_field = true

## Draw through geometry, so basements and building floors are reviewable from outside.
var xray: bool = false:
	set(value):
		xray = value
		_apply_xray()

## Metres above and below the centre a span may be and still be drawn. A tower puts twenty
## floors in one column; the four a reviewer standing on the street cares about are the ones
## near them, and the rest is both clutter and cost.
var height_band_m: float = 9.0:
	set(value):
		height_band_m = maxf(value, 0.5)
		_dirty_field = true

## Seconds between field queries while the player walks. Movement and version changes are
## what trigger a refresh; this only stops one from happening every frame.
var refresh_sec: float = 0.2
## Metres the centre must move before the field is re-queried.
var refresh_move_m: float = 1.5
## Seconds between aim-probe path requests, when an aim provider is bound.
var probe_sec: float = 0.5
## Profile the aim probe paths with.
var probe_profile_id: int = NavProfile.Id.PEDESTRIAN

## Spans, portals, blocks and corridor points drawn by the last refresh.
var spans_drawn: int = 0
var portals_drawn: int = 0
var blocks_drawn: int = 0
var corridor_points: int = 0

var _enabled: bool = false
var _follow: Node3D = null
## Returns the world point the built-in probe paths to. Unset means no aim probe.
var _aim_provider: Callable = Callable()

var _span_mm: MultiMeshInstance3D = null
var _portal_mm: MultiMeshInstance3D = null
var _block_mm: MultiMeshInstance3D = null
var _corridor_mesh: ImmediateMesh = null
var _corridor_instance: MeshInstance3D = null
var _span_material: StandardMaterial3D = null
var _line_material: StandardMaterial3D = null
var _hud_layer: CanvasLayer = null
var _hud: Label = null

## Corridors by source id, so NavAgent can push its live path without the overlay knowing
## anything about agents.
var _corridors: Dictionary[StringName, NavPathResult] = {}

## Reused so a refresh does not allocate a megabyte of instance data every time.
var _span_buffer: PackedFloat32Array = PackedFloat32Array()
var _lut: PackedFloat32Array = PackedFloat32Array()
var _lut_mode: SpanColour = SpanColour.CLEARANCE

var _centre: Vector3 = Vector3.ZERO
var _last_query_centre: Vector3 = Vector3.INF
var _last_version: int = -1
var _refresh_accum: float = 0.0
var _probe_accum: float = 0.0
var _probe_request: int = 0
var _dirty_field: bool = true
var _dirty_corridors: bool = true
var _dirty_blocks: bool = true
var _last_blocked_version: int = -1
## Set once per radius change so a saturated span layer reports itself without spamming.
var _cap_reported: bool = false


func _ready() -> void:
	_build_meshes()
	_build_hud()
	visible = false
	set_process(false)


# ---------------------------------------------------------------------------
# Toggle
# ---------------------------------------------------------------------------

## Turn the overlay on or off. Off means no queries, no `_process` and empty meshes, so an
## overlay nobody asked for costs nothing.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	if on and not _nav_ready():
		push_error("NavDebugOverlay: NavService is not configured yet, nothing to draw")
		return
	_enabled = on
	visible = on
	set_process(on)
	if _hud_layer != null:
		_hud_layer.visible = on
	if on:
		_dirty_field = true
		_dirty_corridors = true
		_dirty_blocks = true
		_last_blocked_version = -1
		_last_query_centre = Vector3.INF
		_refresh_accum = refresh_sec
		_probe_accum = probe_sec
		return
	_cancel_probe()
	_clear_drawing()


func is_enabled() -> bool:
	return _enabled


func toggle() -> bool:
	set_enabled(not _enabled)
	return _enabled


## Cycle the span tint. Returns the new mode's name, for whoever owns the key hint.
func cycle_span_colour() -> String:
	span_colour = ((span_colour + 1) % SpanColour.size()) as SpanColour
	return span_colour_name()


func span_colour_name() -> String:
	match span_colour:
		SpanColour.CLEARANCE:
			return "clearance"
		SpanColour.HEADROOM:
			return "headroom"
		SpanColour.COMPONENT:
			return "component"
		_:
			push_error("NavDebugOverlay: unknown span colour %d" % span_colour)
			return "?"


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

## The node every layer centres on — normally the player. Unset falls back to the active
## camera, so a tool scene without a player still draws something.
func bind_follow(node: Node3D) -> void:
	_follow = node


## Where the built-in probe should path to, as a Callable returning one Vector3 in world
## metres. Unset (or cleared with an empty Callable) disables the probe.
func bind_aim_provider(provider: Callable) -> void:
	if not provider.is_null() and not provider.is_valid():
		push_error("NavDebugOverlay.bind_aim_provider: callable is dead")
		return
	_aim_provider = provider
	_cancel_probe()


## Draw a corridor under `id`, replacing whatever that source drew before. This is the seam
## NavAgent feeds: one call per repath, no knowledge of this overlay's internals.
func set_corridor(id: StringName, path: NavPathResult) -> void:
	if path == null:
		push_error("NavDebugOverlay.set_corridor: corridor '%s' is null" % id)
		return
	_corridors[id] = path
	_dirty_corridors = true


func clear_corridor(id: StringName) -> void:
	if not _corridors.erase(id):
		return
	_dirty_corridors = true


func corridor(id: StringName) -> NavPathResult:
	if not _corridors.has(id):
		return null
	return _corridors[id]


func corridor_count() -> int:
	return _corridors.size()


## Path from the tracked centre to `target_world` and draw the result as the probe
## corridor. Goes through the ordinary request queue, so the corridor layer is exercised by
## the same code path an agent uses.
func probe_to(target_world: Vector3) -> void:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay.probe_to: NavService is not configured")
		return
	_cancel_probe()
	_probe_request = nav.request_path(
		probe_profile_id, _resolve_centre(), target_world, _on_probe_done
	)


## Block the column under `world_pos` for a while. NavService keeps the live set, so the
## block is drawn from the same place an agent's block is, whoever wrote it.
func block_column(world_pos: Vector3, seconds: float) -> void:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay.block_column: NavService is not configured")
		return
	nav.block_column(world_pos, seconds)


## One line of counters, for a HUD that would rather print than host this overlay's own.
func counter_line() -> String:
	var nav := NavService.peek()
	var queued := 0
	var version := 0
	var districts := 0
	if nav != null and nav.is_configured():
		queued = nav.queue_size()
		version = nav.version()
		districts = nav.district_count()
	return (
		"nav spans %d (%s)  portals %d  corridors %d/%dpt  blocks %d  queue %d  v%d  tiles %d"
		+ "  fails %d  repath %d/%d"
	) % [
		spans_drawn,
		span_colour_name(),
		portals_drawn,
		_corridors.size(),
		corridor_points,
		blocks_drawn,
		queued,
		version,
		districts,
		NavAgent.goal_failure_events(),
		NavAgent.stale_repaths(),
		NavAgent.stale_repaths_skipped(),
	]


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay: NavService went away while the overlay was on")
		set_enabled(false)
		return
	var t0 := Time.get_ticks_usec()
	_centre = _resolve_centre()
	_refresh_accum += delta
	_probe_accum += delta
	var blocked_version := nav.blocked_version()
	if blocked_version != _last_blocked_version:
		_last_blocked_version = blocked_version
		_dirty_blocks = true
	if _refresh_accum >= refresh_sec:
		_refresh_accum = 0.0
		var version := nav.version()
		if version != _last_version:
			_last_version = version
			_dirty_field = true
		if _centre.distance_to(_last_query_centre) >= refresh_move_m:
			_dirty_field = true
	if _dirty_field:
		_dirty_field = false
		_last_query_centre = _centre
		_draw_spans()
		_draw_portals()
	if _dirty_corridors:
		_dirty_corridors = false
		_draw_corridors()
	if _dirty_blocks:
		_dirty_blocks = false
		_draw_blocks()
	if not _aim_provider.is_null() and _probe_accum >= probe_sec:
		_probe_accum = 0.0
		_run_aim_probe()
	CityProfiler.scope_us("nav_debug_overlay", Time.get_ticks_usec() - t0)
	CityProfiler.set_counter("nav_debug_spans", spans_drawn)
	CityProfiler.set_counter("nav_debug_portals", portals_drawn)
	CityProfiler.set_counter("nav_debug_blocks", blocks_drawn)
	if _hud != null:
		_hud.text = counter_line()


func _resolve_centre() -> Vector3:
	if _follow != null and is_instance_valid(_follow):
		return _follow.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return global_position


func _run_aim_probe() -> void:
	if not _aim_provider.is_valid():
		push_error("NavDebugOverlay: aim provider died, dropping the probe corridor")
		_aim_provider = Callable()
		clear_corridor(PROBE_CORRIDOR)
		return
	var target: Vector3 = _aim_provider.call()
	if not target.is_finite():
		return
	probe_to(target)


func _on_probe_done(result: NavPathResult) -> void:
	_probe_request = 0
	if not result.is_usable():
		clear_corridor(PROBE_CORRIDOR)
		return
	set_corridor(PROBE_CORRIDOR, result)


func _cancel_probe() -> void:
	if _probe_request == 0:
		return
	var nav := NavService.peek()
	if nav != null:
		nav.cancel_path(_probe_request)
	_probe_request = 0


# ---------------------------------------------------------------------------
# Layers
# ---------------------------------------------------------------------------

func _draw_spans() -> void:
	var world := _nav_world()
	if world == null:
		return
	var raw: Dictionary = world.debug_spans(_centre, radius_m)
	var positions: PackedVector3Array = raw["positions"]
	var total := positions.size()
	var key: PackedByteArray = raw[_tint_key()]
	var lut := _tint_lut()
	var mm := _reserve(_span_mm, mini(total, MAX_SPANS))
	_prepare_span_buffer(mm.instance_count)
	## One buffer upload instead of two engine calls per span, and a table lookup instead of
	## a colour computation: at twenty thousand spans both are the cost of a refresh.
	var y_min := _centre.y - height_band_m
	var y_max := _centre.y + height_band_m
	var written := 0
	for i in range(total):
		var p := positions[i]
		if p.y < y_min or p.y > y_max:
			continue
		if written >= MAX_SPANS:
			if not _cap_reported:
				_cap_reported = true
				push_error(
					"NavDebugOverlay: over %d spans within %.1f m, drawing the first ones only"
					% [MAX_SPANS, radius_m]
				)
			break
		var b := written * INSTANCE_FLOATS
		_span_buffer[b + 3] = p.x
		_span_buffer[b + 7] = p.y + SPAN_LIFT_M
		_span_buffer[b + 11] = p.z
		var c := int(key[i]) * 4
		_span_buffer[b + 12] = lut[c]
		_span_buffer[b + 13] = lut[c + 1]
		_span_buffer[b + 14] = lut[c + 2]
		_span_buffer[b + 15] = lut[c + 3]
		written += 1
	mm.buffer = _span_buffer
	mm.visible_instance_count = written
	spans_drawn = written
	_span_mm.custom_aabb = _ring_aabb(height_band_m * 2.0 + 8.0)


## Every span quad is axis aligned, so the three unit entries of its transform never change
## once written. Writing them only for slots the buffer has just grown into takes three of
## the ten array writes a span used to need out of the refresh loop.
func _prepare_span_buffer(instances: int) -> void:
	var needed := instances * INSTANCE_FLOATS
	if _span_buffer.size() >= needed:
		return
	var first := _span_buffer.size() / INSTANCE_FLOATS
	_span_buffer.resize(needed)
	for i in range(first, instances):
		var b := i * INSTANCE_FLOATS
		_span_buffer[b] = 1.0
		_span_buffer[b + 5] = 1.0
		_span_buffer[b + 10] = 1.0


## Which byte of the debug_spans payload the active colouring reads.
func _tint_key() -> String:
	match span_colour:
		SpanColour.CLEARANCE:
			return "clearance"
		SpanColour.HEADROOM:
			return "headroom"
		SpanColour.COMPONENT:
			return "component"
		_:
			push_error("NavDebugOverlay: unknown span colour %d" % span_colour)
			return "clearance"


## 256 RGBA entries for the active colouring, rebuilt only when the mode changes.
func _tint_lut() -> PackedFloat32Array:
	if not _lut.is_empty() and _lut_mode == span_colour:
		return _lut
	_lut_mode = span_colour
	_lut.resize(256 * 4)
	for v in range(256):
		var tint: Color
		match span_colour:
			SpanColour.CLEARANCE:
				tint = _ramp(float(v) / CLEARANCE_FULL)
			SpanColour.HEADROOM:
				tint = _ramp(float(v) / HEADROOM_FULL)
			SpanColour.COMPONENT:
				## 255 is the bake's "no component": a span no sector search reached.
				if v == 255:
					tint = Color(0.35, 0.35, 0.35, 0.7)
				else:
					tint = Color.from_hsv(fmod(float(v) * 0.618034, 1.0), 0.7, 0.95, 0.7)
			_:
				push_error("NavDebugOverlay: unknown span colour %d" % span_colour)
				tint = Color.WHITE
		var b := v * 4
		_lut[b] = tint.r
		_lut[b + 1] = tint.g
		_lut[b + 2] = tint.b
		_lut[b + 3] = tint.a
	return _lut


func _draw_portals() -> void:
	var world := _nav_world()
	if world == null:
		return
	var points: PackedVector3Array = world.debug_portals(_centre, radius_m)
	var count := points.size()
	if count > MAX_PORTALS:
		push_error(
			"NavDebugOverlay: %d portals within %.1f m exceeds the %d instance cap"
			% [count, radius_m, MAX_PORTALS]
		)
		count = MAX_PORTALS
	var mm := _reserve(_portal_mm, count)
	var lift := Vector3(0.0, PORTAL_HEIGHT_M * 0.5, 0.0)
	for i in range(count):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i] + lift))
		mm.set_instance_color(i, Color(0.25, 0.9, 1.0, 0.55))
	mm.visible_instance_count = count
	portals_drawn = count
	_portal_mm.custom_aabb = _ring_aabb(64.0)


func _draw_blocks() -> void:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay: NavService went away while the overlay was on")
		set_enabled(false)
		return
	var vs := _voxel_size()
	var columns := nav.blocked_columns()
	var count := columns.size()
	if count > MAX_BLOCKS:
		push_error("NavDebugOverlay: %d live blocks, drawing the first %d" % [count, MAX_BLOCKS])
		count = MAX_BLOCKS
	var mm := _reserve(_block_mm, count)
	var basis := Basis.from_scale(Vector3(vs, 1.0, vs))
	for i in range(count):
		var column := columns[i]
		var centre := Vector3(
			(float(column.x) + 0.5) * vs,
			nav.blocked_column_y(column) + BLOCK_HEIGHT_M * 0.5,
			(float(column.y) + 0.5) * vs
		)
		mm.set_instance_transform(i, Transform3D(basis, centre))
		mm.set_instance_color(i, Color(1.0, 0.15, 0.1, 0.35))
	mm.visible_instance_count = count
	blocks_drawn = count
	_block_mm.custom_aabb = _ring_aabb(256.0)


func _draw_corridors() -> void:
	_corridor_mesh.clear_surfaces()
	corridor_points = 0
	if _corridors.is_empty():
		return
	var lift := Vector3(0.0, CORRIDOR_LIFT_M, 0.0)
	var tick := Vector3(0.0, CORRIDOR_TICK_M, 0.0)
	_corridor_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for id: StringName in _corridors:
		var path: NavPathResult = _corridors[id]
		var points := path.points
		if points.size() != path.link_kinds.size():
			push_error(
				"NavDebugOverlay: corridor '%s' has %d points but %d link kinds"
				% [id, points.size(), path.link_kinds.size()]
			)
			continue
		corridor_points += points.size()
		for i in range(1, points.size()):
			## The link kind is the one used to *enter* this point, so it colours the leg
			## arriving here: an orange stretch is a climb, magenta a drop.
			_ribbon(
				points[i - 1] + lift, points[i] + lift, _link_tint(int(path.link_kinds[i]))
			)
	_corridor_mesh.surface_end()
	## Waypoints as upright flags, so a corridor seen end-on is still countable.
	_corridor_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for id: StringName in _corridors:
		var path: NavPathResult = _corridors[id]
		for i in range(path.points.size()):
			var foot := path.points[i] + lift
			_ribbon(foot, foot + tick, Color(1.0, 1.0, 1.0, 0.6))
	_corridor_mesh.surface_end()


## One flat quad from `a` to `b`, widened across whichever axis the leg is not running
## along, so a climb leg is as visible as a walk.
func _ribbon(a: Vector3, b: Vector3, tint: Color) -> void:
	var along := b - a
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	side = side.normalized() * (CORRIDOR_WIDTH_M * 0.5)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(a - side)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(a + side)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(b + side)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(a - side)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(b + side)
	_corridor_mesh.surface_set_color(tint)
	_corridor_mesh.surface_add_vertex(b - side)


func _link_tint(kind: int) -> Color:
	match kind:
		NavPathResult.LINK_WALK:
			return Color(0.4, 1.0, 0.45, 0.95)
		NavPathResult.LINK_CLIMB:
			return Color(1.0, 0.55, 0.1, 1.0)
		NavPathResult.LINK_DROP:
			return Color(1.0, 0.2, 0.8, 1.0)
		NavPathResult.LINK_JUMP:
			return Color(1.0, 0.95, 0.2, 1.0)
		_:
			push_error("NavDebugOverlay: corridor uses unknown link kind %d" % kind)
			return Color.WHITE


func _clear_drawing() -> void:
	_span_mm.multimesh.visible_instance_count = 0
	_portal_mm.multimesh.visible_instance_count = 0
	_block_mm.multimesh.visible_instance_count = 0
	_corridor_mesh.clear_surfaces()
	spans_drawn = 0
	portals_drawn = 0
	blocks_drawn = 0
	corridor_points = 0


## Grow the instance buffer to fit, never shrink it. Resizing a MultiMesh reallocates, so a
## player walking between a street and a stairwell would otherwise pay for it every refresh.
func _reserve(layer: MultiMeshInstance3D, count: int) -> MultiMesh:
	var mm := layer.multimesh
	if mm.instance_count < count:
		mm.instance_count = count
	return mm


## Culling box around the followed node. Instances are placed in world space, so without
## one the MultiMesh AABB would be recomputed from every instance on every refresh.
func _ring_aabb(height_m: float) -> AABB:
	var r := radius_m + 4.0
	return AABB(
		_centre - Vector3(r, height_m * 0.5, r), Vector3(r * 2.0, height_m, r * 2.0)
	)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _build_meshes() -> void:
	_span_material = _unshaded(false)
	_line_material = _unshaded(true)

	## Buffers start small and grow through `_reserve`; reserving the caps up front would
	## cost megabytes for an overlay that is off by default.
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.42, 0.42)
	_span_mm = _make_layer("NavDebugSpans", quad, 4096, _span_material)

	var post := BoxMesh.new()
	post.size = Vector3(0.22, PORTAL_HEIGHT_M, 0.22)
	_portal_mm = _make_layer("NavDebugPortals", post, 128, _line_material)

	var column := BoxMesh.new()
	column.size = Vector3(1.0, BLOCK_HEIGHT_M, 1.0)
	_block_mm = _make_layer("NavDebugBlocks", column, 32, _span_material)

	_corridor_mesh = ImmediateMesh.new()
	_corridor_instance = MeshInstance3D.new()
	_corridor_instance.name = "NavDebugCorridors"
	_corridor_instance.mesh = _corridor_mesh
	_corridor_instance.material_override = _line_material
	_corridor_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_corridor_instance)
	_apply_xray()


func _make_layer(
	node_name: String, mesh: Mesh, reserve: int, material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = reserve
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _unshaded(always_visible: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = always_visible
	return mat


## Corridors are always drawn through geometry — a route hidden by the wall it runs past is
## useless. Spans, portals and blocks follow the `xray` switch.
func _apply_xray() -> void:
	if _span_material == null:
		return
	_span_material.no_depth_test = xray


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "NavDebugHud"
	_hud_layer.layer = UiLayers.DEBUG_NAV_COUNTERS
	_hud_layer.visible = false
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.name = "NavDebugCounters"
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8, 0.95))
	## The counters sit over whatever the camera happens to look at, and a bright sky swallows
	## unoutlined text outright. Same dark outline the other HUD surfaces use.
	_hud.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	_hud.add_theme_constant_override("outline_size", HUD_OUTLINE_PX)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud.offset_left = -840.0
	_hud.offset_top = 12.0
	_hud.offset_right = -16.0
	_hud.offset_bottom = 40.0
	_hud.text = "—"
	_hud_layer.add_child(_hud)


# ---------------------------------------------------------------------------
# NavService access
# ---------------------------------------------------------------------------

func _nav_ready() -> bool:
	var nav := NavService.peek()
	return nav != null and nav.is_configured()


## NavService owns the NativeNavWorld and exposes no wrapper for `debug_spans` /
## `debug_portals`, so the overlay reads the handle directly. The alternative is a second
## world, which would draw a field no agent queries.
func _nav_world() -> NativeNavWorld:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay: NavService went away while the overlay was on")
		set_enabled(false)
		return null
	return nav._world


func _voxel_size() -> float:
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("NavDebugOverlay: no voxel size before NavService is configured")
		return FALLBACK_VOXEL_SIZE
	return nav.voxel_size()


## Red where a body barely fits, through green, to blue where there is room to spare. Tight
## is the loud end on purpose: an open plaza is not what anyone opens this overlay to find.
static func _ramp(t: float) -> Color:
	var k := clampf(t, 0.0, 1.0)
	return Color.from_hsv(0.66 * k, 0.85, 1.0 - 0.25 * k, 0.7)
