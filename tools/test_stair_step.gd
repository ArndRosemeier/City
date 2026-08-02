## One voxel up and one voxel down are the same walk — no free-fall on the way down.
##
## VoxelBoxMover climbs a curb for you, but walking off the same curb used to be a few frames
## of gravity. That briefly armed Jump_Loop every stair tread. VoxelBodyMotion now snaps down
## by the same max_step_height it climbs, so a flight of one-voxel risers is walk on both sides.
##
## Run: powershell -File tools\run_test.ps1 test_stair_step
extends Node

const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

const VOXEL_SIZE := 0.5
const ORIGIN := Vector3i(48, 8, 48)
const STEP_M := 0.55
const EPS := 0.02

var _failed := false
var _terrain: VoxelTerrain
var _tool: VoxelTool
var _brush: CityBrush


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	if not await _make_terrain():
		_quit()
		return
	_brush = CityBrushScript.new(_tool, Vector3i.ZERO)
	_build_stair()
	for _i in range(6):
		await get_tree().process_frame
	await _test_step_up()
	if _failed:
		_quit()
		return
	await _test_step_down()
	if _failed:
		_quit()
		return
	await _test_a_cliff_still_falls()
	_quit()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Two treads: low at z=ORIGIN.z..+3, high at z=+4..+7. Same riser the castle uses.
func _build_stair() -> void:
	_brush.begin_edit()
	for x in range(ORIGIN.x - 2, ORIGIN.x + 3):
		for z in range(ORIGIN.z, ORIGIN.z + 4):
			_brush.set_vox(Vector3i(x, ORIGIN.y, z), VoxelMaterial.STONE)
		for z in range(ORIGIN.z + 4, ORIGIN.z + 8):
			_brush.set_vox(Vector3i(x, ORIGIN.y, z), VoxelMaterial.STONE)
			_brush.set_vox(Vector3i(x, ORIGIN.y + 1, z), VoxelMaterial.STONE)
	_brush.end_edit()


func _make_body(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "StepBody"
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	col.shape = capsule
	col.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(col)
	add_child(body)
	body.global_position = at
	return body


func _motion() -> VoxelBodyMotion:
	var m := VoxelBodyMotion.new()
	m.setup(_terrain, STEP_M)
	return m


func _stand_y(floor_vox_y: int) -> float:
	## Capsule sole sits on the top of the solid voxel.
	return (float(floor_vox_y) + 1.0) * VOXEL_SIZE


func _xz(zx: float, zz: float) -> Vector3:
	return Vector3(
		(float(ORIGIN.x) + 0.5) * VOXEL_SIZE,
		0.0,
		(float(ORIGIN.z) + zz) * VOXEL_SIZE
	)


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------

func _test_step_up() -> void:
	var low := _stand_y(ORIGIN.y)
	var high := _stand_y(ORIGIN.y + 1)
	var body := _make_body(Vector3(_xz(0.0, 2.0).x, low, _xz(0.0, 2.0).z))
	var col := body.get_child(0) as CollisionShape3D
	var motion := _motion()
	## Walk +Z toward the higher tread. Same distance a walker covers in a tick or two.
	var saw_step := false
	var airborne := false
	for _i in range(40):
		motion.move(body, col, Vector3(0.0, -0.5, 2.4), 1.0 / 60.0)
		if not motion.is_on_floor():
			airborne = true
		if motion.has_stepped_up():
			saw_step = true
		if body.global_position.y >= high - EPS:
			break
	if airborne:
		_fail("FAIL stepping up left the body airborne")
	elif not saw_step and body.global_position.y < high - EPS:
		_fail(
			"FAIL never climbed the tread (y=%.3f, want >= %.3f)"
			% [body.global_position.y, high]
		)
	elif body.global_position.y < high - EPS:
		_fail("FAIL step-up ended at y=%.3f, want the high tread %.3f" % [body.global_position.y, high])
	else:
		print("step up: y %.3f -> %.3f (high tread)" % [low, body.global_position.y])
	body.queue_free()
	await get_tree().process_frame


func _test_step_down() -> void:
	var low := _stand_y(ORIGIN.y)
	var high := _stand_y(ORIGIN.y + 1)
	var body := _make_body(Vector3(_xz(0.0, 5.5).x, high, _xz(0.0, 5.5).z))
	var col := body.get_child(0) as CollisionShape3D
	var motion := _motion()
	var saw_step := false
	var airborne := false
	for _i in range(40):
		## Horizontal only — no gravity. If we need gravity to leave the high tread, the snap
		## failed and this is the jump-anim bug again.
		motion.move(body, col, Vector3(0.0, 0.0, -2.4), 1.0 / 60.0)
		if not motion.is_on_floor():
			airborne = true
		if motion.has_stepped_down():
			saw_step = true
		if body.global_position.y <= low + EPS:
			break
	if airborne:
		_fail("FAIL stepping down left the body airborne — jump anims would fire")
	elif not saw_step:
		_fail(
			"FAIL never snapped down (y=%.3f, want the low tread %.3f)"
			% [body.global_position.y, low]
		)
	elif absf(body.global_position.y - low) > EPS:
		_fail("FAIL step-down ended at y=%.3f, want the low tread %.3f" % [body.global_position.y, low])
	else:
		print("step down: y %.3f -> %.3f (low tread, never airborne)" % [high, body.global_position.y])
	body.queue_free()
	await get_tree().process_frame


func _test_a_cliff_still_falls() -> void:
	## High platform with nothing within a step below — the snap must not invent a floor.
	_brush.begin_edit()
	for x in range(ORIGIN.x + 10, ORIGIN.x + 14):
		for z in range(ORIGIN.z, ORIGIN.z + 4):
			_brush.set_vox(Vector3i(x, ORIGIN.y + 4, z), VoxelMaterial.STONE)
	_brush.end_edit()
	for _i in range(4):
		await get_tree().process_frame

	var cliff_y := _stand_y(ORIGIN.y + 4)
	## Start on the last tread of the platform so a short walk clears the lip.
	var lip_z := (float(ORIGIN.z) + 3.6) * VOXEL_SIZE
	var at := Vector3((float(ORIGIN.x) + 12.5) * VOXEL_SIZE, cliff_y, lip_z)
	var body := _make_body(at)
	var col := body.get_child(0) as CollisionShape3D
	var motion := _motion()
	## Walk off the +Z edge into empty air. No gravity — if we snap, we invented a floor.
	for _i in range(20):
		motion.move(body, col, Vector3(0.0, 0.0, 2.4), 1.0 / 60.0)
	var past_lip := body.global_position.z > (float(ORIGIN.z) + 4.2) * VOXEL_SIZE
	if not past_lip:
		_fail("FAIL never cleared the cliff lip (z=%.3f)" % body.global_position.z)
	elif motion.has_stepped_down():
		_fail("FAIL the cliff snap-down invented a floor at y=%.3f" % body.global_position.y)
	elif motion.is_on_floor():
		_fail("FAIL still on_floor after walking off a real cliff")
	elif absf(body.global_position.y - cliff_y) > EPS:
		_fail(
			"FAIL cliff walk changed Y to %.3f — the body should keep floating at %.3f without gravity"
			% [body.global_position.y, cliff_y]
		)
	else:
		print("cliff: cleared the lip at y=%.3f with no false snap" % body.global_position.y)
	body.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

func _make_terrain() -> bool:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	_terrain.bounds = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 220, 4000))
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 512
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	add_child(anchor)
	anchor.global_position = Vector3(ORIGIN) * VOXEL_SIZE

	var box := AABB(Vector3(ORIGIN) - Vector3(16, 8, 16), Vector3(64, 32, 64))
	for _i in range(600):
		await get_tree().process_frame
		if _tool.is_area_editable(box):
			return true
	_fail("FAIL area never became editable")
	return false


func _quit() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
