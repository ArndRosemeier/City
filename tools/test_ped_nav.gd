## Pedestrians on the voxel navigation stack: CrowdDirector, PedGoalProvider and the
## `pedestrian` profile, on stated geometry first and a real baked district second.
##
## The hand-painted street tile is what pins the intent the retired roadmap encoded as graph
## topology: two pavements either side of a carriageway with a marked crossing every 10 m. If
## the profile's surface costs and the pavement anchor table work, a crowd walking between
## anchors stays on the pavement, crosses at the crossings, and never idles in the road. If they
## do not, this tile says so in one number.
##
## The real district then answers the density questions the tile cannot: three LOD tiers at
## once, and whether a crowd keeps the shared NavService queue bounded while it walks.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_ped_nav.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const NavGraphScript := preload("res://scripts/city/nav_graph.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")

const VOXEL_SIZE := 0.5
const WORLD_SEED := 42
## Deep enough that headroom is never the reason a span is missing.
const FIELD_Y_MAX := 47

## The street tile, parked far from every real district and from the other nav tests' tiles.
const STREET_TILE := Vector2i(80, 80)
const STREET_ORIGIN := Vector3i(50000, 0, 50000)
const STREET_SX := 160
const STREET_SZ := 40
## Carriageway band, in tile-local voxel Z. Everything outside it is pavement.
const ROAD_Z0 := 12
const ROAD_Z1 := 28
## Crossings: 3 m of crosswalk every 10 m along the street.
const CROSSWALK_X0 := 7
const CROSSWALK_PITCH := 20
const CROSSWALK_W := 6
## Pavement anchor rows, in tile-local voxel Z.
const WALK_N_Z := 6
const WALK_S_Z := 34
const ANCHOR_PITCH := 8
## Where the crossing-preference pair stands: 1.5 m from the nearest crosswalk edge, which is
## a detour any pedestrian should take rather than pay 2.5x for eight metres of asphalt.
const PAIR_X := 36

## A pedestrian body with no opinion about surfaces, so the crossing detour can be attributed
## to the cost table rather than to the geometry.
const PROFILE_FLAT := 120

## Real district for the density pass. "far" quality is ground plus impostors: a full
## 784 x 560 street deck without the building shells.
const REAL_TILE := Vector2i(0, 0)
## Two and a half times the shipping density of 96 per district, on one director.
const REAL_PEDS := 240
const STREET_PEDS := 120

## Fixed step: the crowd is driven by hand, so the test does not depend on frame timing.
const SIM_DT := 0.05
const STREET_FRAMES := 500
const REAL_FRAMES := 500
const FLEE_FRAMES := 200
## Samples are taken every few frames — one per frame per ped is more data than any assertion
## needs and slows the run down.
const SAMPLE_EVERY := 5
## Wall clock one `_drive` may spend. 500 frames of 240 peds measure well under a second, so
## this is two orders of magnitude of slack and still catches a crowd that has stopped being
## real-time.
const DRIVE_BUDGET_MS := 30000

enum Ground { PAVEMENT, CROSSWALK, CARRIAGEWAY }

## Curb pad sides of a road cell, as StreetNavLayers numbers them. N/S are the pair a crossing
## along X joins, W/E the pair a crossing along Z joins.
const SIDE_N := 0
const SIDE_S := 1
const SIDE_W := 2
const SIDE_E := 3
const SIDE_NORMALS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]
## A crowd spawns in the largest connected part of the layout, so a fragmented one strands it
## on a handful of anchors instead of failing outright. Assert the shape before the density.
const MIN_LARGEST_COMPONENT := 0.8

var _failed := false
var _nav: NavService
var _served: int = 0
var _max_queue: int = 0


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return
	_nav.path_ready.connect(_on_served)
	var flat := NavProfile.pedestrian().duplicate_as(PROFILE_FLAT, "flat-cost pedestrian")
	flat.surface_cost.fill(1.0)
	_nav.register_profile(flat)

	_test_profile_costs()
	if _failed:
		_quit()
		return
	if not _nav.register_district(STREET_TILE, _bake_street()):
		_fail("FAIL NavService refused the street tile")
		_quit()
		return
	_test_corridor_keeps_its_crossing()
	if _failed:
		_quit()
		return
	_test_errand_crosses_at_crossings()
	if _failed:
		_quit()
		return
	await _test_street_crowd()
	if _failed:
		_quit()
		return
	if not _nav.unregister_district(STREET_TILE):
		_fail("FAIL could not unregister the street tile")
		_quit()
		return
	await _test_real_district_crowd()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# The intent, as cost
# ---------------------------------------------------------------------------

## The old ped roadmap held sidewalk nodes and explicit crossing edges, so "stay on the
## pavement, cross at a crossing" was a property of the graph. On the span field it is a
## property of the profile, and this is the shape it has to have.
func _test_profile_costs() -> void:
	var p := NavProfile.pedestrian()
	var road := p.surface_cost[VoxelMaterial.ROAD]
	var asphalt := p.surface_cost[VoxelMaterial.ASPHALT]
	var crosswalk := p.surface_cost[VoxelMaterial.CROSSWALK]
	var pavement := p.surface_cost[VoxelMaterial.CONCRETE]
	if not is_equal_approx(pavement, 1.0):
		_fail("FAIL pavement costs %.2f, so nothing can be cheaper than it" % pavement)
		return
	if crosswalk <= pavement:
		_fail("FAIL a crossing costs %.2f against %.2f of pavement" % [crosswalk, pavement])
		return
	if road <= crosswalk or asphalt <= crosswalk:
		_fail(
			"FAIL carriageway costs %.2f/%.2f and a crossing %.2f, so jaywalking is not dearer"
			% [road, asphalt, crosswalk]
		)
		return
	print(
		"pedestrian costs: pavement %.2f crossing %.2f road %.2f asphalt %.2f"
		% [pavement, crosswalk, road, asphalt]
	)


## What one corridor across the street actually looks like, which is the whole of the pavement
## policy now that PedGoalProvider walks an errand as a single destination.
##
## `NavWorld::neighbours` charges the pedestrian profile 2.5x for asphalt against 1.25x for a
## crossing, so the fine search detours to the paint; `NavWorld::smooth` keeps an intermediate
## point whenever dropping it would raise that cost, so the detour survives string-pulling. The
## flat-cost body is the control: same geometry, no opinion about surfaces, straight across.
##
## Smoothing still has to earn its keep, so the corridor is counted as well as placed: a route
## of one point per cell would be dozens.
func _test_corridor_keeps_its_crossing() -> void:
	var from := _street_world(Vector3i(PAIR_X, 1, WALK_N_Z))
	var to := _street_world(Vector3i(PAIR_X, 1, WALK_S_Z))
	var ped_path := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to)
	var flat_path := _nav.find_path_now(PROFILE_FLAT, from, to)
	if not ped_path.is_usable() or not flat_path.is_usable():
		_fail(
			"FAIL crossing the street is %s for a pedestrian and %s for a flat-cost body"
			% [ped_path.status_name(), flat_path.status_name()]
		)
		return
	var ped_x := _carriageway_crossing_x(ped_path.points)
	var flat_x := _carriageway_crossing_x(flat_path.points)
	if ped_x == INF or flat_x == INF:
		_fail("FAIL a corridor across the street never crossed the carriageway centre")
		return
	if _ground_at(_road_mid_at(ped_x)) != Ground.CROSSWALK:
		_fail(
			"FAIL a pedestrian corridor crosses the carriageway at x=%.1f m, %.1f m off the paint"
			% [ped_x, absf(ped_x - _nearest_crosswalk_x(ped_x))]
		)
		return
	if _ground_at(_road_mid_at(flat_x)) == Ground.CROSSWALK:
		_fail(
			"FAIL the flat-cost control also crossed on the paint at x=%.1f m, so the detour"
			% flat_x
			+ " cannot be attributed to the cost table"
		)
		return
	if ped_path.points.size() > ped_path.raw_points / 2:
		_fail(
			"FAIL smoothing pulled a %d point search down to only %d"
			% [ped_path.raw_points, ped_path.points.size()]
		)
		return
	print(
		(
			"corridor across the street: pedestrian crosses on the paint at x=%.1f m,"
			+ " %d points from %d searched; flat-cost control crosses bare asphalt at x=%.1f m,"
			+ " %d points from %d"
		)
		% [
			ped_x,
			ped_path.points.size(),
			ped_path.raw_points,
			flat_x,
			flat_path.points.size(),
			flat_path.raw_points,
		]
	)


## The errand a ped gets when its destination is across the street: the near curb pad, the
## carriageway mid, the far curb pad, then the destination. Walked leg by leg, that is the ped
## on the crossing and nowhere else on the road.
##
## Cost-aware smoothing does not make these legs redundant, and this is where that was measured:
## `corridors_off_the_paint` paths each errand's destination directly, the way a ped would if
## the legs were dropped, and counts the corridors that end up on bare carriageway anyway.
## Eight metres of asphalt at 2.5x is worth about five metres of pavement each way, so beyond
## that the search jaywalks on purpose and no smoothing rule will change its mind.
func _test_errand_crosses_at_crossings() -> void:
	var roadmap := _street_roadmap()
	var provider := PedGoalProvider.new()
	provider.walk_goal_min_m = 12.0
	provider.walk_goal_max_m = 55.0
	provider.setup(_nav, NavProfile.Id.PEDESTRIAN, 7)
	if provider.bind_roadmap(roadmap) <= 0:
		_fail("FAIL the street roadmap has no pavement nodes")
		return
	var from := _street_world(Vector3i(PAIR_X, 1, WALK_N_Z))
	var crossed := 0
	var strayed := 0
	var direct := 0
	for _try in range(60):
		var legs := provider.plan_errand(from)
		if legs.is_empty():
			_fail("FAIL an errand from the north pavement planned no legs")
			return
		var dest := legs[legs.size() - 1]
		if dest.z < _street_world(Vector3i(0, 0, ROAD_Z1)).z:
			## Same-side errand: nothing to cross, so nothing to check.
			continue
		crossed += 1
		var at := from
		for leg: Vector3 in legs:
			if not _walk_stays_off_the_carriageway(at, leg):
				strayed += 1
				break
			at = leg
		if _corridor_leaves_the_paint(from, dest):
			direct += 1
	if crossed <= 0:
		_fail("FAIL 60 errands from the north pavement and not one crossed the street")
		return
	if strayed > 0:
		_fail(
			"FAIL %d of %d errands across the street walked bare carriageway"
			% [strayed, crossed]
		)
		return
	if provider.crossings_used() <= 0:
		_fail("FAIL errands crossed the street without routing through a single crossing")
		return
	print(
		"errands: %d of 60 crossed the street, all through a crossing (%d crossings used)"
		% [crossed, provider.crossings_used()]
	)
	print(
		(
			"legs are still worth it: pathed straight to the destination instead, %d of %d"
			+ " corridors cross bare carriageway because the nearest crossing is a longer"
			+ " detour than the asphalt is dear"
		)
		% [direct, crossed]
	)


## What one errand would look like without its crossing legs: one corridor from here to the
## destination, sampled the same way a leg is. True when it walks bare carriageway anywhere.
func _corridor_leaves_the_paint(from: Vector3, to: Vector3) -> bool:
	var path := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to)
	if not path.is_usable():
		_fail("FAIL a corridor straight to an errand destination came back %s" % path.status_name())
		return false
	for i in range(1, path.points.size()):
		if not _walk_stays_off_the_carriageway(path.points[i - 1], path.points[i]):
			return true
	return false


## The straight line between two errand legs is what the corridor smoother will make of it, so
## sampling it is the honest question: does this leg put the ped on bare road?
func _walk_stays_off_the_carriageway(from: Vector3, to: Vector3) -> bool:
	var span := to - from
	var steps := maxi(int(ceil(Vector2(span.x, span.z).length() / (VOXEL_SIZE * 0.5))), 1)
	for i in range(steps + 1):
		var at := from + span * (float(i) / float(steps))
		if _ground_at(at) == Ground.CARRIAGEWAY:
			return false
	return true


# ---------------------------------------------------------------------------
# A crowd on stated geometry
# ---------------------------------------------------------------------------

func _test_street_crowd() -> void:
	var roadmap := _street_roadmap()
	var camera := _make_camera(_street_world(Vector3i(STREET_SX / 2, 4, STREET_SZ / 2)))
	var crowd := _make_crowd(STREET_PEDS, camera)
	crowd.setup(roadmap, camera, 11)
	if crowd.agent_count() != STREET_PEDS:
		_fail("FAIL %d of %d peds spawned" % [crowd.agent_count(), STREET_PEDS])
		return
	var provider := crowd.goal_provider()
	var sidewalk_nodes := 0
	for node in range(roadmap.node_count):
		if not roadmap.is_crossing_node(node):
			sidewalk_nodes += 1
	if provider.pavement_count() != sidewalk_nodes:
		_fail(
			"FAIL %d pavement nodes from %d sidewalk and %d crossing nodes"
			% [provider.pavement_count(), sidewalk_nodes, roadmap.node_count - sidewalk_nodes]
		)
		return
	for i in range(crowd.agent_count()):
		if _ground_at(crowd.agent_at(i).global_position) == Ground.CARRIAGEWAY:
			_fail("FAIL ped %d spawned on the carriageway" % i)
			return

	NavAgent.reset_events()
	var origins := _positions(crowd)
	var samples := {Ground.PAVEMENT: 0, Ground.CROSSWALK: 0, Ground.CARRIAGEWAY: 0}
	var frames := await _drive(crowd, STREET_FRAMES, samples)
	if _failed:
		return

	var walked := _walked_count(crowd, origins, 2.0)
	if walked < STREET_PEDS * 8 / 10:
		_fail(
			"FAIL only %d of %d peds covered 2 m in %.0f s (%s)"
			% [walked, STREET_PEDS, float(frames) * SIM_DT, provider.describe_load()]
		)
		return
	var road_samples := int(samples[Ground.CARRIAGEWAY]) + int(samples[Ground.CROSSWALK])
	var total := road_samples + int(samples[Ground.PAVEMENT])
	if total <= 0:
		_fail("FAIL no ped positions were sampled")
		return
	var pavement_share := float(samples[Ground.PAVEMENT]) / float(total)
	var jaywalk_share := 1.0
	if road_samples > 0:
		jaywalk_share = float(samples[Ground.CARRIAGEWAY]) / float(road_samples)
	if pavement_share < 0.6:
		_fail(
			"FAIL peds spent %.0f%% of their time on the pavement, so the crowd is in the road"
			% (pavement_share * 100.0)
		)
		return
	if jaywalk_share > 0.35:
		_fail(
			"FAIL %.0f%% of the time peds were on the carriageway they were not on a crossing"
			% (jaywalk_share * 100.0)
		)
		return

	## The replacement for `_leave_carriageway_if_needed`: a ped between errands stands on the
	## pavement because that is where its errands end, not because it was teleported to a curb.
	var idle_in_road := 0
	var idle := 0
	for i in range(crowd.agent_count()):
		var ped := crowd.agent_at(i)
		if ped.nav.has_corridor():
			continue
		idle += 1
		if _ground_at(ped.global_position) == Ground.CARRIAGEWAY:
			idle_in_road += 1
	if idle_in_road > 0:
		_fail("FAIL %d of %d idle peds are standing on the carriageway" % [idle_in_road, idle])
		return
	if NavAgent.trapped_events() != 0:
		_fail(
			"FAIL %d peds were entombed on a flat street tile" % NavAgent.trapped_events()
		)
		return
	print(
		(
			"street crowd: %d peds walked %d, pavement %.0f%% of samples, jaywalk %.0f%% of"
			+ " carriageway time, %d idle and none in the road, %s"
		)
		% [
			STREET_PEDS,
			walked,
			pavement_share * 100.0,
			jaywalk_share * 100.0,
			idle,
			provider.describe_load(),
		]
	)
	_teardown(crowd, camera)


# ---------------------------------------------------------------------------
# A crowd on a real district
# ---------------------------------------------------------------------------

func _test_real_district_crowd() -> void:
	var t0 := Time.get_ticks_msec()
	var bake: Dictionary = DistrictBakeJobScript.bake({
		"coord": REAL_TILE,
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
	if not _nav.register_district(REAL_TILE, nav_bake):
		_fail("FAIL NavService refused the real district")
		return
	var planner := bake["planner"] as DistrictPlanner
	if planner == null:
		_fail("FAIL the real bake returned no planner to read the street layout from")
		return
	var ground_y := float(int(bake.get("ground_thickness", 6)) + 1) * VOXEL_SIZE
	var roadmap := _planner_roadmap(planner, ground_y)
	if roadmap.is_empty():
		_fail("FAIL the planner produced no pavement anchors")
		return
	if roadmap.largest_component_ratio() < MIN_LARGEST_COMPONENT:
		_fail(
			(
				"FAIL the largest connected part of the layout holds %.0f%% of its %d nodes,"
				+ " so a crowd spawned in it has almost nowhere to walk"
			)
			% [roadmap.largest_component_ratio() * 100.0, roadmap.node_count]
		)
		return
	print(
		"real district %s: bake=%d ms roadmap nodes=%d edges=%d largest_component=%.2f ground_y=%.2f"
		% [
			str(REAL_TILE),
			Time.get_ticks_msec() - t0,
			roadmap.node_count,
			roadmap.edge_count,
			roadmap.largest_component_ratio(),
			ground_y,
		]
	)

	var centre := DistrictCoord.origin_world(REAL_TILE, VOXEL_SIZE) + Vector3(
		float(planner.cells_x) * float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE * 0.5,
		ground_y + 1.7,
		float(planner.cells_z) * float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE * 0.5
	)
	var camera := _make_camera(centre)
	var crowd := _make_crowd(REAL_PEDS, camera)
	crowd.setup(roadmap, camera, 23)
	if crowd.agent_count() != REAL_PEDS:
		_fail("FAIL %d of %d peds spawned" % [crowd.agent_count(), REAL_PEDS])
		return

	NavAgent.reset_events()
	_served = 0
	_max_queue = 0
	var origins := _positions(crowd)
	var frames := await _drive(crowd, REAL_FRAMES, {})
	if _failed:
		return
	var elapsed := float(frames) * SIM_DT
	var provider := crowd.goal_provider()
	var tiers := crowd.count_lod_tiers()
	var walked := _walked_count(crowd, origins, 2.0)

	if provider.goals_issued() <= 0:
		_fail("FAIL the crowd asked for no goals at all in %.0f s" % elapsed)
		return
	if walked < REAL_PEDS * 7 / 10:
		_fail(
			"FAIL only %d of %d peds covered 2 m in %.0f s (%s)"
			% [walked, REAL_PEDS, elapsed, provider.describe_load()]
		)
		return
	if tiers.x <= 0 or tiers.y <= 0 or tiers.z <= 0:
		_fail(
			"FAIL the crowd used tiers near=%d mid=%d far=%d, so the LOD bands are not all live"
			% [tiers.x, tiers.y, tiers.z]
		)
		return
	if crowd.collider_count() <= 0:
		_fail("FAIL no near-tier ped was ever given a capsule to move with")
		return
	## The queue is shared with undead, cars and the overlay. A crowd that fills it is a crowd
	## that makes everything else wait, which is exactly what the budget exists to prevent.
	if _max_queue > 64:
		_fail("FAIL %d queries were queued at once by %d peds" % [_max_queue, REAL_PEDS])
		return
	var trapped := NavAgent.trapped_events()
	if trapped > REAL_PEDS / 20:
		_fail("FAIL %d of %d peds were entombed on an open street deck" % [trapped, REAL_PEDS])
		return
	print(
		(
			"real crowd: %d peds over %.0f s tiers near=%d mid=%d far=%d colliders=%d walked=%d"
			+ " trapped=%d %s"
		)
		% [
			REAL_PEDS,
			elapsed,
			tiers.x,
			tiers.y,
			tiers.z,
			crowd.collider_count(),
			walked,
			trapped,
			provider.describe_load(),
		]
	)
	print(
		"query volume: %d served in %.0f s = %.1f/s, deepest queue %d, %.3f per ped per second"
		% [
			_served,
			elapsed,
			float(_served) / elapsed,
			_max_queue,
			float(_served) / elapsed / float(REAL_PEDS),
		]
	)

	await _test_panic(crowd, camera)
	if _failed:
		return
	_teardown(crowd, camera)
	if not _nav.unregister_district(REAL_TILE):
		_fail("FAIL could not unregister the real district")


## A blast makes the peds around it run, and the flee goals go out under the same per-frame
## budget as everything else instead of three hundred paths in one tick.
func _test_panic(crowd: CrowdDirector, camera: Camera3D) -> void:
	var threat := camera.global_position
	var before: Dictionary[int, float] = {}
	for i in range(crowd.agent_count()):
		var ped := crowd.agent_at(i)
		if ped.dead:
			continue
		var d := _flat_distance(ped.global_position, threat)
		if d <= crowd.flee_radius_m:
			before[i] = d
	if before.is_empty():
		_fail("FAIL no ped stood within %.0f m of the camera to scare" % crowd.flee_radius_m)
		return
	var served_before := _served
	crowd.react_to_destruction(threat, crowd.flee_radius_m)
	var scared := 0
	for i: int in before.keys():
		if crowd.agent_at(i).fleeing:
			scared += 1
	if scared != before.size():
		_fail("FAIL %d of %d peds in the blast radius panicked" % [scared, before.size()])
		return
	await _drive(crowd, FLEE_FRAMES, {})
	if _failed:
		return
	var ran := 0
	for i: int in before.keys():
		var ped := crowd.agent_at(i)
		if _flat_distance(ped.global_position, threat) > float(before[i]) + 2.0:
			ran += 1
	if ran < before.size() / 2:
		_fail(
			"FAIL %d of %d scared peds got 2 m further from the blast in %.0f s"
			% [ran, before.size(), float(FLEE_FRAMES) * SIM_DT]
		)
		return
	print(
		"panic: %d peds scared, %d put distance between themselves and the blast, %d queries,"
		% [scared, ran, _served - served_before]
		+ " deepest queue %d" % _max_queue
	)


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

func _on_served(_result: NavPathResult) -> void:
	_served += 1


## One fixed step per process frame, so NavService's queue is pumped exactly once between
## ticks, the way it is in a running game.
##
## The frame count bounds the simulated time; the wall clock bounds the real time, because a
## crowd frame that has gone from one millisecond to hundreds is the same defect as one that
## never returns, and only the second of those a test runner can kill. Either way it must be a
## failure with a number on it and not a run nobody watches finish.
func _drive(crowd: CrowdDirector, frames: int, samples: Dictionary) -> int:
	var deadline := Time.get_ticks_msec() + DRIVE_BUDGET_MS
	for frame in range(frames):
		await get_tree().process_frame
		crowd.simulate(SIM_DT)
		if Time.get_ticks_msec() > deadline:
			_fail(
				"FAIL %d of %d crowd frames took over %.0f s of wall clock for %.0f s of"
				% [frame + 1, frames, DRIVE_BUDGET_MS / 1000.0, float(frames) * SIM_DT]
				+ " simulated time, so the crowd is grinding rather than walking"
			)
			return frame + 1
		_max_queue = maxi(_max_queue, _nav.queue_size())
		if samples.is_empty() or frame % SAMPLE_EVERY != 0:
			continue
		for i in range(crowd.agent_count()):
			var ped := crowd.agent_at(i)
			if ped.dead:
				continue
			var ground := _ground_at(ped.global_position)
			samples[ground] = int(samples[ground]) + 1
	return frames


func _make_camera(at: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "Observer"
	add_child(camera)
	camera.global_position = at
	return camera


## Visuals are off: a headless run cannot skin a mesh, and none of this is about the visual
## LOD. The nav tiers are the crowd's own and unaffected by the render distance.
func _make_crowd(count: int, camera: Camera3D) -> CrowdDirector:
	var crowd: CrowdDirector = CrowdDirectorScript.new()
	crowd.name = "Crowd_%d" % count
	crowd.pedestrian_count = count
	crowd.render_distance = 0.1
	add_child(crowd)
	crowd.set_physics_process(false)
	if camera == null:
		_fail("FAIL a crowd needs an observer")
	return crowd


func _teardown(crowd: CrowdDirector, camera: Camera3D) -> void:
	crowd.clear_crowd()
	crowd.queue_free()
	camera.queue_free()


func _positions(crowd: CrowdDirector) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(crowd.agent_count()):
		out.append(crowd.agent_at(i).global_position)
	return out


func _walked_count(crowd: CrowdDirector, origins: PackedVector3Array, least_m: float) -> int:
	var moved := 0
	for i in range(crowd.agent_count()):
		if _flat_distance(crowd.agent_at(i).global_position, origins[i]) >= least_m:
			moved += 1
	return moved


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# The street tile
# ---------------------------------------------------------------------------

## Pavement, carriageway, pavement, with a painted crossing every ten metres.
func _bake_street() -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(STREET_SX, 1, STREET_SZ), VoxelMaterial.CONCRETE)
	volume.fill_box(
		Vector3i(0, 0, ROAD_Z0), Vector3i(STREET_SX, 1, ROAD_Z1), VoxelMaterial.ASPHALT
	)
	var x := CROSSWALK_X0
	while x + CROSSWALK_W <= STREET_SX:
		volume.fill_box(
			Vector3i(x, 0, ROAD_Z0),
			Vector3i(x + CROSSWALK_W, 1, ROAD_Z1),
			VoxelMaterial.CROSSWALK
		)
		x += CROSSWALK_PITCH
	var tables := _nav.solidity_tables()
	var bake = CityVoxelNativeScript.make_nav_bake()
	var ok: bool = bake.bake_from_volume(
		volume,
		STREET_ORIGIN,
		STREET_SX,
		STREET_SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the street tile")
		return null
	return bake as RefCounted


## What StreetNavLayers would hand the crowd for this street: a run of pavement nodes down
## each side, and one crossing per crosswalk linking the two curb pads through a carriageway
## mid — the only edge across the road, exactly as `_make_crossing` builds it.
func _street_roadmap() -> PedRoadMap:
	var graph: NavGraph = NavGraphScript.new()
	var pads: Dictionary[Vector2i, int] = {}
	for z: int in [WALK_N_Z, WALK_S_Z]:
		var prev := -1
		for x in range(STREET_SX):
			var on_crossing := _is_crosswalk_centre(x)
			if not on_crossing and posmod(x - ANCHOR_PITCH / 2, ANCHOR_PITCH) != 0:
				continue
			var node := graph.add_node(_street_world(Vector3i(x, 1, z)))
			if prev >= 0:
				graph.link(prev, node)
			prev = node
			if on_crossing:
				pads[Vector2i(x, z)] = node
	var crossings: Array[int] = []
	for x in range(STREET_SX):
		if not _is_crosswalk_centre(x):
			continue
		var mid := graph.add_node(
			_street_world(Vector3i(x, 1, (ROAD_Z0 + ROAD_Z1) / 2))
		)
		graph.link(pads[Vector2i(x, WALK_N_Z)], mid)
		graph.link(pads[Vector2i(x, WALK_S_Z)], mid)
		crossings.append(mid)
	graph.finalize(VOXEL_SIZE)
	for i in range(crossings.size()):
		graph.set_crossing_id(crossings[i], i)
	var map: PedRoadMap = PedRoadMapScript.new()
	map.bind_graph(graph)
	return map


func _is_crosswalk_centre(vx: int) -> bool:
	return posmod(vx - CROSSWALK_X0 - CROSSWALK_W / 2, CROSSWALK_PITCH) == 0


func _nearest_crosswalk_x(world_x: float) -> float:
	var vx := world_x / VOXEL_SIZE - float(STREET_ORIGIN.x)
	var centre := float(CROSSWALK_X0 + CROSSWALK_W / 2)
	var band := roundf((vx - centre) / float(CROSSWALK_PITCH))
	return (float(STREET_ORIGIN.x) + centre + band * float(CROSSWALK_PITCH) + 0.5) * VOXEL_SIZE


func _road_mid_at(world_x: float) -> Vector3:
	return Vector3(world_x, VOXEL_SIZE, _street_world(
		Vector3i(0, 0, (ROAD_Z0 + ROAD_Z1) / 2)
	).z)


## Where a corridor passes the middle of the carriageway, in world metres. INF when it never
## does, which for a corridor between the two pavements is a bug in the test.
func _carriageway_crossing_x(points: PackedVector3Array) -> float:
	var mid_z := _street_world(Vector3i(0, 0, (ROAD_Z0 + ROAD_Z1) / 2)).z
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		if (a.z - mid_z) * (b.z - mid_z) > 0.0:
			continue
		if is_equal_approx(a.z, b.z):
			return a.x
		return lerpf(a.x, b.x, (mid_z - a.z) / (b.z - a.z))
	return INF


## Pavement, crossing or bare carriageway, from the stated geometry of the street tile.
func _ground_at(world: Vector3) -> Ground:
	var vx := floori(world.x / VOXEL_SIZE) - STREET_ORIGIN.x
	var vz := floori(world.z / VOXEL_SIZE) - STREET_ORIGIN.z
	if vz < ROAD_Z0 or vz >= ROAD_Z1:
		return Ground.PAVEMENT
	var phase := posmod(vx - CROSSWALK_X0, CROSSWALK_PITCH)
	## One voxel of slack either side: a smoothed corridor entering a 3 m crossing at an angle
	## clips its edge, and that is not jaywalking.
	if phase <= CROSSWALK_W:
		return Ground.CROSSWALK
	if phase == CROSSWALK_PITCH - 1:
		return Ground.CROSSWALK
	return Ground.CARRIAGEWAY


func _street_world(vox: Vector3i) -> Vector3:
	return Vector3(
		float(STREET_ORIGIN.x + vox.x) + 0.5,
		float(STREET_ORIGIN.y + vox.y),
		float(STREET_ORIGIN.z + vox.z) + 0.5
	) * VOXEL_SIZE


# ---------------------------------------------------------------------------
# The real district
# ---------------------------------------------------------------------------

## The street layout a real district hands the crowd, built from planner topology exactly the
## way StreetNavLayers builds its ped graph: pads along the run a road cell belongs to, all four
## at an intersection, linked along their runs and around every corner, and crossings — pad,
## carriageway mid, pad — as the only edges over a carriageway. Crossings sit at every
## intersection, plus the generator's own sparse mid-block hash.
##
## Which pads a cell gets is what decides whether the crowd has a district to walk or a
## scrapheap of stubs: keying them on "this edge borders something that is not a road" breaks
## every run where a side street joins, and a graph whose largest component is a twentieth of
## its nodes strands the whole crowd on a handful of anchors.
##
## Built here rather than taken from StreetNavLayers because that needs a live VoxelTool to
## snap node heights, and a headless bake has no terrain. The deck is flat at this quality, so
## one ground height is the right answer for every node.
func _planner_roadmap(planner: DistrictPlanner, ground_y: float) -> PedRoadMap:
	var graph: NavGraph = NavGraphScript.new()
	var origin := DistrictCoord.origin_world(REAL_TILE, VOXEL_SIZE)
	var cell_m := float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE
	var inset := cell_m * 0.5 - 1.5
	var pads: Dictionary[Vector3i, int] = {}
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var centre := origin + Vector3(
				(float(cx) + 0.5) * cell_m, ground_y, (float(cz) + 0.5) * cell_m
			)
			for side: int in _pad_sides(planner, cx, cz):
				var normal := SIDE_NORMALS[side]
				pads[Vector3i(cx, cz, side)] = graph.add_node(
					centre + Vector3(float(normal.x) * inset, 0.0, float(normal.y) * inset)
				)
	if pads.is_empty():
		return PedRoadMapScript.new() as PedRoadMap
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var horiz := _is_run(planner, cx, cz, true)
			var vert := _is_run(planner, cx, cz, false)
			## The two pads flanking a run continue into the next cell of that run.
			if (horiz or vert) and LandUse.is_road(planner.tag_at(cx + 1, cz)):
				_link_pads(graph, pads, Vector3i(cx, cz, SIDE_N), Vector3i(cx + 1, cz, SIDE_N))
				_link_pads(graph, pads, Vector3i(cx, cz, SIDE_S), Vector3i(cx + 1, cz, SIDE_S))
			if (horiz or vert) and LandUse.is_road(planner.tag_at(cx, cz + 1)):
				_link_pads(graph, pads, Vector3i(cx, cz, SIDE_W), Vector3i(cx, cz + 1, SIDE_W))
				_link_pads(graph, pads, Vector3i(cx, cz, SIDE_E), Vector3i(cx, cz + 1, SIDE_E))
			if not (horiz and vert):
				continue
			## An intersection's four pads ring the corner, which is how a ped turns without
			## stepping into the carriageway.
			var ring: Array[int] = [SIDE_N, SIDE_E, SIDE_S, SIDE_W]
			for i in range(ring.size()):
				_link_pads(
					graph,
					pads,
					Vector3i(cx, cz, ring[i]),
					Vector3i(cx, cz, ring[(i + 1) % ring.size()])
				)
	var crossings: Array[int] = []
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var horiz := _is_run(planner, cx, cz, true)
			var vert := _is_run(planner, cx, cz, false)
			var intersection := horiz and vert
			if not intersection and not _has_crosswalk(cx, cz):
				continue
			var centre := origin + Vector3(
				(float(cx) + 0.5) * cell_m, ground_y, (float(cz) + 0.5) * cell_m
			)
			if intersection or horiz:
				_add_crossing(graph, pads, crossings, centre, cx, cz, SIDE_N, SIDE_S)
			if intersection or vert:
				_add_crossing(graph, pads, crossings, centre, cx, cz, SIDE_W, SIDE_E)
	graph.finalize(VOXEL_SIZE)
	for i in range(crossings.size()):
		graph.set_crossing_id(crossings[i], i)
	var map: PedRoadMap = PedRoadMapScript.new()
	map.bind_graph(graph)
	return map


## Which sides of a road cell carry a curb pad: both flanks of the run it belongs to, and all
## four where two runs meet.
func _pad_sides(planner: DistrictPlanner, cx: int, cz: int) -> Array[int]:
	var horiz := _is_run(planner, cx, cz, true)
	var vert := _is_run(planner, cx, cz, false)
	if horiz and vert:
		return [SIDE_N, SIDE_S, SIDE_W, SIDE_E]
	if horiz:
		return [SIDE_N, SIDE_S]
	return [SIDE_W, SIDE_E]


## Does this road cell continue along X (or along Z)?
func _is_run(planner: DistrictPlanner, cx: int, cz: int, along_x: bool) -> bool:
	if along_x:
		return (
			LandUse.is_road(planner.tag_at(cx - 1, cz))
			or LandUse.is_road(planner.tag_at(cx + 1, cz))
		)
	return (
		LandUse.is_road(planner.tag_at(cx, cz - 1))
		or LandUse.is_road(planner.tag_at(cx, cz + 1))
	)


func _link_pads(
	graph: NavGraph, pads: Dictionary[Vector3i, int], a: Vector3i, b: Vector3i
) -> void:
	if not pads.has(a) or not pads.has(b):
		return
	graph.link(pads[a], pads[b])


func _add_crossing(
	graph: NavGraph,
	pads: Dictionary[Vector3i, int],
	crossings: Array[int],
	centre: Vector3,
	cx: int,
	cz: int,
	side_a: int,
	side_b: int
) -> void:
	var a := Vector3i(cx, cz, side_a)
	var b := Vector3i(cx, cz, side_b)
	if not pads.has(a) or not pads.has(b):
		return
	var mid := graph.add_node(centre)
	graph.link(pads[a], mid)
	graph.link(pads[b], mid)
	crossings.append(mid)


## The generator's own sparse mid-block crossing rule, mirrored from StreetNavLayers.
func _has_crosswalk(cx: int, cz: int) -> bool:
	return ((cx * 17 + cz * 31) % 7) == 0


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
