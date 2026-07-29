## Combat-table wiring on live units + N-key summon roster.
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
const AIM_ERROR_DEG := 5.0
const WIDE_LOOK_DEG := 35.0

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot
	var score: int = 0

	## Combat targeting rays the physics world, so this CityRoot has to be in the tree — but it
	## must not boot a city to get there.
	func _ready() -> void:
		pass

	func bind_player(walker: CharacterBody3D) -> void:
		_walker = walker

	func adjust_player_score(delta: int) -> void:
		score += delta

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		pass

	## Harness binds a TestDirector with its own terrain; skip CityRoot.setup().
	func _ensure_undead_director() -> void:
		if _undead == null or not is_instance_valid(_undead):
			push_error("TestCity: undead director not bound before summon")
			assert(false, "TestCity: no undead")


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
	await _test_combat_target_cone()
	if _failed:
		_quit()
		return
	await _test_freed_unit_aim_query()
	if _failed:
		_quit()
		return
	await _test_melee_hurts_player()
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
	var hp_mult := float(stats.get("hp_mult"))
	if absf(hp_mult - 0.5) > 0.001:
		_fail("FAIL minion hp_mult %.3f want 0.5" % hp_mult)
		return
	var attacks: PackedStringArray = stats.get("attacks") as PackedStringArray
	if not _has_str(attacks, "melee"):
		_fail("FAIL minion attacks missing melee: %s" % str(attacks))
		return
	if not _has_str(attacks, "nibble"):
		_fail("FAIL minion attacks missing nibble")
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


## CityRoot.summon_monster_at_aim must place at cursor aim (same ray as meteor), never at feet.
func _test_summon_at_aim() -> void:
	var aim_pos := _w(Vector3i(40, 1, 28))
	var stub := AimStub.new()
	stub.name = "AimStub"
	stub.aim = {"point": aim_pos, "normal": Vector3.UP, "did_hit": true}
	## Bound as the player, so it has to be in the tree: CityRoot reads its global position and
	## every unit that ticks asks for it.
	add_child(stub)
	stub.set_physics_process(false)
	_city.bind_player(stub)
	_city._undead = _director
	_city._booting = false
	_city._game_over = false
	var unit := _city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL summon_monster_at_aim returned null on hit")
		return
	if unit.global_position.distance_to(aim_pos) > 0.05:
		_fail(
			"FAIL summon placed at %s want aim %s"
			% [str(unit.global_position), str(aim_pos)]
		)
		_despawn(unit)
		return
	_despawn(unit)
	stub.aim = {"point": Vector3.ZERO, "normal": Vector3.UP, "did_hit": false}
	var missed := _city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if missed != null:
		_fail("FAIL summon_monster_at_aim must not spawn on aim miss")
		_despawn(missed)
		return
	print("summon aim: hit at %s, miss refused" % str(aim_pos))


## Nothing draws a reticle, so the player's look is always a few degrees off the body — and in
## third person the crosshair grazes the street deck long before it reaches the mob. Targeting
## must still resolve onto the creature, must stop at a wall between muzzle and body, and must
## leave the geometry point alone when the player is looking somewhere else entirely.
func _test_combat_target_cone() -> void:
	_city._undead = _director
	var unit := _spawn(
		UndeadUnit.Role.MINION, _w(Vector3i(40, 1, 40)), "kaykit/Skeleton_Minion"
	)
	if unit == null:
		return
	## This harness has no player node for the body to walk toward; the test only wants it to
	## stand still and be shootable.
	unit.set_physics_process(false)
	var chest := unit.global_position + Vector3(0.0, unit.hit_half_height() * 0.85, 0.0)
	## Camera behind and above the player; muzzle at body height 8 m short of the mob.
	var cam_from := chest + Vector3(0.0, 4.0, -8.0)
	var muzzle := chest + Vector3(0.0, -0.2, -8.0)
	var look := _tilt_down((chest - cam_from).normalized(), AIM_ERROR_DEG)
	## Where the deck stops the look ray: far short of the mob, exactly the failing case.
	var ground_point := cam_from + look * 3.5
	var on_body: Dictionary = _city.resolve_combat_target(
		cam_from, look, 80.0, ground_point, muzzle
	)
	if not bool(on_body["is_agent"]):
		_fail(
			"FAIL %.0f° off-centre look kept ground %s instead of the mob at %s"
			% [AIM_ERROR_DEG, str(ground_point), str(chest)]
		)
		_despawn(unit)
		return
	var body_point: Vector3 = on_body["point"] as Vector3
	if body_point.distance_to(chest) > unit.hit_half_height():
		_fail("FAIL target %s is not on the mob at %s" % [str(body_point), str(chest)])
		_despawn(unit)
		return
	if absf(float(on_body["distance"]) - muzzle.distance_to(body_point)) > 0.05:
		_fail("FAIL target distance %.2f is not measured from the muzzle" % on_body["distance"])
		_despawn(unit)
		return
	## Looking well past the mob is a miss, not a magnet.
	var wide := _tilt_down((chest - cam_from).normalized(), WIDE_LOOK_DEG)
	var wide_ground := cam_from + wide * 3.5
	var missed: Dictionary = _city.resolve_combat_target(
		cam_from, wide, 80.0, wide_ground, muzzle
	)
	if bool(missed["is_agent"]):
		_fail("FAIL %.0f° off-centre look still snapped to the mob" % WIDE_LOOK_DEG)
		_despawn(unit)
		return
	if (missed["point"] as Vector3).distance_to(wide_ground) > 0.001:
		_fail("FAIL miss moved the geometry point %s" % str(missed["point"]))
		_despawn(unit)
		return
	## A wall across the muzzle line stops the shot even though the mob is dead centre.
	var wall := _add_wall(muzzle.lerp(chest, 0.5))
	await get_tree().physics_frame
	var blocked: Dictionary = _city.resolve_combat_target(
		cam_from, look, 80.0, ground_point, muzzle
	)
	remove_child(wall)
	wall.free()
	if bool(blocked["is_agent"]):
		_fail("FAIL wall between muzzle and mob did not stop the shot")
		_despawn(unit)
		return
	_despawn(unit)
	await get_tree().physics_frame
	## No creature left: geometry is handed back untouched (summon / meteor ground aim).
	var empty: Dictionary = _city.resolve_combat_target(
		cam_from, look, 80.0, ground_point, muzzle
	)
	if bool(empty["is_agent"]) or (empty["point"] as Vector3).distance_to(ground_point) > 0.001:
		_fail("FAIL empty world moved the geometry point %s" % str(empty["point"]))
		return
	print(
		"combat target: %.0f° off-centre hits the mob past the deck, %.0f° misses, wall blocks"
		% [AIM_ERROR_DEG, WIDE_LOOK_DEG]
	)


## Pitch `dir` down by `degrees` — the aim error a player makes with no reticle to line up.
static func _tilt_down(dir: Vector3, degrees: float) -> Vector3:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		return dir
	var axis := side.normalized()
	var tilted := dir.rotated(axis, deg_to_rad(degrees))
	if tilted.y > dir.y:
		tilted = dir.rotated(axis, -deg_to_rad(degrees))
	return tilted.normalized()


func _add_wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "AimWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 8.0, 0.5)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	return body


class AimStub:
	extends CharacterBody3D
	var aim: Dictionary = {}

	func aim_world_at_cursor() -> Dictionary:
		return aim


func _test_melee_hurts_player() -> void:
	var walker := CityWalker.new()
	walker.name = "TestWalker"
	add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	_city.bind_player(walker)
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
	var _score: int = unit.kill_from_player()
	if _director._units.has(unit):
		_fail("FAIL dead unit still registered on the director")
		unit.queue_free()
		return
	var roster_after_death := _director._units.size()
	unit.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	## Must not throw "Nonexistent function is_alive in base previously freed".
	var after: Dictionary = _director.query_segment_hit(from, to)
	if _director._units.size() != roster_after_death:
		_fail(
			"FAIL director roster changed after free (%d → %d)"
			% [roster_after_death, _director._units.size()]
		)
		return
	if not after.is_empty():
		var hit_unit: Variant = after.get("unit", null)
		if hit_unit != null and not is_instance_valid(hit_unit):
			_fail("FAIL query_segment_hit returned a freed unit")
			return
	print("freed-unit aim: living hit ok, post-death query_segment_hit safe")


func _despawn(unit: UndeadUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _director != null and _director._units.has(unit):
		_director.unregister_unit(unit)
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


func _bake_tile() -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := _nav.solidity_tables()
	var bake = CityVoxelNativeScript.make_nav_bake()
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
	return bake as RefCounted


func _quit() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
