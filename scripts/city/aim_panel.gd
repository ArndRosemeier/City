## Vertical 5×5 m aim surface for world-space click targeting (prototype for in-game UI).
## Summoned with Z; bare LMB paints a marker at the exact hit instead of firing a bolt.
class_name AimPanel
extends Node3D

const SIZE_M := 5.0
const MARKER_M := 0.2
const MARKER_OFFSET_Z := -0.02
const HIT_EPSILON := 0.05

var _marker: MeshInstance3D = null


func begin(origin: Vector3, face_yaw: float) -> void:
	name = "AimPanel"
	add_to_group("aim_panel")
	set_meta("aim_panel", true)
	global_position = origin
	rotation = Vector3(0.0, face_yaw, 0.0)
	_build_surface()


func marker_local_position() -> Vector3:
	if _marker == null or not is_instance_valid(_marker):
		return Vector3.INF
	return _marker.position


func has_marker() -> bool:
	return _marker != null and is_instance_valid(_marker)


## Place or move the marker at a world-space hit on this panel's face.
## Returns false if the point is outside the 5×5 surface.
func mark_at_world(hit: Vector3) -> bool:
	var local := to_local(hit)
	var half := SIZE_M * 0.5
	if absf(local.x) > half + HIT_EPSILON or absf(local.y) > half + HIT_EPSILON:
		return false
	_ensure_marker()
	_marker.position = Vector3(
		clampf(local.x, -half, half),
		clampf(local.y, -half, half),
		MARKER_OFFSET_Z
	)
	return true


func clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _build_surface() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Surface"
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE_M, SIZE_M)
	mesh_inst.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.22, 0.45, 0.72, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("aim_panel")
	body.set_meta("aim_panel", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## Thin slab on the facing plane (local XY).
	box.size = Vector3(SIZE_M, SIZE_M, 0.08)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _ensure_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		return
	_marker = MeshInstance3D.new()
	_marker.name = "AimMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(MARKER_M, MARKER_M)
	_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.15, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = mat
	add_child(_marker)
