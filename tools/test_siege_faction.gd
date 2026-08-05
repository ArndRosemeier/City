## Siege faction rules: the acquire/damage split that lets towers shoot without the horde
## turning on them unprovoked, and the pot arithmetic on SiegeController.
##
## Run: powershell -File tools\run_test.ps1 test_siege_faction
extends Node

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const SiegeLayoutScript := preload("res://scripts/city/siege_layout.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const BeaconRegistryScript := preload("res://scripts/city/beacon_registry.gd")

## Fixture geometry, in district-local voxels at 0.5 m each. The quarter is the real 224-voxel
## square; the outer stones sit 50 m out and the hell gates 54 m out, which is far enough that
## neither lands inside the 20 m withdrawal ring the pot checks use.
const FIX_CENTRE := 112
const FIX_OUTER_OFFSET := 100
const FIX_GATE_RADIUS := 108

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
	_check_beacon_registry()
	_check_pot_and_stake()
	_check_shield_and_gates()
	_check_idle_arcs()
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
	## The wave clock replaced the phase machine: no all-clear state, so a period and a
	## deployment window are what pace the run. Zero on either would mean waves never land.
	if GameData.siege_float("wave_period_sec") <= 0.0:
		_fail("FAIL siege.wave_period_sec missing or zero — waves would never land")
	if GameData.siege_float("deploy_sec") <= 0.0:
		_fail("FAIL siege.deploy_sec missing or zero — no setup time at all")
	if GameData.siege_int("alive_target_base") < 1:
		_fail("FAIL siege.alive_target_base missing or zero")
	var drip := GameData.siege_float("wave_drip_fraction")
	if drip <= 0.0 or drip > 1.0:
		_fail("FAIL siege.wave_drip_fraction %.2f is not a fraction of the period" % drip)
	## Cashing out is the run's only risk. A zero ring would let the player bank with the horde
	## standing on the crystal, which is a pot that costs nothing to keep.
	if GameData.siege_float("withdraw_clear_radius_m") <= 0.0:
		_fail("FAIL siege.withdraw_clear_radius_m missing or zero — banking would be free")
	## The four outer stones are the run's clock. Zero HP on them would hand the centre over on
	## contact, and a pool as deep as the centre's would make the shield the whole run.
	var outer_hp := GameData.siege_float("outer_stone_hp")
	if outer_hp <= 0.0:
		_fail("FAIL siege.outer_stone_hp missing or zero — outer stones would fall instantly")
	if outer_hp >= GameData.siege_float("lodestone_hp"):
		_fail(
			"FAIL siege.outer_stone_hp %.0f is not below the centre's %.0f"
			% [outer_hp, GameData.siege_float("lodestone_hp")]
		)
	## Gate weighting is what makes a wave read as pressure on a flank. A zero floor would leave
	## seven mouths permanently dead, and a share at or below the floor would flatten the table.
	var floor_w := GameData.siege_float("gate_weight_floor")
	var share := GameData.siege_float("gate_primary_share")
	if floor_w <= 0.0:
		_fail("FAIL siege.gate_weight_floor missing or zero — cold gates would never spawn")
	if share <= floor_w:
		_fail(
			"FAIL siege.gate_primary_share %.2f does not beat the floor %.2f"
			% [share, floor_w]
		)
	if GameData.siege_float("gate_falloff") <= 0.0:
		_fail("FAIL siege.gate_falloff missing or zero — every gate would be primary")
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


## A five-stone, eight-gate layout without running a composer: the same shape the controller sees on
## a real tile, small enough to reason about in a test.
func _make_layout() -> SiegeLayout:
	var layout: SiegeLayout = SiegeLayoutScript.new() as SiegeLayout
	layout.quarter_cells = Rect2i(0, 0, 8, 8)
	layout.quarter_vox = Rect2i(0, 0, 224, 224)
	layout.deck_y = 6
	layout.lodestone_xz = Vector2i(FIX_CENTRE, FIX_CENTRE)
	layout.lodestone_base_y = 6
	layout.lodestone_radius_vox = 5
	layout.lodestone_height_vox = 16
	layout.add_breach(Vector3i(0, 6, FIX_CENTRE), Vector2i(1, 0))
	layout.add_pad(Vector3i(40, 6, 40), SiegeLayout.PadKind.STREET)
	for i in range(4):
		var sx := 1 if (i % 2) == 0 else -1
		var sz := 1 if i < 2 else -1
		layout.add_outer_stone(
			Vector2i(
				FIX_CENTRE + sx * FIX_OUTER_OFFSET, FIX_CENTRE + sz * FIX_OUTER_OFFSET
			),
			6,
			4,
			12
		)
	for g in range(8):
		var bearing := TAU * float(g) / 8.0
		var mouth := Vector3i(
			FIX_CENTRE + int(round(cos(bearing) * float(FIX_GATE_RADIUS))),
			6,
			FIX_CENTRE + int(round(sin(bearing) * float(FIX_GATE_RADIUS)))
		)
		var outward := Vector2i(1, 0)
		if absf(cos(bearing)) < absf(sin(bearing)):
			outward = Vector2i(0, 1 if sin(bearing) >= 0.0 else -1)
		elif cos(bearing) < 0.0:
			outward = Vector2i(-1, 0)
		layout.add_hell_gate(mouth, outward, bearing)
	return layout


## Pot stake / spend / kill credit without spawning a real wave.
func _check_pot_and_stake() -> void:
	var city := _FakeCity.new()
	city.name = "FakeCity"
	add_child(city)
	var layout := _make_layout()
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

	## `start_run` opens the deployment window — the run's only pause, before the first wave.
	var phase_now: int = int(ctrl.phase())
	if phase_now != int(SiegeController.Phase.DEPLOY):
		_fail("FAIL expected DEPLOY after start, got %d" % phase_now)
	if ctrl.deploy_left() <= 0.0:
		_fail("FAIL deployment window opened with no time on it")
	_check_withdraw_ring(ctrl, city)
	## Withdrawal is legal for the whole run now: the gate is the ground by the crystal, not a phase.
	city.player_pos = ctrl.lodestone_world_pos()
	if not ctrl.withdraw():
		_fail("FAIL withdraw failed during a live run")
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
	_check_kill_haul_toasts(ctrl)
	_check_vulnerability_radius(ctrl, layout)


## Banking is the run's whole risk. The button lives on the HUD, so nothing physical stops the player
## pressing it from the rim — the rule has to: stand on the crystal's ground, and own it. Waves land
## on a clock and never stop, so a pot that could be cashed out from anywhere, or mid-fight, would
## cost nothing to keep.
func _check_withdraw_ring(ctrl: SiegeController, city: _FakeCity) -> void:
	var ring := ctrl.withdraw_clear_radius_m()
	if ring <= 0.0:
		_fail("FAIL withdraw ring is %.1f m, so banking is never gated" % ring)
		return
	var lode := ctrl.lodestone_world_pos()

	## Half one: out in the quarter with an empty ring, banking is still refused.
	city.player_pos = lode + Vector3(ring + 12.0, 0.0, 0.0)
	if ctrl.withdraw():
		_fail("FAIL banked the pot from %.0f m away — the walk back is free" % (ring + 12.0))
	if not ctrl.is_running():
		_fail("FAIL a refused withdraw ended the run anyway")
	if ctrl.withdraw_block_reason().is_empty():
		_fail("FAIL no reason given for banking from outside the ring")

	## Half two: standing at the crystal, but something else is standing there too.
	city.player_pos = lode
	var mob: UndeadUnit = UndeadUnit.new()
	mob.name = "RingBlocker"
	add_child(mob)
	## A bare unit has no city, and `tick` would deref it on the next physics frame.
	mob.set_physics_process(false)
	mob.global_position = lode + Vector3(ring * 0.5, 0.0, 0.0)
	ctrl._alive.append(mob)
	var blockers := ctrl.withdraw_blockers()
	if blockers != 1:
		_fail("FAIL a mob %.1f m from the stone counted %d blockers" % [ring * 0.5, blockers])
	if ctrl.withdraw():
		_fail("FAIL withdraw banked the pot with an attacker on the crystal")
	if ctrl.pot_total() <= 0:
		_fail("FAIL a refused withdraw emptied the pot")

	## Clear the ring: the reason line has to fall silent, or the HUD button never unlocks.
	mob.global_position = lode + Vector3(ring + 5.0, 0.0, 0.0)
	if ctrl.withdraw_blockers() != 0:
		_fail("FAIL a mob outside the %.0f m ring still blocks banking" % ring)
	if not ctrl.withdraw_block_reason().is_empty():
		_fail(
			"FAIL banking still blocked with a clear ring: %s" % ctrl.withdraw_block_reason()
		)
	ctrl._alive.erase(mob)
	remove_child(mob)
	mob.free()
	print("withdraw: banking needs the player inside a clear %.0f m ring" % ring)


## The haul used to credit the pot and only rename the loot card — without `add_gem` the card
## never becomes visible, so every kill looked unpaid even when Bigs scored. Drive the real
## `grant_monster_kill_haul` path and assert the toast lights up for KayKit-tier HP too.
func _check_kill_haul_toasts(ctrl: SiegeController) -> void:
	if not ctrl.is_running():
		## Withdraw ended the previous run — stake again so `active_siege_run` accepts credit.
		var city: _FakeCity = ctrl.get_parent().get_node("FakeCity") as _FakeCity
		if city == null:
			_fail("FAIL haul toast check lost the fake city")
			return
		city.inventory.add("gem_quartz", 5)
		if not ctrl.start_run({"gem_quartz": 5}):
			_fail("FAIL could not restart a run for the haul toast check")
			return
	var toast: LootToast = LootToast.new() as LootToast
	toast.name = "LootToast"
	add_child(toast)
	var city_root := CityRoot.new()
	city_root.name = "HaulCity"
	add_child(city_root)
	city_root._loot_toast = toast
	city_root._siege_run = ctrl
	var pot_before := ctrl.pot_total()
	city_root.grant_monster_kill_haul(Vector3.ZERO, 34.0)
	if ctrl.pot_total() != pot_before + 1:
		_fail(
			"FAIL siege fodder haul pot %d → %d, want +1"
			% [pot_before, ctrl.pot_total()]
		)
	if not toast.is_showing():
		_fail("FAIL siege kill haul left the loot card invisible")
	if toast.card_count() < 1:
		_fail("FAIL siege kill haul showed no gem cards")
	if toast.headline() != "Siege pot":
		_fail("FAIL siege kill haul headline is '%s', want 'Siege pot'" % toast.headline())
	city_root._siege_run = null
	city_root.queue_free()
	toast.queue_free()
	print("haul toast: fodder kill credits the pot and lights the loot card")


## The Lodestone has no collider, so one radius has to answer both "stop walking" and "you are
## hurting it". If a body could stop outside the damage zone it would be handed a fresh corridor
## every arrival and circle the crystal forever, which is exactly the bug this pins down.
##
## The number reaches the horde through the beacon's hold radius now, not through a spawn-time aim —
## a stone that dies mid-approach has to be able to retarget whoever was walking to it.
func _check_vulnerability_radius(ctrl: SiegeController, layout: SiegeLayout) -> void:
	var radius := ctrl.lodestone_vulnerable_radius_m()
	var crystal := float(layout.lodestone_radius_vox) * 0.5
	if radius <= crystal + UndeadGoalProvider.PUSH_RING_INSET_M:
		_fail(
			"FAIL vulnerability radius %.2f leaves the stand ring inside the %.2f crystal"
			% [radius, crystal]
		)
	var registry: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry
	registry.register(
		ctrl.lodestone_world_pos(), radius, int(MonsterFaction.Id.SIEGE_ATTACKER)
	)
	var beacon := registry.nearest_for(
		int(MonsterFaction.Id.SIEGE_ATTACKER), ctrl.lodestone_world_pos()
	)
	if beacon == null:
		_fail("FAIL a registered stone beacon is not visible to a siege attacker")
		return
	if not is_equal_approx(beacon.hold_radius_m, radius):
		_fail(
			"FAIL attacker holds at %.2f but the Lodestone bites at %.2f"
			% [beacon.hold_radius_m, radius]
		)
	print("lodestone: beacon hold radius == vulnerability radius (%.2f m)" % radius)


## A beacon is perception, not aggro: `nearest_for` is the whole reason a body 120 m away in another
## quarter walks toward a stone it cannot see. Two rules keep that from turning into noise — only the
## audience faction is handed one, and a body between two of them commits to the one it already had.
func _check_beacon_registry() -> void:
	var registry: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry
	var A := int(MonsterFaction.Id.SIEGE_ATTACKER)
	var U := int(MonsterFaction.Id.UNDEAD)
	var west := registry.register(Vector3(-40.0, 0.0, 0.0), 5.0, A)
	var east := registry.register(Vector3(40.0, 0.0, 0.0), 5.0, A)
	if registry.count() != 2:
		_fail("FAIL registry holds %d beacons, want 2" % registry.count())
	## Ambient wildlife must not see siege stones, or the north stone is chewed down before wave one.
	if registry.nearest_for(U, Vector3.ZERO) != null:
		_fail("FAIL a non-audience faction was handed a siege beacon")
	var near_west := registry.nearest_for(A, Vector3(-30.0, 0.0, 0.0))
	if near_west == null or near_west.id != west:
		_fail("FAIL nearest_for picked the far beacon")
	## Hysteresis: standing just past the midpoint, a body already walking west keeps walking west.
	var sticky := registry.nearest_for(A, Vector3(2.0, 0.0, 0.0), west)
	if sticky == null or sticky.id != west:
		_fail("FAIL a body a hair past the midpoint flipped its objective")
	## Past the stickiness slack the closer one has to win, or a body would walk across the tile.
	var flipped := registry.nearest_for(
		A, Vector3(BeaconRegistry.STICKY_SLACK_M + 4.0, 0.0, 0.0), west
	)
	if flipped == null or flipped.id != east:
		_fail("FAIL stickiness held past its slack — bodies would ignore the near stone")
	## A dead stone's id simply loses, which is what retargets everything that was chewing it.
	registry.unregister(west)
	var after := registry.nearest_for(A, Vector3(-30.0, 0.0, 0.0), west)
	if after == null or after.id != east:
		_fail("FAIL an unregistered beacon still held its followers")
	registry.clear_audience(A)
	if not registry.is_empty():
		_fail("FAIL clear_audience left %d beacons behind" % registry.count())
	print("beacons: faction-gated, sticky within %.0f m, dropped on death" % BeaconRegistry.STICKY_SLACK_M)


## The shield is the run: four outer stones stand between the horde and a pot, and the centre cannot
## be hurt until the last of them falls. Drive the contact tick directly rather than waiting on a
## real wave — the arithmetic is what matters, and a spawned horde would take minutes to walk it.
func _check_shield_and_gates() -> void:
	var city := _FakeCity.new()
	city.name = "ShieldCity"
	add_child(city)
	city.inventory.add("gem_quartz", 5)
	var layout := _make_layout()
	var ctrl: SiegeController = SiegeControllerScript.new() as SiegeController
	add_child(ctrl)
	ctrl.setup(layout, Vector3i.ZERO, 0.5, 42, city, Callable(), Callable(), Callable())
	if not ctrl.start_run({"gem_quartz": 5}):
		_fail("FAIL could not stake a run for the shield check")
		return
	if ctrl.stones().size() != 5:
		_fail("FAIL run built %d stone pools, want 5" % ctrl.stones().size())
		return
	if ctrl.outer_stones_alive() != 4:
		_fail("FAIL run opened with %d outer stones" % ctrl.outer_stones_alive())
	if not ctrl.centre_shielded():
		_fail("FAIL the centre is exposed with four outer stones standing")
	## Only the outer stones are perceivable. A centre beacon on wave one would send the whole horde
	## past the stones to stand on an invulnerable crystal.
	var registry := city.beacon_registry()
	if registry.count() != 4:
		_fail("FAIL %d beacons registered at run start, want 4 outer" % registry.count())

	var mob: UndeadUnit = UndeadUnit.new()
	mob.name = "Chewer"
	add_child(mob)
	mob.set_physics_process(false)
	ctrl._alive.append(mob)

	## Contact on the shielded centre does nothing at all.
	mob.global_position = ctrl.lodestone_world_pos()
	ctrl._tick_stones(30.0)
	if ctrl.lodestone_hp() < ctrl.lodestone_hp_max():
		_fail(
			"FAIL the shielded centre took %.0f damage"
			% (ctrl.lodestone_hp_max() - ctrl.lodestone_hp())
		)

	## Now walk it around the outer stones. Each is a separate pool, and each death is permanent.
	for i in range(4):
		var stone: SiegeController.StoneState = ctrl.stones()[i + 1]
		mob.global_position = stone.pos
		ctrl._tick_stones(stone.hp_max / GameData.siege_float("lodestone_dps_per_attacker") + 1.0)
		if stone.alive:
			_fail("FAIL %s survived a full contact pass" % stone.label)
		if stone.beacon_id != 0:
			_fail("FAIL %s kept its beacon after falling" % stone.label)
		var want_left := 3 - i
		if ctrl.outer_stones_alive() != want_left:
			_fail(
				"FAIL %d outer stones left after %s fell, want %d"
				% [ctrl.outer_stones_alive(), stone.label, want_left]
			)
	if ctrl.centre_shielded():
		_fail("FAIL the centre is still shielded with every outer stone down")
	if registry.count() != 1:
		_fail("FAIL last stand registered %d beacons, want the centre alone" % registry.count())
	## The centre is finally reachable, and now contact bites.
	mob.global_position = ctrl.lodestone_world_pos()
	ctrl._tick_stones(2.0)
	if ctrl.lodestone_hp() >= ctrl.lodestone_hp_max():
		_fail("FAIL the exposed centre still takes no contact damage")
	print(
		"shield: centre untouchable behind 4 × %.0f hp, exposed and biting once they fall"
		% GameData.siege_float("outer_stone_hp")
	)
	_check_gate_weights(ctrl, layout)
	ctrl._alive.erase(mob)
	remove_child(mob)
	mob.free()
	ctrl.shutdown()
	if not city.beacon_registry().is_empty():
		_fail("FAIL a finished run left beacons standing for the horde to walk to")
	ctrl.queue_free()
	city.queue_free()


## The arcs belong to the tile, not to a run.
##
## Four bridges of light converging on one crystal is the only thing that explains a Siege quarter to
## someone who has just walked into it: these four protect that one. Standing them up only after a
## stake meant the tile looked like ordinary city with some odd monuments in it, which is how a player
## ended up at an outer stone with no idea the mode existed. So they are up from the moment the
## controller exists, one goes out when its stone falls mid-run, and they are all back once the run is
## over — the stones themselves stand again for the next one.
func _check_idle_arcs() -> void:
	var city := _FakeCity.new()
	city.name = "ArcCity"
	add_child(city)
	city.inventory.add("gem_quartz", 5)
	var layout := _make_layout()
	var ctrl: SiegeController = SiegeControllerScript.new() as SiegeController
	add_child(ctrl)
	ctrl.setup(layout, Vector3i.ZERO, 0.5, 42, city, Callable(), Callable(), Callable())
	if _live_arcs(ctrl) != 4:
		_fail("FAIL an idle Siege tile shows %d shield arcs, want 4" % _live_arcs(ctrl))
		return
	if ctrl.stones().size() != 5:
		_fail("FAIL setup built %d stone pools, want 5 before any stake" % ctrl.stones().size())
		return

	if not ctrl.start_run({"gem_quartz": 5}):
		_fail("FAIL could not stake a run for the arc check")
		return
	if _live_arcs(ctrl) != 4:
		_fail("FAIL staking a run left %d arcs standing" % _live_arcs(ctrl))
	var mob: UndeadUnit = UndeadUnit.new()
	mob.name = "ArcChewer"
	add_child(mob)
	mob.set_physics_process(false)
	ctrl._alive.append(mob)
	var stone: SiegeController.StoneState = ctrl.stones()[1]
	mob.global_position = stone.pos
	ctrl._tick_stones(stone.hp_max / GameData.siege_float("lodestone_dps_per_attacker") + 1.0)
	if stone.alive:
		_fail("FAIL the arc check could not fell an outer stone")
	if _live_arcs(ctrl) != 3:
		_fail("FAIL a fallen stone left %d arcs up, want 3" % _live_arcs(ctrl))

	ctrl._alive.erase(mob)
	remove_child(mob)
	mob.free()
	## Ending the run puts the tile back to its resting state, stones and bridges together.
	ctrl._end_run(true)
	if _live_arcs(ctrl) != 4:
		_fail("FAIL a finished run left %d arcs, want the tile's own 4 back" % _live_arcs(ctrl))
	for s: SiegeController.StoneState in ctrl.stones():
		if not s.alive or s.hp < s.hp_max:
			_fail("FAIL %s did not come back to full between runs" % s.label)
			break
	print("arcs: 4 up on an idle tile, one out per fallen stone, all back when the run ends")

	## Teardown is the one place they go away, or a streamed-out tile leaks eighty meshes.
	ctrl.shutdown()
	if _live_arcs(ctrl) != 0:
		_fail("FAIL shutdown left %d arcs behind" % _live_arcs(ctrl))
	ctrl.queue_free()
	city.queue_free()


func _live_arcs(ctrl: SiegeController) -> int:
	var n := 0
	for stone: SiegeController.StoneState in ctrl.stones():
		if stone.arc != null and is_instance_valid(stone.arc):
			n += 1
	return n


## A wave has a direction. One primary mouth carries most of it, its neighbours get the spill, and
## nothing ever goes fully dark — a cold gate that could never spawn would let the player wall off a
## lane and stop playing.
func _check_gate_weights(ctrl: SiegeController, layout: SiegeLayout) -> void:
	var share := GameData.siege_float("gate_primary_share")
	var floor_w := GameData.siege_float("gate_weight_floor")
	var table := ctrl._roll_gate_weights(3, -1)
	if table.size() != layout.hell_gate_count():
		_fail("FAIL weight table has %d entries for %d gates" % [table.size(), layout.hell_gate_count()])
		return
	var hottest := -1
	var top := -1.0
	for i in range(table.size()):
		if table[i] < floor_w - 0.0001:
			_fail("FAIL gate %d weighted %.3f, below the %.3f floor" % [i, table[i], floor_w])
		if table[i] > top:
			top = table[i]
			hottest = i
	if not is_equal_approx(top, share):
		_fail("FAIL the primary gate weighs %.3f, want the authored share %.3f" % [top, share])
	## Deterministic: the same tile has to play the same wave order across a reload.
	var again := ctrl._roll_gate_weights(3, -1)
	for i in range(table.size()):
		if not is_equal_approx(table[i], again[i]):
			_fail("FAIL the weight table for wave 3 is not reproducible")
			break
	## Two waves out of the same mouth read as a stuck spawner rather than as pressure.
	var avoided := ctrl._roll_gate_weights(3, hottest)
	if ctrl._heaviest_gate(avoided) == hottest:
		_fail("FAIL the next wave picked the same primary gate again")
	print(
		"gates: %d mouths, primary %.2f, floor %.2f, no repeat bearing"
		% [table.size(), share, floor_w]
	)


## Stands in for the CityRoot methods SiegeController actually calls.
class _FakeCity:
	extends Node

	var inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	var _faction: int = int(MonsterFactionScript.Id.HUMAN)
	var active_siege: SiegeController = null
	## Where the test says the player stands. Banking is gated on standing at the crystal, and
	## plate colliders follow the player, so both rules read this.
	var player_pos: Vector3 = Vector3.ZERO
	## CityRoot owns this in the real game; the siege registers its stones here.
	var beacons: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry

	func get_inventory() -> PlayerInventory:
		return inventory

	func beacon_registry() -> BeaconRegistry:
		return beacons

	func get_player_position() -> Vector3:
		return player_pos

	func set_player_combat_faction(id: int) -> void:
		_faction = id

	func player_faction() -> int:
		return _faction

	func begin_siege_run(ctrl: SiegeController) -> void:
		active_siege = ctrl

	func end_siege_run(ctrl: SiegeController) -> void:
		if active_siege == ctrl:
			active_siege = null
