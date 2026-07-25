## Semi-transparent glowing sphere on a tendril tip. Color slowly cycles green ↔ violet.
extends Node3D

const RADIUS_M := 1.5
## Full green → violet → green period.
const COLOR_CYCLE_SEC := 9.0
## Soft brightness throb (slightly offset from color).
const BRIGHT_CYCLE_SEC := 6.5

const GREEN := Color(0.22, 0.95, 0.32)
const VIOLET := Color(0.72, 0.16, 0.95)

var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _age: float = 0.0
var _phase: float = 0.0


func setup(world_pos: Vector3, phase_offset: float = 0.0) -> void:
	_phase = phase_offset
	_age = 0.0
	_build()
	global_position = world_pos
	_apply_look(0.0)
	set_process(true)


func move_to(world_pos: Vector3) -> void:
	global_position = world_pos


func _process(delta: float) -> void:
	_age += delta
	_apply_look(_age)


func _build() -> void:
	if _mi != null:
		return
	_mi = MeshInstance3D.new()
	_mi.name = "AuraSphere"
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS_M
	mesh.height = RADIUS_M * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	_mi.mesh = mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.28)
	_mat.emission_enabled = true
	_mat.emission = GREEN
	_mat.emission_energy_multiplier = 2.2
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_mi.material_override = _mat
	add_child(_mi)

	_light = OmniLight3D.new()
	_light.name = "AuraLight"
	_light.light_color = GREEN
	_light.light_energy = 2.0
	_light.omni_range = RADIUS_M * 3.2
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	add_child(_light)


func _apply_look(age: float) -> void:
	if _mat == null or _light == null:
		return
	var color_t := 0.5 + 0.5 * sin((age + _phase) * TAU / COLOR_CYCLE_SEC)
	var col := GREEN.lerp(VIOLET, color_t)
	var bright_t := 0.5 + 0.5 * sin((age + _phase * 1.37) * TAU / BRIGHT_CYCLE_SEC)
	var bright := lerpf(0.45, 1.0, bright_t)
	_mat.albedo_color = Color(col.r, col.g, col.b, lerpf(0.14, 0.34, bright))
	_mat.emission = col
	_mat.emission_energy_multiplier = lerpf(1.1, 3.6, bright)
	_light.light_color = col
	_light.light_energy = lerpf(0.9, 3.0, bright)
