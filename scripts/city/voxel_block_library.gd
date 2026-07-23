## Builds a VoxelBlockyLibrary with city albedo textures.
class_name VoxelBlockLibrary
extends RefCounted

const TEX_DIR := "res://assets/city/textures/"


static func build() -> VoxelBlockyLibrary:
	var lib := VoxelBlockyLibrary.new()
	var models: Array[VoxelBlockyModel] = []
	models.append(VoxelBlockyModelEmpty.new())
	for id in range(1, VoxelMaterial.COUNT):
		models.append(_make_cube(id))
	lib.models = models
	lib.bake()
	return lib


static func _make_cube(id: int) -> VoxelBlockyModelCube:
	var cube := VoxelBlockyModelCube.new()
	cube.color = Color(1, 1, 1, 1)
	var mat := _material_for(id)
	cube.set_material_override(0, mat)
	if id == VoxelMaterial.GLASS or id == VoxelMaterial.WATER:
		cube.transparency_index = 1
	return cube


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
			mat.albedo_color = Color(0.7, 0.85, 1.0, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.12
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
			mat.roughness = 0.9
		VoxelMaterial.STONE:
			mat.albedo_texture = _tex("stone.jpg")
			mat.roughness = 0.88
		VoxelMaterial.PAINT:
			mat.albedo_texture = _tex("paint.jpg")
			mat.roughness = 0.75
		_:
			mat.albedo_color = VoxelMaterial.color(id)

	if mat.albedo_texture == null and id != VoxelMaterial.GLASS and id != VoxelMaterial.WATER:
		mat.albedo_color = VoxelMaterial.color(id)
	return mat


static func _tex(file_name: String) -> Texture2D:
	var path := TEX_DIR + file_name
	if not ResourceLoader.exists(path):
		push_error("Missing city texture: %s" % path)
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Failed to load city texture: %s" % path)
	return tex
