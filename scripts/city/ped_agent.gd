## Lightweight city pedestrian brain (no Node). Simulated by CrowdDirector.
class_name PedAgent
extends RefCounted

enum State { STAY, WALK }
enum Lod { CULLED, NEAR }

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
## Bound skinned visual while inside render distance; null when culled.
var visual: Node3D = null
## Laser/melee kill — stops simulation; Death01 holds on the visual.
var dead: bool = false
## True while sprinting away from the player after witnessing destruction.
var fleeing: bool = false
## Latest threat point (usually the player) to run away from.
var flee_from: Vector3 = Vector3.ZERO
## Avoid duplicate entries in the budgeted flee-repath queue.
var flee_repath_queued: bool = false

## Roadmap path in world space; walk toward waypoints[path_i].
var waypoints: PackedVector3Array = PackedVector3Array()
var path_i: int = 0


func is_walking() -> bool:
	return (not dead) and state == State.WALK


func is_fleeing() -> bool:
	return (not dead) and fleeing


func move_speed(flee_mul: float = 2.6) -> float:
	if is_fleeing():
		return walk_speed * flee_mul
	return walk_speed


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
