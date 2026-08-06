## Sanity-check build recipes: every catalog entry has voxels, ids are unique, and
## rotation keeps the recipe front pointing at the player.
##
## Run: powershell -File tools\run_test.ps1 test_build_catalog -KeepLog
extends Node

const BuildCatalogScript := preload("res://scripts/city/build_catalog.gd")
const BuildPlacerScript := preload("res://scripts/city/build_placer.gd")


func _ready() -> void:
	var failed := false
	var recipes: Array = BuildCatalogScript.all()
	if recipes.size() < 8:
		push_error("FAIL expected at least 8 recipes, got %d" % recipes.size())
		failed = true
	var seen: Dictionary = {}
	for r: Variant in recipes:
		var recipe: BuildCatalog.Recipe = r
		if recipe.id == "" or seen.has(recipe.id):
			push_error("FAIL bad/duplicate recipe id '%s'" % recipe.id)
			failed = true
		seen[recipe.id] = true
		if recipe.voxels.size() < 4 or recipe.voxels.size() % 4 != 0:
			push_error("FAIL recipe %s has invalid voxel payload" % recipe.id)
			failed = true
			continue
		var n := recipe.voxels.size() / 4
		print("OK recipe %-10s  %4d voxels  (%s)" % [recipe.id, n, recipe.display_name])

	## Front voxel of a 1×1×1 at (0,0,-1) must land toward +Z when facing the player north of it.
	var front := BuildPlacerScript._rotate(Vector3i(0, 0, -1), 0)
	if front != Vector3i(0, 0, 1):
		push_error("FAIL rotate toward +Z: got %s" % front)
		failed = true
	else:
		print("OK rotation maps recipe front toward the player")

	var by := BuildCatalogScript.by_id("cottage")
	if by == null or by.id != "cottage":
		push_error("FAIL by_id(cottage)")
		failed = true
	if by != null and by.requires_recipe:
		push_error("FAIL cottage must remain a free starter stamp")
		failed = true

	var discovery := BuildCatalogScript.discovery_recipes()
	if discovery.size() < 6:
		push_error("FAIL expected pool/hot_tub/statues as discovery recipes, got %d" % discovery.size())
		failed = true
	else:
		print("OK %d discovery build recipes" % discovery.size())
	for id in ["pool", "hot_tub", "dog", "cat", "duck", "elephant"]:
		var stamp := BuildCatalogScript.by_id(id)
		if stamp == null or not stamp.requires_recipe:
			push_error("FAIL '%s' should require recipe discovery" % id)
			failed = true
	for id in ["dog", "cat", "duck", "elephant"]:
		var statue := BuildCatalogScript.by_id(id)
		if (
			statue == null
			or statue.consume_item != "gem_quartz"
			or statue.consume_count != 1
		):
			push_error("FAIL '%s' should cost 1 quartz to place" % id)
			failed = true
	var pool := BuildCatalogScript.by_id("pool")
	if pool == null or pool.consume_item != "gem_sapphire" or pool.consume_count != 1:
		push_error("FAIL pool should cost 1 sapphire to place")
		failed = true
	var tub := BuildCatalogScript.by_id("hot_tub")
	if tub != null and not tub.consume_item.is_empty():
		push_error("FAIL hot tub should not spend gems on place")
		failed = true

	print("RESULT: %s" % ("OK" if not failed else "FAIL"))
	get_tree().quit(1 if failed else 0)
