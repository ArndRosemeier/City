## Brief red flash at a charged-blast impact (visual only; debris handles tumble).
extends Node3D

@export var duration_sec: float = 0.38
@export var base_emission: float = 18.0

var _core_mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _core_mesh: SphereMesh
var _glow_mesh: SphereMesh
var _mat_core: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _light: OmniLight3D
var _radius_m: float = 1.0
var _elapsed: float = 0.0
var _active: bool = false


static func spawn(host: Node, world_pos: Vector3, radius_m: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var script: Script = load("res://scripts/city/blast_flash_vfx.gd") as Script
	var flash: Node = script.new() as Node
	flash.name = "BlastFlash"
	host.add_child(flash)
	flash.call("play", world_pos, radius_m)


func play(world_pos: Vector3, radius_m: float) -> void:
	_ensure_mesh()
	_radius_m = maxf(radius_m, 0.4)
	_elapsed = 0.0
	_active = true
	global_position = world_pos
	visible = true
	if _light != null:
		_light.visible = true
	_apply(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	_elapsed += delta
	var t := clampf(_elapsed / maxf(duration_sec, 0.05), 0.0, 1.0)
	_apply(t)
	if t >= 1.0:
		_active = false
		queue_free()


func _apply(t: float) -> void:
	## Quick expand then fade — peak size near t=0.35.
	var grow := sin(clampf(t / 0.35, 0.0, 1.0) * PI * 0.5)
	var fade := 1.0 - smoothstep(0.25, 1.0, t)
	var core_r := _radius_m * (0.35 + 0.85 * grow)
	var glow_r := core_r * (1.6 + 0.5 * grow)
	if _core_mesh != null:
		_core_mesh.radius = core_r
		_core_mesh.height = core_r * 2.0
	if _glow_mesh != null:
		_glow_mesh.radius = glow_r
		_glow_mesh.height = glow_r * 2.0
	if _mat_core != null:
		_mat_core.albedo_color = Color(1.0, 0.45 + 0.35 * fade, 0.12, fade)
		_mat_core.emission = Color(1.0, 0.35, 0.05)
		_mat_core.emission_energy_multiplier = base_emission * (1.2 + 2.0 * fade * (1.0 - t))
	if _mat_glow != null:
		_mat_glow.albedo_color = Color(1.0, 0.2, 0.04, 0.35 * fade)
		_mat_glow.emission_energy_multiplier = base_emission * 0.7 * fade
	if _light != null:
		_light.light_energy = (14.0 + 22.0 * fade) * (1.0 - t * 0.5)
		_light.omni_range = glow_r * 2.8
		_light.light_color = Color(1.0, 0.35 + 0.25 * fade, 0.08)


func _ensure_mesh() -> void:
	if _core_mi != null:
		return
	_mat_core = _make_mat(Color(1.0, 0.5, 0.1), Color(1.0, 0.35, 0.05), true)
	_mat_glow = _make_mat(Color(1.0, 0.2, 0.04, 0.35), Color(1.0, 0.2, 0.05), true)
	_core_mesh = SphereMesh.new()
	_core_mesh.radial_segments = 18
	_core_mesh.rings = 10
	_glow_mesh = SphereMesh.new()
	_glow_mesh.radial_segments = 14
	_glow_mesh.rings = 8
	_glow_mi = MeshInstance3D.new()
	_glow_mi.name = "Glow"
	_glow_mi.mesh = _glow_mesh
	_glow_mi.material_override = _mat_glow
	_glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow_mi)
	_core_mi = MeshInstance3D.new()
	_core_mi.name = "Core"
	_core_mi.mesh = _core_mesh
	_core_mi.material_override = _mat_core
	_core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core_mi)
	_light = OmniLight3D.new()
	_light.name = "FlashLight"
	_light.shadow_enabled = false
	_light.light_color = Color(1.0, 0.4, 0.1)
	add_child(_light)


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
	return mat
