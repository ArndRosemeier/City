## Fun ephemeral build recipes for the B-menu. Each recipe is a list of voxels
## relative to a ground anchor (y = 0 sits on the hit cell). Front of the piece
## faces local −Z so the placer can yaw it toward the player.
##
## Rows are authored in `assets/gamedata.json` (`build_recipes`) and loaded via GameData.
class_name BuildCatalog
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

class Recipe:
	var id: String = ""
	var display_name: String = ""
	var hint: String = ""
	## Packed as [ox, oy, oz, material_id] per voxel — compact and typed.
	var voxels: PackedInt32Array = PackedInt32Array()


static var _by_id: Dictionary = {}
static var _order: Array[String] = []
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	_by_id.clear()
	_order.clear()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_order.clear()
	var recipes: Dictionary = GameDataScript.build_recipes()
	var ids: Array = recipes.keys()
	ids.sort()
	for id_v: Variant in ids:
		var id := str(id_v)
		var row: Dictionary = recipes[id] as Dictionary
		var r := Recipe.new()
		r.id = id
		r.display_name = str(row.get("display_name", id))
		r.hint = str(row.get("hint", ""))
		var voxels_raw: Variant = row.get("voxels", [])
		if typeof(voxels_raw) != TYPE_ARRAY:
			push_error("BuildCatalog: '%s' voxels must be an array" % id)
			assert(false, "BuildCatalog: bad voxels")
			continue
		var packed := PackedInt32Array()
		for cell_v: Variant in voxels_raw:
			if typeof(cell_v) != TYPE_ARRAY:
				push_error("BuildCatalog: '%s' voxel cell must be [x,y,z,mat]" % id)
				assert(false, "BuildCatalog: bad voxel cell")
				continue
			var cell: Array = cell_v
			if cell.size() != 4:
				push_error("BuildCatalog: '%s' voxel cell length %d" % [id, cell.size()])
				assert(false, "BuildCatalog: bad voxel cell size")
				continue
			packed.append(int(cell[0]))
			packed.append(int(cell[1]))
			packed.append(int(cell[2]))
			packed.append(int(cell[3]))
		r.voxels = packed
		_by_id[id] = r
		_order.append(id)


static func all() -> Array[Recipe]:
	ensure_loaded()
	var out: Array[Recipe] = []
	for id in _order:
		out.append(_by_id[id] as Recipe)
	return out


static func by_id(recipe_id: String) -> Recipe:
	ensure_loaded()
	if not _by_id.has(recipe_id):
		push_error("BuildCatalog.by_id: unknown recipe '%s'" % recipe_id)
		return null
	return _by_id[recipe_id] as Recipe
