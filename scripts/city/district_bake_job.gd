## Pure data bake of one district for WorkerThreadPool (no scene / VoxelTool access).
class_name DistrictBakeJob
extends RefCounted

const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

## Full voxel buildings + decorate.
const QUALITY_FULL := "full"
## Ground voxels + impostor massing only (no building shells / plaza decorate).
const QUALITY_FAR := "far"

## Block edge of NativeOfflineVoxelVolume, used to read the district's voxel Y extent.
const BLOCK_VOX := 16


static func bake(params: Dictionary) -> Dictionary:
	## Returns {ok, error, blocks, impostors, seed, ground_thickness, ..., quality, generator}
	## plus {nav_bake, nav_stats} — a NativeNavBake and its stats() when `bake_nav` is set,
	## null and {} otherwise. Set `bake_nav` together with `nav_solidity`, the four tables
	## from NavSolidity.export_tables(); `nav_link_params` is optional and passed through.
	var coord: Vector2i = params.get("coord", Vector2i.ZERO)
	var world_seed: int = int(params.get("world_seed", 42))
	var size_x: int = int(params.get("size_x", DistrictCoord.SIZE_X_VOX))
	var size_z: int = int(params.get("size_z", DistrictCoord.SIZE_Z_VOX))
	var cell_size: int = int(params.get("cell_size", DistrictCoord.CELL_SIZE))
	var origin: Vector3i = params.get("origin_vox", DistrictCoord.origin_vox(coord))
	var quality: String = str(params.get("quality", QUALITY_FULL))
	var dseed := DistrictCoord.district_seed(world_seed, coord)
	## Theme comes from the world seed + tile coord, so neighbours agree on identity
	## regardless of which one streams in first.
	var theme := DistrictTheme.for_district(world_seed, coord)

	var gen: DistrictGenerator = DistrictGeneratorScript.new()
	gen.size_x = size_x
	gen.size_z = size_z
	gen.cell_size = cell_size
	gen.floor_height_vox = int(params.get("floor_height_vox", 6))
	gen.max_building_height_vox = int(params.get("max_building_height_vox", 200))
	gen.voxel_size = float(params.get("voxel_size", 0.5))
	gen.theme = theme
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

	if quality == QUALITY_FAR:
		for cz_f in range(cells_z):
			for cx_f in range(cells_x):
				gen.paint_cell_impostor_only(cx_f, cz_f)
		gen.decorate_open_spaces_far()
	else:
		for cz2 in range(cells_z):
			for cx2 in range(cells_x):
				gen.paint_cell_structures(cx2, cz2)
		gen.decorate_open_spaces()

	var volume = gen.get_offline_volume()
	if volume == null:
		return {"ok": false, "error": "volume missing"}

	var blocks: Dictionary = volume.export_blocks_u16()
	var nav_bake: RefCounted = null
	var nav_stats: Dictionary = {}
	if bool(params.get("bake_nav", false)):
		var nav: Dictionary = _bake_nav(params, volume, blocks, origin, size_x, size_z, coord)
		if not bool(nav["ok"]):
			return {"ok": false, "error": str(nav["error"])}
		nav_bake = nav["bake"]
		nav_stats = nav["stats"]

	var cells_total := cells_x * cells_z
	var gems: Dictionary = gen.get_hill_gems()
	return {
		"ok": true,
		"error": "",
		"blocks": blocks,
		"nav_bake": nav_bake,
		"nav_stats": nav_stats,
		"impostors": gen.building_impostors.duplicate(true),
		## InteriorRoom refs — mutable so runtime can flip `decorated`.
		"interior_rooms": gen.interior_rooms.duplicate(),
		## CastleDoorway refs (world voxels) for city lot street doors.
		"lot_doorways": gen.lot_doorways.duplicate(),
		## ElevatorShaft refs (world voxels) for multi-storey lots.
		"elevator_shafts": gen.elevator_shafts.duplicate(),
		"seed": dseed,
		"ground_thickness": gen.ground_thickness,
		"cell_size": cell_size,
		"size_x": size_x,
		"size_z": size_z,
		"origin_vox": origin,
		"coord": coord,
		"cells_total": cells_total,
		"quality": quality,
		"planner": planner,
		"generator": gen,
		"theme_id": theme.id,
		"theme_name": theme.display_name,
		"hill_gem_positions": gems.get("positions", PackedVector3Array()),
		"hill_gem_mats": gems.get("mats", PackedInt32Array()),
	}


## Span field for the district we just painted. Returns {ok, error, bake, stats}.
static func _bake_nav(
	params: Dictionary,
	volume: Object,
	blocks: Dictionary,
	origin: Vector3i,
	size_x: int,
	size_z: int,
	coord: Vector2i
) -> Dictionary:
	var tables: Dictionary = params.get("nav_solidity", {})
	if tables.is_empty():
		return {"ok": false, "error": "bake_nav set without nav_solidity tables"}
	var solid_class: PackedByteArray = tables["class"]
	var solid_top: PackedFloat32Array = tables["top"]
	var solid_destructible: PackedByteArray = tables["destructible"]
	var solid_climbable: PackedByteArray = tables["climbable"]
	var link_params: Dictionary = params.get("nav_link_params", {})
	var y_range := _voxel_y_range(blocks)
	## NativeNavBake, kept untyped like every other GDExtension handle so scripts still
	## parse when the DLL is being rebuilt.
	var bake_obj = CityVoxelNativeScript.make_nav_bake()
	var ok: bool = bake_obj.bake_from_volume(
		volume,
		origin,
		size_x,
		size_z,
		y_range.x,
		y_range.y,
		solid_class,
		solid_top,
		solid_destructible,
		solid_climbable,
		link_params
	)
	if not ok:
		return {"ok": false, "error": "nav bake rejected district %s" % str(coord)}
	return {"ok": true, "error": "", "bake": bake_obj, "stats": bake_obj.stats()}


## Inclusive voxel Y bounds of the painted volume. Taken from the block keys rather than a
## constant so hill caves below the deck and 200-voxel towers above it are both covered —
## navigation has no height ceiling.
static func _voxel_y_range(blocks: Dictionary) -> Vector2i:
	if blocks.is_empty():
		push_error("DistrictBakeJob: nav bake asked for the Y range of an empty volume")
		## Inverted on purpose — the Rust bake refuses it instead of navigating nothing.
		return Vector2i(0, -1)
	var y_min := 2147483647
	var y_max := -2147483648
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		y_min = mini(y_min, bp.y * BLOCK_VOX)
		y_max = maxi(y_max, bp.y * BLOCK_VOX + BLOCK_VOX - 1)
	return Vector2i(y_min, y_max)
