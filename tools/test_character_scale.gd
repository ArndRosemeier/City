extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var walker := CityWalker.new()
	root.add_child(walker)
	await process_frame
	await process_frame

	var body: Node3D = walker.get_node_or_null("Body") as Node3D
	if body == null:
		push_error("FAIL no Body")
		quit(1)
		return

	var capsule: CollisionShape3D = null
	for c in walker.get_children():
		if c is CollisionShape3D:
			capsule = c as CollisionShape3D
			break
	if capsule == null:
		push_error("FAIL no CollisionShape3D")
		quit(1)
		return
	var shape0 := capsule.shape as CapsuleShape3D
	if shape0 == null:
		push_error("FAIL no CapsuleShape3D")
		quit(1)
		return
	var height0 := shape0.height

	walker.adjust_character_scale(1.0)
	await process_frame

	var scale_v := walker.get_character_scale()
	var expected := clampf(1.0 * walker.scale_factor_step, walker.scale_min, walker.scale_max)
	if absf(scale_v - expected) > 0.001:
		push_error("FAIL get_character_scale()=%s expected ~%s" % [scale_v, expected])
		quit(1)
		return

	var dig := walker.get_dig_radius()
	var dig_expected := 1.45 * scale_v
	if absf(dig - dig_expected) > 0.001:
		push_error("FAIL get_dig_radius()=%s expected ~%s" % [dig, dig_expected])
		quit(1)
		return

	if absf(body.scale.x - scale_v) > 0.001:
		push_error("FAIL body scale %s does not include character_scale %s" % [body.scale.x, scale_v])
		quit(1)
		return

	var shape1 := capsule.shape as CapsuleShape3D
	if shape1 == null or shape1.height <= height0 + 0.001:
		var h_now := -1.0 if shape1 == null else shape1.height
		push_error("FAIL capsule height did not grow: was %s now %s" % [height0, h_now])
		quit(1)
		return

	# Shrink many times → clamp at scale_min (0.2).
	for _i in range(80):
		walker.adjust_character_scale(-1.0)
	await process_frame
	var clamped := walker.get_character_scale()
	if absf(clamped - walker.scale_min) > 0.001:
		push_error("FAIL shrink clamp got %s expected scale_min %s" % [clamped, walker.scale_min])
		quit(1)
		return

	# Grow many times → clamp at scale_max (5).
	for _j in range(120):
		walker.adjust_character_scale(1.0)
	await process_frame
	var grown := walker.get_character_scale()
	if absf(grown - walker.scale_max) > 0.001:
		push_error("FAIL grow clamp got %s expected scale_max %s" % [grown, walker.scale_max])
		quit(1)
		return

	print("PASS character scale")
	OS.kill(OS.get_process_id())
