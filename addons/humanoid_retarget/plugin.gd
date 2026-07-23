@tool
extends EditorPlugin

var _post_import: EditorScenePostImportPlugin


func _enter_tree() -> void:
	_post_import = preload("res://addons/humanoid_retarget/post_import.gd").new()
	add_scene_post_import_plugin(_post_import)


func _exit_tree() -> void:
	if _post_import != null:
		remove_scene_post_import_plugin(_post_import)
		_post_import = null
