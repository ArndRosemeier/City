## The strip just under a monster's feet: that every live body has one, that it is the size of
## that body, that it draws the pool it is bound to, and that death takes it away again.
##
## Three of these are regressions nothing else in the suite would notice. A bar that keeps its
## last fraction after a hit is a bar that lies about a fight in progress. A bar that allocates
## its own mesh or its own material is forty meshes and forty materials at the wave cap, which is
## the same per-instance-resource mistake that once polluted the live world with preview nodes.
## And a bar left behind by a corpse is a node leak that only shows up after an hour of play.
##
## Run: powershell -File tools/run_test.ps1 test_monster_health_bar -KeepLog
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
## Parked away from every district and from the other tests' tiles.
const TILE := Vector2i(-422, -422)
const ORIGIN := Vector3i(72000, 0, 72000)
const SX := 96
const SZ := 96

## Bodies are chosen by seed, so the seed is pinned and every spawn names its model.
const BODY_SEED := 20260729
const EPS := 0.001
## What a giant grows to in `_test_growing_refits_the_bar`. Not the full ten: four is enough to
## prove the bar follows the body and keeps the test's arithmetic readable.
const GROWN_SCALE := 4.0

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		pass


class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		var monsters := MonsterRoster.new()
		monsters.name = "MonsterRoster"
		add_child(monsters)
		monsters.setup(city, terrain, lod)
		_roster = monsters


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	if not _boot_nav():
		_quit()
		return
	await _test_every_body_wears_one_shared_bar()
	if _failed:
		_quit()
		return
	await _test_size_comes_off_the_body()
	if _failed:
		_quit()
		return
	await _test_fill_follows_the_pool()
	if _failed:
		_quit()
		return
	await _test_growing_refits_the_bar()
	if _failed:
		_quit()
		return
	await _test_a_tower_hangs_its_bar_over_its_stamp()
	if _failed:
		_quit()
		return
	await _test_death_takes_the_bar_with_it()
	_quit()


# ---------------------------------------------------------------------------
# One bar per body, and one mesh and material for all of them
# ---------------------------------------------------------------------------

func _test_every_body_wears_one_shared_bar() -> void:
	var skeleton := _spawn(_w(Vector3i(20, 1, 20)), "kaykit/Skeleton_Minion")
	var monster := _spawn(_w(Vector3i(24, 1, 20)), "big/Frog")
	if skeleton == null or monster == null:
		return
	for unit: UndeadUnit in [skeleton, monster]:
		var bar := unit.health_bar()
		if bar == null:
			_fail("FAIL %s spawned with no health bar" % unit.creature_entry().id)
			return
		if bar.get_parent() != unit:
			_fail("FAIL the bar of %s hangs off %s" % [unit.creature_entry().id, bar.get_parent()])
			return
		if unit.get_node_or_null(NodePath(bar.name)) != bar:
			_fail("FAIL the bar of %s is not findable as '%s'" % [unit.creature_entry().id, bar.name])
			return
		if not is_equal_approx(bar.fraction(), 1.0):
			_fail("FAIL an untouched %s draws %.3f" % [unit.creature_entry().id, bar.fraction()])
			return
		if bar.mesh == null or bar.material_override == null:
			_fail("FAIL the bar of %s has no mesh or no material" % unit.creature_entry().id)
			return
		if bar.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("FAIL the bar of %s casts a shadow" % unit.creature_entry().id)
			return

	## The whole army draws off one quad and one material. Two bodies that do not agree on
	## either of those are a resource per monster.
	var a := skeleton.health_bar()
	var b := monster.health_bar()
	if a.mesh != b.mesh:
		_fail("FAIL two bars carry two meshes")
		return
	if a.material_override != b.material_override:
		_fail("FAIL two bars carry two materials")
		return
	if a.mesh != MonsterHealthBar.shared_mesh():
		_fail("FAIL a bar's mesh is not the shared quad")
		return
	if a.material_override != MonsterHealthBar.shared_material():
		_fail("FAIL a bar's material is not the shared one")
		return
	var material := a.material_override as ShaderMaterial
	if material == null or material.shader == null:
		_fail("FAIL the shared bar material has no shader")
		return
	if not is_equal_approx(float(material.get_shader_parameter("bar_aspect")), 1.0 / MonsterHealthBar.HEIGHT_FRACTION):
		_fail("FAIL the shared material draws at aspect %s" % str(material.get_shader_parameter("bar_aspect")))
		return
	## What the shader is actually handed. A fraction that never reaches the instance is a bar
	## that is only correct in GDScript.
	var drawn: Variant = a.get_instance_shader_parameter("fill")
	if typeof(drawn) != TYPE_FLOAT or not is_equal_approx(float(drawn), 1.0):
		_fail("FAIL the instance fill of a fresh bar is %s" % str(drawn))
		return
	print(
		"bars: skeleton and Frog both wear one, sharing quad %s and material %s"
		% [str(a.mesh.get_class()), str(material.resource_name)]
	)
	await _settle(skeleton)
	await _settle(monster)


# ---------------------------------------------------------------------------
# Size and place
# ---------------------------------------------------------------------------

## A bar is measured off the body, so the roster's whole spread of sizes is one rule. It also has
## to hang just under the soles: a strip at shin or waist height is a different feature.
func _test_size_comes_off_the_body() -> void:
	var bodies: PackedStringArray = PackedStringArray(
		["kaykit/Skeleton_Minion", "blob/GreenBlob", "big/Cactoro"]
	)
	var widths: Array[float] = []
	var units: Array[UndeadUnit] = []
	for id: String in bodies:
		var unit := _spawn(_w(Vector3i(30 + units.size() * 4, 1, 30)), id)
		if unit == null:
			return
		units.append(unit)
		var bar := unit.health_bar()
		var want := unit.hit_radius() * MonsterHealthBar.WIDTH_PER_HIT_RADIUS
		if absf(bar.width_m() - want) > EPS:
			_fail("FAIL %s wears a %.3f m bar, want %.3f m" % [id, bar.width_m(), want])
			return
		if absf(bar.scale.x - want) > EPS:
			_fail("FAIL %s draws its bar at scale %.3f" % [id, bar.scale.x])
			return
		if absf(bar.scale.y - want * MonsterHealthBar.HEIGHT_FRACTION) > EPS:
			_fail("FAIL %s draws a bar %.3f m tall" % [id, bar.scale.y])
			return
		## Just under the soles: the quad is centred, so its origin sits half a bar plus the
		## sole gap below the feet. Anything at or above y=0 rides the shins.
		var want_y := -(
			want * MonsterHealthBar.HEIGHT_FRACTION * 0.5
			+ want * MonsterHealthBar.FOOT_CLEARANCE_FRACTION
		)
		if absf(bar.position.y - want_y) > EPS:
			_fail(
				"FAIL %s draws its bar at %.3f m, want %.3f m under the feet"
				% [id, bar.position.y, want_y]
			)
			return
		if bar.position.y >= 0.0:
			_fail("FAIL %s draws its bar at or above the feet (%.3f)" % [id, bar.position.y])
			return
		if bar.visibility_range_end <= 0.0:
			_fail("FAIL %s draws its bar to infinity" % id)
			return
		## Clear of the body it is drawn over. A bar pulled less far than the meshes reach is a
		## bar with the monster's own belly through the middle of it, which is how the blob in
		## the screenshot harness first came out.
		var reach := unit.body_reach_m()
		if bar.camera_pull_m() <= reach:
			_fail(
				"FAIL %s pulls its bar %.3f m forward over a body that reaches %.3f m"
				% [id, bar.camera_pull_m(), reach]
			)
			return
		if absf(float(bar.get_instance_shader_parameter("camera_pull")) - bar.camera_pull_m()) > EPS:
			_fail("FAIL %s did not hand the shader its pull" % id)
			return
		widths.append(bar.width_m())
	## Width is `hit_radius` times a constant on every one of them, so the ordering is already
	## arithmetic. What is worth asserting is that the roster's own spread survives it: the
	## smallest spawnable blob and the tallest Big monster must not end up wearing the same bar.
	var narrowest: float = widths.min()
	var widest: float = widths.max()
	if widest / narrowest < 1.5:
		_fail("FAIL the roster's bodies all wear near-identical bars: %s" % str(widths))
		return
	print(
		"size: minion %.2f m, GreenBlob %.2f m, Cactoro %.2f m wide, each under its own feet"
		% [widths[0], widths[1], widths[2]]
	)
	for unit: UndeadUnit in units:
		await _settle(unit)


# ---------------------------------------------------------------------------
# The number it draws
# ---------------------------------------------------------------------------

## Hits go through the director, exactly as `CityRoot` deals them, so what is measured is the
## path a real shot takes rather than a setter nothing calls.
func _test_fill_follows_the_pool() -> void:
	var warrior := _spawn(_w(Vector3i(40, 1, 40)), "kaykit/Skeleton_Warrior")
	if warrior == null:
		return
	var bar := warrior.health_bar()
	if not _director.damage_unit(warrior, DamageSource.Id.PLAYER_LASER):
		_fail("FAIL the director refused a laser dart")
		return
	if not warrior.is_alive():
		_fail("FAIL one laser dart killed the warrior this case needs standing")
		return
	if warrior.health_fraction() >= 1.0:
		_fail("FAIL a hit warrior still reads full at %.3f" % warrior.health_fraction())
		return
	if absf(bar.fraction() - warrior.health_fraction()) > EPS:
		_fail(
			"FAIL the bar reads %.3f with the pool at %.3f"
			% [bar.fraction(), warrior.health_fraction()]
		)
		return
	var drawn: Variant = bar.get_instance_shader_parameter("fill")
	if typeof(drawn) != TYPE_FLOAT or absf(float(drawn) - warrior.health_fraction()) > EPS:
		_fail("FAIL the shader was handed %s with the pool at %.3f" % [str(drawn), warrior.health_fraction()])
		return
	var after_one := bar.fraction()
	_director.damage_unit(warrior, DamageSource.Id.PLAYER_LASER)
	if warrior.is_alive() and not (bar.fraction() < after_one):
		_fail("FAIL a second dart left the bar at %.3f" % bar.fraction())
		return
	print(
		"fill: one dart took a warrior's bar %.3f → %.3f, and the shader was handed the same"
		% [1.0, after_one]
	)
	await _settle(warrior)


## Growing on a pad makes a body bigger and tougher without healing it, so the bar has to grow
## with the body and hold the wound it already had.
func _test_growing_refits_the_bar() -> void:
	var unit := _spawn(_w(Vector3i(48, 1, 48)), "kaykit/Skeleton_Mage")
	if unit == null:
		return
	var bar := unit.health_bar()
	_director.damage_unit(unit, DamageSource.Id.PLAYER_LASER)
	if not unit.is_alive():
		_fail("FAIL one dart killed the mage this case needs standing")
		return
	var before_width := bar.width_m()
	var before_fraction := bar.fraction()
	unit.character_scale = GROWN_SCALE
	unit._apply_scale()
	if absf(bar.width_m() - before_width * GROWN_SCALE) > EPS:
		_fail(
			"FAIL a %.0fx body wears a %.3f m bar, want %.3f m"
			% [GROWN_SCALE, bar.width_m(), before_width * GROWN_SCALE]
		)
		return
	if absf(bar.fraction() - before_fraction) > EPS:
		_fail(
			"FAIL growing moved the bar from %.3f to %.3f"
			% [before_fraction, bar.fraction()]
		)
		return
	if absf(bar.fraction() - unit.health_fraction()) > EPS:
		_fail("FAIL after growing the bar reads %.3f and the pool %.3f" % [bar.fraction(), unit.health_fraction()])
		return
	print(
		"growing: a %.0fx body carries a %.2f m bar, still at %.3f of its own pool"
		% [GROWN_SCALE, bar.width_m(), bar.fraction()]
	)
	await _settle(unit)


# ---------------------------------------------------------------------------
# Siege towers
# ---------------------------------------------------------------------------

## A siege tower is a health pool with no body: the voxel stamp is the visual, and the combat host
## stands inside it at pad level. The bar is a half-size horizontal strip centred one voxel under
## the host — the foundation cell under the tower — not over the cap and not a vertical strip.
func _test_a_tower_hangs_its_bar_over_its_stamp() -> void:
	var defs: Array = SiegeTowerCatalog.all()
	if defs.is_empty():
		_fail("FAIL the siege tower catalogue is empty")
		return
	var def: SiegeTowerCatalog.Def = defs[0] as SiegeTowerCatalog.Def
	var muzzle_h := SiegeTowerCatalog.muzzle_height_m(def, VOXEL_SIZE)
	if muzzle_h <= 0.0:
		_fail("FAIL '%s' reports a muzzle at %.3f m" % [def.id, muzzle_h])
		return
	var hit_r := SiegeTowerCatalog.structure_hit_radius_m(def, VOXEL_SIZE)
	var tower: UndeadUnit = _director._roster.spawn_siege_tower(
		def.combat_id, _w(Vector3i(64, 1, 64)), def.hp, muzzle_h, hit_r, BODY_SEED
	)
	if tower == null:
		_fail("FAIL the roster refused a %s" % def.id)
		return
	tower.set_physics_process(false)
	var bar := tower.health_bar()
	if bar == null:
		_fail("FAIL a %s stands with no health bar" % def.id)
		return
	if bar.is_vertical():
		_fail("FAIL %s wears a vertical bar — towers are horizontal at the base" % def.id)
		return
	var want := (
		tower.hit_radius()
		* MonsterHealthBar.WIDTH_PER_HIT_RADIUS
		* MonsterHealthBar.STRUCTURE_SIZE_SCALE
	)
	if absf(bar.width_m() - want) > EPS:
		_fail("FAIL %s wears a %.3f m bar, want half-size %.3f m" % [def.id, bar.width_m(), want])
		return
	var want_thick := want * MonsterHealthBar.HEIGHT_FRACTION
	if absf(bar.scale.y - want_thick) > EPS:
		_fail(
			"FAIL %s bar thickness is %.3f m, want %.3f m"
			% [def.id, bar.scale.y, want_thick]
		)
		return
	if absf(bar.position.y + VOXEL_SIZE) > EPS:
		_fail(
			"FAIL %s draws its bar at %.3f m, want one voxel under the host (%.3f)"
			% [def.id, bar.position.y, -VOXEL_SIZE]
		)
		return
	if bar.visibility_range_end <= 0.0:
		_fail("FAIL %s draws its bar to infinity" % def.id)
		return
	var want_pull := (
		tower.hit_radius() + want * MonsterHealthBar.CAMERA_PULL_MARGIN_FRACTION
	)
	if absf(bar.camera_pull_m() - want_pull) > EPS:
		_fail(
			"FAIL %s pulls its bar %.3f m, want %.3f m to clear its own stamp"
			% [def.id, bar.camera_pull_m(), want_pull]
		)
		return
	if bar.material_override != MonsterHealthBar.shared_structure_material():
		_fail("FAIL %s is not on the structure health-bar material" % def.id)
		return
	print(
		"tower: %s wears a %.2f m horizontal bar at y=%.2f (half-size, base, pull=%.2f)"
		% [def.id, bar.width_m(), bar.position.y, bar.camera_pull_m()]
	)
	await get_tree().process_frame
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------

## The corpse stays for its death clip; the bar does not. It also has to be freed rather than
## merely forgotten, or every kill in a run leaves a quad hanging off a body nobody can see.
func _test_death_takes_the_bar_with_it() -> void:
	var unit := _spawn(_w(Vector3i(56, 1, 56)), "kaykit/Skeleton_Minion")
	if unit == null:
		return
	var bar := unit.health_bar()
	var bar_id := bar.get_instance_id()
	if not _director.damage_unit(unit, DamageSource.Id.PLAYER_MELEE):
		_fail("FAIL the director refused a punch")
		return
	if unit.is_alive():
		_fail("FAIL a punched skeleton is still standing at %.2f" % unit.health())
		return
	if unit.health_bar() != null:
		_fail("FAIL a corpse still reports a health bar")
		return
	if not is_instance_valid(unit):
		_fail("FAIL the corpse went before its death clip")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(instance_from_id(bar_id)):
		_fail("FAIL the bar was dropped but never freed")
		return
	for child in unit.get_children():
		if child is MonsterHealthBar:
			_fail("FAIL a corpse is still wearing '%s'" % child.name)
			return
	print("death: the strip is freed on the killing hit, the corpse stays for its clip")
	await _settle(unit)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _spawn(at: Vector3, body_id: String) -> UndeadUnit:
	var unit := _director._spawn_unit(UndeadUnit.Role.MINION, at, BODY_SEED, body_id)
	if unit == null:
		_fail("FAIL the director refused to spawn %s" % body_id)
		return null
	## Nothing here is a navigation test; the bodies stand where they are put.
	unit.set_physics_process(false)
	return unit


## A killed body frees itself 1.6 s later and nothing here waits that long, so bodies are
## dropped deliberately instead of accumulating across cases.
func _settle(unit: UndeadUnit) -> void:
	await get_tree().process_frame
	if is_instance_valid(unit):
		_director.despawn_unit(unit)
	await get_tree().process_frame


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
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
