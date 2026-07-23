extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var walker := CityWalker.new()
	root.add_child(walker)
	await process_frame
	await process_frame

	if walker.get_node_or_null("CharacterEditor") == null:
		push_error("FAIL missing CharacterEditor")
		quit(1)
		return

	var props := BodyProportions.identity()
	props.height = 0.8
	props.leg_length = 0.6
	props.shoulder_width = -0.5
	walker.apply_proportions(props)
	await process_frame

	var body: Node3D = walker.get_node_or_null("Body") as Node3D
	if body == null:
		push_error("FAIL no Body")
		quit(1)
		return
	var expected := props.body_uniform_scale()
	if absf(body.scale.x - expected) > 0.001:
		push_error("FAIL body scale %s expected %s" % [body.scale.x, expected])
		quit(1)
		return

	walker.toggle_character_editor()
	if not walker.is_character_editor_open():
		push_error("FAIL editor did not open")
		quit(1)
		return
	walker.toggle_character_editor()
	if walker.is_character_editor_open():
		push_error("FAIL editor did not close")
		quit(1)
		return

	print("PASS character editor proportions")
	OS.kill(OS.get_process_id())
