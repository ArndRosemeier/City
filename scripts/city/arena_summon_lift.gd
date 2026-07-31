## Under-pit summon elevator spectacle for the Arena district.
##
## Lights the shaft, raises a freshly spawned catalogue body from the undercroft to the
## sand pad inside a bright light column, then releases AI. Does not reuse city
## ElevatorShaft cabin UX.
class_name ArenaSummonLift
extends Node3D

signal delivery_finished(unit: UndeadUnit)
signal delivery_failed(monster_id: String)

## Was 1.35 s — doubled so the rise reads as a spectacle.
const RISE_SEC := 2.7
const LIGHT_PEAK := 6.5
const COLUMN_LIGHT_PEAK := 8.0
const LIFT_HALF_VOX := 3
## Soft fade after the pad locks so the column does not pop off.
const COLUMN_FADE_SEC := 0.45
const COLUMN_H_M := 3.6

var pad_local: Vector2i = Vector2i.ZERO
var sand_y: int = 6
var undercroft_h: int = 10
var voxel_size: float = 0.5
var origin_vox: Vector3i = Vector3i.ZERO
var busy: bool = false

var _light: OmniLight3D = null
var _column_light: OmniLight3D = null
var _column: MeshInstance3D = null
var _column_mat: StandardMaterial3D = null
var _platform: MeshInstance3D = null
var _spawn_cb: Callable = Callable()


func setup(
	p_pad: Vector2i,
	p_sand_y: int,
	p_undercroft_h: int,
	p_origin_vox: Vector3i,
	p_voxel_size: float,
	spawn_monster: Callable
) -> void:
	pad_local = p_pad
	sand_y = p_sand_y
	undercroft_h = p_undercroft_h
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	_spawn_cb = spawn_monster
	name = "ArenaSummonLift_%d_%d" % [pad_local.x, pad_local.y]
	global_position = _world_at(pad_local.x, sand_y, pad_local.y)
	_build_visuals()


func is_busy() -> bool:
	return busy


func deliver(monster_id: String) -> void:
	if busy:
		push_warning("ArenaSummonLift: busy, rejected '%s'" % monster_id)
		delivery_failed.emit(monster_id)
		return
	if monster_id.is_empty():
		push_error("ArenaSummonLift.deliver: empty id")
		delivery_failed.emit(monster_id)
		return
	if not _spawn_cb.is_valid():
		push_error("ArenaSummonLift.deliver: no spawn callback")
		delivery_failed.emit(monster_id)
		return
	busy = true
	_set_shaft_light(true)
	var bottom := _world_at(pad_local.x, sand_y - undercroft_h + 2, pad_local.y)
	var top := _world_at(pad_local.x, sand_y + 1, pad_local.y)
	var unit: UndeadUnit = _spawn_cb.call(monster_id, bottom) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		_set_shaft_light(false)
		_hide_column()
		busy = false
		delivery_failed.emit(monster_id)
		return
	ArenaCombat.tag_unit(unit)
	## Hold AI/physics during the rise — CharacterBody3D has no freeze flag.
	unit.velocity = Vector3.ZERO
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.global_position = bottom
	if _platform != null:
		_platform.visible = true
		_platform.global_position = bottom + Vector3(0.0, -0.15, 0.0)
	_show_column_at(bottom)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "global_position", top, RISE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	if _platform != null:
		tw.tween_property(
			_platform, "global_position", top + Vector3(0.0, -0.15, 0.0), RISE_SEC
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _column != null:
		tw.tween_property(
			_column, "global_position", _column_center(top), RISE_SEC
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _column_light != null:
		tw.tween_property(
			_column_light, "global_position", top + Vector3(0.0, COLUMN_H_M * 0.45, 0.0), RISE_SEC
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_column_light, "light_energy", COLUMN_LIGHT_PEAK, RISE_SEC * 0.35).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
	if _column_mat != null:
		tw.tween_property(_column_mat, "emission_energy_multiplier", 6.5, RISE_SEC * 0.4).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
		tw.tween_property(_column_mat, "albedo_color:a", 0.55, RISE_SEC * 0.35)
	await tw.finished
	if not is_instance_valid(unit):
		_set_shaft_light(false)
		_hide_column()
		busy = false
		delivery_failed.emit(monster_id)
		return
	unit.global_position = top
	unit.process_mode = Node.PROCESS_MODE_INHERIT
	await _fade_column_out()
	_set_shaft_light(false)
	if _platform != null:
		_platform.visible = false
	busy = false
	delivery_finished.emit(unit)


func _world_at(lx: int, ly: int, lz: int) -> Vector3:
	return Vector3(
		(float(origin_vox.x + lx) + 0.5) * voxel_size,
		float(ly) * voxel_size,
		(float(origin_vox.z + lz) + 0.5) * voxel_size
	)


func _build_visuals() -> void:
	_light = OmniLight3D.new()
	_light.name = "ShaftLight"
	_light.light_color = Color(1.0, 0.82, 0.45)
	_light.light_energy = 0.0
	_light.omni_range = float(LIFT_HALF_VOX * 2 + 4) * voxel_size
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0.0, -float(undercroft_h) * 0.5 * voxel_size, 0.0)

	_column = MeshInstance3D.new()
	_column.name = "LightColumn"
	var cyl := CylinderMesh.new()
	## Fits inside the lift pad; tall enough to wrap a standing catalogue body.
	cyl.top_radius = float(LIFT_HALF_VOX) * voxel_size * 0.85
	cyl.bottom_radius = float(LIFT_HALF_VOX) * voxel_size * 0.95
	cyl.height = COLUMN_H_M
	cyl.radial_segments = 20
	cyl.rings = 1
	_column.mesh = cyl
	_column_mat = StandardMaterial3D.new()
	_column_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_column_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_column_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_column_mat.albedo_color = Color(1.0, 0.92, 0.55, 0.0)
	_column_mat.emission_enabled = true
	_column_mat.emission = Color(1.0, 0.85, 0.4)
	_column_mat.emission_energy_multiplier = 0.0
	_column_mat.disable_receive_shadows = true
	_column.material_override = _column_mat
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	add_child(_column)

	_column_light = OmniLight3D.new()
	_column_light.name = "ColumnLight"
	_column_light.light_color = Color(1.0, 0.9, 0.55)
	_column_light.light_energy = 0.0
	_column_light.omni_range = float(LIFT_HALF_VOX * 2 + 6) * voxel_size
	_column_light.shadow_enabled = false
	_column_light.visible = false
	add_child(_column_light)

	_platform = MeshInstance3D.new()
	_platform.name = "Platform"
	var box := BoxMesh.new()
	box.size = Vector3(
		float(LIFT_HALF_VOX * 2 + 1) * voxel_size * 0.92,
		0.08,
		float(LIFT_HALF_VOX * 2 + 1) * voxel_size * 0.92
	)
	_platform.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.48, 0.38)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.35)
	mat.emission_energy_multiplier = 0.8
	_platform.material_override = mat
	_platform.visible = false
	add_child(_platform)


func _column_center(feet: Vector3) -> Vector3:
	return feet + Vector3(0.0, COLUMN_H_M * 0.5, 0.0)


func _show_column_at(feet: Vector3) -> void:
	if _column != null:
		_column.visible = true
		_column.global_position = _column_center(feet)
		if _column_mat != null:
			_column_mat.albedo_color.a = 0.12
			_column_mat.emission_energy_multiplier = 1.2
	if _column_light != null:
		_column_light.visible = true
		_column_light.global_position = feet + Vector3(0.0, COLUMN_H_M * 0.45, 0.0)
		_column_light.light_energy = COLUMN_LIGHT_PEAK * 0.35


func _hide_column() -> void:
	if _column != null:
		_column.visible = false
	if _column_light != null:
		_column_light.visible = false
		_column_light.light_energy = 0.0
	if _column_mat != null:
		_column_mat.albedo_color.a = 0.0
		_column_mat.emission_energy_multiplier = 0.0


func _fade_column_out() -> void:
	if _column == null and _column_light == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	if _column_mat != null:
		tw.tween_property(_column_mat, "emission_energy_multiplier", 0.0, COLUMN_FADE_SEC)
		tw.tween_property(_column_mat, "albedo_color:a", 0.0, COLUMN_FADE_SEC)
	if _column_light != null:
		tw.tween_property(_column_light, "light_energy", 0.0, COLUMN_FADE_SEC)
	await tw.finished
	_hide_column()


func _set_shaft_light(on: bool) -> void:
	if _light == null:
		return
	_light.light_energy = LIGHT_PEAK if on else 0.0
