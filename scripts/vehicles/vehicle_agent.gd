## Lightweight vehicle brain (no Node). Simulated by VehicleDirector.
class_name VehicleAgent
extends RefCounted

enum Lod { CULLED, MID, NEAR }

var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var lod: int = Lod.CULLED
var speed: float = 8.0
var catalog_id: String = ""
var passenger_count: int = 1
var visual: Node3D = null

var waypoints: PackedVector3Array = PackedVector3Array()
var path_i: int = 0
var moving: bool = false
var stuck_sec: float = 0.0
var cruise_speed: float = 8.0


func clear_path() -> void:
	waypoints = PackedVector3Array()
	path_i = 0
	moving = false


func set_path(world_path: PackedVector3Array) -> void:
	## Assign a route without teleporting — keep current world position.
	waypoints = world_path
	path_i = 0
	if waypoints.is_empty():
		moving = false
		return
	moving = true
	# Skip the first node if we're already on/near it (avoids a one-frame yank).
	if waypoints.size() >= 2:
		var d0 := Vector2(position.x - waypoints[0].x, position.z - waypoints[0].z).length_squared()
		if d0 < 1.0:
			path_i = 1
