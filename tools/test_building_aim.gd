## Third-person look at a building facade. The camera clears the street to the wall, but the
## lower muzzle ray strikes the deck first. Combat (ACTORS_AND_VOXELS) must still resolve onto
## the facade — not dump into the ground a few metres ahead. VOXELS_ONLY keeps first-surface
## camera geometry (summon/placement).
##
## Run: powershell -File tools\run_test.ps1 test_building_aim -KeepLog
extends Node3D

const REACH_M := 80.0
const WALL_Z := 18.0
const WALL_FACE_Z := WALL_Z - 0.25
const DECK_Y := 0.0
const MUZZLE := Vector3(0.0, 1.15, 0.0)
const CAM_FROM := Vector3(0.0, 3.8, -1.2)
## Mid-low facade — camera hits the wall; muzzle→intent dips into the deck first.
const FACADE_POINT := Vector3(0.0, 1.35, WALL_FACE_Z)


var _failed := false
var _city: TestCity


class TestCity:
	extends CityRoot

	func _ready() -> void:
		pass


## Camera geometry is the facade (screen intent). Muzzle combat raycasts the live deck+wall.
class FacadeWalker:
	extends CityWalker
	var test_origin: Vector3 = Vector3.ZERO
	var test_direction: Vector3 = Vector3.FORWARD
	var test_geometry: Vector3 = Vector3.ZERO
	var test_normal: Vector3 = Vector3.FORWARD

	func _ready() -> void:
		set_physics_process(false)
		set_process(false)

	func _geometry_target(
		mode: CityTargeting.TargetMode,
		screen_source: CityTargeting.ScreenSource,
		_reach_m: float
	) -> CityTargeting.Result:
		var result := CityTargeting.Result.new(mode, screen_source)
		result.kind = CityTargeting.TargetKind.VOXEL
		result.point = test_geometry
		result.normal = test_normal.normalized()
		result.geometry_point = test_geometry
		result.geometry_distance = test_origin.distance_to(test_geometry)
		result.ray_origin = test_origin
		result.ray_direction = test_direction.normalized()
		return result


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	_city.name = "TestCity"
	add_child(_city)
	await get_tree().process_frame

	var look := (FACADE_POINT - CAM_FROM).normalized()
	_add_deck()
	_add_wall()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var walker := FacadeWalker.new()
	walker.name = "FacadeWalker"
	walker.test_origin = CAM_FROM
	walker.test_direction = look
	walker.test_geometry = FACADE_POINT
	walker.test_normal = Vector3(0.0, 0.0, -1.0)
	_city.add_child(walker)
	await get_tree().process_frame

	## Prove the harness reproduces the bug shape: muzzle cast must strike the deck first.
	if not _muzzle_hits_deck_before_wall(look):
		_fail("FAIL harness muzzle ray does not hit the deck before the wall")
		_quit()
		return

	## Placement / summon path: camera first-surface (here the facade stub) is unchanged.
	var voxels_only := walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR,
		MUZZLE,
		REACH_M
	)
	if (
		voxels_only.kind != CityTargeting.TargetKind.VOXEL
		or voxels_only.point.distance_to(FACADE_POINT) > 0.05
	):
		_fail("FAIL VOXELS_ONLY lost camera facade geometry %s" % str(voxels_only.point))
		_quit()
		return

	var combat := walker.resolve_target(
		CityTargeting.TargetMode.ACTORS_AND_VOXELS,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR,
		MUZZLE,
		REACH_M
	)
	_assert_hits_facade("resolve_target", combat, look)
	if _failed:
		_quit()
		return

	## Shared projectile math used by beam / charged blast / eye laser.
	for label: String in ["beam", "blast", "laser"]:
		var advance := label == "beam"
		var shot: CityTargeting.ProjectileSolution = walker.call(
			"_combat_projectile_solution", MUZZLE, combat, advance
		) as CityTargeting.ProjectileSolution
		var origin := shot.origin
		var aim := shot.target.point
		var dir := (aim - origin).normalized()
		if dir.dot(look) < 0.85:
			_fail("FAIL %s projectile dir %s leaves look %s" % [label, dir, look])
			_quit()
			return
		if aim.distance_to(FACADE_POINT) > 1.25 and absf(aim.z - WALL_FACE_Z) > 0.75:
			_fail(
				"FAIL %s aim %s is not the building (want near %s) — ground dump?"
				% [label, aim, FACADE_POINT]
			)
			_quit()
			return
		if aim.y < DECK_Y + 0.45:
			_fail("FAIL %s aim %s is in the ground" % [label, aim])
			_quit()
			return
		## Trajectory must reach the facade plane above the street, not stop a few metres out.
		var along_look := (aim - MUZZLE).dot(look)
		if along_look < 10.0:
			_fail(
				"FAIL %s aim only %.2fm along look — deck dump in front of the player"
				% [label, along_look]
			)
			_quit()
			return

	print(
		(
			"building aim: combat+beam/blast/laser hit facade %s (muzzle cleared deck reject)"
			% combat.point
		)
	)
	print("RESULT: OK")
	_quit()


func _assert_hits_facade(label: String, result: CityTargeting.Result, look: Vector3) -> void:
	if result.mode != CityTargeting.TargetMode.ACTORS_AND_VOXELS:
		_fail("FAIL %s lost ACTORS_AND_VOXELS" % label)
		return
	if result.kind != CityTargeting.TargetKind.VOXEL:
		_fail(
			(
				"FAIL %s kind=%s point=%s rejected=%s muzzle_geom=%s"
				+ " — expected VOXEL on the building, not a ground dump"
			)
			% [
				label,
				CityTargeting.kind_name(result.kind),
				result.point,
				result.muzzle_geometry_rejected,
				result.muzzle_geometry_point,
			]
		)
		return
	if result.point.y < DECK_Y + 0.45:
		_fail("FAIL %s endpoint %s is street/underground height" % [label, result.point])
		return
	if absf(result.point.z - WALL_FACE_Z) > 0.9:
		_fail(
			"FAIL %s endpoint %s is not on the facade (want z≈%.2f)"
			% [label, result.point, WALL_FACE_Z]
		)
		return
	if (result.point - MUZZLE).dot(look) < 10.0:
		_fail("FAIL %s endpoint is only a few metres ahead (deck dump)" % label)
		return
	if result.normal.dot(Vector3.UP) > 0.65:
		_fail("FAIL %s normal %s is ground-like" % [label, result.normal])
		return


func _muzzle_hits_deck_before_wall(look: Vector3) -> bool:
	var intent_far := CAM_FROM + look * REACH_M
	var shot_dir := (intent_far - MUZZLE).normalized()
	var cast_from := MUZZLE + shot_dir * 0.35
	var cast_to := MUZZLE + shot_dir * REACH_M
	var query := PhysicsRayQueryParameters3D.create(cast_from, cast_to)
	query.collision_mask = 1
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var point: Vector3 = hit["position"] as Vector3
	var normal: Vector3 = hit["normal"] as Vector3
	## Deck: near-horizontal, well short of the facade.
	return (
		normal.dot(Vector3.UP) > 0.65
		and point.y < MUZZLE.y - 0.2
		and point.z < WALL_FACE_Z - 2.0
	)


func _add_deck() -> void:
	var body := StaticBody3D.new()
	body.name = "StreetDeck"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.4, 40.0)
	shape.shape = box
	body.add_child(shape)
	_city.add_child(body)
	body.global_position = Vector3(0.0, DECK_Y - 0.2, 10.0)


func _add_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "BuildingFacade"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 10.0, 0.5)
	shape.shape = box
	body.add_child(shape)
	_city.add_child(body)
	body.global_position = Vector3(0.0, 5.0, WALL_Z)


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
