## Smoke: Kenney Pirate Kit chest loads with lid + open animation.
## Run: powershell -File tools\run_test.ps1 test_chest_asset
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var packed := load("res://assets/city/chests/chest.glb") as PackedScene
	if packed == null:
		_fail("FAIL could not load chest.glb as PackedScene")
		_finish()
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		_fail("FAIL chest root is not a Node3D")
		_finish()
		return
	add_child(root)

	var lid := root.find_child("lid", true, false) as Node3D
	if lid == null:
		_fail("FAIL no lid node under the chest")
	else:
		print("OK lid at local %s" % lid.position)

	var ap := _find_anim_player(root)
	if ap == null:
		_fail("FAIL no AnimationPlayer on the chest")
		_finish()
		return
	var names := ap.get_animation_list()
	print("OK animations: %s" % ", ".join(PackedStringArray(names)))
	var open_name := _pick_open_animation(names)
	if open_name.is_empty():
		_fail("FAIL no open animation among %s" % str(names))
		_finish()
		return
	ap.play(open_name)
	await get_tree().create_timer(0.35).timeout
	if not ap.is_playing() and ap.current_animation.is_empty():
		## Finished in under 0.35 s is fine — just prove play() accepted it.
		print("OK played '%s' (already finished)" % open_name)
	else:
		print("OK playing '%s'" % open_name)
	_finish()


func _pick_open_animation(names: PackedStringArray) -> String:
	for n: String in names:
		var base := n.get_file() if n.contains("/") else n
		if base == "open":
			return n
	for n: String in names:
		if n.contains("open") and not n.contains("close"):
			return n
	for n: String in names:
		if n.contains("open"):
			return n
	return ""


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
