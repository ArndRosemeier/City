## Traffic on the voxel navigation stack: the lane annotation layer, and VehicleDirector
## driving cars across a real baked district with it.
##
## Cars are the one consumer that keeps a graph, so this test is in two halves. The first is
## the lane semantics the span field cannot carry, on a stated five-by-five street grid: which
## side of the carriageway runs which way, that a U-turn has no edge to take, that a cul-de-sac
## is not a sink, and that a lane point over a destroyed road goes out of service and comes
## back. None of that needs a voxel.
##
## The second half is a real district: 32 cars sharing one NavService with the rest of the
## world, and the three questions a port has to answer — do they drive, do they stop for a
## pedestrian standing on a crossing, and do they run from a blast.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_car_nav.tscn
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const CarLaneGraphScript := preload("res://scripts/city/car_lane_graph.gd")
const StreetTopologyScript := preload("res://scripts/city/street_topology.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")

const VOXEL_SIZE := 0.5
const WORLD_SEED := 42

## The stated grid: a cross of streets through a five-by-five block of lots, plus one spur that
## dead-ends so the cul-de-sac rule has something to be true of.
const GRID_CELLS := 5
const CROSS_ROW := 2
const CROSS_COL := 2
## A one-cell stub off the westbound street with nothing beyond it. Its only road neighbour is
## the cell below, which is what makes it a dead end rather than a corner.
const SPUR := Vector2i(0, 1)

## Lane direction ids, matching CarLaneGraph.DIRS.
const EAST := 0
const WEST := 1
const SOUTH := 2
const NORTH := 3

## Ground the stated grid sits on, in voxels. Only used to place lane points in space.
const GROUND_THICKNESS := 6

## The real district for the driving pass. "far" quality is ground plus impostors: a full
## street deck without the building shells.
const TILE := Vector2i(0, 0)
const CARS := 32

## Fixed step, so nothing here depends on the headless frame rate.
const SIM_DT := 0.05
const DRIVE_FRAMES := 600
const FLEE_FRAMES := 200
## Wall clock one `_drive` may spend. Two orders of magnitude of slack over what 32 cars
## measure at, and still catches traffic that has stopped being real-time.
const DRIVE_BUDGET_MS := 30000

var _failed := false
var _nav: NavService
var _max_queue: int = 0


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return

	_test_lane_sides()
	_test_no_u_turns()
	_test_cul_de_sac_turns_around()
	_test_legs_split_at_turns()
	_test_destruction_closes_and_reopens_lanes()
	if _failed:
		_quit()
		return

	await _test_real_district_traffic()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Lane semantics, on stated geometry
# ---------------------------------------------------------------------------

## The two directions of one street are two different places. A car joining the eastbound lane
## has to end up on the other side of the centreline from the westbound one, or overtaking
## traffic drives through oncoming.
func _test_lane_sides() -> void:
	var lanes := _stated_lanes()
	var east := _node_at(lanes, Vector2i(1, CROSS_ROW), EAST)
	var west := _node_at(lanes, Vector2i(1, CROSS_ROW), WEST)
	if east < 0 or west < 0:
		_fail("FAIL the middle of a street has no eastbound (%d) or westbound (%d) lane" % [east, west])
		return
	var centre_z := _cell_centre(Vector2i(1, CROSS_ROW)).z
	var offset_m := lanes.lane_offset_vox() * VOXEL_SIZE
	if lanes.positions[east].z <= centre_z or lanes.positions[west].z >= centre_z:
		_fail(
			"FAIL both lanes are on the same side: eastbound z=%.2f westbound z=%.2f centre %.2f"
			% [lanes.positions[east].z, lanes.positions[west].z, centre_z]
		)
		return
	var gap := lanes.positions[east].z - lanes.positions[west].z
	if not is_equal_approx(gap, offset_m * 2.0):
		_fail(
			"FAIL the lanes are %.2f m apart, and half a carriageway each side is %.2f m"
			% [gap, offset_m * 2.0]
		)
		return
	print("lane sides: eastbound and westbound %.2f m apart across the centreline" % gap)


## Anti-U-turn is structural: a lane node carries its direction, and no edge leaves it for the
## reverse. The only exception is a dead end, which would otherwise swallow cars.
func _test_no_u_turns() -> void:
	var lanes := _stated_lanes()
	var reversals := 0
	var sinks := 0
	for node in range(lanes.node_count):
		var exits := lanes.exits_from(node)
		if exits.is_empty():
			sinks += 1
			continue
		if _is_dead_end(lanes, node):
			continue
		for next_node in exits:
			if lanes.direction_id(next_node) == _opposite(lanes.direction_id(node)):
				reversals += 1
	if sinks > 0:
		_fail("FAIL %d lane points have no exit, so a car that reaches one never leaves" % sinks)
		return
	if reversals > 0:
		_fail("FAIL %d lane edges turn a car round in the middle of a street" % reversals)
		return
	print("anti-U-turn: %d lane points, no reversing edge and no sink" % lanes.node_count)


## The spur is a street that goes nowhere. Its only lane point has nothing ahead of it, so the
## graph gives it the turn-around it needs, and that one is allowed to reverse.
func _test_cul_de_sac_turns_around() -> void:
	var lanes := _stated_lanes()
	var node := _node_at(lanes, SPUR, NORTH)
	if node < 0:
		_fail("FAIL the spur at %s has no lane point to drive into" % str(SPUR))
		return
	var exits := lanes.exits_from(node)
	if exits.size() != 1:
		_fail("FAIL the cul-de-sac has %d exits, and a dead end has exactly one" % exits.size())
		return
	if lanes.direction_id(exits[0]) != SOUTH:
		_fail(
			"FAIL the cul-de-sac's only exit runs %d, and the way back out of it is south"
			% lanes.direction_id(exits[0])
		)
		return
	if lanes.cell_of(exits[0]) != Vector2i(SPUR.x, SPUR.y + 1):
		_fail("FAIL the turn-around leaves for %s" % str(lanes.cell_of(exits[0])))
		return
	print("cul-de-sac: the spur at %s turns a car round instead of keeping it" % str(SPUR))


## A drive is handed out one lane point at a time, and where the route turns a corner both ends
## of the turn have to survive: given one leg across a junction the corridor smoother pulls the
## string straight and the car cuts the corner into oncoming traffic.
func _test_legs_split_at_turns() -> void:
	var lanes := _stated_lanes()
	var route := PackedInt32Array([
		_node_at(lanes, Vector2i(1, CROSS_ROW), EAST),
		_node_at(lanes, Vector2i(2, CROSS_ROW), EAST),
		_node_at(lanes, Vector2i(CROSS_COL, 3), SOUTH),
		_node_at(lanes, Vector2i(CROSS_COL, 4), SOUTH),
	])
	for node in route:
		if node < 0:
			_fail("FAIL the stated grid is missing a lane point of the turning route")
			return
	var legs := lanes.route_to_legs(route)
	if legs.size() != 3:
		_fail(
			"FAIL a route that turns once became %d legs, and it should be approach, exit, end"
			% legs.size()
		)
		return
	if legs[0] != route[1] or legs[1] != route[2] or legs[2] != route[3]:
		_fail("FAIL the legs of the turning route are %s" % str(legs))
		return
	var straight := PackedInt32Array([route[0], route[1]])
	if lanes.route_to_legs(straight).size() != 1:
		_fail("FAIL a straight two-point route became more than one leg")
		return
	print("legs: a turn is two legs and a straight run is one")


## Destroying a road has to reach the lanes, because the span field will happily route a car
## round a crater while the lane graph goes on insisting there is a carriageway over it.
func _test_destruction_closes_and_reopens_lanes() -> void:
	var lanes := _stated_lanes()
	var node := _node_at(lanes, Vector2i(1, CROSS_ROW), EAST)
	if node < 0:
		_fail("FAIL the stated grid has no eastbound lane point to close")
		return
	var open_before := lanes.open_node_count()
	var version_before := lanes.version()
	lanes.close_node(node)
	if lanes.is_open(node):
		_fail("FAIL a closed lane point is still open")
		return
	if lanes.open_node_count() != open_before - 1:
		_fail(
			"FAIL closing one lane point took %d out of service"
			% (open_before - lanes.open_node_count())
		)
		return
	if lanes.version() <= version_before:
		_fail("FAIL a closure did not bump the version, so cars routed over it never re-plan")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _try in range(20):
		var from_node := lanes.random_node(rng)
		if lanes.plan_trip(from_node, 10.0, 400.0, rng).has(node):
			_fail("FAIL a drive was planned through a lane point that is out of service")
			return
	if lanes.nearest_node(lanes.positions[node]) == node:
		_fail("FAIL a closed lane point is still the nearest one to itself")
		return

	## A rebuilt street has to come back, and nothing else would ever re-test it.
	var at := lanes.positions[node]
	var reach := Vector3(1.0, 0.0, 1.0)
	if lanes.invalidate_box(at - reach, at + reach) <= 0:
		_fail("FAIL invalidating the region around a lane point touched nothing")
		return
	if not lanes.is_open(node):
		_fail("FAIL a lane point over a repaired road did not come back into service")
		return

	## And a closure nobody invalidates expires by itself.
	lanes.close_node(node)
	lanes.advance(CarLaneGraph.CLOSED_SEC + 1.0)
	if not lanes.is_open(node):
		_fail("FAIL a closure outlived its own expiry")
		return
	print("destruction: lane points close, stay off every route, and come back")


# ---------------------------------------------------------------------------
# Traffic on a real district
# ---------------------------------------------------------------------------

func _test_real_district_traffic() -> void:
	var t0 := Time.get_ticks_msec()
	var bake: Dictionary = DistrictBakeJobScript.bake({
		"coord": TILE,
		"world_seed": WORLD_SEED,
		"quality": DistrictBakeJobScript.QUALITY_FAR,
		"bake_nav": true,
		"nav_solidity": _nav.solidity_tables(),
		"nav_link_params": _nav.link_params(),
	})
	if not bool(bake.get("ok", false)):
		_fail("FAIL real bake: %s" % str(bake.get("error", "?")))
		return
	var nav_bake := bake["nav_bake"] as RefCounted
	if nav_bake == null:
		_fail("FAIL the real bake returned no nav field")
		return
	if not _nav.register_district(TILE, nav_bake):
		_fail("FAIL NavService refused the real district")
		return
	var planner := bake["planner"] as DistrictPlanner
	if planner == null:
		_fail("FAIL the real bake returned no planner to read the street layout from")
		return
	var ground_thickness := int(bake.get("ground_thickness", GROUND_THICKNESS))
	var topology: StreetTopology = StreetTopologyScript.new()
	topology.build(
		planner,
		DistrictCoord.CELL_SIZE,
		VOXEL_SIZE,
		ground_thickness,
		DistrictCoord.origin_vox(TILE)
	)
	if not topology.is_ready():
		_fail("FAIL the real district produced no street topology")
		return
	print(
		"real district %s: bake=%d ms lanes=%d edges=%d crossings=%d"
		% [
			str(TILE),
			Time.get_ticks_msec() - t0,
			topology.lanes.node_count,
			topology.lanes.edge_count,
			topology.sidewalks.crossings.size(),
		]
	)

	var centre := DistrictCoord.origin_world(TILE, VOXEL_SIZE) + Vector3(
		float(planner.cells_x) * float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE * 0.5,
		float(ground_thickness + 1) * VOXEL_SIZE + 1.7,
		float(planner.cells_z) * float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE * 0.5
	)
	var camera := _make_camera(centre)
	var traffic := _make_traffic(camera)
	traffic.setup(topology, camera, 31)
	if traffic.vehicle_live_count() != CARS:
		_fail("FAIL %d of %d cars spawned" % [traffic.vehicle_live_count(), CARS])
		return
	for i in range(traffic.vehicle_live_count()):
		if traffic.agent_at(i).global_position == Vector3.INF:
			_fail("FAIL car %d spawned nowhere" % i)
			return

	NavAgent.reset_events()
	var origins := _positions(traffic)
	var frames := await _drive(traffic, DRIVE_FRAMES)
	if _failed:
		return
	var elapsed := float(frames) * SIM_DT
	var provider := traffic.goal_provider()
	var tiers := traffic.count_lod_tiers()
	var driven := _driven_count(traffic, origins, 5.0)

	if provider.goals_issued() <= 0:
		_fail("FAIL the traffic asked for no goals at all in %.0f s" % elapsed)
		return
	if driven < CARS * 7 / 10:
		_fail(
			"FAIL only %d of %d cars covered 5 m in %.0f s (%s)"
			% [driven, CARS, elapsed, provider.describe_load()]
		)
		return
	if provider.stranded() > CARS / 4:
		_fail(
			"FAIL %d of %d cars had nowhere to drive from where they stood"
			% [provider.stranded(), CARS]
		)
		return
	## Some closures are the point — a "far" district's carriageway is not perfectly continuous
	## under every lane point. A flood of them means the lane geometry and the span field
	## disagree about where the road is, which no amount of driving will fix.
	if provider.lane_closures() > topology.lanes.node_count / 4:
		_fail(
			"FAIL %d of %d lane points had no car-sized span under them"
			% [provider.lane_closures(), topology.lanes.node_count]
		)
		return
	var trapped := NavAgent.trapped_events()
	if trapped > 0:
		_fail("FAIL %d cars were entombed on an open street deck" % trapped)
		return
	if _max_queue > 64:
		_fail("FAIL %d queries were queued at once by %d cars" % [_max_queue, CARS])
		return
	print(
		"traffic: %d cars over %.0f s tiers near=%d mid=%d far=%d drove=%d deepest queue %d %s"
		% [CARS, elapsed, tiers.x, tiers.y, tiers.z, driven, _max_queue, provider.describe_load()]
	)

	await _test_yields_to_a_pedestrian(traffic, topology)
	if _failed:
		return
	_test_a_held_car_stands_still(traffic)
	if _failed:
		return
	await _test_panic(traffic, camera)
	if _failed:
		return
	_teardown(traffic, camera)
	if not _nav.unregister_district(TILE):
		_fail("FAIL could not unregister the real district")


## A pedestrian standing on a crossing stops the cars coming at it, and only those: yielding is
## a car-by-car question about what is in front of that car, not a district-wide handbrake.
##
## The stated part is one car placed on the approach to a crossing a ped is standing on, since
## waiting for live traffic to drive into a junction on the frame the test looks is not a test.
## The district-wide part is then the consistency check: every other car agrees with the
## crossing about whether it should be waiting.
func _test_yields_to_a_pedestrian(
	traffic: VehicleDirector, topology: StreetTopology
) -> void:
	var pavement := topology.sidewalks
	var pick := _nearest_crossing_to_a_car(traffic, pavement)
	if pick < 0:
		_fail("FAIL the district has no crossing to step onto")
		return
	var crossing: SidewalkMap.Crossing = pavement.crossings[pick]
	var approach := crossing.center - Vector3(crossing.radius + 1.0, 0.0, 0.0)
	if pavement.yielding_for_car(approach, crossing.center):
		_fail("FAIL a car is waiting at a crossing nobody is standing on")
		return

	var walker := Node3D.new()
	walker.name = "Jaywalker"
	add_child(walker)
	walker.global_position = crossing.center
	pavement.refresh_occupancy([walker])
	if pavement.occupied_crossing_count() != 1:
		_fail(
			"FAIL one ped on a crossing occupied %d of them"
			% pavement.occupied_crossing_count()
		)
		walker.queue_free()
		return
	if not pavement.yielding_for_car(approach, crossing.center):
		_fail("FAIL a car driving straight at an occupied crossing is not held")
		walker.queue_free()
		return
	var away := crossing.center + Vector3(60.0, 0.0, 0.0)
	if pavement.yielding_for_car(away, away + Vector3(5.0, 0.0, 0.0)):
		_fail("FAIL a car 60 m away is held by a crossing it is nowhere near")
		walker.queue_free()
		return

	## No crowd is bound, so the director leaves the occupancy exactly as it was set here.
	traffic.simulate(SIM_DT)
	var held := 0
	var wrong := 0
	for i in range(traffic.vehicle_live_count()):
		var car := traffic.agent_at(i)
		var ahead := car.motor.next_point()
		var should_stop := (
			ahead != Vector3.INF
			and pavement.yielding_for_car(car.global_position, ahead)
		)
		if car.motor.stopped != should_stop:
			wrong += 1
		elif should_stop:
			held += 1
	if wrong > 0:
		_fail(
			"FAIL %d cars disagree with the crossing about whether they should be waiting"
			% wrong
		)
		walker.queue_free()
		return

	walker.queue_free()
	pavement.refresh_occupancy([])
	if pavement.yielding_for_car(approach, crossing.center):
		_fail("FAIL the crossing still holds traffic after the ped stepped off it")
		return
	traffic.simulate(SIM_DT)
	for i in range(traffic.vehicle_live_count()):
		if traffic.agent_at(i).motor.stopped:
			_fail("FAIL car %d is still waiting for a ped that has gone" % i)
			return
	print(
		"yielding: crossing %d holds a car on its approach and nothing 60 m away, %d live cars"
		% [pick, held]
		+ " held, all released after"
	)


## A held car has to actually stand still, and keep its place on the corridor while it does.
## Yielding that dropped the corridor would re-plan the whole drive every time a pedestrian
## steps off a kerb, which is why `stopped` lives on the motor and not in the driver.
func _test_a_held_car_stands_still(traffic: VehicleDirector) -> void:
	var car: VehicleAgent = null
	for i in range(traffic.vehicle_live_count()):
		var cand := traffic.agent_at(i)
		if cand.nav.has_corridor() and cand.motor.next_point() != Vector3.INF:
			car = cand
			break
	if car == null:
		_fail("FAIL not one of %d cars is following a corridor" % traffic.vehicle_live_count())
		return
	var before := car.global_position
	var remaining := car.motor.remaining_m()
	car.motor.stopped = true
	for _tick in range(10):
		car.motor.advance(SIM_DT)
	if not car.global_position.is_equal_approx(before):
		_fail("FAIL a held car drove %.2f m" % before.distance_to(car.global_position))
		return
	if not is_equal_approx(car.motor.remaining_m(), remaining):
		_fail(
			"FAIL a held car's corridor went from %.2f m to %.2f m left"
			% [remaining, car.motor.remaining_m()]
		)
		return
	car.motor.stopped = false
	for _tick in range(10):
		car.motor.advance(SIM_DT)
	if car.global_position.is_equal_approx(before):
		_fail("FAIL a released car stayed where it was held")
		return
	print(
		"held car: %.2f m of corridor kept while stopped, %.2f m driven once released"
		% [remaining, before.distance_to(car.global_position)]
	)


## A blast makes the cars around it floor it, and the lanes over the damage go back up for
## re-testing rather than staying closed on the strength of an old failure.
func _test_panic(traffic: VehicleDirector, camera: Camera3D) -> void:
	var threat := camera.global_position
	var before: Dictionary[int, float] = {}
	for i in range(traffic.vehicle_live_count()):
		var car := traffic.agent_at(i)
		if car.wrecked:
			continue
		var d := _flat_distance(car.global_position, threat)
		if d <= traffic.flee_radius_m:
			before[i] = d
	if before.is_empty():
		_fail("FAIL no car stood within %.0f m of the camera to scare" % traffic.flee_radius_m)
		return
	traffic.react_to_destruction(threat, traffic.flee_radius_m)
	var scared := 0
	for i: int in before.keys():
		if traffic.agent_at(i).fleeing:
			scared += 1
	if scared != before.size():
		_fail("FAIL %d of %d cars in the blast radius panicked" % [scared, before.size()])
		return
	await _drive(traffic, FLEE_FRAMES)
	if _failed:
		return
	var ran := 0
	for i: int in before.keys():
		var car := traffic.agent_at(i)
		if _flat_distance(car.global_position, threat) > float(before[i]) + 5.0:
			ran += 1
	if ran < before.size() / 2:
		_fail(
			"FAIL %d of %d scared cars got 5 m further from the blast in %.0f s"
			% [ran, before.size(), float(FLEE_FRAMES) * SIM_DT]
		)
		return
	print("panic: %d cars scared, %d put distance between themselves and the blast" % [scared, ran])


# ---------------------------------------------------------------------------
# The stated grid
# ---------------------------------------------------------------------------

## A five-by-five block of lots with one street each way through the middle, and a spur off the
## crossroads that dead-ends. Painted rather than generated: the point of this half of the test
## is that the layout is stated, so a lane rule that breaks says which rule it was.
func _stated_planner() -> DistrictPlanner:
	var planner := DistrictPlanner.new()
	planner.cell_size = DistrictCoord.CELL_SIZE
	planner.cells_x = GRID_CELLS
	planner.cells_z = GRID_CELLS
	planner.grid = []
	for cz in range(GRID_CELLS):
		var row: Array = []
		row.resize(GRID_CELLS)
		row.fill(LandUse.LOT)
		planner.grid.append(row)
	for i in range(GRID_CELLS):
		planner.grid[CROSS_ROW][i] = LandUse.ROAD
		planner.grid[i][CROSS_COL] = LandUse.ROAD
	planner.grid[SPUR.y][SPUR.x] = LandUse.ROAD
	return planner


func _stated_lanes() -> CarLaneGraph:
	var lanes: CarLaneGraph = CarLaneGraphScript.new()
	lanes.build(
		_stated_planner(),
		DistrictCoord.CELL_SIZE,
		VOXEL_SIZE,
		Vector3i.ZERO,
		float(GROUND_THICKNESS + 1) * VOXEL_SIZE
	)
	if lanes.is_empty():
		_fail("FAIL the stated grid produced no lanes at all")
	return lanes


func _node_at(lanes: CarLaneGraph, cell: Vector2i, direction: int) -> int:
	for node in range(lanes.node_count):
		if lanes.cell_of(node) == cell and lanes.direction_id(node) == direction:
			return node
	return -1


## A lane point with nothing ahead of it, which is what earns a turn-around.
func _is_dead_end(lanes: CarLaneGraph, node: int) -> bool:
	var exits := lanes.exits_from(node)
	if exits.size() != 1:
		return false
	return lanes.direction_id(exits[0]) == _opposite(lanes.direction_id(node))


func _cell_centre(cell: Vector2i) -> Vector3:
	var half := float(DistrictCoord.CELL_SIZE) * 0.5
	return Vector3(
		(float(cell.x * DistrictCoord.CELL_SIZE) + half) * VOXEL_SIZE,
		0.0,
		(float(cell.y * DistrictCoord.CELL_SIZE) + half) * VOXEL_SIZE
	)


static func _opposite(direction: int) -> int:
	match direction:
		EAST:
			return WEST
		WEST:
			return EAST
		SOUTH:
			return NORTH
		_:
			return SOUTH


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

## One fixed step per process frame, so NavService's queue is pumped exactly once between
## ticks the way it is in a running game.
##
## The frame count bounds the simulated time and the wall clock bounds the real time: traffic
## that has gone from one millisecond a frame to hundreds is the same defect as traffic that
## never returns, and only the second of those a test runner can kill.
func _drive(traffic: VehicleDirector, frames: int) -> int:
	var deadline := Time.get_ticks_msec() + DRIVE_BUDGET_MS
	for frame in range(frames):
		await get_tree().process_frame
		traffic.simulate(SIM_DT)
		if Time.get_ticks_msec() > deadline:
			_fail(
				"FAIL %d of %d traffic frames took over %.0f s of wall clock for %.0f s of"
				% [frame + 1, frames, DRIVE_BUDGET_MS / 1000.0, float(frames) * SIM_DT]
				+ " simulated time, so the traffic is grinding rather than driving"
			)
			return frame + 1
		_max_queue = maxi(_max_queue, _nav.queue_size())
	return frames


func _make_camera(at: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "Observer"
	add_child(camera)
	camera.global_position = at
	return camera


## Visuals are off: a headless run cannot build the catalog's meshes, and none of this is about
## the render LOD. The nav tiers are the director's own and unaffected by the render distance.
func _make_traffic(camera: Camera3D) -> VehicleDirector:
	var traffic: VehicleDirector = VehicleDirectorScript.new()
	traffic.name = "Traffic"
	traffic.vehicle_count = CARS
	traffic.render_distance = 0.05
	add_child(traffic)
	traffic.set_physics_process(false)
	if camera == null:
		_fail("FAIL traffic needs an observer")
	return traffic


func _teardown(traffic: VehicleDirector, camera: Camera3D) -> void:
	traffic.clear_vehicles()
	traffic.queue_free()
	camera.queue_free()


func _positions(traffic: VehicleDirector) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(traffic.vehicle_live_count()):
		out.append(traffic.agent_at(i).global_position)
	return out


func _driven_count(
	traffic: VehicleDirector, origins: PackedVector3Array, least_m: float
) -> int:
	var moved := 0
	for i in range(traffic.vehicle_live_count()):
		if _flat_distance(traffic.agent_at(i).global_position, origins[i]) >= least_m:
			moved += 1
	return moved


## The crossing with a car nearest to it, so the yield test scares somebody rather than
## stepping onto paint at the other end of the district.
func _nearest_crossing_to_a_car(traffic: VehicleDirector, pavement: SidewalkMap) -> int:
	var best := -1
	var best_d := INF
	for id in range(pavement.crossings.size()):
		var at: Vector3 = pavement.crossings[id].center
		for i in range(traffic.vehicle_live_count()):
			var d := _flat_distance(traffic.agent_at(i).global_position, at)
			if d >= best_d:
				continue
			best_d = d
			best = id
	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
