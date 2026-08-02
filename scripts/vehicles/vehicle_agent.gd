## One car: the body the navigation stack drives, plus the presentation and lane state the
## vehicle director and the visual read back.
##
## A Node3D rather than a plain brain, because NavAgent drives a body and NavMotor writes its
## transform. There is no collision shape and no collision layer: cars have never been physics
## bodies while they are driving, and only become one as a RigidBody3D wreck.
##
## `yaw` is the body's own Y rotation rather than a separate field, so the motor steering the
## node and the visual reading the angle cannot drift apart.
class_name VehicleAgent
extends Node3D

## Visual LOD, which is about render distance and has nothing to do with the nav tier.
enum Lod { CULLED, NEAR }

var lod: int = Lod.CULLED
var catalog_id: String = ""
var passenger_count: int = 1
var cruise_speed: float = 8.0

## Bound visual while inside render distance; null when culled.
var visual: Node3D = null
## Avoid duplicate entries in the budgeted visual-creation queue.
var visual_queued: bool = false
## Hit by laser or melee: out of traffic, and the mesh becomes a physics wreck.
var wrecked: bool = false

## Goal, corridor and failure ladder. Built by VehicleDirector.
var nav: NavAgent = null
var motor: VehicleMotor = null

## The whole drive as lane nodes, kept so a blast can be tested against it.
var route: PackedInt32Array = PackedInt32Array()
## Lane nodes still to be driven to, one NavGoal each.
var legs: PackedInt32Array = PackedInt32Array()
## CarLaneGraph version the route was planned against.
var route_version: int = 0
## Lane node the car is currently driving to, or -1. This is what gets closed when there turns
## out to be no road under it.
var lane_node: int = -1
## Lane node the current leg started at, or -1. Together with `lane_node` it names the lane
## line VehicleMotor holds the car on, which is why it is only set for legs of a planned drive:
## a flee goal is a far-away lane point with no single carriageway between here and there.
var lane_from: int = -1

## True while flooring it away from a threat.
var fleeing: bool = false
## Latest threat point to drive away from.
var flee_from: Vector3 = Vector3.ZERO
## Stop fleeing once at least this far from `flee_from`.
var flee_clear_m: float = 200.0
## Avoid duplicate entries in the budgeted flee-goal queue.
var flee_goal_queued: bool = false

## The goal provider hands out no leg before this.
var paused_until: float = 0.0
## Seconds owed to a far-tier body, which is stepped every few frames rather than every one.
var owed_delta: float = 0.0


## Heading in the XZ plane. The visual convention is nose along local -Z.
var yaw: float:
	get:
		return rotation.y
	set(value):
		rotation.y = value


func is_fleeing() -> bool:
	return (not wrecked) and fleeing


func drive_speed(flee_mul: float) -> float:
	if is_fleeing():
		return cruise_speed * flee_mul
	return cruise_speed


## Where the nose points, for choosing a lane the car can join without turning round.
func heading() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


## Drop the rest of the drive. The car asks for a new one on its next goal.
func clear_route() -> void:
	route = PackedInt32Array()
	legs = PackedInt32Array()
	lane_node = -1
	lane_from = -1
