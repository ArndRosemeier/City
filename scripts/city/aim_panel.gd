## Z-summonable debug surface: a Ui3D that paints a marker where LMB hits.
class_name AimPanel
extends "res://scripts/city/ui_3d.gd"


func begin(origin: Vector3, face_yaw: float) -> void:
	name = "AimPanel"
	size_m = Vector2(5.0, 5.0)
	show_debug_marker = true
	surface_color = Color(0.22, 0.45, 0.72, 0.92)
	marker_color = Color(1.0, 0.85, 0.15, 1.0)
	super.begin(origin, face_yaw)
