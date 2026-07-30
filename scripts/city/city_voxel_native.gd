## Loads the Rust city_voxel GDExtension. Required — no GDScript fallback.
class_name CityVoxelNative
extends Object

const EXTENSION_PATH := "res://addons/city_voxel/city_voxel.gdextension"
const VOLUME_CLASS := "NativeOfflineVoxelVolume"
const DEBRIS_CLASS := "NativeCascadeDebris"
## One district's baked span field, produced on a bake worker.
const NAV_BAKE_CLASS := "NativeNavBake"
## Main-thread navigation registry every agent queries.
const NAV_WORLD_CLASS := "NativeNavWorld"
## Deep Mandelbrot (HP reference + perturbation bake).
const MANDELBROT_CLASS := "NativeMandelbrot"

const REQUIRED_CLASSES: Array[String] = [
	VOLUME_CLASS, DEBRIS_CLASS, NAV_BAKE_CLASS, NAV_WORLD_CLASS, MANDELBROT_CLASS
]


static func require_loaded() -> void:
	if _all_registered():
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
	for cls: String in REQUIRED_CLASSES:
		if not ClassDB.class_exists(cls):
			push_error("CityVoxelNative: class %s not registered after load" % cls)
			assert(false, "city_voxel class missing")
			return


static func _all_registered() -> bool:
	for cls: String in REQUIRED_CLASSES:
		if not ClassDB.class_exists(cls):
			return false
	return true


## Back-compat name used by older call sites — now hard-requires.
static func ensure_loaded() -> bool:
	require_loaded()
	return true


static func make_volume() -> NativeOfflineVoxelVolume:
	require_loaded()
	var vol := ClassDB.instantiate(VOLUME_CLASS) as NativeOfflineVoxelVolume
	if vol == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) returned null" % VOLUME_CLASS)
		assert(false, "NativeOfflineVoxelVolume instantiate failed")
	return vol


static func make_cascade_debris() -> NativeCascadeDebris:
	require_loaded()
	var node := ClassDB.instantiate(DEBRIS_CLASS) as NativeCascadeDebris
	if node == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) failed" % DEBRIS_CLASS)
		assert(false, "NativeCascadeDebris instantiate failed")
	return node


## One district's span field. Created on a bake worker; hand it to a NativeNavWorld after.
static func make_nav_bake() -> NativeNavBake:
	require_loaded()
	var bake := ClassDB.instantiate(NAV_BAKE_CLASS) as NativeNavBake
	if bake == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) returned null" % NAV_BAKE_CLASS)
		assert(false, "NativeNavBake instantiate failed")
	return bake


static func make_nav_world() -> NativeNavWorld:
	require_loaded()
	var world := ClassDB.instantiate(NAV_WORLD_CLASS) as NativeNavWorld
	if world == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) returned null" % NAV_WORLD_CLASS)
		assert(false, "NativeNavWorld instantiate failed")
	return world


static func make_mandelbrot() -> Object:
	require_loaded()
	var eng: Object = ClassDB.instantiate(MANDELBROT_CLASS)
	if eng == null:
		push_error("CityVoxelNative: ClassDB.instantiate(%s) returned null" % MANDELBROT_CLASS)
		assert(false, "NativeMandelbrot instantiate failed")
	return eng
