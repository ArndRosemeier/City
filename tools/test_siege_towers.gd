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
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _check_catalog() -> void:
	var ids := SiegeTowerCatalogScript.ids()
	if ids.size() != 6:
		_fail("FAIL expected 6 towers, got %d" % ids.size())
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
		if cost.is_empty() or float(def.get("hp")) <= 0.0:
			_fail("FAIL bad cost/hp for %s" % id)
		var cost_total := 0
		for k: Variant in cost.keys():
			cost_total += int(cost[k])
		if cost_total != 1 or cost.size() != 1:
			_fail("FAIL %s cost should be exactly one gem, got %s" % [id, str(cost)])
		## No collectible gem mats in the stamp.
		var n: int = voxels.size() / 4
		for i in range(n):
			var mat: int = voxels[i * 4 + 3]
			if VoxelMaterial.is_gem(mat):
				_fail("FAIL %s stamp uses gem mat %d" % [id, mat])
	print("catalog: %d towers, one gem each" % ids.size())


func _check_combat_rows() -> void:
	for def_v: Variant in SiegeTowerCatalogScript.all():
		var def: RefCounted = def_v as RefCounted
		var combat_id := str(def.get("combat_id"))
		if not CombatTableScript.has_monster(combat_id):
			_fail("FAIL missing combat row %s" % combat_id)
			continue
		if CombatTableScript.faction_for(combat_id) != "siege_defender":
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
	layout.add_gate(Vector3i(112, 6, 0), Vector2i(0, 1))
	layout.add_pad(Vector3i(100, 6, 100), SiegeLayout.PadKind.STREET)
	layout.add_pad(Vector3i(120, 6, 100), SiegeLayout.PadKind.STREET)

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
	if not ctrl.start_run({"gem_quartz": 5}):
		_fail("FAIL start_run with quartz stake")
		return
	_check_pad_plates(ctrl, layout, city)
	var def: RefCounted = SiegeTowerCatalogScript.by_id("splinter_post") as RefCounted
	var cost: Dictionary = def.get("cost") as Dictionary
	if not ctrl.can_afford(cost):
		_fail("FAIL should afford splinter_post after stake")
	if not ctrl.spend_from_pot(cost):
		_fail("FAIL spend_from_pot splinter_post")
	if ctrl.pot_total() != 4:
		_fail("FAIL pot should be 4 after 5−1, got %d" % ctrl.pot_total())
	if not ctrl.can_afford(cost):
		_fail("FAIL should still afford splinter_post on remaining quartz")
	var resin: RefCounted = SiegeTowerCatalogScript.by_id("resin_vat") as RefCounted
	var resin_cost: Dictionary = resin.get("cost") as Dictionary
	if ctrl.can_afford(resin_cost):
		_fail("FAIL resin_vat should be unaffordable without amber in pot")
	## Drain quartz so the list has nothing left — console must not soft-lock.
	while ctrl.can_afford(cost):
		if not ctrl.spend_from_pot(cost):
			_fail("FAIL spend while draining quartz")
			break
	## Empty pot: the "+" still opens, the list just has nothing to sell.
	var empty_plate := ctrl.get_node_or_null("SiegePadPanel_0") as Ui3D
	empty_plate.button_pressed.emit(&"plus", Vector2.ZERO)
	if not city.picker.is_open():
		_fail("FAIL the + plate did not open the build picker on an empty pot")
	elif not city.picker.listed_tower_ids().is_empty():
		_fail(
			"FAIL empty pot still listed %s"
			% str(city.picker.listed_tower_ids())
		)
	city.picker.close_panel()
	ctrl.credit_kill_mats([VoxelMaterial.GEM_AMBER])
	if not ctrl.can_afford(resin_cost):
		_fail("FAIL resin_vat should be affordable after amber credit")
	print("pot: one-gem costs + empty list recovery")
	ctrl.shutdown()
	ctrl.queue_free()


## The pad plate is the only way to reach a tower, so a plate with no button is a dead district,
## and a picker that lists a recipe the pot cannot pay for is a dead end the player can press.
func _check_pad_plates(ctrl: SiegeController, layout: SiegeLayout, city: _FakeCity) -> void:
	for i in range(layout.pad_count()):
		var plate := ctrl.get_node_or_null("SiegePadPanel_%d" % i) as Ui3D
		if plate == null:
			_fail("FAIL no pad plate for pad %d" % i)
			return
		if plate.button_at_uv(Vector2(0.5, 0.5)) != &"plus":
			_fail("FAIL pad plate %d has no + button in the middle of the face" % i)
			return
	var first := ctrl.get_node_or_null("SiegePadPanel_0") as Ui3D
	first.button_pressed.emit(&"plus", Vector2.ZERO)
	if not city.picker.is_open():
		_fail("FAIL the + plate did not open the build picker")
		return
	if city.picker.pad_index() != 0:
		_fail("FAIL picker opened for pad %d, want 0" % city.picker.pad_index())
	## Stake was quartz-only, so only the quartz recipe may be offered.
	var listed := city.picker.listed_tower_ids()
	if listed != PackedStringArray(["splinter_post"]):
		_fail(
			"FAIL quartz stake should list Splinter Post alone, got %s" % str(listed)
		)
	city.picker.close_panel()
	if city.picker.is_open():
		_fail("FAIL picker stayed open after close")
	print("pads: %d plates live, picker lists only affordable recipes" % layout.pad_count())


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
	var tower := roster.spawn_siege_tower(str(def.get("combat_id")), at, hp)
	if tower == null:
		_fail("FAIL roster refused to spawn a siege tower")
		_teardown_tower_scaffold(roster, terrain, city)
		return
	tower.set_physics_process(false)
	if not tower.is_siege_tower():
		_fail("FAIL spawned body does not report as a siege tower")
	if not tower.is_alive():
		_fail("FAIL fresh tower is not alive")
	if not is_equal_approx(tower.health_max(), hp):
		_fail(
			"FAIL tower max hp is %.1f, want the authored %.1f"
			% [tower.health_max(), hp]
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
	print("body: meshless tower spawns with authored hp and takes only mob damage")
	roster.despawn_unit(tower)
	_teardown_tower_scaffold(roster, terrain, city)


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


class _FakeCity:
	extends Node
	var inventory: PlayerInventory = null
	## The real picker, so the affordable-list rule is checked through the surface the player
	## presses rather than a stub that could drift from it.
	var picker: SiegeBuildPicker = null
	var _faction: int = int(MonsterFactionScript.Id.HUMAN)

	func _ready() -> void:
		picker = SiegeBuildPickerScript.new() as SiegeBuildPicker
		picker.name = "SiegeBuildPicker"
		add_child(picker)

	func get_inventory() -> PlayerInventory:
		return inventory

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
