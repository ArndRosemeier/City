extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/inspect_humans.tscn")
	if packed == null:
		push_error("failed to load inspect scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await create_timer(0.25).timeout
	var male := scene.get_node_or_null("Male")
	var female := scene.get_node_or_null("Female")
	print("inspect smoke male=", male != null, " female=", female != null)
	quit(0 if male and female else 1)
