## Headless run of the main crowd scene for a few frames.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	var humans := main.get_node_or_null("Humans")
	var child_count := 0 if humans == null else humans.get_child_count()
	print("Main scene OK; pedestrian count=%d" % child_count)
	quit(0 if child_count > 0 else 1)
