## District names + signposts: the generated names, which tiles get posts, and — the part that
## actually goes wrong — whether an arrow points at the district whose name is on it.
##
## What is at risk, and therefore checked:
##   - A name is only useful if it is the *same* name next time. It is derived from the district
##     seed, so a reload, an unload, or a hop from the far side of the map must reproduce it.
##   - A signpost is a lie if the board is flipped. So the direction is never taken from the
##     input: it is measured from the live arrow-tip node, walked one tile along, and fed back
##     through `DistrictCoord.from_world`. If any axis or sign in the chain is wrong — the yaw
##     formula, the +X tip convention, coord.x↔X vs coord.y↔Z — the caption stops matching the
##     tile the arrow physically leads to.
##   - Captions must be readable from both sides, so each face carries its own label sitting on
##     the outside of the plank it faces.
##   - Posts must not bunch up, and special tiles must get none.
##
## Run: powershell -File tools\run_test.ps1 test_signposts
extends Node3D

const DistrictNameScript := preload("res://scripts/city/district_name.gd")
const SignpostScript := preload("res://scripts/city/signpost.gd")
const SignpostPlacerScript := preload("res://scripts/city/signpost_placer.gd")

const WORLD_SEED := 4242
const VOX := 0.5
const CELL_SIZE := 28
const GROUND_THICKNESS := 6
## An ordinary tile for the placer runs. The theme is forced on the planner, so the coord only
## has to be somewhere the neighbours are interesting.
const TEST_COORD := Vector2i(2, 1)

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_theme_patterns()
	_check_specialness()
	_check_name_determinism()
	_check_name_spread()
	_check_board_orientation()
	_check_caption_faces()
	_check_placement()
	_check_special_tiles_get_none()
	_check_placement_determinism()
	_check_visibility_does_not_flicker()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_theme_patterns() -> void:
	for id in range(DistrictTheme.COUNT):
		var theme := DistrictTheme.make(id)
		if theme.name_pattern.count("%s") != 1:
			_fail(
				"FAIL theme %s has name_pattern '%s' — needs exactly one %%s"
				% [theme.display_name, theme.name_pattern]
			)
		var label := DistrictNameScript.apply_pattern(theme, "Anoha")
		if not label.contains("Anoha"):
			_fail("FAIL theme %s dropped the stem: '%s'" % [theme.display_name, label])
		if label == "Anoha":
			_fail("FAIL theme %s adds no theme wording at all" % theme.display_name)
	print("patterns: %d themes, each one %%s and a theme word" % DistrictTheme.COUNT)


func _check_specialness() -> void:
	## Every theme whose planner gives it edge stubs only, so there is no through-street for a
	## signpost to stand on. Siege is deliberately absent: it keeps the full street grid.
	var expected := [
		DistrictTheme.HILL, DistrictTheme.GRAVEYARD, DistrictTheme.LAKE,
		DistrictTheme.CASTLE, DistrictTheme.FRACTAL, DistrictTheme.ARENA,
		DistrictTheme.ZOO, DistrictTheme.GAMING,
	]
	for id in range(DistrictTheme.COUNT):
		var want: bool = expected.has(id)
		var got := DistrictTheme.make(id).is_special()
		if got != want:
			_fail(
				"FAIL theme %s is_special()=%s, expected %s"
				% [DistrictTheme.make(id).display_name, got, want]
			)
	print("specialness: %d special of %d themes" % [expected.size(), DistrictTheme.COUNT])


func _check_name_determinism() -> void:
	for i in range(40):
		var coord := Vector2i(i - 20, 7 - i)
		var first := DistrictNameScript.for_district(WORLD_SEED, coord)
		var second := DistrictNameScript.for_district(WORLD_SEED, coord)
		if first != second:
			_fail("FAIL %s named '%s' then '%s'" % [coord, first, second])
		if first.is_empty():
			_fail("FAIL %s got an empty name" % coord)
		## Bare stem plus theme wording — a fingerpost caption, not a sentence.
		if first.length() > 24:
			_fail("FAIL %s got an unusable caption '%s'" % [coord, first])
	## A different world must rename every tile, or names would be world-independent.
	var same := 0
	for i in range(40):
		var coord := Vector2i(i, -i)
		if (
			DistrictNameScript.for_district(WORLD_SEED, coord)
			== DistrictNameScript.for_district(WORLD_SEED + 1, coord)
		):
			same += 1
	if same > 4:
		_fail("FAIL %d/40 names survived a world seed change" % same)
	print("determinism: names stable per (seed, coord), %d/40 shared across seeds" % same)


func _check_name_spread() -> void:
	var seen := {}
	var count := 0
	for x in range(-10, 10):
		for z in range(-10, 10):
			seen[DistrictNameScript.for_district(WORLD_SEED, Vector2i(x, z))] = true
			count += 1
	var distinct := seen.size()
	if float(distinct) < float(count) * 0.9:
		_fail("FAIL only %d distinct names over %d tiles" % [distinct, count])
	var samples := PackedStringArray()
	for x in range(8):
		samples.append(DistrictNameScript.for_district(WORLD_SEED, Vector2i(x, 3)))
	print("spread: %d distinct names over %d tiles" % [distinct, count])
	print("samples: %s" % ", ".join(samples))


## The load-bearing check. Each board is asked to point at a cardinal; the answer is read back
## off the arrow-tip node, not off the request.
func _check_board_orientation() -> void:
	var post: Signpost = SignpostScript.new() as Signpost
	add_child(post)
	post.build_pole()
	var wanted: Array[Vector3] = [
		Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD,
		Vector3(1.0, 0.0, 1.0).normalized(),
	]
	for d: Vector3 in wanted:
		post.add_board(d, "Probe")
	if post.board_count() != wanted.size():
		_fail("FAIL built %d boards, wanted %d" % [post.board_count(), wanted.size()])
	for i in range(wanted.size()):
		var want: Vector3 = wanted[i]
		var got := post.board_tip_direction(i)
		if got.dot(want) < 0.999:
			_fail(
				"FAIL board %d asked for %s, tip actually points %s (dot %.4f)"
				% [i, want, got, got.dot(want)]
			)
		if absf(got.y) > 0.001:
			_fail("FAIL board %d tip is not horizontal: %s" % [i, got])
	## Boards must stack, not overlap: each one lower than the last.
	for i in range(1, wanted.size()):
		if post.board_origin(i).y >= post.board_origin(i - 1).y:
			_fail("FAIL board %d does not sit below board %d" % [i, i - 1])
	if post.board_origin(wanted.size() - 1).y < 2.0:
		_fail("FAIL the lowest board hangs into head height")
	post.queue_free()
	print("orientation: %d boards point where they were told" % wanted.size())


func _check_caption_faces() -> void:
	var post: Signpost = SignpostScript.new() as Signpost
	add_child(post)
	post.build_pole()
	post.add_board(Vector3.FORWARD, "Anoha-Hill")
	var tip := post.board_tip_direction(0)
	var origin := post.board_origin(0)
	var faces := post.caption_transforms(0)
	if faces.size() != 2:
		_fail("FAIL board carries %d captions, wanted 2 (one per face)" % faces.size())
	var normals: Array[Vector3] = []
	for face: Transform3D in faces:
		var normal := face.basis.z.normalized()
		normals.append(normal)
		if absf(normal.y) > 0.001:
			_fail("FAIL caption faces out of plumb: %s" % normal)
		if absf(normal.dot(tip)) > 0.001:
			_fail("FAIL caption reads along the arrow instead of across it: %s" % normal)
		## The label must sit on the side of the plank it faces, or it reads through the board.
		if (face.origin - origin).dot(normal) <= 0.0:
			_fail("FAIL caption sits behind the face it reads from")
	if normals[0].dot(normals[1]) > -0.999:
		_fail("FAIL the two captions do not face opposite ways: %s / %s" % normals)
	if post.board_text(0) != "Anoha-Hill":
		_fail("FAIL caption text came back as '%s'" % post.board_text(0))
	print("captions: both faces readable, '%s'" % post.board_text(0))
	post.queue_free()


func _check_placement() -> void:
	var placer := _run_placer(DistrictTheme.GARDEN_RESIDENTIAL, TEST_COORD)
	var posts := _posts_of(placer)
	if posts.size() < placer.min_posts or posts.size() > placer.max_posts:
		_fail("FAIL placed %d posts, wanted %d-%d" % [posts.size(), placer.min_posts, placer.max_posts])
	for i in range(posts.size()):
		for j in range(i + 1, posts.size()):
			var a := posts[i].global_position
			var b := posts[j].global_position
			var gap := Vector2(a.x - b.x, a.z - b.z).length()
			if gap < placer.min_separation_m:
				_fail("FAIL posts %d and %d stand %.1f m apart (min %.1f)" % [i, j, gap, placer.min_separation_m])
	for post: Signpost in posts:
		_check_post_points_true(post)
	print("placement: %d posts, all spread and all pointing true" % posts.size())
	placer.queue_free()


## Walk one tile span along each arrow and ask the engine which district that lands in. The
## caption has to name *that* tile.
func _check_post_points_true(post: Signpost) -> void:
	if post.board_count() != 4:
		_fail("FAIL post carries %d boards, wanted one per neighbour" % post.board_count())
	var reached := {}
	for i in range(post.board_count()):
		var dir := post.board_tip_direction(i)
		var span := (
			float(DistrictCoord.SIZE_X_VOX) * VOX
			if absf(dir.x) > 0.5
			else float(DistrictCoord.SIZE_Z_VOX) * VOX
		)
		var landing := DistrictCoord.from_world(post.global_position + dir * span, VOX)
		if landing == TEST_COORD:
			_fail("FAIL board %d points back into its own tile %s" % [i, landing])
		if (landing - TEST_COORD).length_squared() != 1:
			_fail("FAIL board %d leads to %s, not a cardinal neighbour of %s" % [i, landing, TEST_COORD])
		var expected := DistrictNameScript.for_district(WORLD_SEED, landing)
		if post.board_text(i) != expected:
			_fail(
				"FAIL board %d reads '%s' but its arrow leads to %s, which is '%s'"
				% [i, post.board_text(i), landing, expected]
			)
		if reached.has(landing):
			_fail("FAIL two boards on one post lead to %s" % landing)
		reached[landing] = true


func _check_special_tiles_get_none() -> void:
	for id in range(DistrictTheme.COUNT):
		if not DistrictTheme.make(id).is_special():
			continue
		var placer := _run_placer(id, TEST_COORD)
		var posts := _posts_of(placer)
		if not posts.is_empty():
			_fail("FAIL special theme %s got %d posts" % [DistrictTheme.make(id).display_name, posts.size()])
		placer.queue_free()
	print("special tiles: no posts on any of them")


func _check_placement_determinism() -> void:
	var first := _run_placer(DistrictTheme.OLD_TOWN, TEST_COORD)
	var second := _run_placer(DistrictTheme.OLD_TOWN, TEST_COORD)
	var a := _posts_of(first)
	var b := _posts_of(second)
	if a.size() != b.size():
		_fail("FAIL same tile placed %d posts then %d" % [a.size(), b.size()])
	else:
		for i in range(a.size()):
			if a[i].global_position.distance_to(b[i].global_position) > 0.001:
				_fail("FAIL post %d moved between runs: %s vs %s" % [i, a[i].global_position, b[i].global_position])
	first.queue_free()
	second.queue_free()
	print("determinism: %d posts land in the same spots on a re-bake" % a.size())


## The cull used to test one point at the top of the pole against the frustum, so a post winked
## out whenever that point left the view — standing close to it, or panning it toward the screen
## edge — even with its boards filling the screen. Walk a camera in and around a post and it must
## stay shown the whole way.
func _check_visibility_does_not_flicker() -> void:
	var placer := _run_placer(DistrictTheme.GARDEN_RESIDENTIAL, TEST_COORD)
	var posts := _posts_of(placer)
	if posts.is_empty():
		_fail("FAIL no posts to check visibility on")
		placer.queue_free()
		return
	var post: Signpost = posts[0]
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)

	## Straight at it, from far enough to be in range down to standing at its foot.
	for metres in [130.0, 90.0, 40.0, 12.0, 4.0, 1.5]:
		cam.global_position = post.global_position + Vector3(0.0, 1.7, float(metres))
		cam.look_at(post.global_position + Vector3(0.0, 1.7, 0.0))
		placer.set_camera(cam)
		if not post.visible:
			_fail("FAIL post culled from %.1f m away while looking straight at it" % metres)

	## Panned away, close up: the boards leave the view but the post must not be unloaded, or it
	## pops on the way back. Godot culls the meshes itself.
	cam.global_position = post.global_position + Vector3(0.0, 1.7, 6.0)
	for turn in [0.0, 45.0, 90.0, 135.0, 180.0]:
		cam.rotation = Vector3(0.0, deg_to_rad(float(turn)), 0.0)
		placer.set_camera(cam)
		if not post.visible:
			_fail("FAIL post culled at 6 m when the camera turned %.0f°" % turn)

	## Past the draw distance it does go, and it must not chatter on the boundary.
	cam.global_position = post.global_position + Vector3(0.0, 1.7, placer.draw_distance_m + 40.0)
	placer.set_camera(cam)
	if post.visible:
		_fail("FAIL post still drawn well beyond its draw distance")
	var flips := 0
	var was := post.visible
	for step in range(24):
		## Hover right on the edge, drifting by centimetres.
		var jitter := 0.05 * float(step % 2)
		cam.global_position = (
			post.global_position + Vector3(0.0, 1.7, placer.draw_distance_m + jitter)
		)
		placer.set_camera(cam)
		if post.visible != was:
			flips += 1
			was = post.visible
	if flips > 1:
		_fail("FAIL post flipped visibility %d times while hovering on the draw-distance edge" % flips)
	cam.queue_free()
	placer.queue_free()
	print("visibility: swept 130 m in to 1.5 m, a full turn at 6 m, 24 steps on the distance edge")


func _run_placer(theme_id: int, coord: Vector2i) -> SignpostPlacer:
	var planner := DistrictPlanner.new()
	planner.theme = DistrictTheme.make(theme_id)
	planner.cell_size = CELL_SIZE
	planner.avenue_light_cells = _fake_avenue_cells()
	var placer: SignpostPlacer = SignpostPlacerScript.new() as SignpostPlacer
	add_child(placer)
	placer.place_from_planner(
		planner, CELL_SIZE, VOX, GROUND_THICKNESS,
		DistrictCoord.origin_vox(coord), WORLD_SEED, coord, null
	)
	return placer


## Stand-in for the planner's avenue grid: a checkerboard across the whole tile, which is what
## the real one is a subset of.
func _fake_avenue_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var cells_x := DistrictCoord.SIZE_X_VOX / CELL_SIZE
	var cells_z := DistrictCoord.SIZE_Z_VOX / CELL_SIZE
	for z in range(cells_z):
		for x in range(cells_x):
			if (x + z) % 2 == 0:
				cells.append(Vector2i(x, z))
	return cells


func _posts_of(placer: SignpostPlacer) -> Array[Signpost]:
	var out: Array[Signpost] = []
	for c in placer.get_children():
		out.append(c as Signpost)
	return out
