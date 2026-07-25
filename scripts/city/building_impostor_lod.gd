## Far-building massing LOD: stepped boxes + window-grid shader beyond voxel mesh radius.
## Near the camera, VoxelTerrain shows full Blocky detail; farther away only these shells draw.
## Uses nearest-face distance + hysteresis so shells don't flicker at the mesh fringe.
## Packs only in-frustum shells into MultiMesh visible_instance_count.
class_name BuildingImpostorLod
extends Node3D

const IMPOSTOR_SHADER := preload("res://assets/city/shaders/building_impostor.gdshader")

@export var voxel_detail_distance: float = 440.0
@export var cull_distance: float = 900.0
@export var refresh_sec: float = 0.35
## Band (m) where LOD state is sticky. Hide shells well inside the mesh radius;
## only bring them back near the outer fringe so voxels and shells overlap briefly.
@export var lod_hysteresis_m: float = 16.0
## 0 = day, 1 = night — window emission on impostor glass.
@export var night_factor: float = 0.0

var _entries: Array = []  # Dictionary: shape, center, size, yaw, color, custom
## One MultiMesh per primitive, indexed by BuildingGrammar.ImpostorShape. Round buildings
## need a round shell — drawing them as boxes turned every cylinder and pod back into a
## block the moment the voxels were swapped out.
var _mms: Array[MultiMeshInstance3D] = []
## Axis-aligned world extent per entry. `size` is in the part's own frame, so yawed
## parts (pitched roofs, twisted slabs) would otherwise be measured across the wrong
## axis when picking LOD distance and frustum corners.
var _world_size: PackedVector3Array = PackedVector3Array()
var _shader_mat: ShaderMaterial
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
	_world_size.resize(_entries.size())
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var s: Vector3 = e["size"]
		var yaw := float(e.get("yaw", 0.0))
		if is_zero_approx(yaw):
			_world_size[i] = s
			continue
		var ca := absf(cos(yaw))
		var sa := absf(sin(yaw))
		_world_size[i] = Vector3(ca * s.x + sa * s.z, s.y, sa * s.x + ca * s.z)
	_build_multimesh()
	_refresh(true)
	print(
		"BuildingImpostorLod: buildings=%d detail=%.0fm cull=%.0fm hyst=%.0fm"
		% [_entries.size(), voxel_detail_distance, cull_distance, lod_hysteresis_m]
	)


func set_night_factor(factor: float) -> void:
	night_factor = clampf(factor, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("night_factor", night_factor)


func clear() -> void:
	_entries.clear()
	_impostor_on = PackedByteArray()
	_world_size = PackedVector3Array()
	_visible_count = 0
	_shader_mat = null
	for mmi in _mms:
		if mmi != null and is_instance_valid(mmi):
			mmi.queue_free()
	_mms.clear()


func visible_count() -> int:
	return _visible_count


## Footprints for minimap (XZ boxes). Only entries whose center is within radius.
func get_footprints_near(origin: Vector3, radius_m: float) -> Array:
	var out: Array = []
	var r2 := radius_m * radius_m
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var center: Vector3 = e["center"]
		var dx := center.x - origin.x
		var dz := center.z - origin.z
		if dx * dx + dz * dz > r2:
			continue
		out.append({
			"center": center,
			"size": _world_size[i],
		})
	return out


## Unit-sized primitive per shape; the instance transform scales it to the part size.
func _shape_mesh(shape: int) -> Mesh:
	match shape:
		BuildingGrammar.ImpostorShape.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			## Coarse: these are only ever seen past the voxel mesh radius.
			cyl.radial_segments = 12
			cyl.rings = 1
			return cyl
		BuildingGrammar.ImpostorShape.SPHERE:
			var sph := SphereMesh.new()
			sph.radius = 0.5
			sph.height = 1.0
			sph.radial_segments = 12
			sph.rings = 6
			return sph
		BuildingGrammar.ImpostorShape.PRISM:
			## Symmetric ridge along local Z — pitched roofs on houses.
			var pri := PrismMesh.new()
			pri.size = Vector3.ONE
			pri.left_to_right = 0.5
			pri.subdivide_width = 0
			pri.subdivide_height = 0
			pri.subdivide_depth = 0
			return pri
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box


func _build_multimesh() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _entries.is_empty():
		return
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = IMPOSTOR_SHADER
	_shader_mat.set_shader_parameter("night_factor", night_factor)
	var shape_count := BuildingGrammar.ImpostorShape.size()
	var per_shape := PackedInt32Array()
	per_shape.resize(shape_count)
	for e: Dictionary in _entries:
		var s := int(e.get("shape", BuildingGrammar.ImpostorShape.BOX))
		per_shape[s] += 1
	_mms.resize(shape_count)
	for shape in range(shape_count):
		if per_shape[shape] == 0:
			_mms[shape] = null
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BuildingImpostors%d" % shape
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _shape_mesh(shape)
		mm.instance_count = per_shape[shape]
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.material_override = _shader_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mms[shape] = mmi


func _physics_process(delta: float) -> void:
	if _mms.is_empty() or _entries.is_empty():
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
	if _mms.is_empty() or _camera == null or not is_instance_valid(_camera):
		return
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
	var writes := PackedInt32Array()
	writes.resize(_mms.size())
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var center: Vector3 = e["center"]
		var size: Vector3 = e["size"]
		var wsize: Vector3 = _world_size[i]
		var d2 := _horiz_dist_sq_to_aabb(cam, center, wsize)
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
		if not _building_in_frustum(_camera, center, wsize):
			continue
		var shape := int(e.get("shape", BuildingGrammar.ImpostorShape.BOX))
		var mmi := _mms[shape]
		if mmi == null:
			continue
		## Slight undersize avoids z-fight while shells overlap the voxel fringe.
		var basis := Basis.from_scale(size * 0.988)
		var yaw := float(e.get("yaw", 0.0))
		if not is_zero_approx(yaw):
			basis = Basis(Vector3.UP, yaw) * basis
		var w := writes[shape]
		var mm := mmi.multimesh
		mm.set_instance_transform(w, Transform3D(basis, center))
		mm.set_instance_color(w, e["color"])
		mm.set_instance_custom_data(w, e.get("custom", Color(size.x, size.y, size.z, 0.35)))
		writes[shape] = w + 1
		_visible_count += 1
	## Tight AABB so parked/hidden instances don't inflate the MultiMesh cull box.
	var box := AABB(
		cam - Vector3(cull_distance, 80.0, cull_distance),
		Vector3(cull_distance * 2.0, 160.0, cull_distance * 2.0)
	)
	for shape in range(_mms.size()):
		var mmi2 := _mms[shape]
		if mmi2 == null:
			continue
		mmi2.multimesh.visible_instance_count = writes[shape]
		mmi2.custom_aabb = box if writes[shape] > 0 else AABB(Vector3.ZERO, Vector3.ZERO)
