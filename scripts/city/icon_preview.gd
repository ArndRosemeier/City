## One small 3-D icon in a world of its own: a SubViewport holding a camera framed on the origin
## and a single light, so anything inside `InventoryItemVisual.bounding_radius()` fits the square.
##
## Inventory slots and recipe rows both draw this way, and the setup lives here rather than in
## each of them because every way it goes wrong looks the same from outside — an aim that never
## happened, a preview outside the frame, or a preview leaking into the game's World3D all just
## render an empty box.
class_name IconPreview
extends SubViewportContainer

const CAM_FOV := 35.0
## Slack between the item's bounding sphere and the edge of the square render target.
const CAM_FIT_MARGIN := 1.12
## How far the camera stands above the item, as a fraction of its distance from it.
const CAM_RISE := 0.11

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _mesh: MeshInstance3D


## Eye point: a touch above the item at the origin, far enough back that its bounding sphere
## fits the square target at CAM_FOV.
static func camera_position() -> Vector3:
	var half_fov := deg_to_rad(CAM_FOV * 0.5)
	var back := InventoryItemVisual.bounding_radius() * CAM_FIT_MARGIN / sin(half_fov)
	return Vector3(0.0, back * CAM_RISE, back)


func build(render_px: Vector2i) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = render_px
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)

	_world = Node3D.new()
	_world.name = "IconWorld"
	_vp.add_child(_world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.1
	_world.add_child(light)

	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	## The widget is built detached and only enters the tree when the caller adds it, so the aim
	## has to come from the given eye point rather than a global one.
	_cam.look_at_from_position(camera_position(), Vector3.ZERO, Vector3.UP)
	_world.add_child(_cam)


func viewport() -> SubViewport:
	return _vp


func camera() -> Camera3D:
	return _cam


func current_mesh() -> MeshInstance3D:
	return _mesh


## Swap what the icon shows; null clears it.
func show_mesh(mesh: MeshInstance3D) -> void:
	if _world == null:
		push_error("IconPreview.show_mesh: build() was never called")
		return
	if _mesh != null and is_instance_valid(_mesh):
		## Detached first: a queued free still draws for the rest of the frame, on top of the
		## replacement that is about to be added at the same spot.
		_world.remove_child(_mesh)
		_mesh.queue_free()
	_mesh = mesh
	if mesh != null:
		_world.add_child(mesh)
