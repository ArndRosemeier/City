## Renders the Tetris block / ghost / Game Boy shell shaders for a few frames so any
## shader compile error is printed, then saves a preview PNG.
extends SceneTree

const BLOCK_SHADER := "res://assets/city/shaders/tetris_block.gdshader"
const GHOST_SHADER := "res://assets/city/shaders/tetris_ghost.gdshader"
const SHELL_SHADER := "res://assets/city/shaders/gameboy_shell.gdshader"
const OUT_PNG := "res://tools/tetris_shader_preview.png"

const PIECE_COLORS := [
	Color(0.15, 0.9, 0.95),
	Color(0.2, 0.35, 0.95),
	Color(0.98, 0.55, 0.12),
	Color(0.98, 0.9, 0.15),
	Color(0.2, 0.92, 0.3),
	Color(0.78, 0.28, 0.95),
	Color(0.95, 0.18, 0.22),
]

## Names the game sets from GDScript — each must exist as a shader uniform.
const REQUIRED_UNIFORMS := {
	BLOCK_SHADER: [
		"block_color", "edge_color", "core_color", "mesh_half", "emission_base",
		"emission_peak", "pulse_hz", "bevel", "seam", "ring_radius", "ring_width",
		"stud_scale", "stud_size", "gloss",
	],
	GHOST_SHADER: ["ghost_color", "mesh_half", "frame_width", "strength", "fill", "pulse_hz"],
	SHELL_SHADER: [
		"albedo_tex", "texture_mix", "plastic_tint", "seam_color", "lcd_glow", "lcd_deep",
		"cell_size", "seam_width", "bevel", "grain_scale", "grain_strength",
		"cell_tint_variation", "emission_base", "emission_peak", "pulse_hz",
		"scan_strength", "sheen",
	],
}

var _frames := 0


func _check_uniforms(path: String, shader: Shader) -> void:
	var have: Dictionary = {}
	for entry in shader.get_shader_uniform_list():
		have[String(entry["name"])] = true
	var want: Array = REQUIRED_UNIFORMS[path]
	for u in want:
		if not have.has(String(u)):
			push_error("FAIL %s: missing uniform '%s'" % [path, u])
			quit(1)
			return
	print("OK uniforms (%d): %s" % [want.size(), path])


func _load_shader(path: String) -> Shader:
	var shader: Shader = load(path) as Shader
	if shader == null:
		push_error("FAIL load: %s" % path)
		quit(1)
	print("OK load: %s" % path)
	_check_uniforms(path, shader)
	return shader


func _initialize() -> void:
	var block_shader := _load_shader(BLOCK_SHADER)
	var ghost_shader := _load_shader(GHOST_SHADER)
	var shell_shader := _load_shader(SHELL_SHADER)

	var holder := Node3D.new()
	holder.name = "ShaderProbe"
	root.add_child(holder)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	holder.add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.35, 3.4)
	cam.rotation = Vector3(-0.08, 0.0, 0.0)
	holder.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.75, 0.6, 0.0)
	light.light_energy = 1.4
	holder.add_child(light)

	## Game Boy shell slab behind the pieces (panel seams every 0.5 world units).
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = shell_shader
	wall_mat.set_shader_parameter("texture_mix", 0.0)
	wall_mat.set_shader_parameter("cell_size", 0.5)
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(4.0, 2.0, 0.5)
	wall.mesh = wall_box
	wall.material_override = wall_mat
	wall.position = Vector3(0.0, 0.25, -0.9)
	holder.add_child(wall)

	var half := 0.225
	var x := -1.35
	for c in PIECE_COLORS:
		var color: Color = c
		var mat := ShaderMaterial.new()
		mat.shader = block_shader
		mat.set_shader_parameter("block_color", color)
		mat.set_shader_parameter("edge_color", Color(1, 1, 1).lerp(color.lightened(0.5), 0.4))
		mat.set_shader_parameter("core_color", color.lightened(0.65))
		mat.set_shader_parameter("mesh_half", half)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (half * 2.0)
		mi.mesh = box
		mi.material_override = mat
		mi.position = Vector3(x, 0.35, 0.0)
		mi.rotation = Vector3(0.3, 0.6, 0.0)
		holder.add_child(mi)
		x += 0.45

	var ghost_mat := ShaderMaterial.new()
	ghost_mat.shader = ghost_shader
	ghost_mat.set_shader_parameter("mesh_half", half)
	for i in 4:
		var gi := MeshInstance3D.new()
		var gbox := BoxMesh.new()
		gbox.size = Vector3.ONE * (half * 2.0)
		gi.mesh = gbox
		gi.material_override = ghost_mat
		gi.position = Vector3(-0.9 + float(i) * 0.45, -0.3, 0.0)
		holder.add_child(gi)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		push_error("FAIL: no viewport image")
		return true
	img.save_png(OUT_PNG)
	print("SAVED preview: %s" % OUT_PNG)
	return true
