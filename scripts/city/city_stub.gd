## Placeholder kept for crowd main scene compatibility.
class_name CityStub
extends Node3D

signal city_ready


func generate_placeholder_ground() -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	mesh_instance.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.28)
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	city_ready.emit()
