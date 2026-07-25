## Headless package check: prove a staged/portable City folder can load scripts + main scene.
## Exit codes: 0 = OK, non-zero = failed (make_installer must abort).
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0

	if not FileAccess.file_exists("res://.godot/global_script_class_cache.cfg"):
		push_error("PORTABLE_VALIDATE: missing .godot/global_script_class_cache.cfg")
		failed += 1
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.godot/imported")):
		push_error("PORTABLE_VALIDATE: missing .godot/imported (asset import did not run)")
		failed += 1

	## Load every gameplay / tool script so new class_name + preload() breakage surfaces here.
	failed += _load_tree("res://scripts")
	failed += _load_tree("res://addons/city_voxel")

	var scene_path := "res://scenes/city_poc.tscn"
	if not ResourceLoader.exists(scene_path):
		push_error("PORTABLE_VALIDATE: missing %s" % scene_path)
		failed += 1
	else:
		var packed: Resource = load(scene_path)
		if packed == null or not (packed is PackedScene):
			push_error("PORTABLE_VALIDATE: failed to load %s" % scene_path)
			failed += 1

	if failed > 0:
		push_error("PORTABLE_VALIDATE: FAILED (%d error group(s))" % failed)
		quit(1)
		return

	print("PORTABLE_VALIDATE: OK")
	quit(0)


func _load_tree(res_dir: String) -> int:
	var fails := 0
	var abs_dir := ProjectSettings.globalize_path(res_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return 0
	fails += _load_dir_recursive(res_dir)
	return fails


func _load_dir_recursive(res_dir: String) -> int:
	var fails := 0
	var da := DirAccess.open(res_dir)
	if da == null:
		push_error("PORTABLE_VALIDATE: cannot open %s" % res_dir)
		return 1
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name == "." or name == "..":
			name = da.get_next()
			continue
		var path := res_dir.path_join(name)
		if da.current_is_dir():
			fails += _load_dir_recursive(path)
		elif name.ends_with(".gd"):
			## Skip this validator itself if present under tools when scanned later.
			var script: Resource = load(path)
			if script == null:
				push_error("PORTABLE_VALIDATE: script failed to load: %s" % path)
				fails += 1
		name = da.get_next()
	da.list_dir_end()
	return fails
