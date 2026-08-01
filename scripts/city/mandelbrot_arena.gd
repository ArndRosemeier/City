## Scene content for a Fractal district: four MandelbrotPanels on the glow-square edges.
## Panels face *away* from the district centre so a player reading a panel has the plaza
## behind it. Create on any panel restarts the plaza terrain morph for that zoom.
## Instant Create runs behind a fractal wait splash; Clear reloads the district.
##
## Each panel marks a different curated Mandelbrot postcard. Lock-on → Create without further
## zoom places a recipe on one of the sculpture's highest peaks.
class_name MandelbrotArena
extends Node3D

const MandelbrotPanelScript := preload("res://scripts/city/mandelbrot_panel.gd")
const FractalTerrainMorphScript := preload("res://scripts/city/fractal_terrain_morph.gd")

## Pull panels slightly onto the square so they sit on glowing voxels, not the grass verge.
const EDGE_INSET_M := 0.5
const UI_IDLE := Color(0.08, 0.08, 0.10, 1.0)
const UI_DISSOLVE := Color(0.85, 0.14, 0.12, 1.0)
const UI_BUILD := Color(0.14, 0.85, 0.28, 1.0)
const UI_PULSE_HZ := 1.6
const UI_GLOW_MIN := 1.1
const UI_GLOW_MAX := 4.2
## Spawn order matches south / north / west / east — recipe site index uses this.
const PANEL_EDGE_NAMES: Array[StringName] = [
	FractalTerrainMorphScript.EDGE_SOUTH,
	FractalTerrainMorphScript.EDGE_NORTH,
	FractalTerrainMorphScript.EDGE_WEST,
	FractalTerrainMorphScript.EDGE_EAST,
]

var _morph: FractalTerrainMorph = null
var _brush_getter: Callable = Callable()
var _glow_min: Vector3 = Vector3.ZERO
var _glow_max: Vector3 = Vector3.ZERO
var _ground_y_m: float = 0.0
var _voxel_size: float = 0.5
var _ui_phase: StringName = &"idle"
var _ui_pulse_t: float = 0.0
## Shared Instant checkbox across all four panels.
var _instant: bool = false
var _district_seed: int = 0
var _district_coord: Vector2i = Vector2i.ZERO
## Panel that started the in-flight Create; used to decide whether a peak recipe pays.
var _pending_create_panel: Node3D = null
var _pending_create_locked: bool = false


func setup(
	world_min: Vector3,
	world_max: Vector3,
	ground_y_m: float,
	brush_getter: Callable = Callable(),
	voxel_size: float = 0.5,
	district_seed: int = 0,
	district_coord: Vector2i = Vector2i.ZERO
) -> void:
	name = "MandelbrotArena"
	_brush_getter = brush_getter
	_voxel_size = voxel_size
	_glow_min = world_min
	_glow_max = world_max
	_ground_y_m = ground_y_m
	_district_seed = district_seed
	_district_coord = district_coord
	var min_xz := Vector2(world_min.x, world_min.z)
	var max_xz := Vector2(world_max.x, world_max.z)
	var size := Vector2(max_xz.x - min_xz.x, max_xz.y - min_xz.y)
	if size.x < 20.0 or size.y < 20.0:
		push_error("MandelbrotArena: glow square too small (%s)" % str(size))
		return
	## Force a square footprint even if callers pass a slightly oblong AABB.
	var side := minf(size.x, size.y)
	var center := Vector3(
		(min_xz.x + max_xz.x) * 0.5,
		ground_y_m,
		(min_xz.y + max_xz.y) * 0.5
	)
	var half := side * 0.5 - EDGE_INSET_M
	var panel_y := ground_y_m + MandelbrotPanelScript.PANEL_H * 0.5
	var spots := MandelbrotSpots.pick_for_district(_district_seed, 4)
	## Local −Z is the panel face. Outward on each edge (centre behind the panel).
	## Yaw table is the inward-facing set rotated by π (Ui3D / Godot Y convention).
	_spawn_panel(Vector3(center.x, panel_y, center.z - half), 0.0, spots, 0) ## south → −Z
	_spawn_panel(Vector3(center.x, panel_y, center.z + half), PI, spots, 1) ## north → +Z
	_spawn_panel(Vector3(center.x - half, panel_y, center.z), PI * 0.5, spots, 2) ## west → −X
	_spawn_panel(Vector3(center.x + half, panel_y, center.z), -PI * 0.5, spots, 3) ## east → +X
	_ensure_morph()


func panel_count() -> int:
	var n := 0
	for child in get_children():
		if child.has_method("rebuild_fractal"):
			n += 1
	return n


func morph_node() -> FractalTerrainMorph:
	return _morph


func instant_mode() -> bool:
	return _instant


## Panels that currently show a lock marker / have an assigned postcard (tests).
func lock_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in get_children():
		if child.has_method("lock_spot") and bool(child.call("has_lock_spot")):
			out.append(child.call("lock_spot") as Dictionary)
	return out


func _ensure_morph() -> void:
	if _morph != null and is_instance_valid(_morph):
		_morph.configure(_glow_min, _glow_max, _ground_y_m, _voxel_size, _brush_getter)
	else:
		_morph = FractalTerrainMorphScript.new() as FractalTerrainMorph
		_morph.name = "FractalTerrainMorph"
		add_child(_morph)
		_morph.configure(_glow_min, _glow_max, _ground_y_m, _voxel_size, _brush_getter)
	if not _morph.phase_changed.is_connected(_on_morph_phase_changed):
		_morph.phase_changed.connect(_on_morph_phase_changed)
	if not _morph.morph_finished.is_connected(_on_morph_finished):
		_morph.morph_finished.connect(_on_morph_finished)


func _on_morph_phase_changed(phase: StringName) -> void:
	_ui_phase = phase
	_ui_pulse_t = 0.0
	if phase == FractalTerrainMorphScript.PHASE_IDLE:
		set_process(false)
		_apply_ui_glow(UI_IDLE, 0.0)
	else:
		set_process(true)
		_process(0.0)


func _process(delta: float) -> void:
	if (
		_ui_phase != FractalTerrainMorphScript.PHASE_DISSOLVE
		and _ui_phase != FractalTerrainMorphScript.PHASE_BUILD
	):
		return
	_ui_pulse_t += delta
	var wave := 0.5 + 0.5 * sin(_ui_pulse_t * TAU * UI_PULSE_HZ)
	## Slightly sharper peaks so the throb reads as glow, not a dim blink.
	wave = wave * wave
	var energy := lerpf(UI_GLOW_MIN, UI_GLOW_MAX, wave)
	var color := (
		UI_DISSOLVE if _ui_phase == FractalTerrainMorphScript.PHASE_DISSOLVE else UI_BUILD
	)
	_apply_ui_glow(color, energy)


func _apply_ui_glow(color: Color, emission_energy: float) -> void:
	for child in get_children():
		if child.has_method("set_surface_glow"):
			child.call("set_surface_glow", color, emission_energy)
		elif child.has_method("set_surface_color"):
			child.call("set_surface_color", color)


func _spawn_panel(origin: Vector3, face_yaw: float, spots: Array[Dictionary], edge_index: int) -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", origin, face_yaw)
	if edge_index >= 0 and edge_index < spots.size():
		panel.call("assign_lock_spot", spots[edge_index], edge_index)
	if panel.has_method("set_instant_mode"):
		panel.call("set_instant_mode", _instant)
	if panel.has_signal("instant_changed"):
		panel.connect(
			"instant_changed",
			func(enabled: bool) -> void:
				_on_panel_instant_changed(enabled)
		)
	if panel.has_signal("create_requested"):
		panel.connect(
			"create_requested",
			func(cx_hp: String, cy_hp: String, scale_hp: String) -> void:
				_on_create_requested(cx_hp, cy_hp, scale_hp, panel)
		)
	if panel.has_signal("clear_requested"):
		panel.connect("clear_requested", _on_clear_requested)
	if panel.has_signal("lock_engaged"):
		panel.connect("lock_engaged", _on_lock_engaged.bind(panel))


func _on_lock_engaged(panel: Node3D) -> void:
	var audio := _city_audio()
	if audio != null:
		audio.play_lock_on(panel.global_position)


func _on_panel_instant_changed(enabled: bool) -> void:
	if _instant == enabled:
		return
	_instant = enabled
	for child in get_children():
		if child.has_method("set_instant_mode"):
			child.call("set_instant_mode", enabled)


func _on_create_requested(
	cx_hp: String, cy_hp: String, scale_hp: String, panel: Node3D
) -> void:
	_ensure_morph()
	var edge := _edge_for_panel(panel)
	var instant := _instant
	if panel.has_method("instant_mode"):
		instant = bool(panel.call("instant_mode"))
	_pending_create_panel = panel
	_pending_create_locked = panel.has_method("is_lock_active") and bool(panel.call("is_lock_active"))
	if instant:
		_start_instant_create(cx_hp, cy_hp, scale_hp, edge, panel)
		return
	## Restart — Create always means “use this zoom”, growing from this panel's edge.
	_morph.start(cx_hp, cy_hp, scale_hp, edge, false)


func _start_instant_create(
	cx_hp: String, cy_hp: String, scale_hp: String, edge: StringName, panel: Node3D
) -> void:
	var art: Texture2D = null
	if panel.has_method("bake_texture"):
		art = panel.call("bake_texture") as Texture2D
	var root := get_tree().get_first_node_in_group(&"city_root")
	if root != null and root.has_method("request_fractal_create_wait"):
		var work := func() -> void:
			await _morph.start(cx_hp, cy_hp, scale_hp, edge, true)
		var accepted: bool = bool(root.call("request_fractal_create_wait", art, work))
		if accepted:
			return
		push_error("MandelbrotArena: Instant Create wait rejected — falling back to realtime")
	## No CityRoot (tests) or splash busy: still run instant morph without splash.
	_morph.start(cx_hp, cy_hp, scale_hp, edge, true)


func _on_morph_finished() -> void:
	if not _pending_create_locked:
		_pending_create_panel = null
		return
	var panel := _pending_create_panel
	_pending_create_panel = null
	_pending_create_locked = false
	if panel == null or not is_instance_valid(panel):
		return
	## Still locked after the morph — player did not zoom away mid-bake.
	if panel.has_method("is_lock_active") and not bool(panel.call("is_lock_active")):
		return
	_place_peak_recipe(panel)


func _place_peak_recipe(panel: Node3D) -> void:
	## Largest same-height plateau, not the tip of a thin spire — those are usually unclimbable.
	var peak := _morph.largest_plateau_world()
	if not is_finite(peak.x):
		push_error("MandelbrotArena: locked Create finished with no plateau to host a recipe")
		return
	var dist := get_parent() as DistrictInstance
	if dist == null or dist.recipe_pickups == null or not is_instance_valid(dist.recipe_pickups):
		## Tests may run the arena without a district — still report the site for assertions.
		print("MandelbrotArena: plateau recipe at %s (no placer)" % str(peak))
		return
	var edge_index := int(panel.get("lock_edge_index")) if panel.get("lock_edge_index") != null else -1
	if edge_index < 0:
		edge_index = PANEL_EDGE_NAMES.find(_edge_for_panel(panel))
	var site_seed := _district_seed ^ (0xF2AC0 + edge_index * 0x11)
	## One voxel above the shelf so the scroll sits on it, not inside it.
	var world := peak + Vector3(0.0, _voxel_size, 0.0)
	dist.recipe_pickups.try_place_fractal_peak(
		_district_coord, edge_index, world, site_seed
	)


func _on_clear_requested() -> void:
	if _morph != null and is_instance_valid(_morph):
		_morph.abort()
	_pending_create_panel = null
	_pending_create_locked = false
	var dist := get_parent() as DistrictInstance
	if dist == null:
		push_error("MandelbrotArena: Clear needs a DistrictInstance parent")
		return
	var root := get_tree().get_first_node_in_group(&"city_root")
	if root == null or not root.has_method("request_district_reload"):
		push_error("MandelbrotArena: Clear needs CityRoot.request_district_reload")
		return
	root.call("request_district_reload", dist.coord)


## Which morph edge is nearest the panel (player stands outside, plaza toward centre).
func _edge_for_panel(panel: Node3D) -> StringName:
	var center := Vector3(
		(_glow_min.x + _glow_max.x) * 0.5,
		0.0,
		(_glow_min.z + _glow_max.z) * 0.5
	)
	var p := panel.global_position
	var dx := p.x - center.x
	var dz := p.z - center.z
	if absf(dz) >= absf(dx):
		return FractalTerrainMorphScript.EDGE_SOUTH if dz < 0.0 else FractalTerrainMorphScript.EDGE_NORTH
	return FractalTerrainMorphScript.EDGE_WEST if dx < 0.0 else FractalTerrainMorphScript.EDGE_EAST


func _city_audio() -> CityAudio:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group(CityAudio.GROUP_NAME)
	if nodes.is_empty():
		return null
	return nodes[0] as CityAudio
