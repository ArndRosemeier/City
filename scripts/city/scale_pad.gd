## Glowing floor pad that continuously grows or shrinks the player while they stand on it.
## Scale is clamped to the walker's scale_min / scale_max (0.2× … 5×).
class_name ScalePad
extends Area3D

enum Kind { GROW, SHRINK }

@export var kind: Kind = Kind.GROW
## Exponential scale rate (natural log per second). ~0.35 ≈ +42%/s grow.
@export var log_rate: float = 0.35
@export var pad_radius: float = 3.2

var _mat_disc: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_shaft: StandardMaterial3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _phase: float = 0.0
var _base_emission: float = 3.5


func configure(p_kind: Kind, radius: float = 3.2) -> void:
	kind = p_kind
	pad_radius = radius
	_build_visuals()
	_build_trigger()


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  ## CityWalker
	if _mat_disc == null:
		_build_visuals()
		_build_trigger()


func _physics_process(delta: float) -> void:
	_phase += delta
	_animate_glow()
	var dir := 1.0 if kind == Kind.GROW else -1.0
	for body in get_overlapping_bodies():
		if body.has_method("nudge_character_scale_exp"):
			body.call("nudge_character_scale_exp", dir * log_rate, delta)


func _build_trigger() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = pad_radius
	## Tall enough that giant (5×) players still register while standing on it.
	shape.height = 14.0
	cs.shape = shape
	cs.position.y = shape.height * 0.5
	add_child(cs)


func _build_visuals() -> void:
	for c in get_children():
		if c is MeshInstance3D or c is OmniLight3D:
			c.queue_free()

	var grow := kind == Kind.GROW
	## Teal grow / amber-coral shrink — high contrast, no purple default.
	var col := Color(0.15, 0.95, 0.72) if grow else Color(1.0, 0.38, 0.12)
	var col_soft := Color(col.r, col.g, col.b, 0.55)

	_mat_disc = StandardMaterial3D.new()
	_mat_disc.albedo_color = col_soft
	_mat_disc.emission_enabled = true
	_mat_disc.emission = col
	_mat_disc.emission_energy_multiplier = _base_emission
	_mat_disc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_disc.roughness = 0.35
	_mat_disc.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_ring = _mat_disc.duplicate() as StandardMaterial3D
	_mat_ring.albedo_color = Color(col.r, col.g, col.b, 0.85)
	_mat_ring.emission_energy_multiplier = _base_emission + 1.5

	_mat_shaft = StandardMaterial3D.new()
	_mat_shaft.albedo_color = Color(col.r, col.g, col.b, 0.18)
	_mat_shaft.emission_enabled = true
	_mat_shaft.emission = col
	_mat_shaft.emission_energy_multiplier = 1.8
	_mat_shaft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_shaft.roughness = 0.2
	_mat_shaft.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_shaft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = pad_radius
	disc_mesh.bottom_radius = pad_radius
	disc_mesh.height = 0.08
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.material_override = _mat_disc
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.05
	add_child(disc)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = pad_radius * 0.82
	torus.outer_radius = pad_radius * 1.02
	torus.rings = 24
	torus.ring_segments = 16
	_ring.mesh = torus
	_ring.material_override = _mat_ring
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.12
	add_child(_ring)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = pad_radius * 0.22
	shaft_mesh.bottom_radius = pad_radius * 0.55
	shaft_mesh.height = 5.5
	shaft_mesh.radial_segments = 16
	shaft.mesh = shaft_mesh
	shaft.material_override = _mat_shaft
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position.y = 2.8
	add_child(shaft)

	## Floating glyph: ↑ grow (cone) / ↓ shrink (inverted cone).
	var glyph := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.radial_segments = 12
	if grow:
		cone.top_radius = 0.02
		cone.bottom_radius = 0.55
		cone.height = 0.95
	else:
		cone.top_radius = 0.55
		cone.bottom_radius = 0.02
		cone.height = 0.95
	glyph.mesh = cone
	var glyph_mat := _mat_ring.duplicate() as StandardMaterial3D
	glyph_mat.albedo_color = Color(1, 1, 1, 0.95)
	glyph_mat.emission_energy_multiplier = _base_emission + 2.0
	glyph.material_override = glyph_mat
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.position.y = 1.35
	add_child(glyph)
	glyph.set_meta("scale_pad_glyph", true)

	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 4.5
	_light.omni_range = pad_radius * 3.5
	_light.shadow_enabled = false
	_light.position.y = 2.2
	add_child(_light)


func _animate_glow() -> void:
	var pulse := 0.55 + 0.45 * sin(_phase * 4.2)
	var breathe := 0.75 + 0.25 * sin(_phase * 1.7)
	if _mat_disc != null:
		_mat_disc.emission_energy_multiplier = _base_emission * pulse
	if _mat_ring != null:
		_mat_ring.emission_energy_multiplier = (_base_emission + 1.5) * breathe
	if _mat_shaft != null:
		_mat_shaft.emission_energy_multiplier = 1.4 + 1.2 * pulse
	if _ring != null:
		_ring.rotation.y = _phase * 1.25
		_ring.scale = Vector3(1.0 + 0.06 * sin(_phase * 3.0), 1.0, 1.0 + 0.06 * sin(_phase * 3.0))
	if _light != null:
		_light.light_energy = 3.2 + 2.8 * pulse
	for c in get_children():
		if c is MeshInstance3D and c.has_meta("scale_pad_glyph"):
			var g := c as MeshInstance3D
			g.position.y = 1.25 + 0.22 * sin(_phase * 2.8)
			g.rotation.y = _phase * 0.9
