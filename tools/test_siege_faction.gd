## Siege faction rules: the acquire/damage split that lets towers shoot without the horde
## turning on them unprovoked, and the pot arithmetic on SiegeController.
##
## Run: powershell -File tools\run_test.ps1 test_siege_faction
extends Node

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const SiegeLayoutScript := preload("res://scripts/city/siege_layout.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_names()
	_check_hostility_matrix()
	_check_acquire_split()
	_check_spectator_untouched()
	_check_gamedata()
	_check_pot_and_stake()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _check_names() -> void:
	if MonsterFaction.faction_name(MonsterFaction.Id.SIEGE_ATTACKER) != "siege_attacker":
		_fail("FAIL siege_attacker name")
	if MonsterFaction.faction_name(MonsterFaction.Id.SIEGE_DEFENDER) != "siege_defender":
		_fail("FAIL siege_defender name")
	if MonsterFaction.from_name("siege_attacker") != MonsterFaction.Id.SIEGE_ATTACKER:
		_fail("FAIL from_name siege_attacker")
	if MonsterFaction.from_name("siege_defender") != MonsterFaction.Id.SIEGE_DEFENDER:
		_fail("FAIL from_name siege_defender")
	if not MonsterFaction.all().has(MonsterFaction.Id.SIEGE_ATTACKER):
		_fail("FAIL SIEGE_ATTACKER missing from all()")
	if not MonsterFaction.all().has(MonsterFaction.Id.SIEGE_DEFENDER):
		_fail("FAIL SIEGE_DEFENDER missing from all()")
	print("names: siege_attacker / siege_defender resolve both ways")


func _check_hostility_matrix() -> void:
	var A := MonsterFaction.Id.SIEGE_ATTACKER
	var D := MonsterFaction.Id.SIEGE_DEFENDER
	var H := MonsterFaction.Id.HUMAN
	var U := MonsterFaction.Id.UNDEAD
	## Same side never fights.
	if MonsterFaction.is_hostile(A, A) or MonsterFaction.is_hostile(D, D):
		_fail("FAIL same-side siege factions are hostile")
	## Cross siege: damage both ways.
	if not MonsterFaction.is_hostile(A, D) or not MonsterFaction.is_hostile(D, A):
		_fail("FAIL attacker↔defender must be hostile for damage")
	## Attackers still fight the open world.
	if not MonsterFaction.is_hostile(A, H) or not MonsterFaction.is_hostile(A, U):
		_fail("FAIL siege_attacker should be hostile to human/undead")
	## Defenders only fight the horde — never civilians, never stray undead.
	if MonsterFaction.is_hostile(D, H) or MonsterFaction.is_hostile(H, D):
		_fail("FAIL siege_defender must not be hostile to human")
	if MonsterFaction.is_hostile(D, U) or MonsterFaction.is_hostile(U, D):
		_fail("FAIL siege_defender must not be hostile to undead")
	print("hostility: attacker↔defender damage both ways; defenders ignore civilians")


func _check_acquire_split() -> void:
	var A := MonsterFaction.Id.SIEGE_ATTACKER
	var D := MonsterFaction.Id.SIEGE_DEFENDER
	var H := MonsterFaction.Id.HUMAN
	var U := MonsterFaction.Id.UNDEAD
	## The whole point: defenders are never fresh prey.
	if MonsterFaction.can_acquire(A, D):
		_fail("FAIL attacker must not acquire defender as fresh prey")
	## Towers (and the defending player) still pick the horde.
	if not MonsterFaction.can_acquire(D, A):
		_fail("FAIL defender must acquire attacker")
	## Human outside a run is still fair game.
	if not MonsterFaction.can_acquire(A, H):
		_fail("FAIL attacker must still acquire a human player outside a run")
	## Ordinary hostility still acquires.
	if not MonsterFaction.can_acquire(U, H):
		_fail("FAIL undead must still acquire human")
	if MonsterFaction.can_acquire(U, U):
		_fail("FAIL same-faction acquire")
	## can_acquire never disagrees with is_hostile on a true — it only narrows.
	for hunter in MonsterFaction.all():
		for prey in MonsterFaction.all():
			if MonsterFaction.can_acquire(hunter, prey) and not MonsterFaction.is_hostile(hunter, prey):
				_fail(
					"FAIL can_acquire(%s,%s) without is_hostile"
					% [MonsterFaction.faction_name(hunter), MonsterFaction.faction_name(prey)]
				)
	print("acquire: defenders are unacquirable; towers still hunt the horde")


func _check_spectator_untouched() -> void:
	var S := MonsterFaction.Id.SPECTATOR
	var U := MonsterFaction.Id.UNDEAD
	var D := MonsterFaction.Id.SIEGE_DEFENDER
	if MonsterFaction.is_hostile(S, U) or MonsterFaction.is_hostile(U, S):
		_fail("FAIL SPECTATOR hostility changed")
	if MonsterFaction.can_acquire(U, S) or MonsterFaction.can_acquire(S, U):
		_fail("FAIL SPECTATOR acquire changed")
	if MonsterFaction.is_hostile(S, D) or MonsterFaction.can_acquire(D, S):
		_fail("FAIL SPECTATOR×SIEGE_DEFENDER should stay non-hostile")
	print("spectator: zoo cloak rules unchanged")


func _check_gamedata() -> void:
	if GameData.siege_int("min_stake_total") < 1:
		_fail("FAIL siege.min_stake_total missing or zero")
	if GameData.siege_float("lodestone_hp") < 1.0:
		_fail("FAIL siege.lodestone_hp missing or zero")
	if GameData.siege_int("district_alive_cap") != 34:
		_fail("FAIL siege district cap should match the shared 34-unit ceiling")
	var factions: Variant = GameData.siege().get("source_factions", [])
	if typeof(factions) != TYPE_ARRAY or (factions as Array).is_empty():
		_fail("FAIL siege.source_factions empty")
	print(
		"gamedata: min_stake=%d lodestone=%.0f factions=%d"
		% [
			GameData.siege_int("min_stake_total"),
			GameData.siege_float("lodestone_hp"),
			(factions as Array).size(),
		]
	)


## Pot stake / spend / kill credit without spawning a real wave.
func _check_pot_and_stake() -> void:
	var city := _FakeCity.new()
	city.name = "FakeCity"
	add_child(city)
	var layout: SiegeLayout = SiegeLayoutScript.new() as SiegeLayout
	layout.quarter_cells = Rect2i(0, 0, 8, 8)
	layout.quarter_vox = Rect2i(0, 0, 224, 224)
	layout.deck_y = 6
	layout.lodestone_xz = Vector2i(112, 112)
	layout.lodestone_base_y = 6
	layout.lodestone_radius_vox = 5
	layout.lodestone_height_vox = 16
	layout.add_gate(Vector3i(0, 6, 112), Vector2i(1, 0))
	layout.add_pad(Vector3i(40, 6, 40), SiegeLayout.PadKind.STREET)
	if not layout.is_valid():
		_fail("FAIL fixture layout invalid")
		return

	var ctrl: SiegeController = SiegeControllerScript.new() as SiegeController
	add_child(ctrl)
	ctrl.setup(
		layout,
		Vector3i.ZERO,
		0.5,
		42,
		city,
		Callable(),
		Callable(),
		Callable()
	)
	if ctrl.get_node_or_null("SiegeLodestonePanel") == null:
		_fail("FAIL Lodestone panel was not spawned")
		return
	if ctrl.min_stake_total() != GameData.siege_int("min_stake_total"):
		_fail("FAIL min_stake_total getter disagrees with gamedata")

	## Short stake rejected.
	if ctrl.start_run({"gem_quartz": 1}):
		_fail("FAIL start_run accepted a stake below the minimum")
	## Rich enough.
	city.inventory.add("gem_quartz", 10)
	city.inventory.add("gem_amber", 2)
	if not ctrl.start_run({"gem_quartz": 5, "gem_amber": 1}):
		_fail("FAIL start_run rejected a valid stake")
		return
	if city.inventory.count_of("gem_quartz") != 5:
		_fail("FAIL stake did not pull quartz from inventory")
	if city.inventory.count_of("gem_amber") != 1:
		_fail("FAIL stake did not pull amber from inventory")
	if ctrl.pot_total() != 6:
		_fail("FAIL pot_total is %d, want 6" % ctrl.pot_total())
	if city.player_faction() != int(MonsterFaction.Id.SIEGE_DEFENDER):
		_fail("FAIL player was not switched to SIEGE_DEFENDER")
	if city.active_siege != ctrl:
		_fail("FAIL CityRoot was not told about the run")

	## Kill haul feeds the pot, not the bag.
	var mats: Array[int] = [VoxelMaterial.GEM_TOPAZ, VoxelMaterial.GEM_TOPAZ]
	var paid := ctrl.credit_kill_mats(mats)
	if paid != 2:
		_fail("FAIL credit_kill_mats paid %d, want 2" % paid)
	if ctrl.pot_total() != 8:
		_fail("FAIL pot after kill haul is %d, want 8" % ctrl.pot_total())
	if city.inventory.count_of("gem_topaz") != 0:
		_fail("FAIL kill haul leaked into inventory during a run")

	## Spend for a tower.
	if not ctrl.spend_from_pot({"gem_quartz": 3}):
		_fail("FAIL spend_from_pot rejected an affordable cost")
	var pot_after: Dictionary = ctrl.pot_snapshot()
	if int(pot_after.get("gem_quartz", 0)) != 2:
		_fail("FAIL pot quartz after spend is wrong")
	if ctrl.spend_from_pot({"gem_diamond": 1}):
		_fail("FAIL spend_from_pot accepted a cost the pot cannot cover")

	## Withdraw only between waves — start_run left us in INTERMISSION.
	var phase_now: int = int(ctrl.phase())
	if phase_now != int(SiegeController.Phase.INTERMISSION):
		_fail("FAIL expected INTERMISSION after start, got %d" % phase_now)
	if not ctrl.withdraw():
		_fail("FAIL withdraw failed during intermission")
	if city.inventory.count_of("gem_quartz") != 5 + 2:
		## started with 10, staked 5 (left 5), pot had 2 quartz left after spend, banked → 7
		_fail(
			"FAIL quartz after withdraw is %d, want 7"
			% city.inventory.count_of("gem_quartz")
		)
	if city.inventory.count_of("gem_topaz") != 2:
		_fail("FAIL topaz kill haul was not banked on withdraw")
	if city.player_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL player faction not restored after withdraw")
	if city.active_siege != null:
		_fail("FAIL siege run still registered after withdraw")
	print("pot: stake → kill credit → spend → withdraw all round-trip")
	_check_vulnerability_radius(ctrl, layout)


## The Lodestone has no collider, so one radius has to answer both "stop walking" and "you are
## hurting it". If a body could stop outside the damage zone it would be handed a fresh corridor
## every arrival and circle the crystal forever, which is exactly the bug this pins down.
func _check_vulnerability_radius(ctrl: SiegeController, layout: SiegeLayout) -> void:
	var radius := ctrl.lodestone_vulnerable_radius_m()
	var crystal := float(layout.lodestone_radius_vox) * 0.5
	if radius <= crystal + UndeadGoalProvider.PUSH_RING_INSET_M:
		_fail(
			"FAIL vulnerability radius %.2f leaves the stand ring inside the %.2f crystal"
			% [radius, crystal]
		)
	var unit: UndeadUnit = UndeadUnit.new()
	unit.set_push_aim(ctrl.lodestone_world_pos(), radius)
	if not is_equal_approx(unit.push_hold_m(), radius):
		_fail(
			"FAIL attacker holds at %.2f but the Lodestone bites at %.2f"
			% [unit.push_hold_m(), radius]
		)
	unit.free()
	print("lodestone: hold radius == vulnerability radius (%.2f m)" % radius)


## Stands in for the CityRoot methods SiegeController actually calls.
class _FakeCity:
	extends Node

	var inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	var _faction: int = int(MonsterFactionScript.Id.HUMAN)
	var active_siege: SiegeController = null

	func get_inventory() -> PlayerInventory:
		return inventory

	func set_player_combat_faction(id: int) -> void:
		_faction = id

	func player_faction() -> int:
		return _faction

	func begin_siege_run(ctrl: SiegeController) -> void:
		active_siege = ctrl

	func end_siege_run(ctrl: SiegeController) -> void:
		if active_siege == ctrl:
			active_siege = null
