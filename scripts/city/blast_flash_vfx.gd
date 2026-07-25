## Impact crack: white-hot flash + thin expanding shock ring (not a carve-sized soap bubble).
extends Node3D

@export var duration_sec: float = 0.42
@export var base_emission: float = 22.0

var _core_mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _ring_mi: MeshInstance3D
var _core_mesh: SphereMesh
var _glow_mesh: SphereMesh
var _ring_mesh: TorusMesh
var _mat_core: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _light: OmniLight3D
var _carve_radius_m: float = 1.0
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
	_carve_radius_m = maxf(radius_m, 0.4)
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
	## t=0: tiny white crack. Soft glow peaks early and dies; ring expands with carve hint.
	var crack := 1.0 - smoothstep(0.0, 0.12, t)
	var glow_fade := 1.0 - smoothstep(0.05, 0.35, t)
	var ring_u := clampf(t / 0.22, 0.0, 1.0)
	var ring_fade := 1.0 - smoothstep(0.08, 0.45, t)

	var core_peak := lerpf(0.35, 0.55, clampf((_carve_radius_m - 1.0) / 3.5, 0.0, 1.0))
	var core_r := lerpf(0.06, core_peak, 1.0 - crack * 0.85) * (0.55 + 0.45 * crack)
	## Shrink core after the crack so it doesn't become a balloon.
	core_r *= lerpf(1.0, 0.35, smoothstep(0.1, 0.4, t))
	var glow_r := core_r * (1.8 + 0.6 * glow_fade)

	if _core_mesh != null:
		_core_mesh.radius = maxf(core_r, 0.02)
		_core_mesh.height = _core_mesh.radius * 2.0
	if _glow_mesh != null:
		_glow_mesh.radius = maxf(glow_r, 0.04)
		_glow_mesh.height = _glow_mesh.radius * 2.0

	## Thin shock ring → ~0.55 × carve radius.
	var ring_outer := _carve_radius_m * 0.55 * (1.0 - (1.0 - ring_u) * (1.0 - ring_u))
	var ring_tube := lerpf(0.04, 0.018, ring_u)
	if _ring_mesh != null:
		_ring_mesh.outer_radius = maxf(ring_outer, 0.08)
		_ring_mesh.inner_radius = maxf(ring_outer - ring_tube, 0.02)
	if _ring_mi != null:
		_ring_mi.visible = ring_fade > 0.02
		_ring_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	var white_hot := Color(
		1.0,
		lerpf(0.95, 0.55, 1.0 - crack),
		lerpf(0.85, 0.15, 1.0 - crack)
	)
	if _mat_core != null:
		_mat_core.albedo_color = Color(white_hot.r, white_hot.g, white_hot.b, crack * 0.95 + glow_fade * 0.25)
		_mat_core.emission = white_hot
		_mat_core.emission_energy_multiplier = base_emission * (2.5 * crack + 0.8 * glow_fade)
	if _mat_glow != null:
		_mat_glow.albedo_color = Color(1.0, 0.55, 0.2, 0.28 * glow_fade)
		_mat_glow.emission = Color(1.0, 0.45, 0.12)
		_mat_glow.emission_energy_multiplier = base_emission * 0.55 * glow_fade
	if _mat_ring != null:
		_mat_ring.albedo_color = Color(1.0, 0.75, 0.35, 0.55 * ring_fade)
		_mat_ring.emission = Color(1.0, 0.7, 0.3)
		_mat_ring.emission_energy_multiplier = base_emission * 0.9 * ring_fade

	## Light punch dies in ~0.2 s; range scales gently with carve power.
	if _light != null:
		var light_life := 1.0 - smoothstep(0.0, 0.22, t)
		_light.light_energy = (18.0 + 28.0 * crack) * light_life
		_light.omni_range = 2.2 + _carve_radius_m * 0.55
		_light.light_color = white_hot
		_light.visible = light_life > 0.02


func _ensure_mesh() -> void:
	if _core_mi != null:
		return
	_mat_core = _make_mat(Color(1.0, 0.95, 0.85), Color(1.0, 0.9, 0.7), true)
	_mat_glow = _make_mat(Color(1.0, 0.45, 0.12, 0.3), Color(1.0, 0.4, 0.1), true)
	_mat_ring = _make_mat(Color(1.0, 0.7, 0.3, 0.5), Color(1.0, 0.65, 0.25), true)

	_core_mesh = SphereMesh.new()
	_core_mesh.radial_segments = 16
	_core_mesh.rings = 8
	_glow_mesh = SphereMesh.new()
	_glow_mesh.radial_segments = 12
	_glow_mesh.rings = 6
	_ring_mesh = TorusMesh.new()
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 10
	_ring_mesh.outer_radius = 0.2
	_ring_mesh.inner_radius = 0.16

	_glow_mi = _make_mi("Glow", _glow_mesh, _mat_glow)
	_core_mi = _make_mi("Core", _core_mesh, _mat_core)
	_ring_mi = _make_mi("ShockRing", _ring_mesh, _mat_ring)
	_ring_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_glow_mi)
	add_child(_core_mi)
	add_child(_ring_mi)

	_light = OmniLight3D.new()
	_light.name = "FlashLight"
	_light.shadow_enabled = false
	_light.light_color = Color(1.0, 0.85, 0.55)
	add_child(_light)


func _make_mi(mi_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mi_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


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
