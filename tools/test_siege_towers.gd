## Siege tower catalogue + pot build path (no full city bake).
##
## Run: powershell -File tools\run_test.ps1 test_siege_towers
extends Node

const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")
const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const SiegeLayoutScript := preload("res://scripts/city/siege_layout.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const SiegeBuildPickerScript := preload("res://scripts/city/siege_build_picker.gd")
const BeaconRegistryScript := preload("res://scripts/city/beacon_registry.gd")
const VoxelWardScript := preload("res://scripts/city/voxel_ward.gd")

## Nav scaffolding for the one test that spawns a real tower body.
const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
const TILE := Vector2i(-431, -431)
const ORIGIN := Vector3i(71000, 0, 71000)
const SX := 64
const SZ := 64

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CombatTableScript.reload()
	SiegeTowerCatalogScript.reload()
	_check_catalog()
	_check_combat_rows()
	_check_afford_and_spend()
	_check_tower_body()
	_check_voxel_ward()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _check_catalog() -> void:
	var ids := SiegeTowerCatalogScript.ids()
	var buildable := SiegeTowerCatalogScript.buildable()
	if buildable.size() != 6:
		_fail("FAIL expected 6 buildable towers, got %d" % buildable.size())
		return
	if ids.size() != buildable.size() + 1:
		_fail(
			"FAIL expected the six pad recipes plus one world-placed spire, got %d rows"
			% ids.size()
		)
		return
	for id: String in ids:
		var def: RefCounted = SiegeTowerCatalogScript.by_id(id) as RefCounted
		if def == null:
			_fail("FAIL missing def %s" % id)
			continue
		var voxels: PackedInt32Array = def.get("voxels") as PackedInt32Array
		var cost: Dictionary = def.get("cost") as Dictionary
		if voxels.is_empty() or voxels.size() % 4 != 0:
			_fail("FAIL bad voxels for %s" % id)
		if float(def.get("hp")) <= 0.0:
			_fail("FAIL bad hp for %s" % id)
		## A world-placed spire is never sold, so a price on it would be a pad listing waiting
		## to happen. Everything the player can buy costs exactly one gem.
		if not bool(def.get("buildable")):
			if not cost.is_empty():
				_fail("FAIL world-placed %s carries a cost %s" % [id, str(cost)])
			continue
		var cost_total := 0
		for k: Variant in cost.keys():
			cost_total += int(cost[k])
		if cost_total != 1 or cost.size() != 1:
			_fail("FAIL %s cost should be exactly one gem, got %s" % [id, str(cost)])
		## Fractal shaft + ORB tip — never collectible gem ore, never brick fabric.
		var n: int = voxels.size() / 4
		var saw_orb := false
		var top_oy := -1
		var top_mat := -1
		for i in range(n):
			var oy: int = voxels[i * 4 + 1]
			var mat: int = voxels[i * 4 + 3]
			if VoxelMaterial.is_gem(mat):
				_fail("FAIL %s stamp uses gem mat %d" % [id, mat])
			if mat == VoxelMaterial.ORB:
				saw_orb = true
			elif not VoxelMaterial.is_fractal_display(mat):
				_fail("FAIL %s shaft mat %d is not fractal-display" % [id, mat])
			if oy >= top_oy:
				top_oy = oy
				top_mat = mat
		if not saw_orb:
			_fail("FAIL %s stamp has no ORB tip" % id)
		if top_mat != VoxelMaterial.ORB:
			_fail("FAIL %s tip mat is %d, want ORB" % [id, top_mat])
	print(
		"catalog: %d fractal spires with ORB tips (%d for sale)"
		% [ids.size(), buildable.size()]
	)


func _check_combat_rows() -> void:
	for def_v: Variant in SiegeTowerCatalogScript.all():
		var def: RefCounted = def_v as RefCounted
		var combat_id := str(def.get("combat_id"))
		if not CombatTableScript.has_monster(combat_id):
			_fail("FAIL missing combat row %s" % combat_id)
			continue
		## Pad recipes defend; a world-placed spire is authored on a monster side and has its
		## faction set again at spawn, so only the bought ones are checked here.
		if bool(def.get("buildable")) and CombatTableScript.faction_for(combat_id) != "siege_defender":
			_fail("FAIL %s faction is not siege_defender" % combat_id)
		var stats := CombatTableScript.resolve(combat_id)
		if stats == null:
			_fail("FAIL resolve failed for %s" % combat_id)
			continue
		if float(stats.get("speed_mult")) > 0.0:
			_fail("FAIL %s speed_mult should be 0" % combat_id)
		var attacks: PackedStringArray = stats.get("attacks") as PackedStringArray
		if attacks.is_empty():
			_fail("FAIL %s has no attacks" % combat_id)
	print("combat: siege/* rows resolve as immobile siege_defender kits")


func _check_afford_and_spend() -> void:
	var layout: SiegeLayout = SiegeLayoutScript.new() as SiegeLayout
	layout.quarter_vox = Rect2i(0, 0, 224, 224)
	layout.deck_y = 6
	layout.lodestone_xz = Vector2i(112, 112)
	layout.lodestone_base_y = 6
	layout.lodestone_radius_vox = 5
	layout.lodestone_height_vox = 16
	layout.add_breach(Vector3i(112, 6, 0), Vector2i(0, 1))
	layout.add_pad(Vector3i(100, 6, 100), SiegeLayout.PadKind.STREET)
	layout.add_pad(Vector3i(120, 6, 100), SiegeLayout.PadKind.STREET)
	## A run needs its five stones and its mouths, even in a pad-only fixture: `start_run` builds a
	## pool and a beacon per stone, and `is_valid` refuses a layout that has none.
	for i in range(4):
		var sx := 1 if (i % 2) == 0 else -1
		var sz := 1 if i < 2 else -1
		layout.add_outer_stone(Vector2i(112 + sx * 100, 112 + sz * 100), 6, 4, 12)
	for g in range(8):
		var bearing := TAU * float(g) / 8.0
		layout.add_hell_gate(
			Vector3i(
				112 + int(round(cos(bearing) * 108.0)),
				6,
				112 + int(round(sin(bearing) * 108.0))
			),
			Vector2i(1, 0) if absf(cos(bearing)) >= absf(sin(bearing)) else Vector2i(0, 1),
			bearing
		)

	var inv: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	inv.add("gem_quartz", 20)
	inv.add("gem_amber", 10)

	var city := _FakeCity.new()
	city.name = "FakeCity"
	city.inventory = inv
	add_child(city)

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
	if not ctrl.start_run():
		_fail("FAIL start_run refused a free start")
		return
	_check_pad_plates(ctrl, layout, city)
	var def: RefCounted = SiegeTowerCatalogScript.by_id("splinter_post") as RefCounted
	var cost: Dictionary = def.get("cost") as Dictionary
	if not ctrl.can_afford(cost):
		_fail("FAIL should afford splinter_post from the bag")
	if not ctrl.spend_tower_cost(cost):
		_fail("FAIL spend_tower_cost splinter_post")
	if inv.count_of("gem_quartz") != 19:
		_fail("FAIL bag quartz should be 19 after 20−1, got %d" % inv.count_of("gem_quartz"))
	if ctrl.pot_total() != 0:
		_fail("FAIL tower spend put gems in the pot — costs come from the bag")
	if not ctrl.can_afford(cost):
		_fail("FAIL should still afford splinter_post on remaining quartz")
	var resin: RefCounted = SiegeTowerCatalogScript.by_id("resin_vat") as RefCounted
	var resin_cost: Dictionary = resin.get("cost") as Dictionary
	## Drain amber so resin is unaffordable, then drain quartz so the list empties.
	while inv.count_of("gem_amber") > 0:
		inv.remove("gem_amber", 1)
	if ctrl.can_afford(resin_cost):
		_fail("FAIL resin_vat should be unaffordable without amber in the bag")
	while ctrl.can_afford(cost):
		if not ctrl.spend_tower_cost(cost):
			_fail("FAIL spend while draining quartz")
			break
	## Empty bag of tower gems: the "+" still opens, the list just has nothing to sell.
	var empty_plate := ctrl.get_node_or_null("SiegePadPanel_0") as Ui3D
	city.player_pos = empty_plate.global_position
	empty_plate.button_pressed.emit(&"plus", Vector2.ZERO)
	if not city.picker.is_open():
		_fail("FAIL the + plate did not open the build picker on an empty bag")
	elif not city.picker.listed_tower_ids().is_empty():
		_fail(
			"FAIL empty bag still listed %s"
			% str(city.picker.listed_tower_ids())
		)
	city.picker.close_panel()
	## Kill loot fills the pot, not the bag — so amber credit must not unlock a tower.
	ctrl.credit_kill_mats([VoxelMaterial.GEM_AMBER])
	if ctrl.can_afford(resin_cost):
		_fail("FAIL resin_vat became affordable from pot amber — towers pay from the bag")
	inv.add("gem_amber", 1)
	if not ctrl.can_afford(resin_cost):
		_fail("FAIL resin_vat should be affordable after amber is in the bag")
	print("bag: one-gem costs + empty list recovery")
	ctrl.shutdown()
	ctrl.queue_free()


## The pad plate is the only way to reach a tower, so a plate with no button is a dead district,
## and a picker that lists a recipe the bag cannot pay for is a dead end the player can press.
func _check_pad_plates(ctrl: SiegeController, layout: SiegeLayout, city: _FakeCity) -> void:
	for i in range(layout.pad_count()):
		var plate := ctrl.get_node_or_null("SiegePadPanel_%d" % i) as Ui3D
		if plate == null:
			_fail("FAIL no pad plate for pad %d" % i)
			return
		if plate.button_at_uv(Vector2(0.5, 0.5)) != &"plus":
			_fail("FAIL pad plate %d has no + button in the middle of the face" % i)
			return
	_check_plate_lod(ctrl, layout, city)
	var first := ctrl.get_node_or_null("SiegePadPanel_0") as Ui3D
	## Operate range is 10 m — stand on the plate before pressing.
	city.player_pos = first.global_position
	first.button_pressed.emit(&"plus", Vector2.ZERO)
	if not city.picker.is_open():
		_fail("FAIL the + plate did not open the build picker")
		return
	if city.picker.pad_index() != 0:
		_fail("FAIL picker opened for pad %d, want 0" % city.picker.pad_index())
	## Bag has quartz and amber, so both one-gem recipes that match those gems are offered.
	var listed := city.picker.listed_tower_ids()
	if not listed.has("splinter_post") or not listed.has("resin_vat"):
		_fail(
			"FAIL bag with quartz+amber should list Splinter Post and Resin Vat, got %s"
			% str(listed)
		)
	if listed.has("arc_pylon"):
		_fail("FAIL bag without topaz listed Arc Pylon")
	city.picker.close_panel()
	if city.picker.is_open():
		_fail("FAIL picker stayed open after close")
	_check_plate_too_far(ctrl, city, first)
	print("pads: %d plates live, picker lists only affordable recipes" % layout.pad_count())


## A quarter carries hundreds of plates, which only works because each one draws at short range and
## carries no collider until the player is within view distance. Both are easy to lose in a refactor
## and neither shows up as a failure — the district just gets slow, and shots aimed low stop firing
## because `CityWalker._try_world_interact` swallows them on the first plate it rays.
func _check_plate_lod(ctrl: SiegeController, layout: SiegeLayout, city: _FakeCity) -> void:
	for i in range(layout.pad_count()):
		var plate := ctrl.get_node_or_null("SiegePadPanel_%d" % i) as Ui3D
		if plate.is_collision_enabled():
			_fail("FAIL pad plate %d was born with a live collider" % i)
			return
		if plate.view_distance_m <= 0.0:
			_fail("FAIL pad plate %d draws at any range — the view cutoff is missing" % i)
			return
		if plate.surface_color.a < 0.999:
			_fail("FAIL pad plate %d has a translucent face — hundreds of those is the slow path" % i)
			return
		var surface := plate.get_node_or_null("Surface") as GeometryInstance3D
		if surface == null:
			_fail("FAIL pad plate %d has no Surface mesh" % i)
			return
		if not is_equal_approx(surface.visibility_range_end, plate.view_distance_m):
			_fail(
				"FAIL pad plate %d culls at %.1f m but asked for %.1f"
				% [i, surface.visibility_range_end, plate.view_distance_m]
			)
			return
		if surface.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("FAIL pad plate %d casts shadows" % i)
			return
	## Inside view distance the collider goes live so a distant aim can toast instead of fire;
	## past view distance it stays deaf.
	var plate0 := ctrl.get_node_or_null("SiegePadPanel_0") as Ui3D
	city.player_pos = plate0.global_position + Vector3(20.0, 0.0, 0.0)
	ctrl._tick_plate_proximity(SiegeControllerScript.PLATE_PROXIMITY_INTERVAL_SEC)
	if not plate0.is_collision_enabled():
		_fail("FAIL pad plate 0 stayed deaf at 20 m (inside view distance)")
	city.player_pos = plate0.global_position + Vector3(40.0, 0.0, 0.0)
	ctrl._tick_plate_proximity(SiegeControllerScript.PLATE_PROXIMITY_INTERVAL_SEC)
	if plate0.is_collision_enabled():
		_fail("FAIL pad plate 0 kept a collider at 40 m (past view distance)")
	print(
		"plates: %.0f m view cutoff, operate ≤ %.0f m, colliders to view range"
		% [plate0.view_distance_m, SiegeControllerScript.PLATE_TOUCH_M]
	)


## Aiming a plate past operate range must not open the picker — toast and swallow the shot.
func _check_plate_too_far(ctrl: SiegeController, city: _FakeCity, plate: Ui3D) -> void:
	city.picker.close_panel()
	city.toast.last_message = ""
	city.player_pos = plate.global_position + Vector3(15.0, 0.0, 0.0)
	plate.button_pressed.emit(&"plus", Vector2.ZERO)
	if city.picker.is_open():
		_fail("FAIL pad press at 15 m opened the picker — operate range is 10 m")
		city.picker.close_panel()
	if city.toast.last_message != "too far to operate":
		_fail(
			"FAIL far pad press toasted '%s', want 'too far to operate'"
			% city.toast.last_message
		)


## Spawn a real tower body. A tower is a meshless `UndeadUnit` with no CreatureCatalog entry,
## so every catalogue-derived path it walks has to have an authored answer instead — that is the
## bug class this covers: `_apply_scale` used to ask `CreatureHealth` for a tier and got a
## "no catalogue entry" error at the moment the player bought the tower.
func _check_tower_body() -> void:
	var nav := NavService.instance()
	nav.ensure_configured(VOXEL_SIZE)
	if not nav.is_configured():
		_fail("FAIL NavService did not configure")
		return
	var bake := _bake_tile(nav)
	if bake == null:
		return
	if not nav.register_district(TILE, bake):
		_fail("FAIL NavService refused the test tile")
		return
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	add_child(terrain)
	terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var city: CityRoot = CityRoot.new()
	var roster: MonsterRoster = MonsterRosterScript.new() as MonsterRoster
	roster.name = "MonsterRoster"
	add_child(roster)
	roster.setup(city, terrain, NavLod.for_collision_view(48, VOXEL_SIZE))

	var def: RefCounted = SiegeTowerCatalogScript.by_id("splinter_post") as RefCounted
	var hp := float(def.get("hp"))
	var at := Vector3(
		float(ORIGIN.x + 8), float(ORIGIN.y + 1), float(ORIGIN.z + 8)
	) * VOXEL_SIZE
	var muzzle_h := (
		SiegeTowerCatalogScript.muzzle_height_m(def, VOXEL_SIZE)
		- SiegeControllerScript.TOWER_HOST_LIFT_M
	)
	var hit_r := SiegeTowerCatalogScript.structure_hit_radius_m(def, VOXEL_SIZE)
	var tower := roster.spawn_siege_tower(
		str(def.get("combat_id")), at, hp, muzzle_h, hit_r
	)
	if tower == null:
		_fail("FAIL roster refused to spawn a siege tower")
		_teardown_tower_scaffold(roster, terrain, city)
		return
	tower.set_physics_process(false)
	_check_tower_muzzle(tower, def, at)
	_check_tower_hunts_at_far_tier(tower)
	if not tower.is_siege_tower():
		_fail("FAIL spawned body does not report as a siege tower")
	if not tower.is_alive():
		_fail("FAIL fresh tower is not alive")
	if not is_equal_approx(tower.health_max(), hp):
		_fail(
			"FAIL tower max hp is %.1f, want the authored %.1f"
			% [tower.health_max(), hp]
		)
	if not is_equal_approx(tower.hit_radius(), hit_r):
		_fail(
			"FAIL tower hit radius is %.2f m, want stamp volume %.2f m"
			% [tower.hit_radius(), hit_r]
		)
	if tower.faction() != int(MonsterFactionScript.Id.SIEGE_DEFENDER):
		_fail("FAIL tower faction is %d, want SIEGE_DEFENDER" % tower.faction())
	## Player fire must never chew a pad the pot paid for.
	if tower.apply_damage_scaled(DamageSource.Id.PLAYER_MELEE, 1.0, "player", null):
		_fail("FAIL player melee killed an own tower")
	if not is_equal_approx(tower.health(), hp):
		_fail("FAIL player melee took %.1f hp off an own tower" % (hp - tower.health()))
	## The horde still gets to knock it down.
	tower.apply_damage_scaled(DamageSource.Id.MONSTER_MELEE_MOB, 1.0, "mob", null)
	if tower.health() >= hp:
		_fail("FAIL mob melee did not damage a tower")
	_check_melee_reaches_tower_wall(city, roster, tower, hit_r)
	print("body: meshless tower spawns with authored hp and takes only mob damage")
	roster.despawn_unit(tower)
	_teardown_tower_scaffold(roster, terrain, city)


## A body at the stamp wall is outside creature-scale melee of the host point, but inside the
## stamp hit volume. Without that volume, hunt never engages and swings never land.
func _check_melee_reaches_tower_wall(
	city: CityRoot, roster: MonsterRoster, tower: UndeadUnit, hit_r: float
) -> void:
	city._monsters = roster
	var melee := CombatTableScript.monster_attack_range_m("melee")
	## Past table melee of the host centre, still inside structure + swing.
	var wall_dist := hit_r + melee * 0.35
	if wall_dist <= melee + 0.05:
		## Tiny stamp: nothing to prove about the gap.
		print(
			"wall reach: stamp hit %.2f m is inside table melee %.2f m — skip gap case"
			% [hit_r, melee]
		)
		return
	var stand := tower.global_position + Vector3(wall_dist, 0.0, 0.0)
	var attacker: UndeadUnit = roster.spawn_by_id("kaykit/Skeleton_Minion", stand) as UndeadUnit
	if attacker == null:
		_fail("FAIL could not spawn a melee attacker for the tower wall case")
		return
	attacker.set_physics_process(false)
	attacker.set_faction(int(MonsterFactionScript.Id.SIEGE_ATTACKER))
	var aim := tower.global_position + Vector3(0.0, 1.0, 0.0)
	var provider := attacker.goal_provider()
	if provider == null:
		_fail("FAIL attacker has no goal provider")
		roster.despawn_unit(attacker)
		return
	provider.promote_attacker(tower)
	if provider._hunt(aim) != null:
		_fail(
			"FAIL wall stand at %.2f m opened a hunt corridor (hit %.2f m, melee %.2f m)"
			% [wall_dist, hit_r, melee]
		)
		roster.despawn_unit(attacker)
		return
	var combat: RefCounted = attacker.combat()
	if combat == null or not bool(combat.call("try_attack_living", aim)):
		_fail(
			"FAIL wall stand at %.2f m could not swing at the tower (hit %.2f m)"
			% [wall_dist, hit_r]
		)
		roster.despawn_unit(attacker)
		return
	print(
		"wall reach: attacker at %.2f m engages and swings (stamp hit %.2f m, melee %.2f m)"
		% [wall_dist, hit_r, melee]
	)
	roster.despawn_unit(attacker)


## The muzzle is where prey acquisition starts its voxel LOS probe, and a tower stands inside the
## mass it painted. A muzzle taken from body span — 1.35 m, what a creature with no catalogue entry
## falls back to — sits in the middle of its own stone: the probe is blocked at the first step,
## nothing is ever acquired, and a whole field of towers holds fire without one line in the log.
func _check_tower_muzzle(tower: UndeadUnit, def: RefCounted, host_pos: Vector3) -> void:
	var pad_y := host_pos.y - SiegeControllerScript.TOWER_HOST_LIFT_M
	## ORB tip is a full solid cell for LOS even though the mesh is a sphere — the eye must
	## clear that cell's top face, not sit in the mesh crown inside it.
	var cells := SiegeTowerCatalogScript.STAMP_BASE_CELLS + int(def.get("stamp_top_oy")) + 1
	var mass_top := pad_y + float(cells) * VOXEL_SIZE
	var muzzle := tower.muzzle_world()
	if muzzle.y <= mass_top:
		_fail(
			"FAIL tower muzzle y %.2f sits in its own tip cell (mass top %.2f)"
			% [muzzle.y, mass_top]
		)
		return
	print("muzzle: eye at %.2f m clears the ORB cell top at %.2f m" % [muzzle.y, mass_top])


## A tower must keep looking for targets however far it is from the player. Walkers past the LOD
## mid radius (80 m) skip the prey query and wander instead — nobody can see them fight. A tower
## cannot wander, and a quarter is wider than 80 m: taking that shortcut meant the far half of the
## defence stood idle while the horde ate it, which is exactly what the player saw. The tell is the
## goal: the shortcut's only output is a wander, so anything else means the query ran.
func _check_tower_hunts_at_far_tier(tower: UndeadUnit) -> void:
	var agent: NavAgent = tower._nav_agent
	if agent == null:
		_fail("FAIL tower has no nav agent, so nothing refreshes its prey")
		return
	agent._update_tier(tower.global_position + Vector3(500.0, 0.0, 0.0))
	if tower.nav_tier() != NavLod.Tier.FAR:
		_fail("FAIL tower tier is %s, wanted FAR" % NavLod.tier_name(tower.nav_tier()))
		return
	var goal: NavGoal = tower.goal_provider().next_goal(null)
	if goal == null:
		print("far tier: tower holds and keeps querying prey instead of wandering")
		return
	_fail("FAIL a far tower was handed a %s goal it can never walk" % goal.tag)


## A standing tower holds its own stamp against damage, which is what keeps its hit points the only
## way it comes down: without it a blast carves the footing out from under a live turret. The claim is
## per cell and per owner rather than a property of stone, because the stone in the wall behind the
## tower stays as carveable as it ever was — so what has to hold is that a released owner leaves
## nothing behind, and that two structures cannot both own a cell.
func _check_voxel_ward() -> void:
	var ward: VoxelWard = VoxelWardScript.new() as VoxelWard
	var mine := Vector3i(10, 4, 10)
	var theirs := Vector3i(20, 4, 20)
	if ward.holds(mine):
		_fail("FAIL a fresh ward already holds %v" % mine)
		return
	ward.claim(7, [mine, mine + Vector3i.UP] as Array[Vector3i])
	ward.claim(9, [theirs] as Array[Vector3i])
	if not ward.holds(mine) or not ward.holds(mine + Vector3i.UP):
		_fail("FAIL the ward dropped a claimed cell")
		return
	if ward.owner_of(mine) != 7 or ward.owner_of(theirs) != 9:
		_fail(
			"FAIL the ward reads owners %d and %d"
			% [ward.owner_of(mine), ward.owner_of(theirs)]
		)
		return
	if ward.cell_count() != 3:
		_fail("FAIL the ward holds %d cells, want 3" % ward.cell_count())
		return
	## Releasing one structure must not touch what another is standing on — two towers dying in the
	## same wave is the ordinary case.
	var dropped: Array[Vector3i] = ward.release(7)
	if dropped.size() != 2:
		_fail("FAIL releasing owner 7 did not give back its two cells")
		return
	if not dropped.has(mine) or not dropped.has(mine + Vector3i.UP):
		_fail("FAIL release did not return the cells owner 7 held")
		return
	if ward.holds(mine) or ward.holds(mine + Vector3i.UP):
		_fail("FAIL a released cell is still held")
		return
	if not ward.holds(theirs):
		_fail("FAIL releasing one owner took another's cell with it")
		return
	if not ward.release(7).is_empty():
		_fail("FAIL releasing owner 7 twice gave cells back twice")
		return
	print("ward: %d cells claimed per owner, released without touching a neighbour" % 3)


func _teardown_tower_scaffold(
	roster: MonsterRoster, terrain: VoxelTerrain, city: CityRoot
) -> void:
	if roster != null and is_instance_valid(roster):
		roster.clear_all()
		roster.queue_free()
	if terrain != null and is_instance_valid(terrain):
		terrain.queue_free()
	NavService.reset()
	if city != null and is_instance_valid(city):
		city.free()


func _bake_tile(nav: NavService) -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := nav.solidity_tables()
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
		nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test tile")
		return null
	return bake


class _ToastStub:
	extends RefCounted
	var last_message: String = ""

	func show_message(text: String) -> void:
		last_message = text


class _FakeCity:
	extends Node
	var inventory: PlayerInventory = null
	## The real picker, so the affordable-list rule is checked through the surface the player
	## presses rather than a stub that could drift from it.
	var picker: SiegeBuildPicker = null
	var toast: _ToastStub = _ToastStub.new()
	var player_pos: Vector3 = Vector3.ZERO
	var _faction: int = int(MonsterFactionScript.Id.HUMAN)
	## CityRoot owns this in the real game; a run registers a beacon per stone in it.
	var beacons: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry

	func _ready() -> void:
		picker = SiegeBuildPickerScript.new() as SiegeBuildPicker
		picker.name = "SiegeBuildPicker"
		add_child(picker)

	func get_inventory() -> PlayerInventory:
		return inventory

	func beacon_registry() -> BeaconRegistry:
		return beacons

	## Plate colliders follow the player, so the controller needs this every proximity tick.
	func get_player_position() -> Vector3:
		return player_pos

	func get_loot_toast() -> _ToastStub:
		return toast

	func open_siege_build_picker(pad_index: int, controller: Node) -> void:
		picker.open_for_pad(pad_index, controller, Vector2.ZERO)

	func close_siege_build_picker() -> void:
		picker.close_panel()

	func refresh_siege_build_picker() -> void:
		picker.refresh()

	func begin_siege_run(_ctrl: Variant) -> void:
		pass

	func end_siege_run(_ctrl: Variant) -> void:
		pass

	func set_player_combat_faction(id: int) -> void:
		_faction = id

	func voxel_brush() -> Variant:
		return null

	func voxel_terrain() -> Variant:
		return null
