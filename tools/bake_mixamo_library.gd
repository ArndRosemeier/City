## Bake Mixamo FBX/GLB under assets/humans/animations/mixamo/raw/ into a shared
## AnimationLibrary with _m name postfix (Kick → Kick_m).
##
## Usage (after Godot has imported the raw files once):
##   Godot_v4.6-voxel_win64.exe --headless --path . -s res://tools/bake_mixamo_library.gd
extends SceneTree

const RAW_DIR := "res://assets/humans/animations/mixamo/raw"
const OUT_PATH := "res://assets/humans/animations/mixamo/mixamo_actions.tres"
const POSTFIX := "_m"


func _initialize() -> void:
	var abs_raw := ProjectSettings.globalize_path(RAW_DIR)
	if not DirAccess.dir_exists_absolute(abs_raw):
		DirAccess.make_dir_recursive_absolute(abs_raw)
	var dir := DirAccess.open(RAW_DIR)
	if dir == null:
		push_error("bake_mixamo_library: cannot open %s" % RAW_DIR)
		quit(1)
		return

	var library := AnimationLibrary.new()
	var added := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower := fname.to_lower()
			if lower.ends_with(".fbx") or lower.ends_with(".glb") or lower.ends_with(".gltf"):
				var path := "%s/%s" % [RAW_DIR, fname]
				added += _ingest_file(path, library)
		fname = dir.get_next()
	dir.list_dir_end()

	if added == 0:
		push_error(
			"bake_mixamo_library: no clips baked. Drop Mixamo FBX (With Skin, In Place) into %s then reimport in the editor and re-run."
			% RAW_DIR
		)
		quit(1)
		return

	var err := ResourceSaver.save(library, OUT_PATH)
	if err != OK:
		push_error("bake_mixamo_library: save failed %s err=%s" % [OUT_PATH, err])
		quit(1)
		return
	print("bake_mixamo_library: saved %d clips → %s" % [added, OUT_PATH])
	for n in library.get_animation_list():
		print("  - ", n)
	quit(0)


func _ingest_file(path: String, library: AnimationLibrary) -> int:
	if not ResourceLoader.exists(path):
		push_warning("bake_mixamo_library: missing %s (import in editor first)" % path)
		return 0
	var res: Resource = load(path)
	if res == null:
		push_warning("bake_mixamo_library: load failed %s" % path)
		return 0

	var base := path.get_file().get_basename()
	base = _sanitize_name(base)
	var clip_name := base if base.ends_with(POSTFIX) else base + POSTFIX

	var src_player: AnimationPlayer = null
	var tmp_root: Node = null
	if res is PackedScene:
		tmp_root = (res as PackedScene).instantiate()
		src_player = _find_animation_player(tmp_root)
	elif res is AnimationLibrary:
		## Rare: already an AnimationLibrary import.
		var src_lib := res as AnimationLibrary
		var count := 0
		for anim_name in src_lib.get_animation_list():
			var anim: Animation = src_lib.get_animation(anim_name)
			if anim == null:
				continue
			var out_name := clip_name if src_lib.get_animation_list().size() == 1 else _sanitize_name(String(anim_name)) + POSTFIX
			library.add_animation(out_name, _prepare(anim.duplicate(true) as Animation))
			count += 1
		return count
	else:
		push_warning("bake_mixamo_library: unsupported type %s for %s" % [res.get_class(), path])
		return 0

	if src_player == null:
		push_warning("bake_mixamo_library: no AnimationPlayer in %s" % path)
		if tmp_root != null:
			tmp_root.free()
		return 0

	var names: PackedStringArray = src_player.get_animation_list()
	var best_name := ""
	var best_len := -1.0
	for anim_name in names:
		var key := String(anim_name)
		var low := key.to_lower()
		if low.contains("tpose") or low.contains("t-pose") or low.contains("t_pose"):
			continue
		var src: Animation = src_player.get_animation(anim_name)
		if src == null:
			continue
		## Prefer Mixamo's main clip name when present.
		if low == "mixamo_com" or low.contains("mixamo"):
			best_name = key
			best_len = src.length
			break
		if src.length > best_len:
			best_len = src.length
			best_name = key

	var count := 0
	if best_name != "":
		var src: Animation = src_player.get_animation(best_name)
		library.add_animation(clip_name, _prepare(src.duplicate(true) as Animation))
		count = 1
		print("bake_mixamo_library: %s [%s] → %s (%.2fs)" % [path.get_file(), best_name, clip_name, best_len])

	if tmp_root != null:
		tmp_root.free()
	return count


func _prepare(anim: Animation) -> Animation:
	## Keep one-shots non-looping; strip hips/root translation for in-place playback.
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ != Animation.TYPE_POSITION_3D:
			continue
		var leaf := path.get_file()
		if leaf.ends_with(":Root") or leaf.ends_with(":Hips") or leaf == "Root" or leaf == "Hips":
			anim.remove_track(i)
	return anim


func _sanitize_name(name: String) -> String:
	var s := name.strip_edges()
	s = s.replace(" ", "_").replace("-", "_")
	while s.contains("__"):
		s = s.replace("__", "_")
	return s


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
