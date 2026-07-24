## Slim 100 m sinister beam — infection energy transmitting into space.
## After impact the beam stays permanently as a crater marker (no fade / no free).
extends Node3D

const HEIGHT_M := 100.0
const CORE_RADIUS_M := 0.22
const HALO_RADIUS_M := 0.95

@export var follow_pulse_hz: float = 2.2
@export var planted_pulse_hz: float = 1.6
@export var impact_surge_sec: float = 0.85

var _core_mi: MeshInstance3D
var _halo_mi: MeshInstance3D
var _mat_core: ShaderMaterial
var _mat_halo: ShaderMaterial
var _follow: Node3D
var _planted: bool = false
var _age: float = 0.0
var _planted_age: float = 0.0
var _intensity: float = 1.0


static func attach_to_meteor(host: Node, meteor: Node3D) -> Node:
	if host == null or meteor == null:
		return null
	var script: Script = load("res://scripts/city/infection_sky_beam_vfx.gd") as Script
	var beam: Node = script.new() as Node
	beam.name = "InfectionSkyBeam"
	host.add_child(beam)
	beam.call("start_following", meteor)
	return beam


func start_following(target: Node3D) -> void:
	_ensure_mesh()
	_follow = target
	_planted = false
	_age = 0.0
	_intensity = 1.0
	visible = true
	set_process(true)
	_snap_to_follow()


## Pin the beam at the crater forever.
func start_lingering(world_pos: Vector3, _duration_sec: float = -1.0) -> void:
	_ensure_mesh()
	_follow = null
	_planted = true
	_planted_age = 0.0
	global_position = world_pos
	global_rotation = Vector3.ZERO
	_intensity = 1.4
	visible = true
	set_process(true)
	_apply_intensity(_intensity)


func _process(delta: float) -> void:
	_age += delta
	if _follow != null and is_instance_valid(_follow):
		_snap_to_follow()
		var pulse := 0.55 + 0.45 * sin(_age * TAU * follow_pulse_hz)
		_intensity = lerpf(0.85, 1.35, pulse)
		_apply_intensity(_intensity)
		return

	if not _planted:
		## Follow target gone without planting — keep last pose, still pulse forever.
		_planted = true
		_planted_age = 0.0

	_planted_age += delta
	var surge := 0.0
	if _planted_age < impact_surge_sec:
		var surge_t := clampf(_planted_age / maxf(impact_surge_sec, 0.05), 0.0, 1.0)
		surge = sin(surge_t * PI) * 1.8
	var pulse2 := 0.55 + 0.45 * sin(_age * TAU * planted_pulse_hz)
	## Never fade to zero — steady permanent marker.
	_intensity = lerpf(1.05, 1.45, pulse2) + surge
	_apply_intensity(_intensity)


func _snap_to_follow() -> void:
	## World-up only — do not inherit the spinning meteor basis.
	global_position = _follow.global_position
	global_rotation = Vector3.ZERO


func _apply_intensity(amount: float) -> void:
	if _mat_core != null:
		_mat_core.set_shader_parameter("intensity", amount)
		_mat_core.set_shader_parameter("scroll_speed", lerpf(4.2, 7.5, clampf(amount * 0.4, 0.0, 1.0)))
	if _mat_halo != null:
		_mat_halo.set_shader_parameter("intensity", amount * 0.55)
		_mat_halo.set_shader_parameter("scroll_speed", lerpf(3.2, 5.8, clampf(amount * 0.4, 0.0, 1.0)))


func _ensure_mesh() -> void:
	if _core_mi != null:
		return
	_mat_core = _make_mat(Color(0.78, 0.32, 1.0, 0.9), 5.2, 5.5)
	_mat_halo = _make_mat(Color(0.45, 0.12, 0.85, 0.32), 2.2, 4.0)
	_core_mi = _make_cylinder("Core", CORE_RADIUS_M, _mat_core)
	_halo_mi = _make_cylinder("Halo", HALO_RADIUS_M, _mat_halo)
	_core_mi.position = Vector3(0.0, HEIGHT_M * 0.5, 0.0)
	_halo_mi.position = Vector3(0.0, HEIGHT_M * 0.5, 0.0)
	_apply_intensity(1.0)


func _make_cylinder(node_name: String, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.height = HEIGHT_M
	mesh.radial_segments = 10
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_mat(color: Color, emission: float, scroll: float) -> ShaderMaterial:
	var shader: Shader = load("res://assets/city/shaders/infection_sky_beam.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("beam_color", color)
	mat.set_shader_parameter("emission_mul", emission)
	mat.set_shader_parameter("scroll_speed", scroll)
	mat.set_shader_parameter("intensity", 1.0)
	mat.set_shader_parameter("fade_top", 0.78)
	mat.set_shader_parameter("streak_count", 7.0)
	return mat
