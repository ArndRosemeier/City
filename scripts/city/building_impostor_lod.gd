## Far-building massing LOD: simple colored boxes beyond the voxel mesh radius.
## Near the camera, VoxelTerrain shows full Blocky detail; farther away only these shells draw.
## Uses nearest-face distance + hysteresis so shells don't flicker at the mesh fringe.
## Packs only in-frustum shells into MultiMesh visible_instance_count.
class_name BuildingImpostorLod
extends Node3D

@export var voxel_detail_distance: float = 440.0
@export var cull_distance: float = 900.0
@export var refresh_sec: float = 0.35
## Band (m) where LOD state is sticky. Hide shells well inside the mesh radius;
## only bring them back near the outer fringe so voxels and shells overlap briefly.
@export var lod_hysteresis_m: float = 16.0

var _entries: Array = []  # Dictionary: center, size, color
var _mm: MultiMeshInstance3D
var _camera: Camera3D
var _accum: float = 0.0
var _visible_count: int = 0
## Per-building: 1 = want impostor (distance band), 0 = hidden (voxel detail expected).
var _impostor_on: PackedByteArray = PackedByteArray()


func setup(camera: Camera3D, buildings: Array, detail_distance_m: float) -> void:
	clear()
	_camera = camera
	## Switch slightly inside the viewer radius so shells vanish only after meshes exist.
	voxel_detail_distance = maxf(detail_distance_m * 0.88, 0.0)
	cull_distance = maxf(detail_distance_m * 2.4, 220.0)
	_entries = buildings.duplicate()
	_impostor_on.resize(_entries.size())
	_impostor_on.fill(0)
	_build_multimesh()
	_refresh(true)
	print(
		"BuildingImpostorLod: buildings=%d detail=%.0fm cull=%.0fm hyst=%.0fm"
		% [_entries.size(), voxel_detail_distance, cull_distance, lod_hysteresis_m]
	)


func clear() -> void:
	_entries.clear()
	_impostor_on = PackedByteArray()
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
	mm.visible_instance_count = 0
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.72
	mat.metallic = 0.05
	_mm.material_override = mat
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)


func _physics_process(delta: float) -> void:
	if _mm == null or _entries.is_empty():
		return
	_accum += delta
	if _accum < refresh_sec:
		return
	_accum = 0.0
	_refresh(false)


func _horiz_dist_sq_to_aabb(cam: Vector3, center: Vector3, size: Vector3) -> float:
	## Distance to nearest point of the building footprint (not the center).
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cx := clampf(cam.x, center.x - hx, center.x + hx)
	var cz := clampf(cam.z, center.z - hz, center.z + hz)
	var dx := cx - cam.x
	var dz := cz - cam.z
	return dx * dx + dz * dz


func _building_in_frustum(cam: Camera3D, center: Vector3, size: Vector3) -> bool:
	## Center + mid-height footprint corners — cheap AABB sample.
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y := center.y
	if cam.is_position_in_frustum(center):
		return true
	if cam.is_position_in_frustum(Vector3(center.x - hx, y, center.z - hz)):
		return true
	if cam.is_position_in_frustum(Vector3(center.x + hx, y, center.z - hz)):
		return true
	if cam.is_position_in_frustum(Vector3(center.x - hx, y, center.z + hz)):
		return true
	return cam.is_position_in_frustum(Vector3(center.x + hx, y, center.z + hz))


func _refresh(force: bool) -> void:
	if _mm == null or _camera == null or not is_instance_valid(_camera):
		return
	var mm := _mm.multimesh
	var cam := _camera.global_position
	var hyst := lod_hysteresis_m
	## Inside this: force shells off (voxels should own the near field).
	var hide_d := maxf(voxel_detail_distance - hyst, 0.0)
	## Outside this (and inside cull): force shells on.
	var show_d := maxf(voxel_detail_distance + hyst * 0.35, hide_d + 1.0)
	if voxel_detail_distance <= 0.001:
		## Far tiles: always show shells (no voxel buildings).
		hide_d = -1.0
		show_d = -1.0
	var hide_r2 := hide_d * hide_d
	var show_r2 := show_d * show_d
	var cull_r2 := cull_distance * cull_distance
	_visible_count = 0
	var write_i := 0
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var center: Vector3 = e["center"]
		var size: Vector3 = e["size"]
		var d2 := _horiz_dist_sq_to_aabb(cam, center, size)
		var on := _impostor_on[i] != 0
		if force:
			on = d2 > show_r2 and d2 <= cull_r2
		elif d2 > cull_r2:
			on = false
		elif d2 <= hide_r2:
			on = false
		elif d2 >= show_r2:
			on = true
		## else: keep previous state (hysteresis band)
		_impostor_on[i] = 1 if on else 0
		if not on:
			continue
		if not _building_in_frustum(_camera, center, size):
			continue
		## Slight undersize avoids z-fight while shells overlap the voxel fringe.
		var basis := Basis.from_scale(size * 0.988)
		mm.set_instance_transform(write_i, Transform3D(basis, center))
		mm.set_instance_color(write_i, e["color"])
		write_i += 1
	mm.visible_instance_count = write_i
	_visible_count = write_i
	## Tight AABB so parked/hidden instances don't inflate the MultiMesh cull box.
	if write_i > 0:
		_mm.custom_aabb = AABB(cam - Vector3(cull_distance, 80.0, cull_distance), Vector3(cull_distance * 2.0, 160.0, cull_distance * 2.0))
	else:
		_mm.custom_aabb = AABB(Vector3.ZERO, Vector3.ZERO)
