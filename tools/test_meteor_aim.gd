## Meteor aim must land on geometry / destructible voxels, never snap to agents.
## Combat aim still magnets agents. Build ground-aim stays physics-only.
##
## Run: powershell -File tools\run_test.ps1 test_meteor_aim
extends Node

const AGENT_SNAP := Vector3(100.0, 50.0, 100.0)
const DESTRUCTIBLE_POINT := Vector3(10.0, 2.0, -8.0)
const DESTRUCTIBLE_DISTANCE := 5.0


class FakeCityRoot:
	extends Node

	var resolve_calls: int = 0
	var probe_calls: int = 0

	func resolve_laser_aim(
		_cam_from: Vector3, _wall_aim: Vector3, _eye_from: Vector3
	) -> Vector3:
		resolve_calls += 1
		return AGENT_SNAP

	func apply_laser_agent_hit(
		_from: Vector3,
		_to: Vector3,
		_direction: Vector3,
		_source: int,
		_creatures: bool = true
	) -> bool:
		return false

	func probe_destructible_ray(_from_world: Vector3, _to_world: Vector3) -> Dictionary:
		probe_calls += 1
		return {
			"point": DESTRUCTIBLE_POINT,
			"normal": Vector3.UP,
			"distance": DESTRUCTIBLE_DISTANCE,
		}


var _failed := false
var _meteor_hit: Vector3 = Vector3.INF


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _on_meteor_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_meteor_hit = hit_point


func _ready() -> void:
	var root := FakeCityRoot.new()
	root.name = "FakeCityRoot"
	add_child(root)
	var walker := CityWalker.new()
	root.add_child(walker)
	await get_tree().process_frame
	await get_tree().process_frame

	_check_combat_still_magnets_agents(walker, root)
	_check_world_aim_keeps_destructibles_skips_agents(walker, root)
	_check_ground_aim_skips_both(walker, root)
	_check_meteor_request_skips_agents(walker, root)

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_combat_still_magnets_agents(walker: CityWalker, root: FakeCityRoot) -> void:
	root.resolve_calls = 0
	root.probe_calls = 0
	var aim: Dictionary = walker.call("_aim_ray_at_cursor") as Dictionary
	var point: Vector3 = aim["point"] as Vector3
	if root.probe_calls < 1:
		_fail("FAIL combat aim did not probe destructibles")
	if root.resolve_calls < 1:
		_fail("FAIL combat aim did not resolve agent magnet")
	if not point.is_equal_approx(AGENT_SNAP):
		_fail("FAIL combat aim point %s expected agent snap %s" % [point, AGENT_SNAP])


func _check_world_aim_keeps_destructibles_skips_agents(
	walker: CityWalker, root: FakeCityRoot
) -> void:
	root.resolve_calls = 0
	root.probe_calls = 0
	var aim: Dictionary = walker.aim_world_at_cursor()
	var point: Vector3 = aim["point"] as Vector3
	if root.probe_calls < 1:
		_fail("FAIL world aim did not probe destructibles")
	if root.resolve_calls != 0:
		_fail("FAIL world aim called resolve_laser_aim (%d)" % root.resolve_calls)
	if not point.is_equal_approx(DESTRUCTIBLE_POINT):
		_fail(
			"FAIL world aim point %s expected destructible %s" % [point, DESTRUCTIBLE_POINT]
		)
	if point.is_equal_approx(AGENT_SNAP):
		_fail("FAIL world aim snapped to agent")


func _check_ground_aim_skips_both(walker: CityWalker, root: FakeCityRoot) -> void:
	root.resolve_calls = 0
	root.probe_calls = 0
	var aim: Dictionary = walker.aim_ground_at_cursor()
	var point: Vector3 = aim["point"] as Vector3
	if root.probe_calls != 0:
		_fail("FAIL ground aim probed destructibles (%d)" % root.probe_calls)
	if root.resolve_calls != 0:
		_fail("FAIL ground aim called resolve_laser_aim (%d)" % root.resolve_calls)
	if point.is_equal_approx(AGENT_SNAP):
		_fail("FAIL ground aim snapped to agent")
	if point.is_equal_approx(DESTRUCTIBLE_POINT):
		_fail("FAIL ground aim used destructible march")


func _check_meteor_request_skips_agents(walker: CityWalker, root: FakeCityRoot) -> void:
	root.resolve_calls = 0
	root.probe_calls = 0
	_meteor_hit = Vector3.INF
	walker.meteor_requested.connect(_on_meteor_requested)
	walker._request_infection_meteor()
	if not _meteor_hit.is_finite():
		_fail("FAIL meteor_requested did not fire")
		return
	if root.resolve_calls != 0:
		_fail("FAIL meteor aim called resolve_laser_aim (%d)" % root.resolve_calls)
	if root.probe_calls < 1:
		_fail("FAIL meteor aim did not probe destructibles")
	if not _meteor_hit.is_equal_approx(DESTRUCTIBLE_POINT):
		_fail(
			"FAIL meteor aim point %s expected destructible %s"
			% [_meteor_hit, DESTRUCTIBLE_POINT]
		)
	if _meteor_hit.is_equal_approx(AGENT_SNAP):
		_fail("FAIL meteor aim snapped to agent")
