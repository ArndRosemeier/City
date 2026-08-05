## One ImageTexture per inventory item id, baked once via SubViewport from
## `InventoryItemVisual` (same cuts / materials as the inventory panel).
##
## Ui3D buttons take a `Texture2D`; the live `IconPreview` SubViewport is a Control
## widget, so Lodestone / boards ask here for a baked portrait instead.
class_name InventoryIconCache
extends RefCounted

const ICON_PX := 128

## Static cache survives panel rebuilds within a session.
static var _textures: Dictionary = {}  ## String -> ImageTexture
static var _bake_lock: bool = false


static func texture_for(item_id: String) -> Texture2D:
	return _textures.get(item_id) as Texture2D


## Bake any missing icons. Must be awaited from a Node in the tree.
static func bake_ids(ids: PackedStringArray, host: Node) -> void:
	if host == null or not is_instance_valid(host):
		push_error("InventoryIconCache.bake_ids: host required")
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("InventoryIconCache.bake_ids: no SceneTree")
		return
	## Every pad console in a Siege quarter queues a bake, so the whole batch can be
	## outlived by its hosts on district unload. Carry the id, not the reference.
	var host_id := host.get_instance_id()
	while _bake_lock:
		if _live_host(host_id) == null:
			return
		await tree.process_frame
	if _live_host(host_id) == null:
		return
	_bake_lock = true
	for item_id: String in ids:
		if _live_host(host_id) == null:
			break
		if item_id.is_empty() or _textures.has(item_id):
			continue
		await _bake_one(item_id, host_id, tree)
	_bake_lock = false


## The host may be freed while we await a frame. Passing a freed instance into a `Node`-typed
## parameter is rejected before the body runs, so `is_instance_valid` inside such a helper never
## gets its chance — validity has to be settled by id first.
static func _live_host(host_id: int) -> Node:
	if not is_instance_id_valid(host_id):
		return null
	var node := instance_from_id(host_id) as Node
	if node == null or not node.is_inside_tree():
		return null
	return node


static func _bake_one(item_id: String, host_id: int, tree: SceneTree) -> void:
	var host := _live_host(host_id)
	if host == null:
		return
	var mesh := InventoryItemVisual.make_mesh(item_id)
	if mesh == null:
		_textures[item_id] = _fallback_tex(item_id)
		return

	var vp := SubViewport.new()
	vp.name = "InvIconBake"
	vp.size = Vector2i(ICON_PX, ICON_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = World3D.new()
	host.add_child(vp)

	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.1
	world.add_child(light)

	world.add_child(mesh)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = IconPreview.CAM_FOV
	cam.look_at_from_position(IconPreview.camera_position(), Vector3.ZERO, Vector3.UP)

	## Two frames so the viewport paints the mesh. Await the main tree — never
	## `host.get_tree()` after an await; the panel may already be freed on unload.
	await tree.process_frame
	if not is_instance_valid(vp):
		return
	await tree.process_frame
	if not is_instance_valid(vp):
		return
	var img: Image = vp.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		_textures[item_id] = ImageTexture.create_from_image(img)
	else:
		_textures[item_id] = _fallback_tex(item_id)
	if is_instance_valid(vp):
		vp.queue_free()


static func _fallback_tex(item_id: String) -> ImageTexture:
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	var h := float(item_id.hash() & 0xffff) / 65535.0
	var c := Color.from_hsv(h, 0.45, 0.7, 1.0)
	img.fill(c)
	return ImageTexture.create_from_image(img)
