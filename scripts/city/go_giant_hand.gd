## Spectacle mitt that flies in and plants a giant stone.
class_name GoGiantHand
extends Node3D

var voxel_size: float = 0.5
var _mitt: MeshInstance3D = null
var _stone: MeshInstance3D = null
var _place_epoch: int = 0
var _active_tween: Tween = null


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


func cancel() -> void:
	_place_epoch += 1
	visible = false
	if _active_tween != null and is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = null


func place_at(world_target: Vector3, is_black: bool) -> void:
	_place_epoch += 1
	var epoch := _place_epoch
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
	await _tween_to(hover, 0.45, epoch)
	if epoch != _place_epoch:
		return
	await _tween_to(world_target + Vector3(0.0, 1.2, 0.0), 0.22, epoch)
	if epoch != _place_epoch:
		return
	await get_tree().create_timer(0.08).timeout
	if epoch != _place_epoch:
		return
	await _tween_to(start, 0.35, epoch)
	if epoch != _place_epoch:
		return
	visible = false


func _tween_to(pos: Vector3, dur: float, epoch: int) -> void:
	if epoch != _place_epoch:
		return
	if _active_tween != null and is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(self, "global_position", pos, dur)
	await _active_tween.finished
	if epoch == _place_epoch:
		_active_tween = null
