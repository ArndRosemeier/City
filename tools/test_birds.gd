## Ambient birds: where they land, what sends them up, and what they cost when nobody is
## looking.
##
## What is at risk, and therefore checked:
##   - Perches come from a live voxel scan, not the bake. If that scan drifts by a voxel the
##     flock sits inside canopies or hovers above them, so every tree seat is checked against
##     the voxel that is supposed to be holding it up.
##   - Trees are the point. A scan that mostly returns pavement would still "work" and would
##     still look wrong, so the tree seats have to outnumber the fallback ones.
##   - Birds take off when an actor walks up. Both halves matter: close actors must flush the
##     flock, and distant ones must not — a flock that scatters at any range never sits.
##   - A startled bird has to come back down, or the first disturbance empties the trees for
##     the rest of the session.
##   - The flock must stay over its own tile. Birds have no streaming of their own, so one
##     that wanders off is a bird over unloaded ground.
##   - Draw distance needs hysteresis, or a player on the boundary sees the flock strobe.
##
## Run: powershell -File tools\run_test.ps1 test_birds
extends Node3D

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const TreeStamperScript := preload("res://scripts/city/tree_stamper.gd")
const BirdDirectorScript := preload("res://scripts/city/bird_director.gd")

const VOX := 0.5
const GROUND_Y := 6
const SIZE_VOX := Vector2i(96, 96)
const CELL_SIZE := 28
## Trees are planted on a grid with this pitch so canopies never merge into one blob.
const TREE_PITCH := 14
const SIM_DT := 1.0 / 30.0

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var brush := _build_grove()
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	var flock := _build_flock(brush, cam)

	_check_perches(flock, brush)
	_check_flock_spawned(flock)
	_check_model_is_bird_shaped(flock)
	_check_flight_wobbles(flock)
	_check_flush_radius(flock)
	_check_blast_scatters_wider(flock)
	_check_startled_birds_land_again(flock)
	_check_stays_over_the_tile(flock)
	_check_draw_distance(flock, cam)
	_check_teardown(flock)

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## A patch of ground with a regular orchard on it: enough canopies that a 384-column scan
## cannot miss them, spaced far enough apart to stay separate perches.
func _build_grove() -> CityBrush:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	brush.fill_box(
		Vector3i(0, GROUND_Y, 0),
		Vector3i(SIZE_VOX.x, GROUND_Y + 1, SIZE_VOX.y),
		VoxelMaterial.SIDEWALK
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805
	var stamper: TreeStamper = TreeStamperScript.new() as TreeStamper
	stamper.brush = brush
	stamper.rng = rng
	## No canopy gems: a gem in place of a leaf would be a seat the scan should not offer.
	stamper.allow_canopy_gems = false
	var planted := 0
	for z in range(8, SIZE_VOX.y - 8, TREE_PITCH):
		for x in range(8, SIZE_VOX.x - 8, TREE_PITCH):
			stamper.round_tree(x, GROUND_Y, z)
			planted += 1
	## Two landmark pines, which grow straight through the scan band. They exist to be
	## refused: a scan that takes its own ceiling for a treetop seats birds inside canopies,
	## which is exactly what the first live screenshot of this feature showed.
	stamper.landmark_tree(24, GROUND_Y, 60)
	stamper.landmark_tree(60, GROUND_Y, 24)
	print("grove: %d round trees + 2 landmark pines over %dx%d voxels"
		% [planted, SIZE_VOX.x, SIZE_VOX.y])
	return brush


func _build_flock(brush: CityBrush, cam: Camera3D) -> BirdDirector:
	var flock: BirdDirector = BirdDirectorScript.new() as BirdDirector
	flock.name = "Birds"
	add_child(flock)
	## Nothing is culled during the behaviour checks; the cull gets its own pass at the end.
	flock.render_distance = 1000.0
	flock.setup(
		brush, null, Vector3i.ZERO, SIZE_VOX, GROUND_Y, CELL_SIZE, VOX, cam, 4242
	)
	return flock


## Every tree seat must be standing on foliage, and trees must be the flock's main option
## rather than an accident.
func _check_perches(flock: BirdDirector, brush: CityBrush) -> void:
	if flock.tree_perch_count() <= 0:
		_fail("FAIL scan found no canopy to sit on in a grove of trees")
		return
	if flock.tree_perch_count() <= flock.perch_count() - flock.tree_perch_count():
		_fail(
			"FAIL only %d of %d perches are trees — the scan is finding pavement, not canopy"
			% [flock.tree_perch_count(), flock.perch_count()]
		)
	for i in range(flock.perch_count()):
		var seat: Vector3 = flock._perches[i]
		var under := Vector3i(
			int(floor(seat.x / VOX)),
			int(floor((seat.y - VOX * 0.5) / VOX)),
			int(floor(seat.z / VOX))
		)
		var support := brush.get_vox(under)
		if support == VoxelMaterial.AIR:
			_fail("FAIL seat %s has nothing under it" % str(seat))
			return
		if i < flock.tree_perch_count() and not VoxelMaterial.is_foliage(support):
			_fail("FAIL tree seat %s stands on mat %d, not foliage" % [str(seat), support])
			return
		## The pines reach past the scan band, so this is where a scan that trusts its own
		## ceiling puts a bird in the middle of a crown.
		if brush.get_vox(under + Vector3i.UP) != VoxelMaterial.AIR:
			_fail("FAIL seat %s is buried under mat %d" % [str(seat), brush.get_vox(under + Vector3i.UP)])
			return
	print(
		"perches: %d seats, %d of them canopy tops, all on solid foliage"
		% [flock.perch_count(), flock.tree_perch_count()]
	)


func _check_flock_spawned(flock: BirdDirector) -> void:
	if flock.bird_live_count() != flock.bird_count:
		_fail(
			"FAIL flock is %d birds, wanted %d"
			% [flock.bird_live_count(), flock.bird_count]
		)
		return
	var sitting := _perched_count(flock)
	if sitting == 0:
		_fail("FAIL no bird started on a perch, so nothing can be walked up to")
	print("flock: %d birds, %d of them already sitting" % [flock.bird_live_count(), sitting])


## There has to be something to look at. A flock of empty Node3Ds behaves perfectly and is
## invisible, which is how a bird system passes every other check here and ships with no birds.
func _check_model_is_bird_shaped(flock: BirdDirector) -> void:
	var bird: BirdActor = flock._birds[0]
	var meshes := _mesh_children(bird)
	if meshes.size() < 5:
		_fail("FAIL bird is %d mesh parts — body, head, beak, tail and two wings expected" % meshes.size())
		return
	var box := AABB(meshes[0].global_position, Vector3.ZERO)
	for mesh in meshes:
		if mesh.mesh == null:
			_fail("FAIL %s has no mesh resource" % mesh.name)
			return
		box = box.merge(mesh.global_transform * mesh.mesh.get_aabb())
	## Sparrow to crow: anything outside this is not a bird, it is a bug in the scale chain.
	if box.size.z < 0.15 or box.size.z > 1.2 or box.size.x < 0.15 or box.size.x > 1.5:
		_fail("FAIL bird measures %s, which is not a bird" % str(box.size))
		return
	## Wings have to move, or the flight animation is a static cross.
	var before := flock._birds[0]._wing_l.rotation.z
	flock._birds[0].fly_to(bird.global_position + Vector3(20.0, 5.0, 0.0), Vector3.INF)
	for _step in range(4):
		flock._birds[0].tick(SIM_DT)
	if is_equal_approx(flock._birds[0]._wing_l.rotation.z, before):
		_fail("FAIL wings did not move over four frames of flight")
	print("model: %d parts, %.2f x %.2f x %.2f m, wings beating" % [
		meshes.size(), box.size.x, box.size.y, box.size.z
	])


func _mesh_children(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			out.append(mesh)
		out.append_array(_mesh_children(child))
	return out


## A bird that cruises on rails is not flapping. Sample a short leg and demand both a vertical
## bounce and a sideways drift off the straight line to the target.
func _check_flight_wobbles(flock: BirdDirector) -> void:
	var bird: BirdActor = flock._birds[0]
	var start := Vector3(24.0, flock._deck_y + 14.0, 24.0)
	var goal := start + Vector3(30.0, 0.0, 0.0)
	bird.global_position = start
	bird.fly_to(goal, Vector3.INF)
	## Cancel the take-off climb that `fly_to` puts in the body — it is real path movement and
	## would otherwise be read as flutter.
	bird.velocity = Vector3(bird.cruise_speed, 0.0, 0.0)
	var y_min := start.y
	var y_max := start.y
	var side_peak := 0.0
	var roll_peak := 0.0
	var travelled := 0.0
	var was := start
	## Tick this bird alone. Going through the flock lets the director re-plan it mid-sample,
	## and the real climb toward a new target swamps the flutter we are trying to measure.
	for _step in range(90):
		bird.tick(SIM_DT)
		y_min = minf(y_min, bird.global_position.y)
		y_max = maxf(y_max, bird.global_position.y)
		side_peak = maxf(side_peak, absf(bird.global_position.z - start.z))
		roll_peak = maxf(roll_peak, absf(bird.rotation.z))
		travelled += bird.global_position.distance_to(was)
		was = bird.global_position
	var bounce := y_max - y_min
	if bounce < 0.05 or bounce > 0.35:
		_fail("FAIL flight Y span is %.3f m — wanted a flutter, not rails or a rollercoaster" % bounce)
	if side_peak < 0.04 or side_peak > 0.4:
		_fail("FAIL sideways weave peaked at %.3f m, outside the subtle band" % side_peak)
	## Roll follows the weave; a bird that weaves with a level body looks glued on.
	if roll_peak < 0.01:
		_fail("FAIL bird weaved but never banked (peak roll %.3f)" % roll_peak)
	## The wobble must not become the movement. It used to be folded into `velocity`, where it
	## compounded frame on frame and quietly added several m/s of travel on top of the cruise.
	var ground_speed := travelled / (90.0 * SIM_DT)
	if absf(ground_speed - bird.cruise_speed) > bird.cruise_speed * 0.25:
		_fail(
			"FAIL bird covered ground at %.1f m/s on a %.1f m/s cruise — wobble is moving it"
			% [ground_speed, bird.cruise_speed]
		)
	print("wobble: Y span %.2f m, sideways peak %.2f m, roll peak %.2f rad, %.1f m/s over %.1f m/s cruise" % [
		bounce, side_peak, roll_peak, ground_speed, bird.cruise_speed
	])


## Someone walking up sends the birds around them up, and only those.
func _check_flush_radius(flock: BirdDirector) -> void:
	_land_everything(flock)
	var victim: BirdActor = _first_perched(flock)
	if victim == null:
		_fail("FAIL could not get a bird to sit for the flush check")
		return
	var far_seat := victim.global_position + Vector3(300.0, 0.0, 300.0)
	if flock.flush_near(far_seat, flock.flush_radius_m) != 0:
		_fail("FAIL an actor 400 m away startled the flock")
	if victim.is_flying():
		_fail("FAIL the bird left its perch with nobody near it")
	var walker := victim.global_position + Vector3(flock.flush_radius_m * 0.4, 0.0, 0.0)
	var flushed := flock.flush_near(walker, flock.flush_radius_m)
	if flushed <= 0 or not victim.is_flying():
		_fail("FAIL a bird sat still while an actor walked into its perch")
		return
	if victim.state != BirdActor.State.FLEEING:
		_fail("FAIL startled bird is in state %d, not fleeing" % int(victim.state))
	## It has to leave, not circle the thing that scared it.
	var before := victim.global_position.distance_to(walker)
	for _step in range(60):
		flock.simulate(SIM_DT)
	var after := victim.global_position.distance_to(walker)
	if after <= before + 2.0:
		_fail("FAIL startled bird only got from %.1f m to %.1f m away" % [before, after])
	print("flush: %d birds up, the closest one climbed out to %.0f m" % [flushed, after])


## A blast is not a pedestrian: it clears the trees for streets around, not one canopy.
func _check_blast_scatters_wider(flock: BirdDirector) -> void:
	_land_everything(flock)
	var seats := _perched_count(flock)
	if seats < 3:
		_fail("FAIL only %d birds would sit down for the blast check" % seats)
		return
	var centre: BirdActor = _first_perched(flock)
	flock.react_to_destruction(centre.global_position, 200.0)
	var still_sitting := _perched_count(flock)
	if still_sitting != 0:
		_fail("FAIL %d birds sat through a blast that covered the whole tile" % still_sitting)
	print("blast: all %d sitting birds left the trees" % seats)


## The flock has to settle again, or one disturbance empties the district for good.
func _check_startled_birds_land_again(flock: BirdDirector) -> void:
	for _step in range(90 * 30):
		flock.simulate(SIM_DT)
		if _perched_count(flock) > 0:
			break
	var sitting := _perched_count(flock)
	if sitting == 0:
		_fail("FAIL no bird found a perch again within 90 s of being scared off")
		return
	print("settle: %d birds back in the trees" % sitting)


## Birds are not streamed, so one that leaves its tile is drawn over ground that may not be
## loaded. Flight targets are clamped; this checks the bodies actually stay inside them.
func _check_stays_over_the_tile(flock: BirdDirector) -> void:
	var min_xz := Vector2.ZERO
	var max_xz := Vector2(float(SIZE_VOX.x), float(SIZE_VOX.y)) * VOX
	## One cruise leg of slack: a bird eases into a turn rather than pivoting on the boundary.
	var slack := 12.0
	for _step in range(120 * 30):
		flock.simulate(SIM_DT)
		for bird in flock._birds:
			var p := bird.global_position
			if (
				p.x < min_xz.x - slack
				or p.z < min_xz.y - slack
				or p.x > max_xz.x + slack
				or p.z > max_xz.y + slack
			):
				_fail("FAIL %s wandered to %s, off a tile of %s" % [bird.name, str(p), str(max_xz)])
				return
			if p.y < flock._deck_y - 1.0:
				_fail("FAIL %s sank to %.1f m, below the street deck" % [bird.name, p.y])
				return
	print("bounds: the flock stayed over its own tile through 120 s of flying")


## Draw distance only, with hysteresis: standing on the boundary must not strobe.
func _check_draw_distance(flock: BirdDirector, cam: Camera3D) -> void:
	flock.render_distance = 60.0
	var bird: BirdActor = flock._birds[0]
	cam.global_position = bird.global_position + Vector3(0.0, 0.0, 4.0)
	flock._refresh_visibility()
	if not bird.visible:
		_fail("FAIL bird culled from 4 m away")
	cam.global_position = bird.global_position + Vector3(0.0, 0.0, 200.0)
	flock._refresh_visibility()
	if bird.visible:
		_fail("FAIL bird still drawn 200 m out, well past its draw distance")
	var flips := 0
	var was := bird.visible
	for step in range(24):
		var side := -1.0 if (step % 2) == 0 else 1.0
		cam.global_position = bird.global_position + Vector3(
			0.0, 0.0, flock.render_distance + side
		)
		flock._refresh_visibility()
		if bird.visible != was:
			flips += 1
			was = bird.visible
	if flips != 1:
		_fail("FAIL bird flipped visibility %d times on the draw boundary, wanted 1" % flips)
	if not bird.visible:
		_fail("FAIL bird never came back on during the edge walk")
	print("draw distance: %d transition over 24 steps straddling the boundary" % flips)


func _check_teardown(flock: BirdDirector) -> void:
	flock.clear_birds()
	if flock.bird_live_count() != 0 or flock.perch_count() != 0:
		_fail(
			"FAIL teardown left %d birds and %d perches behind"
			% [flock.bird_live_count(), flock.perch_count()]
		)
		return
	## An empty flock must be inert rather than an error, because a tile unloads mid-flight.
	flock.simulate(SIM_DT)
	flock.queue_free()
	print("teardown: flock cleared and still safe to tick")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Put every bird straight onto a perch, so a check starts from a known flock.
func _land_everything(flock: BirdDirector) -> void:
	if flock.perch_count() == 0:
		_fail("FAIL cannot land the flock: the scan found nowhere to sit")
		return
	for i in range(flock._birds.size()):
		var bird: BirdActor = flock._birds[i]
		bird.sit_on(flock._perches[i % flock.perch_count()])
		## Long enough that nothing leaves on its own timer while a check is running.
		bird.decide_in = 1000.0


func _perched_count(flock: BirdDirector) -> int:
	var n := 0
	for bird in flock._birds:
		if not bird.is_flying():
			n += 1
	return n


func _first_perched(flock: BirdDirector) -> BirdActor:
	for bird in flock._birds:
		if not bird.is_flying():
			return bird
	return null
