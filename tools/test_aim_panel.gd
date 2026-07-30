## Proves the Z-summonable aim panel maps world hits onto its 5×5 face and rejects misses.
##
## Run: powershell -File tools\run_test.ps1 test_aim_panel
extends Node

const AimPanelScript := preload("res://scripts/city/aim_panel.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")

const ORIGIN := Vector3(10.0, 5.0, 20.0)
const TOLERANCE := 0.05

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_z_binding()
	await _check_mark_mapping()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_z_binding() -> void:
	var bind: Dictionary = PlayerControlsScript.default_binding("aim_panel")
	if str(bind.get("device", "")) != "key":
		_fail("FAIL aim_panel default device is not key: %s" % str(bind))
		return
	if int(bind.get("code", -1)) != KEY_Z:
		_fail("FAIL aim_panel default key is %d, expected KEY_Z" % int(bind.get("code", -1)))


func _check_mark_mapping() -> void:
	var panel: Node3D = AimPanelScript.new() as Node3D
	add_child(panel)
	## face_yaw = 0 → local −Z is world −Z, so the face is visible from +Z.
	panel.call("begin", ORIGIN, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var local_target := Vector3(1.0, 1.0, 0.0)
	var world_hit: Vector3 = panel.to_global(local_target)
	if not bool(panel.call("mark_at_world", world_hit)):
		_fail("FAIL mark_at_world rejected an on-panel hit at %s" % str(world_hit))
		panel.queue_free()
		return
	if not bool(panel.call("has_marker")):
		_fail("FAIL marker was not created after a valid hit")
		panel.queue_free()
		return
	var marked: Vector3 = panel.call("marker_local_position") as Vector3
	if absf(marked.x - local_target.x) > TOLERANCE or absf(marked.y - local_target.y) > TOLERANCE:
		_fail(
			"FAIL marker local %s does not match target %s"
			% [str(marked), str(local_target)]
		)
		panel.queue_free()
		return

	## Miss far outside the 5×5 face must not create a marker.
	panel.call("clear_marker")
	var miss: Vector3 = panel.to_global(Vector3(4.0, 4.0, 0.0))
	if bool(panel.call("mark_at_world", miss)):
		_fail("FAIL mark_at_world accepted an off-panel hit at %s" % str(miss))
		panel.queue_free()
		return
	if bool(panel.call("has_marker")):
		_fail("FAIL marker exists after a rejected miss")
		panel.queue_free()
		return

	## Physics ray from in front of the panel must hit the StaticBody and map the same cell.
	var from := ORIGIN + Vector3(1.0, 1.0, 3.0)
	var to := ORIGIN + Vector3(1.0, 1.0, -1.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_fail("FAIL physics ray did not hit the aim panel collider")
		panel.queue_free()
		return
	var found: Node = hit.get("collider") as Node
	var resolved: Node = null
	while found != null:
		if found.has_method("mark_at_world") and (
			found.is_in_group("aim_panel") or bool(found.has_meta("aim_panel"))
		):
			resolved = found
			break
		found = found.get_parent()
	if resolved != panel:
		_fail("FAIL ray collider did not resolve to the AimPanel")
		panel.queue_free()
		return
	if not bool(panel.call("mark_at_world", hit["position"] as Vector3)):
		_fail("FAIL mark_at_world failed for physics hit %s" % str(hit.get("position")))
		panel.queue_free()
		return
	var ray_marked: Vector3 = panel.call("marker_local_position") as Vector3
	if absf(ray_marked.x - 1.0) > 0.15 or absf(ray_marked.y - 1.0) > 0.15:
		_fail(
			"FAIL physics-hit marker local %s is not near (1, 1)"
			% str(ray_marked)
		)
		panel.queue_free()
		return

	panel.queue_free()
