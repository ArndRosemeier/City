## Spectacle mitt that flies in and plants a giant stone.
class_name GoGiantHand
extends Node3D

var voxel_size: float = 0.5
var _mitt: MeshInstance3D = null
var _stone: MeshInstance3D = null


func configure(p_voxel_size: float) -> void:
	voxel_size = p_voxel_size
	_mitt = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.7, 3.2)
	_mitt.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.68, 0.48)
	_mitt.material_override = mat
	add_child(_mitt)
	_stone = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.7
	sph.height = 1.2
	_stone.mesh = sph
	_stone.position = Vector3(0.0, -0.85, 0.4)
	add_child(_stone)
	visible = false


func place_at(world_target: Vector3, is_black: bool) -> void:
	visible = true
	var mat := _stone.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		_stone.material_override = mat
	mat.albedo_color = Color(0.08, 0.08, 0.09) if is_black else Color(0.92, 0.92, 0.9)
	var start := world_target + Vector3(8.0, 14.0, -6.0)
	var hover := world_target + Vector3(0.0, 4.0, 0.0)
	global_position = start
	look_at(world_target, Vector3.UP)
	await _tween_to(hover, 0.45)
	await _tween_to(world_target + Vector3(0.0, 1.2, 0.0), 0.22)
	await get_tree().create_timer(0.08).timeout
	await _tween_to(start, 0.35)
	visible = false


func _tween_to(pos: Vector3, dur: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", pos, dur)
	await tw.finished
