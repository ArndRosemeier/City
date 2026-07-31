## One front-facing portrait ImageTexture per CreatureCatalog id, baked once via SubViewport.
## Arena summon boards (and anything else) ask `texture_for` / `bake_ids`.
class_name MonsterIconCache
extends RefCounted

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")

const ICON_PX := 128
## Static cache survives board rebuilds within a session.
static var _textures: Dictionary = {}  ## String -> ImageTexture


static func texture_for(monster_id: String) -> Texture2D:
	return _textures.get(monster_id) as Texture2D


## Bake any missing portraits. Must be awaited from a Node in the tree.
static func bake_ids(ids: PackedStringArray, host: Node) -> void:
	if host == null or not is_instance_valid(host):
		push_error("MonsterIconCache.bake_ids: host required")
		return
	for mid: String in ids:
		if mid.is_empty() or _textures.has(mid):
			continue
		await _bake_one(mid, host)


static func _bake_one(monster_id: String, host: Node) -> void:
	var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(monster_id)
	if entry == null:
		_textures[monster_id] = _fallback_tex(monster_id)
		return
	var packed: PackedScene = load(entry.path) as PackedScene
	if packed == null:
		_textures[monster_id] = _fallback_tex(monster_id)
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		_textures[monster_id] = _fallback_tex(monster_id)
		return

	var vp := SubViewport.new()
	vp.name = "IconBake"
	vp.size = Vector2i(ICON_PX, ICON_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = World3D.new()
	host.add_child(vp)

	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	light.light_energy = 1.15
	world.add_child(light)

	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.add_child(root)
	root.rotation = Vector3(0.0, entry.model_yaw, 0.0)
	root.position = entry.model_offset
	var player := _find_player(root)
	if player != null:
		var clip := CreatureClipsScript.try_resolve(
			player.get_animation_list(), CreatureClips.Action.IDLE
		)
		if not clip.is_empty():
			player.play(clip)
			player.seek(0.0, true)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var tall := maxf(entry.measured_height, 1.0)
	var dist := tall * 1.55
	cam.position = Vector3(0.0, tall * 0.52, dist)
	cam.look_at(Vector3(0.0, tall * 0.45, 0.0), Vector3.UP)
	cam.fov = 28.0

	## Two frames so the viewport paints the posed mesh.
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		_textures[monster_id] = ImageTexture.create_from_image(img)
	else:
		_textures[monster_id] = _fallback_tex(monster_id)
	vp.queue_free()


static func _fallback_tex(monster_id: String) -> ImageTexture:
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	var h := float(monster_id.hash() & 0xffff) / 65535.0
	var c := Color.from_hsv(h, 0.55, 0.75, 1.0)
	img.fill(c)
	return ImageTexture.create_from_image(img)


static func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
