## Loads every .gdshader in the project and fails on GDScript-style `#` comments or
## ShaderMaterial compile errors — so bad shaders never wait for a live district spawn.
##
## Run: powershell -File tools\run_test.ps1 test_shaders_compile
extends Node

var _failed := false
var _checked := 0


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var paths := _collect_shaders("res://")
	paths.sort()
	if paths.is_empty():
		_fail("FAIL no .gdshader files found under res://")
		_finish()
		return
	for path in paths:
		_check_shader(path)
	print("checked %d shaders" % _checked)
	_finish()


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _collect_shaders(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_walk_dir(root, out)
	return out


func _walk_dir(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			## Skip editor cache and the vendored Godot tree under tools/godot.
			if name == ".godot" or name == "godot":
				name = dir.get_next()
				continue
			_walk_dir(child, out)
		elif name.ends_with(".gdshader"):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _check_shader(path: String) -> void:
	_checked += 1
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_fail("FAIL could not read %s" % path)
		return
	var line_no := 0
	for line in text.split("\n"):
		line_no += 1
		var trimmed := line.strip_edges()
		## `#include` / `#ifdef` are valid shader preprocessor; `##` and `# comment`
		## are GDScript and break the tokenizer (`Unknown character '#'`).
		if trimmed.begins_with("##") or _is_hash_comment(trimmed):
			_fail(
				"FAIL %s:%d uses GDScript-style '#' comment — shaders only allow // or /* */"
				% [path, line_no]
			)
			return
	var shader := load(path) as Shader
	if shader == null:
		_fail("FAIL load(%s) did not return a Shader" % path)
		return
	var mat := ShaderMaterial.new()
	## Assigning the shader triggers the renderer compile path used at runtime.
	mat.shader = shader
	if mat.shader == null:
		_fail("FAIL ShaderMaterial rejected %s" % path)
		return


func _is_hash_comment(trimmed: String) -> bool:
	if not trimmed.begins_with("#"):
		return false
	## Preprocessor directives: #include, #define, #ifdef, #ifndef, #endif, #else, #elif
	var rest := trimmed.substr(1)
	if rest.is_empty():
		return true
	if rest[0] == " " or rest[0] == "\t":
		return true
	var keyword := rest.strip_edges().get_slice(" ", 0).get_slice("\t", 0)
	match keyword:
		"include", "define", "ifdef", "ifndef", "endif", "else", "elif", "pragma":
			return false
		_:
			return true
