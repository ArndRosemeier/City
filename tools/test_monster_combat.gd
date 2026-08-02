## Combat-table wiring on live units + N-key summon roster (no CityTargeting soft-aim).
##
## Run: powershell -File tools/run_test.ps1 test_monster_combat -KeepLog
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
const TILE := Vector2i(-421, -421)
const ORIGIN := Vector3i(71000, 0, 71000)
const SX := 96
const SZ := 96
const BODY_SEED := 20260729
const HEALTH_EPS := 0.05
const BODY_CLEARANCE_M := 0.06
## Summon may snap onto a standable span within this of the cached aim.
const SUMMON_SNAP_SLACK_M := 8.0

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot

	## Combat kit damage goes through CityRoot; this CityRoot has to be in the tree — but it
	## must not boot a city to get there.
	func _ready() -> void:
		pass

	func bind_player(walker: CharacterBody3D) -> void:
		_walker = walker

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		pass

	## Harness binds a MonsterRoster; skip CityRoot.setup().
	func _ensure_monster_roster() -> void:
		if _monsters == null or not is_instance_valid(_monsters):
			push_error("TestCity: MonsterRoster not bound before summon")
			assert(false, "TestCity: no MonsterRoster")

	func bind_monsters(roster: MonsterRoster) -> void:
		_monsters = roster


class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		var monsters := MonsterRoster.new()
		monsters.name = "MonsterRoster"
		add_child(monsters)
		monsters.setup(city, terrain, lod)
		_roster = monsters
		if city is TestCity:
			(city as TestCity).bind_monsters(monsters)


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	_city.name = "TestCity"
	add_child(_city)
	_test_summon_list()
	if _failed:
		_quit()
		return
	if not _boot_nav():
		_quit()
		return
	_test_resolve_on_spawn()
	if _failed:
		_quit()
		return
	_test_summon_at_aim()
	if _failed:
		_quit()
		return
	await _test_freed_unit_aim_query()
	if _failed:
		_quit()
		return
	await _test_melee_hurts_player()
	if _failed:
		_quit()
		return
	await _test_factions_and_mob_melee()
	if _failed:
		_quit()
		return
	await _test_global_cooldown()
	if _failed:
		_quit()
		return
	_test_crumble_stride_closes_in()
	if _failed:
		_quit()
		return
	await _test_player_minion_power()
	_quit()


func _test_summon_list() -> void:
	var labels: PackedStringArray = MonsterSummonPanelScript.list_labels()
	if labels.is_empty() or labels[0] != "Random":
		_fail("FAIL summon list does not start with Random")
		return
	var ids: PackedStringArray = MonsterSummonPanelScript.summonable_ids()
	if ids.is_empty():
		_fail("FAIL summonable_ids is empty")
		return
	if not ids.has("kaykit/Skeleton_Minion"):
		_fail("FAIL summonable_ids missing kaykit/Skeleton_Minion")
		return
	## Panel builds and claims the modal layer.
	var panel: CanvasLayer = MonsterSummonPanelScript.new()
	add_child(panel)
	if panel.layer != UiLayers.MODAL_MONSTER_SUMMON:
		_fail("FAIL summon panel layer %d" % panel.layer)
		panel.queue_free()
		return
	panel.call("open_panel")
	if not bool(panel.call("is_open")):
		_fail("FAIL summon panel did not open")
		panel.queue_free()
		return
	if str(panel.call("selected_monster_id")) != "":
		_fail("FAIL default selection is not Random")
		panel.queue_free()
		return
	panel.call("close_panel")
	panel.queue_free()
	print("summon UI: Random first, %d spawnable bodies" % ids.size())


func _test_resolve_on_spawn() -> void:
	var unit := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(20, 1, 20)), "kaykit/Skeleton_Minion")
	if unit == null:
		return
	var stats: RefCounted = unit.combat_stats()
	if stats == null:
		_fail("FAIL unit has no combat stats")
		return
	## Body row overrides the `minion` template's 0.5 — see kaykit/Skeleton_Minion in
	## gamedata.json and tools/fixtures/combat_effective_stats.json.
	var hp_mult := float(stats.get("hp_mult"))
	if absf(hp_mult - 0.6471) > 0.001:
		_fail("FAIL minion hp_mult %.4f want 0.6471" % hp_mult)
		return
	var attacks: PackedStringArray = stats.get("attacks") as PackedStringArray
	if not _has_str(attacks, "melee"):
		_fail("FAIL minion attacks missing melee: %s" % str(attacks))
		return
	## Buildings are not targets: nothing in a kit may aim at fabric any more.
	for gone: String in ["nibble", "debris"]:
		if _has_str(attacks, gone):
			_fail("FAIL minion still carries the building attack '%s'" % gone)
			return
	if not bool(unit.combat().call("hunts_living")):
		_fail("FAIL a minion with melee and %.0f m aggro does not hunt" % float(stats.get("aggro_range_m")))
		return
	var want_hp: float = CreatureHealth.for_scale(unit.creature_entry(), 1.0) * hp_mult
	if absf(unit.health_max() - want_hp) > HEALTH_EPS:
		_fail("FAIL health_max %.2f want %.2f" % [unit.health_max(), want_hp])
		return
	var mage := _spawn(UndeadUnit.Role.MAGE, _w(Vector3i(24, 1, 20)), "kaykit/Skeleton_Mage")
	if mage == null:
		return
	var mage_stats: RefCounted = mage.combat_stats()
	if mage_stats == null:
		_fail("FAIL mage has no combat stats")
		return
	var mage_attacks: PackedStringArray = mage_stats.get("attacks") as PackedStringArray
	if not _has_str(mage_attacks, "orb_convert"):
		_fail("FAIL mage missing orb_convert")
		return
	if not _has_str(mage_attacks, "eye_laser"):
		_fail("FAIL mage missing eye_laser")
		return
	_despawn(unit)
	_despawn(mage)
	print(
		"resolve: minion hp_mult=%.2f attacks=%s; mage attacks=%s"
		% [hp_mult, str(attacks), str(mage_attacks)]
	)


## CityRoot.summon_monster_at_aim must place near cursor aim (meteor Dictionary path), never at feet.
func _test_summon_at_aim() -> void:
	var aim_pos := _w(Vector3i(40, 1, 28))
	var stub := AimStub.new()
	stub.name = "AimStub"
	## Bound as the player, so it has to be in the tree: CityRoot reads its global position and
	## every unit that ticks asks for it.
	add_child(stub)
	stub.set_physics_process(false)
	_city.bind_player(stub)
	_city._undead = _director
	_city._booting = false
	_city._game_over = false
	_city._summon_aim = {"point": aim_pos, "normal": Vector3.UP, "did_hit": true}
	var unit := _city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL summon_monster_at_aim returned null on hit")
		return
	var expected := aim_pos + Vector3.UP * BODY_CLEARANCE_M
	if unit.global_position.distance_to(expected) > SUMMON_SNAP_SLACK_M:
		_fail(
			"FAIL summon placed at %s want near aim %s"
			% [str(unit.global_position), str(expected)]
		)
		_despawn(unit)
		return
	_despawn(unit)
	_city._summon_aim = {"point": Vector3.ZERO, "normal": Vector3.UP, "did_hit": false}
	var missed := _city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if missed != null:
		_fail("FAIL summon_monster_at_aim must not spawn on aim miss")
		_despawn(missed)
		return
	print("summon aim: hit near %s, miss refused" % str(aim_pos))


func _test_melee_hurts_player() -> void:
	var walker := CityWalker.new()
	walker.name = "TestWalker"
	add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	_city.bind_player(walker)
	## The player is a body in the faction system like any other, and being human is the only
	## reason a skeleton swings at it.
	if walker.combat_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL the player fights as faction %d, not human" % walker.combat_faction())
		return
	if _city.player_faction() != walker.combat_faction():
		_fail("FAIL CityRoot reports player faction %d" % _city.player_faction())
		return
	if not MonsterFaction.is_hostile(int(MonsterFaction.Id.UNDEAD), _city.player_faction()):
		_fail("FAIL undead are not hostile to humans")
		return
	var before := walker.get_health()
	if before <= 0.0:
		_fail("FAIL walker has no health after ready")
		return
	var unit := _spawn(
		UndeadUnit.Role.MINION,
		walker.global_position + Vector3(1.0, 0.0, 0.0),
		"kaykit/Skeleton_Minion"
	)
	if unit == null:
		return
	unit.set_combat_prey(walker.global_position)
	var combat: RefCounted = unit.combat()
	if combat == null:
		_fail("FAIL no combat kit on unit")
		return
	if not bool(combat.call("try_attack_living", walker.global_position)):
		_fail("FAIL melee try_attack_living returned false")
		return
	## Windup is 0 for melee — damage should land immediately.
	var after := walker.get_health()
	var dmg_mult := float(combat.call("damage_mult"))
	var expect: float = before - DamageSource.amount(DamageSource.Id.MONSTER_MELEE) * dmg_mult
	if absf(after - expect) > HEALTH_EPS:
		_fail("FAIL player health %.2f want %.2f after melee" % [after, expect])
		return
	## Spawn-by-id path used by the N-key summon.
	var summoned := _director.spawn_monster_by_id(
		"big/Frog", _w(Vector3i(30, 1, 20)), BODY_SEED
	)
	if summoned == null:
		_fail("FAIL spawn_monster_by_id returned null")
		return
	if summoned.creature_entry() == null or summoned.creature_entry().id != "big/Frog":
		_fail("FAIL summoned body is not big/Frog")
		return
	if summoned.combat_stats() == null:
		_fail("FAIL summoned body has no combat stats")
		return
	print(
		"melee: player %.1f→%.1f (mult %.2f); summon big/Frog ok"
		% [before, after, dmg_mult]
	)
	_despawn(unit)
	_despawn(summoned)
	walker.queue_free()


## Every catalogue body maps to a faction; same-faction packs do not hunt each other; a
## cross-faction melee swing must drain HP (the old hug bug).
func _test_factions_and_mob_melee() -> void:
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		var faction_id: int = int(MonsterFaction.for_body(entry.id))
		if faction_id < 0:
			_fail("FAIL no faction for %s" % entry.id)
			return
	if _city.ped_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL pedestrians are faction %d, not human" % _city.ped_faction())
		return
	var undead_a := _spawn(
		UndeadUnit.Role.MINION, _w(Vector3i(40, 1, 40)), "kaykit/Skeleton_Minion"
	)
	## Same-faction decoy farther out; hostile frog inside melee reach (1.8 m).
	var undead_b := _spawn(
		UndeadUnit.Role.MINION, _w(Vector3i(50, 1, 40)), "kaykit/Skeleton_Warrior"
	)
	var beast := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(41, 1, 40)), "big/Frog")
	if undead_a == null or undead_b == null or beast == null:
		return
	if undead_a.faction() != int(MonsterFaction.Id.UNDEAD):
		_fail("FAIL Skeleton_Minion faction is %d" % undead_a.faction())
		return
	if beast.faction() != int(MonsterFaction.Id.BEAST):
		_fail("FAIL big/Frog faction is %d" % beast.faction())
		return
	if undead_a.is_hostile_to(undead_b):
		_fail("FAIL same-faction skeletons are hostile to each other")
		return
	if not undead_a.is_hostile_to(beast):
		_fail("FAIL undead is not hostile to beast")
		return
	var ally_pos: Vector3 = _city.find_nearest_monster_position(
		undead_a.global_position, 20.0, undead_a
	)
	if ally_pos != Vector3.INF and ally_pos.distance_to(undead_b.global_position) < 0.5:
		_fail("FAIL find_nearest_monster_position returned same-faction ally")
		return
	if ally_pos == Vector3.INF or ally_pos.distance_to(beast.global_position) > 0.5:
		_fail("FAIL find_nearest_monster_position missed cross-faction prey")
		return
	var before := beast.health()
	undead_a.set_combat_prey(beast.global_position)
	var combat: RefCounted = undead_a.combat()
	if not bool(combat.call("try_attack_living", beast.global_position)):
		_fail("FAIL cross-faction melee try_attack_living returned false")
		return
	var after := beast.health()
	var dmg_mult := float(combat.call("damage_mult"))
	var armor := float(beast.combat().call("armor_mult"))
	var expect: float = (
		before - DamageSource.amount(DamageSource.Id.MONSTER_MELEE_MOB) * dmg_mult / maxf(armor, 0.001)
	)
	if absf(after - expect) > HEALTH_EPS:
		_fail("FAIL mob melee left %.2f, want %.2f" % [after, expect])
		return
	if after >= before:
		_fail("FAIL mob melee dealt no damage (%.2f → %.2f)" % [before, after])
		return
	## Revenge: the frog must sticky-pursue the skeleton that hit it, overriding prey pick.
	var frog_provider := beast.goal_provider()
	if frog_provider == null or not frog_provider.has_forced_attacker():
		_fail("FAIL victim did not promote the attacker as forced pursuit prey")
		return
	if frog_provider.pursuit() != UndeadGoalProvider.Pursuit.HOT:
		_fail("FAIL revenge pursuit is not Hot (phase %d)" % frog_provider.pursuit())
		return
	var revenge: Vector3 = frog_provider.last_known_prey()
	if revenge.distance_to(undead_a.global_position + Vector3(0.0, 1.0, 0.0)) > 1.5:
		_fail("FAIL revenge LKP %s is not the attacker" % str(revenge))
		return
	print(
		"factions: undead↔undead allied, undead→frog melee %.1f→%.1f, frog revenge-pursues"
		% [before, after]
	)
	_despawn(undead_a)
	_despawn(undead_b)
	_despawn(beast)


## One shared recovery after any attack. A multi-attack kit used to empty its whole pool the
## moment line of sight opened — the freed cage boss threw laser, blaster burst and charged
## blast inside three seconds because every per-attack timer sat at zero.
func _test_global_cooldown() -> void:
	var walker := CityWalker.new()
	walker.name = "GcdWalker"
	add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	walker.global_position = _w(Vector3i(20, 1, 60))
	_city.bind_player(walker)
	var unit := _spawn(
		UndeadUnit.Role.MINION,
		walker.global_position + Vector3(1.0, 0.0, 0.0),
		"kaykit/Skeleton_Minion"
	)
	if unit == null:
		walker.queue_free()
		return
	var combat: RefCounted = unit.combat()
	unit.set_combat_prey(walker.global_position)
	var before := walker.get_health()
	if not bool(combat.call("try_attack_living", walker.global_position)):
		_fail("FAIL first melee did not fire")
		_despawn(unit)
		walker.queue_free()
		return
	if walker.get_health() >= before:
		_fail("FAIL first melee dealt no damage")
		_despawn(unit)
		walker.queue_free()
		return
	var gcd := float(combat.call("global_cooldown_left"))
	if absf(gcd - MonsterCombat.GLOBAL_COOLDOWN_S) > 0.001:
		_fail("FAIL global cooldown %.2f after a swing, want %.2f" % [gcd, MonsterCombat.GLOBAL_COOLDOWN_S])
		_despawn(unit)
		walker.queue_free()
		return
	## The point of the shared timer: melee recovers sooner than the GCD, and must still wait.
	var melee_cd := CombatTable.monster_attack_cooldown_s("melee")
	if melee_cd >= MonsterCombat.GLOBAL_COOLDOWN_S:
		_fail("FAIL melee cooldown %.2f is not shorter than the GCD — nothing to prove" % melee_cd)
		_despawn(unit)
		walker.queue_free()
		return
	combat.call("tick", melee_cd + 0.05)
	## Melee's own timer is up — only the shared recovery is holding the swing.
	if not bool(combat.call("is_attack_ready", "melee")):
		_fail("FAIL melee's own %.2f s cooldown did not drain" % melee_cd)
		_despawn(unit)
		walker.queue_free()
		return
	if float(combat.call("global_cooldown_left")) <= 0.0:
		_fail("FAIL the GCD drained in %.2f s, want %.1f s" % [melee_cd, MonsterCombat.GLOBAL_COOLDOWN_S])
		_despawn(unit)
		walker.queue_free()
		return
	var held := walker.get_health()
	combat.call("try_attack_living", walker.global_position)
	if walker.get_health() < held - HEALTH_EPS:
		_fail("FAIL a second swing landed while the GCD was still running")
		_despawn(unit)
		walker.queue_free()
		return
	## Past the shared recovery the same body swings again.
	combat.call("tick", MonsterCombat.GLOBAL_COOLDOWN_S)
	if float(combat.call("global_cooldown_left")) > 0.0:
		_fail("FAIL global cooldown did not drain")
		_despawn(unit)
		walker.queue_free()
		return
	if not bool(combat.call("try_attack_living", walker.global_position)):
		_fail("FAIL melee did not resume after the GCD")
		_despawn(unit)
		walker.queue_free()
		return
	if walker.get_health() >= held:
		_fail("FAIL the post-GCD swing dealt no damage")
		_despawn(unit)
		walker.queue_free()
		return
	_despawn(unit)
	walker.queue_free()

	## Multi-attack kit: firing one power must lock the others that never fired.
	var boss := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(28, 1, 60)), "big/CageDemon")
	if boss == null:
		return
	var boss_combat: RefCounted = boss.combat()
	for attack_id: String in ["blaster", "eye_laser", "charged_blast"]:
		if not bool(boss_combat.call("has_attack", attack_id)):
			_fail("FAIL big/CageDemon kit is missing %s" % attack_id)
			_despawn(boss)
			return
		if not bool(boss_combat.call("is_attack_ready", attack_id)):
			_fail("FAIL %s is not ready on a fresh CageDemon" % attack_id)
			_despawn(boss)
			return
	## Stand in for one executed blaster — every `_execute_*` routes through here.
	boss_combat.call("_set_cooldown", "blaster")
	## The untouched powers keep their own timers at zero; the shared recovery is what stops
	## the kit emptying itself, so the pick has to come back empty.
	for attack_id: String in ["eye_laser", "charged_blast"]:
		if not bool(boss_combat.call("is_attack_ready", attack_id)):
			_fail("FAIL %s took a cooldown it never fired" % attack_id)
			_despawn(boss)
			return
	if str(boss_combat.call("_pick_attack", 2.0)) != "":
		_fail("FAIL the kit picked another attack inside the GCD")
		_despawn(boss)
		return
	boss_combat.call("tick", MonsterCombat.GLOBAL_COOLDOWN_S + 0.01)
	if str(boss_combat.call("_pick_attack", 2.0)) != "eye_laser":
		_fail(
			"FAIL after the GCD the kit picked '%s', want eye_laser"
			% str(boss_combat.call("_pick_attack", 2.0))
		)
		_despawn(boss)
		return
	## The fired power keeps its own longer recovery on top of the shared one.
	if bool(boss_combat.call("is_attack_ready", "blaster")):
		_fail("FAIL blaster skipped its own %.1f s cooldown" % CombatTable.monster_attack_cooldown_s("blaster"))
		_despawn(boss)
		return
	_despawn(boss)
	print(
		"gcd: %.1f s shared recovery holds melee past its %.1f s cooldown; one CageDemon power locks the rest"
		% [MonsterCombat.GLOBAL_COOLDOWN_S, melee_cd]
	)


## A terrain-chewing body has to close in and be allowed to route through fabric. The cage boss
## used to hold `ranged_boss` artillery range (28 m), which in a cave meant it was always
## "already in range": the provider handed it no goal, it never moved, and `crumble_stride`
## only fires on a stride — so it stood in the rock forever.
func _test_crumble_stride_closes_in() -> void:
	var boss := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(66, 1, 40)), "big/CageDemon")
	if boss == null:
		return
	if not boss.chews_terrain():
		_fail("FAIL big/CageDemon does not report a terrain-chewing aura")
		_despawn(boss)
		return
	if boss.nav_profile_id() != NavProfile.Id.MONSTER_BREAKER:
		_fail("FAIL cage boss navigates on profile %d, want MONSTER_BREAKER" % boss.nav_profile_id())
		_despawn(boss)
		return
	var breaker := NavService.instance().profile(NavProfile.Id.MONSTER_BREAKER)
	if breaker == null or not breaker.can_break:
		_fail("FAIL MONSTER_BREAKER profile is missing or cannot break")
		_despawn(boss)
		return
	var stand := float(boss.combat().call("hunt_standoff_m"))
	if absf(stand - MonsterCombat.CHEWER_STANDOFF_M) > 0.001:
		_fail("FAIL chewer stand-off %.2f, want %.2f" % [stand, MonsterCombat.CHEWER_STANDOFF_M])
		_despawn(boss)
		return
	var preferred := float(boss.combat_stats().get("preferred_range_m"))
	if stand >= preferred:
		_fail("FAIL chewer holds %.1f m — no closer than its %.1f m artillery range" % [stand, preferred])
		_despawn(boss)
		return

	## Pinned against fabric with prey out of reach: chew toward the prey, or the navigator
	## never opens a corridor and the body never strides.
	var aura: RefCounted = boss.get("_aura") as RefCounted
	if aura == null:
		_fail("FAIL cage boss has no aura kit")
		_despawn(boss)
		return
	boss.velocity = Vector3.ZERO
	boss.set_combat_prey(boss.global_position + Vector3(12.0, 0.0, 0.0))
	var dir: Vector3 = aura.call("_stride_direction") as Vector3
	if dir.distance_to(Vector3.RIGHT) > 0.01:
		_fail("FAIL a pinned chewer digs toward %s, want %s" % [str(dir), str(Vector3.RIGHT)])
		_despawn(boss)
		return
	## Already at its fighting distance — standing still must not grind the world away.
	boss.set_combat_prey(boss.global_position + Vector3(1.0, 0.0, 0.0))
	if (aura.call("_stride_direction") as Vector3) != Vector3.ZERO:
		_fail("FAIL a chewer at contact range keeps chewing while standing still")
		_despawn(boss)
		return
	boss.set_combat_prey(Vector3.INF)
	if (aura.call("_stride_direction") as Vector3) != Vector3.ZERO:
		_fail("FAIL a chewer with no prey still chews")
		_despawn(boss)
		return
	_despawn(boss)

	## A big body without the aura keeps "a wall is a wall" and its artillery stand-off.
	var plain := _spawn(UndeadUnit.Role.MINION, _w(Vector3i(70, 1, 40)), "big/Demon")
	if plain == null:
		return
	if plain.chews_terrain():
		_fail("FAIL big/Demon reports a terrain-chewing aura")
		_despawn(plain)
		return
	if plain.nav_profile_id() != NavProfile.Id.MONSTER:
		_fail("FAIL big/Demon navigates on profile %d, want MONSTER" % plain.nav_profile_id())
		_despawn(plain)
		return
	var plain_stand := float(plain.combat().call("hunt_standoff_m"))
	if plain_stand <= MonsterCombat.CHEWER_STANDOFF_M:
		_fail("FAIL big/Demon holds only %.1f m — it should keep artillery range" % plain_stand)
		_despawn(plain)
		return
	_despawn(plain)
	print(
		"crumble stride: cage boss closes to %.1f m on MONSTER_BREAKER (artillery %.0f m); "
		% [stand, preferred]
		+ "big/Demon still holds %.1f m on MONSTER" % plain_stand
	)


## Minion power: half-size human ally; recast dismisses the previous body; 60s lifetime + HUD.
func _test_player_minion_power() -> void:
	var walker := CityWalker.new()
	walker.name = "MinionWalker"
	add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	_city.bind_player(walker)
	walker.global_position = _w(Vector3i(60, 1, 20))
	walker.set_energy_points(walker.energy_max)

	var hud: CanvasLayer = PlayerHealthHud.new()
	hud.name = "TestMinionHealthHud"
	_city.add_child(hud)
	await get_tree().process_frame
	_city.set("_health_hud", hud)

	var unit := _spawn(
		UndeadUnit.Role.MINION, _w(Vector3i(62, 1, 20)), "kaykit/Skeleton_Warrior"
	)
	if unit == null:
		walker.queue_free()
		return
	var full_hp := unit.health_max()
	var full_dmg := float(unit.combat().call("damage_mult"))
	var full_scale := unit.character_scale
	unit.become_player_minion()
	if unit.faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL player minion faction is %d" % unit.faction())
		_despawn(unit)
		walker.queue_free()
		return
	if absf(unit.character_scale - full_scale * 0.5) > 0.001:
		_fail("FAIL player minion scale %.3f want %.3f" % [unit.character_scale, full_scale * 0.5])
		_despawn(unit)
		walker.queue_free()
		return
	if absf(float(unit.combat().call("damage_mult")) - full_dmg * 0.5) > 0.001:
		_fail(
			"FAIL player minion damage_mult %.3f want %.3f"
			% [float(unit.combat().call("damage_mult")), full_dmg * 0.5]
		)
		_despawn(unit)
		walker.queue_free()
		return
	if absf(unit.health_max() - full_hp * 0.5) > HEALTH_EPS:
		_fail("FAIL player minion HP %.2f want %.2f" % [unit.health_max(), full_hp * 0.5])
		_despawn(unit)
		walker.queue_free()
		return
	## Ally kit must not treat the human player as prey.
	unit.set_combat_prey(walker.global_position)
	var before_hp := walker.get_health()
	if bool(unit.combat().call("try_attack_living", walker.global_position)):
		## Melee may still "fire" at a point, but it must not drain the ally player.
		pass
	if walker.get_health() < before_hp - HEALTH_EPS:
		_fail("FAIL human-faction minion damaged the player")
		_despawn(unit)
		walker.queue_free()
		return
	_despawn(unit)

	if absf(AbilityRegistry.MINION_DURATION_SEC - 60.0) > 0.01:
		_fail("FAIL MINION_DURATION_SEC is %.1f, want 60" % AbilityRegistry.MINION_DURATION_SEC)
		walker.queue_free()
		return

	## Recast replaces: first body dies when the second spawns.
	_city.call("_spawn_minion")
	var first: UndeadUnit = _city.get("_player_minion") as UndeadUnit
	if first == null or not is_instance_valid(first):
		_fail("FAIL _spawn_minion did not track a living ally")
		walker.queue_free()
		return
	if first.faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL summoned minion faction is %d" % first.faction())
		walker.queue_free()
		return
	if absf(first.character_scale - 0.5) > 0.001:
		_fail("FAIL summoned minion scale %.3f want 0.5" % first.character_scale)
		walker.queue_free()
		return
	if not bool(hud.call("minion_bar_visible")):
		_fail("FAIL minion health bar stayed hidden after summon")
		walker.queue_free()
		return
	if absf(float(hud.call("minion_fill_fraction")) - 1.0) > 0.01:
		_fail(
			"FAIL minion bar fill %.3f want 1.0" % float(hud.call("minion_fill_fraction"))
		)
		walker.queue_free()
		return
	var life_left := float(_city.get("_player_minion_life_left"))
	if life_left < AbilityRegistry.MINION_DURATION_SEC - 0.05:
		_fail("FAIL minion life left %.2f right after summon" % life_left)
		walker.queue_free()
		return
	var first_id := first.get_instance_id()
	walker.set_energy_points(walker.energy_max)
	_city.call("_spawn_minion")
	var second: UndeadUnit = _city.get("_player_minion") as UndeadUnit
	if second == null or not is_instance_valid(second):
		_fail("FAIL recast left no player minion")
		walker.queue_free()
		return
	if second.get_instance_id() == first_id:
		_fail("FAIL recast kept the same minion instance")
		walker.queue_free()
		return
	await get_tree().process_frame
	if is_instance_valid(first) and first.is_alive():
		_fail("FAIL prior minion still alive after recast")
		walker.queue_free()
		return
	if AbilityRegistry.MINION_MAX != 1:
		_fail("FAIL MINION_MAX is %d, want 1" % AbilityRegistry.MINION_MAX)
		walker.queue_free()
		return
	## Lifetime expiry dismisses the ally and hides the strip.
	_city.set("_player_minion_life_left", 0.01)
	_city.call("_tick_player_minion", 0.02)
	await get_tree().process_frame
	if _city.get("_player_minion") != null:
		_fail("FAIL expired minion was not dismissed")
		walker.queue_free()
		return
	if bool(hud.call("minion_bar_visible")):
		_fail("FAIL minion bar still visible after expiry")
		walker.queue_free()
		return
	print(
		"player minion: human, half HP/dmg/scale, 60s life + HUD; recast replaced %d → %d"
		% [first_id, second.get_instance_id()]
	)
	walker.queue_free()
	hud.queue_free()


## Killing a body used to leave a freed Ref in the director list; blaster aim then crashed
## on `is_alive()` ("previously freed"). Death must unregister before queue_free lands.
func _test_freed_unit_aim_query() -> void:
	var unit := _spawn(
		UndeadUnit.Role.MINION, _w(Vector3i(32, 1, 32)), "kaykit/Skeleton_Minion"
	)
	if unit == null:
		return
	var from := unit.global_position + Vector3(0.0, 1.0, -4.0)
	var to := unit.global_position + Vector3(0.0, 1.0, 4.0)
	var before: Dictionary = _director.query_segment_hit(from, to)
	if before.is_empty() or before.get("unit") != unit:
		_fail("FAIL query_segment_hit missed the living unit")
		_despawn(unit)
		return
	## Death unregisters; free immediately (skip the 1.6 s corpse timer).
	unit.kill_from_player()
	var monsters := _director.roster()
	if monsters.is_registered(unit):
		_fail("FAIL dead unit still registered on the MonsterRoster")
		unit.queue_free()
		return
	var roster_after_death := monsters.tracked_count()
	unit.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	## Must not throw "Nonexistent function is_alive in base previously freed".
	var after: Dictionary = _director.query_segment_hit(from, to)
	if monsters.tracked_count() != roster_after_death:
		_fail(
			"FAIL MonsterRoster changed after free (%d → %d)"
			% [roster_after_death, monsters.tracked_count()]
		)
		return
	if not after.is_empty():
		var hit_unit: Variant = after.get("unit", null)
		if hit_unit != null and not is_instance_valid(hit_unit):
			_fail("FAIL query_segment_hit returned a freed unit")
			return
	print("freed-unit aim: living hit ok, post-death query_segment_hit safe")


class AimStub:
	extends CityWalker

	func _ready() -> void:
		pass


func _despawn(unit: UndeadUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _director != null:
		_director.despawn_unit(unit)
		return
	unit.queue_free()


func _has_str(arr: PackedStringArray, needle: String) -> bool:
	for s: String in arr:
		if s == needle:
			return true
	return false


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
		_fail("FAIL spawn refused %s" % body_id)
		return null
	unit.set_physics_process(false)
	return unit


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


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


func _quit() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
