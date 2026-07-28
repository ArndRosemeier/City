## Builds the small tilted solid used as an inventory icon (gem or trap).
##
## Every gem used to be the same cube, so quartz and diamond — two near-white stones in a
## palette that is shared with the ore in the hills — were the same 64 px blob. The palette
## belongs to the world, so the stones are told apart here instead: each gem type gets its own
## cut, and the cave glow is turned down for the preview so the cut is visible at all rather
## than clipped to white.
class_name InventoryItemVisual
extends RefCounted

const PREVIEW_SIZE := 0.55
## Gem emission is tuned for ore glowing in an unlit cave. A slot is a lit 64 px square with no
## glow pass, where that much emission clips every stone to the same white.
const ICON_EMISSION_SCALE := 0.22
## World sparkle is sized for metre-wide ore bodies; over a half-metre icon it is one flat
## blotch, which costs the cut its facets.
const ICON_SPARKLE_SCALE := 14.0

static var _icon_mat_cache: Dictionary = {}  ## VoxelMaterial.GEM_* → ShaderMaterial


## Radius of the sphere that holds the icon at any yaw, so a preview camera can frame it
## without knowing its cut or how it is turned. Every cut below fits the PREVIEW_SIZE cube.
static func bounding_radius() -> float:
	return PREVIEW_SIZE * sqrt(3.0) * 0.5


static func make_mesh(item_id: String) -> MeshInstance3D:
	var def := InventoryCatalog.item(item_id)
	if def == null:
		push_error("InventoryItemVisual: unknown item '%s'" % item_id)
		return null
	var shape := _shape_for(def)
	if shape == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = shape
	mi.material_override = _material_for(def)
	## Slight yaw / pitch so a stone reads as an item, not a flat UI tile.
	mi.rotation_degrees = Vector3(-18.0, 32.0, 8.0)
	return mi


## One cut per gem type. Colour alone cannot separate quartz from diamond or amber from topaz,
## so the silhouette carries the identity: a blunt six-sided shaft, a resin bead, a sharp
## square spindle, a cube, a tall step-cut block and a brilliant.
static func _shape_for(def: InventoryCatalog.ItemDef) -> Mesh:
	if def.is_trap:
		return _block(Vector3.ONE * PREVIEW_SIZE)
	match def.gem_mat_id:
		VoxelMaterial.GEM_QUARTZ:
			return _column(6, 0.21, PREVIEW_SIZE)
		VoxelMaterial.GEM_AMBER:
			return _bead(PREVIEW_SIZE * 0.5)
		VoxelMaterial.GEM_TOPAZ:
			return _bipyramid(4, 0.27, 0.56)
		VoxelMaterial.GEM_SAPPHIRE:
			return _block(Vector3.ONE * 0.5)
		VoxelMaterial.GEM_EMERALD:
			return _block(Vector3(0.34, PREVIEW_SIZE, 0.34))
		VoxelMaterial.GEM_DIAMOND:
			return _bipyramid(8, 0.30, 0.52)
	push_error("InventoryItemVisual: item '%s' has no icon shape" % def.id)
	return null


static func _block(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _bead(radius: float) -> SphereMesh:
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 14
	ball.rings = 7
	return ball


static func _column(sides: int, radius: float, height: float) -> CylinderMesh:
	var col := CylinderMesh.new()
	col.top_radius = radius
	col.bottom_radius = radius
	col.height = height
	col.radial_segments = sides
	col.rings = 0
	return col


## Two pyramids joined at a girdle: the classic cut-stone silhouette, symmetric about the
## girdle so the drawn mass stays centred in the slot.
static func _bipyramid(sides: int, radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## A cut stone reads by its facets; smoothed normals would erase them.
	st.set_smooth_group(-1)
	var top := Vector3(0.0, height * 0.5, 0.0)
	var bottom := Vector3(0.0, -height * 0.5, 0.0)
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	for i in sides:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % sides]
		## Front faces wind clockwise seen from outside, so the crown and the pavilion run
		## opposite ways around the girdle.
		st.add_vertex(top)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(bottom)
		st.add_vertex(p1)
		st.add_vertex(p0)
	st.generate_normals()
	return st.commit()


static func _material_for(def: InventoryCatalog.ItemDef) -> Material:
	if def.is_trap:
		return trap_material()
	if def.gem_mat_id >= 0:
		return gem_icon_material(def.gem_mat_id)
	push_error("InventoryItemVisual: item '%s' has no material mapping" % def.id)
	return StandardMaterial3D.new()


## The world gem look with its cave glow turned down. VoxelBlockLibrary hands out one shared
## cached material per gem id and the ore in the hills is drawn with it, so this copies rather
## than edits: the icon must not be able to change how a gem seam looks underground.
static func gem_icon_material(gem_mat_id: int) -> ShaderMaterial:
	var cached: Variant = _icon_mat_cache.get(gem_mat_id)
	if cached is ShaderMaterial:
		return cached
	var world := VoxelBlockLibrary.gem_material(gem_mat_id)
	var mat := world.duplicate() as ShaderMaterial
	var em_base := float(world.get_shader_parameter("emission_base"))
	var em_peak := float(world.get_shader_parameter("emission_peak"))
	mat.set_shader_parameter("emission_base", em_base * ICON_EMISSION_SCALE)
	mat.set_shader_parameter("emission_peak", em_peak * ICON_EMISSION_SCALE)
	mat.set_shader_parameter("sparkle_scale", ICON_SPARKLE_SCALE)
	_icon_mat_cache[gem_mat_id] = mat
	return mat


## Shared trap look — quartz palette with the inward-pulse shader.
static func trap_material() -> ShaderMaterial:
	var shader: Shader = load("res://assets/city/shaders/voxel_trap.gdshader") as Shader
	if shader == null:
		push_error("InventoryItemVisual: missing voxel_trap.gdshader")
		return ShaderMaterial.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var albedo := VoxelMaterial.color(VoxelMaterial.GEM_QUARTZ)
	mat.set_shader_parameter("base_color", albedo)
	mat.set_shader_parameter("emission_color", Color(0.7, 0.88, 1.0))
	mat.set_shader_parameter("emission_base", 1.4)
	mat.set_shader_parameter("emission_peak", 5.2)
	mat.set_shader_parameter("pulse_hz", 1.4)
	mat.set_shader_parameter("sparkle_scale", 4.5)
	mat.set_shader_parameter("metallic_base", 0.22)
	mat.set_shader_parameter("roughness_base", 0.18)
	return mat


## World / preview mesh that also scales inward so the suck reads in silhouette.
static func make_trap_node() -> MeshInstance3D:
	var mi := make_mesh(InventoryCatalog.ID_TRAP)
	if mi == null:
		return null
	mi.set_meta("trap_pulse", true)
	return mi


static func tick_trap_pulse(mi: MeshInstance3D, time_sec: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	if not bool(mi.get_meta("trap_pulse", false)):
		return
	var wave := 0.5 + 0.5 * sin(time_sec * TAU * 1.4)
	## Shrink toward the center on the bright beat.
	var s := lerpf(1.0, 0.72, wave)
	mi.scale = Vector3.ONE * s
