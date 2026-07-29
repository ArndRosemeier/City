## How much of a monster is left, drawn as a strip at its feet.
##
## Only monsters carry one. Pedestrians and vehicles have no health pool at all — one hit removes
## them — so a bar under a ped would be a bar that can only ever read full.
##
## Cost is the whole shape of this. Forty bodies can be alive at once, so a bar is a single
## MeshInstance3D wearing the one QuadMesh and the one ShaderMaterial the entire army shares, and
## the two numbers that differ per body ride on the instance instead of on a material of its own.
## Nothing here is polled: the strip is written when the pool moves and when the body changes size,
## and the engine draws it from there. Turning it to face the camera is the vertex shader's job, so
## a city full of bars costs no script time at all between hits.
##
## Size comes off the body rather than out of a table. `hit_radius` already carries the
## catalogue's measurement of whichever creature the unit is wearing and whatever it has grown to,
## so a two-metre skeleton and a twenty-metre giant both get a bar in proportion to themselves
## without either of them being named here.
class_name MonsterHealthBar
extends MeshInstance3D

const SHADER: Shader = preload("res://assets/city/shaders/monster_health_bar.gdshader")

## Bar width, as a multiple of the body's hit radius.
const WIDTH_PER_HIT_RADIUS := 2.0
## Height and the gap above the feet, both as fractions of the width, so the strip keeps its
## proportions and its stand-off from the pavement on every body.
const HEIGHT_FRACTION := 0.16
const FOOT_CLEARANCE_FRACTION := 0.28
## How far past the body's own silhouette the quad is pulled, as a fraction of the width, so a
## bar is never read flush against the thing it is drawn over.
const CAMERA_PULL_MARGIN_FRACTION := 0.25
## Frame thickness, as a fraction of the bar's height.
const FRAME_FRACTION := 0.16
## Past this many of its own widths the strip is a pixel nobody can read, so the engine stops
## drawing it. Counted in widths rather than metres: a giant's bar is legible from much further
## out than a skeleton's, and hiding both at the same distance would throw one of them away.
const SIGHT_RANGE_PER_WIDTH := 55.0

static var _shared_mesh: QuadMesh = null
static var _shared_material: ShaderMaterial = null

var _fraction: float = 1.0
var _width: float = 0.0
var _pull: float = 0.0


func _init() -> void:
	name = "HealthBar"
	mesh = shared_mesh()
	material_override = shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	set_instance_shader_parameter("fill", _fraction)


## Size and place the bar off the body wearing it. `body_reach_m` is how far that body is drawn
## from its own axis, which decides how far the quad has to be pulled toward the camera to be
## read at all; the hit radius, which is a capsule round the torso, decides how big it is.
##
## Run again whenever the body changes size, which is every frame a monster spends growing.
func fit_to_body(hit_radius_m: float, body_reach_m: float) -> void:
	if hit_radius_m <= 0.0:
		push_error("MonsterHealthBar: %f is not a hit radius to size a bar off" % hit_radius_m)
		return
	_width = hit_radius_m * WIDTH_PER_HIT_RADIUS
	## The hit capsule is inside the drawn body by construction, so it is the floor on reach.
	_pull = maxf(body_reach_m, hit_radius_m) + _width * CAMERA_PULL_MARGIN_FRACTION
	scale = Vector3(_width, _width * HEIGHT_FRACTION, _width)
	position = Vector3(0.0, _width * FOOT_CLEARANCE_FRACTION, 0.0)
	visibility_range_end = _width * SIGHT_RANGE_PER_WIDTH
	custom_aabb = _sweep_aabb()
	set_instance_shader_parameter("camera_pull", _pull)


## How much of the track is filled, 0..1. The instance is only written when the number moved, so
## a body standing untouched in a wave costs nothing.
func set_fraction(fraction: float) -> void:
	var next := clampf(fraction, 0.0, 1.0)
	if is_equal_approx(next, _fraction):
		return
	_fraction = next
	set_instance_shader_parameter("fill", _fraction)


func fraction() -> float:
	return _fraction


## Bar width in metres, 0 until `fit_to_body`.
func width_m() -> float:
	return _width


## How far in front of its body the bar is drawn, in metres. 0 until `fit_to_body`.
func camera_pull_m() -> float:
	return _pull


## How far `model` is drawn from its own axis, in the units it was authored in — the widest
## |x| or |z| any of its meshes reaches. Measured rather than assumed because the hit capsule is
## a torso: a blob is drawn two or three times wider than the radius its hits are counted on, and
## a bar pulled only clear of the capsule stays inside the blob.
static func body_reach(model: Node3D) -> float:
	if model == null:
		push_error("MonsterHealthBar: no model to measure a body reach off")
		return 0.0
	return _reach_of(model, Transform3D.IDENTITY)


## Unit-sized, both of them: the node's own scale is what makes a bar the size of its monster.
static func shared_mesh() -> QuadMesh:
	if _shared_mesh == null:
		_shared_mesh = QuadMesh.new()
		_shared_mesh.size = Vector2.ONE
		_shared_mesh.resource_name = "MonsterHealthBar"
	return _shared_mesh


static func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
		_shared_material.resource_name = "MonsterHealthBar"
		_shared_material.set_shader_parameter("bar_aspect", 1.0 / HEIGHT_FRACTION)
		_shared_material.set_shader_parameter("frame_fraction", FRAME_FRACTION)
	return _shared_material


## `to_root` maps `node`'s own space into the space of the model `body_reach` was handed, so the
## model's own transform is deliberately not part of it: the answer is in authored units and the
## caller multiplies by whatever build and growth the body is wearing.
static func _reach_of(node: Node, to_root: Transform3D) -> float:
	var reach := 0.0
	var visual := node as VisualInstance3D
	if visual != null:
		var box := to_root * visual.get_aabb()
		reach = maxf(
			maxf(absf(box.position.x), absf(box.end.x)),
			maxf(absf(box.position.z), absf(box.end.z))
		)
	for child in node.get_children():
		var spatial := child as Node3D
		var child_to_root := to_root if spatial == null else to_root * spatial.transform
		reach = maxf(reach, _reach_of(child, child_to_root))
	return reach


## The quad is turned to face the camera in the vertex shader and slid toward it, so the flat box
## the mesh reports is not where it ends up drawing. Culling reads that box, and a bar culled on
## its own stale outline pops out at the edge of the screen — so the box is the whole sphere the
## quad can turn and be pulled into, in the local units the node's scale is applied to.
func _sweep_aabb() -> AABB:
	var reach := 0.5 * _width * sqrt(1.0 + HEIGHT_FRACTION * HEIGHT_FRACTION) + _pull
	var half := Vector3(reach / _width, reach / (_width * HEIGHT_FRACTION), reach / _width)
	return AABB(-half, half * 2.0)
