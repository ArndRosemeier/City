## A gem chest standing in a furnished room: click it, the lid swings, and it pays out of the
## district's gem budget once.
##
## Clicked rather than walked into — the blaster's pre-fire swallow resolves it (see
## `CityWalker._try_world_interact`), which is why the body sits on collision layer 1 and the node
## carries the `world_interact` group. A chest is a thing you would never want to shoot.
##
## Town chests spend the district gem budget. Hill chests do not — cave ore owns that ledger so
## the bake can paint exactly what is left; a hill chest is a small free haul instead.
class_name GemChest
extends Node3D

const CHEST_SCENE_PATH := "res://assets/city/chests/chest.glb"

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Fewest and most gems one chest can hold before the budget has its say (gamedata).
static var GEMS_MIN: int = 1
static var GEMS_MAX: int = 3
## Kenney's chest is authored about 1 m across; city rooms are 0.5 m voxels, so it reads as a
## crate rather than furniture at this size.
const MODEL_SCALE := 0.9
## Clickable box when the model reports no usable bounds of its own.
const FALLBACK_EXTENTS := Vector3(0.45, 0.35, 0.35)

## Which tile's budget this chest draws on.
var district_coord: Vector2i = Vector2i.ZERO

var _rng := RandomNumberGenerator.new()
var _anim: AnimationPlayer
var _opened: bool = false
## Kept past `build` so the recipe roll and the gem roll cannot drift apart.
var _chest_seed: int = 0


## Stand a chest at `world_pos` facing `yaw`, drawing on `coord`'s budget. `chest_seed` fixes how
## many gems it holds, so the same room in the same world always holds the same chest.
func build(coord: Vector2i, world_pos: Vector3, yaw: float, chest_seed: int) -> bool:
	district_coord = coord
	_chest_seed = chest_seed
	_rng.seed = chest_seed
	var packed := load(CHEST_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("GemChest: cannot load %s" % CHEST_SCENE_PATH)
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		push_error("GemChest: %s is not a Node3D scene" % CHEST_SCENE_PATH)
		return false
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	_anim = _find_anim_player(model)
	if _anim == null:
		push_error("GemChest: the chest model has no AnimationPlayer, so the lid cannot open")
	global_position = world_pos
	rotation.y = yaw
	_add_click_body(model)
	add_to_group("world_interact")
	return true


## True when this chest is spent — open, whatever it paid out.
func is_opened() -> bool:
	return _opened


## Clicked. Returns true in every case where the click belonged to the chest, so the shot that
## found it is swallowed rather than turned into a bolt: an already-open chest is still a chest.
func interact_at_world(_world_pos: Vector3) -> bool:
	if _opened:
		return true
	_opened = true
	_play_open()
	var city := _city_root()
	if city == null:
		push_error("GemChest: opened with no CityRoot to hand the gems to")
		return true
	var loot: Dictionary = GameDataScript.chest_loot()
	GEMS_MIN = int(loot.get("gems_min", 1))
	GEMS_MAX = int(loot.get("gems_max", 3))
	var wanted := _rng.randi_range(GEMS_MIN, GEMS_MAX)
	var paid := 0
	## Hills: cave ore owns the district budget (bake paints remaining). Chests there are a
	## separate toy haul so opening one cannot ghost out topaz still sitting in the rock.
	var hill_chest := _is_hill_district(city)
	var economy := city.get_economy()
	for _i in range(wanted):
		var gem: int
		if hill_chest:
			gem = VoxelMaterial.pick_gem(_rng)
			if city.grant_district_gem(district_coord, gem, false):
				paid += 1
			continue
		## Other themes: draw only from what this tile still owes.
		gem = economy.pick_available(district_coord, _rng)
		if gem == VoxelMaterial.AIR:
			break
		if city.grant_district_gem(district_coord, gem, true):
			paid += 1
	## A chest is the one recipe site that is not a landmark, so it rolls rarely — but it rolls
	## before the haul is reported, so a chest that pays a scroll names itself for the scroll.
	var found_recipe := _try_pay_recipe(city)
	## After the grants: each one has put its stone on the loot card, and the city plays the lid and
	## the flourish over the finished haul.
	if not found_recipe:
		city.report_chest_opened(global_position, paid)
	print(
		"GemChest: district %s chest held %d gems, paid %d"
		% [str(district_coord), wanted, paid]
	)
	return true


## Rare bonus: the chest also held a sealed recipe. Seeded off the chest, so the same chest in
## the same world either always holds one or never does.
func _try_pay_recipe(city: CityRoot) -> bool:
	var site := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_CHEST, district_coord, _chest_seed
	)
	if city.is_recipe_site_looted(site):
		return false
	if not RecipePickupPlacer.should_place(RecipePickupPlacer.SITE_CHEST, _chest_seed):
		return false
	return city.collect_recipe_pickup(site, global_position)


func _is_hill_district(city: CityRoot) -> bool:
	if city == null:
		return false
	return city.get_loaded_district_theme_id(district_coord) == DistrictTheme.HILL


func _play_open() -> void:
	if _anim == null:
		return
	var open_name := _open_animation()
	if open_name.is_empty():
		push_error("GemChest: the chest model has no open animation")
		return
	_anim.play(open_name)


func _open_animation() -> String:
	for name in _anim.get_animation_list():
		var base: String = name.get_file() if name.contains("/") else name
		if base == "open":
			return name
	for name in _anim.get_animation_list():
		if name.contains("open") and not name.contains("close"):
			return name
	return ""


## One box on layer 1 covering the model, so the aim ray can find the chest at all. Sized from
## the meshes rather than guessed, because the kit's chest is not a unit cube.
func _add_click_body(model: Node3D) -> void:
	var bounds := _model_bounds(model)
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	add_child(body)


## Union of the model's mesh bounds in this chest's own space, or a crate-sized fallback.
func _model_bounds(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	var out := AABB()
	var have := false
	for mi in meshes:
		if mi.mesh == null:
			continue
		var local := (model.transform * _relative_transform(model, mi)) * mi.mesh.get_aabb()
		if not have:
			out = local
			have = true
		else:
			out = out.merge(local)
	if not have or out.size.length_squared() < 0.000001:
		push_error("GemChest: the chest model reports no mesh bounds — using a crate-sized box")
		return AABB(-FALLBACK_EXTENTS, FALLBACK_EXTENTS * 2.0)
	return out


## `node`'s transform expressed in `base`'s space. Cheaper and safer than global transforms,
## which are not valid until the chest is in the tree.
func _relative_transform(base: Node3D, node: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var walk: Node3D = node
	while walk != null and walk != base:
		out = walk.transform * out
		walk = walk.get_parent() as Node3D
	return out


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for child in node.get_children():
		_collect_meshes(child, out)


func _find_anim_player(node: Node) -> AnimationPlayer:
	var ap := node as AnimationPlayer
	if ap != null:
		return ap
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


func _city_root() -> CityRoot:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("city_root")
	if nodes.is_empty():
		return null
	return nodes[0] as CityRoot
