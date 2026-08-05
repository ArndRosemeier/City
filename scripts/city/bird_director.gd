## The birds over one district tile: a small flock that sits on tree canopies, crosses the
## tile between perches, and bursts off whatever it is sitting on the moment an actor walks
## up to it.
##
## Deliberately outside the nav / crowd stack. Birds have no goals, no collision, no health
## and no effect on anything else in the world, so none of that machinery would earn its
## keep here. The whole cost is one perch scan when the tile streams in, then a fixed handful
## of nodes that stop drawing past `render_distance`.
##
## Perches come from a voxel scan rather than the bake, so a flock finds the trees on any
## tile whichever composer planted them, and a canopy that gets blasted away simply stops
## being a place birds land (see `_seat_is_gone`).
class_name BirdDirector
extends Node3D

const BirdActorScript := preload("res://scripts/city/bird_actor.gd")

@export var bird_count: int = 20
## Past this the flock stops drawing. Birds are small: there is nothing to see out here.
@export var render_distance: float = 120.0
## Any actor that comes this close to a sitting bird sends it up.
@export var flush_radius_m: float = 6.5

## Extra range a bird keeps once it is already drawn, so the draw-distance edge cannot chatter.
const DRAW_HYSTERESIS_M := 12.0
## Cadence of the cull + threat pass. Everything else runs per frame.
const TICK_SEC := 0.25
## Columns probed for a landing spot when the tile streams in.
const PERCH_SAMPLES := 384
## How far above the street deck a canopy top can sit, in voxels. Landmark pines go higher
## than this; a bird then lands on the highest whorl inside the band, which is still the tree.
const PERCH_SCAN_VOX := 22
## Stop probing once the flock has this many canopies to choose from.
const TREE_PERCH_TARGET := 40
## Ledges, roofs and pavement are fair perches too, but trees are what birds are for, so
## only this many non-foliage seats are ever kept.
const GROUND_PERCH_MAX := 12
## Cruise band above the street deck.
const CRUISE_ALT_MIN_M := 10.0
const CRUISE_ALT_MAX_M := 28.0
## How long a startled bird stays on the wing before it looks for somewhere new to sit.
const FLEE_SEC := 4.0
## A bird sits this long before it decides to go somewhere else on its own.
const IDLE_MIN_SEC := 7.0
const IDLE_MAX_SEC := 26.0
## Arrival slop, in metres.
const ARRIVE_M := 1.4
## Seats within this of each other are the same tree as far as the flock is concerned.
const PERCH_SPACING_M := 3.0

var _birds: Array[BirdActor] = []
## World points where feet can stand. Tree canopies first, then the few ground seats.
var _perches: PackedVector3Array = PackedVector3Array()
## How many of `_perches` are foliage tops. The rest are the ledge/pavement fallbacks.
var _tree_perch_count: int = 0
var _camera: Camera3D
## Where the flock learns that something walked up. Null in tools and headless tests, where
## nothing ever does — `flush_near` is then the only way in.
var _city: CityRoot = null
## Live voxel reads, for checking a seat is still there before a bird commits to it.
var _brush: CityBrush = null
## World XZ box the flock stays inside: this tile, so nobody flies off over unloaded ground.
var _min_xz: Vector2 = Vector2.ZERO
var _max_xz: Vector2 = Vector2.ZERO
## World Y of the street deck's walking surface.
var _deck_y: float = 3.5
## Voxel pitch of the tile, for turning a seat back into the voxel holding it up.
var _voxel_m: float = 0.5
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
## Set by the cull pass: false when the whole flock is out of draw range.
var _any_drawn: bool = true
## Species this flock draws from, shared by every bird wearing one.
var _coats: Array[BirdActor.Coat] = []


func clear_birds() -> void:
	for bird in _birds:
		if is_instance_valid(bird):
			bird.queue_free()
	_birds.clear()
	_perches = PackedVector3Array()
	_tree_perch_count = 0


func bird_live_count() -> int:
	return _birds.size()


func perch_count() -> int:
	return _perches.size()


func tree_perch_count() -> int:
	return _tree_perch_count


## Bind the query that says where the non-bird actors are. Without it a flock only ever
## reacts to `flush_near` calls (destruction, tools).
func bind_city(city: CityRoot) -> void:
	_city = city


## Find this tile's perches and put a flock on them. `brush` reads world voxel coordinates;
## `size_vox` is the tile's X/Z extent and `ground_y_vox` its street-deck voxel.
func setup(
	brush: CityBrush,
	planner: DistrictPlanner,
	origin_vox: Vector3i,
	size_vox: Vector2i,
	ground_y_vox: int,
	cell_size: int,
	voxel_size: float,
	camera: Camera3D,
	seed_value: int
) -> void:
	clear_birds()
	if brush == null:
		push_error("BirdDirector.setup: no brush to read perches from")
		return
	_brush = brush
	_camera = camera
	_rng.seed = seed_value
	_voxel_m = voxel_size
	_deck_y = float(ground_y_vox + 1) * voxel_size
	_min_xz = Vector2(float(origin_vox.x), float(origin_vox.z)) * voxel_size
	_max_xz = _min_xz + Vector2(float(size_vox.x), float(size_vox.y)) * voxel_size
	_ensure_species()
	_scan_perches(planner, origin_vox, size_vox, ground_y_vox, cell_size, voxel_size)
	_spawn_flock()
	print(
		"BirdDirector: birds=%d perches=%d (trees=%d)"
		% [_birds.size(), _perches.size(), _tree_perch_count]
	)


# ---------------------------------------------------------------------------
# Perches
# ---------------------------------------------------------------------------

## Probe columns for something to stand on. Green cells get most of the samples because
## that is where the trees are; the rest scatter over the tile so a bird can also end up on
## a roof or a kerb across town.
func _scan_perches(
	planner: DistrictPlanner,
	origin_vox: Vector3i,
	size_vox: Vector2i,
	ground_y_vox: int,
	cell_size: int,
	voxel_size: float
) -> void:
	var green := _green_cells(planner)
	var ground_seats := 0
	var trees := PackedVector3Array()
	var ground := PackedVector3Array()
	for _i in range(PERCH_SAMPLES):
		if trees.size() >= TREE_PERCH_TARGET:
			break
		var local := _sample_column(green, size_vox, cell_size)
		var wx := origin_vox.x + local.x
		var wz := origin_vox.z + local.y
		var top := _column_top(wx, wz, ground_y_vox)
		if top.y < 0:
			continue
		var seat := Vector3(
			(float(wx) + 0.5) * voxel_size,
			float(top.y + 1) * voxel_size,
			(float(wz) + 0.5) * voxel_size
		)
		if VoxelMaterial.is_foliage(top.x):
			if not _too_close(trees, seat):
				trees.append(seat)
			continue
		if ground_seats >= GROUND_PERCH_MAX or _too_close(ground, seat):
			continue
		ground.append(seat)
		ground_seats += 1
	_perches = trees
	_tree_perch_count = trees.size()
	_perches.append_array(ground)


## Cells the planner left open to greenery — parks, hillsides, churchyards.
func _green_cells(planner: DistrictPlanner) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if planner == null:
		return out
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if LandUse.is_open_nature(planner.tag_at(cx, cz)):
				out.append(Vector2i(cx, cz))
	return out


## One district-local column to probe. Mostly from greenery, sometimes from anywhere.
func _sample_column(
	green: Array[Vector2i], size_vox: Vector2i, cell_size: int
) -> Vector2i:
	if not green.is_empty() and _rng.randf() < 0.75:
		var cell := green[_rng.randi_range(0, green.size() - 1)]
		return Vector2i(
			clampi(cell.x * cell_size + _rng.randi_range(0, cell_size - 1), 2, size_vox.x - 3),
			clampi(cell.y * cell_size + _rng.randi_range(0, cell_size - 1), 2, size_vox.y - 3)
		)
	return Vector2i(
		_rng.randi_range(2, size_vox.x - 3), _rng.randi_range(2, size_vox.y - 3)
	)


## Highest solid voxel of a column inside the perch band, as (material, y). Scanned downward
## so the first hit is the top, and bounded at the deck so a column of open air still costs
## only the band. y = -1 for a column with nothing to offer.
##
## A column whose band starts solid is refused outright. Without that rule anything taller
## than the band — a landmark pine, a tower — reports its band ceiling as a "top" and birds
## end up sitting buried inside the canopy. A perch is only a perch if the scan saw the open
## air above it.
func _column_top(wx: int, wz: int, ground_y_vox: int) -> Vector2i:
	var y := ground_y_vox + PERCH_SCAN_VOX
	if _brush.get_vox(Vector3i(wx, y, wz)) != VoxelMaterial.AIR:
		return Vector2i(VoxelMaterial.AIR, -1)
	y -= 1
	while y >= ground_y_vox:
		var mat := _brush.get_vox(Vector3i(wx, y, wz))
		if mat != VoxelMaterial.AIR:
			return Vector2i(mat, y)
		y -= 1
	return Vector2i(VoxelMaterial.AIR, -1)


func _too_close(seats: PackedVector3Array, seat: Vector3) -> bool:
	var min_d2 := PERCH_SPACING_M * PERCH_SPACING_M
	for i in range(seats.size()):
		if seats[i].distance_squared_to(seat) < min_d2:
			return true
	return false


## True when the voxel under a seat has been carved away since the scan. Birds check this
## before they commit to a landing, so a blasted canopy quietly stops being a perch.
func _seat_is_gone(seat: Vector3) -> bool:
	if _brush == null:
		return false
	## Half a voxel below the seat is unambiguously the cell holding it up, where the seat
	## height itself sits exactly on a voxel boundary and floors either way.
	var under := Vector3i(
		int(floor(seat.x / _voxel_m)),
		int(floor((seat.y - _voxel_m * 0.5) / _voxel_m)),
		int(floor(seat.z / _voxel_m))
	)
	return _brush.get_vox(under) == VoxelMaterial.AIR


# ---------------------------------------------------------------------------
# Flock
# ---------------------------------------------------------------------------

## Five coats over the one model. Body, wings and beak per species.
func _ensure_species() -> void:
	if _coats.is_empty():
		_coats = BirdActorScript.build_species_coats()


func _spawn_flock() -> void:
	for i in range(bird_count):
		var bird: BirdActor = BirdActorScript.new()
		bird.name = "Bird_%d" % i
		add_child(bird)
		var coat := _coats[_rng.randi_range(0, _coats.size() - 1)]
		## Wrens to crows over the same mesh.
		var size := _rng.randf_range(0.7, 1.55)
		bird.build(coat.body, coat.accent, coat.beak, size)
		## Small birds beat faster and travel a little quicker than the heavy ones.
		bird.cruise_speed = lerpf(13.0, 8.5, clampf((size - 0.7) / 0.85, 0.0, 1.0))
		bird.flee_speed = bird.cruise_speed * 1.7
		_birds.append(bird)
		## Half the flock starts sitting, the rest already crossing the tile.
		if not _perches.is_empty() and (i % 2) == 0:
			bird.sit_on(_perches[_rng.randi_range(0, _perches.size() - 1)])
			bird.decide_in = _rng.randf_range(0.0, IDLE_MAX_SEC)
		else:
			bird.global_position = _wander_point()
			_send_somewhere(bird)


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	simulate(delta)


## One step of the whole flock. Public so a test can drive it at a fixed step instead of at
## whatever rate the frame clock happens to run at.
func simulate(delta: float) -> void:
	if _birds.is_empty():
		return
	_accum += delta
	var slow_pass := _accum >= TICK_SEC
	if slow_pass:
		_accum = 0.0
		CityProfiler.begin("birds_cull")
		_refresh_visibility()
		CityProfiler.end("birds_cull")
		CityProfiler.begin("birds_threat")
		_scan_threats()
		CityProfiler.end("birds_threat")
	CityProfiler.begin("birds")
	for bird in _birds:
		## A bird nobody can see does not need to be anywhere in particular.
		if not bird.visible:
			continue
		bird.tick(delta)
		_advance_plan(bird, delta)
	CityProfiler.end("birds")


## Draw distance only. Frustum culling is the renderer's job — it tests real bounds per
## frame, where a script testing one point makes a bird blink out at the screen edge.
func _refresh_visibility() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam := _camera.global_position
	var show_r2 := render_distance * render_distance
	var hide_r := render_distance + DRAW_HYSTERESIS_M
	var hide_r2 := hide_r * hide_r
	_any_drawn = false
	for bird in _birds:
		var d2 := bird.global_position.distance_squared_to(cam)
		bird.visible = d2 <= (hide_r2 if bird.visible else show_r2)
		if bird.visible:
			_any_drawn = true


## Ask the city where the actors are and startle whoever they are standing on top of.
##
## Skipped entirely for a flock nobody can see. Every loaded tile has one of these, and the
## query walks every pedestrian, car and monster in the world — running that four times a
## second for tiles two districts away buys nothing, because the birds there are not drawn
## and are not being ticked either.
func _scan_threats() -> void:
	if not _any_drawn:
		return
	if _city == null or not is_instance_valid(_city) or _camera == null:
		return
	if not is_instance_valid(_camera):
		return
	var actors := _city.collect_actor_positions(_camera.global_position, render_distance)
	for i in range(actors.size()):
		flush_near(actors[i], flush_radius_m)


## Everything sitting within `radius_m` of `point` goes up. The one door into a scare: the
## proximity pass, blasts and tools all arrive here.
func flush_near(point: Vector3, radius_m: float) -> int:
	var r2 := radius_m * radius_m
	var flushed := 0
	for bird in _birds:
		if bird.state != BirdActor.State.PERCHED:
			continue
		if bird.global_position.distance_squared_to(point) > r2:
			continue
		_startle(bird, point)
		flushed += 1
	return flushed


## Blasts scatter the flock over a wider radius than a passer-by does — that is the whole
## difference between someone walking up and the ground coming apart.
func react_to_destruction(world_pos: Vector3, radius_m: float = 26.0) -> void:
	flush_near(world_pos, radius_m)


func _startle(bird: BirdActor, threat: Vector3) -> void:
	var away := Vector3(bird.global_position.x - threat.x, 0.0, bird.global_position.z - threat.z)
	if away.length_squared() < 0.01:
		away = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	away = away.normalized()
	var run := bird.global_position + away * _rng.randf_range(30.0, 55.0)
	bird.flee_to(
		Vector3(
			clampf(run.x, _min_xz.x, _max_xz.x),
			_deck_y + _rng.randf_range(CRUISE_ALT_MIN_M, CRUISE_ALT_MAX_M),
			clampf(run.z, _min_xz.y, _max_xz.y)
		)
	)
	bird.decide_in = FLEE_SEC


## Run one bird's clock and hand it a new job when the old one is done.
func _advance_plan(bird: BirdActor, delta: float) -> void:
	bird.decide_in -= delta
	match bird.state:
		BirdActor.State.PERCHED:
			if bird.decide_in <= 0.0:
				_send_somewhere(bird)
		BirdActor.State.FLEEING:
			if bird.decide_in <= 0.0:
				_send_somewhere(bird)
		BirdActor.State.FLYING:
			if bird.distance_to_target() > ARRIVE_M:
				return
			if bird.perch.is_finite() and not _seat_is_gone(bird.perch):
				bird.sit_on(bird.perch)
				bird.decide_in = _rng.randf_range(IDLE_MIN_SEC, IDLE_MAX_SEC)
				return
			_send_somewhere(bird)


## Pick the next thing for a bird to do: usually a perch across the tile, sometimes just a
## loop through the air. A bird with nowhere to sit keeps flying.
func _send_somewhere(bird: BirdActor) -> void:
	if _perches.is_empty() or _rng.randf() < 0.25:
		bird.fly_to(_wander_point(), Vector3.INF)
		bird.decide_in = 0.0
		return
	var seat := _pick_perch(bird.global_position)
	## Approach from above: the last leg of the flight ends over the branch, not through it.
	bird.fly_to(seat + Vector3(0.0, 0.35, 0.0), seat)
	bird.decide_in = 0.0


## Prefer trees, and prefer somewhere that is not where the bird already is.
func _pick_perch(from: Vector3) -> Vector3:
	var pool := _tree_perch_count if _tree_perch_count > 0 else _perches.size()
	for _try in range(4):
		var seat := _perches[_rng.randi_range(0, pool - 1)]
		if seat.distance_squared_to(from) > 36.0:
			return seat
	return _perches[_rng.randi_range(0, pool - 1)]


func _wander_point() -> Vector3:
	return Vector3(
		_rng.randf_range(_min_xz.x, _max_xz.x),
		_deck_y + _rng.randf_range(CRUISE_ALT_MIN_M, CRUISE_ALT_MAX_M),
		_rng.randf_range(_min_xz.y, _max_xz.y)
	)
