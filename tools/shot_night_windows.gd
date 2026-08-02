## Night window study — the lit grids of both facade shaders across a receding skyline.
##
##   powershell -File tools\run_test.ps1 shot_night_windows -Rendered
##
## Writes tools/night_windows_glass.png (voxel_glass GLASS_LIT panels) and
## tools/night_windows_impostor.png (building_impostor shells, boxes + cylinders).
##
## Both shaders draw binary lit/dark window grids, which alias into crawling moire once a
## window cell shrinks past a pixel. Near towers must still read as distinct windows;
## the back of the field must settle into a smooth glow instead of a noise field.
extends Node

const IMPOSTOR_SHADER := preload("res://assets/city/shaders/building_impostor.gdshader")
const OUT_DIR := "res://tools/"
## z, lateral spread, height — rows march away so one frame spans every on-screen scale.
const ROWS: Array[Vector3] = [
	Vector3(-60.0, 110.0, 70.0),
	Vector3(-130.0, 170.0, 90.0),
	Vector3(-250.0, 250.0, 76.0),
	Vector3(-430.0, 340.0, 110.0),
	Vector3(-700.0, 430.0, 88.0),
	Vector3(-1100.0, 560.0, 120.0),
	Vector3(-1700.0, 700.0, 100.0),
]

var _failed := false


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	_build_environment(root)

	VoxelBlockLibrary.set_glass_lit_night_factor(1.0)
	var glass := Node3D.new()
	glass.name = "GlassField"
	root.add_child(glass)
	_build_glass_field(glass)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 62.0
	cam.far = 5000.0
	cam.global_position = Vector3(0.0, 62.0, 90.0)
	cam.look_at(Vector3(0.0, 46.0, -700.0))
	await _settle()
	_shoot("night_windows_glass.png")

	glass.queue_free()
	await get_tree().process_frame
	_build_impostor_field(root)
	await _settle()
	_shoot("night_windows_impostor.png")

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _build_environment(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.13, 0.20)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38.0, 25.0, 0.0)
	moon.light_energy = 0.18
	moon.light_color = Color(0.6, 0.7, 1.0)
	root.add_child(moon)


## Towers of every row, as (position, size) pairs. Odd rows are nudged sideways so the
## back of the field is not hidden behind the front of it.
func _tower_layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in range(ROWS.size()):
		var row := ROWS[r]
		var count := 3 + r
		for i in range(count):
			var t := (float(i) / float(count - 1)) * 2.0 - 1.0
			var w := 20.0 + 6.0 * float((i + r) % 3)
			var h := row.z * (0.7 + 0.3 * float((i * 5 + r * 3) % 4))
			out.append({
				"pos": Vector3(t * row.y + (14.0 if r % 2 == 1 else 0.0), h * 0.5, row.x),
				"size": Vector3(w, h, w * 0.9),
				"lit": 0.24 + 0.08 * float((i + r) % 4),
			})
	return out


func _build_glass_field(root: Node3D) -> void:
	var mat := VoxelBlockLibrary.surface_material(VoxelMaterial.GLASS_LIT, false)
	for t: Dictionary in _tower_layout():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = t["size"]
		mi.mesh = box
		mi.material_override = mat
		mi.position = t["pos"]
		root.add_child(mi)


func _build_impostor_field(root: Node3D) -> void:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = IMPOSTOR_SHADER
	shader_mat.set_shader_parameter("night_factor", 1.0)

	var towers := _tower_layout()
	var boxes: Array[Dictionary] = []
	var rounds: Array[Dictionary] = []
	for i in range(towers.size()):
		## Every fourth shell is round — cylinders exercise the face-axis pick, which runs
		## on interpolated normals and used to flip the whole grid as the camera moved.
		if i % 4 == 3:
			rounds.append(towers[i])
		else:
			boxes.append(towers[i])
	_add_multimesh(root, _unit_box(), boxes, shader_mat)
	_add_multimesh(root, _unit_cylinder(), rounds, shader_mat)


func _unit_box() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


func _unit_cylinder() -> Mesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	return cyl


func _add_multimesh(
	root: Node3D, mesh: Mesh, parts: Array[Dictionary], shader_mat: ShaderMaterial
) -> void:
	if parts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = parts.size()
	for i in range(parts.size()):
		var p: Dictionary = parts[i]
		var size: Vector3 = p["size"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), p["pos"]))
		mm.set_instance_color(i, Color(0.36, 0.36, 0.40))
		mm.set_instance_custom_data(i, Color(size.x, size.y, size.z, float(p["lit"])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = shader_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func _settle() -> void:
	await get_tree().create_timer(1.0).timeout


func _shoot(out_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % out_name)
		_failed = true
		return
	var path := OUT_DIR + out_name
	img.save_png(path)
	print("NIGHT_WINDOWS wrote %s" % path)
