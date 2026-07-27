## Lightweight vehicle brain (no Node). Simulated by VehicleDirector.
class_name VehicleAgent
extends RefCounted

enum Lod { CULLED, NEAR }

var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var lod: int = Lod.CULLED
var speed: float = 8.0
var catalog_id: String = ""
var passenger_count: int = 1
var visual: Node3D = null
## Avoid duplicate entries in the budgeted visual-creation queue.
var visual_queued: bool = false

var waypoints: PackedVector3Array = PackedVector3Array()
var path_i: int = 0
var moving: bool = false
var stuck_sec: float = 0.0
var cruise_speed: float = 8.0
## Hit by laser/melee — removed from traffic; mesh becomes a physics wreck.
var wrecked: bool = false
## True while flooring it away from the player after witnessing destruction.
var fleeing: bool = false
## Latest threat point (usually the player) to drive away from.
var flee_from: Vector3 = Vector3.ZERO
## Avoid duplicate entries in the budgeted flee-repath queue.
var flee_repath_queued: bool = false
## Graph node we must not reverse into on the next trip (anti-U-turn).
var avoid_next_node: int = -1
## Net-progress stuck detection (circling short loops still "moves").
var progress_anchor: Vector3 = Vector3.ZERO
var progress_timer: float = 0.0


func is_fleeing() -> bool:
	return (not wrecked) and fleeing


func drive_speed(flee_mul: float = 1.85) -> float:
	if is_fleeing():
		return cruise_speed * flee_mul
	return cruise_speed


func clear_path() -> void:
	waypoints = PackedVector3Array()
	path_i = 0
	moving = false


func set_path(world_path: PackedVector3Array) -> void:
	## Assign a route without teleporting — keep current world position.
	waypoints = world_path
	path_i = 0
	progress_anchor = position
	progress_timer = 0.0
	if waypoints.is_empty():
		moving = false
		return
	moving = true
	# Skip the first node if we're already on/near it (avoids a one-frame yank).
	if waypoints.size() >= 2:
		var d0 := Vector2(position.x - waypoints[0].x, position.z - waypoints[0].z).length_squared()
		if d0 < 1.0:
			path_i = 1


func remember_arrival_edge(path_nodes: PackedInt32Array) -> void:
	## After finishing a route, forbid reversing the last edge on the next trip.
	if path_nodes.size() >= 2:
		avoid_next_node = path_nodes[path_nodes.size() - 2]
	else:
		avoid_next_node = -1
