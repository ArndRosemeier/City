## Texture setup inspection.
##
## Renders every opaque voxel material as a real-scale panel lineup at close range and
## again as a long grazing-angle ground run, so "crude" can be judged from pixels rather
## than asserted. Also prints, per texture, whether the imported resource really has
## mipmaps and really is block compressed: the shaders all ask for
## filter_linear_mipmap_anisotropic, which silently degrades to plain linear when the
## .import has mipmaps/generate=false, and Godot serves a stale cached product outside
## the editor, so neither can be trusted from the .import file alone.
extends Node

const LINEUP_A_PNG := "res://tools/texaudit_lineup_a.png"
const LINEUP_B_PNG := "res://tools/texaudit_lineup_b.png"
const GRAZE_PNG := "res://tools/texaudit_graze.png"
const SCALE_PNG := "res://tools/texaudit_scale.png"
const LAWN_PNG := "res://tools/texaudit_lawn.png"
const DECK := 3.5

## Materials whose art has an authored feature pitch — standing seam, pantile, curtain
## panel, riveted plate, floor tile — drawn beside a 0.5 m voxel cube. If a tile_meters
## drifts away from the pitch the generator authored, the features shrink against the
## cube, which is the failure this view exists to make obvious.
const SCALE_IDS: Array[int] = [
	VoxelMaterial.ROOF,
	VoxelMaterial.ROOF_CLAY,
	VoxelMaterial.METAL,
	VoxelMaterial.METAL_PLATE,
	VoxelMaterial.TILES,
]

## Facade / wall materials, drawn as upright 2 x 3 m panels.
const WALL_IDS: Array[int] = [
	VoxelMaterial.BRICK_DARK,
	VoxelMaterial.BRICK,
	VoxelMaterial.STONE,
	VoxelMaterial.PLASTER,
	VoxelMaterial.CONCRETE,
	VoxelMaterial.METAL,
	VoxelMaterial.METAL_PLATE,
	VoxelMaterial.PAINT,
	VoxelMaterial.ROOF,
	VoxelMaterial.ROOF_CLAY,
	VoxelMaterial.CASTLE_BLOCK,
	VoxelMaterial.CAVE_WALL,
]

## Ground materials, drawn as flat 2 x 2 m pads seen from above the horizon. The whole
## graveyard kit is here in one row: four of its materials used to render as the same
## black slab, which is only visible when they are side by side.
const GROUND_IDS: Array[int] = [
	VoxelMaterial.ASPHALT,
	VoxelMaterial.SIDEWALK,
	VoxelMaterial.CURB,
	VoxelMaterial.PLAZA,
	VoxelMaterial.TILES,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.PARK,
	VoxelMaterial.GRAVE_PATH,
	VoxelMaterial.GRAVE_SOIL,
	VoxelMaterial.GRAVE_STONE,
	VoxelMaterial.GRAVE_MARBLE,
	VoxelMaterial.WROUGHT_IRON,
	VoxelMaterial.DIRT,
	VoxelMaterial.BEDROCK,
]

var _holder: Node3D = null


func _ready() -> void:
	_report_mipmaps()
	_holder = Node3D.new()
	_holder.name = "TexAudit"
	add_child(_holder)
	_build_environment()

	await _lineup(WALL_IDS, true, LINEUP_A_PNG)
	await _lineup(GROUND_IDS, false, LINEUP_B_PNG)
	await _scale_row()
	await _lawn()
	await _grazing_run()

	print("RESULT: OK")
	get_tree().quit(0)


## Every texture the surface specs reference, with its real mipmap state, GPU format
## and VRAM cost. All three are import settings that no test can assert from the
## .import file alone, because Godot serves a stale cached product outside the editor.
func _report_mipmaps() -> void:
	var seen: Dictionary = {}
	var without: Array[String] = []
	var uncompressed: Array[String] = []
	var bytes := 0
	for id in range(1, VoxelMaterial.COUNT):
		if VoxelSurfaceSpec.has_bespoke_shader(id):
			continue
		var spec := VoxelSurfaceSpec.for_id(id)
		for file in [spec.albedo_file, spec.normal_file]:
			var name := String(file)
			if name == "" or seen.has(name):
				continue
			seen[name] = true
			var tex := load(VoxelBlockLibrary.TEX_DIR + name) as Texture2D
			if tex == null:
				push_error("audit: cannot load %s" % name)
				continue
			var img := tex.get_image()
			if img == null:
				push_error("audit: no image for %s" % name)
				continue
			var has_mips := img.has_mipmaps()
			var size := img.get_data().size()
			bytes += size
			print(
				"MIPS %s %-24s %dx%d %-14s %.2f MB"
				% [
					"yes" if has_mips else "NO ", name, img.get_width(), img.get_height(),
					_format_name(img.get_format()), float(size) / 1048576.0,
				]
			)
			if not has_mips:
				without.append(name)
			if not _is_block_compressed(img.get_format()):
				uncompressed.append(name)
	print(
		"MIPS SUMMARY: %d of %d textures have no mipmaps: %s"
		% [without.size(), seen.size(), ", ".join(without)]
	)
	print(
		"VRAM SUMMARY: %.1f MB over %d textures, %d not block compressed: %s"
		% [float(bytes) / 1048576.0, seen.size(), uncompressed.size(), ", ".join(uncompressed)]
	)


func _format_name(format: int) -> String:
	match format:
		Image.FORMAT_RGB8:
			return "RGB8"
		Image.FORMAT_RGBA8:
			return "RGBA8"
		Image.FORMAT_DXT1:
			return "DXT1/BC1"
		Image.FORMAT_DXT5:
			return "DXT5/BC3"
		Image.FORMAT_RGTC_RG:
			return "RGTC/BC5"
		Image.FORMAT_BPTC_RGBA:
			return "BPTC/BC7"
		_:
			return "format %d" % format


func _is_block_compressed(format: int) -> bool:
	return format >= Image.FORMAT_DXT1 and format < Image.FORMAT_MAX


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.75)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_holder.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0.0)
	sun.light_energy = 1.5
	_holder.add_child(sun)


## Each pitch-authored material as a 2.4 x 3.0 m panel with a 0.5 m voxel in front of it,
## so the authored feature can be measured against the grid it has to sit on.
func _scale_row() -> void:
	var made: Array[MeshInstance3D] = []
	var voxel := VoxelBlockLibrary.VOXEL_WORLD_SIZE
	for i in range(SCALE_IDS.size()):
		var id := SCALE_IDS[i]
		var x := (float(i) - 2.0) * 2.6
		made.append(_panel(Vector3(2.4, 3.0, 0.5), Vector3(x, DECK + 0.5, 0.0), id))
		made.append(
			_panel(
				Vector3(voxel, voxel, voxel),
				Vector3(x - 1.2 + voxel * 0.5, DECK - 1.25, 0.8),
				VoxelMaterial.PLASTER
			)
		)
		var spec := VoxelSurfaceSpec.for_id(id)
		print("SCALE %d (%s): one repeat over %s m" % [id, spec.albedo_file, spec.tile_meters])
	await _shoot(Vector3(0.0, DECK + 0.5, 9.0), Vector3.ZERO, 60.0, SCALE_PNG)
	for mi in made:
		mi.queue_free()
	await get_tree().process_frame


func _panel(size: Vector3, pos: Vector3, id: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = VoxelBlockLibrary.surface_material(id, false)
	mi.position = pos
	_holder.add_child(mi)
	return mi


## Two rows, however wide that makes them. Upright walls face the camera; ground pads are
## laid flat and tilted up 72 degrees so a floor material is still judged head-on.
func _lineup(ids: Array[int], upright: bool, path: String) -> void:
	var made: Array[MeshInstance3D] = []
	var cols := (ids.size() + 1) / 2
	for i in range(ids.size()):
		var col := i % cols
		var row := i / cols
		var x := (float(col) - (float(cols) - 1.0) * 0.5) * 2.2
		var y := DECK + 2.0 - float(row) * 3.2
		var mi: MeshInstance3D
		if upright:
			mi = _panel(Vector3(2.0, 3.0, 0.5), Vector3(x, y, 0.0), ids[i])
		else:
			mi = _panel(Vector3(2.0, 0.5, 3.0), Vector3(x, y, 0.0), ids[i])
			mi.rotation = Vector3(deg_to_rad(-72.0), 0.0, 0.0)
		made.append(mi)
	## Stand back in proportion to the row so a wider lineup does not crop.
	await _shoot(Vector3(0.0, DECK + 0.4, 7.6 * float(cols) / 6.0), Vector3.ZERO, 55.0, path)
	for mi in made:
		mi.queue_free()
	await get_tree().process_frame


## Grass on its own, 80 m of it at eye level. It is the largest surface in the game and a
## 2 m test pad cannot show whether the patch variation survives minification — which is
## the whole question, since the photoscan's own blade detail does not.
func _lawn() -> void:
	var pad := _panel(
		Vector3(80.0, 0.5, 80.0), Vector3(0.0, DECK - 0.25, -30.0), VoxelMaterial.PARK
	)
	await _shoot(Vector3(0.0, DECK + 1.7, 8.0), Vector3(deg_to_rad(-8.0), 0.0, 0.0), 70.0, LAWN_PNG)
	pad.queue_free()
	await get_tree().process_frame


## A 120 m ground run per material, viewed near-horizontal. This is where missing
## mipmaps and missing anisotropy show up as shimmer and mush.
func _grazing_run() -> void:
	var ids: Array[int] = [
		VoxelMaterial.ASPHALT,
		VoxelMaterial.SIDEWALK,
		VoxelMaterial.CURB,
		VoxelMaterial.GRAVE_PATH,
		VoxelMaterial.TILES,
		VoxelMaterial.PLAZA,
	]
	for i in range(ids.size()):
		_panel(Vector3(4.0, 0.5, 120.0), Vector3((float(i) - 2.5) * 4.2, DECK - 0.25, -55.0), ids[i])
	await _shoot(Vector3(0.0, DECK + 1.4, 6.0), Vector3(deg_to_rad(-3.0), 0.0, 0.0), 60.0, GRAZE_PNG)


func _shoot(pos: Vector3, rot: Vector3, fov: float, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = pos
	cam.rotation = rot
	cam.fov = fov
	cam.far = 4000.0
	_holder.add_child(cam)
	cam.make_current()
	for _i in range(40):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("audit: no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
