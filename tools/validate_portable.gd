## Headless package check: prove a staged/portable Eccentri City folder can boot.
## Exit codes: 0 = OK, non-zero = failed (pack_release / make_installer must abort).
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

	failed += _require_files([
		"res://addons/city_voxel/bin/city_voxel.dll",
		"res://addons/city_voxel/city_voxel.gdextension",
		"res://scenes/city_poc.tscn",
		"res://assets/city/shaders/voxel_gem.gdshader",
		"res://assets/city/shaders/voxel_surface.gdshader",
		"res://assets/city/shaders/voxel_water.gdshader",
		"res://scripts/city/city_root.gd",
		"res://scripts/city/gem_light_director.gd",
		"res://scripts/city/city_audio.gd",
		"res://tools/ensure_city_deps.ps1",
	])

	## Native extension must resolve — missing DLL is a hard player failure.
	if ClassDB.class_exists("NativeOfflineVoxelVolume"):
		pass
	else:
		## Extension may register under a different path; still require the DLL file above.
		## Soft-check: gdextension resource loads.
		var ext := load("res://addons/city_voxel/city_voxel.gdextension")
		if ext == null:
			push_error("PORTABLE_VALIDATE: city_voxel.gdextension failed to load")
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


func _require_files(paths: Array) -> int:
	var fails := 0
	for path_v in paths:
		var path := String(path_v)
		if not FileAccess.file_exists(path):
			push_error("PORTABLE_VALIDATE: required file missing: %s" % path)
			fails += 1
	return fails


func _load_tree(res_dir: String) -> int:
	var abs_dir := ProjectSettings.globalize_path(res_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return 0
	return _load_dir_recursive(res_dir)


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
			var script: Resource = load(path)
			if script == null:
				push_error("PORTABLE_VALIDATE: script failed to load: %s" % path)
				fails += 1
		name = da.get_next()
	da.list_dir_end()
	return fails
