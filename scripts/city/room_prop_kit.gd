## Stamp helpers for the indoor room-prop catalog (RoomPropCatalog).
## Prefer `stamp_brush` for city/castle writes — live edits must go through CityBrush.
##
## Multi-cell props: the origin cell carries the mesh (which may extend past 1×1×1);
## other cells of the footprint get PROP_FOOTPRINT so nav and the decorator treat
## them as occupied without drawing a second copy of the mesh.
## Walk-through ground decor writes *only* the origin — a solid PROP_FOOTPRINT sibling
## would snag the walker on tall flowers / grass even when the mesh cell is passable.
class_name RoomPropKit
extends RefCounted


static func material_for(stem: String) -> int:
	return RoomPropCatalog.id_for_stem(stem)


static func size_of(stem: String) -> Vector3i:
	return RoomPropCatalog.size_of_stem(stem)


## Every cell of the prop's voxel footprint, origin-relative.
static func recipe_cells(stem: String) -> Array[Vector3i]:
	var s := size_of(stem)
	var out: Array[Vector3i] = []
	for y in range(s.y):
		for z in range(s.z):
			for x in range(s.x):
				out.append(Vector3i(x, y, z))
	return out


static func stamp(
	tool: VoxelTool,
	origin: Vector3i,
	stem: String,
	overwrite: bool = false
) -> void:
	var mat := material_for(stem)
	if mat == VoxelMaterial.AIR or mat == 0:
		return
	var walk := RoomPropCatalog.walk_through_of(mat)
	for off in recipe_cells(stem):
		if walk and off != Vector3i.ZERO:
			continue
		var at := origin + off
		if not overwrite and tool.get_voxel(at) != VoxelMaterial.AIR:
			continue
		tool.set_voxel(at, mat if off == Vector3i.ZERO else VoxelMaterial.PROP_FOOTPRINT)


## True when every footprint cell is inside `volume` air and currently empty (or overwrite).
static func can_stamp_brush(
	brush: CityBrush,
	volume: RoomVolume,
	origin: Vector3i,
	stem: String,
	overwrite: bool = false
) -> bool:
	var mat := material_for(stem)
	if mat == VoxelMaterial.AIR or mat == 0:
		return false
	var y_lo := volume.prop_y()
	var y_hi := volume.floor_y + volume.air_h
	for off in recipe_cells(stem):
		var at := origin + off
		if at.y < y_lo or at.y > y_hi:
			return false
		if not volume.contains_xz(Vector2i(at.x, at.z)):
			return false
		if volume.is_cleared(Vector2i(at.x, at.z)):
			return false
		if not overwrite and brush.get_vox(at) != VoxelMaterial.AIR:
			return false
	return true


## City write funnel. Returns true if the full footprint was written.
static func stamp_brush(
	brush: CityBrush,
	origin: Vector3i,
	stem: String,
	overwrite: bool = false
) -> bool:
	var mat := material_for(stem)
	if mat == VoxelMaterial.AIR or mat == 0:
		return false
	var cells := recipe_cells(stem)
	var walk := RoomPropCatalog.walk_through_of(mat)
	if not overwrite:
		for off in cells:
			if brush.get_vox(origin + off) != VoxelMaterial.AIR:
				return false
	for off in cells:
		## Passable decor: reserve the full footprint for placement checks, but only
		## persist the origin so sibling cells stay air (no solid collision boxes).
		if walk and off != Vector3i.ZERO:
			continue
		var id := mat if off == Vector3i.ZERO else VoxelMaterial.PROP_FOOTPRINT
		brush.set_vox(origin + off, id)
	return true


static func kit_names() -> PackedStringArray:
	return RoomPropCatalog.kit_names()


static func prop_count() -> int:
	return RoomPropCatalog.PROP_COUNT


## Largest catalog footprint axis — search window when resolving a PROP_FOOTPRINT hit.
const _ORIGIN_SEARCH := 8


## World cells belonging to the stamped prop that owns `hit` (origin + footprints).
## Empty when `hit` is not furniture. Does not write.
static func assembly_entries(brush: CityBrush, hit: Vector3i) -> Array:
	if brush == null:
		return []
	var id := brush.get_vox(hit)
	if not VoxelMaterial.is_prop_furniture(id):
		return []
	var origin := hit
	var origin_id := id
	if id == VoxelMaterial.PROP_FOOTPRINT:
		var found := _find_origin(brush, hit)
		if found.x == -2147483648:
			## Orphan footprint — clear just this cell.
			return [{"vox": hit, "mat": id}]
		origin = found
		origin_id = brush.get_vox(origin)
		if not VoxelMaterial.is_room_prop(origin_id):
			return [{"vox": hit, "mat": id}]
	var size := RoomPropCatalog.size_of_id(origin_id)
	var out: Array = []
	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var at := origin + Vector3i(x, y, z)
				var mid := brush.get_vox(at)
				if VoxelMaterial.is_prop_furniture(mid):
					out.append({"vox": at, "mat": mid})
	return out


## Clear every cell of the prop assembly containing `hit`. Returns carved entries.
## Delegates to CityBrush.destroy_vox — do not clear furniture via set_vox(AIR) loops.
static func destroy_assembly(brush: CityBrush, hit: Vector3i) -> Array:
	if brush == null:
		return []
	if not VoxelMaterial.is_prop_furniture(brush.get_vox(hit)):
		return []
	return brush.destroy_vox(hit)


## Origin cell of the prop that covers `foot`, or a sentinel if none.
static func _find_origin(brush: CityBrush, foot: Vector3i) -> Vector3i:
	var miss := Vector3i(-2147483648, 0, 0)
	for oy in range(0, _ORIGIN_SEARCH):
		for oz in range(0, _ORIGIN_SEARCH):
			for ox in range(0, _ORIGIN_SEARCH):
				var cand := foot - Vector3i(ox, oy, oz)
				var id := brush.get_vox(cand)
				if not VoxelMaterial.is_room_prop(id):
					continue
				var sz := RoomPropCatalog.size_of_id(id)
				if ox < sz.x and oy < sz.y and oz < sz.z:
					return cand
	return miss
