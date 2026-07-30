## Headless: multi-cell furniture must clear as one assembly via CityBrush.destroy_vox.
##
## Run: Godot --headless --path . -s res://tools/test_prop_blast.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const RoomPropKitScript := preload("res://scripts/city/room_prop_kit.gd")


func _initialize() -> void:
	var failed := false
	failed = _check_destroy_vox_footprint(failed)
	failed = _check_set_vox_air_redirect(failed)
	failed = _check_fill_box_air(failed)
	failed = _check_origin_hit(failed)
	if failed:
		push_error("test_prop_blast: FAILED")
		quit(1)
	else:
		print("test_prop_blast: OK")
		quit(0)


func _offline_brush() -> CityBrush:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	return brush


func _check_destroy_vox_footprint(failed: bool) -> bool:
	var brush := _offline_brush()
	var origin := Vector3i(10, 2, 10)
	if not RoomPropKitScript.stamp_brush(brush, origin, "loungeSofa", true):
		push_error("stamp loungeSofa failed")
		return true
	var size := RoomPropKitScript.size_of("loungeSofa")
	var foot := origin + Vector3i(size.x - 1, 0, size.z - 1)
	if brush.get_vox(foot) != VoxelMaterial.PROP_FOOTPRINT:
		push_error("expected PROP_FOOTPRINT at %s" % foot)
		return true
	var carved: Array = brush.destroy_vox(foot)
	if carved.is_empty():
		push_error("destroy_vox returned empty for footprint hit")
		return true
	if brush.get_vox(origin) != VoxelMaterial.AIR:
		push_error("origin mesh cell survived footprint destroy_vox")
		return true
	for off in RoomPropKitScript.recipe_cells("loungeSofa"):
		if brush.get_vox(origin + off) != VoxelMaterial.AIR:
			push_error("cell %s survived destroy_vox" % (origin + off))
			return true
	print("  destroy_vox footprint clears whole sofa (%d cells)" % carved.size())
	return failed


func _check_set_vox_air_redirect(failed: bool) -> bool:
	## Even a naive set_vox(AIR) on a footprint must wipe the assembly.
	var brush := _offline_brush()
	var origin := Vector3i(40, 2, 40)
	if not RoomPropKitScript.stamp_brush(brush, origin, "desk", true):
		push_error("stamp desk failed")
		return true
	var foot := origin + Vector3i(1, 0, 0)
	brush.set_vox(foot, VoxelMaterial.AIR)
	if brush.get_vox(origin) != VoxelMaterial.AIR:
		push_error("set_vox(AIR) left desk origin mesh — redirect broken")
		return true
	print("  set_vox(AIR) redirects through destroy_vox")
	return failed


func _check_fill_box_air(failed: bool) -> bool:
	## Bulk AIR (undead dig-out style) must still wipe multi-cell furniture.
	var brush := _offline_brush()
	var origin := Vector3i(50, 2, 50)
	if not RoomPropKitScript.stamp_brush(brush, origin, "loungeSofa", true):
		push_error("stamp loungeSofa for fill_box failed")
		return true
	var size := RoomPropKitScript.size_of("loungeSofa")
	## Clear only a corner of the footprint — assembly must still vanish.
	brush.fill_box(origin, origin + Vector3i(1, 1, 1), VoxelMaterial.AIR)
	if brush.get_vox(origin) != VoxelMaterial.AIR:
		push_error("fill_box(AIR) left sofa origin")
		return true
	var far := origin + Vector3i(size.x - 1, 0, size.z - 1)
	if brush.get_vox(far) != VoxelMaterial.AIR:
		push_error("fill_box(AIR) left distant footprint cell")
		return true
	print("  fill_box(AIR) clears furniture assembly")
	return failed


func _check_origin_hit(failed: bool) -> bool:
	var brush := _offline_brush()
	var origin := Vector3i(30, 2, 30)
	if not RoomPropKitScript.stamp_brush(brush, origin, "bedSingle", true):
		push_error("stamp bedSingle failed")
		return true
	var carved: Array = brush.destroy_vox(origin)
	var expect := RoomPropKitScript.recipe_cells("bedSingle").size()
	if carved.size() != expect:
		push_error("origin hit carved %d, expected %d" % [carved.size(), expect])
		return true
	print("  destroy_vox origin clears bed footprint (%d cells)" % carved.size())
	return failed
