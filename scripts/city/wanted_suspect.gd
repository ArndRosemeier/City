## The one killer every wanted bill in the city is about: their look, and the mugshot printed
## on the posters.
##
## A poster is only worth reading if the face on it is the face in the street, so the suspect
## is rolled once per world rather than once per tile. Every district that pastes a bill
## dresses its marked pedestrian in exactly this outfit, and the portrait is baked from the
## same outfit, so the picture cannot drift from the person.
##
## Nothing here substitutes a stand-in when a step fails. A missing hostile outfit, a rig
## without a head or a viewport that renders nothing are all reported with `push_error` and
## leave the portrait null — the posters then go up with an empty frame, which is loud enough
## to notice and specific enough to fix.
class_name WantedSuspect
extends RefCounted

## Mugshot resolution. Read from a couple of metres on a 3 m frame, so a little over the
## screen pixels it ever covers.
const PORTRAIT_W := 320
const PORTRAIT_H := 400

## Head-and-shoulders framing. Bodies face −Z once `CrowdPedVisual` has turned them, so the
## lens sits on −Z (same geometry as the ped close-up shot tool).
const CAM_DIST := 1.0
const CAM_DROP := 0.11
const CAM_FOV := 31.0

## MakeHuman / MPFB rigs name it exactly this; `BodyProportions` scales the same bone.
const HEAD_BONE := "Head"

static var _world_seed: int = 0
static var _outfit: PedOutfit = null
static var _portrait: ImageTexture = null
## One attempt per world. A second try would only reprint the same error on the next tile
## that streams in, and the first one already named the broken step.
static var _bake_tried: bool = false
static var _baking: bool = false


## The killer's look for this world. Same answer on every tile, so the marked ped and the
## portrait are the same person.
static func identity(world_seed: int) -> PedOutfit:
	if _outfit != null and _world_seed == world_seed:
		return _outfit
	_world_seed = world_seed
	_portrait = null
	_bake_tried = false
	_outfit = _roll(world_seed)
	return _outfit


## The baked mugshot, or null when it has not been baked yet (or the bake failed and said so).
static func portrait() -> ImageTexture:
	return _portrait


## Bake the mugshot once per world. Must be awaited from a node in the tree — the viewport
## needs two frames to paint. Cheap after the first call.
static func ensure_portrait(world_seed: int, host: Node) -> void:
	var outfit := identity(world_seed)
	if outfit == null:
		return
	if _portrait != null or _bake_tried:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("WantedSuspect.ensure_portrait: no SceneTree")
		return
	## Two tiles can stream at once; the second waits rather than baking the same face twice.
	while _baking:
		if not _host_ok(host):
			return
		await tree.process_frame
	if _portrait != null or _bake_tried:
		return
	if not _host_ok(host):
		return
	## A dummy renderer has no framebuffer to read back, which is a property of the harness
	## rather than a fault in the poster: headless tests check the placement, the rendered
	## game checks the picture.
	if DisplayServer.get_name() == "headless":
		print("WantedSuspect: headless session, mugshot not baked")
		_bake_tried = true
		return
	_baking = true
	await _bake(outfit, host, tree)
	_baking = false
	_bake_tried = true


## Drop the cached suspect (tests that walk several worlds in one process).
static func forget() -> void:
	_outfit = null
	_portrait = null
	_bake_tried = false
	_world_seed = 0


static func _roll(world_seed: int) -> PedOutfit:
	## Taken from the hostile pool directly rather than through `pick`, which needs a sex up
	## front: with a single bandit outfit shipped, half the worlds would ask for the sex that
	## has none and get a nude body. The pool decides who the killer is.
	var pool := PedOutfitCatalog.outfits_for_faction(PedOutfit.Faction.HOSTILE)
	if pool.is_empty():
		push_error(
			"WantedSuspect: the hostile outfit pool is empty — export a bandit outfit before "
			+ "the city posts wanted bills"
		)
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x0BADFACE
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _host_ok(host: Node) -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree()


static func _bake(outfit: PedOutfit, host: Node, tree: SceneTree) -> void:
	var vp := SubViewport.new()
	vp.name = "MugshotBake"
	vp.size = Vector2i(PORTRAIT_W, PORTRAIT_H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = World3D.new()
	host.add_child(vp)

	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)

	## Front key plus a soft fill: a single directional light leaves half the face black,
	## which reads as a smudge once the picture is toned down to ink.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-18.0, 195.0, 0.0)
	key.light_energy = 1.5
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8.0, 130.0, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)

	## The same visual the crowd uses, so the poster is baked from the exact body the player
	## will meet — outfit scene, skin tint and all.
	var visual := CrowdPedVisual.new()
	visual.name = "Suspect"
	world.add_child(visual)
	visual.bind_agent(0, outfit.female, 1.0, outfit)

	var head_y := _head_height(visual, outfit)
	if head_y <= 0.0:
		vp.queue_free()
		return

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = CAM_FOV
	cam.position = Vector3(0.0, head_y, -CAM_DIST)
	cam.look_at(Vector3(0.0, head_y - CAM_DROP, 0.0), Vector3.UP)

	await tree.process_frame
	if not is_instance_valid(vp):
		return
	await tree.process_frame
	if not is_instance_valid(vp):
		return
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.get_width() == 0:
		push_error("WantedSuspect: the mugshot viewport rendered nothing")
		return
	img.convert(Image.FORMAT_RGBA8)
	_tone_sepia(img)
	_portrait = ImageTexture.create_from_image(img)


## Eye level of the baked body, from the rig. A guessed height would frame the chest or the
## sky depending on the outfit, so a rig without the bone is an error, not a shrug.
static func _head_height(visual: CrowdPedVisual, outfit: PedOutfit) -> float:
	var skel := _find_skeleton(visual)
	if skel == null:
		push_error(
			"WantedSuspect: outfit %s has no Skeleton3D — cannot frame a mugshot"
			% outfit.variant_id
		)
		return 0.0
	var bone := skel.find_bone(HEAD_BONE)
	if bone < 0:
		push_error(
			"WantedSuspect: outfit %s has no '%s' bone — cannot frame a mugshot"
			% [outfit.variant_id, HEAD_BONE]
		)
		return 0.0
	return skel.to_global(skel.get_bone_global_pose(bone).origin).y


static func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## Ink on old paper: desaturate, crush the blacks and warm what is left.
static func _tone_sepia(img: Image) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a <= 0.004:
				continue
			var l := c.get_luminance()
			img.set_pixel(
				x,
				y,
				Color(
					clampf(l * 0.86 + 0.14, 0.0, 1.0),
					clampf(l * 0.74 + 0.09, 0.0, 1.0),
					clampf(l * 0.55 + 0.05, 0.0, 1.0),
					c.a
				)
			)
