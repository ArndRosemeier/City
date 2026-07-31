## Purple conversion orb fired by undead mages.
extends Area3D

const SPEED_MPS := 25.0
const MAX_RANGE_M := 30.0
## Visual / collision sphere (2× original 0.55).
const VISUAL_RADIUS_M := 1.1
## Convert / player-hit radius (2× original 0.55 * 1.6).
const CAPTURE_RADIUS_M := 1.76

var _velocity: Vector3 = Vector3.ZERO
var _traveled: float = 0.0
var _director: Node
## CityRoot (or any host with projectile_obstacle_distance) for wall occlusion.
var _obstacle_host: Node
var _alive: bool = true


func launch(
	from: Vector3, toward: Vector3, director: Node, obstacle_host: Node = null
) -> void:
	_director = director
	_obstacle_host = obstacle_host if obstacle_host != null else director
	global_position = from
	var dir := toward - from
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	_velocity = dir.normalized() * SPEED_MPS
	_traveled = 0.0
	_alive = true
	_build()
	set_physics_process(true)


func _build() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CAPTURE_RADIUS_M
	cs.shape = sphere
	add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = VISUAL_RADIUS_M
	mesh.height = VISUAL_RADIUS_M * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.2, 0.95, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.25, 1.0)
	mat.emission_energy_multiplier = 4.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.65, 0.3, 1.0)
	light.light_energy = 3.4
	light.omni_range = 9.0
	light.shadow_enabled = false
	add_child(light)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var prev := global_position
	var step := _velocity * delta
	global_position += step
	_traveled += step.length()
	if _traveled >= MAX_RANGE_M:
		_die()
		return
	## Solid voxels stop the orb (same probe as bolts / player projectiles).
	if _obstacle_host != null and _obstacle_host.has_method("projectile_obstacle_distance"):
		var tip := global_position
		var hit_d: float = float(
			_obstacle_host.call("projectile_obstacle_distance", prev, tip, false)
		)
		if hit_d >= 0.0 and hit_d < prev.distance_to(tip):
			var dir := _velocity
			if dir.length_squared() < 0.0001:
				dir = tip - prev
			if dir.length_squared() > 0.0001:
				dir = dir.normalized()
			else:
				dir = Vector3.FORWARD
			var hit_point := prev + dir * hit_d
			## Same voxel strike path as player laser / blaster impacts.
			if _obstacle_host.has_method("apply_voxel_strike"):
				_obstacle_host.call(
					"apply_voxel_strike", hit_point - dir * 0.15, dir, 2.5, 1.0
				)
			_die()
			return
	## Invasion director converts peds (+ player). Free / arena summons still kill the player.
	if _director != null and _director.has_method("try_convert_ped_at"):
		if bool(_director.call("try_convert_ped_at", global_position, CAPTURE_RADIUS_M)):
			_die()
			return
	if (
		_obstacle_host != null
		and _obstacle_host.has_method("try_orb_hit_player")
		and bool(_obstacle_host.call("try_orb_hit_player", global_position, CAPTURE_RADIUS_M))
	):
		_die()


func _die() -> void:
	_alive = false
	queue_free()
