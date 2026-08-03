## One saved character: who he is, what he carries, where he stood — plus the little the world
## itself remembers, which is one row per district the run has touched.
##
## District voxels are deliberately absent. Terrain follows from `city_seed` alone, and the
## streamer already discards edits once the bubble moves off a district, so a save that claimed to
## restore a dug tunnel would be lying about what the game can do. Loading re-generates the same
## city from the seed and drops the character back in; a stored position that regeneration has
## filled in is resolved by `first_free_footing` instead of by remembering the hole.
##
## What *is* saved per district is six gem counts and an explored flag (see `DistrictEconomy`).
## That is enough for a stripped tile to stay stripped and for exploration to pay once, without
## a voxel edit stream anywhere in the format.
##
## The other thing the world remembers is any match still in progress (see `WorldGames`): a Go
## game is hours of play that regeneration cannot recover from a seed, so the board travels in
## the save and the table is set back up on arrival.
##
## Two kinds of slot share one format:
##   quicksave — `user://saves/quicksave.json`. Written by Quicksave, the periodic autosave and
##               the exit autosave; boot resumes from this file and no other.
##   named     — `user://saves/<name>.json`, one file per name. Plain JSON on purpose: handing the
##               file to someone else's saves folder is the entire porting story.
class_name GameSave
extends RefCounted

const SAVES_DIR := "user://saves"
## Reserved: the autosave slot owns this name, so a named save can never overwrite it.
const QUICKSAVE_NAME := "quicksave"
const FILE_SUFFIX := ".json"
## Bump when the payload changes shape in a way an older file cannot satisfy.
## 2 added `districts` (per-tile gem budgets + explored) and `score`.
## 3 added `mode`, `unlocks`, `tray`, `hardness_tier` (Stage 2 loadout).
## 4 added `recipes` and `recipe_sites`: a v3 Adventure save has no cookbook, and silently
##   handing it an empty one would strip crafts the player had already earned.
## 5 added `games`, the matches a run has going (see `WorldGames`).
const VERSION := 5
const NAME_MAX_LENGTH := 48

## Where slots live. A round-trip test points this at a scratch folder, because the alternative is
## a headless run overwriting the autosave of whoever is playing on that machine. The game itself
## never moves it.
static var _dir: String = SAVES_DIR


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

static func saves_dir() -> String:
	return _dir


## Test-only. Every slot path follows from this, so pointing it elsewhere isolates a whole run.
static func use_directory(path: String) -> void:
	if path.is_empty():
		push_error("GameSave.use_directory: an empty path is not a folder")
		return
	_dir = path


static func use_default_directory() -> void:
	_dir = SAVES_DIR


static func quicksave_path() -> String:
	return "%s/%s%s" % [_dir, QUICKSAVE_NAME, FILE_SUFFIX]


## File path for a named slot. Empty when `raw` holds no usable name.
static func named_path(raw: String) -> String:
	var name := sanitize_name(raw)
	if name.is_empty():
		return ""
	return "%s/%s%s" % [_dir, name, FILE_SUFFIX]


## A filename the user cannot break: letters, digits, dash and underscore, spaces folded to '_'.
## Empty means the input had nothing usable in it, which callers must report rather than guess at.
static func sanitize_name(raw: String) -> String:
	var trimmed := raw.strip_edges()
	var out := ""
	for i in trimmed.length():
		var c := trimmed[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			out += c
		elif c == "-" or c == "_":
			out += c
		elif c == " ":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	if out.length() > NAME_MAX_LENGTH:
		out = out.substr(0, NAME_MAX_LENGTH)
	return out.lstrip("_-").rstrip("_-")


## True when `raw` sanitizes onto the autosave slot. Named saves must refuse it: the autosave
## overwrites that file on a timer, so a hand-made save there would evaporate.
static func is_reserved_name(raw: String) -> bool:
	return sanitize_name(raw).to_lower() == QUICKSAVE_NAME


static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(_dir):
		return true
	var err := DirAccess.make_dir_recursive_absolute(_dir)
	if err != OK:
		push_error("GameSave: cannot create %s (error %d)" % [_dir, err])
		return false
	return true


# ---------------------------------------------------------------------------
# Slots
# ---------------------------------------------------------------------------

static func has_quicksave() -> bool:
	return FileAccess.file_exists(quicksave_path())


static func write_quicksave(data: Dictionary) -> bool:
	return _write_path(quicksave_path(), data)


## The saved payload, or an empty dictionary when there is nothing readable to resume from.
static func read_quicksave() -> Dictionary:
	return _read_path(quicksave_path())


static func delete_quicksave() -> bool:
	var path := quicksave_path()
	if not FileAccess.file_exists(path):
		return true
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("GameSave: cannot delete %s (error %d)" % [path, err])
		return false
	return true


## Move an autosave this build cannot resume out of the slot, keeping it as `quicksave.json.bak` so
## a save from an older build is not simply thrown away.
##
## Boot does this the moment a read comes back empty: the alternative is a file that fails the same
## way on every launch and then gets silently overwritten by the first autosave anyway. The `.bak`
## tail is past `FILE_SUFFIX` on purpose — the Load list only ever looks at `*.json`, so a retired
## file is invisible to it rather than a slot that refuses to load.
static func retire_quicksave() -> bool:
	var path := quicksave_path()
	if not FileAccess.file_exists(path):
		return false
	var kept := "%s.bak" % path
	if FileAccess.file_exists(kept):
		var gone := DirAccess.remove_absolute(kept)
		if gone != OK:
			push_error("GameSave: cannot replace %s (error %d)" % [kept, gone])
			return false
	var err := DirAccess.rename_absolute(path, kept)
	if err != OK:
		push_error("GameSave: cannot move %s aside (error %d)" % [path, err])
		return false
	print("GameSave: %s could not be resumed, kept as %s" % [path, kept])
	return true


static func write_named(raw_name: String, data: Dictionary) -> bool:
	var path := named_path(raw_name)
	if path.is_empty():
		push_error("GameSave.write_named: '%s' has no usable characters for a filename" % raw_name)
		return false
	if is_reserved_name(raw_name):
		push_error("GameSave.write_named: '%s' is the autosave slot" % QUICKSAVE_NAME)
		return false
	return _write_path(path, data)


static func read_named(raw_name: String) -> Dictionary:
	var path := named_path(raw_name)
	if path.is_empty():
		push_error("GameSave.read_named: '%s' is not a save name" % raw_name)
		return {}
	return _read_path(path)


static func delete_named(raw_name: String) -> bool:
	var path := named_path(raw_name)
	if path.is_empty() or is_reserved_name(raw_name):
		push_error("GameSave.delete_named: '%s' is not a named slot" % raw_name)
		return false
	if not FileAccess.file_exists(path):
		return true
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("GameSave: cannot delete %s (error %d)" % [path, err])
		return false
	return true


## Every named slot, newest first. The quicksave is not one of them — it is the autosave file and
## the Load list is a library of saves the player made on purpose.
static func list_named() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(_dir):
		return out
	var dir := DirAccess.open(_dir)
	if dir == null:
		push_error("GameSave: cannot list %s (error %d)" % [_dir, DirAccess.get_open_error()])
		return out
	for file: String in dir.get_files():
		if not file.ends_with(FILE_SUFFIX):
			continue
		var name := file.substr(0, file.length() - FILE_SUFFIX.length())
		if name.to_lower() == QUICKSAVE_NAME:
			continue
		var data := _read_path("%s/%s" % [_dir, file])
		if data.is_empty():
			continue
		out.append({
			"name": name,
			"display_name": String(data.get("display_name", name)),
			"saved_at": String(data.get("saved_at", "")),
			"city_seed": int(data.get("city_seed", 0)),
		})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["saved_at"]) > String(b["saved_at"])
	)
	return out


# ---------------------------------------------------------------------------
# Payload
# ---------------------------------------------------------------------------

## Everything the save holds, read off the live character. `display_name` is what the Load list
## shows; the quicksave passes its own label. `economy` may be null in tools that have no world.
static func capture(
	world_seed: int,
	walker: CityWalker,
	inventory: PlayerInventory,
	display_name: String,
	economy: DistrictEconomy = null,
	score: int = 0,
	loadout: PlayerLoadout = null,
	games: WorldGames = null
) -> Dictionary:
	if walker == null or not is_instance_valid(walker):
		push_error("GameSave.capture: there is no walker to save")
		return {}
	## A detached walker still reports its scale, health, outfit and yaw quite happily, and only
	## lies about where it is — as the world origin. Refuse the whole payload rather than write a
	## save that looks healthy and resumes in the wrong place.
	if not walker.is_inside_tree():
		push_error("GameSave.capture: the walker has left the tree, so it has no world position")
		return {}
	if inventory == null:
		push_error("GameSave.capture: there is no inventory to save")
		return {}
	var props := walker.get_proportions()
	if props == null:
		push_error("GameSave.capture: the walker has no proportions")
		return {}
	var loadout_data := {}
	if loadout != null:
		loadout_data = loadout.to_save_dict()
	else:
		## Tools without a loadout still write a sandbox default so v4 readers stay happy.
		var fallback := PlayerLoadout.new()
		fallback.reset_sandbox()
		loadout_data = fallback.to_save_dict()
	return {
		"version": VERSION,
		"display_name": display_name,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"city_seed": world_seed,
		"position": _vec3_to_array(walker.global_position),
		"yaw": walker.get_yaw(),
		"female": walker.is_female(),
		"character_scale": walker.get_character_scale(),
		"proportions": props.to_dict(),
		"outfit": walker.outfit_save_dict(),
		"health": walker.get_health(),
		"energy": walker.get_energy(),
		"inventory": inventory.slots_snapshot(),
		"score": score,
		"districts": {} if economy == null else economy.to_save_dict(),
		"mode": str(loadout_data.get("mode", PlayerLoadout.MODE_SANDBOX)),
		"unlocks": loadout_data.get("unlocks", []),
		"tray": loadout_data.get("tray", []),
		"hardness_tier": int(loadout_data.get("hardness_tier", PlayerLoadout.HARDNESS_ROCK)),
		"recipes": loadout_data.get("recipes", []),
		"recipe_sites": loadout_data.get("recipe_sites", []),
		"games": {} if games == null else games.to_save_dict(),
	}


static func saved_seed(data: Dictionary) -> int:
	return int(data.get("city_seed", 0))


static func saved_score(data: Dictionary) -> int:
	return int(data.get("score", 0))


static func apply_loadout(loadout: PlayerLoadout, data: Dictionary) -> void:
	if loadout == null:
		push_error("GameSave.apply_loadout: no loadout")
		return
	loadout.load_save_dict({
		"mode": data.get("mode", PlayerLoadout.MODE_SANDBOX),
		"unlocks": data.get("unlocks", []),
		"tray": data.get("tray", []),
		"hardness_tier": data.get("hardness_tier", PlayerLoadout.HARDNESS_ROCK),
		"recipes": data.get("recipes", []),
		"recipe_sites": data.get("recipe_sites", []),
	})


## Pour the saved district rows back into the live economy. A save with no rows is a run that
## never left the spawn tile, not a broken file.
static func apply_districts(economy: DistrictEconomy, data: Dictionary) -> void:
	if economy == null:
		push_error("GameSave.apply_districts: no economy")
		return
	var raw: Variant = data.get("districts", null)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("GameSave.apply_districts: the save has no districts object")
		return
	economy.load_save_dict(raw as Dictionary)


## Hand the saved matches back to the live registry. The games themselves are resumed later,
## by whoever owns the table: this only restores the paperwork.
static func apply_games(games: WorldGames, data: Dictionary) -> void:
	if games == null:
		push_error("GameSave.apply_games: no games registry")
		return
	var raw: Variant = data.get("games", null)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("GameSave.apply_games: the save has no games object")
		return
	games.load_save_dict(raw as Dictionary)


## Where the character stood. Vector3.INF when the payload has no usable position, which is a
## corrupt save rather than a spawn instruction.
static func saved_position(data: Dictionary) -> Vector3:
	var raw: Variant = data.get("position", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 3:
		push_error("GameSave: the save has no position triple")
		return Vector3.INF
	return _array_to_vec3(raw as Array)


static func saved_yaw(data: Dictionary) -> float:
	return float(data.get("yaw", 0.0))


## Restore look, size and pools. Position is the caller's business: it owns the terrain and the
## footing search, and a body placed before the ground exists falls through the world.
static func apply_character(walker: CityWalker, data: Dictionary) -> void:
	if walker == null or not is_instance_valid(walker):
		push_error("GameSave.apply_character: no walker")
		return
	if data.is_empty():
		push_error("GameSave.apply_character: empty save")
		return
	var props_raw: Variant = data.get("proportions", null)
	if typeof(props_raw) != TYPE_DICTIONARY:
		push_error("GameSave.apply_character: the save has no proportions object")
		return
	var props := BodyProportions.from_dict(props_raw as Dictionary)
	var outfit_raw: Variant = data.get("outfit", null)
	var outfit_id := ""
	var skin := Color(0.82, 0.65, 0.52)
	if typeof(outfit_raw) == TYPE_DICTIONARY:
		var outfit_dict: Dictionary = outfit_raw
		outfit_id = String(outfit_dict.get("variant_id", ""))
		skin = Color.from_string(String(outfit_dict.get("skin", "")), skin)
	walker.restore_look(bool(data.get("female", false)), props, outfit_id, skin)
	## Force: a restore must not shrink the character because the mesh has not settled yet.
	walker.set_character_scale(float(data.get("character_scale", 1.0)), true, true)
	walker.set_health_points(float(data.get("health", walker.get_health_max())))
	walker.set_energy_points(float(data.get("energy", walker.get_energy_max())))
	walker.set_yaw(saved_yaw(data))


static func apply_inventory(inventory: PlayerInventory, data: Dictionary) -> void:
	if inventory == null:
		push_error("GameSave.apply_inventory: no inventory")
		return
	var raw: Variant = data.get("inventory", null)
	if typeof(raw) != TYPE_ARRAY:
		push_error("GameSave.apply_inventory: the save has no inventory array")
		return
	inventory.restore_slots(raw as Array)


# ---------------------------------------------------------------------------
# Footing
# ---------------------------------------------------------------------------

## Feet height for the spot nearest `world` in its own voxel column where a body `height_voxels`
## tall stands on something solid. Vector3.INF when the column offers nothing inside the two
## reaches — the caller then falls back to the district's own spawn.
##
## Upwards is the case the feature exists for: the world is rebuilt from the seed, so a character
## saved inside a tunnel he dug is inside rock on load and has to come out on top of it. Downwards
## is shorter and exists because the autosave fires on a timer and will sooner or later catch him
## mid-jump or falling; without it, a save taken in the air would send him to the district spawn.
## Nearest-first rather than one direction then the other, so neither case pulls him further than
## the other would have.
static func first_free_footing(
	tool: VoxelTool,
	world: Vector3,
	voxel_size: float,
	height_voxels: int,
	max_up_voxels: int,
	max_down_voxels: int
) -> Vector3:
	if tool == null:
		push_error("GameSave.first_free_footing: no voxel tool")
		return Vector3.INF
	if voxel_size <= 0.0:
		push_error("GameSave.first_free_footing: voxel size %f" % voxel_size)
		return Vector3.INF
	if height_voxels < 1 or max_up_voxels < 0 or max_down_voxels < 0:
		push_error(
			"GameSave.first_free_footing: height %d / reach +%d -%d is not a body"
			% [height_voxels, max_up_voxels, max_down_voxels]
		)
		return Vector3.INF
	var vx := floori(world.x / voxel_size)
	var vz := floori(world.z / voxel_size)
	var start_y := floori(world.y / voxel_size)
	for step in maxi(max_up_voxels, max_down_voxels) + 1:
		if step <= max_up_voxels and _stands_at(tool, vx, start_y + step, vz, height_voxels):
			return _footing_world(vx, start_y + step, vz, voxel_size)
		if step > 0 and step <= max_down_voxels \
				and _stands_at(tool, vx, start_y - step, vz, height_voxels):
			return _footing_world(vx, start_y - step, vz, voxel_size)
	return Vector3.INF


static func _footing_world(vx: int, y: int, vz: int, voxel_size: float) -> Vector3:
	return Vector3(
		(float(vx) + 0.5) * voxel_size,
		float(y) * voxel_size,
		(float(vz) + 0.5) * voxel_size
	)


## True when a body of `height_voxels` fits with its feet on cell `floor_y` and something solid
## directly under them.
static func _stands_at(
	tool: VoxelTool, vx: int, floor_y: int, vz: int, height_voxels: int
) -> bool:
	if not _blocks_body(tool, Vector3i(vx, floor_y - 1, vz)):
		return false
	return _clear_for_body(tool, vx, floor_y, vz, height_voxels)


## Water is not a floor and not a wall: a body wades through it, so it neither supports a stand
## nor blocks one.
static func _blocks_body(tool: VoxelTool, cell: Vector3i) -> bool:
	var mat := int(tool.get_voxel(cell))
	if mat == VoxelMaterial.AIR or mat == VoxelMaterial.WATER:
		return false
	return VoxelMaterial.is_solid(mat)


static func _clear_for_body(
	tool: VoxelTool, vx: int, floor_y: int, vz: int, height_voxels: int
) -> bool:
	for i in height_voxels:
		if _blocks_body(tool, Vector3i(vx, floor_y + i, vz)):
			return false
	return true


# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

static func _write_path(path: String, data: Dictionary) -> bool:
	if data.is_empty():
		push_error("GameSave: refusing to write an empty payload to %s" % path)
		return false
	if not ensure_dir():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameSave: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameSave: cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameSave: %s does not hold a save object" % path)
		return {}
	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version == VERSION:
		return data
	if version <= 0:
		## No version at all: something wrote this file that was not a build of this game.
		push_error("GameSave: %s carries no save version, so it is not a save" % path)
		return {}
	## A well-formed save from another build. That is what a `VERSION` bump *does*, so it is a
	## warning and not a fault — the run starts fresh and callers decide what to do with the file.
	push_warning(
		"GameSave: %s is save version %d and this build reads %d — it cannot be resumed"
		% [path, version, VERSION]
	)
	return {}


static func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _array_to_vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
