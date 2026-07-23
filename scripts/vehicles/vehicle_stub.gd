## Vehicles module stub
## Procedural non-voxel cars will live here later.
class_name VehicleStub
extends Node3D

func spawn_placeholder_marker() -> void:
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.8, 4.0)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.15)
	marker.material_override = mat
	marker.position = Vector3(6.0, 0.4, 0.0)
	add_child(marker)
