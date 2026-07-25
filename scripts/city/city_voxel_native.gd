## Loads the Rust city_voxel GDExtension. Required — no GDScript fallback.
class_name CityVoxelNative
extends Object

const EXTENSION_PATH := "res://addons/city_voxel/city_voxel.gdextension"
const VOLUME_CLASS := "NativeOfflineVoxelVolume"
const DEBRIS_CLASS := "NativeCascadeDebris"


static func require_loaded() -> void:
	if ClassDB.class_exists(VOLUME_CLASS) and ClassDB.class_exists(DEBRIS_CLASS):
		return
	if not FileAccess.file_exists(EXTENSION_PATH):
		push_error(
			"CityVoxelNative: missing %s — rebuild with tools/build_city_voxel.ps1"
			% EXTENSION_PATH
		)
		assert(false, "city_voxel.gdextension missing")
		return
	if not GDExtensionManager.is_extension_loaded(EXTENSION_PATH):
		var err := GDExtensionManager.load_extension(EXTENSION_PATH)
		if err != OK:
			push_error(
				"CityVoxelNative: load_extension failed (%s) for %s"
				% [error_string(err), EXTENSION_PATH]
			)
			assert(false, "city_voxel GDExtension failed to load")
			return
	if not ClassDB.class_exists(VOLUME_CLASS):
		push_error("CityVoxelNative: class %s not registered after load" % VOLUME_CLASS)
		assert(false, "NativeOfflineVoxelVolume missing")
		return
	if not ClassDB.class_exists(DEBRIS_CLASS):
		push_error("CityVoxelNative: class %s not registered after load" % DEBRIS_CLASS)
		assert(false, "NativeCascadeDebris missing")
		return


## Back-compat name used by older call sites — now hard-requires.
static func ensure_loaded() -> bool:
	require_loaded()
	return true


static func make_volume() -> Object:
	require_loaded()
	var vol: Object = ClassDB.instantiate(VOLUME_CLASS)
	if vol == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) returned null" % VOLUME_CLASS)
		assert(false, "NativeOfflineVoxelVolume instantiate failed")
	return vol


static func make_cascade_debris() -> Node:
	require_loaded()
	var node: Object = ClassDB.instantiate(DEBRIS_CLASS)
	if node == null or not (node is Node):
		push_error("CityVoxelNative: ClassDB.instantiate(%s) failed" % DEBRIS_CLASS)
		assert(false, "NativeCascadeDebris instantiate failed")
	return node as Node
