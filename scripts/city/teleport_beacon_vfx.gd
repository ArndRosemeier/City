## The column of light standing on a teleport pad, visible across the district.
##
## Same shader as InfectionSkyBeamVfx, but cyan and slow: the infection beam is a warning, this
## is a landmark. It rises out of the chamber's open roof so you can walk to it from anywhere
## on the tile without a map.
class_name TeleportBeaconVfx
extends Node3D

const HEIGHT_M := 120.0
## Wide enough to hold up across a district. A slimmer column reads fine from the pad and
## disappears into the roofline two blocks away, which defeats the point of having one.
const CORE_RADIUS_M := 1.1
const HALO_RADIUS_M := 3.4
## Slow enough to read as a steady signal rather than an alarm.
const PULSE_HZ := 0.45
const CORE_COLOR := Color(0.35, 0.92, 1.0, 0.85)
const HALO_COLOR := Color(0.12, 0.55, 0.95, 0.22)

var _mat_core: ShaderMaterial = null
var _mat_halo: ShaderMaterial = null
var _age: float = 0.0


func plant_at(world_pos: Vector3) -> void:
	_ensure_mesh()
	global_position = world_pos
	global_rotation = Vector3.ZERO
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var pulse := 0.5 + 0.5 * sin(_age * TAU * PULSE_HZ)
	_apply_intensity(lerpf(0.85, 1.15, pulse))


func _apply_intensity(amount: float) -> void:
	if _mat_core == null:
		return
	_mat_core.set_shader_parameter("intensity", amount)
	_mat_halo.set_shader_parameter("intensity", amount * 0.5)


func _ensure_mesh() -> void:
	if _mat_core != null:
		return
	_mat_core = _make_mat(CORE_COLOR, 6.5, 1.6)
	_mat_halo = _make_mat(HALO_COLOR, 2.6, 1.1)
	_make_cylinder("Core", CORE_RADIUS_M, _mat_core)
	_make_cylinder("Halo", HALO_RADIUS_M, _mat_halo)
	_apply_intensity(1.0)


func _make_cylinder(node_name: String, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.35
	mesh.bottom_radius = radius
	mesh.height = HEIGHT_M
	mesh.radial_segments = 12
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, HEIGHT_M * 0.5, 0.0)
	add_child(mi)


func _make_mat(color: Color, emission: float, scroll: float) -> ShaderMaterial:
	var shader: Shader = load("res://assets/city/shaders/infection_sky_beam.gdshader") as Shader
	if shader == null:
		push_error("TeleportBeaconVfx: beam shader missing")
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("beam_color", color)
	mat.set_shader_parameter("emission_mul", emission)
	mat.set_shader_parameter("scroll_speed", scroll)
	mat.set_shader_parameter("intensity", 1.0)
	mat.set_shader_parameter("fade_top", 0.9)
	mat.set_shader_parameter("streak_count", 5.0)
	return mat
