## Compiles every GDScript in the project and fails on the first one that does not.
##
## GDScript only reports errors like a wrong argument count when the script is actually
## compiled, and a broken script fails *silently* at runtime: the district bake just
## returns "bake failed" and the city never spawns. Run this after touching any function
## signature. Editor linting does not catch it.
##
## Runs as a scene, not with `-s`: script mode skips autoloads, so every script that
## touches the CityProfiler singleton would be reported as broken.
##
## Run: Godot --headless --path . res://tools/test_scripts_compile.tscn
extends Node

const ROOTS: Array[String] = ["res://scripts", "res://tools", "res://addons"]


func _ready() -> void:
	var paths: Array[String] = []
	for root in ROOTS:
		_collect(root, paths)
	paths.sort()
	var failed: Array[String] = []
	for p in paths:
		var res := load(p)
		if res == null:
			failed.append("%s (load returned null)" % p)
			continue
		var gs := res as GDScript
		if gs == null:
			failed.append("%s (not a GDScript)" % p)
			continue
		## Tool/abstract scripts are still expected to compile; can_instantiate() is the
		## only signal GDScript exposes for "this script has a compile error".
		if not gs.can_instantiate():
			failed.append(p)
	print("checked %d scripts" % paths.size())
	for f in failed:
		push_error("FAIL does not compile: %s" % f)
	print("RESULT: %s" % ("OK" if failed.is_empty() else "FAILED"))
	get_tree().quit(0 if failed.is_empty() else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
