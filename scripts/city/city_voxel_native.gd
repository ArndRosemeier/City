## Ensures the Rust city_voxel GDExtension is loaded (NativeOfflineVoxelVolume).
class_name CityVoxelNative
extends Object

const EXTENSION_PATH := "res://addons/city_voxel/city_voxel.gdextension"


static func ensure_loaded() -> bool:
	if ClassDB.class_exists("NativeOfflineVoxelVolume"):
		return true
	if not FileAccess.file_exists(EXTENSION_PATH):
		return false
	if GDExtensionManager.is_extension_loaded(EXTENSION_PATH):
		return ClassDB.class_exists("NativeOfflineVoxelVolume")
	var err := GDExtensionManager.load_extension(EXTENSION_PATH)
	return err == OK and ClassDB.class_exists("NativeOfflineVoxelVolume")


static func make_volume():
	if ensure_loaded():
		return ClassDB.instantiate("NativeOfflineVoxelVolume")
	return null
