## Thin brush: live VoxelTool *or* NativeOfflineVoxelVolume (thread-safe baking).
## Local district coords; live mode offsets by `origin` into world voxel space.
##
## This is the single funnel for live voxel writes: nothing outside this class may
## call VoxelTool.do_point / do_box / set_voxel on the city terrain, because every
## live write has to be observable through `voxels_changed`.
##
## Clearing voxels (AIR): use `destroy_vox` / `set_vox(..., AIR)` / `fill_box(..., AIR)`.
## All three go through furniture assembly clearing. Non-AIR `fill_box` stays a fast bulk paint.
class_name CityBrush
extends RefCounted

## Region a finished live edit touched, in *world* voxel space: `position` is the
## inclusive minimum, `end` the exclusive maximum. Offline (baking) brushes never
## emit — their nav data comes out of the district bake instead.
##
## Subscribers hook the one live brush CityRoot owns:
##     city_root.voxel_brush().voxels_changed.connect(_on_voxels_changed)
## Nav span/portal rebuild plus nav_version invalidation is the first consumer.
signal voxels_changed(aabb_vox: AABB)

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
## Match OfflineVolumeCommitter / VoxelTerrain block edge.
const _BLOCK := 16

var tool: VoxelTool
var origin: Vector3i = Vector3i.ZERO
## Set when baking off-thread; null in live mode.
var volume: NativeOfflineVoxelVolume

## Open begin_edit() scopes. Writes coalesce into one signal until this hits 0.
var _edit_depth: int = 0
var _dirty: bool = false
var _dirty_min: Vector3i = Vector3i.ZERO
var _dirty_max: Vector3i = Vector3i.ZERO
## Live `set_vox` calls inside begin_edit — flushed as whole 16³ blocks on end_edit
## (copy → patch → paste) so the remesher does one pass per block instead of thrashing
## on every furniture cell. World voxel → material id.
var _pending_live: Dictionary = {}


func _init(p_tool: VoxelTool = null, p_origin: Vector3i = Vector3i.ZERO) -> void:
	tool = p_tool
	origin = p_origin
	if tool != null:
		tool.channel = VoxelBuffer.CHANNEL_TYPE
		tool.mode = VoxelTool.MODE_SET


## Coalesce every write until the matching end_edit() into one `voxels_changed`.
## Nestable; the signal fires when the outermost scope closes. Wrap whole logical
## edits (a blast, a stamped prop) so subscribers rebuild a region once.
func begin_edit() -> void:
	_edit_depth += 1


func end_edit() -> void:
	if _edit_depth <= 0:
		push_error("CityBrush.end_edit: no matching begin_edit")
		return
	_edit_depth -= 1
	if _edit_depth == 0:
		_flush_edit()


## Inclusive min, exclusive max, both already in world voxel space.
func _touch(min_incl: Vector3i, max_excl: Vector3i) -> void:
	if _dirty:
		_dirty_min = Vector3i(
			mini(_dirty_min.x, min_incl.x),
			mini(_dirty_min.y, min_incl.y),
			mini(_dirty_min.z, min_incl.z)
		)
		_dirty_max = Vector3i(
			maxi(_dirty_max.x, max_excl.x),
			maxi(_dirty_max.y, max_excl.y),
			maxi(_dirty_max.z, max_excl.z)
		)
	else:
		_dirty = true
		_dirty_min = min_incl
		_dirty_max = max_excl
	if _edit_depth == 0:
		_flush_edit()


func _flush_edit() -> void:
	if tool != null and volume == null and not _pending_live.is_empty():
		_flush_pending_live_blocks()
	_pending_live.clear()
	if not _dirty:
		return
	_dirty = false
	voxels_changed.emit(AABB(Vector3(_dirty_min), Vector3(_dirty_max - _dirty_min)))


## Apply buffered cell writes like a district stamp: one remesh per touched block.
func _flush_pending_live_blocks() -> void:
	var mask := 1 << VoxelBuffer.CHANNEL_TYPE
	var groups: Dictionary = {}  # Vector3i block_pos → Dictionary local → id
	for pos_v: Variant in _pending_live.keys():
		var pos: Vector3i = pos_v as Vector3i
		var wbp := Vector3i(
			int(floor(float(pos.x) / float(_BLOCK))),
			int(floor(float(pos.y) / float(_BLOCK))),
			int(floor(float(pos.z) / float(_BLOCK)))
		)
		if not groups.has(wbp):
			groups[wbp] = {}
		var local := pos - wbp * _BLOCK
		(groups[wbp] as Dictionary)[local] = int(_pending_live[pos])
	for wbp_v: Variant in groups.keys():
		var wbp: Vector3i = wbp_v as Vector3i
		var cells: Dictionary = groups[wbp] as Dictionary
		var block_origin := wbp * _BLOCK
		var buf := VoxelBuffer.new()
		buf.create(_BLOCK, _BLOCK, _BLOCK)
		tool.copy(block_origin, buf, mask)
		buf.decompress_channel(VoxelBuffer.CHANNEL_TYPE)
		for local_v: Variant in cells.keys():
			var local: Vector3i = local_v as Vector3i
			buf.set_voxel(
				int(cells[local]), local.x, local.y, local.z, VoxelBuffer.CHANNEL_TYPE
			)
		tool.paste(block_origin, buf, mask)


func use_offline_volume(p_volume: NativeOfflineVoxelVolume = null) -> void:
	if p_volume != null:
		volume = p_volume
	else:
		volume = CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	## Offline paints in local space; origin applied at commit time.
	origin = Vector3i.ZERO


## Fill an axis-aligned box [min_v, max_v) with `material_id` (local coords).
##
## CORRECT USAGE
## - Painting solid materials (brick, stone, park, …): call fill_box as usual — fast
##   bulk path (`tool.do_box` / offline `volume.fill_box`).
## - Clearing volume to AIR (doors, courtyards, vaults, dig-out, morph shrink): still
##   call `fill_box(..., VoxelMaterial.AIR)`. AIR is routed through `_clear_box` →
##   `destroy_vox` so multi-cell furniture (origin mesh + PROP_FOOTPRINT) is removed
##   as one assembly.
## - Single-cell runtime destruction: prefer `destroy_vox(pos)` (or `set_vox(pos, AIR)`,
##   which redirects furniture through the same path).
##
## DO NOT
## - Bypass CityBrush with `VoxelTool.do_box` / `set_voxel` / offline volume writes for
##   AIR. A bulk AIR paint that skips `destroy_vox` leaves ghost furniture: the visual
##   mesh lives on the origin cell while sibling cells are only PROP_FOOTPRINT fillers.
## - Assume "fill_box is always a dumb overwrite". For AIR it intentionally expands
##   clears outside the box when a prop assembly straddles the boundary.
## - Reintroduce a fast AIR do_box path for performance without also resolving prop
##   assemblies — that regression is a gameplay bug (blasts / dig-out "go through" sofas).
##
## COST: AIR clears are O(volume) per-cell; non-AIR fills stay O(1) bulk ops. Bake-sized
## hollows are fine; do not micro-optimize AIR back to do_box.
func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	if material_id == VoxelMaterial.AIR:
		_clear_box(min_v, max_v)
		return
	if volume != null:
		volume.fill_box(min_v, max_v, material_id)
		return
	if tool == null:
		push_error("CityBrush.fill_box: no tool or volume")
		return
	tool.mode = VoxelTool.MODE_SET
	tool.value = material_id
	var a := min_v + origin
	var b := max_v + origin - Vector3i.ONE
	tool.do_box(a, b)
	_touch(a, b + Vector3i.ONE)


## AIR half of fill_box: per-cell clear so multi-cell props die as assemblies.
func _clear_box(min_v: Vector3i, max_v: Vector3i) -> void:
	begin_edit()
	for y in range(min_v.y, max_v.y):
		for z in range(min_v.z, max_v.z):
			for x in range(min_v.x, max_v.x):
				var pos := Vector3i(x, y, z)
				var id := get_vox(pos)
				if id == VoxelMaterial.AIR:
					continue
				if VoxelMaterial.is_prop_furniture(id):
					destroy_vox(pos)
				else:
					_write_vox(pos, VoxelMaterial.AIR)
	end_edit()


## Paint a cell. Writing AIR onto furniture is redirected to `destroy_vox` so a
## multi-cell prop cannot leave a ghost mesh when only one footprint cell is cleared.
## Prefer `destroy_vox` explicitly from runtime destruction code.
func set_vox(pos: Vector3i, material_id: int) -> void:
	if material_id == VoxelMaterial.AIR and VoxelMaterial.is_prop_furniture(get_vox(pos)):
		destroy_vox(pos)
		return
	_write_vox(pos, material_id)


## Runtime destruction funnel. Clears `pos`; if it is furniture, clears the whole
## stamped assembly (origin mesh + PROP_FOOTPRINT siblings). Returns carved
## `{vox, mat}` entries (empty when already AIR). Does not enforce is_destructible —
## callers that care filter first.
func destroy_vox(pos: Vector3i) -> Array:
	var id := get_vox(pos)
	if id == VoxelMaterial.AIR:
		return []
	if VoxelMaterial.is_prop_furniture(id):
		var entries: Array = RoomPropKit.assembly_entries(self, pos)
		if entries.is_empty():
			_write_vox(pos, VoxelMaterial.AIR)
			return [{"vox": pos, "mat": id}]
		for entry in entries:
			_write_vox(entry["vox"] as Vector3i, VoxelMaterial.AIR)
		return entries
	_write_vox(pos, VoxelMaterial.AIR)
	return [{"vox": pos, "mat": id}]


func _write_vox(pos: Vector3i, material_id: int) -> void:
	if volume != null:
		volume.set_vox(pos, material_id)
		return
	if tool == null:
		push_error("CityBrush.set_vox: no tool or volume")
		return
	var world := pos + origin
	if _edit_depth > 0:
		## Defer to end_edit block paste — see _flush_pending_live_blocks.
		_pending_live[world] = material_id
		_touch(world, world + Vector3i.ONE)
		return
	tool.set_voxel(world, material_id)
	_touch(world, world + Vector3i.ONE)


func get_vox(pos: Vector3i) -> int:
	if volume != null:
		return int(volume.get_vox(pos))
	if tool == null:
		return 0
	var world := pos + origin
	if _pending_live.has(world):
		return int(_pending_live[world])
	return tool.get_voxel(world)


func column(x: int, z: int, y0: int, y1: int, material_id: int) -> void:
	fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), material_id)


## Euclidean disk at a single Y (inclusive radius in voxels).
func fill_disk(cx: int, cz: int, y: int, radius: int, material_id: int) -> void:
	if radius < 0:
		return
	var r2 := radius * radius
	begin_edit()
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= r2:
				set_vox(Vector3i(x, y, z), material_id)
	end_edit()


## Solid cylinder from y0 inclusive to y1 exclusive.
func fill_cylinder(cx: int, cz: int, y0: int, y1: int, radius: int, material_id: int) -> void:
	if y0 >= y1 or radius < 0:
		return
	begin_edit()
	for y in range(y0, y1):
		fill_disk(cx, cz, y, radius, material_id)
	end_edit()


## Hollow cylinder shell. Inner void uses Euclidean radius `radius - wall_thick`.
## When `hollow_inner` is false, behaves like fill_cylinder.
func fill_cylinder_shell(
	cx: int,
	cz: int,
	y0: int,
	y1: int,
	radius: int,
	material_id: int,
	hollow_inner: bool = true,
	wall_thick: int = 1
) -> void:
	if y0 >= y1 or radius < 0:
		return
	if not hollow_inner or wall_thick <= 0:
		fill_cylinder(cx, cz, y0, y1, radius, material_id)
		return
	var outer2 := radius * radius
	var inner_r := maxi(0, radius - wall_thick)
	var inner2 := inner_r * inner_r
	begin_edit()
	for y in range(y0, y1):
		for z in range(cz - radius, cz + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				var dx := x - cx
				var dz := z - cz
				var d2 := dx * dx + dz * dz
				if d2 <= outer2 and d2 > inner2:
					set_vox(Vector3i(x, y, z), material_id)
	end_edit()


## Solid ellipsoid centred on `center` with per-axis radii.
func fill_ellipsoid(center: Vector3i, radii: Vector3i, material_id: int) -> void:
	if radii.x <= 0 or radii.y <= 0 or radii.z <= 0:
		return
	var fx := float(radii.x)
	var fy := float(radii.y)
	var fz := float(radii.z)
	begin_edit()
	for y in range(center.y - radii.y, center.y + radii.y + 1):
		var ny := float(y - center.y) / fy
		for z in range(center.z - radii.z, center.z + radii.z + 1):
			var nz := float(z - center.z) / fz
			for x in range(center.x - radii.x, center.x + radii.x + 1):
				var nx := float(x - center.x) / fx
				if nx * nx + ny * ny + nz * nz <= 1.0:
					set_vox(Vector3i(x, y, z), material_id)
	end_edit()


## Hollow ellipsoid: only the outer rind is painted so the interior stays walkable.
func fill_ellipsoid_shell(
	center: Vector3i, radii: Vector3i, material_id: int, wall_thick: int = 2
) -> void:
	if radii.x <= 0 or radii.y <= 0 or radii.z <= 0:
		return
	if wall_thick <= 0:
		fill_ellipsoid(center, radii, material_id)
		return
	var fx := float(radii.x)
	var fy := float(radii.y)
	var fz := float(radii.z)
	var ix := maxf(fx - float(wall_thick), 0.001)
	var iy := maxf(fy - float(wall_thick), 0.001)
	var iz := maxf(fz - float(wall_thick), 0.001)
	begin_edit()
	for y in range(center.y - radii.y, center.y + radii.y + 1):
		var dy := float(y - center.y)
		for z in range(center.z - radii.z, center.z + radii.z + 1):
			var dz := float(z - center.z)
			for x in range(center.x - radii.x, center.x + radii.x + 1):
				var dx := float(x - center.x)
				var outer := (dx / fx) * (dx / fx) + (dy / fy) * (dy / fy) + (dz / fz) * (dz / fz)
				if outer > 1.0:
					continue
				var inner := (dx / ix) * (dx / ix) + (dy / iy) * (dy / iy) + (dz / iz) * (dz / iz)
				if inner > 1.0:
					set_vox(Vector3i(x, y, z), material_id)
	end_edit()


## Thin ring: voxels with distance in (radius - thick, radius] (Euclidean).
func fill_disk_ring(
	cx: int, cz: int, y: int, radius: int, thick: int, material_id: int
) -> void:
	if radius < 0 or thick <= 0:
		return
	var outer2 := radius * radius
	var inner_r := maxi(0, radius - thick)
	var inner2 := inner_r * inner_r
	begin_edit()
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			var d2 := dx * dx + dz * dz
			if d2 <= outer2 and d2 > inner2:
				set_vox(Vector3i(x, y, z), material_id)
	end_edit()
