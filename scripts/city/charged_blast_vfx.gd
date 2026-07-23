## Slow red charged bomb: arcs to the aim point, pulses while flying, explodes on contact.
class_name ChargedBlastVfx
extends Node3D

signal impact(hit_point: Vector3, direction: Vector3, radius_m: float)

@export var speed_mps: float = 10.0
@export var base_emission: float = 14.0
@export var arc_height_frac: float = 0.28
@export var arc_height_min_m: float = 1.8

var _root: Node3D
var _core_mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _core_mesh: SphereMesh
var _glow_mesh: SphereMesh
var _mat_core: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _light: OmniLight3D
var _active: bool = false
var _origin: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _radius_m: float = 1.0
var _visual_scale: float = 1.0
var _duration: float = 0.5
var _elapsed: float = 0.0
var _phase: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO
var _obstacle_probe: Callable = Callable()


func setup() -> void:
	_ensure_mesh()


func set_obstacle_probe(probe: Callable) -> void:
	_obstacle_probe = probe


func is_firing() -> bool:
	return _active


func fire(
	origin: Vector3,
	aim_point: Vector3,
	blast_radius_m: float,
	projectile_speed: float = -1.0,
	visual_scale: float = 1.0
) -> void:
	_ensure_mesh()
	if _root == null:
		return
	var delta := aim_point - origin
	var dist := delta.length()
	if dist < 0.35:
		return
	_origin = origin
	_target = aim_point
	_radius_m = maxf(blast_radius_m, 0.35)
	_visual_scale = maxf(visual_scale, 0.05)
	if projectile_speed > 0.0:
		speed_mps = projectile_speed
	_duration = maxf(dist / maxf(speed_mps, 0.1), 0.2)
	_elapsed = 0.0
	_phase = 0.0
	_prev_pos = origin
	_active = true
	_reparent_to_world()
	_root.visible = true
	if _light != null:
		_light.visible = true
	_apply_pulse(0.0)
	_root.global_position = origin
	## Immediate ped/car probe along the straight segment.
	if _obstacle_probe.is_valid():
		var hit0: Variant = _obstacle_probe.call(origin, aim_point)
		if typeof(hit0) == TYPE_FLOAT or typeof(hit0) == TYPE_INT:
			var d0 := float(hit0)
			if d0 >= 0.0 and d0 < dist:
				_retarget_along(origin, aim_point, d0)
	set_process(true)


func _retarget_along(from: Vector3, to: Vector3, dist: float) -> void:
	var seg := to - from
	var len := seg.length()
	if len < 0.05:
		return
	_target = from + seg * (clampf(dist, 0.05, len) / len)
	_duration = maxf(_target.distance_to(_origin) / maxf(speed_mps, 0.1), 0.12)
	_elapsed = 0.0


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	_elapsed += delta
	_phase += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var pos := _sample_arc(t)
	## Mid-flight: shorten if the bomb sweeps into an agent.
	if _obstacle_probe.is_valid() and t < 0.98:
		var hit_d: Variant = _obstacle_probe.call(_prev_pos, pos)
		if typeof(hit_d) == TYPE_FLOAT or typeof(hit_d) == TYPE_INT:
			var d := float(hit_d)
			if d >= 0.0 and d < _prev_pos.distance_to(pos):
				var seg := pos - _prev_pos
				var seg_len := seg.length()
				if seg_len > 0.001:
					pos = _prev_pos + seg * (d / seg_len)
				_finish_impact(pos)
				return
	_root.global_position = pos
	_apply_pulse(t)
	_prev_pos = pos
	if t >= 1.0:
		_finish_impact(_target)


func _sample_arc(t: float) -> Vector3:
	var flat := _target - _origin
	var horiz := Vector3(flat.x, 0.0, flat.z)
	var horiz_len := horiz.length()
	var apex := maxf(horiz_len * arc_height_frac, arc_height_min_m)
	var pos := _origin.lerp(_target, t)
	pos.y += apex * 4.0 * t * (1.0 - t)
	return pos


func _apply_pulse(_flight_t: float) -> void:
	## Expanding / contracting red glow while underway (subtle).
	var breath := 0.5 + 0.5 * sin(_phase * 7.5)
	var throb := 0.5 + 0.5 * sin(_phase * 13.0 + 0.7)
	## Half prior size; pulse amplitude also halved vs the old 0.12 / glow swing.
	var size := _radius_m * (0.11 + 0.06 * breath) * (0.85 + 0.2 * _visual_scale)
	size = maxf(size, 0.06)
	if _core_mesh != null:
		_core_mesh.radius = size
		_core_mesh.height = size * 2.0
	if _glow_mesh != null:
		_glow_mesh.radius = size * (1.85 + 0.225 * throb)
		_glow_mesh.height = _glow_mesh.radius * 2.0
	var flash := 0.55 + 0.45 * throb
	if _mat_core != null:
		_mat_core.albedo_color = Color(1.0, 0.18 + 0.2 * flash, 0.05)
		_mat_core.emission = Color(1.0, 0.12 + 0.25 * flash, 0.02)
		_mat_core.emission_energy_multiplier = base_emission * (1.1 + 1.4 * flash)
	if _mat_glow != null:
		_mat_glow.albedo_color = Color(1.0, 0.15, 0.02, 0.2 + 0.25 * breath)
		_mat_glow.emission = Color(1.0, 0.2, 0.05)
		_mat_glow.emission_energy_multiplier = base_emission * 0.55 * (0.8 + 0.9 * flash)
	if _light != null:
		_light.light_color = Color(1.0, 0.25 + 0.2 * flash, 0.05)
		_light.light_energy = 5.0 + 12.0 * flash
		_light.omni_range = size * (6.0 + 1.5 * breath)


func _finish_impact(hit: Vector3) -> void:
	var dir := hit - _prev_pos
	if dir.length_squared() < 0.0001:
		dir = _target - _origin
	if dir.length_squared() < 0.0001:
		dir = Vector3.DOWN
	else:
		dir = dir.normalized()
	_active = false
	if _root != null:
		_root.visible = false
	if _light != null:
		_light.visible = false
	set_process(false)
	impact.emit(hit, dir, _radius_m)


func _exit_tree() -> void:
	_free_mesh()


func _ensure_mesh() -> void:
	if _root != null and is_instance_valid(_root):
		return

	_mat_core = _make_mat(Color(1.0, 0.2, 0.05), Color(1.0, 0.15, 0.02), false)
	_mat_glow = _make_mat(Color(1.0, 0.12, 0.02, 0.28), Color(1.0, 0.2, 0.05), true)

	_root = Node3D.new()
	_root.name = "ChargedBlastOrb"
	add_child(_root)

	_core_mesh = SphereMesh.new()
	_core_mesh.radial_segments = 20
	_core_mesh.rings = 12
	_glow_mesh = SphereMesh.new()
	_glow_mesh.radial_segments = 16
	_glow_mesh.rings = 10

	_glow_mi = _make_mi("Glow", _glow_mesh, _mat_glow)
	_core_mi = _make_mi("Core", _core_mesh, _mat_core)
	_root.add_child(_glow_mi)
	_root.add_child(_core_mi)

	_light = OmniLight3D.new()
	_light.name = "BlastLight"
	_light.light_color = Color(1.0, 0.3, 0.05)
	_light.light_energy = 8.0
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.visible = false
	_root.add_child(_light)

	_root.visible = false
	set_process(false)


func _make_mat(albedo: Color, emission: Color, transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = base_emission
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat


func _make_mi(mi_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mi_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _reparent_to_world() -> void:
	var host := _resolve_world_host()
	if host == null or _root == null:
		return
	if _root.get_parent() == host:
		return
	var keep: Transform3D = _root.global_transform
	if _root.get_parent() != null:
		_root.get_parent().remove_child(_root)
	host.add_child(_root)
	_root.global_transform = keep


func _resolve_world_host() -> Node:
	if get_tree() != null and get_tree().current_scene != null:
		return get_tree().current_scene
	var p: Node = get_parent()
	while p != null:
		if String(p.name) == "CityRoot" or String(p.name) == "CityPoc":
			return p
		p = p.get_parent()
	return get_parent()


func _free_mesh() -> void:
	_active = false
	set_process(false)
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_core_mi = null
	_glow_mi = null
	_core_mesh = null
	_glow_mesh = null
	_mat_core = null
	_mat_glow = null
	_light = null
