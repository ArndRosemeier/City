## Continuous green repair channel: thick wobbling cylinder from hand to target.
## Pose is owned by CityWalker (Spell_Simple_Idle); this only draws the beam.
class_name RepairBeamVfx
extends Node3D

@export var core_radius_m: float = 0.14
@export var glow_radius_m: float = 0.32
@export var wobble_hz: float = 7.5
@export var wobble_amp: float = 0.055
@export var pulse_hz: float = 3.2

var _root: Node3D
var _core_mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _core_mesh: CylinderMesh
var _glow_mesh: CylinderMesh
var _mat_core: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _light: OmniLight3D
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _active: bool = false


func start(from: Vector3, to: Vector3) -> void:
	_ensure_mesh()
	_from = from
	_to = to
	_age = 0.0
	_active = true
	visible = true
	set_process(true)
	_layout()


func set_endpoints(from: Vector3, to: Vector3) -> void:
	_ensure_mesh()
	_from = from
	_to = to
	if not _active:
		_active = true
		visible = true
		set_process(true)
	_layout()


func stop() -> void:
	_active = false
	visible = false
	set_process(false)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	_layout()


func _layout() -> void:
	if _root == null:
		return
	var delta := _to - _from
	var length := delta.length()
	if length < 0.08:
		visible = false
		return
	visible = true
	var dir := delta / length
	## Lateral wobble so the beam reads as living energy, not a rigid stick.
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up_axis := side.cross(dir).normalized()
	var wobble := sin(_age * TAU * wobble_hz)
	var lateral := side * (wobble * wobble_amp * length * 0.04)
	var mid := (_from + _to) * 0.5 + lateral
	global_position = mid
	## CylinderMesh is Y-up; align local +Y with the beam axis.
	var basis := Basis()
	basis.y = dir
	basis.x = side
	basis.z = up_axis
	global_transform = Transform3D(basis.orthonormalized(), mid)

	var pulse := 0.85 + 0.15 * sin(_age * TAU * pulse_hz)
	var rad_mul := 1.0 + wobble_amp * 2.2 * absf(wobble)
	_core_mesh.height = length
	_core_mesh.top_radius = core_radius_m * rad_mul
	_core_mesh.bottom_radius = core_radius_m * rad_mul * 1.05
	_glow_mesh.height = length
	_glow_mesh.top_radius = glow_radius_m * rad_mul
	_glow_mesh.bottom_radius = glow_radius_m * rad_mul * 1.08
	_mat_core.emission_energy_multiplier = 4.5 * pulse
	_mat_glow.emission_energy_multiplier = 1.8 * pulse
	if _light != null:
		_light.light_energy = 2.4 * pulse
		_light.omni_range = 3.5 + length * 0.08


func _ensure_mesh() -> void:
	if _root != null:
		return
	_root = Node3D.new()
	_root.name = "Beam"
	add_child(_root)

	_core_mesh = CylinderMesh.new()
	_core_mesh.height = 1.0
	_core_mesh.top_radius = core_radius_m
	_core_mesh.bottom_radius = core_radius_m
	_core_mesh.radial_segments = 12

	_glow_mesh = CylinderMesh.new()
	_glow_mesh.height = 1.0
	_glow_mesh.top_radius = glow_radius_m
	_glow_mesh.bottom_radius = glow_radius_m
	_glow_mesh.radial_segments = 12

	_mat_core = StandardMaterial3D.new()
	_mat_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_core.albedo_color = Color(0.45, 1.0, 0.55, 1.0)
	_mat_core.emission_enabled = true
	_mat_core.emission = Color(0.25, 0.95, 0.4)
	_mat_core.emission_energy_multiplier = 4.5
	_mat_core.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	_mat_glow = StandardMaterial3D.new()
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow.albedo_color = Color(0.2, 0.85, 0.35, 0.35)
	_mat_glow.emission_enabled = true
	_mat_glow.emission = Color(0.15, 0.7, 0.3)
	_mat_glow.emission_energy_multiplier = 1.8
	_mat_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_glow.cull_mode = BaseMaterial3D.CULL_DISABLED

	_glow_mi = MeshInstance3D.new()
	_glow_mi.mesh = _glow_mesh
	_glow_mi.material_override = _mat_glow
	_glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_glow_mi)

	_core_mi = MeshInstance3D.new()
	_core_mi.mesh = _core_mesh
	_core_mi.material_override = _mat_core
	_core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_core_mi)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 1.0, 0.5)
	_light.light_energy = 2.4
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_root.add_child(_light)

	visible = false
	set_process(false)
