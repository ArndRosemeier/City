## Headless dump of BuildCatalog → stdout JSON for gamedata migration.
## Run: tools\godot\Godot_v4.6-voxel_win64.exe --headless --path . -s tools/dump_build_recipes.gd
extends SceneTree


func _init() -> void:
	var out: Dictionary = {}
	for recipe in BuildCatalog.all():
		var voxels: Array = []
		var packed: PackedInt32Array = recipe.voxels
		var i := 0
		while i + 3 < packed.size():
			voxels.append([packed[i], packed[i + 1], packed[i + 2], packed[i + 3]])
			i += 4
		var row: Dictionary = {
			"display_name": recipe.display_name,
			"hint": recipe.hint,
			"voxels": voxels,
		}
		if not recipe.consume_item.is_empty():
			row["consume_item"] = recipe.consume_item
			row["consume_count"] = recipe.consume_count
		if recipe.requires_recipe:
			row["requires_recipe"] = true
		out[recipe.id] = row
	print("BUILD_RECIPES_JSON_BEGIN")
	print(JSON.stringify(out))
	print("BUILD_RECIPES_JSON_END")
	quit(0)
