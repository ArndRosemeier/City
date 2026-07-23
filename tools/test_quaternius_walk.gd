extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var walker := CityWalker.new()
	get_root().add_child(walker)
	# Give _ready + deferred setup a frame.
	await process_frame
	await process_frame
	var ap: AnimationPlayer = walker.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("anim_player=", ap != null)
	if ap == null:
		push_error("FAIL no AnimationPlayer")
		quit(1)
		return
	print("anims=", ap.get_animation_list())
	print("current=", ap.current_animation)
	if not ap.has_animation("quat/Idle"):
		push_error("FAIL missing quat/Idle")
		quit(1)
		return
	if not ap.has_animation("quat/Walk"):
		push_error("FAIL missing quat/Walk")
		quit(1)
		return
	# Force Walk without CityWalker physics overriding to Idle (stationary).
	walker.set_physics_process(false)
	ap.play("quat/Walk")
	for _i in range(30):
		await process_frame
	if ap.current_animation != "quat/Walk":
		push_error("FAIL expected quat/Walk, got %s" % ap.current_animation)
		quit(1)
		return
	print("playing=", ap.current_animation, " pos=", ap.current_animation_position)
	print("PASS quaternius idle/walk wired")
	OS.kill(OS.get_process_id())
