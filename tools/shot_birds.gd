## Bird look inspection: boots the live city, finds a flock's canopy perch on the spawn tile
## and photographs a bird close up, in the tree line, and on the wing after it is flushed.
##
## Birds are centimetres of geometry: at street distance they are meant to be specks, so the
## close-up is what says whether the model reads as a bird at all.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Wants a tile with trees on it — the seeded spawn is whatever the seed says:
##
##   powershell -File tools\run_test.ps1 shot_birds -Rendered -GodotArgs "--spawn-theme=garden"
extends Node

const WORLD_SEED := 42
const CLOSE_PNG := "res://tools/birds_perched_close.png"
const TREELINE_PNG := "res://tools/birds_treeline.png"
const FLUSHED_PNG := "res://tools/birds_flushed.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	## Waited out on the clock, not on a frame count: an empty scene runs at several hundred
	## frames a second, so a frame budget expires while the spawn tile is still baking.
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
	var flock := district.birds
	if flock == null or not is_instance_valid(flock):
		push_error("FAIL district %s has no flock" % str(district.coord))
		get_tree().quit(1)
		return
	print(
		"flock on %s: %d birds, %d perches (%d canopy)"
		% [str(district.coord), flock.bird_live_count(), flock.perch_count(), flock.tree_perch_count()]
	)
	if flock.tree_perch_count() == 0:
		push_error(
			"FAIL district %s found no canopy to sit on — run with --spawn-theme=garden"
			% str(district.coord)
		)
		get_tree().quit(1)
		return

	## The walker has to stand next to the tree before the terrain around it meshes, and the
	## flock only ticks inside its draw distance, so move in first and pick a sitter after.
	var seat := _open_perch(flock, district.live_brush())
	## Stand the walker back from the tree. Terrain only meshes around it, so it has to be
	## nearby — but park it any closer and the flock does the right thing and leaves before
	## the shutter opens, which is what the first three attempts at this shot photographed.
	await _goto(walker, seat + Vector3(20.0, 0.0, 20.0))
	var bird := _sit_one_bird(flock, seat)

	await _shoot(bird.global_position + Vector3(0.42, 0.28, 0.42), bird.global_position, CLOSE_PNG)
	await _shoot(seat + Vector3(9.0, 3.0, 9.0), seat, TREELINE_PNG)

	## Walk something up to the tree and photograph what the flock does about it.
	flock.flush_near(seat, flock.flush_radius_m)
	await _settle(1.4)
	await _shoot(seat + Vector3(14.0, 6.0, 14.0), seat + Vector3(0.0, 6.0, 0.0), FLUSHED_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


## The canopy top with the most air around it. A bird deep in a hedge is a perfectly good
## bird and a useless photograph — the first close-up taken here was of the inside of one.
func _open_perch(flock: BirdDirector, brush: CityBrush) -> Vector3:
	var best: Vector3 = flock._perches[0]
	var best_open := -1
	for i in range(flock.tree_perch_count()):
		var seat: Vector3 = flock._perches[i]
		var base := Vector3i(
			int(floor(seat.x / CityRoot.VOXEL_SIZE)),
			int(floor(seat.y / CityRoot.VOXEL_SIZE)),
			int(floor(seat.z / CityRoot.VOXEL_SIZE))
		)
		var open := 0
		for dy in range(0, 3):
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if brush.get_vox(base + Vector3i(dx, dy, dz)) == VoxelMaterial.AIR:
						open += 1
		if open > best_open:
			best_open = open
			best = seat
	print("close-up perch %s has %d/75 open cells around it" % [str(best), best_open])
	return best


## Park a bird on the chosen seat so the close-up has a subject whatever the flock is doing.
func _sit_one_bird(flock: BirdDirector, seat: Vector3) -> BirdActor:
	var bird: BirdActor = flock._birds[0]
	bird.sit_on(seat)
	bird.decide_in = 600.0
	bird.visible = true
	return bird


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


## Terrain only meshes around the walker, so it is parked at the target and given time to
## mesh before anything is photographed.
func _goto(walker: Node3D, target: Vector3) -> void:
	walker.global_position = Vector3(target.x, target.y + 6.0, target.z)
	await _settle(12.0)


func _shoot(from: Vector3, look_at: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = from
	cam.fov = 60.0
	cam.near = 0.02
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(look_at, Vector3.UP)
	cam.make_current()
	await _settle(2.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
