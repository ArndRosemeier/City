## Scatters a handful of fingerposts across an ordinary district, each naming and pointing at
## the four neighbouring tiles.
##
## Special districts (Hill, Graveyard, Lake, Castle, Fractal, Arena) get none: they have no
## through-streets to stand on, and a waymark in the middle of a lake reads as a glitch.
class_name SignpostPlacer
extends Node3D

const SignpostScript := preload("res://scripts/city/signpost.gd")
const DistrictNameScript := preload("res://scripts/city/district_name.gd")

## Feature salt for the site RNG, so posts do not land in step with scale pads or names.
const SITE_FEATURE_ID := 0x53474E

## Extra range a post keeps once it is already showing, so the draw-distance edge cannot chatter.
const FADE_HYSTERESIS_M := 12.0

## The four tiles a post can point at, as world XZ directions.
const CARDINALS: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]

@export var min_posts: int = 1
@export var max_posts: int = 4
## "Never close together": no two posts within this radius, so they read as sparse waymarks
## rather than a row of street furniture.
@export var min_separation_m: float = 90.0
@export var draw_distance_m: float = 140.0

var _posts: Array[Node3D] = []
var _camera: Camera3D
var _accum: float = 0.0


## Rebind the camera the draw-distance / frustum cull measures against.
func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_refresh_visibility()


func clear_posts() -> void:
	_posts.clear()
	for c in get_children():
		c.queue_free()


func place_from_planner(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	ground_thickness: int,
	origin_vox: Vector3i,
	world_seed: int,
	coord: Vector2i,
	camera: Camera3D
) -> void:
	clear_posts()
	_camera = camera
	if planner == null or planner.theme == null:
		push_error("SignpostPlacer.place_from_planner: planner/theme missing for %s" % coord)
		return
	if planner.theme.is_special():
		return

	var dseed := DistrictCoord.district_seed(world_seed, coord)
	var rng := RandomNumberGenerator.new()
	rng.seed = DistrictCoord.feature_seed(dseed, SITE_FEATURE_ID)
	var target := rng.randi_range(min_posts, max_posts)
	var sites := _pick_sites(planner, cell_size, voxel_size, ground_thickness, origin_vox, rng, target)

	var captions := _neighbour_captions(world_seed, coord)
	for site: Vector3 in sites:
		_spawn_post(site, captions, origin_vox, voxel_size)
	_refresh_visibility()
	print(
		"SignpostPlacer: %s posts=%d/%d (theme=%s)"
		% [coord, _posts.size(), target, planner.theme.display_name]
	)


## Deterministic sweep over the district's avenue cells, greedily keeping sites that clear
## `min_separation_m`. Shuffled rather than strided so the whole tile is in play.
func _pick_sites(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	ground_thickness: int,
	origin_vox: Vector3i,
	rng: RandomNumberGenerator,
	target: int
) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	var cells := planner.avenue_light_cells.duplicate()
	if cells.is_empty():
		return sites
	## Fisher-Yates off the seeded rng — Array.shuffle() would use the global one.
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp

	var gy := float(ground_thickness + 1) * voxel_size
	var oxw := float(origin_vox.x) * voxel_size
	var ozw := float(origin_vox.z) * voxel_size
	var min_d2 := min_separation_m * min_separation_m
	for cell: Vector2i in cells:
		if sites.size() >= target:
			break
		var wx := oxw + (float(cell.x) + 0.5) * float(cell_size) * voxel_size
		var wz := ozw + (float(cell.y) + 0.5) * float(cell_size) * voxel_size
		## Curb corner opposite the one ScalePadPlacer uses, so a post and a pad sharing a
		## cell end up on opposite sides of the junction instead of inside each other.
		var ox := -3.4 if (cell.x % 2) == 0 else 3.4
		var oz := -3.4 if (cell.y % 2) == 0 else 3.4
		var pos := Vector3(wx + ox, gy, wz + oz)
		if _too_close(sites, pos, min_d2):
			continue
		sites.append(pos)
	return sites


func _too_close(sites: Array[Vector3], pos: Vector3, min_d2: float) -> bool:
	for p: Vector3 in sites:
		if Vector2(p.x - pos.x, p.z - pos.z).length_squared() < min_d2:
			return true
	return false


## Generated name of each cardinal neighbour, indexed like CARDINALS.
func _neighbour_captions(world_seed: int, coord: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	for d: Vector3 in CARDINALS:
		## coord.x runs along world X, coord.y along world Z.
		var neighbour := coord + Vector2i(int(d.x), int(d.z))
		out.append(DistrictNameScript.for_district(world_seed, neighbour))
	return out


func _spawn_post(
	origin: Vector3, captions: PackedStringArray, origin_vox: Vector3i, voxel_size: float
) -> void:
	var post: Signpost = SignpostScript.new() as Signpost
	post.name = "Signpost"
	add_child(post)
	post.position = origin
	post.build_pole()
	## Nearest border first, so the top board is the tile you would reach soonest from here.
	for i in _cardinals_by_proximity(origin, origin_vox, voxel_size):
		post.add_board(CARDINALS[i], captions[i])
	_posts.append(post)


## CARDINALS indices sorted by how close `origin` is to that side's district border.
func _cardinals_by_proximity(
	origin: Vector3, origin_vox: Vector3i, voxel_size: float
) -> PackedInt32Array:
	var min_x := float(origin_vox.x) * voxel_size
	var min_z := float(origin_vox.z) * voxel_size
	var max_x := min_x + float(DistrictCoord.SIZE_X_VOX) * voxel_size
	var max_z := min_z + float(DistrictCoord.SIZE_Z_VOX) * voxel_size
	var ranked: Array = []
	for i in range(CARDINALS.size()):
		var d: Vector3 = CARDINALS[i]
		var gap := 0.0
		if d.x > 0.0:
			gap = max_x - origin.x
		elif d.x < 0.0:
			gap = origin.x - min_x
		elif d.z > 0.0:
			gap = max_z - origin.z
		else:
			gap = origin.z - min_z
		ranked.append({"i": i, "gap": gap})
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["gap"]) < float(b["gap"])
	)
	var out := PackedInt32Array()
	for r: Dictionary in ranked:
		out.append(int(r["i"]))
	return out


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	_refresh_visibility()


## Draw distance only. Frustum culling is deliberately left to the renderer, which does it per
## frame against each mesh's real bounds: testing one point up the pole instead made a post
## wink out whenever that point crossed the screen edge — or whenever you walked up close and
## it went over the top of the view — while the boards were still filling the screen.
func _refresh_visibility() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam := _camera.global_position
	var show_r2 := draw_distance_m * draw_distance_m
	## Widened once shown, so standing on the boundary cannot chatter it on and off.
	var hide_r2 := (draw_distance_m + FADE_HYSTERESIS_M) * (draw_distance_m + FADE_HYSTERESIS_M)
	for post: Node3D in _posts:
		if not is_instance_valid(post):
			continue
		var limit := hide_r2 if post.visible else show_r2
		post.visible = post.global_position.distance_squared_to(cam) <= limit
