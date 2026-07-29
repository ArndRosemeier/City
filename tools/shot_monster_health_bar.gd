## Photographs the strip under a monster's feet, on bodies the size of the roster's extremes and
## at four different states of the pool.
##
## What a headless assertion cannot answer about this feature is whether the bar is legible: a
## strip sized off a skeleton's hit radius has to still read on a four-times giant, and one drawn
## at a body's feet has to stay out of that body's own legs from wherever the camera is. Both are
## picture questions, so this stands four bodies on a pad, wounds three of them by known amounts
## and saves what the screen actually looked like, with the numbers printed beside each shot.
##
## Run: powershell -File tools\run_test.ps1 shot_monster_health_bar -Rendered
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
## Parked away from every district and from the tests' tiles.
const TILE := Vector2i(-424, -424)
const ORIGIN := Vector3i(74000, 0, 74000)
const SX := 96
const SZ := 96
const BODY_SEED := 20260729

const LINEUP_PNG := "res://tools/monster_health_bar_lineup.png"
const CLOSEUP_PNG := "res://tools/monster_health_bar_closeup.png"
## The widest body in the roster relative to its hit radius, and the one the camera pull has to
## clear. A blob whose bar is inside the blob is the failure this shot is here to catch.
const BLOB_PNG := "res://tools/monster_health_bar_blob.png"

## What a grown body in the lineup stands at. Not the full ten: a 10x giant would be the only
## thing in the frame, and the claim being photographed is that one rule dresses every size.
const GROWN_SCALE := 4.0
## Where the four bodies stand, in voxels along x on one z line.
const STAND_X: Array[int] = [28, 40, 54, 74]
const STAND_Z := 40

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain
var _stage: Node3D


class TestCity:
	extends CityRoot

	func adjust_player_score(delta: int) -> void:
		pass

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		pass


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
	if not _boot_nav():
		_finish()
		return
	_build_stage()
	_hide_error_panel()

	## Full, lightly chipped, halfway down, and nearly finished — the whole colour ramp in one
	## frame, on bodies that are 1.8, 2.2, 3.2 and (grown) 10.5 units tall.
	var blob := _place(0, "blob/GreenBlob", 1.0, 1.0)
	var skeleton := _place(1, "kaykit/Skeleton_Warrior", 1.0, 0.72)
	var orc := _place(2, "big/Orc", 1.0, 0.5)
	var giant := _place(3, "kaykit/Skeleton_Mage", GROWN_SCALE, 0.22)
	if _failed:
		_finish()
		return

	await _shoot_lineup([blob, skeleton, orc, giant])
	await _shoot_closeup(skeleton, CLOSEUP_PNG)
	await _shoot_closeup(blob, BLOB_PNG)
	_finish()


# ---------------------------------------------------------------------------
# Subjects
# ---------------------------------------------------------------------------

## One body on the pad, grown to `body_scale` and worn down to `target_fraction`.
func _place(slot: int, body_id: String, body_scale: float, target_fraction: float) -> UndeadUnit:
	var unit := _director._spawn_unit(
		UndeadUnit.Role.MINION, _w(Vector3i(STAND_X[slot], 1, STAND_Z)), BODY_SEED, body_id
	)
	if unit == null:
		_fail("FAIL the director refused to spawn %s" % body_id)
		return null
	unit.set_physics_process(false)
	if not is_equal_approx(body_scale, 1.0):
		unit.character_scale = body_scale
		unit._apply_scale()
	if not is_equal_approx(target_fraction, 1.0):
		_wound_to(unit, target_fraction)
	return unit


## Eye-laser darts until the body is at or below `target`, which is how a player would get it
## there. A body that dies on the way is a body this shot cannot photograph, and it says so
## rather than leaving an empty patch of pavement in the frame.
func _wound_to(unit: UndeadUnit, target: float) -> void:
	var darts := 0
	while unit.is_alive() and unit.health_fraction() > target and darts < 40:
		_director.damage_unit(unit, DamageSource.Id.PLAYER_LASER)
		darts += 1
	if not unit.is_alive():
		_fail(
			"FAIL %s died after %d darts on the way to %.2f"
			% [unit.creature_entry().id, darts, target]
		)


# ---------------------------------------------------------------------------
# Shots
# ---------------------------------------------------------------------------

func _shoot_lineup(units: Array) -> void:
	var left := _w(Vector3i(STAND_X[0], 1, STAND_Z))
	var right := _w(Vector3i(STAND_X[STAND_X.size() - 1], 1, STAND_Z))
	var middle := (left + right) * 0.5
	var span := right.x - left.x
	var tallest := 0.0
	for unit: UndeadUnit in units:
		tallest = maxf(tallest, unit.hit_half_height() * 2.0)
	await _shoot(
		Vector3(middle.x, middle.y + tallest * 0.75, middle.z + span * 0.95),
		Vector3(middle.x, middle.y + tallest * 0.35, middle.z),
		LINEUP_PNG,
		units
	)


## Close enough to read the frame, the track and the fill on one wounded body, which is the
## thing the lineup is too wide to answer.
func _shoot_closeup(unit: UndeadUnit, path: String) -> void:
	var feet := unit.global_position
	var height := unit.hit_half_height() * 2.0
	await _shoot(
		feet + Vector3(0.9, height * 0.55, 3.2),
		feet + Vector3(0.0, height * 0.30, 0.0),
		path,
		[unit]
	)


func _shoot(eye: Vector3, target: Vector3, path: String, units: Array) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 45.0
	cam.far = 900.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(0.5)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image for %s" % path)
		cam.queue_free()
		return
	img.save_png(path)
	print("SAVED %s" % path)
	for unit: UndeadUnit in units:
		var bar := unit.health_bar()
		if bar == null:
			_fail("FAIL %s stands in the shot with no bar" % unit.creature_entry().id)
			continue
		if absf(bar.fraction() - unit.health_fraction()) > 0.001:
			_fail(
				"FAIL %s draws %.3f with its pool at %.3f"
				% [unit.creature_entry().id, bar.fraction(), unit.health_fraction()]
			)
			continue
		print(
			"    %-24s scale %4.1fx  health %6.1f/%6.1f (%3.0f%%)  bar %5.2f m wide, %4.2f m up"
			% [
				unit.creature_entry().id,
				unit.character_scale,
				unit.health(),
				unit.health_max(),
				bar.fraction() * 100.0,
				bar.width_m(),
				bar.position.y,
			]
		)
	cam.queue_free()


# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sky_mat.ground_bottom_color = Color(0.24, 0.24, 0.26)
	sky_mat.ground_horizon_color = Color(0.45, 0.45, 0.47)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	_stage.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 155.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	_stage.add_child(sun)

	## The bodies stand on the baked tile's deck, which has no mesh of its own out here.
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(180.0, 180.0)
	pad.mesh = plane
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.30, 0.31, 0.33)
	pad_mat.roughness = 0.95
	pad.material_override = pad_mat
	pad.position = _w(Vector3i(STAND_X[1], 1, STAND_Z))
	_stage.add_child(pad)


## Boot warnings would otherwise sit across the middle of every shot.
func _hide_error_panel() -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		_fail("FAIL no ErrorOverlay autoload")
		return
	panel.visible = false


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

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


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _finish() -> void:
	if _director != null and is_instance_valid(_director):
		_director.clear_all()
	NavService.reset()
	if _city != null:
		_city.free()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
