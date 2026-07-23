## Lightweight city pedestrian brain (no Node). Simulated by CrowdDirector.
class_name PedAgent
extends RefCounted

enum State { STAY, WALK }
enum Lod { CULLED, MID, NEAR }

var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var state: int = State.STAY
var lod: int = Lod.CULLED

## 0 = prefers staying, 1 = prefers walking.
var walk_tendency: float = 0.5
var walk_speed: float = 1.35
var female: bool = false
var body_scale: float = 1.0
var outfit: PedOutfit
var next_decision_at: float = 0.0
## Bound near-LOD visual while inside near_distance; null when mid/culled.
var visual: Node3D = null

## Roadmap path in world space; walk toward waypoints[path_i].
var waypoints: PackedVector3Array = PackedVector3Array()
var path_i: int = 0


func is_walking() -> bool:
	return state == State.WALK


func clear_path() -> void:
	waypoints = PackedVector3Array()
	path_i = 0
	state = State.STAY


func set_path(world_path: PackedVector3Array) -> void:
	## Keep current world position — do not teleport onto the first waypoint
	## (that used to drop idle/spawned peds onto crossing mids).
	waypoints = world_path
	path_i = 0
	if waypoints.is_empty():
		state = State.STAY
		return
	state = State.WALK
	if waypoints.size() >= 2:
		var d0 := Vector2(position.x - waypoints[0].x, position.z - waypoints[0].z).length_squared()
		if d0 < 1.0:
			path_i = 1
