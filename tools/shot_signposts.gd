## Signpost look inspection on the live city: finds a fingerpost in the spawn district, then
## photographs it from both readable sides plus straight down.
##
## The overhead shot is the one that matters. It is taken north-up / east-right (camera pitched
## -90° with no yaw), so an arrow that should point at the +X neighbour must point *right* on
## screen and the -Z one must point *up*. A board flipped 180° is obvious there and nowhere else.
## The log prints the same thing numerically: caption, measured tip direction, and the district
## that direction actually leads into.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Needs an ordinary tile — special tiles carry no posts:
##
##   powershell -Command "& '.\tools\run_test.ps1' -Scene shot_signposts -Rendered
##     -GodotArgs @('--spawn-theme=garden')"
extends Node

const WORLD_SEED := 42
const FRONT_PNG := "res://tools/signpost_front.png"
const BACK_PNG := "res://tools/signpost_back.png"
const TOP_PNG := "res://tools/signpost_top.png"

var _failed := false
## The placer culls against whichever camera it was bound to, so the shot camera has to take
## that job over or every post is invisible in the picture.
var _placer: SignpostPlacer


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	await _settle(10.0)

	var district := _spawn_district(city)
	if district == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	var theme := district.generator.theme
	if theme.is_special():
		push_error(
			"FAIL spawn tile %s is %s, which carries no posts — run with --spawn-theme=garden"
			% [district.coord, theme.display_name]
		)
		get_tree().quit(1)
		return
	if district.signposts == null:
		push_error("FAIL district %s never built a signpost placer" % district.coord)
		get_tree().quit(1)
		return
	_placer = district.signposts
	var posts := _placer.get_children()
	print("district %s (%s): %d signposts" % [district.coord, theme.display_name, posts.size()])
	if posts.is_empty():
		push_error("FAIL ordinary district %s got no signposts" % district.coord)
		get_tree().quit(1)
		return

	var post: Signpost = posts[0] as Signpost
	_report_boards(post, district.coord)

	## Park the walker beside the post so the terrain around it meshes before the shots.
	var top := post.board_tip_direction(0)
	walker.global_position = post.global_position + Vector3(0.0, 40.0, 0.0) - top * 6.0
	await _settle(12.0)

	## The readable faces are perpendicular to the top board's arrow.
	var side := Vector3(-top.z, 0.0, top.x)
	var board_mid := post.global_position + Vector3(0.0, Signpost.BOARD_TOP_Y_M - 0.6, 0.0) + top * 0.9
	await _shoot(board_mid + side * 4.2 + Vector3(0.0, 0.8, 0.0), board_mid, FRONT_PNG)
	await _shoot(board_mid - side * 4.2 + Vector3(0.0, 0.8, 0.0), board_mid, BACK_PNG)
	await _shoot_aerial(post.global_position, TOP_PNG)

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Every board's caption next to the tile its arrow physically leads into, so the picture and
## the numbers have to agree.
func _report_boards(post: Signpost, home: Vector2i) -> void:
	if post.board_count() != 4:
		_fail("FAIL post carries %d boards, wanted one per neighbour" % post.board_count())
	for i in range(post.board_count()):
		var dir := post.board_tip_direction(i)
		var span := (
			float(DistrictCoord.SIZE_X_VOX) * CityRoot.VOXEL_SIZE
			if absf(dir.x) > 0.5
			else float(DistrictCoord.SIZE_Z_VOX) * CityRoot.VOXEL_SIZE
		)
		var landing := DistrictCoord.from_world(post.global_position + dir * span, CityRoot.VOXEL_SIZE)
		var expected := DistrictName.for_district(WORLD_SEED, landing)
		print(
			"  board %d: '%s' → dir %s → tile %s ('%s')"
			% [i, post.board_text(i), dir, landing, expected]
		)
		if post.board_text(i) != expected:
			_fail("FAIL board %d names '%s' but points into %s" % [i, post.board_text(i), landing])
		if (landing - home).length_squared() != 1:
			_fail("FAIL board %d leads to %s, not a neighbour of %s" % [i, landing, home])


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.coord == want and di.generator != null:
			return di
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target)
	cam.make_current()
	_placer.set_camera(cam)
	await _settle(2.0)
	_save(path)
	cam.queue_free()


## Map-aligned oblique: no yaw, so screen-right is world +X and screen-up is world -Z. Steep
## enough to see all four arms at once, shallow enough that the tapered tips still read.
func _shoot_aerial(post_pos: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = post_pos + Vector3(0.0, 10.5, 9.0)
	cam.rotation = Vector3(deg_to_rad(-38.0), 0.0, 0.0)
	cam.make_current()
	_placer.set_camera(cam)
	await _settle(2.0)
	_save(path)
	cam.queue_free()


func _save(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)
