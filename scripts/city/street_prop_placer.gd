## Places street-light poles, sidewalk props, + culled OmniLights along avenue cells.
class_name StreetPropPlacer
extends Node3D

@export var max_omni_lights: int = 12
@export var light_energy: float = 1.2
@export var light_range: float = 14.0
@export var activate_distance: float = 45.0
## Hide pole meshes beyond this (lights already distance-budgeted).
@export var pole_draw_distance: float = 90.0
## Mesh street furniture draw distance.
@export var prop_draw_distance: float = 70.0
## 0 = full day (lamps off), 1 = full night (lamps at full energy).
@export var night_factor: float = 0.0

var _poles: Array[Node3D] = []
var _props: Array[Node3D] = []
var _omnis: Array[OmniLight3D] = []
var _lamp_mats: Array[StandardMaterial3D] = []
var _camera: Camera3D
var _accum: float = 0.0
var _metal_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _sign_mat: StandardMaterial3D


func set_night_factor(factor: float) -> void:
	night_factor = clampf(factor, 0.0, 1.0)
	_refresh_lights(true)


func clear_props() -> void:
	for p in _poles:
		if is_instance_valid(p):
			p.queue_free()
	_poles.clear()
	_props.clear()
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
	_ensure_mats()
	if planner == null:
		return
	var gy := float(ground_thickness + 1) * voxel_size
	var step_cells := 3
	var placed := 0
	var max_poles := 80
	var max_furniture := 64
	var furniture := 0
	var oxw := float(origin_vox.x) * voxel_size
	var ozw := float(origin_vox.z) * voxel_size
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planner.avenue_light_cells.size() * 7919 + origin_vox.x * 13 + origin_vox.z)
	for cell in planner.avenue_light_cells:
		if (cell.x + cell.y) % step_cells != 0:
			continue
		if placed >= max_poles:
			break
		var wx := oxw + (float(cell.x) + 0.5) * float(cell_size) * voxel_size
		var wz := ozw + (float(cell.y) + 0.5) * float(cell_size) * voxel_size
		var ox := 1.6 if (cell.x % 2) == 0 else -1.6
		var oz := 1.6 if (cell.y % 2) == 0 else -1.6
		var base := Vector3(wx + ox, gy, wz + oz)
		_spawn_pole(base)
		placed += 1
		if furniture >= max_furniture:
			continue
		## Offset props along the curb away from the lamp base.
		var along := Vector3(-oz * 0.35, 0.0, ox * 0.35)
		var kind := (cell.x * 3 + cell.y * 7) % 5
		match kind:
			0:
				_spawn_bollard(base + along * 2.2)
				furniture += 1
			1:
				_spawn_trash(base + along * 2.8)
				furniture += 1
			2:
				_spawn_bench(base + along * 3.2, ox, oz)
				furniture += 1
			3:
				_spawn_sign(base + along * 2.5)
				furniture += 1
			_:
				if rng.randf() < 0.45:
					_spawn_bollard(base + along * 1.8)
					furniture += 1
	_refresh_lights(true)
	print(
		"StreetPropPlacer: poles=%d furniture=%d omni_budget=%d"
		% [placed, furniture, max_omni_lights]
	)


func _ensure_mats() -> void:
	if _metal_mat != null:
		return
	_metal_mat = StandardMaterial3D.new()
	_metal_mat.albedo_color = Color(0.22, 0.22, 0.24)
	_metal_mat.metallic = 0.55
	_metal_mat.roughness = 0.42
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.42, 0.28, 0.16)
	_wood_mat.roughness = 0.78
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.albedo_color = Color(0.85, 0.18, 0.16)
	_sign_mat.roughness = 0.55


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
	pole.material_override = _metal_mat
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position.y = 2.6
	root.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.1, 0.08, 0.08)
	arm.mesh = arm_mesh
	arm.material_override = _metal_mat
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


func _spawn_bollard(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Bollard"
	root.position = origin
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.11
	cyl.height = 0.85
	mesh.mesh = cyl
	mesh.material_override = _metal_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position.y = 0.425
	root.add_child(mesh)
	add_child(root)
	_props.append(root)


func _spawn_trash(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "TrashCan"
	root.position = origin
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.24
	cyl.height = 0.7
	body.mesh = cyl
	body.material_override = _metal_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.position.y = 0.35
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.25
	lid_mesh.bottom_radius = 0.25
	lid_mesh.height = 0.06
	lid.mesh = lid_mesh
	lid.material_override = _metal_mat
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lid.position.y = 0.72
	root.add_child(lid)
	add_child(root)
	_props.append(root)


func _spawn_bench(origin: Vector3, ox: float, oz: float) -> void:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = origin
	## Orient seat along the curb (perpendicular to lamp offset).
	if absf(ox) > absf(oz):
		root.rotation.y = PI * 0.5
	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(1.4, 0.08, 0.42)
	seat.mesh = seat_mesh
	seat.material_override = _wood_mat
	seat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seat.position.y = 0.42
	root.add_child(seat)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(1.4, 0.45, 0.06)
	back.mesh = back_mesh
	back.material_override = _wood_mat
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position = Vector3(0.0, 0.62, -0.18)
	root.add_child(back)
	for sx in [-0.55, 0.55]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.08, 0.4, 0.08)
		leg.mesh = leg_mesh
		leg.material_override = _metal_mat
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leg.position = Vector3(sx, 0.2, 0.0)
		root.add_child(leg)
	add_child(root)
	_props.append(root)


func _spawn_sign(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "StreetSign"
	root.position = origin
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.035
	post_mesh.bottom_radius = 0.04
	post_mesh.height = 2.4
	post.mesh = post_mesh
	post.material_override = _metal_mat
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.position.y = 1.2
	root.add_child(post)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.55, 0.7, 0.04)
	plate.mesh = plate_mesh
	plate.material_override = _sign_mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = Vector3(0.0, 2.15, 0.0)
	root.add_child(plate)
	add_child(root)
	_props.append(root)


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
	var prop_r2 := prop_draw_distance * prop_draw_distance
	for i in range(_poles.size()):
		var p: Node3D = _poles[i]
		var d2 := p.global_position.distance_squared_to(cam)
		var in_view := d2 <= pole_r2 and _camera.is_position_in_frustum(p.global_position + Vector3(0.0, 3.0, 0.0))
		p.visible = in_view
		scored.append({"i": i, "d2": d2})
	for prop in _props:
		if not is_instance_valid(prop):
			continue
		var pd2 := prop.global_position.distance_squared_to(cam)
		prop.visible = pd2 <= prop_r2 and _camera.is_position_in_frustum(prop.global_position + Vector3(0.0, 0.5, 0.0))
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
