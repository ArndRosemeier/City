## Builds a VoxelBlockyLibrary with city albedo textures.
## Most types stay cubes. Detail types use VoxelBlockyModelMesh visuals with a
## hidden unit-cube collision surface (CharacterBody physics treats them as solid blocks).
class_name VoxelBlockLibrary
extends RefCounted

const TEX_DIR := "res://assets/city/textures/"


static func build() -> VoxelBlockyLibrary:
	var lib := VoxelBlockyLibrary.new()
	var models: Array[VoxelBlockyModel] = []
	models.append(VoxelBlockyModelEmpty.new())
	for id in range(1, VoxelMaterial.COUNT):
		models.append(_make_model(id))
	lib.models = models
	lib.bake()
	return lib


static func _make_model(id: int) -> VoxelBlockyModel:
	match id:
		VoxelMaterial.PLANTER:
			## Collision matches the low rim — not a full cell wall.
			return _mesh_model(id, _mesh_planter(), false, false, AABB(Vector3(0.05, 0.0, 0.05), Vector3(0.9, 0.34, 0.9)))
		VoxelMaterial.LEAVES:
			## Walk-through foliage.
			return _mesh_model(id, _mesh_leaves(), false, false, AABB(), false)
		VoxelMaterial.BARK:
			return _mesh_model(id, _mesh_trunk(), false, false, AABB(Vector3(0.28, 0.0, 0.28), Vector3(0.44, 1.0, 0.44)))
		VoxelMaterial.WATER:
			## Pool surface only — don't trap the player in an invisible full cell.
			return _mesh_model(id, _mesh_water(), true, false, AABB(Vector3(0.02, 0.15, 0.02), Vector3(0.96, 0.48, 0.96)))
		VoxelMaterial.GLASS:
			return _mesh_model(id, _mesh_glass(), true, false, AABB(Vector3(0.12, 0.1, 0.12), Vector3(0.76, 0.8, 0.76)))
		VoxelMaterial.GLASS_LIT:
			return _mesh_model(id, _mesh_glass(), true, false, AABB(Vector3(0.12, 0.1, 0.12), Vector3(0.76, 0.8, 0.76)))
		VoxelMaterial.CURB:
			## Low curb lip (~0.2 m world) so CharacterBody can step/jump it.
			return _mesh_model(id, _mesh_curb(), false, true, AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.4, 1.0)))
		VoxelMaterial.ROAD_LINE:
			return _mesh_model(id, _mesh_road_line(), false, true, AABB(Vector3.ZERO, Vector3.ONE))
		VoxelMaterial.PAINT:
			return _mesh_model(id, _mesh_flower(), false, false, AABB(), false)
		_:
			return _make_cube(id)


static func _make_cube(id: int) -> VoxelBlockyModelCube:
	var cube := VoxelBlockyModelCube.new()
	cube.color = Color(1, 1, 1, 1)
	cube.set_material_override(0, material_for(id))
	if id == VoxelMaterial.GLASS or id == VoxelMaterial.GLASS_LIT or id == VoxelMaterial.WATER:
		cube.transparency_index = 1
	return cube


## Visual mesh (surface 0) + optional collision mesh (surface 1).
## Pass collide=false for walk-through props (leaves / flowers).
static func _mesh_model(
	id: int,
	visual: ArrayMesh,
	transparent: bool,
	culls_neighbors: bool,
	collision_aabb: AABB = AABB(Vector3.ZERO, Vector3.ONE),
	collide: bool = true
) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	var mat := material_for(id)
	if collide:
		model.mesh = _with_collision_box(visual, mat, collision_aabb)
		model.collision_aabbs = [collision_aabb]
		model.set_material_override(0, mat)
		model.set_material_override(1, _collision_discard_material())
		model.set_mesh_collision_enabled(0, false)
		model.set_mesh_collision_enabled(1, true)
	else:
		model.mesh = visual
		model.collision_aabbs = []
		model.set_material_override(0, mat)
		model.set_mesh_collision_enabled(0, false)
	model.culls_neighbors = culls_neighbors
	if transparent:
		model.transparency_index = 1
	return model


static func _collision_discard_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled;
void fragment() {
	discard;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


static func _with_collision_box(visual: ArrayMesh, visual_mat: Material, box: AABB) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in range(visual.get_surface_count()):
		var arrs := visual.surface_get_arrays(s)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		out.surface_set_material(out.get_surface_count() - 1, visual_mat)
	var coll := _box_mesh(box.position, box.position + box.size)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coll.surface_get_arrays(0))
	out.surface_set_material(out.get_surface_count() - 1, _collision_discard_material())
	return out


static func _box_mesh(bmin: Vector3, bmax: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Six faces, outward normals, simple UVs.
	_add_quad(st, Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(0, 0, 1))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(0, 0, -1))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(1, 0, 0))
	_add_quad(st, Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(0, 1, 0))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(0, -1, 0))
	st.index()
	return st.commit()


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	n: Vector3
) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(b)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(d)


## Low open planter box (wood rim + floor).
static func _mesh_planter() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.32
	var t := 0.1
	## Floor
	_emit_box(st, Vector3(0.08, 0.0, 0.08), Vector3(0.92, 0.06, 0.92))
	## Four rim walls
	_emit_box(st, Vector3(0.06, 0.0, 0.06), Vector3(0.94, h, 0.06 + t))
	_emit_box(st, Vector3(0.06, 0.0, 0.94 - t), Vector3(0.94, h, 0.94))
	_emit_box(st, Vector3(0.06, 0.0, 0.06), Vector3(0.06 + t, h, 0.94))
	_emit_box(st, Vector3(0.94 - t, 0.0, 0.06), Vector3(0.94, h, 0.94))
	st.index()
	return st.commit()


## Cross-plane foliage (classic plant card).
static func _mesh_leaves() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := 0.05
	var y1 := 0.95
	var inset := 0.08
	## Plane along X
	_add_quad(
		st,
		Vector3(inset, y0, 0.5),
		Vector3(1.0 - inset, y0, 0.5),
		Vector3(1.0 - inset, y1, 0.5),
		Vector3(inset, y1, 0.5),
		Vector3(0, 0, 1)
	)
	_add_quad(
		st,
		Vector3(1.0 - inset, y0, 0.5),
		Vector3(inset, y0, 0.5),
		Vector3(inset, y1, 0.5),
		Vector3(1.0 - inset, y1, 0.5),
		Vector3(0, 0, -1)
	)
	## Plane along Z
	_add_quad(
		st,
		Vector3(0.5, y0, inset),
		Vector3(0.5, y0, 1.0 - inset),
		Vector3(0.5, y1, 1.0 - inset),
		Vector3(0.5, y1, inset),
		Vector3(1, 0, 0)
	)
	_add_quad(
		st,
		Vector3(0.5, y0, 1.0 - inset),
		Vector3(0.5, y0, inset),
		Vector3(0.5, y1, inset),
		Vector3(0.5, y1, 1.0 - inset),
		Vector3(-1, 0, 0)
	)
	st.index()
	return st.commit()


## Thin trunk cylinder.
static func _mesh_trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var r := 0.2
	var cx := 0.5
	var cz := 0.5
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var x0 := cx + cos(a0) * r
		var z0 := cz + sin(a0) * r
		var x1 := cx + cos(a1) * r
		var z1 := cz + sin(a1) * r
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)).normalized()
		_add_quad(
			st,
			Vector3(x0, 0.0, z0),
			Vector3(x1, 0.0, z1),
			Vector3(x1, 1.0, z1),
			Vector3(x0, 1.0, z0),
			n
		)
	## Top disk (simple fan as quads from center)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var x0 := cx + cos(a0) * r
		var z0 := cz + sin(a0) * r
		var x1 := cx + cos(a1) * r
		var z1 := cz + sin(a1) * r
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(cx, 1.0, cz))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(Vector3(x0, 1.0, z0))
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(x1, 1.0, z1))
	st.index()
	return st.commit()


## Recessed water surface (pond / fountain pool).
static func _mesh_water() -> ArrayMesh:
	return _box_mesh(Vector3(0.02, 0.15, 0.02), Vector3(0.98, 0.62, 0.98))


## Inset window pane.
static func _mesh_glass() -> ArrayMesh:
	return _box_mesh(Vector3(0.12, 0.1, 0.12), Vector3(0.88, 0.9, 0.88))


## Low curb lip — visual matches the short collision box (~0.2 m world).
static func _mesh_curb() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.28, 1.0))
	_emit_box(st, Vector3(0.04, 0.28, 0.04), Vector3(0.96, 0.4, 0.96))
	st.index()
	return st.commit()


## Lane paint: full asphalt body + raised center stripe (one material).
static func _mesh_road_line() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.98, 1.0))
	_emit_box(st, Vector3(0.35, 0.98, 0.05), Vector3(0.65, 1.0, 0.95))
	st.index()
	return st.commit()


## Small flower blob for park accents.
static func _mesh_flower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.3, 0.0, 0.3), Vector3(0.7, 0.2, 0.7))
	_emit_box(st, Vector3(0.22, 0.2, 0.22), Vector3(0.78, 0.55, 0.78))
	_emit_box(st, Vector3(0.35, 0.55, 0.35), Vector3(0.65, 0.75, 0.65))
	st.index()
	return st.commit()


static func _emit_box(st: SurfaceTool, bmin: Vector3, bmax: Vector3) -> void:
	_add_quad(st, Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(0, 0, 1))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(0, 0, -1))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(1, 0, 0))
	_add_quad(st, Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(0, 1, 0))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(0, -1, 0))


## Shared textured materials for debris / impostors (same look as Blocky voxels).
static var _mat_cache: Dictionary = {}  # int → StandardMaterial3D


static func material_for(id: int) -> StandardMaterial3D:
	var cached: Variant = _mat_cache.get(id)
	if cached is StandardMaterial3D:
		return cached
	var mat := _material_for(id)
	_mat_cache[id] = mat
	return mat


## Drive emissive punched windows with day/night (shared GLASS_LIT material).
static func set_glass_lit_night_factor(night_factor: float) -> void:
	var mat := material_for(VoxelMaterial.GLASS_LIT)
	var n := clampf(night_factor, 0.0, 1.0)
	var power := smoothstep(0.15, 0.7, n)
	mat.emission_enabled = power > 0.02
	mat.emission = Color(1.0, 0.82, 0.4)
	mat.emission_energy_multiplier = lerpf(0.05, 3.2, power)
	mat.albedo_color = Color(1.0, 0.9, 0.55, lerpf(0.35, 0.62, power))


static func _material_for(id: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.88

	match id:
		VoxelMaterial.BEDROCK:
			mat.albedo_texture = _tex("rock.jpg")
			mat.roughness = 0.95
		VoxelMaterial.ROAD, VoxelMaterial.ASPHALT:
			mat.albedo_texture = _tex("asphalt.jpg")
			mat.roughness = 0.92
		VoxelMaterial.SIDEWALK:
			mat.albedo_texture = _tex("sidewalk.jpg")
			mat.roughness = 0.9
		VoxelMaterial.CONCRETE:
			mat.albedo_texture = _tex("concrete.jpg")
			mat.roughness = 0.9
		VoxelMaterial.BRICK:
			mat.albedo_texture = _tex("brick.jpg")
			mat.roughness = 0.85
		VoxelMaterial.BRICK_DARK:
			mat.albedo_texture = _tex("brick_dark.jpg")
			mat.roughness = 0.85
		VoxelMaterial.GLASS:
			mat.albedo_texture = _tex("glass.jpg")
			mat.albedo_color = Color(0.75, 0.88, 1.0, 0.4)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.08
			mat.metallic = 0.2
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		VoxelMaterial.GLASS_LIT:
			mat.albedo_texture = _tex("glass.jpg")
			mat.albedo_color = Color(1.0, 0.9, 0.55, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.12
			mat.metallic = 0.15
			mat.emission_enabled = false
			mat.emission = Color(1.0, 0.82, 0.4)
			mat.emission_energy_multiplier = 0.05
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		VoxelMaterial.PLAZA:
			mat.albedo_texture = _tex("plaza.jpg")
			mat.roughness = 0.88
		VoxelMaterial.PARK:
			mat.albedo_texture = _tex("grass.jpg")
			mat.roughness = 0.95
		VoxelMaterial.ROOF:
			mat.albedo_texture = _tex("roof.jpg")
			mat.roughness = 0.75
		VoxelMaterial.ROOF_CLAY:
			mat.albedo_texture = _tex("roof_clay.jpg")
			mat.roughness = 0.78
		VoxelMaterial.PLANTER:
			mat.albedo_texture = _tex("wood.jpg")
			mat.roughness = 0.8
		VoxelMaterial.PLASTER:
			mat.albedo_texture = _tex("plaster.jpg")
			mat.roughness = 0.9
		VoxelMaterial.METAL:
			mat.albedo_texture = _tex("metal.jpg")
			mat.roughness = 0.35
			mat.metallic = 0.85
		VoxelMaterial.METAL_PLATE:
			mat.albedo_texture = _tex("metal_plate.jpg")
			mat.roughness = 0.45
			mat.metallic = 0.8
		VoxelMaterial.GRAVEL:
			mat.albedo_texture = _tex("gravel.jpg")
			mat.roughness = 0.95
		VoxelMaterial.DIRT:
			mat.albedo_texture = _tex("dirt.jpg")
			mat.roughness = 0.95
		VoxelMaterial.WATER:
			mat.albedo_texture = _tex("water.jpg")
			mat.albedo_color = Color(0.55, 0.75, 0.95, 0.62)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.08
			mat.metallic = 0.05
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		VoxelMaterial.CURB:
			mat.albedo_texture = _tex("curb.jpg")
			mat.roughness = 0.9
		VoxelMaterial.ROAD_LINE:
			mat.albedo_texture = _tex("road_line.jpg")
			mat.roughness = 0.85
		VoxelMaterial.CROSSWALK:
			mat.albedo_texture = _tex("crosswalk.jpg")
			mat.roughness = 0.85
		VoxelMaterial.TILES:
			mat.albedo_texture = _tex("tiles.jpg")
			mat.roughness = 0.7
		VoxelMaterial.BARK:
			mat.albedo_texture = _tex("bark.jpg")
			mat.roughness = 0.92
		VoxelMaterial.LEAVES:
			mat.albedo_texture = _tex("leaves.jpg")
			mat.roughness = 0.88
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		VoxelMaterial.STONE:
			mat.albedo_texture = _tex("stone.jpg")
			mat.roughness = 0.88
		VoxelMaterial.PAINT:
			mat.albedo_texture = _tex("paint.jpg")
			mat.roughness = 0.7
		_:
			mat.albedo_color = VoxelMaterial.color(id)

	if mat.albedo_texture == null and id != VoxelMaterial.GLASS and id != VoxelMaterial.GLASS_LIT and id != VoxelMaterial.WATER:
		mat.albedo_color = VoxelMaterial.color(id)
	_apply_normal_map(mat, id)
	return mat


static func _apply_normal_map(mat: StandardMaterial3D, id: int) -> void:
	var normal_file := ""
	match id:
		VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK:
			normal_file = "brick_normal.jpg"
		VoxelMaterial.ASPHALT, VoxelMaterial.ROAD:
			normal_file = "asphalt_normal.jpg"
		VoxelMaterial.CONCRETE:
			normal_file = "concrete_normal.jpg"
		VoxelMaterial.PLASTER:
			normal_file = "plaster_normal.jpg"
		VoxelMaterial.CURB, VoxelMaterial.SIDEWALK:
			normal_file = "sidewalk_normal.jpg"
		VoxelMaterial.STONE:
			normal_file = "stone_normal.jpg"
		_:
			return
	var ntex := _tex_optional(normal_file)
	if ntex == null:
		return
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.normal_scale = 0.85


static func _tex(file_name: String) -> Texture2D:
	var path := TEX_DIR + file_name
	if not ResourceLoader.exists(path):
		push_error("Missing city texture: %s" % path)
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Failed to load city texture: %s" % path)
	return tex


static func _tex_optional(file_name: String) -> Texture2D:
	var path := TEX_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
