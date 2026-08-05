## Builds the small tilted solid used as an inventory icon (gem, trap or tonic).
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

## Tonic glass. The two are told apart the same way the stones are — by build first, tint
## second — so a slot never depends on the player remembering which colour did what.
## Speed is orange so it does not steal the cyan shell the shield ward uses in the world.
const TONIC_SPEED_COLOR := Color(0.98, 0.55, 0.16)
const TONIC_REGEN_COLOR := Color(0.46, 0.94, 0.55)
## Soft ward blue — also the world aura while the shield power is up.
const SHIELD_AURA_COLOR := Color(0.36, 0.86, 1.0)
## Sides on a lathed bottle. Enough to read as blown glass at 64 px, few enough to stay cheap.
const TONIC_SIDES := 12

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
	if def.is_boost:
		return _flask_for(def.id)
	if def.is_cloudstone:
		return _bead(PREVIEW_SIZE * 0.48)
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


## A drinkable is a bottle, never a stone: the icon has to say "consumable" before it says which
## one. Profiles are `(radius, height)` as fractions of PREVIEW_SIZE, bottom-to-top, revolved
## around Y — a slim vial for speed, a round-bellied flask for regen.
static func _flask_for(item_id: String) -> Mesh:
	match item_id:
		InventoryCatalog.ID_BOOST_SPEED:
			return _lathe([
				Vector2(0.00, -0.50),
				Vector2(0.17, -0.50),
				Vector2(0.18, -0.20),
				Vector2(0.13, 0.02),
				Vector2(0.10, 0.34),
				Vector2(0.14, 0.43),
				Vector2(0.00, 0.50),
			])
		InventoryCatalog.ID_BOOST_REGEN:
			return _lathe([
				Vector2(0.00, -0.50),
				Vector2(0.22, -0.48),
				Vector2(0.30, -0.26),
				Vector2(0.28, -0.02),
				Vector2(0.13, 0.14),
				Vector2(0.11, 0.38),
				Vector2(0.16, 0.45),
				Vector2(0.00, 0.50),
			])
	push_error("InventoryItemVisual: tonic '%s' has no bottle profile" % item_id)
	return null


## Revolve a profile around Y. Smooth-shaded, unlike the stones: facets are what makes a cut
## stone read as cut, and the same facets would make blown glass read as another mineral.
static func _lathe(profile: Array[Vector2]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in TONIC_SIDES:
		var a0 := TAU * float(i) / float(TONIC_SIDES)
		var a1 := TAU * float(i + 1) / float(TONIC_SIDES)
		for k in range(profile.size() - 1):
			var lo := profile[k]
			var hi := profile[k + 1]
			var lo0 := _lathe_point(lo, a0)
			var lo1 := _lathe_point(lo, a1)
			var hi0 := _lathe_point(hi, a0)
			var hi1 := _lathe_point(hi, a1)
			## Front faces wind clockwise seen from outside, as on the cut stones above. A ring
			## of radius zero is a pole, where one of the two triangles collapses to a line.
			if lo.x > 0.0:
				st.add_vertex(hi0)
				st.add_vertex(lo0)
				st.add_vertex(lo1)
			if hi.x > 0.0:
				st.add_vertex(hi0)
				st.add_vertex(lo1)
				st.add_vertex(hi1)
	st.generate_normals()
	return st.commit()


static func _lathe_point(rim: Vector2, angle: float) -> Vector3:
	return Vector3(
		cos(angle) * rim.x * PREVIEW_SIZE,
		rim.y * PREVIEW_SIZE,
		sin(angle) * rim.x * PREVIEW_SIZE
	)


## Lit glass with a little inner glow, so a tonic stays legible on the dark slot without the
## cave-ore shader the stones share.
static func tonic_material(item_id: String) -> StandardMaterial3D:
	var colour := _tonic_colour(item_id)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = 0.15
	mat.roughness = 0.16
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 0.45
	return mat


static func _tonic_colour(item_id: String) -> Color:
	match item_id:
		InventoryCatalog.ID_BOOST_SPEED:
			return TONIC_SPEED_COLOR
		InventoryCatalog.ID_BOOST_REGEN:
			return TONIC_REGEN_COLOR
	push_error("InventoryItemVisual: tonic '%s' has no colour" % item_id)
	return Color.MAGENTA


static func _material_for(def: InventoryCatalog.ItemDef) -> Material:
	if def.is_trap:
		return trap_material()
	if def.is_boost:
		return tonic_material(def.id)
	if def.is_cloudstone:
		return cloudstone_material()
	if def.gem_mat_id >= 0:
		return gem_icon_material(def.gem_mat_id)
	push_error("InventoryItemVisual: item '%s' has no material mapping" % def.id)
	return StandardMaterial3D.new()


static func cloudstone_material() -> ShaderMaterial:
	var mat := VoxelBlockLibrary.surface_material(VoxelMaterial.CLOUDSTONE, true).duplicate() as ShaderMaterial
	mat.set_shader_parameter("emission_strength", 0.55)
	mat.set_shader_parameter("puff_speed", 0.4)
	return mat


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
