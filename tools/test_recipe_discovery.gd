## Recipe discovery: an empty Adventure cookbook, the schematic gate on power unlocks, what a
## scroll turns into once nothing is left to learn, and the save round-trip that keeps all of it.
##
## Run: powershell -File tools\run_test.ps1 test_recipe_discovery
extends Node

const GameSaveScript := preload("res://scripts/city/game_save.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const PlayerLoadoutScript := preload("res://scripts/city/player_loadout.gd")
const LootToastScript := preload("res://scripts/city/loot_toast.gd")

const SCRATCH_DIR := "user://test_recipe_discovery"
const WORLD_SEED := 90210

var _failed := false


class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	GameSaveScript.use_directory(SCRATCH_DIR)
	_wipe_scratch()
	_check_catalog_has_a_schematic_per_power()
	_check_mode_starting_books()
	_check_learn_and_craft_gate()
	await _check_pickup_learns_then_pays_gems()
	await _check_walk_over_collects()
	_check_site_ids_and_chances()
	await _check_save_round_trip()
	_wipe_scratch()
	GameSaveScript.use_default_directory()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _wipe_scratch() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.dir_exists("test_recipe_discovery"):
		_wipe_dir(SCRATCH_DIR)


func _wipe_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var child := path.path_join(name)
		if d.current_is_dir():
			_wipe_dir(child)
		DirAccess.remove_absolute(child)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


## Every gem-priced power must have a schematic, or shipping a new ability would quietly hand
## it out for free the moment a player has the gems.
func _check_catalog_has_a_schematic_per_power() -> void:
	for def in AbilityRegistry.unlockable_defs():
		var id := InventoryCatalog.schematic_id_for_ability(def.id)
		var recipe := InventoryCatalog.recipe(id)
		if recipe == null:
			_fail("FAIL no schematic for gated power '%s'" % def.id)
			continue
		if recipe.kind != InventoryCatalog.RECIPE_KIND_SCHEMATIC:
			_fail("FAIL '%s' is not a schematic" % id)
		if recipe.unlocks_ability != def.id:
			_fail("FAIL schematic '%s' points at '%s'" % [id, recipe.unlocks_ability])
	if InventoryCatalog.craft_recipes().is_empty():
		_fail("FAIL the catalog lost its craft recipes")
	for recipe in InventoryCatalog.craft_recipes():
		if recipe.output_id.is_empty():
			_fail("FAIL craft recipe '%s' has no output" % recipe.id)
	print("OK one schematic per gated power, crafts still produce items")


func _starter_schematic_count() -> int:
	## Adventure grant_starter teaches schematics for gated starter unlocks (e.g. hardness).
	var n := 0
	for id in AbilityRegistry.STARTER_UNLOCKS:
		var schematic_id := InventoryCatalog.schematic_id_for_ability(str(id))
		if InventoryCatalog.has_recipe(schematic_id):
			n += 1
	return n


func _check_mode_starting_books() -> void:
	var adv: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	adv.reset_adventure()
	var starters := _starter_schematic_count()
	if adv.known_recipes.size() != starters:
		_fail(
			"FAIL adventure cookbook should be only starter schematics (want %d got %d)"
			% [starters, adv.known_recipes.size()]
		)
	if adv.missing_recipe_ids().size() != InventoryCatalog.all_recipe_ids().size() - starters:
		_fail("FAIL adventure should be missing every non-starter recipe")
	if adv.knows_recipe(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL adventure must not know the trap recipe")
	if adv.knows_recipe(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL adventure must not know the cloudstone craft")

	var sand: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	sand.reset_sandbox()
	if not sand.knows_recipe(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL sandbox must know every craft recipe")
	if not sand.knows_recipe(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL sandbox must know the cloudstone craft")
	if not sand.knows_ability_schematic(AbilityRegistry.ID_MINION):
		_fail("FAIL sandbox must know every schematic")
	if not sand.missing_recipe_ids().is_empty():
		_fail("FAIL sandbox must be missing nothing")
	print("OK adventure starts empty, sandbox starts complete")


func _check_learn_and_craft_gate() -> void:
	var adv: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	adv.reset_adventure()
	if adv.knows_ability_schematic(AbilityRegistry.ID_STOMP):
		_fail("FAIL adventure must not know the stomp schematic")
	var schematic := InventoryCatalog.schematic_id_for_ability(AbilityRegistry.ID_STOMP)
	if not adv.learn_recipe(schematic):
		_fail("FAIL learning the stomp schematic should report a new recipe")
	if adv.learn_recipe(schematic):
		_fail("FAIL learning a known recipe must report false")
	if not adv.knows_ability_schematic(AbilityRegistry.ID_STOMP):
		_fail("FAIL stomp schematic did not stick")
	if adv.knows_ability_schematic(AbilityRegistry.ID_SHIELD):
		_fail("FAIL learning one schematic must not unlock another")

	var city := TestCity.new()
	add_child(city)
	city._loadout = adv
	city._inventory = PlayerInventoryScript.new() as PlayerInventory
	city._inventory.add(InventoryCatalog.ID_SAPPHIRE, 10)
	city._inventory.add(InventoryCatalog.ID_TOPAZ, 10)
	if city.try_unlock_ability(AbilityRegistry.ID_SHIELD):
		_fail("FAIL a funded but unknown power must not unlock")
	city._inventory.add(InventoryCatalog.ID_QUARTZ, 20)
	city._inventory.add(InventoryCatalog.ID_EMERALD, 5)
	if not city.try_unlock_ability(AbilityRegistry.ID_STOMP):
		_fail("FAIL a known and funded power must unlock")
	city.queue_free()
	print("OK schematic gates the unlock, and only its own power")


func _check_pickup_learns_then_pays_gems() -> void:
	var city := TestCity.new()
	add_child(city)
	city.city_seed = WORLD_SEED
	city._loadout = PlayerLoadoutScript.new() as PlayerLoadout
	city._loadout.reset_adventure()
	city._inventory = PlayerInventoryScript.new() as PlayerInventory
	city._loot_toast = LootToastScript.new() as LootToast
	city.add_child(city._loot_toast)
	await get_tree().process_frame

	var site := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_HILL_SUMMIT, Vector2i(3, -1), 0
	)
	var before_n := city._loadout.known_recipes.size()
	if not city.collect_recipe_pickup(site, Vector3(10.0, 20.0, 10.0)):
		_fail("FAIL the first scroll should have taught something")
	if city._loadout.known_recipes.size() != before_n + 1:
		_fail("FAIL a scroll must teach exactly one recipe")
	if not city.is_recipe_site_looted(site):
		_fail("FAIL the site should be marked looted")
	if city.collect_recipe_pickup(site, Vector3(10.0, 20.0, 10.0)):
		_fail("FAIL a looted site must not pay again")
	if city._loadout.known_recipes.size() != before_n + 1:
		_fail("FAIL the second collect changed the cookbook")

	## Full cookbook: the same kind of site now has to pay a rare stone instead.
	city._loadout.learn_every_recipe()
	var gem_site := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_CASTLE_TOWER, Vector2i(0, 0), 2
	)
	var before := (
		city._inventory.count_of(InventoryCatalog.ID_EMERALD)
		+ city._inventory.count_of(InventoryCatalog.ID_DIAMOND)
	)
	if not city.collect_recipe_pickup(gem_site, Vector3(4.0, 30.0, 4.0)):
		_fail("FAIL a full cookbook should still pay out")
	var after := (
		city._inventory.count_of(InventoryCatalog.ID_EMERALD)
		+ city._inventory.count_of(InventoryCatalog.ID_DIAMOND)
	)
	if after != before + 1:
		_fail("FAIL full cookbook should pay one rare gem, got %d" % (after - before))
	city.queue_free()
	print("OK a scroll learns once, then falls back to a rare gem")


## Walking onto the scroll must collect it. Click still works, but a climb that ends with the
## player standing on the prop used to do nothing because only the blaster ray could take it.
func _check_walk_over_collects() -> void:
	var city := TestCity.new()
	add_child(city)
	city.city_seed = WORLD_SEED
	city._loadout = PlayerLoadoutScript.new() as PlayerLoadout
	city._loadout.reset_adventure()
	city._inventory = PlayerInventoryScript.new() as PlayerInventory
	city._loot_toast = LootToastScript.new() as LootToast
	city.add_child(city._loot_toast)
	await get_tree().process_frame

	var site := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_GAZEBO, Vector2i(1, 1), 0
	)
	var pickup := RecipePickup.new()
	city.add_child(pickup)
	if not pickup.build(site, Vector3(8.0, 3.0, 8.0), 42):
		_fail("FAIL recipe pickup failed to build")
		city.queue_free()
		return
	await get_tree().process_frame
	var area := pickup.get_node_or_null("CollectArea") as Area3D
	if area == null:
		_fail("FAIL recipe pickup has no CollectArea")
		city.queue_free()
		return
	if area.collision_mask != 2:
		_fail("FAIL CollectArea mask is %d, want the walker layer (2)" % area.collision_mask)

	## Anything else on that layer (peds, undead) must not vacuum the scroll.
	var decoy := CharacterBody3D.new()
	decoy.collision_layer = 2
	area.body_entered.emit(decoy)
	await get_tree().process_frame
	if pickup == null or not is_instance_valid(pickup) or pickup.is_taken():
		_fail("FAIL a non-walker body collected the recipe")
		city.queue_free()
		return

	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.set_physics_process(false)
	walker.set_process(false)
	city.add_child(walker)
	await get_tree().process_frame
	area.body_entered.emit(walker)
	await get_tree().process_frame
	if is_instance_valid(pickup) and not pickup.is_taken():
		_fail("FAIL walking onto the recipe left it standing")
	if city._loadout.known_recipes.is_empty():
		_fail("FAIL walk-over did not teach a recipe")
	if not city.is_recipe_site_looted(site):
		_fail("FAIL walk-over did not mark the site looted")
	city.queue_free()
	print("OK walking onto a recipe collects it")


func _check_site_ids_and_chances() -> void:
	var a := RecipePickupPlacer.site_id(RecipePickupPlacer.SITE_ROOFTOP, Vector2i(2, -3), 4)
	var b := RecipePickupPlacer.site_id(RecipePickupPlacer.SITE_ROOFTOP, Vector2i(2, -3), 5)
	if a == b:
		_fail("FAIL two roofs on one tile share a site id")
	if a != RecipePickupPlacer.site_id(RecipePickupPlacer.SITE_ROOFTOP, Vector2i(2, -3), 4):
		_fail("FAIL site ids are not stable")
	## Landmarks that cost a climb always pay; the cheap sites are long odds.
	for kind: int in [
		RecipePickupPlacer.SITE_HILL_SUMMIT,
		RecipePickupPlacer.SITE_CASTLE_TOWER,
		RecipePickupPlacer.SITE_ARENA_TOWER,
		RecipePickupPlacer.SITE_GAZEBO,
		RecipePickupPlacer.SITE_FRACTAL_PEAK,
	]:
		if not RecipePickupPlacer.should_place(kind, 1234):
			_fail("FAIL landmark kind %d should always place" % kind)
	if RecipePickupPlacer.chance_pct(RecipePickupPlacer.SITE_ROOFTOP) >= 50:
		_fail("FAIL rooftops should be a long shot")
	if RecipePickupPlacer.chance_pct(RecipePickupPlacer.SITE_CHEST) >= 50:
		_fail("FAIL chest bonus should be a long shot")
	if RecipePickupPlacer.chance_pct(RecipePickupPlacer.SITE_ZOO_GAZEBO) != 50:
		_fail(
			"FAIL zoo-gazebo chance is %d, want 50"
			% RecipePickupPlacer.chance_pct(RecipePickupPlacer.SITE_ZOO_GAZEBO)
		)
	if RecipePickupPlacer.site_kind_name(RecipePickupPlacer.SITE_ZOO_GAZEBO) != "zoo-gazebo":
		_fail("FAIL SITE_ZOO_GAZEBO name is wrong")
	var hits := 0
	for seed_i in range(200):
		if RecipePickupPlacer.should_place(RecipePickupPlacer.SITE_ROOFTOP, seed_i * 7919):
			hits += 1
	if hits == 0 or hits > 60:
		_fail("FAIL rooftop roll landed %d/200 times" % hits)
	var zoo_hits := 0
	for seed_i in range(200):
		if RecipePickupPlacer.should_place(RecipePickupPlacer.SITE_ZOO_GAZEBO, seed_i * 7919):
			zoo_hits += 1
	if zoo_hits < 60 or zoo_hits > 140:
		_fail("FAIL zoo-gazebo roll landed %d/200 times (want ~50%%)" % zoo_hits)
	print("OK site ids are stable and unique, chances behave")


func _check_save_round_trip() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "RecipeWalker"
	add_child(walker)
	walker.set_physics_process(false)
	walker.set_process(false)
	await get_tree().process_frame
	if walker.get_proportions() == null:
		_fail("FAIL walker came up without proportions")
		walker.queue_free()
		return
	walker.global_position = Vector3(3.0, 2.0, 5.0)
	var inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	var loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	loadout.reset_adventure()
	loadout.learn_recipe(InventoryCatalog.RECIPE_TRAP)
	loadout.learn_recipe(
		InventoryCatalog.schematic_id_for_ability(AbilityRegistry.ID_DISTRICT_HOP)
	)
	var site := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_CRYPT, Vector2i(-4, 7), 1
	)
	loadout.mark_recipe_site_looted(site)

	var data := GameSaveScript.capture(
		WORLD_SEED, walker, inventory, "Recipes", null, 0, loadout
	)
	if data.is_empty():
		_fail("FAIL capture empty")
		walker.queue_free()
		return
	var restored: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	GameSaveScript.apply_loadout(restored, data)
	if not restored.knows_recipe(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL restored cookbook lost the trap recipe")
	if not restored.knows_ability_schematic(AbilityRegistry.ID_DISTRICT_HOP):
		_fail("FAIL restored cookbook lost the district hop schematic")
	if restored.knows_recipe(InventoryCatalog.RECIPE_BOOST_SPEED):
		_fail("FAIL restored cookbook invented a recipe")
	if not restored.is_recipe_site_looted(site):
		_fail("FAIL restored run forgot which sites it had emptied")

	## A sandbox save is never trimmed down to whatever happened to be in the file.
	var sandbox: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	sandbox.load_save_dict({"mode": PlayerLoadout.MODE_SANDBOX, "recipes": []})
	if not sandbox.knows_recipe(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL sandbox load must restore the whole cookbook")
	walker.queue_free()
	print("OK cookbook and looted sites survive a save")
