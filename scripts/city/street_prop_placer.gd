## Places street-light poles + culled OmniLights along avenue cells.
class_name StreetPropPlacer
extends Node3D

@export var max_omni_lights: int = 12
@export var light_energy: float = 1.2
@export var light_range: float = 14.0
@export var activate_distance: float = 45.0
## Hide pole meshes beyond this (lights already distance-budgeted).
@export var pole_draw_distance: float = 90.0
## 0 = full day (lamps off), 1 = full night (lamps at full energy).
@export var night_factor: float = 0.0

var _poles: Array[Node3D] = []
var _omnis: Array[OmniLight3D] = []
var _lamp_mats: Array[StandardMaterial3D] = []
var _camera: Camera3D
var _accum: float = 0.0


func set_night_factor(factor: float) -> void:
	night_factor = clampf(factor, 0.0, 1.0)
	_refresh_lights(true)


func clear_props() -> void:
	for p in _poles:
		if is_instance_valid(p):
			p.queue_free()
	_poles.clear()
	_omnis.clear()
	_lamp_mats.clear()
	for c in get_children():
		c.queue_free()


func place_from_planner(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	ground_thickness: int,
	camera: Camera3D,
	origin_vox: Vector3i = Vector3i.ZERO
) -> void:
	clear_props()
	_camera = camera
	if planner == null:
		return
	var gy := float(ground_thickness + 1) * voxel_size
	var step_cells := 3
	var placed := 0
	var max_poles := 80
	var oxw := float(origin_vox.x) * voxel_size
	var ozw := float(origin_vox.z) * voxel_size
	for cell in planner.avenue_light_cells:
		if (cell.x + cell.y) % step_cells != 0:
			continue
		if placed >= max_poles:
			break
		var wx := oxw + (float(cell.x) + 0.5) * float(cell_size) * voxel_size
		var wz := ozw + (float(cell.y) + 0.5) * float(cell_size) * voxel_size
		var ox := 1.6 if (cell.x % 2) == 0 else -1.6
		var oz := 1.6 if (cell.y % 2) == 0 else -1.6
		_spawn_pole(Vector3(wx + ox, gy, wz + oz))
		placed += 1
	_refresh_lights(true)
	print("StreetPropPlacer: poles=%d omni_budget=%d" % [placed, max_omni_lights])


func _spawn_pole(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "StreetLight"
	root.position = origin

	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 5.2
	pole.mesh = cyl
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.22, 0.24)
	pole_mat.metallic = 0.4
	pole_mat.roughness = 0.45
	pole.material_override = pole_mat
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position.y = 2.6
	root.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.1, 0.08, 0.08)
	arm.mesh = arm_mesh
	arm.material_override = pole_mat
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.position = Vector3(0.45, 5.15, 0.0)
	root.add_child(arm)

	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.14
	lamp_mesh.height = 0.28
	lamp.mesh = lamp_mesh
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.92, 0.75)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.88, 0.55)
	lamp_mat.emission_energy_multiplier = 0.15
	lamp.material_override = lamp_mat
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.position = Vector3(0.95, 5.05, 0.0)
	root.add_child(lamp)

	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.9, 0.7)
	omni.light_energy = light_energy
	omni.omni_range = light_range
	omni.shadow_enabled = false
	omni.position = Vector3(0.95, 5.0, 0.0)
	omni.visible = false
	root.add_child(omni)

	add_child(root)
	_poles.append(root)
	_omnis.append(omni)
	_lamp_mats.append(lamp_mat)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.35:
		return
	_accum = 0.0
	_refresh_lights(false)


func _refresh_lights(_force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam := _camera.global_position
	var scored: Array = []
	var pole_r2 := pole_draw_distance * pole_draw_distance
	for i in range(_poles.size()):
		var p: Node3D = _poles[i]
		var d2 := p.global_position.distance_squared_to(cam)
		var in_view := d2 <= pole_r2 and _camera.is_position_in_frustum(p.global_position + Vector3(0.0, 3.0, 0.0))
		p.visible = in_view
		scored.append({"i": i, "d2": d2})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))
	var limit := mini(max_omni_lights, scored.size())
	var activate_r2 := activate_distance * activate_distance
	## Lamps only come on as night falls.
	var lamps_on := night_factor > 0.18
	var lamp_power := smoothstep(0.18, 0.75, night_factor)
	var active: Dictionary = {}
	if lamps_on:
		for k in range(limit):
			var item: Dictionary = scored[k]
			var idx := int(item["i"])
			if float(item["d2"]) <= activate_r2 and _poles[idx].visible:
				active[idx] = true
	for i in range(_omnis.size()):
		var on := active.has(i)
		_omnis[i].visible = on
		_omnis[i].light_energy = light_energy * lamp_power if on else 0.0
		if i < _lamp_mats.size() and _lamp_mats[i] != null:
			_lamp_mats[i].emission_energy_multiplier = lerpf(0.12, 3.4, lamp_power) if on else lerpf(0.08, 0.35, lamp_power * 0.25)
