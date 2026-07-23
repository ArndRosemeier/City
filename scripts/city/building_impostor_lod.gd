## Far-building massing LOD: simple colored boxes beyond the voxel mesh radius.
## Near the camera, VoxelTerrain shows full Blocky detail; farther away only these shells draw.
class_name BuildingImpostorLod
extends Node3D

@export var voxel_detail_distance: float = 440.0
@export var cull_distance: float = 900.0
@export var refresh_sec: float = 0.45

var _entries: Array = []  # Dictionary: center, size, color
var _mm: MultiMeshInstance3D
var _camera: Camera3D
var _accum: float = 0.0
var _visible_count: int = 0


func setup(camera: Camera3D, buildings: Array, detail_distance_m: float) -> void:
	clear()
	_camera = camera
	voxel_detail_distance = detail_distance_m
	cull_distance = maxf(detail_distance_m * 2.0, 700.0)
	_entries = buildings.duplicate()
	_build_multimesh()
	_refresh(true)
	print(
		"BuildingImpostorLod: buildings=%d detail=%.0fm cull=%.0fm"
		% [_entries.size(), voxel_detail_distance, cull_distance]
	)


func clear() -> void:
	_entries.clear()
	_visible_count = 0
	if _mm != null and is_instance_valid(_mm):
		_mm.queue_free()
	_mm = null


func visible_count() -> int:
	return _visible_count


func _build_multimesh() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _entries.is_empty():
		return
	_mm = MultiMeshInstance3D.new()
	_mm.name = "BuildingImpostors"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = _entries.size()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.72
	mat.metallic = 0.05
	_mm.material_override = mat
	_mm.multimesh = mm
	add_child(_mm)
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -2000.0, 0.0))
	for i in range(_entries.size()):
		mm.set_instance_transform(i, hidden)


func _physics_process(delta: float) -> void:
	if _mm == null or _entries.is_empty():
		return
	_accum += delta
	if _accum < refresh_sec:
		return
	_accum = 0.0
	_refresh(false)


func _refresh(_force: bool) -> void:
	if _mm == null or _camera == null or not is_instance_valid(_camera):
		return
	var mm := _mm.multimesh
	var cam := _camera.global_position
	var detail_r2 := voxel_detail_distance * voxel_detail_distance
	var cull_r2 := cull_distance * cull_distance
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -2000.0, 0.0))
	_visible_count = 0
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var center: Vector3 = e["center"]
		var dx := center.x - cam.x
		var dz := center.z - cam.z
		var d2 := dx * dx + dz * dz
		# Inside voxel mesh radius: hide shell (full Blocky buildings show).
		# Beyond mesh radius: show massing box. Beyond cull: hide.
		if d2 <= detail_r2 or d2 > cull_r2:
			mm.set_instance_transform(i, hidden)
			continue
		var size: Vector3 = e["size"]
		var basis := Basis.from_scale(size)
		var origin := center
		mm.set_instance_transform(i, Transform3D(basis, origin))
		mm.set_instance_color(i, e["color"])
		_visible_count += 1
