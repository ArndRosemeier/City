## Headless: fractal cascade peels a column then hops to one same-material neighbour.
extends Node

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const FractalCascadeScript := preload("res://scripts/city/fractal_cascade.gd")


func _ready() -> void:
	var failed := false
	if not VoxelMaterial.is_fractal_display(VoxelMaterial.FRACTAL_BAND_3):
		push_error("FAIL BAND_3 not fractal_display")
		failed = true
	if VoxelMaterial.is_fractal_display(VoxelMaterial.STONE):
		push_error("FAIL STONE wrongly fractal_display")
		failed = true
	if not _check_peel_and_hop():
		failed = true
	if not _check_no_branch():
		failed = true
	if not _check_same_material():
		failed = true
	if not _check_blast_sphere_seeds_from_neighbour():
		failed = true
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)


func _brush() -> CityBrush:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume(volume)
	return brush


func _check_peel_and_hop() -> bool:
	var brush := _brush()
	for y in range(2, 6):
		brush.set_vox(Vector3i(10, y, 20), VoxelMaterial.FRACTAL_BAND_3)
	for y in range(2, 5):
		brush.set_vox(Vector3i(11, y, 20), VoxelMaterial.FRACTAL_BAND_3)
	brush.set_vox(Vector3i(10, 1, 20), VoxelMaterial.DIRT)
	brush.set_vox(Vector3i(14, 2, 20), VoxelMaterial.FRACTAL_BAND_3)
	var c = FractalCascadeScript.new()
	if c.start(brush, Vector3i(10, 4, 20)).is_empty():
		push_error("FAIL start empty")
		return false
	for y in range(2, 6):
		if brush.get_vox(Vector3i(10, y, 20)) != VoxelMaterial.AIR:
			push_error("FAIL column not peeled")
			return false
	if brush.get_vox(Vector3i(10, 1, 20)) != VoxelMaterial.DIRT:
		push_error("FAIL dirt carved")
		return false
	if c.tick().is_empty():
		push_error("FAIL hop empty")
		return false
	for y in range(2, 5):
		if brush.get_vox(Vector3i(11, y, 20)) != VoxelMaterial.AIR:
			push_error("FAIL neighbour not peeled")
			return false
	if brush.get_vox(Vector3i(14, 2, 20)) != VoxelMaterial.FRACTAL_BAND_3:
		push_error("FAIL distant cell destroyed")
		return false
	if not c.tick().is_empty() or c.is_active():
		push_error("FAIL did not stop")
		return false
	return true


func _check_no_branch() -> bool:
	## T-junction: path takes one arm, the other must remain.
	var brush := _brush()
	var mat := VoxelMaterial.FRACTAL_BAND_5
	brush.set_vox(Vector3i(5, 2, 5), mat)
	brush.set_vox(Vector3i(5, 2, 6), mat)
	brush.set_vox(Vector3i(4, 2, 6), mat)
	brush.set_vox(Vector3i(3, 2, 6), mat)
	brush.set_vox(Vector3i(6, 2, 6), mat)
	brush.set_vox(Vector3i(7, 2, 6), mat)
	var c = FractalCascadeScript.new()
	c.start(brush, Vector3i(5, 2, 5))
	var guard := 0
	while c.is_active() and guard < 20:
		c.tick()
		guard += 1
	var left := brush.get_vox(Vector3i(3, 2, 6)) == mat
	var right := brush.get_vox(Vector3i(7, 2, 6)) == mat
	if left == right:
		push_error("FAIL branched or stalled (left=%s right=%s)" % [left, right])
		return false
	return true


func _check_same_material() -> bool:
	var brush := _brush()
	for y in range(2, 5):
		brush.set_vox(Vector3i(0, y, 0), VoxelMaterial.FRACTAL_BAND_3)
		brush.set_vox(Vector3i(1, y, 0), VoxelMaterial.FRACTAL_BAND_7)
	var c = FractalCascadeScript.new()
	c.start(brush, Vector3i(0, 3, 0))
	if not c.tick().is_empty() or c.is_active():
		push_error("FAIL hopped onto different material")
		return false
	if brush.get_vox(Vector3i(1, 2, 0)) != VoxelMaterial.FRACTAL_BAND_7:
		push_error("FAIL different-mat neighbour carved")
		return false
	return true


## Floor blast next to a fractal column: seed from the fractal cell in the sphere, not the dirt centre.
func _check_blast_sphere_seeds_from_neighbour() -> bool:
	var brush := _brush()
	brush.set_vox(Vector3i(5, 2, 5), VoxelMaterial.DIRT)
	for y in range(2, 6):
		brush.set_vox(Vector3i(6, y, 5), VoxelMaterial.FRACTAL_BAND_3)
	## Mimic CityRoot pass 1: note centre dirt, then neighbour fractal → fractal wins the seed.
	var seed := Vector3i(2147483647, 2147483647, 2147483647)
	for vox in [Vector3i(5, 2, 5), Vector3i(6, 2, 5), Vector3i(6, 3, 5)]:
		var mat := brush.get_vox(vox)
		if VoxelMaterial.is_fractal_display(mat) and seed.x == 2147483647:
			seed = vox
	if seed != Vector3i(6, 2, 5):
		push_error("FAIL expected fractal seed at column base, got %s" % seed)
		return false
	var c = FractalCascadeScript.new()
	if c.start(brush, seed).is_empty():
		push_error("FAIL neighbour seed did not peel")
		return false
	for y in range(2, 6):
		if brush.get_vox(Vector3i(6, y, 5)) != VoxelMaterial.AIR:
			push_error("FAIL column not peeled from floor-adjacent seed")
			return false
	if brush.get_vox(Vector3i(5, 2, 5)) != VoxelMaterial.DIRT:
		push_error("FAIL dirt centre was carved by fractal cascade")
		return false
	return true
