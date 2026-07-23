## Single eye-laser dart: long shaft, sharp tip, one shot per fire().
## Glows and morphs (length / thickness / spin / color) while traveling.
class_name EyeLaserVfx
extends Node3D

signal impact(hit_point: Vector3, direction: Vector3)

@export var shaft_length_m: float = 4.4
@export var tip_length_m: float = 1.1
@export var shaft_radius_m: float = 0.11
@export var tip_base_radius_m: float = 0.11
@export var speed_mps: float = 30.0
@export var base_emission: float = 12.0

var _root: Node3D
var _shaft_mi: MeshInstance3D
var _tip_mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _shaft_mesh: CylinderMesh
var _tip_mesh: CylinderMesh
var _glow_mesh: CylinderMesh
var _mat_core: StandardMaterial3D
var _mat_tip: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _light: OmniLight3D
var _active: bool = false
var _character_scale: float = 1.0
var _origin: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.FORWARD
var _aim_dist: float = 0.0
var _traveled: float = 0.0
var _phase: float = 0.0
var _spin: float = 0.0
## Visual morph multipliers (hit detection uses base length only).
var _len_mul: float = 1.0
var _rad_mul: float = 1.0
var _tip_mul: float = 1.0
## Optional: (from: Vector3, tip: Vector3) -> float distance, or -1 if clear.
var _obstacle_probe: Callable = Callable()


func setup(_skeleton: Skeleton3D = null, _camera: Camera3D = null) -> void:
	_ensure_mesh()


func set_obstacle_probe(probe: Callable) -> void:
	_obstacle_probe = probe


func set_character_scale(scale: float) -> void:
	_character_scale = maxf(scale, 0.05)
	_apply_size()


func is_firing() -> bool:
	return _active


func _base_total() -> float:
	return (shaft_length_m + tip_length_m) * _character_scale


func _visual_total() -> float:
	return _base_total() * _len_mul


## One click → one dart. Rear starts at origin (eyes); tip points at aim.
## character_scale multiplies dart size (damage carve uses walker scale separately).
func fire(
	origin: Vector3,
	aim_point: Vector3,
	projectile_speed: float = -1.0,
	character_scale: float = -1.0
) -> void:
	_ensure_mesh()
	if _root == null:
		return
	if character_scale > 0.0:
		set_character_scale(character_scale)
	var delta := aim_point - origin
	var dist := delta.length()
	if dist < 0.25:
		return
	_dir = delta / dist
	_origin = origin
	_aim_dist = dist
	_traveled = 0.0
	_phase = 0.0
	_spin = 0.0
	_len_mul = 1.0
	_rad_mul = 1.0
	_tip_mul = 1.0
	if projectile_speed > 0.0:
		speed_mps = projectile_speed
	_active = true
	_apply_size()
	_reparent_to_world()
	_root.visible = true
	if _light != null:
		_light.visible = true
	## Immediate probe so a ped/car already inside the dart length registers now.
	if _obstacle_probe.is_valid():
		var tip0 := _origin + _dir * minf(_base_total(), _aim_dist)
		var hit0: Variant = _obstacle_probe.call(_origin, tip0)
		if typeof(hit0) == TYPE_FLOAT or typeof(hit0) == TYPE_INT:
			var d0 := float(hit0)
			if d0 >= 0.0 and d0 < _aim_dist:
				_aim_dist = maxf(d0, 0.05)
	if _base_total() >= _aim_dist:
		_finish_impact()
		return
	_animate_shape(0.0)
	_orient()
	set_process(true)


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	_traveled += speed_mps * delta
	_phase += delta
	_spin += delta * (9.0 + 6.0 * sin(_phase * 3.1))
	## Mid-flight: stop early if the tip has swept into a ped/car.
	if _obstacle_probe.is_valid():
		var tip_along := minf(_traveled + _base_total(), _aim_dist)
		var tip := _origin + _dir * tip_along
		var hit_d: Variant = _obstacle_probe.call(_origin, tip)
		if typeof(hit_d) == TYPE_FLOAT or typeof(hit_d) == TYPE_INT:
			var d := float(hit_d)
			if d >= 0.0 and d < _aim_dist:
				_aim_dist = maxf(d, 0.05)
	_animate_shape(delta)
	_orient()
	if _traveled + _base_total() >= _aim_dist:
		_finish_impact()


func _animate_shape(_delta: float) -> void:
	## Stretch / squash along flight + breathing thickness + tip flare.
	var wave_a := sin(_phase * 14.0)
	var wave_b := sin(_phase * 7.5 + 1.2)
	var wave_c := sin(_phase * 22.0 + 0.4)
	_len_mul = 0.72 + 0.38 * wave_a + 0.12 * wave_b
	_rad_mul = 0.55 + 0.55 * (0.5 + 0.5 * wave_b) + 0.15 * wave_c
	_tip_mul = 0.7 + 0.55 * (0.5 + 0.5 * sin(_phase * 18.0 + 0.8))
	_apply_size()

	## Hot core ↔ cooler cyan, with a white flash beat.
	var flash := 0.55 + 0.45 * sin(_phase * 20.0)
	var cool := 0.5 + 0.5 * sin(_phase * 5.5)
	if _mat_core != null:
		_mat_core.emission = Color(0.15 + 0.35 * cool, 0.75 + 0.2 * flash, 1.0)
		_mat_core.emission_energy_multiplier = base_emission * (0.9 + 1.1 * flash)
		_mat_core.albedo_color = Color(0.35 + 0.4 * flash, 0.9, 1.0)
	if _mat_tip != null:
		_mat_tip.emission = Color(0.7 + 0.3 * flash, 0.95, 1.0)
		_mat_tip.emission_energy_multiplier = base_emission * (1.4 + 1.6 * flash)
		_mat_tip.albedo_color = Color(0.85, 0.98, 1.0)
	if _mat_glow != null:
		_mat_glow.emission_energy_multiplier = base_emission * 0.45 * (0.7 + 0.6 * flash)
		_mat_glow.albedo_color = Color(0.2, 0.85, 1.0, 0.18 + 0.22 * flash)
	if _light != null:
		_light.light_energy = 4.0 + 10.0 * flash
		_light.light_color = Color(0.35 + 0.4 * cool, 0.85, 1.0)
		_light.omni_range = (2.5 + 2.0 * _rad_mul) * _character_scale


func _finish_impact() -> void:
	var hit := _origin + _dir * _aim_dist
	_active = false
	if _root != null:
		_root.visible = false
	if _light != null:
		_light.visible = false
	set_process(false)
	impact.emit(hit, _dir)


func _exit_tree() -> void:
	_free_mesh()


func _ensure_mesh() -> void:
	if _root != null and is_instance_valid(_root):
		return

	_mat_core = _make_mat(Color(0.45, 0.96, 1.0), Color(0.25, 0.9, 1.0), false)
	_mat_tip = _make_mat(Color(0.9, 0.98, 1.0), Color(0.7, 0.95, 1.0), false)
	_mat_glow = _make_mat(Color(0.2, 0.85, 1.0, 0.25), Color(0.15, 0.8, 1.0), true)

	_root = Node3D.new()
	_root.name = "LaserDart"
	add_child(_root)

	_shaft_mesh = CylinderMesh.new()
	_shaft_mesh.radial_segments = 18
	_shaft_mesh.cap_top = true
	_shaft_mesh.cap_bottom = true

	_tip_mesh = CylinderMesh.new()
	_tip_mesh.radial_segments = 18
	_tip_mesh.top_radius = 0.0
	_tip_mesh.cap_top = true
	_tip_mesh.cap_bottom = true

	_glow_mesh = CylinderMesh.new()
	_glow_mesh.radial_segments = 14
	_glow_mesh.cap_top = false
	_glow_mesh.cap_bottom = false

	_glow_mi = _make_mi("GlowSheath", _glow_mesh, _mat_glow)
	_shaft_mi = _make_mi("Shaft", _shaft_mesh, _mat_core)
	_tip_mi = _make_mi("Tip", _tip_mesh, _mat_tip)
	_root.add_child(_glow_mi)
	_root.add_child(_shaft_mi)
	_root.add_child(_tip_mi)

	_light = OmniLight3D.new()
	_light.name = "DartLight"
	_light.light_color = Color(0.4, 0.9, 1.0)
	_light.light_energy = 6.0
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.visible = false
	_root.add_child(_light)

	_apply_size()
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


func _apply_size() -> void:
	var s := _character_scale
	var shaft_len := shaft_length_m * s * _len_mul
	var tip_len := tip_length_m * s * _len_mul * _tip_mul
	var shaft_r := shaft_radius_m * s * _rad_mul
	var tip_r := tip_base_radius_m * s * _rad_mul
	var glow_r := shaft_r * (2.2 + 0.8 * _rad_mul)
	var glow_len := shaft_len + tip_len * 0.65

	if _shaft_mesh != null:
		_shaft_mesh.height = shaft_len
		## Tapered shaft: thicker rear, thinner toward tip.
		_shaft_mesh.bottom_radius = shaft_r * 1.25
		_shaft_mesh.top_radius = shaft_r * 0.55
	if _tip_mesh != null:
		_tip_mesh.height = tip_len
		_tip_mesh.top_radius = 0.0
		_tip_mesh.bottom_radius = tip_r
	if _glow_mesh != null:
		_glow_mesh.height = glow_len
		_glow_mesh.top_radius = glow_r * 0.7
		_glow_mesh.bottom_radius = glow_r

	## +Y = flight: shaft behind, tip ahead. Soft sheath around both.
	var tip_pos_y := shaft_len * 0.5
	var shaft_pos_y := -tip_len * 0.5
	if _shaft_mi != null:
		_shaft_mi.position = Vector3(0.0, shaft_pos_y, 0.0)
	if _tip_mi != null:
		_tip_mi.position = Vector3(0.0, tip_pos_y, 0.0)
	if _glow_mi != null:
		_glow_mi.position = Vector3(0.0, (shaft_pos_y + tip_pos_y) * 0.35, 0.0)
	if _light != null:
		_light.position = Vector3(0.0, tip_pos_y * 0.6, 0.0)


func _orient() -> void:
	if _root == null:
		return
	var total := _visual_total()
	var rear := _origin + _dir * _traveled
	var center := rear + _dir * (total * 0.5)
	var y_axis := _dir
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 1e-10:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	## Spin around flight axis for a living, twisting dart.
	var basis := Basis(x_axis, y_axis, z_axis)
	basis = basis.rotated(y_axis, _spin)
	_root.global_transform = Transform3D(basis, center)


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
	_shaft_mi = null
	_tip_mi = null
	_glow_mi = null
	_shaft_mesh = null
	_tip_mesh = null
	_glow_mesh = null
	_mat_core = null
	_mat_tip = null
	_mat_glow = null
	_light = null
