## Typed contract for every screen-to-world targeting request in the city.
class_name CityTargeting
extends RefCounted


enum TargetMode {
	VOXELS_ONLY,
	ACTORS_AND_VOXELS,
}


enum ScreenSource {
	LOOK_CROSSHAIR,
	FREE_CURSOR,
}


enum TargetKind {
	MISS,
	VOXEL,
	ACTOR,
}


class Result:
	extends RefCounted

	var mode: TargetMode
	var screen_source: ScreenSource
	var kind: TargetKind = TargetKind.MISS
	var point: Vector3 = Vector3.INF
	var normal: Vector3 = Vector3.UP
	var voxel: Vector3i = Vector3i.ZERO
	var has_voxel: bool = false
	var ray_origin: Vector3 = Vector3.INF
	var ray_direction: Vector3 = Vector3.ZERO
	var shot_origin: Vector3 = Vector3.INF
	var geometry_point: Vector3 = Vector3.INF
	var geometry_distance: float = INF
	## Combat-only muzzle ray. Camera geometry above remains the untouched screen-intent receipt.
	var muzzle_geometry_point: Vector3 = Vector3.INF
	var muzzle_geometry_distance: float = INF
	var muzzle_geometry_projection: float = -INF
	var muzzle_geometry_rejected: bool = false
	var actor_point: Vector3 = Vector3.INF
	var actor_distance: float = INF
	var actor: Node3D = null

	func _init(p_mode: TargetMode, p_screen_source: ScreenSource) -> void:
		mode = p_mode
		screen_source = p_screen_source

	func did_hit() -> bool:
		return kind != TargetKind.MISS

	func target_distance(from: Vector3) -> float:
		if not did_hit():
			return INF
		return from.distance_to(point)


class ProjectileSolution:
	extends RefCounted

	var origin: Vector3
	var target: Result

	func _init(p_origin: Vector3, p_target: Result) -> void:
		origin = p_origin
		target = p_target


static func mode_name(mode: TargetMode) -> String:
	match mode:
		TargetMode.VOXELS_ONLY:
			return "VOXELS_ONLY"
		TargetMode.ACTORS_AND_VOXELS:
			return "ACTORS_AND_VOXELS"
	push_error("CityTargeting.mode_name: unknown mode %d" % int(mode))
	assert(false, "CityTargeting: unknown target mode")
	return "INVALID"


static func screen_source_name(source: ScreenSource) -> String:
	match source:
		ScreenSource.LOOK_CROSSHAIR:
			return "LOOK_CROSSHAIR"
		ScreenSource.FREE_CURSOR:
			return "FREE_CURSOR"
	push_error("CityTargeting.screen_source_name: unknown source %d" % int(source))
	assert(false, "CityTargeting: unknown screen source")
	return "INVALID"


static func kind_name(kind: TargetKind) -> String:
	match kind:
		TargetKind.MISS:
			return "MISS"
		TargetKind.VOXEL:
			return "VOXEL"
		TargetKind.ACTOR:
			return "ACTOR"
	push_error("CityTargeting.kind_name: unknown kind %d" % int(kind))
	assert(false, "CityTargeting: unknown target kind")
	return "INVALID"
