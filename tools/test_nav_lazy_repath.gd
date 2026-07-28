## What the lazy-repath hook is worth: a crowd walking a live district while one corner of it
## is repainted, measured once with `NavAgent.dirty_probe` wired to NavService's dirty-sector
## query and once with the hook cleared.
##
## Cleared is the behaviour the agent shipped with — no probe means every nav_version bump
## stales every corridor — so the two passes are the before and after of the same run. The
## churn is a surface repaint rather than a hole: it rebuilds sectors and bumps the version
## exactly like a blast, without changing where anybody can walk, so the two passes differ in
## the hook and in nothing else.
##
## This node joins the `city_root` group and answers `voxel_brush()`, which is how NavDirtyTracker
## finds the live brush.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_nav_lazy_repath.tscn
extends Node

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
## A district coordinate no other nav test bakes.
const DISTRICT := Vector2i(5, 5)
const FIELD_Y_MAX := 47
## Six sectors square: 84 m of deck, so a corridor crosses a few sectors and most of the field
## is somewhere a given agent is not walking.
const FIELD_VOX := 168
const SECTOR_VOX := 28

## Peds, and where they walk. Bare Node3D bodies on the mid tier: this measures repaths, and a
## capsule sweep per agent would only make the frames dearer.
const AGENTS := 120
const OBSERVER_OFFSET_M := 40.0
const SIM_DT := 0.05
const FRAMES := 400
## Frames between repaints. Ten is far more churn than a game produces and makes the two passes
## differ by hundreds of repaths rather than by a handful.
const CHURN_EVERY := 10

## The repainted corner, in tile-local voxels: one sector's worth, well away from the middle
## the crowd mostly walks.
const CHURN_X := 6
const CHURN_Z := 6
const CHURN_SPAN := 18

## Wall clock one pass may spend. A pass measures a couple of seconds, so this catches a run
## that has stopped being a measurement instead of letting the runner kill it.
const PASS_BUDGET_MS := 60000

var _origin: Vector3i = Vector3i.ZERO
var _terrain: VoxelTerrain
var _tool: VoxelTool
var _brush: CityBrush
var _nav: NavService
var _bodies: Array[Node3D] = []
var _agents: Array[NavAgent] = []
var _rng := RandomNumberGenerator.new()
var _churn_toggle: bool = false
var _failed := false


## One measured pass.
class Pass:
	extends RefCounted
	var repaths: int = 0
	var skipped: int = 0
	var rebuilds: int = 0
	var walked: int = 0
	var version_bumps: int = 0


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


## The seam CityRoot publishes.
func voxel_brush() -> CityBrush:
	return _brush


func _ready() -> void:
	add_to_group("city_root")
	_origin = DistrictCoord.origin_vox(DISTRICT)
	CityVoxelNativeScript.require_loaded()
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return

	await _make_terrain()
	if _failed:
		_quit()
		return
	_paint_world()
	if not _register_field():
		_quit()
		return
	await get_tree().process_frame
	if not _nav.dirty().is_attached():
		_fail("FAIL the dirty tracker never attached to the published brush")
		_quit()
		return

	## Wired first, because that is the shipping configuration; the cleared pass is the
	## comparison and runs second so a regression shows up as the interesting number moving.
	var wired := await _measure(true)
	if _failed:
		_quit()
		return
	var unwired := await _measure(false)
	if _failed:
		_quit()
		return

	_report(wired, unwired)
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

## One pass: spawn the crowd, walk it, repaint the corner every CHURN_EVERY frames, and count
## what the agents did about it. The crowd is rebuilt from the same seed each time, so both
## passes start from the same positions and the same goals.
func _measure(probe_wired: bool) -> Pass:
	_spawn_crowd(probe_wired)
	NavAgent.reset_events()
	var out := Pass.new()
	var rebuilds_before := _nav.dirty().rebuilds()
	var version_before := _nav.version()
	var origins := _positions()
	var deadline := Time.get_ticks_msec() + PASS_BUDGET_MS
	## The observer is held a fixed distance from each body, so every agent stays on the mid
	## tier: the near tier wants a collider and the far tier repaths on its own clock, and
	## either would measure something other than lazy invalidation.
	var offset := Vector3(0.0, 0.0, OBSERVER_OFFSET_M)
	for frame in range(FRAMES):
		await get_tree().process_frame
		if frame % CHURN_EVERY == 0:
			_churn()
		for i in range(_agents.size()):
			_agents[i].tick(SIM_DT, _bodies[i].global_position + offset)
		if Time.get_ticks_msec() > deadline:
			_fail(
				"FAIL %d of %d frames took over %.0f s of wall clock, so the pass is grinding"
				% [frame + 1, FRAMES, PASS_BUDGET_MS / 1000.0]
			)
			return out
	out.repaths = NavAgent.stale_repaths()
	out.skipped = NavAgent.stale_repaths_skipped()
	out.rebuilds = _nav.dirty().rebuilds() - rebuilds_before
	out.version_bumps = _nav.version() - version_before
	out.walked = _walked_count(origins, 2.0)
	if out.rebuilds <= 0:
		_fail("FAIL the pass rebuilt nothing, so no corridor could go stale")
		return out
	if out.walked < AGENTS / 2:
		_fail("FAIL only %d of %d agents covered 2 m, so the crowd is not walking" % [
			out.walked, AGENTS
		])
		return out
	print(
		"pass probe=%s: repaths=%d skipped=%d rebuilds=%d version bumps=%d walked=%d"
		% [
			"wired" if probe_wired else "cleared",
			out.repaths,
			out.skipped,
			out.rebuilds,
			out.version_bumps,
			out.walked,
		]
	)
	_clear_crowd()
	return out


func _report(wired: Pass, unwired: Pass) -> void:
	if unwired.skipped != 0:
		_fail("FAIL an agent with no dirty probe skipped %d repaths" % unwired.skipped)
		return
	if wired.repaths >= unwired.repaths:
		_fail(
			"FAIL the probe saved nothing: %d repaths wired against %d cleared"
			% [wired.repaths, unwired.repaths]
		)
		return
	if wired.skipped <= 0:
		_fail("FAIL the wired pass never skipped a version bump, so the probe is not answering")
		return
	## The two passes have to be comparable, or the reduction is measuring churn instead of
	## the hook. Rebuild counts within a fifth of each other is the same amount of world change.
	var churn_ratio := float(wired.rebuilds) / float(unwired.rebuilds)
	if churn_ratio < 0.8 or churn_ratio > 1.25:
		_fail(
			"FAIL the passes saw %d and %d rebuilds, too different to compare"
			% [wired.rebuilds, unwired.rebuilds]
		)
		return
	var saved := float(unwired.repaths - wired.repaths) / float(unwired.repaths)
	print(
		(
			"lazy repath: %d agents over %.0f s of churn (%d rebuilds, %d version bumps) repathed"
			+ " %d times with the probe against %d without — %.0f%% fewer, %d bumps proved"
			+ " irrelevant"
		)
		% [
			AGENTS,
			float(FRAMES) * SIM_DT,
			wired.rebuilds,
			wired.version_bumps,
			wired.repaths,
			unwired.repaths,
			saved * 100.0,
			wired.skipped,
		]
	)


# ---------------------------------------------------------------------------
# The crowd
# ---------------------------------------------------------------------------

## Walks from one random deck point to the next, forever. A crowd needs somewhere to go and
## nothing here is about goal selection.
class RoamProvider:
	extends NavGoalProvider
	var nav: NavService = null
	var profile_id: int = NavProfile.Id.PEDESTRIAN
	var min_vox: Vector3 = Vector3.ZERO
	var span_vox: float = 0.0
	var voxel_size: float = 0.5
	var rng := RandomNumberGenerator.new()

	func next_goal(_request: NavGoalRequest) -> NavGoal:
		for _try in range(8):
			var at := Vector3(
				min_vox.x + rng.randf() * span_vox,
				min_vox.y,
				min_vox.z + rng.randf() * span_vox
			) * voxel_size
			var hit := nav.nearest_surface(profile_id, at, 4.0)
			if hit.found:
				return NavGoal.go_to_point(hit.position, 1.5)
		push_error("RoamProvider: eight probes on an open deck and not one found a span")
		return null


func _spawn_crowd(probe_wired: bool) -> void:
	_rng.seed = 4242
	var provider := RoamProvider.new()
	provider.nav = _nav
	provider.min_vox = Vector3(float(_origin.x) + 4.0, 2.0, float(_origin.z) + 4.0)
	provider.span_vox = float(FIELD_VOX) - 8.0
	provider.voxel_size = VOXEL_SIZE
	provider.rng.seed = 909
	for i in range(AGENTS):
		var at := Vector3(
			float(_origin.x) + 4.0 + _rng.randf() * float(FIELD_VOX - 8),
			1.0,
			float(_origin.z) + 4.0 + _rng.randf() * float(FIELD_VOX - 8)
		) * VOXEL_SIZE
		var body := Node3D.new()
		body.name = "Roamer_%d" % i
		add_child(body)
		body.global_position = at
		var agent := NavAgent.new()
		agent.setup(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), provider)
		if not probe_wired:
			agent.dirty_probe = Callable()
		elif agent.dirty_probe.is_null():
			_fail("FAIL setup left the dirty probe unset, so there is nothing to measure")
			return
		_bodies.append(body)
		_agents.append(agent)


func _clear_crowd() -> void:
	for agent: NavAgent in _agents:
		agent.dispose()
	for body: Node3D in _bodies:
		body.queue_free()
	_agents.clear()
	_bodies.clear()


func _positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for body: Node3D in _bodies:
		out.append(body.global_position)
	return out


func _walked_count(origins: PackedVector3Array, least_m: float) -> int:
	var moved := 0
	for i in range(_bodies.size()):
		var a := _bodies[i].global_position
		var b := origins[i]
		if Vector2(a.x - b.x, a.z - b.z).length() >= least_m:
			moved += 1
	return moved


# ---------------------------------------------------------------------------
# Churn
# ---------------------------------------------------------------------------

## Repaint the corner sector's surface, alternating the material so every edit is a real
## change. Passability is untouched: the point is a version bump the crowd mostly does not
## care about, not a route that closes.
func _churn() -> void:
	var material := VoxelMaterial.ASPHALT if _churn_toggle else VoxelMaterial.CONCRETE
	_churn_toggle = not _churn_toggle
	_brush.begin_edit()
	_brush.fill_box(
		Vector3i(CHURN_X, 0, CHURN_Z),
		Vector3i(CHURN_X + CHURN_SPAN, 1, CHURN_Z + CHURN_SPAN),
		material
	)
	_brush.end_edit()


# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------

func _paint_world() -> void:
	var setup: CityBrush = CityBrushScript.new(_tool, _origin) as CityBrush
	setup.begin_edit()
	_paint_into(setup)
	setup.end_edit()
	_brush = CityBrushScript.new(_tool, _origin) as CityBrush


## A flat deck, so the only thing that varies between the passes is the hook.
func _paint_into(brush: CityBrush) -> void:
	brush.fill_box(Vector3i.ZERO, Vector3i(FIELD_VOX, 1, FIELD_VOX), VoxelMaterial.CONCRETE)


func _register_field() -> bool:
	var volume = CityVoxelNativeScript.make_volume()
	var offline: CityBrush = CityBrushScript.new() as CityBrush
	offline.use_offline_volume(volume)
	_paint_into(offline)
	var tables := _nav.solidity_tables()
	var bake = CityVoxelNativeScript.make_nav_bake()
	var ok: bool = bake.bake_from_volume(
		volume,
		_origin,
		FIELD_VOX,
		FIELD_VOX,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the %d square deck" % FIELD_VOX)
		return false
	if not _nav.register_district(DISTRICT, bake as RefCounted):
		_fail("FAIL NavService refused district %s" % str(DISTRICT))
		return false
	var stats := _nav.district_stats(DISTRICT)
	print(
		"field %s: %d columns over %d sectors, spans=%d portals=%d"
		% [
			str(DISTRICT),
			int(stats["columns"]),
			(FIELD_VOX / SECTOR_VOX) * (FIELD_VOX / SECTOR_VOX),
			int(stats["spans"]),
			int(stats["portals"]),
		]
	)
	return true


func _make_terrain() -> void:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	_terrain.bounds = AABB(
		Vector3(float(_origin.x) - 512.0, 0.0, float(_origin.z) - 512.0),
		Vector3(1536.0, 220.0, 1536.0)
	)
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = false
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 500
	anchor.requires_visuals = false
	anchor.requires_collisions = false
	add_child(anchor)
	anchor.global_position = (
		Vector3(float(_origin.x + FIELD_VOX / 2), 8.0, float(_origin.z + FIELD_VOX / 2))
		* VOXEL_SIZE
	)

	var box := AABB(
		Vector3(float(_origin.x) - 32.0, 0.0, float(_origin.z) - 32.0),
		Vector3(float(FIELD_VOX) + 64.0, 220.0, float(FIELD_VOX) + 64.0)
	)
	for _i in range(900):
		await get_tree().process_frame
		if _tool.is_area_editable(box):
			return
	_fail("FAIL the deck never became editable")


func _quit() -> void:
	_clear_crowd()
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
