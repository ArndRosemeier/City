## Scene content for a Fractal district: four MandelbrotPanels on the glow-square edges.
## Panels face *away* from the district centre so a player reading a panel has the plaza
## behind it.
class_name MandelbrotArena
extends Node3D

const MandelbrotPanelScript := preload("res://scripts/city/mandelbrot_panel.gd")

## Pull panels slightly onto the square so they sit on glowing voxels, not the grass verge.
const EDGE_INSET_M := 0.5


func setup(world_min: Vector3, world_max: Vector3, ground_y_m: float) -> void:
	name = "MandelbrotArena"
	var min_xz := Vector2(world_min.x, world_min.z)
	var max_xz := Vector2(world_max.x, world_max.z)
	var size := Vector2(max_xz.x - min_xz.x, max_xz.y - min_xz.y)
	if size.x < 20.0 or size.y < 20.0:
		push_error("MandelbrotArena: glow square too small (%s)" % str(size))
		return
	## Force a square footprint even if callers pass a slightly oblong AABB.
	var side := minf(size.x, size.y)
	var center := Vector3(
		(min_xz.x + max_xz.x) * 0.5,
		ground_y_m,
		(min_xz.y + max_xz.y) * 0.5
	)
	var half := side * 0.5 - EDGE_INSET_M
	var panel_y := ground_y_m + MandelbrotPanelScript.PANEL_H * 0.5
	## Local −Z is the panel face. Outward on each edge (centre behind the panel).
	## Yaw table is the inward-facing set rotated by π (Ui3D / Godot Y convention).
	_spawn_panel(Vector3(center.x, panel_y, center.z - half), 0.0) ## south → −Z
	_spawn_panel(Vector3(center.x, panel_y, center.z + half), PI) ## north → +Z
	_spawn_panel(Vector3(center.x - half, panel_y, center.z), PI * 0.5) ## west → −X
	_spawn_panel(Vector3(center.x + half, panel_y, center.z), -PI * 0.5) ## east → +X


func panel_count() -> int:
	var n := 0
	for child in get_children():
		if child.has_method("rebuild_fractal"):
			n += 1
	return n


func _spawn_panel(origin: Vector3, face_yaw: float) -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", origin, face_yaw)
