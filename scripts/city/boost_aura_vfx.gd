## Soft glowing shells around the player while a speed tonic, regen tonic, or shield is up.
##
## Three independent layers (orange speed / green regen / cyan shield) so they can stack and
## still read as distinct. Parent is the walker; Y sits at mid-capsule and scales with body size.
extends Node3D

const InventoryItemVisualScript := preload("res://scripts/city/inventory_item_visual.gd")

const SPEED_COLOR := InventoryItemVisualScript.TONIC_SPEED_COLOR
const REGEN_COLOR := InventoryItemVisualScript.TONIC_REGEN_COLOR
const SHIELD_COLOR := InventoryItemVisualScript.SHIELD_AURA_COLOR

## Body-local mid-height at scale 1 (capsule center ~0.9 m).
const MID_HEIGHT_M := 0.9
## Soft shell radius at scale 1 — slightly outside the capsule.
const SHELL_RADIUS_M := 1.05
## Torus major radius / tube thickness at scale 1 (same convention as the charge orb).
const RING_MAJOR_M := 0.88
const RING_TUBE_M := 0.08
const PULSE_SEC := 1.35
const RING_SPIN_DEG_PER_SEC := 110.0


var _body_scale: float = 1.0
var _speed_on: bool = false
var _regen_on: bool = false
var _shield_on: bool = false
var _age: float = 0.0
## Shield layer colour. Defaults to the player ward cyan; the zoo recolors it per faction.
var _shield_color: Color = SHIELD_COLOR

var _speed_root: Node3D
var _regen_root: Node3D
var _shield_root: Node3D
var _speed_shell: MeshInstance3D
var _regen_shell: MeshInstance3D
var _shield_shell: MeshInstance3D
var _speed_ring: MeshInstance3D
var _regen_ring: MeshInstance3D
var _shield_ring: MeshInstance3D
var _speed_mat: StandardMaterial3D
var _regen_mat: StandardMaterial3D
var _shield_mat: StandardMaterial3D
var _speed_ring_mat: StandardMaterial3D
var _regen_ring_mat: StandardMaterial3D
var _shield_ring_mat: StandardMaterial3D
var _speed_light: OmniLight3D
var _regen_light: OmniLight3D
var _shield_light: OmniLight3D
var _speed_mesh: SphereMesh
var _regen_mesh: SphereMesh
var _shield_mesh: SphereMesh
var _speed_torus: TorusMesh
var _regen_torus: TorusMesh
var _shield_torus: TorusMesh


func setup() -> void:
	name = "BoostAura"
	_build_layers()
	_apply_scale()
	_sync_visibility()
	set_process(true)


func set_body_scale(scale: float) -> void:
	_body_scale = maxf(scale, 0.05)
	_apply_scale()


func set_speed_active(on: bool) -> void:
	if _speed_on == on:
		return
	_speed_on = on
	_sync_visibility()


func set_regen_active(on: bool) -> void:
	if _regen_on == on:
		return
	_regen_on = on
	_sync_visibility()


func set_shield_active(on: bool) -> void:
	if _shield_on == on:
		return
	_shield_on = on
	_sync_visibility()


## Recolor the shield ward. Call before or after `set_shield_active` — mats update live.
func set_shield_color(color: Color) -> void:
	_shield_color = color
	if _shield_mat != null:
		_shield_mat.albedo_color = Color(color.r, color.g, color.b, _shield_mat.albedo_color.a)
		_shield_mat.emission = color
	if _shield_ring_mat != null:
		_shield_ring_mat.albedo_color = Color(
			color.r, color.g, color.b, _shield_ring_mat.albedo_color.a
		)
		_shield_ring_mat.emission = color
	if _shield_light != null:
		_shield_light.light_color = color


func is_speed_active() -> bool:
	return _speed_on


func is_regen_active() -> bool:
	return _regen_on


func is_shield_active() -> bool:
	return _shield_on


func _process(delta: float) -> void:
	if not _speed_on and not _regen_on and not _shield_on:
		return
	_age += delta
	_apply_pulse(_age)
	if _speed_on and _speed_ring != null:
		_speed_ring.rotate_y(deg_to_rad(RING_SPIN_DEG_PER_SEC) * delta)
	if _regen_on and _regen_ring != null:
		## Opposite, slower spin so stacked tonics do not look like one mesh.
		_regen_ring.rotate_y(-deg_to_rad(RING_SPIN_DEG_PER_SEC * 0.55) * delta)
	if _shield_on and _shield_ring != null:
		_shield_ring.rotate_y(deg_to_rad(RING_SPIN_DEG_PER_SEC * 0.8) * delta)


func _build_layers() -> void:
	if _speed_root != null:
		return

	_speed_root = Node3D.new()
	_speed_root.name = "SpeedAura"
	add_child(_speed_root)
	_speed_mat = _make_shell_mat(SPEED_COLOR, 0.16)
	_speed_ring_mat = _make_shell_mat(SPEED_COLOR, 0.42)
	_speed_mesh = SphereMesh.new()
	_speed_mesh.radial_segments = 20
	_speed_mesh.rings = 12
	_speed_shell = _make_mesh_instance("Shell", _speed_mesh, _speed_mat)
	_speed_root.add_child(_speed_shell)
	_speed_torus = TorusMesh.new()
	_speed_torus.rings = 28
	_speed_torus.ring_segments = 10
	_speed_ring = _make_mesh_instance("Ring", _speed_torus, _speed_ring_mat)
	_speed_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_speed_root.add_child(_speed_ring)
	_speed_light = _make_light("Light", SPEED_COLOR)
	_speed_root.add_child(_speed_light)

	_regen_root = Node3D.new()
	_regen_root.name = "RegenAura"
	add_child(_regen_root)
	_regen_mat = _make_shell_mat(REGEN_COLOR, 0.14)
	_regen_ring_mat = _make_shell_mat(REGEN_COLOR, 0.38)
	_regen_mesh = SphereMesh.new()
	_regen_mesh.radial_segments = 20
	_regen_mesh.rings = 12
	_regen_shell = _make_mesh_instance("Shell", _regen_mesh, _regen_mat)
	_regen_root.add_child(_regen_shell)
	_regen_torus = TorusMesh.new()
	_regen_torus.rings = 26
	_regen_torus.ring_segments = 10
	_regen_ring = _make_mesh_instance("Ring", _regen_torus, _regen_ring_mat)
	## Tilted so it does not sit in the same plane as the speed ring.
	_regen_ring.rotation_degrees = Vector3(72.0, 18.0, 0.0)
	_regen_root.add_child(_regen_ring)
	_regen_light = _make_light("Light", REGEN_COLOR)
	_regen_root.add_child(_regen_light)

	_shield_root = Node3D.new()
	_shield_root.name = "ShieldAura"
	add_child(_shield_root)
	_shield_mat = _make_shell_mat(_shield_color, 0.18)
	_shield_ring_mat = _make_shell_mat(_shield_color, 0.46)
	_shield_mesh = SphereMesh.new()
	_shield_mesh.radial_segments = 20
	_shield_mesh.rings = 12
	_shield_shell = _make_mesh_instance("Shell", _shield_mesh, _shield_mat)
	_shield_root.add_child(_shield_shell)
	_shield_torus = TorusMesh.new()
	_shield_torus.rings = 30
	_shield_torus.ring_segments = 10
	_shield_ring = _make_mesh_instance("Ring", _shield_torus, _shield_ring_mat)
	## Upright hoop — a ward, not a tonic belt.
	_shield_ring.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	_shield_root.add_child(_shield_ring)
	_shield_light = _make_light("Light", _shield_color)
	_shield_root.add_child(_shield_light)


func _make_mesh_instance(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_light(node_name: String, color: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = SHELL_RADIUS_M * 2.8
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	return light


func _make_shell_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


func _apply_scale() -> void:
	var s := _body_scale
	position = Vector3(0.0, MID_HEIGHT_M * s, 0.0)

	if _speed_mesh != null:
		## Slightly taller ellipsoid so the shell hugs a standing body.
		_speed_mesh.radius = SHELL_RADIUS_M * s
		_speed_mesh.height = SHELL_RADIUS_M * 2.35 * s
	if _regen_mesh != null:
		## Inner shell so both tonics stay readable when stacked.
		_regen_mesh.radius = SHELL_RADIUS_M * 0.82 * s
		_regen_mesh.height = SHELL_RADIUS_M * 2.05 * s
	if _shield_mesh != null:
		## Outermost ward — a touch larger than the speed shell so shield reads as armour.
		_shield_mesh.radius = SHELL_RADIUS_M * 1.12 * s
		_shield_mesh.height = SHELL_RADIUS_M * 2.5 * s
	if _speed_torus != null:
		var major := RING_MAJOR_M * s
		var tube := RING_TUBE_M * s
		_speed_torus.outer_radius = major
		_speed_torus.inner_radius = maxf(major - tube, 0.01)
	if _regen_torus != null:
		var major_r := RING_MAJOR_M * 0.78 * s
		var tube_r := RING_TUBE_M * 0.9 * s
		_regen_torus.outer_radius = major_r
		_regen_torus.inner_radius = maxf(major_r - tube_r, 0.01)
	if _shield_torus != null:
		var major_s := RING_MAJOR_M * 1.05 * s
		var tube_s := RING_TUBE_M * 1.05 * s
		_shield_torus.outer_radius = major_s
		_shield_torus.inner_radius = maxf(major_s - tube_s, 0.01)
	if _speed_light != null:
		_speed_light.omni_range = SHELL_RADIUS_M * 2.8 * s
	if _regen_light != null:
		_regen_light.omni_range = SHELL_RADIUS_M * 2.4 * s
	if _shield_light != null:
		_shield_light.omni_range = SHELL_RADIUS_M * 3.0 * s


func _sync_visibility() -> void:
	if _speed_root != null:
		_speed_root.visible = _speed_on
	if _regen_root != null:
		_regen_root.visible = _regen_on
	if _shield_root != null:
		_shield_root.visible = _shield_on
	visible = _speed_on or _regen_on or _shield_on
	if not visible:
		_age = 0.0


func _apply_pulse(age: float) -> void:
	var pulse := 0.5 + 0.5 * sin(age * TAU / PULSE_SEC)
	if _speed_on:
		_tint_layer(
			_speed_mat, _speed_ring_mat, _speed_light, SPEED_COLOR, pulse, 0.12, 0.28, 0.7, 1.9
		)
	if _regen_on:
		## Phase-shifted so green does not throb in lockstep with orange.
		var regen_pulse := 0.5 + 0.5 * sin((age + PULSE_SEC * 0.35) * TAU / (PULSE_SEC * 1.25))
		_tint_layer(
			_regen_mat,
			_regen_ring_mat,
			_regen_light,
			REGEN_COLOR,
			regen_pulse,
			0.10,
			0.24,
			0.55,
			1.6
		)
	if _shield_on:
		var shield_pulse := 0.5 + 0.5 * sin((age + PULSE_SEC * 0.6) * TAU / (PULSE_SEC * 0.9))
		_tint_layer(
			_shield_mat,
			_shield_ring_mat,
			_shield_light,
			_shield_color,
			shield_pulse,
			0.14,
			0.32,
			0.85,
			2.2
		)


func _tint_layer(
	shell_mat: StandardMaterial3D,
	ring_mat: StandardMaterial3D,
	light: OmniLight3D,
	color: Color,
	pulse: float,
	alpha_lo: float,
	alpha_hi: float,
	energy_lo: float,
	energy_hi: float
) -> void:
	if shell_mat != null:
		shell_mat.albedo_color = Color(color.r, color.g, color.b, lerpf(alpha_lo, alpha_hi, pulse))
		shell_mat.emission = color
		shell_mat.emission_energy_multiplier = lerpf(energy_lo, energy_hi, pulse)
	if ring_mat != null:
		ring_mat.albedo_color = Color(
			color.r, color.g, color.b, lerpf(alpha_lo + 0.18, alpha_hi + 0.28, pulse)
		)
		ring_mat.emission = color
		ring_mat.emission_energy_multiplier = lerpf(energy_lo + 0.4, energy_hi + 0.8, pulse)
	if light != null:
		light.light_color = color
		light.light_energy = lerpf(0.35, 1.35, pulse)
