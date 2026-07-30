## Proves Ui3D hit→UV mapping and that AimPanel (Z summon) inherits it with a debug marker.
##
## Run: powershell -File tools\run_test.ps1 test_aim_panel
extends Node

const Ui3DScript := preload("res://scripts/city/ui_3d.gd")
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
	await _check_ui_3d_uv()
	await _check_aim_panel_marker()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_z_binding() -> void:
	var bind: Dictionary = PlayerControlsScript.default_binding("aim_panel")
	if str(bind.get("device", "")) != "key":
		_fail("FAIL aim_panel default device is not key: %s" % str(bind))
		return
	if int(bind.get("code", -1)) != KEY_Z:
		_fail("FAIL aim_panel default key is %d, expected KEY_Z" % int(bind.get("code", -1)))


func _check_ui_3d_uv() -> void:
	var panel: Node3D = Ui3DScript.new() as Node3D
	add_child(panel)
	panel.set("size_m", Vector2(5.0, 5.0))
	panel.set("show_debug_marker", false)
	panel.call("begin", ORIGIN, 0.0)
	await get_tree().physics_frame

	## Local (1,1) on a 5×5 face → UV ((1+2.5)/5, (1+2.5)/5) = (0.7, 0.7)
	var world_hit: Vector3 = panel.to_global(Vector3(1.0, 1.0, 0.0))
	var uv: Vector2 = panel.call("world_to_uv", world_hit) as Vector2
	if not is_finite(uv.x) or absf(uv.x - 0.7) > TOLERANCE or absf(uv.y - 0.7) > TOLERANCE:
		_fail("FAIL Ui3D world_to_uv got %s, expected ~ (0.7, 0.7)" % str(uv))
		panel.queue_free()
		return

	## Lambdas cannot assign outer locals reliably — capture into a Dictionary.
	var press_state := {"count": 0, "uv": Vector2.INF}
	var on_pressed := func(p_uv: Variant, _local: Variant, _world: Variant) -> void:
		press_state["count"] = int(press_state["count"]) + 1
		press_state["uv"] = p_uv as Vector2
	if not panel.has_signal("ui_pressed"):
		_fail("FAIL Ui3D is missing ui_pressed signal")
		panel.queue_free()
		return
	var err := panel.connect("ui_pressed", on_pressed)
	if err != OK:
		_fail("FAIL could not connect Ui3D.ui_pressed: %s" % error_string(err))
		panel.queue_free()
		return
	if not bool(panel.call("press_at_world", world_hit)):
		_fail("FAIL Ui3D press_at_world rejected an on-panel hit")
		panel.queue_free()
		return
	var last_uv: Vector2 = panel.get("last_press_uv") as Vector2
	if absf(last_uv.x - 0.7) > TOLERANCE or absf(last_uv.y - 0.7) > TOLERANCE:
		_fail("FAIL Ui3D last_press_uv %s, expected ~ (0.7, 0.7)" % str(last_uv))
		panel.queue_free()
		return
	if int(press_state["count"]) != 1:
		_fail("FAIL Ui3D.ui_pressed emitted %d times, expected 1" % int(press_state["count"]))
		panel.queue_free()
		return
	var pressed_uv: Vector2 = press_state["uv"] as Vector2
	if absf(pressed_uv.x - 0.7) > TOLERANCE or absf(pressed_uv.y - 0.7) > TOLERANCE:
		_fail("FAIL Ui3D ui_pressed signal UV %s, expected ~ (0.7, 0.7)" % str(pressed_uv))
		panel.queue_free()
		return
	if bool(panel.call("has_marker")):
		_fail("FAIL Ui3D showed a marker with show_debug_marker=false")
		panel.queue_free()
		return

	var miss: Vector3 = panel.to_global(Vector3(4.0, 4.0, 0.0))
	if bool(panel.call("press_at_world", miss)):
		_fail("FAIL Ui3D press_at_world accepted an off-panel hit")
		panel.queue_free()
		return

	panel.queue_free()


func _check_aim_panel_marker() -> void:
	var panel: Node3D = AimPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", ORIGIN, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not panel.is_in_group("ui_3d"):
		_fail("FAIL AimPanel is not in group ui_3d")
		panel.queue_free()
		return

	var local_target := Vector3(1.0, 1.0, 0.0)
	var world_hit: Vector3 = panel.to_global(local_target)
	if not bool(panel.call("mark_at_world", world_hit)):
		_fail("FAIL mark_at_world rejected an on-panel hit at %s" % str(world_hit))
		panel.queue_free()
		return
	if not bool(panel.call("has_marker")):
		_fail("FAIL AimPanel marker was not created after a valid hit")
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

	panel.call("clear_marker")
	var miss: Vector3 = panel.to_global(Vector3(4.0, 4.0, 0.0))
	if bool(panel.call("mark_at_world", miss)):
		_fail("FAIL mark_at_world accepted an off-panel hit at %s" % str(miss))
		panel.queue_free()
		return

	var from := ORIGIN + Vector3(1.0, 1.0, 3.0)
	var to := ORIGIN + Vector3(1.0, 1.0, -1.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_fail("FAIL physics ray did not hit the aim panel collider")
		panel.queue_free()
		return
	var resolved: Node = Ui3DScript.from_collider(hit.get("collider"))
	if resolved != panel:
		_fail("FAIL Ui3D.from_collider did not resolve to the AimPanel")
		panel.queue_free()
		return
	if not bool(panel.call("press_at_world", hit["position"] as Vector3)):
		_fail("FAIL press_at_world failed for physics hit")
		panel.queue_free()
		return
	var ray_marked: Vector3 = panel.call("marker_local_position") as Vector3
	if absf(ray_marked.x - 1.0) > 0.15 or absf(ray_marked.y - 1.0) > 0.15:
		_fail("FAIL physics-hit marker local %s is not near (1, 1)" % str(ray_marked))
		panel.queue_free()
		return

	panel.queue_free()
