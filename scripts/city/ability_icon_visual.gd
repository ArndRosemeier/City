## The little 3-D badge a power is drawn with, so a recipe row can show the thing it builds
## rather than only naming it.
##
## Same rule the gems follow in `InventoryItemVisual`: the silhouette carries the identity and
## colour only reinforces it, because a 34 px row is too small for two icons that differ by hue
## alone. Each badge is a single mesh assembled from primitives rather than a little scene, so
## one material, one draw call and one framing check cover every power.
class_name AbilityIconVisual
extends RefCounted

## Badges share the item framing, so a power and a crafted item read at the same size in a row.
const SIZE := InventoryItemVisual.PREVIEW_SIZE

const STEEL := Color(0.62, 0.70, 0.80)
const BEAM_RED := Color(0.95, 0.32, 0.30)
const CHARGE_AMBER := Color(0.98, 0.68, 0.24)
const SLAM_GREY := Color(0.55, 0.57, 0.62)
const WARD_BLUE := InventoryItemVisual.SHIELD_AURA_COLOR
const GROW_GREEN := Color(0.44, 0.90, 0.48)
const SHRINK_VIOLET := Color(0.72, 0.48, 0.96)
const MINION_EMERALD := Color(0.30, 0.86, 0.62)
const PORTAL_CYAN := Color(0.36, 0.88, 0.96)
const CABINET_YELLOW := Color(0.96, 0.84, 0.30)
const TRAP_ICE := Color(0.74, 0.90, 1.0)
const TONIC_SPEED := InventoryItemVisual.TONIC_SPEED_COLOR
const TONIC_REGEN := InventoryItemVisual.TONIC_REGEN_COLOR
const HARD_PLATE := Color(0.80, 0.84, 0.90)
const HARD_EXOTIC := Color(0.66, 0.42, 0.92)


## Null for anything with no badge — builds, and any power added without one. The caller decides
## whether that is a missing icon or simply a row that shows no picture.
static func make_mesh(ability_id: String) -> MeshInstance3D:
	var shape := _shape_for(ability_id)
	if shape == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = shape
	mi.material_override = _material_for(ability_id)
	## Slight yaw / pitch, as on the stones, so a badge reads as an object rather than a decal.
	mi.rotation_degrees = Vector3(-14.0, 26.0, 0.0)
	return mi


static func has_icon(ability_id: String) -> bool:
	return _shape_for(ability_id) != null


static func _shape_for(ability_id: String) -> Mesh:
	match ability_id:
		AbilityRegistry.ID_BLASTER:
			## Stubby barrel over a grip: the plainest gun shape there is, for the plainest gun.
			## Laid across the view, not down it — a barrel aimed at the camera is a dot.
			return _combine([
				_rod(0.095, 0.40, Vector3(0.0, 0.06, 0.0), _lie_along_x()),
				_box(Vector3(0.12, 0.21, 0.14), Vector3(-0.10, -0.15, 0.0)),
			])
		AbilityRegistry.ID_LASER:
			## A beam is a line: a thin lance with the emitter bead at the muzzle.
			return _combine([
				_rod(0.065, 0.42, Vector3.ZERO, _lie_along_x()),
				_ball(0.125, Vector3(0.21, 0.0, 0.0)),
			])
		AbilityRegistry.ID_CHARGED_BLAST:
			## A held charge: a core with a containment ring round its equator.
			return _combine([
				_ball(0.19, Vector3.ZERO),
				_ring(0.26, 0.34, Vector3.ZERO, Basis.IDENTITY),
			])
		AbilityRegistry.ID_STOMP:
			## Anvil on a plate — weight coming down, seen from the side.
			return _combine([
				_box(Vector3(0.46, 0.13, 0.46), Vector3(0.0, -0.20, 0.0)),
				_box(Vector3(0.30, 0.28, 0.30), Vector3(0.0, 0.01, 0.0)),
			])
		AbilityRegistry.ID_SHIELD:
			## Dome on a rim. Nothing else in the set is a half-ball.
			return _combine([
				_dome(0.30, Vector3(0.0, -0.12, 0.0)),
				_ring(0.30, 0.36, Vector3(0.0, -0.12, 0.0), Basis.IDENTITY),
			])
		AbilityRegistry.ID_GROW:
			## Block with an arrow driving up out of it.
			return _combine([
				_box(Vector3(0.30, 0.26, 0.30), Vector3(0.0, -0.16, 0.0)),
				_spike(0.17, 0.30, Vector3(0.0, 0.16, 0.0), Basis.IDENTITY),
			])
		AbilityRegistry.ID_SHRINK:
			## The same pair mirrored: the arrow presses down onto the block.
			return _combine([
				_box(Vector3(0.30, 0.26, 0.30), Vector3(0.0, 0.16, 0.0)),
				_spike(0.17, 0.30, Vector3(0.0, -0.16, 0.0), Basis(Vector3.FORWARD, PI)),
			])
		AbilityRegistry.ID_MINION:
			## A small figure: head, body, feet. Reads as "someone else" at a glance.
			return _combine([
				_ball(0.13, Vector3(0.0, 0.20, 0.0)),
				_box(Vector3(0.24, 0.26, 0.16), Vector3(0.0, -0.02, 0.0)),
				_box(Vector3(0.26, 0.08, 0.18), Vector3(0.0, -0.19, 0.0)),
			])
		AbilityRegistry.ID_DISTRICT_HOP:
			## An upright gate with something already through it.
			return _combine([
				_ring(0.24, 0.33, Vector3.ZERO, Basis(Vector3.RIGHT, PI * 0.5)),
				_ball(0.10, Vector3.ZERO),
			])
		AbilityRegistry.ID_TETRIS:
			## The J piece, four cells of it, unmistakable to anyone who would want the cabinet.
			return _combine([
				_box(Vector3.ONE * 0.17, Vector3(-0.085, 0.17, 0.0)),
				_box(Vector3.ONE * 0.17, Vector3(-0.085, 0.0, 0.0)),
				_box(Vector3.ONE * 0.17, Vector3(-0.085, -0.17, 0.0)),
				_box(Vector3.ONE * 0.17, Vector3(0.085, -0.17, 0.0)),
			])
		AbilityRegistry.ID_USE_TRAP:
			## The trap block inside the ring it snaps shut with — a cube where the charge has
			## a ball, so the two ringed badges never read the same.
			return _combine([
				_box(Vector3.ONE * 0.24, Vector3.ZERO),
				_ring(0.27, 0.34, Vector3.ZERO, Basis.IDENTITY),
			])
		AbilityRegistry.ID_USE_BOOST_SPEED:
			return _tonic_badge(0.115, 0.44)
		AbilityRegistry.ID_USE_BOOST_REGEN:
			return _tonic_badge(0.160, 0.36)
		AbilityRegistry.ID_HARDNESS_REINFORCED:
			## Plates stacked: what the tier lets the tools cut through.
			return _combine([
				_box(Vector3(0.46, 0.17, 0.46), Vector3(0.0, -0.13, 0.0)),
				_box(Vector3(0.34, 0.17, 0.34), Vector3(0.0, 0.08, 0.0)),
			])
		AbilityRegistry.ID_HARDNESS_EXOTIC:
			## One plate more, and a point on top: the tier above the tier above.
			return _combine([
				_box(Vector3(0.42, 0.10, 0.42), Vector3(0.0, -0.22, 0.0)),
				_box(Vector3(0.35, 0.10, 0.35), Vector3(0.0, -0.10, 0.0)),
				_box(Vector3(0.28, 0.10, 0.28), Vector3(0.0, 0.02, 0.0)),
				_spike(0.15, 0.20, Vector3(0.0, 0.17, 0.0), Basis.IDENTITY),
			])
	## Discovery stamps share one plaque badge — the name carries which build it is.
	if BuildCatalog.has_id(ability_id):
		return _combine([
			_box(Vector3(0.42, 0.08, 0.42), Vector3(0.0, -0.18, 0.0)),
			_box(Vector3(0.28, 0.28, 0.28), Vector3(0.0, 0.05, 0.0)),
		])
	return null


## Bottle badge for the drinkables, shaped like the tonic in the slot so the row and the item
## agree; the two differ in build the same way their bottles do.
static func _tonic_badge(radius: float, height: float) -> ArrayMesh:
	return _combine([
		_capsule(radius, height, Vector3(0.0, -0.05, 0.0)),
		_rod(radius * 0.45, 0.12, Vector3(0.0, height * 0.5 - 0.03, 0.0), Basis.IDENTITY),
	])


static func _material_for(ability_id: String) -> StandardMaterial3D:
	var colour := _colour_for(ability_id)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = 0.2
	mat.roughness = 0.34
	mat.emission_enabled = true
	mat.emission = colour
	## Just enough glow to keep a badge legible on the dark panel without blowing out its facets.
	mat.emission_energy_multiplier = 0.35
	return mat


static func _colour_for(ability_id: String) -> Color:
	match ability_id:
		AbilityRegistry.ID_BLASTER:
			return STEEL
		AbilityRegistry.ID_LASER:
			return BEAM_RED
		AbilityRegistry.ID_CHARGED_BLAST:
			return CHARGE_AMBER
		AbilityRegistry.ID_STOMP:
			return SLAM_GREY
		AbilityRegistry.ID_SHIELD:
			return WARD_BLUE
		AbilityRegistry.ID_GROW:
			return GROW_GREEN
		AbilityRegistry.ID_SHRINK:
			return SHRINK_VIOLET
		AbilityRegistry.ID_MINION:
			return MINION_EMERALD
		AbilityRegistry.ID_DISTRICT_HOP:
			return PORTAL_CYAN
		AbilityRegistry.ID_TETRIS:
			return CABINET_YELLOW
		AbilityRegistry.ID_USE_TRAP:
			return TRAP_ICE
		AbilityRegistry.ID_USE_BOOST_SPEED:
			return TONIC_SPEED
		AbilityRegistry.ID_USE_BOOST_REGEN:
			return TONIC_REGEN
		AbilityRegistry.ID_HARDNESS_REINFORCED:
			return HARD_PLATE
		AbilityRegistry.ID_HARDNESS_EXOTIC:
			return HARD_EXOTIC
	if BuildCatalog.has_id(ability_id):
		return STEEL
	push_error("AbilityIconVisual: '%s' has a badge but no colour" % ability_id)
	return Color.MAGENTA


# ── assembly ───────────────────────────────────────────────────────────────────────────────

## Bake the parts down to one surface. `append_from` carries each primitive's own winding and
## normals over, which is why the badges are built out of engine primitives rather than by hand.
static func _combine(parts: Array[Dictionary]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in parts:
		st.append_from(part["mesh"] as Mesh, 0, part["at"] as Transform3D)
	return st.commit()


static func _part(mesh: Mesh, at: Vector3, basis: Basis) -> Dictionary:
	return {"mesh": mesh, "at": Transform3D(basis, at)}


static func _box(size: Vector3, at: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	var m := BoxMesh.new()
	m.size = size
	return _part(m, at, basis)


static func _ball(radius: float, at: Vector3) -> Dictionary:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 14
	m.rings = 7
	return _part(m, at, Basis.IDENTITY)


static func _dome(radius: float, at: Vector3) -> Dictionary:
	var m := SphereMesh.new()
	m.radius = radius
	## A hemisphere wants its own height, not a full sphere's: leaving it at 2×radius stretches
	## the dome to twice the height it should stand, and out of the frame the camera covers.
	m.height = radius
	m.is_hemisphere = true
	m.radial_segments = 16
	m.rings = 7
	return _part(m, at, Basis.IDENTITY)


static func _rod(radius: float, height: float, at: Vector3, basis: Basis) -> Dictionary:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 0
	return _part(m, at, basis)


## Cone, point up unless the basis turns it.
static func _spike(radius: float, height: float, at: Vector3, basis: Basis) -> Dictionary:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 0
	return _part(m, at, basis)


static func _capsule(radius: float, height: float, at: Vector3) -> Dictionary:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return _part(m, at, Basis.IDENTITY)


static func _ring(inner: float, outer: float, at: Vector3, basis: Basis) -> Dictionary:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 8
	return _part(m, at, basis)


## Cylinders stand along Y; a barrel has to lie across the view instead.
static func _lie_along_x() -> Basis:
	return Basis(Vector3.FORWARD, PI * 0.5)
