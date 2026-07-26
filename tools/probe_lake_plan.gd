## Bake a Lake district and dump its plan view, so the shoreline and the islands can
## be judged without booting the live city.
##
## Run: Godot --headless --path . --script tools/probe_lake_plan.gd
extends SceneTree

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const WORLD_SEED := 42
const BLOCK := 16
const PLAN_PNG := "res://tools/lake_plan.png"
## Console map downsample — one character per this many voxels on each axis.
const ASCII_STEP := 8


func _initialize() -> void:
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.LAKE, 8)
	print("baking Lake district at %s" % coord)
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
	})
	if not bool(res.get("ok", false)):
		push_error("bake failed: %s" % res.get("error", "?"))
		quit(1)
		return
	var size_x := int(res["size_x"])
	var size_z := int(res["size_z"])
	var deck := int(res["ground_thickness"])
	var top_mat := PackedInt32Array()
	var top_y := PackedInt32Array()
	top_mat.resize(size_x * size_z)
	top_y.resize(size_x * size_z)
	top_mat.fill(VoxelMaterial.AIR)
	top_y.fill(-1)
	_collect_surface(res["blocks"], size_x, size_z, top_mat, top_y)
	_print_ascii(size_x, size_z, top_mat)
	_save_png(size_x, size_z, deck, top_mat, top_y)
	quit(0)


func _collect_surface(
	blocks: Dictionary,
	size_x: int,
	size_z: int,
	top_mat: PackedInt32Array,
	top_y: PackedInt32Array
) -> void:
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var data: PackedByteArray = blocks[key]
		var uniform := data.size() <= 2
		if uniform and int(data[0]) == VoxelMaterial.AIR:
			continue
		for lz in range(BLOCK):
			var wz := bp.z * BLOCK + lz
			if wz < 0 or wz >= size_z:
				continue
			for lx in range(BLOCK):
				var wx := bp.x * BLOCK + lx
				if wx < 0 or wx >= size_x:
					continue
				var col := wz * size_x + wx
				for ly in range(BLOCK - 1, -1, -1):
					var vid := (
						int(data[0]) if uniform
						else int(data[(ly + lx * BLOCK + lz * BLOCK * BLOCK) * 2])
					)
					if vid == VoxelMaterial.AIR:
						continue
					var wy := bp.y * BLOCK + ly
					if wy > top_y[col]:
						top_y[col] = wy
						top_mat[col] = vid
					break


func _print_ascii(size_x: int, size_z: int, top_mat: PackedInt32Array) -> void:
	var z := 0
	while z < size_z:
		var line := ""
		var x := 0
		while x < size_x:
			line += _glyph(top_mat[z * size_x + x])
			x += ASCII_STEP
		print(line)
		z += ASCII_STEP


func _glyph(mat: int) -> String:
	match mat:
		VoxelMaterial.WATER:
			return "~"
		VoxelMaterial.LEAVES, VoxelMaterial.BARK:
			return "T"
		VoxelMaterial.PARK:
			return ","
		VoxelMaterial.GRAVEL, VoxelMaterial.DIRT, VoxelMaterial.STONE:
			return "."
		VoxelMaterial.ASPHALT, VoxelMaterial.ROAD_LINE, VoxelMaterial.CROSSWALK:
			return "#"
		VoxelMaterial.SIDEWALK, VoxelMaterial.CURB:
			return "="
		VoxelMaterial.AIR:
			return " "
		_:
			return "?"


func _save_png(
	size_x: int,
	size_z: int,
	deck: int,
	top_mat: PackedInt32Array,
	top_y: PackedInt32Array
) -> void:
	var img := Image.create(size_x, size_z, false, Image.FORMAT_RGB8)
	for z in range(size_z):
		for x in range(size_x):
			var col := z * size_x + x
			var mat := top_mat[col]
			var c := VoxelMaterial.color(mat)
			## Shade by height so islands and banks read as relief, not flat colour.
			var rel := float(top_y[col] - deck)
			c = c.lightened(clampf(rel * 0.05, 0.0, 0.4)) if rel > 0.0 else c
			img.set_pixel(x, z, c)
	var err := img.save_png(PLAN_PNG)
	if err != OK:
		push_error("could not save %s (error %d)" % [PLAN_PNG, err])
		return
	print("SAVED %s" % PLAN_PNG)
