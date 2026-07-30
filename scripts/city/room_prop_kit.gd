## Stamp helpers for the indoor room-prop catalog (RoomPropCatalog).
## Prefer `stamp_brush` for city/castle writes — live edits must go through CityBrush.
##
## Multi-cell props: the origin cell carries the mesh (which may extend past 1×1×1);
## other cells of the footprint get PROP_FOOTPRINT so nav and the decorator treat
## them as occupied without drawing a second copy of the mesh.
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
	for off in recipe_cells(stem):
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
	if not overwrite:
		for off in cells:
			if brush.get_vox(origin + off) != VoxelMaterial.AIR:
				return false
	for off in cells:
		var id := mat if off == Vector3i.ZERO else VoxelMaterial.PROP_FOOTPRINT
		brush.set_vox(origin + off, id)
	return true


static func kit_names() -> PackedStringArray:
	return RoomPropCatalog.kit_names()


static func prop_count() -> int:
	return RoomPropCatalog.PROP_COUNT
