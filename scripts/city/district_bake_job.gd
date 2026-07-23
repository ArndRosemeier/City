## Pure data bake of one district for WorkerThreadPool (no scene / VoxelTool access).
class_name DistrictBakeJob
extends RefCounted

const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")


static func bake(params: Dictionary) -> Dictionary:
	## Returns {ok, error, blocks, impostors, seed, ground_thickness, cell_size, size_x, size_z, origin_vox, coord, planner}
	var coord: Vector2i = params.get("coord", Vector2i.ZERO)
	var world_seed: int = int(params.get("world_seed", 42))
	var size_x: int = int(params.get("size_x", DistrictCoord.SIZE_X_VOX))
	var size_z: int = int(params.get("size_z", DistrictCoord.SIZE_Z_VOX))
	var cell_size: int = int(params.get("cell_size", DistrictCoord.CELL_SIZE))
	var origin: Vector3i = params.get("origin_vox", DistrictCoord.origin_vox(coord))
	var dseed := DistrictCoord.district_seed(world_seed, coord)

	var gen: DistrictGenerator = DistrictGeneratorScript.new()
	gen.size_x = size_x
	gen.size_z = size_z
	gen.cell_size = cell_size
	gen.floor_height_vox = int(params.get("floor_height_vox", 6))
	gen.max_building_height_vox = int(params.get("max_building_height_vox", 200))
	gen.voxel_size = float(params.get("voxel_size", 0.5))
	gen.begin_generate_offline(dseed, origin, coord)

	gen.paint_district_ground_slab()
	var planner := gen.get_planner()
	if planner == null:
		return {"ok": false, "error": "planner missing"}

	var cells_x := planner.cells_x
	var cells_z := planner.cells_z
	for cz in range(cells_z):
		for cx in range(cells_x):
			gen.paint_cell_ground(cx, cz)
	for cz2 in range(cells_z):
		for cx2 in range(cells_x):
			gen.paint_cell_structures(cx2, cz2)
	gen.decorate_open_spaces()

	var volume = gen.get_offline_volume()
	if volume == null:
		return {"ok": false, "error": "volume missing"}

	var cells_total := cells_x * cells_z
	return {
		"ok": true,
		"error": "",
		## Pre-expand to uint16 on the worker — main thread must not loop voxels.
		"blocks": volume.export_blocks_u16(),
		"impostors": gen.building_impostors.duplicate(true),
		"seed": dseed,
		"ground_thickness": gen.ground_thickness,
		"cell_size": cell_size,
		"size_x": size_x,
		"size_z": size_z,
		"origin_vox": origin,
		"coord": coord,
		"cells_total": cells_total,
		## Planner stays alive for nav/props on the main thread.
		"planner": planner,
		"generator": gen,
	}
