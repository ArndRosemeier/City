## World-level navigation: one NativeNavWorld, the profiles every agent queries with, and
## a budgeted request queue so a path never costs a frame.
##
## Districts stream in and out, so the nav field cannot live on a district: each tile hands
## its baked span field here on load and takes it back out on unload, and the Rust world
## stitches whichever borders happen to be loaded. Searching, smoothing and profile
## filtering all happen in Rust — this side is a registry and a scheduler.
##
## It is also where the world's mutation lands: a NavDirtyTracker follows CityRoot's live
## brush and queues sector rebuilds, which the frame pump drains under its own budget.
class_name NavService
extends RefCounted

## Self-preload so the static accessors type-check before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_service.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const NavSolidityScript := preload("res://scripts/city/nav_solidity.gd")
const NavProfileScript := preload("res://scripts/city/nav_profile.gd")
const NavPathResultScript := preload("res://scripts/city/nav_path_result.gd")
const NavDirtyRegionScript := preload("res://scripts/city/nav_dirty_region.gd")
const NavDirtyTrackerScript := preload("res://scripts/city/nav_dirty_tracker.gd")

## Expansions one query may spend before it returns its best effort.
const DEFAULT_BUDGET := 20000
## Microseconds of one frame the queue may spend serving requests.
const DEFAULT_FRAME_BUDGET_USEC := 1500
## Hard cap per frame, so a cheap-query flood cannot fill the budget with scheduling.
const DEFAULT_MAX_PER_FRAME := 8
## Microseconds of one frame the incremental span/portal rebuild may spend.
const DEFAULT_DIRTY_BUDGET_USEC := 2000

signal district_registered(coord: Vector2i)
signal district_unregistered(coord: Vector2i)
## Fired for every served request, in addition to the request's own callback.
signal path_ready(result: NavPathResult)

## One queued query. Held by id so it can be cancelled when its agent dies.
class Request:
	extends RefCounted
	var id: int = 0
	var profile_id: int = -1
	var from_world: Vector3 = Vector3.ZERO
	var to_world: Vector3 = Vector3.ZERO
	var budget: int = 0
	var on_done: Callable = Callable()
	var cancelled: bool = false


## One live dynamic block, mirroring what the nav world was told.
##
## The extension owns the authoritative overlay and reads nothing back out of it, and every
## block in the world is written through `block_column`, so this mirror is a complete answer
## rather than a guess. It expires on `_now` — the value the pump last handed the world —
## because Rust expires against exactly that and not against the live clock.
class Block:
	extends RefCounted
	var expiry: float = 0.0
	var world_y: float = 0.0


## What NativeNavWorld.nearest_surface found, as a value instead of a Dictionary.
class SurfaceHit:
	extends RefCounted
	var found: bool = false
	var position: Vector3 = Vector3.ZERO
	var clearance: int = 0
	var headroom: int = 0
	var water_depth: int = 0


static var _instance: _Self = null

## Tuning, public so a stress scene can widen or starve the queue on purpose.
var frame_budget_usec: int = DEFAULT_FRAME_BUDGET_USEC
var max_queries_per_frame: int = DEFAULT_MAX_PER_FRAME
var default_budget: int = DEFAULT_BUDGET
var dirty_budget_usec: int = DEFAULT_DIRTY_BUDGET_USEC

## The native navigation registry. Null until `ensure_configured` builds it.
var _world: NativeNavWorld = null
var _solidity: NavSolidity = null
var _tables: Dictionary = {}
var _voxel_size: float = 0.0
var _profiles: Dictionary[int, NavProfile] = {}
var _queue: Array[Request] = []
var _by_id: Dictionary[int, Request] = {}
var _next_request_id: int = 1
var _served_last_frame: int = 0
var _pump_connected: bool = false
var _dirty: NavDirtyTracker = null
## Version of the last district registration or removal. Those change portals everywhere,
## so no older path can be trusted.
var _structural_version: int = 0
## Live dynamic blocks by voxel column, mirroring the nav world's own overlay.
var _blocks: Dictionary[Vector2i, Block] = {}
var _blocked_version: int = 0
## The clock the pump last advanced the nav world to. Blocks expire against this and not
## against the live clock, because that is what Rust compares against.
var _now: float = 0.0


## The one navigation world. Cheap until `ensure_configured` builds the native side.
static func instance() -> _Self:
	if _instance == null:
		_instance = _Self.new()
	return _instance


## The world if one was built, without building one. For teardown paths that must not
## resurrect the service on their way out.
static func peek() -> _Self:
	return _instance


## Drop the world and everything registered in it. Tests and world teardown only.
static func reset() -> void:
	if _instance == null:
		return
	_instance._shutdown()
	_instance = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Build the native world, the passability tables and the default profiles. Idempotent;
## the voxel size is world-wide, so a second, different one is a bug rather than a switch.
func ensure_configured(voxel_size: float) -> void:
	if _world != null:
		if not is_equal_approx(voxel_size, _voxel_size):
			push_error(
				"NavService: configured at voxel_size %.4f, refused reconfigure to %.4f"
				% [_voxel_size, voxel_size]
			)
		return
	if voxel_size <= 0.0:
		push_error("NavService.ensure_configured: voxel_size %.4f must be positive" % voxel_size)
		return
	CityProfiler.begin("nav_configure")
	if NavDirtyRegionScript.SECTOR_VOX != DistrictCoord.CELL_SIZE:
		push_error(
			"NavService: nav sector is %d voxels but a planner cell is %d"
			% [NavDirtyRegionScript.SECTOR_VOX, DistrictCoord.CELL_SIZE]
		)
	_voxel_size = voxel_size
	_solidity = NavSolidityScript.build()
	_tables = _solidity.export_tables()
	_world = CityVoxelNativeScript.make_nav_world() as NativeNavWorld
	_world.configure(
		voxel_size,
		_tables["class"],
		_tables["top"],
		_tables["destructible"],
		_tables["climbable"],
		link_params()
	)
	var walk_id := int(_world.link_walk_id())
	if walk_id != NavPathResultScript.LINK_WALK:
		push_error(
			"NavService: LINK_WALK is %d in the extension but %d in NavPathResult"
			% [walk_id, NavPathResultScript.LINK_WALK]
		)
	for profile: NavProfile in NavProfileScript.defaults():
		register_profile(profile)
	_dirty = NavDirtyTrackerScript.new()
	_structural_version = version()
	## Start both clocks on the same reading, so a block written before the first pump lasts
	## the duration it was given instead of expiring on that pump.
	_now = float(Time.get_ticks_msec()) * 0.001
	_world.advance_time(_now)
	_connect_pump()
	CityProfiler.end("nav_configure")


func is_configured() -> bool:
	return _world != null


func voxel_size() -> float:
	return _voxel_size


## The four passability tables, for DistrictBakeJob's `nav_solidity` parameter. Read-only
## on the bake worker — the bake never writes them, so the copy is shared, not duplicated.
func solidity_tables() -> Dictionary:
	if _tables.is_empty():
		push_error("NavService.solidity_tables: call ensure_configured first")
	return _tables


func solidity() -> NavSolidity:
	if _solidity == null:
		push_error("NavService.solidity: call ensure_configured first")
	return _solidity


## Link bake tuning for `nav_link_params`. Empty means the Rust LinkParams defaults, which
## are the ones mirrored from the player's climb rules — one source of truth, so the bake
## and the world can never disagree.
func link_params() -> Dictionary:
	return {}


func register_profile(profile: NavProfile) -> void:
	if _world == null:
		push_error("NavService.register_profile: call ensure_configured first")
		return
	_world.register_profile(profile.id, profile.to_spec())
	if not _world.has_profile(profile.id):
		push_error("NavService: extension rejected profile %d" % profile.id)
		return
	_profiles[profile.id] = profile


func profile(id: int) -> NavProfile:
	if not _profiles.has(id):
		push_error("NavService.profile: %d is not registered" % id)
		return null
	return _profiles[id]


func has_profile(id: int) -> bool:
	return _profiles.has(id)


func profile_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _profiles.keys():
		out.append(id)
	out.sort()
	return out


# ---------------------------------------------------------------------------
# Districts
# ---------------------------------------------------------------------------

## Hand a district's baked span field to the world. Main thread only: the bake runs on a
## worker, the registry does not. The field is moved, so the bake handle is spent after.
func register_district(coord: Vector2i, nav_bake: RefCounted) -> bool:
	if _world == null:
		push_error("NavService.register_district: call ensure_configured first")
		return false
	if nav_bake == null:
		push_error("NavService.register_district: district %s has no bake" % str(coord))
		return false
	var t0 := Time.get_ticks_usec()
	if not _world.insert_bake(coord, nav_bake):
		push_error("NavService.register_district: extension refused district %s" % str(coord))
		return false
	CityProfiler.scope_us("nav_register", Time.get_ticks_usec() - t0)
	CityProfiler.set_counter("nav_districts", district_count())
	## The field knows which voxel rows it was baked from, and a rebuild reads exactly those
	## plus what its link probes reach above them. Learning the band here is what keeps the
	## dirty material copy off the ~220 rows of rock and sky the district also contains.
	var band: Vector2i = _world.rebuild_y_range(coord)
	if band.y < band.x:
		push_error("NavService.register_district: district %s reports no nav Y band" % str(coord))
		return false
	_dirty.set_district_y_band(coord, band)
	_structural_version = version()
	district_registered.emit(coord)
	return true


func unregister_district(coord: Vector2i) -> bool:
	if _world == null:
		return false
	if not _world.remove_district(coord):
		return false
	_dirty.forget_district(coord)
	CityProfiler.set_counter("nav_districts", district_count())
	_structural_version = version()
	district_unregistered.emit(coord)
	return true


func has_district(coord: Vector2i) -> bool:
	if _world == null:
		return false
	return _world.has_district(coord)


func district_count() -> int:
	if _world == null:
		return 0
	return int(_world.district_count())


## {ok, columns, spans, max_spans_per_column, nodes, portals, links, bytes, version}.
func district_stats(coord: Vector2i) -> Dictionary:
	if _world == null:
		push_error("NavService.district_stats: call ensure_configured first")
		return {"ok": false}
	return _world.district_stats(coord)


## Monotonic, bumped by every field change. A path built against an older one may be stale;
## `is_path_stale` answers whether it actually is for a given corridor.
func version() -> int:
	if _world == null:
		return 0
	return int(_world.version())


# ---------------------------------------------------------------------------
# Dynamic updates
# ---------------------------------------------------------------------------

## The dirty-column tracker. It attaches itself to CityRoot's live brush, so nothing has to
## wire the subscription up; tools and tests without a CityRoot call `attach` on it.
func dirty() -> NavDirtyTracker:
	if _dirty == null:
		push_error("NavService.dirty: call ensure_configured first")
	return _dirty


## Rebuild whatever the queue holds, ignoring the frame budget. For a tool, a test, or a
## load that must not hand agents a stale field. Returns the rebuild units handled.
func flush_dirty() -> int:
	if _world == null:
		push_error("NavService.flush_dirty: call ensure_configured first")
		return 0
	return _drain_dirty(0)


## One frame's worth of rebuild, on demand. The pump calls this with `dirty_budget_usec`;
## a test calls it to time a budgeted drain without waiting for a frame to happen.
func drain_dirty(budget_usec: int) -> int:
	if _world == null:
		push_error("NavService.drain_dirty: call ensure_configured first")
		return 0
	if budget_usec < 1:
		push_error("NavService.drain_dirty: %d us is not a budget" % budget_usec)
		return 0
	return _drain_dirty(budget_usec)


## Microseconds the last rebuild spent in each phase: spans, clearance, links, the inbound
## link refresh, components, and the whole-field node index and portals. For the profiler
## and for pinning down what a multi-sector unit actually pays for.
func last_rebuild_timing() -> Dictionary:
	if _world == null:
		push_error("NavService.last_rebuild_timing: call ensure_configured first")
		return {}
	return _world.last_rebuild_timing()


## One frame's worth of rebuild, in units of one sector.
##
## The first unit always runs, so a queue bigger than the budget still makes progress
## instead of growing forever; every unit after it has to fit the *remaining* budget at the
## price of the dearest unit measured so far, because a budget checked only after the fact
## can be blown by exactly one unit and that unit is the frame hitch. Each turn of the loop
## either finishes a unit or drops a region, so the queue strictly shrinks.
func _drain_dirty(budget_usec: int) -> int:
	if _dirty.pending() == 0:
		return 0
	var t0 := Time.get_ticks_usec()
	var handled := 0
	while _dirty.pending() > 0:
		## A district the world does not hold is ordinary: the tile may still be baking, or
		## it may have streamed out while the region sat in the queue. Drop all of it at
		## once rather than a unit per frame of a field that is not there.
		if not has_district(_dirty.peek_next().coord):
			_dirty.drop_next()
			continue
		_rebuild_unit(_dirty.take_unit())
		handled += 1
		if budget_usec > 0 and Time.get_ticks_usec() - t0 + _dirty.worst_unit_usec() > budget_usec:
			break
	CityProfiler.scope_us("nav_dirty", Time.get_ticks_usec() - t0)
	CityProfiler.set_counter("nav_dirty_pending", _dirty.pending())
	CityProfiler.set_counter("nav_dirty_pending_units", _dirty.pending_units())
	CityProfiler.set_counter("nav_dirty_worst_unit_us", _dirty.worst_unit_usec())
	## Dropped regions are places where the field knowingly lags the world, so they belong
	## on the profiler rather than in a silent counter.
	CityProfiler.set_counter(
		"nav_dirty_dropped", _dirty.skipped_unregistered() + _dirty.skipped_unloaded()
	)
	return handled


func _rebuild_unit(unit: NavDirtyRegion) -> void:
	var t0 := Time.get_ticks_usec()
	if not _dirty.fill_materials(unit):
		return
	var sectors := int(
		_world.rebuild_region(unit.coord, unit.box_min, unit.box_size, unit.materials, unit.stride)
	)
	## Whole cost of the unit, material copy included, since that is what the frame pays.
	var usec := Time.get_ticks_usec() - t0
	if sectors <= 0:
		push_error("NavService: %s rebuilt no sector in a registered district" % str(unit))
		unit.drop_materials()
		return
	_dirty.note_rebuilt(unit, sectors, usec, version())


## Has the world changed under this path in a way that can matter to it?
##
## True when a district came or went, or when an edit rebuilt sectors the corridor from
## `from_index` on crosses. A blast on the other side of town leaves a path alone, which is
## the point: agents repath lazily instead of all at once.
func is_path_stale(result: NavPathResult, from_index: int = 0) -> bool:
	if result == null:
		push_error("NavService.is_path_stale: no result")
		return true
	if _world == null:
		push_error("NavService.is_path_stale: call ensure_configured first")
		return true
	if result.nav_version >= version():
		return false
	if result.nav_version < _structural_version:
		return true
	return _dirty.crosses_since(result.nav_version, result.points, from_index, _voxel_size)


## The same question for a corridor an agent has already partly walked, as a Callable of the
## shape `NavAgent.dirty_probe` wants. `setup` hands every agent this, so an agent repaths on
## a version bump only when the edit landed on the corridor it is actually following.
func corridor_probe() -> Callable:
	return corridor_crosses_dirty


## Does `points` cross a sector that changed since `since_version`? A corridor still holding
## the current version cannot be stale, and one older than the last district registration is
## stale whatever the sectors say.
func corridor_crosses_dirty(points: PackedVector3Array, since_version: int) -> bool:
	if _world == null:
		push_error("NavService.corridor_crosses_dirty: call ensure_configured first")
		return true
	if since_version >= version():
		return false
	if since_version < _structural_version:
		return true
	return _dirty.crosses_since(since_version, points, 0, _voxel_size)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Queue a path. Returns the request id; `on_done` takes one NavPathResult, and every
## result is also emitted on `path_ready`. Pass `budget` to override the expansion cap.
func request_path(
	profile_id: int,
	from_world: Vector3,
	to_world: Vector3,
	on_done: Callable = Callable(),
	budget: int = 0
) -> int:
	if _world == null:
		push_error("NavService.request_path: call ensure_configured first")
		return 0
	if not _profiles.has(profile_id):
		push_error("NavService.request_path: profile %d is not registered" % profile_id)
		return 0
	if not on_done.is_null() and not on_done.is_valid():
		push_error("NavService.request_path: callback for profile %d is dead" % profile_id)
		return 0
	var req := Request.new()
	req.id = _next_request_id
	_next_request_id += 1
	req.profile_id = profile_id
	req.from_world = from_world
	req.to_world = to_world
	req.budget = budget if budget > 0 else default_budget
	req.on_done = on_done
	_queue.append(req)
	_by_id[req.id] = req
	return req.id


## Drop a queued request, e.g. because its agent died. False when it already ran.
func cancel_path(request_id: int) -> bool:
	if not _by_id.has(request_id):
		return false
	_by_id[request_id].cancelled = true
	return true


## Path right now, skipping the queue. For tests, spawn placement and one-off tools —
## agents use request_path so the frame cost stays bounded.
func find_path_now(
	profile_id: int, from_world: Vector3, to_world: Vector3, budget: int = 0
) -> NavPathResult:
	if _world == null:
		push_error("NavService.find_path_now: call ensure_configured first")
		return null
	if not _profiles.has(profile_id):
		push_error("NavService.find_path_now: profile %d is not registered" % profile_id)
		return null
	var req := Request.new()
	req.profile_id = profile_id
	req.from_world = from_world
	req.to_world = to_world
	req.budget = budget if budget > 0 else default_budget
	return _serve(req)


## Is there any route at all? Cheaper than a path, for goal selection.
##
## Optimistic on purpose: the answer comes from the permissive high-level graph, so a body
## too wide for the corridor it found can still be reported reachable. A false here is
## final, a true is a candidate — find_path is the authority.
func reachable(profile_id: int, from_world: Vector3, to_world: Vector3) -> bool:
	if _world == null:
		push_error("NavService.reachable: call ensure_configured first")
		return false
	return bool(_world.reachable(profile_id, from_world, to_world))


## Snap a world position onto the nearest surface this body can occupy.
func nearest_surface(profile_id: int, world_pos: Vector3, radius_m: float) -> SurfaceHit:
	var hit := SurfaceHit.new()
	if _world == null:
		push_error("NavService.nearest_surface: call ensure_configured first")
		return hit
	var raw: Dictionary = _world.nearest_surface(profile_id, world_pos, radius_m)
	hit.found = bool(raw["found"])
	hit.position = raw["position"]
	if hit.found:
		hit.clearance = int(raw["clearance"])
		hit.headroom = int(raw["headroom"])
		hit.water_depth = int(raw["water_depth"])
	return hit


## Mark the column under a world position impassable for a while, so one agent's discovery
## steers the others too.
func block_column(world_pos: Vector3, seconds: float) -> void:
	if _world == null:
		push_error("NavService.block_column: call ensure_configured first")
		return
	if seconds <= 0.0:
		push_error("NavService.block_column: %.3f s is not a duration" % seconds)
		return
	_world.block_world_column(world_pos, seconds)
	var block := Block.new()
	block.expiry = _now + seconds
	block.world_y = world_pos.y
	_blocks[column_of(world_pos)] = block
	_blocked_version += 1


## Voxel column a world position falls in — the key the nav world blocks by.
func column_of(world_pos: Vector3) -> Vector2i:
	if _voxel_size <= 0.0:
		push_error("NavService.column_of: call ensure_configured first")
		return Vector2i.ZERO
	return Vector2i(floori(world_pos.x / _voxel_size), floori(world_pos.z / _voxel_size))


## Is the column under this world position blocked right now? Answered from the mirror, on
## the same clock and by the same key the nav world uses, so it agrees with what the search
## is actually refusing to expand into.
func is_column_blocked(world_pos: Vector3) -> bool:
	return is_blocked_column(column_of(world_pos))


func is_blocked_column(column: Vector2i) -> bool:
	_prune_blocks()
	return _blocks.has(column)


## Every live blocked column. The overlay draws from this instead of remembering the blocks
## it happened to write itself.
func blocked_columns() -> Array[Vector2i]:
	_prune_blocks()
	var out: Array[Vector2i] = []
	out.resize(_blocks.size())
	var i := 0
	for column: Vector2i in _blocks:
		out[i] = column
		i += 1
	return out


func blocked_column_count() -> int:
	_prune_blocks()
	return _blocks.size()


## Height the block was reported at, so a drawn block does not slide up a staircase behind
## the agent that wrote it.
func blocked_column_y(column: Vector2i) -> float:
	_prune_blocks()
	if not _blocks.has(column):
		push_error("NavService.blocked_column_y: %s is not blocked" % str(column))
		return 0.0
	return _blocks[column].world_y


## Bumped by every block written and every one that expires, so a consumer can redraw on
## change instead of diffing the set every frame.
func blocked_version() -> int:
	_prune_blocks()
	return _blocked_version


## Drop what the nav world has already dropped. Rust expires against the time the pump last
## handed it, so expiring against `_now` and not the live clock is what keeps the two the
## same set rather than nearly the same set.
func _prune_blocks() -> void:
	if _blocks.is_empty():
		return
	var dead: Array[Vector2i] = []
	for column: Vector2i in _blocks:
		if _blocks[column].expiry <= _now:
			dead.append(column)
	if dead.is_empty():
		return
	for column: Vector2i in dead:
		_blocks.erase(column)
	_blocked_version += 1


func queue_size() -> int:
	return _queue.size()


func served_last_frame() -> int:
	return _served_last_frame


# ---------------------------------------------------------------------------
# Scheduler
# ---------------------------------------------------------------------------

func _connect_pump() -> void:
	if _pump_connected:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("NavService: no SceneTree, the query queue would never be served")
		return
	tree.process_frame.connect(_pump)
	_pump_connected = true


## One frame's worth of queries. The first request always runs, so a single expensive
## path cannot stall the queue behind its own budget.
func _pump() -> void:
	if _world == null:
		return
	_now = float(Time.get_ticks_msec()) * 0.001
	_world.advance_time(_now)
	_prune_blocks()
	_dirty.poll_attachment(Engine.get_main_loop() as SceneTree)
	## Before the queries, so a path asked for this frame is answered against the world as
	## it is now rather than as it was before the blast.
	_drain_dirty(dirty_budget_usec)
	_served_last_frame = 0
	if _queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty():
		var req: Request = _queue.pop_front()
		_by_id.erase(req.id)
		if req.cancelled:
			continue
		_serve(req)
		_served_last_frame += 1
		if _served_last_frame >= max_queries_per_frame:
			break
		if Time.get_ticks_usec() - t0 >= frame_budget_usec:
			break
	CityProfiler.scope_us("nav_queries", Time.get_ticks_usec() - t0)
	CityProfiler.set_counter("nav_queue", _queue.size())


func _serve(req: Request) -> NavPathResult:
	var raw: Dictionary = _world.find_path(
		req.profile_id, req.from_world, req.to_world, req.budget
	)
	var result: NavPathResult = NavPathResultScript.from_query(
		req.id, req.profile_id, req.from_world, req.to_world, version(), raw
	)
	path_ready.emit(result)
	## A dead callback means the agent despawned while it waited, which is ordinary.
	if req.on_done.is_valid():
		req.on_done.call(result)
	return result


func _shutdown() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _pump_connected and tree != null:
		tree.process_frame.disconnect(_pump)
	_pump_connected = false
	if _dirty != null:
		_dirty.detach()
		_dirty = null
	_structural_version = 0
	_blocks.clear()
	_blocked_version = 0
	_now = 0.0
	_queue.clear()
	_by_id.clear()
	_profiles.clear()
	_tables = {}
	_solidity = null
	_voxel_size = 0.0
	_world = null
