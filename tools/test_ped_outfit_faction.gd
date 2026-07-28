## Faction pools: hostile gear must be unreachable from a civilian or player spawn.
##
## The guarantee has three parts, and this test covers all three: pick() takes the pool as a
## required argument, the pools are built disjoint at load, and a tag that is not registered in
## TAG_FACTIONS rejects its entry instead of falling into the civilian pool.
extends Node

const FIXTURE := "res://tools/fixtures/catalog_faction.json"
const FIXTURE_UNKNOWN_TAG := "res://tools/fixtures/catalog_unknown_tag.json"
## Every script that dresses a civilian or the player. Each must name the civilian pool at every
## call site, so a hostile outfit can never be drawn there.
const CIVILIAN_SPAWN_SCRIPTS: Array[String] = [
	"res://scripts/city/city_walker.gd",
	"res://scripts/city/crowd_director.gd",
	"res://scripts/city/tetris_ped_npc.gd",
	"res://scripts/vehicles/vehicle_visual.gd",
]
const SEEDS := 4000

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_pools()
	_check_civilian_never_hostile()
	_check_hostile_pool()
	_check_unregistered_tag_is_rejected()
	_check_spawn_call_sites()
	_check_production_catalog()
	_finish()


func _check_pools() -> void:
	PedOutfitCatalog.reload_from(FIXTURE)
	var civilians := PedOutfitCatalog.count_for(PedOutfit.Faction.CIVILIAN)
	var hostiles := PedOutfitCatalog.count_for(PedOutfit.Faction.HOSTILE)
	if civilians != 2:
		_fail("fixture should hold 2 civilian outfits, got %d" % civilians)
	if hostiles != 2:
		_fail("fixture should hold 2 hostile outfits, got %d" % hostiles)


## The player and every civilian go through this exact call, so it is the guarantee under test.
func _check_civilian_never_hostile() -> void:
	PedOutfitCatalog.reload_from(FIXTURE)
	var hostile_ids: PackedStringArray = PackedStringArray()
	for outfit in PedOutfitCatalog.outfits_for_faction(PedOutfit.Faction.HOSTILE):
		hostile_ids.append(outfit.variant_id)
	if hostile_ids.is_empty():
		_fail("fixture has no hostile outfit — the civilian check would be vacuous")
		return
	var rng := RandomNumberGenerator.new()
	for seed_value in SEEDS:
		rng.seed = seed_value
		for female: bool in [false, true]:
			var outfit := PedOutfitCatalog.pick(rng, female, PedOutfit.Faction.CIVILIAN)
			if outfit.faction != PedOutfit.Faction.CIVILIAN:
				_fail("seed %d female=%s: civilian pick returned faction %d"
					% [seed_value, female, int(outfit.faction)])
				return
			if hostile_ids.has(outfit.variant_id):
				_fail("seed %d female=%s: civilian pick returned hostile outfit %s"
					% [seed_value, female, outfit.variant_id])
				return
			if outfit.female != female:
				_fail("seed %d: civilian pick returned wrong sex for %s" % [seed_value, outfit.variant_id])
				return


func _check_hostile_pool() -> void:
	PedOutfitCatalog.reload_from(FIXTURE)
	var rng := RandomNumberGenerator.new()
	for seed_value in SEEDS:
		rng.seed = seed_value
		for female: bool in [false, true]:
			var outfit := PedOutfitCatalog.pick(rng, female, PedOutfit.Faction.HOSTILE)
			if outfit.faction != PedOutfit.Faction.HOSTILE:
				_fail("seed %d: hostile pick returned faction %d" % [seed_value, int(outfit.faction)])
				return
			if not outfit.variant_id.begins_with("fixture_bandit"):
				_fail("seed %d: hostile pick returned %s" % [seed_value, outfit.variant_id])
				return


## A tag nobody classified must not reach a pool. Godot logs the rejection as an error; that is
## the point of the check, so the error line in the log is expected.
func _check_unregistered_tag_is_rejected() -> void:
	print("expect one PedOutfitCatalog error below: unregistered tag 'brigand'")
	PedOutfitCatalog.reload_from(FIXTURE_UNKNOWN_TAG)
	if PedOutfitCatalog.count() != 0:
		_fail("entry with an unregistered tag was accepted (%d entries)" % PedOutfitCatalog.count())
	if PedOutfitCatalog.count_for(PedOutfit.Faction.CIVILIAN) != 0:
		_fail("entry with an unregistered tag landed in the civilian pool")


## Structural half of the guarantee: no civilian spawn path may ask for anything but CIVILIAN.
func _check_spawn_call_sites() -> void:
	for script_path in CIVILIAN_SPAWN_SCRIPTS:
		var f := FileAccess.open(script_path, FileAccess.READ)
		if f == null:
			_fail("cannot read %s" % script_path)
			continue
		var lines := f.get_as_text().split("\n")
		var calls := 0
		for i in lines.size():
			var line: String = lines[i]
			if not (line.contains(".pick(") or line.contains(".random(")):
				continue
			if not (line.contains("PedOutfit") or line.contains("OutfitCatalog")):
				continue
			calls += 1
			if not line.contains("PedOutfit.Faction.CIVILIAN"):
				_fail(
					"%s:%d requests an outfit without naming the civilian pool: %s"
					% [script_path, i + 1, line.strip_edges()]
				)
		if calls == 0:
			_fail("%s has no outfit pick call — this check has gone stale" % script_path)


## The shipped catalog must classify cleanly, so no entry is silently dropped at boot.
func _check_production_catalog() -> void:
	PedOutfitCatalog.reload()
	var total := PedOutfitCatalog.count()
	if total <= 0:
		_fail("production catalog is empty")
		return
	var civilians := PedOutfitCatalog.count_for(PedOutfit.Faction.CIVILIAN)
	var hostiles := PedOutfitCatalog.count_for(PedOutfit.Faction.HOSTILE)
	if civilians + hostiles != total:
		_fail("production catalog: %d entries but %d pooled" % [total, civilians + hostiles])
	print("production catalog: %d civilian, %d hostile" % [civilians, hostiles])
	if hostiles <= 0:
		return
	## With a real hostile outfit shipped, run the leak check against the shipped data too.
	var hostile_ids: PackedStringArray = PackedStringArray()
	for outfit in PedOutfitCatalog.outfits_for_faction(PedOutfit.Faction.HOSTILE):
		hostile_ids.append(outfit.variant_id)
	var rng := RandomNumberGenerator.new()
	for seed_value in SEEDS:
		rng.seed = seed_value
		for female: bool in [false, true]:
			var picked := PedOutfitCatalog.pick(rng, female, PedOutfit.Faction.CIVILIAN)
			if hostile_ids.has(picked.variant_id):
				_fail(
					"seed %d: shipped civilian pick returned hostile outfit %s"
					% [seed_value, picked.variant_id]
				)
				return


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL ", msg)


func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: OK")
		get_tree().quit(0)
		return
	print("RESULT: FAIL (%d)" % _failures.size())
	get_tree().quit(1)
