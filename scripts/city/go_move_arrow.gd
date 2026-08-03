## Dart of light thrown from a player's hand onto the crossing a stone is about to take.
##
## Announces *who* is moving before the stone shows up: the colours match the giant-board
## beam, violet for Black and yellow for White. The path is a plain ballistic arc, so the
## dart tips over and comes down onto the board instead of sliding in flat.
class_name GoMoveArrow
extends Node3D

signal landed()

const GoGiantBeamScript := preload("res://scripts/city/go_giant_beam.gd")

## Sizes are absolute metres, not board cells: this is a projectile crossing the room, and
## it has to read the same whether the table is playing 9×9 or 19×19.
const LENGTH_M := 0.34
const HEAD_LENGTH_M := 0.12
const HEAD_RADIUS_M := 0.05
const SHAFT_RADIUS_M := 0.016
## Kept under the head cone's width: a glow big enough to swallow the point turns the
## dart into a blob and the direction of flight stops reading.
const GLOW_SIZE_M := 0.15
const TRAIL_COUNT := 16
## Spacing between trail sprites, in fractions of the flight — the tail covers the last
## TRAIL_COUNT × this much of the arc. Close enough that the sprites overlap into a
## streak instead of a dotted line.
const TRAIL_SPACING := 0.018
const TRAIL_SIZE_M := 0.2
const IMPACT_SIZE_M := 0.6
const IMPACT_SEC := 0.3

const SPEED_MPS := 7.0
const MIN_FLIGHT_SEC := 0.32
const MAX_FLIGHT_SEC := 0.9
## Apex above the straight line from hand to crossing.
const ARC_FRAC := 0.3
const ARC_MIN_M := 0.22
const ARC_MAX_M := 2.4

const TEX_PX := 96

static var _glow_tex: ImageTexture = null

var _dart: Node3D = null
var _body_mat: StandardMaterial3D = null
var _glow_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _trail: Array[MeshInstance3D] = []
var _trail_mats: Array[StandardMaterial3D] = []
var _impact: MeshInstance3D = null
var _impact_mat: StandardMaterial3D = null

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _arc: float = 0.0
var _tint: Color = GoGiantBeamScript.WHITE_LIGHT
## Bumped by every launch and by cancel, so a stale tween cannot drive a newer flight.
var _epoch: int = 0
var _tween: Tween = null


func _ready() -> void:
	_build()
	visible = false


## Throws a dart from `from` to `to` and returns its flight time in seconds, so the caller
## can drop the stone at the moment it arrives. The impact flash plays on afterwards.
func fly(from: Vector3, to: Vector3, is_black: bool) -> float:
	if _dart == null:
		push_error("GoMoveArrow.fly: called before the node entered the tree")
		return 0.0
	_epoch += 1
	var epoch := _epoch
	_kill_tween()
	_aim(from, to, is_black)
	_impact.visible = false
	_dart.visible = true
	visible = true
	_apply_progress(0.0)
	var seconds := clampf(_from.distance_to(_to) / SPEED_MPS, MIN_FLIGHT_SEC, MAX_FLIGHT_SEC)
	_tween = create_tween()
	## Linear: a thrown object covers ground evenly, the arc supplies the drama.
	_tween.tween_method(_apply_progress, 0.0, 1.0, seconds)
	_tween.tween_callback(_arrive.bind(epoch))
	return seconds


func cancel() -> void:
	_epoch += 1
	_kill_tween()
	visible = false


## Freezes the dart at `t` along its arc without running a tween. Screenshot tests cannot
## reliably catch a third of a second of flight on a chosen frame.
func preview_at(from: Vector3, to: Vector3, is_black: bool, t: float) -> void:
	if _dart == null:
		push_error("GoMoveArrow.preview_at: called before the node entered the tree")
		return
	_epoch += 1
	_kill_tween()
	_aim(from, to, is_black)
	_impact.visible = false
	_dart.visible = true
	visible = true
	_apply_progress(t)


func _aim(from: Vector3, to: Vector3, is_black: bool) -> void:
	_from = from
	_to = to
	_arc = clampf(from.distance_to(to) * ARC_FRAC, ARC_MIN_M, ARC_MAX_M)
	_tint = GoGiantBeamScript.BLACK_LIGHT if is_black else GoGiantBeamScript.WHITE_LIGHT
	_body_mat.albedo_color = _tint
	_glow_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.8)
	_light.light_color = _tint


## Position on the parabola: the straight line lifted by an apex at half flight.
func _point_at(t: float) -> Vector3:
	var c := clampf(t, 0.0, 1.0)
	return _from.lerp(_to, c) + Vector3.UP * (_arc * 4.0 * c * (1.0 - c))


func _tangent_at(t: float) -> Vector3:
	var c := clampf(t, 0.0, 1.0)
	return (_to - _from) + Vector3.UP * (_arc * 4.0 * (1.0 - 2.0 * c))


func _apply_progress(t: float) -> void:
	var head := _point_at(t)
	_dart.global_transform = Transform3D(_aim_basis(_tangent_at(t)), head)
	_light.global_position = head
	_light.light_energy = 1.6
	for i in range(_trail.size()):
		var quad := _trail[i]
		## Starts a gap behind the dart, so the streak does not swallow the arrowhead.
		var tt := t - float(i + 3) * TRAIL_SPACING
		if tt <= 0.0:
			quad.visible = false
			continue
		quad.visible = true
		quad.global_position = _point_at(tt)
		var fade := 1.0 - float(i) / float(TRAIL_COUNT)
		## Taper mostly by opacity: shrinking the sprites too far breaks the streak apart.
		quad.scale = Vector3.ONE * lerpf(0.4, 1.0, fade)
		_trail_mats[i].albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.42 * fade * fade)


func _arrive(epoch: int) -> void:
	if epoch != _epoch:
		return
	_dart.visible = false
	for quad in _trail:
		quad.visible = false
	landed.emit()
	_flash(epoch)


func _flash(epoch: int) -> void:
	_impact.global_position = _to
	_impact.scale = Vector3.ONE * 0.4
	_impact.visible = true
	_light.global_position = _to
	var burst := create_tween()
	burst.set_parallel(true)
	(
		burst
		. tween_property(_impact, "scale", Vector3.ONE, IMPACT_SEC)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	burst.tween_method(_apply_impact_alpha, 0.95, 0.0, IMPACT_SEC)
	burst.tween_property(_light, "light_energy", 0.0, IMPACT_SEC).from(3.4)
	await burst.finished
	if epoch != _epoch:
		return
	visible = false


func _apply_impact_alpha(alpha: float) -> void:
	_impact_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, alpha)


## Basis whose −Z (the Godot forward axis) runs along `dir`.
static func _aim_basis(dir: Vector3) -> Basis:
	if dir.length_squared() < 0.000001:
		return Basis.IDENTITY
	var back := -dir.normalized()
	## Near-vertical flight has no meaningful yaw; any reference that is not parallel does.
	var up_ref := Vector3.UP if absf(back.y) < 0.98 else Vector3.FORWARD
	var x_axis := up_ref.cross(back).normalized()
	return Basis(x_axis, back.cross(x_axis), back)


func _build() -> void:
	_dart = Node3D.new()
	_dart.name = "Dart"
	add_child(_dart)

	## Origin sits on the point of the arrow, so the node's position is where it strikes;
	## the body trails behind along +Z (the dart flies toward its own −Z).
	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.albedo_color = _tint
	var shaft_len := LENGTH_M - HEAD_LENGTH_M
	_add_cone(SHAFT_RADIUS_M, SHAFT_RADIUS_M, shaft_len, HEAD_LENGTH_M + shaft_len * 0.5)
	_add_cone(0.0, HEAD_RADIUS_M, HEAD_LENGTH_M, HEAD_LENGTH_M * 0.5)

	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(GLOW_SIZE_M, GLOW_SIZE_M)
	glow.mesh = glow_quad
	_glow_mat = _sprite_material()
	glow.material_override = _glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(0.0, 0.0, LENGTH_M * 0.5)
	_dart.add_child(glow)

	for i in range(TRAIL_COUNT):
		var quad := MeshInstance3D.new()
		quad.name = "Trail%d" % i
		var mesh := QuadMesh.new()
		mesh.size = Vector2(TRAIL_SIZE_M, TRAIL_SIZE_M)
		quad.mesh = mesh
		var mat := _sprite_material()
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		_trail.append(quad)
		_trail_mats.append(mat)

	_impact = MeshInstance3D.new()
	_impact.name = "Impact"
	var impact_quad := QuadMesh.new()
	impact_quad.size = Vector2(IMPACT_SIZE_M, IMPACT_SIZE_M)
	_impact.mesh = impact_quad
	_impact_mat = _sprite_material()
	## The flash straddles the crossing the stone takes; depth-tested it would be swallowed
	## by that stone and only the outer halo would show.
	_impact_mat.no_depth_test = true
	_impact.material_override = _impact_mat
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact.visible = false
	add_child(_impact)

	_light = OmniLight3D.new()
	_light.name = "Spark"
	_light.omni_range = 1.8
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _add_cone(top_radius: float, bottom_radius: float, height: float, at_z: float) -> void:
	var inst := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = top_radius
	cone.bottom_radius = bottom_radius
	cone.height = height
	cone.radial_segments = 12
	cone.rings = 1
	inst.mesh = cone
	inst.material_override = _body_mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## CylinderMesh grows along +Y with its tip on top; −90° about X turns that tip forward.
	inst.rotation.x = deg_to_rad(-90.0)
	inst.position = Vector3(0.0, 0.0, at_z)
	_dart.add_child(inst)


## Camera-facing additive puff — used for the head glow, the tail and the impact.
static func _sprite_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	## Billboarding rebuilds the quad's basis in the shader and drops the node scale with
	## it — the trail shrinks its sprites that way, so the scale has to be kept.
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.albedo_texture = _shared_glow_tex()
	return mat


static func _shared_glow_tex() -> ImageTexture:
	if _glow_tex == null:
		var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 1.0, 1.0, 0.0))
		var half := float(TEX_PX) * 0.5
		for py in range(TEX_PX):
			for px in range(TEX_PX):
				var dx := (float(px) + 0.5 - half) / half
				var dy := (float(py) + 0.5 - half) / half
				var r := sqrt(dx * dx + dy * dy)
				if r >= 1.0:
					continue
				## Bright core with a long tail, so no edge shows as a ring.
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, pow(1.0 - r, 2.2)))
		_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
