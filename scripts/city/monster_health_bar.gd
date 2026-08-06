## How much of a monster is left, drawn as a horizontal strip. Creatures wear it under the feet;
## siege towers wear a half-size strip at the base (`fit_over_structure`).
##
## Only monsters carry one. Pedestrians and vehicles have no health pool at all — one hit removes
## them — so a bar under a ped would be a bar that can only ever read full.
##
## These are real world `MeshInstance3D` quads (not a screen overlay). Forty bodies can be alive at
## once, so a bar wears the one QuadMesh and the one ShaderMaterial the entire army shares, and the
## numbers that differ per body ride on the instance. The vertex shader billboards toward the
## camera and pulls the quad forward so the body does not swallow it — no per-frame script aim.
##
## Size comes off the body rather than out of a table. `hit_radius` already carries the
## catalogue's measurement of whichever creature the unit is wearing and whatever it has grown to,
## so a two-metre skeleton and a twenty-metre giant both get a bar in proportion to themselves
## without either of them being named here.
class_name MonsterHealthBar
extends MeshInstance3D

const SHADER: Shader = preload("res://assets/city/shaders/monster_health_bar.gdshader")
const STRUCTURE_SHADER: Shader = preload(
	"res://assets/city/shaders/monster_health_bar_structure.gdshader"
)

## Bar length along its fill axis, as a multiple of the body's hit radius (creatures).
const WIDTH_PER_HIT_RADIUS := 2.0
## Short axis (thickness) as a fraction of the long axis.
const HEIGHT_FRACTION := 0.16
## Gap between the body and the near edge of the strip, as a fraction of the long axis.
const FOOT_CLEARANCE_FRACTION := 0.06
## How far past the body's own silhouette the quad is pulled, as a fraction of the long axis.
const CAMERA_PULL_MARGIN_FRACTION := 0.25
## Frame thickness, as a fraction of the bar's short axis.
const FRAME_FRACTION := 0.16
## Past this many of its own long-axis lengths the strip is a pixel nobody can read.
const SIGHT_RANGE_PER_WIDTH := 55.0
## Towers: half the creature strip's width and thickness for the same hit radius.
const STRUCTURE_SIZE_SCALE := 0.5

static var _shared_mesh: QuadMesh = null
static var _shared_material: ShaderMaterial = null
static var _shared_structure_material: ShaderMaterial = null

var _fraction: float = 1.0
## Length along the fill axis (metres).
var _long_m: float = 0.0
var _pull: float = 0.0
var _vertical: bool = false


func _init() -> void:
	name = "HealthBar"
	mesh = shared_mesh()
	material_override = shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	set_instance_shader_parameter("fill", _fraction)
	set_instance_shader_parameter("vertical", 0.0)


## Size and place the bar off the body wearing it. `body_reach_m` is how far that body is drawn
## from its own axis, which decides how far the quad has to be pulled toward the camera to be
## read at all; the hit radius, which is a capsule round the torso, decides how big it is.
##
## Run again whenever the body changes size, which is every frame a monster spends growing.
func fit_to_body(hit_radius_m: float, body_reach_m: float) -> void:
	if hit_radius_m <= 0.0:
		push_error("MonsterHealthBar: %f is not a hit radius to size a bar off" % hit_radius_m)
		return
	_vertical = false
	material_override = shared_material()
	set_instance_shader_parameter("vertical", 0.0)
	## The hit capsule is inside the drawn body by construction, so it is the floor on reach.
	_size_horizontal(hit_radius_m, maxf(body_reach_m, hit_radius_m), 1.0, true)
	## Quad is centred on the node, so the centre sits half a bar plus the sole gap below y=0.
	_place(-(_short_m() * 0.5 + _long_m * FOOT_CLEARANCE_FRACTION))


## Horizontal strip at the base of a siege tower: centred on the pad cell under the host
## (`voxel_size_m` down from the combat host), half as wide and thick as a creature bar.
## `top_m` is the muzzle height — kept so callers still pass the stamp they sized the host with.
##
## The foundation cell is inside the stamp, so the strip pulls forward by the hit radius the same
## way a creature bar clears its legs. Depth testing stays on: a wall between the camera and the
## tower hides the bar. Skipping the depth test used to plant the strip without a pull, and also
## drew every hostile spire through the keep — a free map of rooms the player had not opened.
func fit_over_structure(hit_radius_m: float, top_m: float, voxel_size_m: float = 0.5) -> void:
	if hit_radius_m <= 0.0:
		push_error("MonsterHealthBar: %f is not a hit radius to size a bar off" % hit_radius_m)
		return
	if top_m <= 0.0:
		push_error("MonsterHealthBar: %f is not a tower height" % top_m)
		return
	if voxel_size_m <= 0.0:
		push_error("MonsterHealthBar: %f is not a voxel size" % voxel_size_m)
		return
	_vertical = false
	material_override = shared_structure_material()
	set_instance_shader_parameter("vertical", 0.0)
	_size_horizontal(hit_radius_m, hit_radius_m, STRUCTURE_SIZE_SCALE, true)
	## One voxel straight down from the host — the foundation cell under the tower centre.
	_place(-voxel_size_m)


func _size_horizontal(
	hit_radius_m: float, reach_m: float, size_scale: float, use_camera_pull: bool
) -> void:
	_long_m = hit_radius_m * WIDTH_PER_HIT_RADIUS * size_scale
	_pull = (reach_m + _long_m * CAMERA_PULL_MARGIN_FRACTION) if use_camera_pull else 0.0
	scale = Vector3(_long_m, _short_m(), _long_m)
	visibility_range_end = _long_m * SIGHT_RANGE_PER_WIDTH
	set_instance_shader_parameter("camera_pull", _pull)


## Centre of the quad on the wearer's own axis. Runs after sizing: the cull box is built out of
## the long axis and the pull.
func _place(centre_y: float) -> void:
	position = Vector3(0.0, centre_y, 0.0)
	custom_aabb = _sweep_aabb()


func _short_m() -> float:
	return _long_m * HEIGHT_FRACTION


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


func is_vertical() -> bool:
	return _vertical


## Length along the fill axis in metres, 0 until fitted (the strip's width).
func width_m() -> float:
	return _long_m


## How far in front of its body the bar is drawn, in metres. 0 until fitted.
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


## Tower bars: same look as `shared_material`, pulled clear of the foundation rather than x-rayed.
static func shared_structure_material() -> ShaderMaterial:
	if _shared_structure_material == null:
		_shared_structure_material = ShaderMaterial.new()
		_shared_structure_material.shader = STRUCTURE_SHADER
		_shared_structure_material.resource_name = "MonsterHealthBarStructure"
		_shared_structure_material.set_shader_parameter("bar_aspect", 1.0 / HEIGHT_FRACTION)
		_shared_structure_material.set_shader_parameter("frame_fraction", FRAME_FRACTION)
	return _shared_structure_material


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
	if _long_m <= 0.0:
		return AABB()
	var short_m := _short_m()
	var reach := 0.5 * sqrt(_long_m * _long_m + short_m * short_m) + _pull
	if _vertical:
		var half := Vector3(reach / short_m, reach / _long_m, reach / short_m)
		return AABB(-half, half * 2.0)
	var half_h := Vector3(reach / _long_m, reach / short_m, reach / _long_m)
	return AABB(-half_h, half_h * 2.0)
