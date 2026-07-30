## Stamp helpers for the indoor room-prop catalog (RoomPropCatalog).
## Prefer `stamp_brush` for city/castle writes — live edits must go through CityBrush.
class_name RoomPropKit
extends RefCounted


static func material_for(stem: String) -> int:
	return RoomPropCatalog.id_for_stem(stem)


## Single-cell recipe for every catalog prop (multi-cell footprints come later).
static func recipe_cells(_stem: String) -> Array[Vector3i]:
	return [Vector3i.ZERO] as Array[Vector3i]


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
		tool.set_voxel(at, mat)


## City write funnel. Returns true if at least one cell was written.
static func stamp_brush(
	brush: CityBrush,
	origin: Vector3i,
	stem: String,
	overwrite: bool = false
) -> bool:
	var mat := material_for(stem)
	if mat == VoxelMaterial.AIR or mat == 0:
		return false
	var wrote := false
	for off in recipe_cells(stem):
		var at := origin + off
		if not overwrite and brush.get_vox(at) != VoxelMaterial.AIR:
			continue
		brush.set_vox(at, mat)
		wrote = true
	return wrote


static func kit_names() -> PackedStringArray:
	return RoomPropCatalog.kit_names()


static func prop_count() -> int:
	return RoomPropCatalog.PROP_COUNT
