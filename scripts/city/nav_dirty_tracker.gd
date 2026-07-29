## Turns live voxel edits into budgeted navigation rebuilds.
##
## It hangs off the two write paths that exist — the one live `CityBrush` and the native
## cascade, both publishing `voxels_changed(aabb_vox)` with the same contract — snaps every
## edited region to the sector grid, coalesces the ones that overlap, and reads the fresh
## materials straight out of the live `VoxelTool` when NavService drains the queue. Nothing
## here touches the nav field itself — NavService owns the `NativeNavWorld`, so the rebuild
## call and the version bump live there.
##
## Queueing and paying are deliberately different sizes. A queued *region* is as large as
## coalescing can make it, because merging is what stops a burst of writes costing a rescan
## each; a drained *unit* is one sector, because that is the granularity a frame budget can
## stop at. A blast does not respect the sector grid, so without that division the smallest
## thing a frame could be asked to do was already over budget.
##
## It also keeps a short log of what was rebuilt and at which nav version, which is what
## lets a consumer ask whether *its* corridor went stale instead of repathing the whole
## population every time something explodes on the other side of town.
class_name NavDirtyTracker
extends RefCounted

const NavDirtyRegionScript := preload("res://scripts/city/nav_dirty_region.gd")

## Largest *queued region*, per axis, in sectors. 2x2 sectors is 56x56 columns: enough that
## a blast straddling sector borders, or a burst of writes across them, coalesces into one
## queue entry instead of a swarm of them.
const MAX_REGION_SECTORS := 2
## Sectors one rebuild *unit* may carry, which is what a frame actually pays for.
##
## A region is indivisible only if nothing divides it, and this is the division: the 2x2
## region above measures 2.31 ms to rebuild in one go against a ~2 ms frame budget, while
## one sector measures 0.49-0.65 ms and two 1.04 ms, so a unit of one sector leaves the
## budget room to run two of them and stop. Smaller would only multiply the per-unit costs
## that scale with the whole field rather than with the dirty columns — the node index and
## the portal CSR — for no gain.
const UNIT_SECTORS := 1
## Columns of untouched world copied around a dirty region as context. `rebuild_region`
## rebuilds the sectors its box carries whole and reads the rest: the climb probes and jump
## arcs of the rebuilt sectors reach this far out, and so do the links the neighbouring
## sectors point back in, which the rebuild recomputes rather than leaving them naming spans
## it just deleted. Mirrors `link_reach` in native/city_voxel/src/nav.rs, which is the
## bake's `max_jump_gap`; supplying less makes `rebuild_region` refuse the region loudly.
const MARGIN_VOX := 3
## Finished regions kept for the staleness check. A path older than the oldest entry can no
## longer be proven unaffected, so it counts as stale.
const LOG_CAPACITY := 96
## Slack added around a logged region when testing a corridor against it. One sector covers
## everything a rebuild can change outside its own columns: the neighbours' inward links, and
## the clearance values around the edit, which cannot reach further than the 15 cells they
## saturate at.
const STALE_MARGIN_VOX := NavDirtyRegionScript.SECTOR_VOX

## Sectors one rebuild unit carries. Public so a test can widen it to a whole region on
## purpose and compare a split rebuild against the single-shot one.
var unit_sectors: int = UNIT_SECTORS

var _brush: CityBrush = null
var _terrain: VoxelTerrain = null
## The native cascade, which clears collapsing columns from Rust and publishes the same
## `voxels_changed(aabb_vox)` the brush does. Typed as Node like CityRoot types it: the
## extension owns the class, and this file must still parse without it.
var _cascade: Node = null
## The CityRoot the brush came from, so a regenerated world is noticed.
var _root: Node = null
var _pending: Array[NavDirtyRegion] = []
var _log: Array[NavDirtyRegion] = []
## Versions at or below this can no longer be checked against the log.
var _log_floor_version: int = 0
## Inclusive voxel Y band of each registered district's nav field, as NavService learns it
## from the field itself. The material copy carries this and nothing more.
var _y_band: Dictionary[Vector2i, Vector2i] = {}

var _buffer: VoxelBuffer = null
var _buffer_size: Vector3i = Vector3i.ZERO

var _queued: int = 0
var _coalesced: int = 0
var _rebuilds: int = 0
var _sectors_rebuilt: int = 0
var _skipped_unregistered: int = 0
var _skipped_unloaded: int = 0
var _last_sectors: int = 0
var _last_rebuild_usec: int = 0
var _last_copy_usec: int = 0
var _worst_unit_usec: int = 0


# ---------------------------------------------------------------------------
# Attachment
# ---------------------------------------------------------------------------

## Listen to a brush. Idempotent for the same pair; handing over a different brush moves
## the subscription, which is what `CityRoot._regenerate()` needs since a new terrain means
## a new VoxelTool and a new brush.
func attach(brush: CityBrush, terrain: VoxelTerrain) -> void:
	if brush == null:
		push_error("NavDirtyTracker.attach: no brush")
		return
	if terrain == null:
		push_error("NavDirtyTracker.attach: brush without a terrain, nothing to rescan")
		return
	if brush == _brush and terrain == _terrain:
		return
	_disconnect_brush()
	_brush = brush
	_terrain = terrain
	_brush.voxels_changed.connect(_on_voxels_changed)


## Listen to the native cascade as well. Same signal, same contract, so it lands in the
## same handler. Idempotent for the same node; a regenerated world builds a new one.
func attach_cascade(cascade: Node) -> void:
	if cascade == null:
		push_error("NavDirtyTracker.attach_cascade: no cascade")
		return
	if not cascade.has_signal(&"voxels_changed"):
		push_error(
			"NavDirtyTracker.attach_cascade: %s has no voxels_changed signal" % cascade.get_class()
		)
		return
	if cascade == _cascade:
		return
	_disconnect_cascade()
	_cascade = cascade
	_cascade.connect(&"voxels_changed", _on_voxels_changed)


func detach() -> void:
	_disconnect_brush()
	_disconnect_cascade()
	_root = null


func _disconnect_brush() -> void:
	if _brush != null and _brush.voxels_changed.is_connected(_on_voxels_changed):
		_brush.voxels_changed.disconnect(_on_voxels_changed)
	_brush = null
	_terrain = null


func _disconnect_cascade() -> void:
	if (
		_cascade != null
		and is_instance_valid(_cascade)
		and _cascade.is_connected(&"voxels_changed", _on_voxels_changed)
	):
		_cascade.disconnect(&"voxels_changed", _on_voxels_changed)
	_cascade = null


func is_attached() -> bool:
	return _brush != null


func is_cascade_attached() -> bool:
	return _cascade != null and is_instance_valid(_cascade)


## Find the live brush and the live cascade through the CityRoot group and follow them when
## the world regenerates. No CityRoot means a tool or a test scene, which attaches its own.
func poll_attachment(tree: SceneTree) -> void:
	if tree == null:
		push_error("NavDirtyTracker.poll_attachment: no SceneTree")
		return
	if _root == null or not is_instance_valid(_root):
		_root = tree.get_first_node_in_group(&"city_root")
		if _root == null:
			return
		if not _root.has_method("voxel_brush"):
			push_error("NavDirtyTracker: the city_root group holds a node without voxel_brush()")
			_root = null
			return
	_poll_cascade()
	var brush: CityBrush = _root.call("voxel_brush") as CityBrush
	if brush == null:
		## CityRoot before it built its terrain. Nothing is being edited yet either.
		return
	if brush == _brush:
		return
	attach(brush, _terrain_of(_root))


## CityRoot names the node it builds, and frees it on regenerate, so a stale handle just
## means the cascade has not been rebuilt yet.
func _poll_cascade() -> void:
	if _cascade != null and not is_instance_valid(_cascade):
		_cascade = null
	var cascade: Node = _root.get_node_or_null(^"NativeCascadeDebris")
	if cascade == null or cascade == _cascade:
		return
	attach_cascade(cascade)


func _terrain_of(root: Node) -> VoxelTerrain:
	for child: Node in root.get_children():
		var terrain := child as VoxelTerrain
		if terrain != null:
			return terrain
	push_error("NavDirtyTracker: CityRoot has a brush but no VoxelTerrain to read back")
	return null


# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

## Inclusive minimum, exclusive maximum, world voxel space — the CityBrush contract.
func _on_voxels_changed(aabb_vox: AABB) -> void:
	var min_v := Vector3i(
		floori(aabb_vox.position.x), floori(aabb_vox.position.y), floori(aabb_vox.position.z)
	)
	var end_v := Vector3i(ceili(aabb_vox.end.x), ceili(aabb_vox.end.y), ceili(aabb_vox.end.z))
	if end_v.x <= min_v.x or end_v.z <= min_v.z:
		push_error("NavDirtyTracker: empty edit region %s" % str(aabb_vox))
		return
	add_columns(min_v.x, min_v.z, end_v.x - 1, end_v.z - 1)


## Queue a column rectangle for rebuild, inclusive on both ends. Public so a tool can
## dirty a region without going through the brush.
func add_columns(min_x: int, min_z: int, max_x: int, max_z: int) -> void:
	var size := DistrictCoord.size_vox()
	var d0 := Vector2i(_floor_div(min_x, size.x), _floor_div(min_z, size.z))
	var d1 := Vector2i(_floor_div(max_x, size.x), _floor_div(max_z, size.z))
	for dz in range(d0.y, d1.y + 1):
		for dx in range(d0.x, d1.x + 1):
			var coord := Vector2i(dx, dz)
			var origin := DistrictCoord.origin_vox(coord)
			_add_in_district(
				coord,
				maxi(min_x, origin.x),
				maxi(min_z, origin.z),
				mini(max_x, origin.x + size.x - 1),
				mini(max_z, origin.z + size.z - 1)
			)


## Split one district's share of an edit into regions of at most MAX_REGION_SECTORS per
## axis, so a meteor crater drains over frames instead of eating one whole.
func _add_in_district(coord: Vector2i, min_x: int, min_z: int, max_x: int, max_z: int) -> void:
	if min_x > max_x or min_z > max_z:
		return
	## Both bounds walk the grid of sector *starts*; from_columns turns a start into the
	## full sector.
	var span := (MAX_REGION_SECTORS - 1) * NavDirtyRegionScript.SECTOR_VOX
	var x := NavDirtyRegionScript.floor_to_sector(min_x)
	var x_last := NavDirtyRegionScript.floor_to_sector(max_x)
	var z_first := NavDirtyRegionScript.floor_to_sector(min_z)
	var z_last := NavDirtyRegionScript.floor_to_sector(max_z)
	while x <= x_last:
		var x_end := mini(x + span, x_last)
		var z := z_first
		while z <= z_last:
			var z_end := mini(z + span, z_last)
			_enqueue(NavDirtyRegionScript.from_columns(coord, x, z, x_end, z_end))
			z = z_end + NavDirtyRegionScript.SECTOR_VOX
		x = x_end + NavDirtyRegionScript.SECTOR_VOX


## Merge into a queued neighbour when the union still fits one region, so a hundred cell
## writes in the same sector cost one rescan rather than a hundred. A region part way
## through draining is left alone: growing it would renumber the sectors it has already
## rebuilt, so the new edit becomes a region of its own.
func _enqueue(region: NavDirtyRegion) -> void:
	_queued += 1
	for i in range(_pending.size()):
		var other := _pending[i]
		if not other.is_untouched() or not other.adjoins(region):
			continue
		var union := other.union_sectors(region)
		if union.x > MAX_REGION_SECTORS or union.y > MAX_REGION_SECTORS:
			continue
		other.absorb(region)
		_coalesced += 1
		_absorb_neighbours(i)
		return
	_pending.append(region)


## A grown region may now reach queued neighbours it did not before.
func _absorb_neighbours(index: int) -> void:
	var target := _pending[index]
	var i := _pending.size() - 1
	while i >= 0:
		if i == index:
			i -= 1
			continue
		var other := _pending[i]
		if other.is_untouched() and target.adjoins(other):
			var union := target.union_sectors(other)
			if union.x <= MAX_REGION_SECTORS and union.y <= MAX_REGION_SECTORS:
				target.absorb(other)
				_pending.remove_at(i)
				_coalesced += 1
				if i < index:
					index -= 1
		i -= 1


func pending() -> int:
	return _pending.size()


## Rebuild units the queue still holds. The oldest region may already be part drained, so
## this is what is left to pay for rather than a region count times a constant.
func pending_units() -> int:
	var total := 0
	for region: NavDirtyRegion in _pending:
		total += region.units_left(unit_sectors)
	return total


## Oldest queued region, left in the queue. For the debug overlay and the tests.
func peek_next() -> NavDirtyRegion:
	return peek_at(0)


func peek_at(index: int) -> NavDirtyRegion:
	if index < 0 or index >= _pending.size():
		push_error("NavDirtyTracker.peek_at: %d of %d queued" % [index, _pending.size()])
		return null
	return _pending[index]


## The next rebuild unit of the oldest queued region. The region leaves the queue when it
## has no unit left, so a multi-sector edit spreads over as many drains as it takes.
## NavService drains with this.
func take_unit() -> NavDirtyRegion:
	if _pending.is_empty():
		push_error("NavDirtyTracker.take_unit: queue is empty")
		return null
	var region := _pending[0]
	var unit := region.take_unit(unit_sectors)
	if not region.has_units():
		_pending.pop_front()
	return unit


## Give up on the oldest queued region, whatever is left of it. Its district is not in the
## nav world, which is ordinary while a tile is baking or after it streamed out.
func drop_next() -> void:
	if _pending.is_empty():
		push_error("NavDirtyTracker.drop_next: queue is empty")
		return
	note_unregistered(_pending.pop_front())


func clear_pending() -> void:
	_pending.clear()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

## Record the voxel Y band a district's nav field occupies. NavService reads it off the
## field itself on registration, so the copy below is sized by the bake rather than by a
## constant that could drift from it.
func set_district_y_band(coord: Vector2i, band: Vector2i) -> void:
	if band.y < band.x:
		push_error(
			"NavDirtyTracker.set_district_y_band: district %s reports the empty band %s"
			% [str(coord), str(band)]
		)
		return
	_y_band[coord] = band


func forget_district(coord: Vector2i) -> void:
	_y_band.erase(coord)


## Inclusive voxel Y band a rebuild in this district reads. Inverted when the district is
## not registered.
func district_y_band(coord: Vector2i) -> Vector2i:
	return _y_band.get(coord, Vector2i(0, -1))


## Copy the region's materials out of the live terrain into the layout `rebuild_region`
## expects: a dense box, Y fastest, then X, then Z, `stride` bytes per voxel.
##
## The box carries the region's columns plus `MARGIN_VOX` either side, over the full Y band
## `rebuild_y_range` reported at registration (field rows + link-probe headroom) and no more.
## That band is sized by the offline bake, which can reach past the live terrain ceiling —
## clamping to `terrain.bounds` used to hand NativeNavWorld a short box (e.g. 0..223 when the
## district needs 0..229) and the rebuild refused it. Rows the terrain does not store are
## filled with air (sky). The XZ margin is read as context, never rebuilt. False means the
## region cannot be rebuilt right now.
func fill_materials(region: NavDirtyRegion) -> bool:
	if _brush == null or _brush.tool == null:
		push_error("NavDirtyTracker.fill_materials: no live brush attached")
		return false
	if _terrain == null or not is_instance_valid(_terrain):
		push_error("NavDirtyTracker.fill_materials: the terrain is gone")
		return false
	var band := district_y_band(region.coord)
	if band.y < band.x:
		push_error(
			"NavDirtyTracker.fill_materials: no nav Y band for district %s" % str(region.coord)
		)
		return false
	## Full band — never shorten to terrain.bounds. `rebuild_region` requires every row.
	var y_min := int(band.x)
	var y_max := int(band.y)
	var y_size := y_max - y_min + 1
	var bounds := _terrain.bounds
	var terrain_y_min := floori(bounds.position.y)
	var terrain_y_max := floori(bounds.position.y) + ceili(bounds.size.y) - 1
	var box_min := Vector3i(region.min_x - MARGIN_VOX, y_min, region.min_z - MARGIN_VOX)
	var box_size := Vector3i(
		region.max_x - region.min_x + 1 + 2 * MARGIN_VOX,
		y_size,
		region.max_z - region.min_z + 1 + 2 * MARGIN_VOX
	)
	## Probe editability on the XZ footprint at a Y the terrain actually holds. Upper sky
	## rows past the ceiling are padded with air and do not need to be streamed.
	var copy_y0 := maxi(y_min, terrain_y_min)
	var copy_y1 := mini(y_max, terrain_y_max)
	var probe_y0 := copy_y0
	var probe_y1 := copy_y1
	if probe_y1 < probe_y0:
		if y_max < terrain_y_min or y_min > terrain_y_max:
			push_error(
				"NavDirtyTracker.fill_materials: nav band %s lies outside terrain bounds %s"
				% [str(band), str(bounds)]
			)
			return false
		## Band is entirely above/below the stored ceiling — still need the columns loaded.
		probe_y0 = clampi(y_min, terrain_y_min, terrain_y_max)
		probe_y1 = probe_y0
	var probe_box := AABB(
		Vector3(float(box_min.x), float(probe_y0), float(box_min.z)),
		Vector3(float(box_size.x), float(probe_y1 - probe_y0 + 1), float(box_size.z))
	)
	if not _brush.tool.is_area_editable(probe_box):
		## The tile streamed out from under a queued edit. Rebuilding from a half-loaded
		## copy would carve holes into the field, so drop the region instead.
		_skipped_unloaded += 1
		return false
	var t0 := Time.get_ticks_usec()
	var buffer := _buffer_for(box_size)
	## Sky / unstored headroom starts as air; the terrain slice overwrites what exists.
	buffer.fill(VoxelMaterial.AIR, VoxelBuffer.CHANNEL_TYPE)
	if copy_y1 >= copy_y0:
		var slice_h := copy_y1 - copy_y0 + 1
		var slice := VoxelBuffer.new()
		slice.create(box_size.x, slice_h, box_size.z)
		var slice_min := Vector3i(box_min.x, copy_y0, box_min.z)
		_brush.tool.copy(slice_min, slice, 1 << VoxelBuffer.CHANNEL_TYPE)
		slice.decompress_channel(VoxelBuffer.CHANNEL_TYPE)
		var dst_y := copy_y0 - y_min
		buffer.copy_channel_from_area(
			slice,
			Vector3i.ZERO,
			Vector3i(box_size.x, slice_h, box_size.z),
			Vector3i(0, dst_y, 0),
			VoxelBuffer.CHANNEL_TYPE
		)
	buffer.decompress_channel(VoxelBuffer.CHANNEL_TYPE)
	var stride := 1 << buffer.get_channel_depth(VoxelBuffer.CHANNEL_TYPE)
	var data := buffer.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)
	_last_copy_usec = Time.get_ticks_usec() - t0
	var want := box_size.x * box_size.y * box_size.z * stride
	if data.size() != want:
		push_error(
			"NavDirtyTracker: type channel gave %d bytes for %s at stride %d, expected %d"
			% [data.size(), str(box_size), stride, want]
		)
		return false
	region.box_min = box_min
	region.box_size = box_size
	region.materials = data
	region.stride = stride
	return true


func _buffer_for(size: Vector3i) -> VoxelBuffer:
	if _buffer != null and _buffer_size == size:
		return _buffer
	_buffer = VoxelBuffer.new()
	_buffer.create(size.x, size.y, size.z)
	_buffer_size = size
	return _buffer


# ---------------------------------------------------------------------------
# Bookkeeping
# ---------------------------------------------------------------------------

## Record a finished rebuild unit. `new_version` is the nav version it produced: a path
## built before it and crossing this unit's columns is stale.
func note_rebuilt(region: NavDirtyRegion, sectors: int, usec: int, new_version: int) -> void:
	region.sectors = sectors
	region.version = new_version
	region.drop_materials()
	_rebuilds += 1
	_sectors_rebuilt += sectors
	_last_sectors = sectors
	_last_rebuild_usec = usec
	_worst_unit_usec = maxi(_worst_unit_usec, usec)
	_log.append(region)
	while _log.size() > LOG_CAPACITY:
		var dropped: NavDirtyRegion = _log.pop_front()
		_log_floor_version = maxi(_log_floor_version, dropped.version)


## An edit landed in a district the nav world does not hold. Ordinary while a tile is still
## baking or already unloaded, so it is counted rather than shouted about.
func note_unregistered(region: NavDirtyRegion) -> void:
	region.drop_materials()
	_skipped_unregistered += 1


## Rebuild units finished. One region of several sectors counts once per unit.
func rebuilds() -> int:
	return _rebuilds


func sectors_rebuilt() -> int:
	return _sectors_rebuilt


func regions_queued() -> int:
	return _queued


func regions_coalesced() -> int:
	return _coalesced


func skipped_unregistered() -> int:
	return _skipped_unregistered


func skipped_unloaded() -> int:
	return _skipped_unloaded


## Sectors the last rebuild unit touched.
func last_sectors() -> int:
	return _last_sectors


func last_rebuild_usec() -> int:
	return _last_rebuild_usec


func last_copy_usec() -> int:
	return _last_copy_usec


## Dearest rebuild unit measured so far, material copy included. The drain will not start a
## unit the rest of its frame budget cannot pay for, and this is what it prices one at.
func worst_unit_usec() -> int:
	return _worst_unit_usec


# ---------------------------------------------------------------------------
# Staleness
# ---------------------------------------------------------------------------

## Did anything rebuilt after `since_version` touch the corridor from `from_index` on?
##
## `points` is in world metres. Segments are tested by their bounding box, which can only
## err towards reporting a stale path, and a path older than the log reports stale because
## there is no longer evidence that it is not.
func crosses_since(
	since_version: int, points: PackedVector3Array, from_index: int, voxel_size: float
) -> bool:
	if voxel_size <= 0.0:
		push_error("NavDirtyTracker.crosses_since: voxel_size %.4f" % voxel_size)
		return true
	if since_version <= _log_floor_version:
		return true
	if points.is_empty():
		return false
	var start := maxi(from_index, 0)
	## Newest first: versions only grow along the log, so the first entry the path is old
	## enough to have missed ends the search.
	for i in range(_log.size() - 1, -1, -1):
		var region := _log[i]
		if region.version <= since_version:
			return false
		if _region_touches_path(region, points, start, voxel_size):
			return true
	return false


func _region_touches_path(
	region: NavDirtyRegion, points: PackedVector3Array, start: int, voxel_size: float
) -> bool:
	var last := points.size() - 1
	if start >= last:
		var only := points[mini(start, last)] / voxel_size
		return region.touches_xz(only.x, only.z, only.x, only.z, STALE_MARGIN_VOX)
	for i in range(start, last):
		var a := points[i] / voxel_size
		var b := points[i + 1] / voxel_size
		if region.touches_xz(
			minf(a.x, b.x), minf(a.z, b.z), maxf(a.x, b.x), maxf(a.z, b.z), STALE_MARGIN_VOX
		):
			return true
	return false


func _floor_div(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))
