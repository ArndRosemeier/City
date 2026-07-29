## The health and damage model: what one hit costs, how many of them a body survives, and when
## the run ends.
##
## Everything here is an arithmetic or state claim about combat rather than a check that some
## object exists. Three of the assertions are regressions the damage model could break in silence
## and that nothing else in the suite would notice:
##
## One — a skeleton still dies to one punch, and a fresh giant is still worth a thousand points.
## Tiering a roster is exactly the change that turns fodder into a four-punch chore and drops the
## award on the floor while every nav test stays green.
## Two — game over fires on the hit that empties the pool and not on the one before it. Off by one
## in that direction is a game nobody can play, and it is invisible until someone plays it.
## Three — the energy pool and the health pool never move each other. They are both hundred-point
## pools that regenerate, and the entire design rests on them not being the same number.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_damage_model.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const PlayerHealthHudScript := preload("res://scripts/city/player_health_hud.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
## Parked away from every district and from the other tests' tiles.
const TILE := Vector2i(-420, -420)
const ORIGIN := Vector3i(70000, 0, 70000)
const SX := 96
const SZ := 96

## Bodies are chosen by seed, so the seed is pinned and every spawn names its model.
const BODY_SEED := 20260728

## Tolerance on a derived health value. Tighter than any damage amount, so a wrong exponent or a
## wrong reference height cannot hide inside it.
const HEALTH_EPS := 0.05
## Tolerance on a regenerated amount, which accumulates over a few hundred fixed steps.
const REGEN_EPS := 0.3
const REGEN_STEP_SEC := 0.05

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

## CityRoot with the score ledger and the game-over screen replaced by counters. Never entered
## into the tree, so `_ready` never boots a world.
class TestCity:
	extends CityRoot
	var score: int = 0
	var game_over_calls: int = 0
	var game_over_reason: String = ""

	## `is_player_alive` and `get_player_target_position` are left as CityRoot wrote them —
	## the orb case below is a test of those, so stubbing them would test the stub.
	func bind_player(walker: CityWalker) -> void:
		_walker = walker

	func adjust_player_score(delta: int) -> void:
		score += delta

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		game_over_calls += 1
		game_over_reason = reason


## The real director, minus the CityRoot child lookup it does to find the terrain.
class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		_terrain = terrain
		_lod = lod


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	_test_damage_table()
	if _failed:
		_quit()
		return
	_test_player_pool_depletes_by_source()
	if _failed:
		_quit()
		return
	_test_regeneration_waits_then_stops_at_full()
	if _failed:
		_quit()
		return
	_test_tiers_across_the_three_families()
	if _failed:
		_quit()
		return
	_test_hud_follows_the_pool()
	if _failed:
		_quit()
		return
	if not _boot_nav():
		_quit()
		return
	await _test_weak_bodies_die_on_the_expected_hit()
	if _failed:
		_quit()
		return
	await _test_giant_takes_many_and_still_pays_a_thousand()
	if _failed:
		_quit()
		return
	await _test_pools_are_independent_and_game_over_is_not_early()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# The table every number comes from
# ---------------------------------------------------------------------------

## Every id has an amount, a target and a name, and the two that hurt the player also have a
## reason to print. A source that resolves to nothing would deal zero damage in play.
func _test_damage_table() -> void:
	print("damage sources:")
	for id: DamageSource.Id in DamageSource.all():
		var amount := DamageSource.amount(id)
		if amount <= 0.0:
			_fail("FAIL %s deals %.2f" % [DamageSource.source_name(id), amount])
			return
		var target := DamageSource.target(id)
		var reason := "-"
		if target == DamageSource.Target.PLAYER:
			reason = DamageSource.death_reason(id)
			if reason.is_empty() or reason == "?":
				_fail("FAIL %s can kill the player with no reason" % DamageSource.source_name(id))
				return
		print(
			"    %-14s %6.1f  %-8s %s"
			% [
				DamageSource.source_name(id),
				amount,
				"player" if target == DamageSource.Target.PLAYER else "creature",
				reason,
			]
		)
	## The pool is a hundred points and the orb takes a quarter, which is the whole of "survives
	## a few hits". If either number moves, the design moved with it.
	if not is_equal_approx(DamageSource.amount(DamageSource.Id.UNDEAD_ORB), 25.0):
		_fail("FAIL an orb takes %.1f, not a quarter of the pool" % DamageSource.amount(DamageSource.Id.UNDEAD_ORB))
		return


# ---------------------------------------------------------------------------
# The player pool
# ---------------------------------------------------------------------------

func _test_player_pool_depletes_by_source() -> void:
	var health := PlayerHealth.new()
	health.configure(100.0, 4.0, 6.0)
	if not is_equal_approx(health.current(), 100.0):
		_fail("FAIL a configured pool starts at %.2f" % health.current())
		return

	var taken := health.apply_damage(DamageSource.Id.UNDEAD_ORB)
	if not is_equal_approx(taken, 25.0) or not is_equal_approx(health.current(), 75.0):
		_fail("FAIL one orb took %.2f and left %.2f" % [taken, health.current()])
		return
	if not is_equal_approx(health.fraction(), 0.75):
		_fail("FAIL a pool at 75 of 100 reads %.3f full" % health.fraction())
		return
	health.apply_damage(DamageSource.Id.GIANT_DEBRIS)
	if not is_equal_approx(health.current(), 65.0):
		_fail("FAIL a strip of debris left %.2f" % health.current())
		return

	## The count that decides whether the design is "survives a few hits": four orbs, and the
	## fourth is the one that ends it.
	var orbs := PlayerHealth.new()
	orbs.configure(100.0, 4.0, 6.0)
	var deaths: Array[int] = []
	orbs.depleted.connect(func(source: DamageSource.Id) -> void: deaths.append(int(source)))
	for hit in range(1, 5):
		orbs.apply_damage(DamageSource.Id.UNDEAD_ORB)
		if hit < 4 and not deaths.is_empty():
			_fail("FAIL the pool emptied on orb %d of 4" % hit)
			return
		if hit < 4 and orbs.is_depleted():
			_fail("FAIL the pool reads empty at %.2f after orb %d" % [orbs.current(), hit])
			return
	if deaths.size() != 1 or deaths[0] != int(DamageSource.Id.UNDEAD_ORB):
		_fail("FAIL four orbs emitted %d depletions %s" % [deaths.size(), str(deaths)])
		return
	if not is_equal_approx(orbs.current(), 0.0):
		_fail("FAIL an emptied pool holds %.2f" % orbs.current())
		return

	## A hit on a body that is already down is not a second game over.
	if not is_equal_approx(orbs.apply_damage(DamageSource.Id.UNDEAD_ORB), 0.0):
		_fail("FAIL a fifth orb took points off a dead player")
		return
	if deaths.size() != 1:
		_fail("FAIL a hit after death emitted another depletion")
		return

	## Ten strips of a giant's facade, and the tenth is fatal — the slow way to die.
	var crush := PlayerHealth.new()
	crush.configure(100.0, 4.0, 6.0)
	for _strip in range(9):
		crush.apply_damage(DamageSource.Id.GIANT_DEBRIS)
	if crush.is_depleted() or not is_equal_approx(crush.current(), 10.0):
		_fail("FAIL nine strips of debris left %.2f" % crush.current())
		return
	crush.apply_damage(DamageSource.Id.GIANT_DEBRIS)
	if not crush.is_depleted():
		_fail("FAIL ten strips of debris left %.2f standing" % crush.current())
		return
	print(
		"player pool: 100 points, an orb takes 25 and the fourth converts you;"
		+ " ten strips of giant debris also do it"
	)


func _test_regeneration_waits_then_stops_at_full() -> void:
	var health := PlayerHealth.new()
	health.configure(100.0, 4.0, 6.0)
	health.apply_damage(DamageSource.Id.UNDEAD_ORB)
	if not is_equal_approx(health.seconds_until_regen(), 6.0):
		_fail("FAIL a fresh wound owes %.2f seconds of quiet" % health.seconds_until_regen())
		return

	## Nothing comes back inside the delay. This is what makes a fight a fight rather than a
	## queue of hits you walk off between them.
	_tick(health, 5.5)
	if not is_equal_approx(health.current(), 75.0):
		_fail("FAIL 5.5 s after the hit the pool is already at %.2f" % health.current())
		return

	## And then it does, at the stated rate. Two seconds past the delay is eight points.
	_tick(health, 2.5)
	if absf(health.current() - 83.0) > REGEN_EPS:
		_fail("FAIL 8 s after the hit the pool is at %.2f, not about 83" % health.current())
		return

	## A second hit puts the whole delay back, so sustained pressure never heals.
	health.apply_damage(DamageSource.Id.GIANT_DEBRIS)
	var after_hit := health.current()
	_tick(health, 5.5)
	if not is_equal_approx(health.current(), after_hit):
		_fail("FAIL the delay did not restart: %.2f became %.2f" % [after_hit, health.current()])
		return

	## Left alone it fills and stops. A pool that overshoots its own maximum is a pool with no
	## maximum.
	_tick(health, 60.0)
	if not is_equal_approx(health.current(), 100.0):
		_fail("FAIL a minute of quiet left the pool at %.2f" % health.current())
		return
	if not is_equal_approx(health.fraction(), 1.0):
		_fail("FAIL a full pool reads %.3f" % health.fraction())
		return

	## Regeneration never revives. Death is the one state the delay does not run out of.
	var dead := PlayerHealth.new()
	dead.configure(100.0, 4.0, 6.0)
	for _orb in range(4):
		dead.apply_damage(DamageSource.Id.UNDEAD_ORB)
	_tick(dead, 60.0)
	if not is_equal_approx(dead.current(), 0.0):
		_fail("FAIL a dead player regenerated to %.2f" % dead.current())
		return
	print(
		"regeneration: nothing for 6 s after a hit, then 4/s to the cap and no further;"
		+ " a new hit restarts the wait and death ends it"
	)


func _tick(health: PlayerHealth, seconds: float) -> void:
	var steps := int(round(seconds / REGEN_STEP_SEC))
	for _step in range(steps):
		health.tick(REGEN_STEP_SEC)


# ---------------------------------------------------------------------------
# Enemy tiers off the catalogue
# ---------------------------------------------------------------------------

## The tier table in full, then the claims that make it a design rather than a formula: the
## families sit in bands, headgear does not buy toughness, and the biggest blob is still weaker
## than the smallest Big monster.
func _test_tiers_across_the_three_families() -> void:
	print("creature tiers:")
	print(
		"    %-24s %-8s %6s %7s %5s %5s %5s"
		% ["model", "family", "height", "health", "fist", "laser", "stomp"]
	)
	var band_low: Dictionary[int, float] = {}
	var band_high: Dictionary[int, float] = {}
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if not entry.is_spawnable():
			continue
		var health := CreatureHealth.for_entry(entry)
		if health <= 0.0:
			_fail("FAIL %s has %.2f health" % [entry.id, health])
			return
		var family := int(entry.family)
		band_low[family] = minf(band_low.get(family, INF), health)
		band_high[family] = maxf(band_high.get(family, -INF), health)
		print(
			"    %-24s %-8s %6.3f %7.2f %5d %5d %5d"
			% [
				entry.id,
				CreatureCatalog.family_name(entry.family).trim_prefix("quaternius_"),
				entry.collider_height,
				health,
				CreatureHealth.hits_to_kill(health, DamageSource.Id.PLAYER_MELEE),
				CreatureHealth.hits_to_kill(health, DamageSource.Id.PLAYER_LASER),
				CreatureHealth.hits_to_kill(health, DamageSource.Id.PLAYER_STOMP),
			]
		)

	## Spot checks against specific bodies, computed by hand from the catalogue's own heights.
	var expected: Dictionary[String, float] = {
		"kaykit/Skeleton_Minion": 34.0,
		## The mage measures 2.630 units because of the hat and still has the shared body's
		## health. If this ever equals 41.3, the tier is being read off `measured_height`.
		"kaykit/Skeleton_Mage": 34.0,
		"big/Frog": 92.64,
		"big/Cactoro": 136.02,
		"blob/GreenBlob": 39.54,
		"blob/Mushnub_Evolved": 61.01,
	}
	for id: String in expected:
		var entry := CreatureCatalog.by_id(id)
		var got := CreatureHealth.for_entry(entry)
		if absf(got - expected[id]) > HEALTH_EPS:
			_fail("FAIL %s has %.2f health, expected %.2f" % [id, got, expected[id]])
			return

	## The blob-in-a-tall-hat check. `Mushnub_Evolved` is the tallest spawnable body in the game
	## at 4.411 units — taller than every Quaternius Big monster — and most of that is mushroom
	## cap. It must not outlast the shortest Big monster, which is a real 2.695-unit body.
	var tallest_blob := CreatureHealth.for_entry(CreatureCatalog.by_id("blob/Mushnub_Evolved"))
	var smallest_big := CreatureHealth.for_entry(CreatureCatalog.by_id("big/Frog"))
	if tallest_blob >= smallest_big:
		_fail(
			"FAIL the tallest blob has %.2f health against the smallest Big monster's %.2f"
			% [tallest_blob, smallest_big]
		)
		return
	var blob := int(CreatureCatalog.Family.QUATERNIUS_BLOB)
	var big := int(CreatureCatalog.Family.QUATERNIUS_BIG)
	var kaykit := int(CreatureCatalog.Family.KAYKIT_SKELETON)
	if band_high[blob] >= band_low[big]:
		_fail(
			"FAIL the blob band tops out at %.2f and the Big band starts at %.2f, so they overlap"
			% [band_high[blob], band_low[big]]
		)
		return
	if not is_equal_approx(band_low[kaykit], band_high[kaykit]):
		_fail(
			"FAIL the skeletons span %.2f..%.2f, so a dressing changed a body"
			% [band_low[kaykit], band_high[kaykit]]
		)
		return
	if CreatureHealth.hits_to_kill(band_high[kaykit], DamageSource.Id.PLAYER_MELEE) != 1:
		_fail("FAIL a skeleton at %.2f does not fall to one punch" % band_high[kaykit])
		return
	if CreatureHealth.hits_to_kill(band_high[blob], DamageSource.Id.PLAYER_MELEE) != 2:
		_fail("FAIL the toughest blob at %.2f is not two punches" % band_high[blob])
		return

	## And growth. A giant is tougher than the body it grew out of without being ten times so.
	var giant := CreatureHealth.for_scale(
		CreatureCatalog.by_id("kaykit/Skeleton_Mage"), UndeadUnit.GIANT_SCALE_TARGET
	)
	if absf(giant - 240.70) > HEALTH_EPS:
		_fail("FAIL a giant grown off a skeleton has %.2f health, expected about 240.7" % giant)
		return
	if CreatureHealth.hits_to_kill(giant, DamageSource.Id.PLAYER_BLAST) != 2:
		_fail(
			"FAIL a giant takes %d charged blasts"
			% CreatureHealth.hits_to_kill(giant, DamageSource.Id.PLAYER_BLAST)
		)
		return
	if CreatureHealth.hits_to_kill(giant, DamageSource.Id.PLAYER_MELEE) != 8:
		_fail(
			"FAIL a giant takes %d punches"
			% CreatureHealth.hits_to_kill(giant, DamageSource.Id.PLAYER_MELEE)
		)
		return
	print(
		(
			"    bands: skeletons %.1f, blobs %.1f-%.1f, Big monsters %.1f-%.1f,"
			+ " a 10x giant off a skeleton %.1f"
		)
		% [band_high[kaykit], band_low[blob], band_high[blob], band_low[big], band_high[big], giant]
	)


# ---------------------------------------------------------------------------
# The bar
# ---------------------------------------------------------------------------

## The HUD claim worth asserting is that the bar is bound to the pool it says it is and that it
## draws the fraction, plus that it lives where `ui_layers.gd` says the HUD band is — a health
## bar above the inventory modal would be the same bug the layer table was written to end.
func _test_hud_follows_the_pool() -> void:
	if UiLayers.HUD_HEALTH < UiLayers.HUD_MIN or UiLayers.HUD_HEALTH > UiLayers.HUD_MAX:
		_fail("FAIL the health bar is on layer %d, outside the HUD band" % UiLayers.HUD_HEALTH)
		return
	if UiLayers.HUD_HEALTH == UiLayers.HUD_ENERGY:
		_fail("FAIL the health bar shares layer %d with the energy bar" % UiLayers.HUD_HEALTH)
		return
	if UiLayers.HUD_HEALTH >= UiLayers.MODAL_INVENTORY:
		_fail("FAIL the health bar draws over the inventory modal")
		return

	var hud: CanvasLayer = PlayerHealthHudScript.new()
	add_child(hud)
	if hud.layer != UiLayers.HUD_HEALTH:
		_fail("FAIL the bar put itself on layer %d" % hud.layer)
		hud.queue_free()
		return
	for fraction: float in [1.0, 0.62, 0.25, 0.0]:
		hud.call("show_preview", 100.0 * fraction, 100.0)
		var drawn := float(hud.call("fill_fraction"))
		if absf(drawn - fraction) > 0.001:
			_fail("FAIL a pool at %.2f drew a bar %.3f full" % [fraction, drawn])
			hud.queue_free()
			return
	hud.queue_free()
	print(
		"hud: the wound bar is layer %d, the energy bar %d, the inventory modal %d"
		% [UiLayers.HUD_HEALTH, UiLayers.HUD_ENERGY, UiLayers.MODAL_INVENTORY]
	)


# ---------------------------------------------------------------------------
# Live bodies
# ---------------------------------------------------------------------------

## Hits are dealt through the director, exactly as `CityRoot._apply_agent_hit` deals them, so
## what is measured is the whole path: the unit's pool, the death it triggers and the score the
## director credits for it.
func _test_weak_bodies_die_on_the_expected_hit() -> void:
	## One punch. Combat-table minion hp_mult 0.5 → 17 pool; still dies to the fist.
	var skeleton := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(20, 1, 20)), "kaykit/Skeleton_Minion")
	if skeleton == null:
		return
	var minion_stats: RefCounted = skeleton.combat_stats()
	if minion_stats == null:
		_fail("FAIL spawned minion has no combat stats")
		return
	var minion_hp_mult := float(minion_stats.get("hp_mult"))
	var minion_hp: float = 34.0 * minion_hp_mult
	if absf(skeleton.health_max() - minion_hp) > HEALTH_EPS:
		_fail(
			"FAIL a spawned skeleton has %.2f health, want %.2f (hp_mult %.2f)"
			% [skeleton.health_max(), minion_hp, minion_hp_mult]
		)
		return
	_city.score = 0
	if not _director.damage_unit(skeleton, DamageSource.Id.PLAYER_MELEE):
		_fail("FAIL the director refused a punch")
		return
	if skeleton.is_alive():
		_fail("FAIL a punched skeleton has %.2f health left" % skeleton.health())
		return
	if _city.score != UndeadUnit.HIT_SCORE_NORMAL:
		_fail("FAIL a killed skeleton paid %d, not %d" % [_city.score, UndeadUnit.HIT_SCORE_NORMAL])
		return
	## And it only pays once, however many shots arrive after it.
	_director.damage_unit(skeleton, DamageSource.Id.PLAYER_MELEE)
	if _city.score != UndeadUnit.HIT_SCORE_NORMAL:
		_fail("FAIL a corpse paid another %d" % (_city.score - UndeadUnit.HIT_SCORE_NORMAL))
		return
	await _settle(skeleton)

	## Warrior: tougher pool + armor, so the first laser must leave it standing.
	var chipped := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(24, 1, 20)), "kaykit/Skeleton_Warrior")
	if chipped == null:
		return
	var war_stats: RefCounted = chipped.combat_stats()
	if war_stats == null:
		_fail("FAIL warrior has no combat stats")
		return
	var war_hp_mult := float(war_stats.get("hp_mult"))
	var war_armor := float(war_stats.get("armor_mult"))
	var war_hp: float = 34.0 * war_hp_mult
	if absf(chipped.health_max() - war_hp) > HEALTH_EPS:
		_fail("FAIL warrior has %.2f health, want %.2f" % [chipped.health_max(), war_hp])
		return
	_city.score = 0
	_director.damage_unit(chipped, DamageSource.Id.PLAYER_LASER)
	if not chipped.is_alive():
		_fail("FAIL one laser dart killed a warrior outright")
		return
	var after_one: float = war_hp - DamageSource.amount(DamageSource.Id.PLAYER_LASER) / war_armor
	if absf(chipped.health() - after_one) > HEALTH_EPS:
		_fail("FAIL one laser dart left %.2f, want %.2f" % [chipped.health(), after_one])
		return
	if _city.score != 0:
		_fail("FAIL a surviving warrior already paid %d" % _city.score)
		return
	var darts := _hits_to_kill_armored(
		chipped.health_max(), DamageSource.Id.PLAYER_LASER, war_armor
	)
	if darts < 2:
		_fail("FAIL a warrior falls to %d laser darts" % darts)
		return
	for _i in range(darts - 1):
		_director.damage_unit(chipped, DamageSource.Id.PLAYER_LASER)
	if chipped.is_alive():
		_fail("FAIL %d laser darts left a warrior standing at %.2f" % [darts, chipped.health()])
		return
	if _city.score != UndeadUnit.HIT_SCORE_NORMAL:
		_fail("FAIL the finishing dart paid %d" % _city.score)
		return
	await _settle(chipped)

	## A mid-size monster is several hits; punches count armour from the combat table.
	var monster := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(28, 1, 20)), "big/Frog")
	if monster == null:
		return
	var frog_stats: RefCounted = monster.combat_stats()
	if frog_stats == null:
		_fail("FAIL Frog has no combat stats")
		return
	var frog_armor := float(frog_stats.get("armor_mult"))
	var punches := _hits_to_kill_armored(
		monster.health_max(), DamageSource.Id.PLAYER_MELEE, frog_armor
	)
	if punches < 3:
		_fail("FAIL a Big monster falls to %d punches" % punches)
		return
	_city.score = 0
	for hit in range(punches):
		if not monster.is_alive():
			_fail("FAIL the monster died on punch %d of %d" % [hit, punches])
			return
		_director.damage_unit(monster, DamageSource.Id.PLAYER_MELEE)
	if monster.is_alive():
		_fail("FAIL %d punches left a monster at %.2f" % [punches, monster.health()])
		return
	if _city.score != UndeadUnit.HIT_SCORE_NORMAL:
		_fail("FAIL a killed monster paid %d" % _city.score)
		return
	await _settle(monster)

	## The area attack the stomp became: every body in the crater, one hit each.
	var swept: Array[UndeadUnit] = []
	for i in range(3):
		var body := _spawn(
			UndeadUnit.Role.MINION, _w(Vector3i(40 + i * 2, 1, 40)), "kaykit/Skeleton_Minion"
		)
		if body == null:
			return
		swept.append(body)
	var far := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(70, 1, 40)), "kaykit/Skeleton_Minion")
	if far == null:
		return
	_city.score = 0
	var reached := _director.damage_units_in_sphere(
		_w(Vector3i(42, 1, 40)), 4.0, DamageSource.Id.PLAYER_STOMP
	)
	if reached != swept.size():
		_fail("FAIL one stomp reached %d of %d bodies" % [reached, swept.size()])
		return
	for body: UndeadUnit in swept:
		if body.is_alive():
			_fail("FAIL a stomped skeleton survived at %.2f" % body.health())
			return
	if not far.is_alive():
		_fail("FAIL a skeleton fifteen metres away died to the stomp")
		return
	if _city.score != UndeadUnit.HIT_SCORE_NORMAL * swept.size():
		_fail("FAIL three stomped skeletons paid %d" % _city.score)
		return
	for body: UndeadUnit in swept:
		await _settle(body)
	await _settle(far)
	print(
		(
			"live bodies: minion dies to 1 punch, warrior to %d darts, Frog to %d punches,"
			+ " and one stomp cleared 3 in its crater — %d apiece, once each"
		)
		% [darts, punches, UndeadUnit.HIT_SCORE_NORMAL]
	)


func _test_giant_takes_many_and_still_pays_a_thousand() -> void:
	var giant := _spawn(UndeadUnit.Role.GIANT, _w(Vector3i(48, 1, 60)), "kaykit/Skeleton_Mage")
	if giant == null:
		return
	## What `_tick_growing` does on every frame of the grow pad, in one step.
	giant.character_scale = UndeadUnit.GIANT_SCALE_TARGET
	giant._apply_scale()
	if not giant.is_giant():
		_fail("FAIL a grown body does not read as a giant")
		return
	if absf(giant.health_max() - 240.70) > HEALTH_EPS:
		_fail("FAIL a grown giant has %.2f health" % giant.health_max())
		return

	## Growing must not heal: a giant worn down to a third and then finished growing is still
	## worn down, or a body on a pad is invulnerable by standing there.
	var wounded := _spawn(UndeadUnit.Role.GIANT, _w(Vector3i(52, 1, 60)), "kaykit/Skeleton_Mage")
	if wounded == null:
		return
	_city.score = 0
	_director.damage_unit(wounded, DamageSource.Id.PLAYER_LASER)
	var fraction_before := wounded.health_fraction()
	wounded.character_scale = UndeadUnit.GIANT_SCALE_TARGET
	wounded._apply_scale()
	if absf(wounded.health_fraction() - fraction_before) > 0.001:
		_fail(
			"FAIL growing took a body from %.3f to %.3f of its pool"
			% [fraction_before, wounded.health_fraction()]
		)
		return
	await _settle(wounded)

	_city.score = 0
	var blasts := 0
	while giant.is_alive() and blasts < 12:
		_director.damage_unit(giant, DamageSource.Id.PLAYER_BLAST)
		blasts += 1
	if giant.is_alive():
		_fail("FAIL a giant survived %d charged blasts" % blasts)
		return
	if blasts != 2:
		_fail("FAIL a giant fell to %d charged blasts" % blasts)
		return
	if _city.score != UndeadUnit.HIT_SCORE_GIANT:
		_fail("FAIL a killed giant paid %d, not %d" % [_city.score, UndeadUnit.HIT_SCORE_GIANT])
		return
	await _settle(giant)
	print(
		"giant: %.0f health, 2 charged blasts, %d points — and growing keeps its wounds"
		% [240.7, UndeadUnit.HIT_SCORE_GIANT]
	)


# ---------------------------------------------------------------------------
# The two pools, and the screen that ends the run
# ---------------------------------------------------------------------------

## A real walker, because the claim is about the walker's two pools and not about
## `PlayerHealth` in isolation. Physics is off, so nothing regenerates behind the assertions.
func _test_pools_are_independent_and_game_over_is_not_early() -> void:
	var walker := CityWalker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame

	if not walker.has_action_animation(walker.hit_react_anim):
		_fail("FAIL the walker has no '%s' clip to flinch with" % walker.hit_react_anim)
		walker.queue_free()
		return
	if not is_equal_approx(walker.get_health(), 100.0) or not is_equal_approx(walker.get_energy(), 100.0):
		_fail(
			"FAIL a fresh walker has %.2f health and %.2f energy"
			% [walker.get_health(), walker.get_energy()]
		)
		walker.queue_free()
		return
	## Every change the bar would have drawn, from before the first hit — a pool that moves
	## without telling the HUD is a bar that lies.
	var reports: Array[float] = []
	walker.health_changed.connect(
		func(current: float, _maximum: float) -> void: reports.append(current)
	)

	## Spending energy is not an injury. Twenty points on a charged blast, five times over,
	## empties the ability budget and must leave the pool that ends the run untouched.
	for _shot in range(5):
		if not walker.try_spend_energy(walker.energy_cost_blast):
			_fail("FAIL the walker could not afford a blast at %.2f energy" % walker.get_energy())
			walker.queue_free()
			return
	if not is_equal_approx(walker.get_energy(), 0.0):
		_fail("FAIL five blasts left %.2f energy" % walker.get_energy())
		walker.queue_free()
		return
	if not is_equal_approx(walker.get_health(), 100.0):
		_fail("FAIL emptying the energy pool cost %.2f health" % (100.0 - walker.get_health()))
		walker.queue_free()
		return
	if walker.is_health_depleted():
		_fail("FAIL an empty energy pool reads as a dead player")
		walker.queue_free()
		return

	## And the reverse: being hit does not refund or spend the ability budget.
	walker.take_damage(DamageSource.Id.UNDEAD_ORB)
	if not is_equal_approx(walker.get_energy(), 0.0):
		_fail("FAIL an orb moved the energy pool to %.2f" % walker.get_energy())
		walker.queue_free()
		return
	if not is_equal_approx(walker.get_health(), 75.0):
		_fail("FAIL an orb left %.2f health" % walker.get_health())
		walker.queue_free()
		return

	## The whole game-over path, wired the way CityRoot wires it: the orb drains the pool, the
	## pool reports it empty, and that is the only thing that shows the screen.
	_city.bind_player(walker)
	walker.health_depleted.connect(_city._on_player_health_depleted)
	var chest := _city.get_player_target_position()
	if not chest.is_finite():
		_fail("FAIL the city cannot say where the player is standing")
		walker.queue_free()
		return

	## An orb that lands nowhere near the player hurts nobody — the near-miss half of "not
	## before".
	_city.game_over_calls = 0
	if _city.try_orb_hit_player(chest + Vector3(20.0, 0.0, 0.0), 0.5):
		_fail("FAIL an orb twenty metres away hit the player")
		walker.queue_free()
		return
	if not is_equal_approx(walker.get_health(), 75.0):
		_fail("FAIL a missed orb took %.2f" % (75.0 - walker.get_health()))
		walker.queue_free()
		return

	for orb in range(2, 4):
		if not _city.try_orb_hit_player(chest, 0.5):
			_fail("FAIL orb %d missed a player standing on it" % orb)
			walker.queue_free()
			return
		if _city.game_over_calls != 0:
			_fail("FAIL the run ended on orb %d of 4, at %.2f health" % [orb, walker.get_health()])
			walker.queue_free()
			return
	if not is_equal_approx(walker.get_health(), 25.0):
		_fail("FAIL three orbs left %.2f health" % walker.get_health())
		walker.queue_free()
		return

	_city.try_orb_hit_player(chest, 0.5)
	if _city.game_over_calls != 1:
		_fail("FAIL the fourth orb showed the game-over screen %d times" % _city.game_over_calls)
		walker.queue_free()
		return
	if _city.game_over_reason != DamageSource.death_reason(DamageSource.Id.UNDEAD_ORB):
		_fail("FAIL the screen blamed '%s'" % _city.game_over_reason)
		walker.queue_free()
		return
	if reports.size() != 4:
		_fail("FAIL four orbs told the HUD %d times: %s" % [reports.size(), str(reports)])
		walker.queue_free()
		return
	if not is_equal_approx(walker.get_energy(), 0.0):
		_fail("FAIL dying moved the energy pool to %.2f" % walker.get_energy())
		walker.queue_free()
		return
	walker.queue_free()
	await get_tree().process_frame
	print(
		(
			"pools: five blasts spent 100 energy for 0 health, and four orbs spent 100 health"
			+ " for 0 energy; the screen appeared once, on the fourth"
		)
	)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Hits of `source` needed to empty `health` when each hit deals amount/armor_mult.
func _hits_to_kill_armored(health: float, source: DamageSource.Id, armor_mult: float) -> int:
	var per := DamageSource.amount(source) / maxf(armor_mult, 0.001)
	if per <= 0.0:
		_fail("FAIL armored hits_to_kill got non-positive damage")
		return 0
	var left := health
	var hits := 0
	while not CreatureHealth.is_dead(left):
		left -= per
		hits += 1
	return hits


func _boot_nav() -> bool:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		return false
	if not _nav.register_district(TILE, _bake_tile()):
		_fail("FAIL NavService refused the test tile")
		return false
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	_director = TestDirector.new()
	_director.name = "UndeadInvasion"
	add_child(_director)
	_director.bind(_city, _terrain, NavLod.for_collision_view(48, VOXEL_SIZE))
	return true


func _spawn(role: UndeadUnit.Role, at: Vector3, body_id: String) -> UndeadUnit:
	var unit := _director._spawn_unit(role, at, BODY_SEED, body_id)
	if unit == null:
		_fail("FAIL the director refused to spawn %s at %.1f,%.1f" % [body_id, at.x, at.z])
		return null
	## Nothing here is a navigation test; the bodies stand where they are put.
	unit.set_physics_process(false)
	return unit


## A killed body plays its death clip and frees itself 1.6 s later. Nothing here waits that
## long, so it is dropped deliberately instead of accumulating across cases. A body that died
## here is already off the roster; one still standing has to be taken off it before it leaves
## the tree, or the director's registered-on-exit alarm fires.
func _settle(unit: UndeadUnit) -> void:
	await get_tree().process_frame
	if is_instance_valid(unit):
		if _director._units.has(unit):
			_director.unregister_unit(unit)
		unit.queue_free()
	await get_tree().process_frame


func _bake_tile() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		ORIGIN,
		SX,
		SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test tile")
		return null
	return bake


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _quit() -> void:
	if _director != null and is_instance_valid(_director):
		_director.clear_all()
	NavService.reset()
	if _city != null:
		## Never entered the tree, so nothing else will free it.
		_city.free()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
