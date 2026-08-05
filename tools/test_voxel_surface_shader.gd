## Voxel surface shader check: compiles the shared shaders, asserts every uniform
## the library sets exists, verifies each voxel type has a surface spec, and renders a
## real-scale preview PNG (brick wall / asphalt / grass / glass / water).
extends SceneTree

const SURFACE_SHADER := "res://assets/city/shaders/voxel_surface.gdshader"
const GLASS_SHADER := "res://assets/city/shaders/voxel_glass.gdshader"
const WATER_SHADER := "res://assets/city/shaders/voxel_water.gdshader"
const FOLIAGE_SHADER := "res://assets/city/shaders/voxel_foliage.gdshader"
const CLOUDSTONE_SHADER := "res://assets/city/shaders/voxel_cloudstone.gdshader"
const OUT_PNG := "res://tools/voxel_surface_preview.png"

## Names VoxelBlockLibrary sets from GDScript — each must exist as a shader uniform.
const REQUIRED_UNIFORMS := {
	SURFACE_SHADER: [
		"albedo_tex", "normal_tex", "use_normal", "tile_meters", "tint", "normal_strength",
		"roughness_base", "metallic_base", "object_space", "lot_meters", "tint_variation",
		"weathering", "grime", "ground_y", "grime_height", "streaks",
	],
	GLASS_SHADER: [
		"albedo_tex", "tile_meters", "tint", "roughness_base", "metallic_base",
		"object_space", "fresnel_strength", "window_meters", "lit_ratio", "night_factor",
		"lit_warm", "lit_cool", "lit_energy", "day_sky_tint",
	],
	WATER_SHADER: [
		"albedo_tex", "tile_meters", "tint", "deep_tint", "roughness_base", "metallic_base",
		"object_space", "scroll_speed", "wave_scale", "wave_strength", "wave_speed",
		"fresnel_strength", "sparkle",
	],
	FOLIAGE_SHADER: [
		"albedo_tex", "tint", "roughness_base", "metallic_base", "alpha_scissor",
		"lot_meters", "tint_variation",
	],
	CLOUDSTONE_SHADER: [
		"tint", "shadow_tint", "roughness_base", "metallic_base", "object_space",
		"puff_scale", "puff_speed", "emission_strength", "edge_softness",
	],
}

var _frames := 0
var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _check_uniforms(path: String) -> void:
	var shader := load(path) as Shader
	if shader == null:
		_fail("FAIL load: %s" % path)
		return
	var have: Dictionary = {}
	for entry in shader.get_shader_uniform_list():
		have[String(entry["name"])] = true
	var want: Array = REQUIRED_UNIFORMS[path]
	for u in want:
		if not have.has(String(u)):
			_fail("FAIL %s: missing uniform '%s'" % [path, u])
			return
	print("OK uniforms (%d): %s" % [want.size(), path])


func _check_specs() -> void:
	var kinds: Dictionary = {}
	for id in range(1, VoxelMaterial.COUNT):
		if VoxelSurfaceSpec.has_bespoke_shader(id):
			continue
		var spec := VoxelSurfaceSpec.for_id(id)
		if spec.albedo_file == "":
			_fail("FAIL spec %d: no albedo texture" % id)
			return
		if spec.tile_meters.x <= 0.0 or spec.tile_meters.y <= 0.0:
			_fail("FAIL spec %d: bad tile_meters %s" % [id, spec.tile_meters])
			return
		var mat := VoxelBlockLibrary.surface_material(id, false)
		if mat.shader == null:
			_fail("FAIL spec %d: material has no shader" % id)
			return
		kinds[spec.kind] = int(kinds.get(spec.kind, 0)) + 1
	print(
		"OK specs: %d opaque, %d glass, %d water, %d foliage, %d cloudstone"
		% [
			int(kinds.get(VoxelSurfaceSpec.Kind.OPAQUE, 0)),
			int(kinds.get(VoxelSurfaceSpec.Kind.GLASS, 0)),
			int(kinds.get(VoxelSurfaceSpec.Kind.WATER, 0)),
			int(kinds.get(VoxelSurfaceSpec.Kind.FOLIAGE, 0)),
			int(kinds.get(VoxelSurfaceSpec.Kind.CLOUDSTONE, 0)),
		]
	)
	if int(kinds.get(VoxelSurfaceSpec.Kind.FOLIAGE, 0)) < 2:
		_fail("FAIL expected LEAVES+YEW foliage kinds")
	if int(kinds.get(VoxelSurfaceSpec.Kind.CLOUDSTONE, 0)) < 1:
		_fail("FAIL expected CLOUDSTONE surface kind")


func _slab(holder: Node3D, size: Vector3, pos: Vector3, id: int) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = VoxelBlockLibrary.surface_material(id, false)
	mi.position = pos
	holder.add_child(mi)


func _initialize() -> void:
	for path in REQUIRED_UNIFORMS.keys():
		_check_uniforms(String(path))
	_check_specs()

	var holder := Node3D.new()
	holder.name = "SurfaceProbe"
	root.add_child(holder)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	holder.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.7, 0.0)
	sun.light_energy = 1.4
	holder.add_child(sun)

	## Street deck sits at world y = 3.5 (ground_thickness=6 + 1 voxel), which is where
	## the shader's ground grime ramp starts.
	var deck := 3.5
	_slab(holder, Vector3(16.0, 0.5, 10.0), Vector3(0.0, deck - 0.25, 0.0), VoxelMaterial.ASPHALT)
	_slab(holder, Vector3(16.0, 0.2, 2.0), Vector3(0.0, deck + 0.1, 4.0), VoxelMaterial.SIDEWALK)
	## Two brick walls one lot apart: the per-lot tint hash should make them differ.
	_slab(holder, Vector3(6.0, 7.0, 0.5), Vector3(-5.0, deck + 3.5, -2.0), VoxelMaterial.BRICK)
	_slab(holder, Vector3(6.0, 7.0, 0.5), Vector3(9.0, deck + 3.5, -2.0), VoxelMaterial.BRICK)
	_slab(holder, Vector3(6.0, 7.0, 0.5), Vector3(2.0, deck + 3.5, -2.0), VoxelMaterial.PLASTER)
	_slab(holder, Vector3(3.0, 3.0, 0.4), Vector3(-5.0, deck + 4.0, -1.6), VoxelMaterial.GLASS_LIT)
	_slab(holder, Vector3(3.0, 3.0, 0.4), Vector3(2.0, deck + 4.0, -1.6), VoxelMaterial.GLASS)
	_slab(holder, Vector3(4.0, 0.3, 3.0), Vector3(-6.0, deck + 0.2, 3.0), VoxelMaterial.PARK)
	_slab(holder, Vector3(3.0, 0.3, 2.5), Vector3(6.5, deck + 0.2, 3.0), VoxelMaterial.WATER)
	_slab(holder, Vector3(2.0, 2.0, 2.0), Vector3(-11.0, deck + 1.0, 2.0), VoxelMaterial.STONE)
	_slab(holder, Vector3(2.0, 2.0, 2.0), Vector3(12.0, deck + 1.0, 2.0), VoxelMaterial.ROOF_CLAY)

	## Object-space projection used by tumbling debris.
	var debris := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3.ONE * 0.5
	debris.mesh = dbox
	debris.material_override = VoxelBlockLibrary.surface_material(VoxelMaterial.BRICK, true)
	debris.position = Vector3(0.0, deck + 0.4, 3.6)
	debris.rotation = Vector3(0.4, 0.7, 0.2)
	holder.add_child(debris)

	## Night windows so the per-window lit hash is visible in the preview.
	VoxelBlockLibrary.set_glass_lit_night_factor(0.85)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, deck + 4.5, 12.0)
	cam.rotation = Vector3(-0.18, 0.0, 0.0)
	cam.fov = 60.0
	holder.add_child(cam)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	## Headless builds use RendererDummy — get_image() errors there. Uniform/spec
	## checks above are the real gate; the PNG is a headed/dev convenience.
	if DisplayServer.get_name() == "headless":
		print("SKIP preview PNG (headless / RendererDummy)")
	else:
		var img: Image = root.get_texture().get_image()
		if img == null:
			_fail("FAIL: no viewport image")
		else:
			img.save_png(OUT_PNG)
			print("SAVED preview: %s" % OUT_PNG)
	if _failed:
		print("RESULT: FAILED")
		quit(1)
	else:
		print("RESULT: OK")
		quit(0)
	return true
