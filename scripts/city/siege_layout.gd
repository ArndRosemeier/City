## Planned geometry for a Siege-theme district (district-local voxel coords).
##
## Survives the composer so the runtime controller can find the five stones, the foundation pads,
## the hell gates and the barricade breaches. Unlike every other themed layout this describes an
## *overlay* rather than a landmark: the quarter is a rectangle of ordinary street grid that the
## barricade pass sealed off, so roads, lots and sidewalks underneath it are the normal urban
## output — and the outer stones and hell gates stand out in that ordinary city, well beyond it.
class_name SiegeLayout
extends RefCounted

## What a foundation pad stands on. This is a placement rule and an access story at once — the
## higher a pad sits the better it sees, and the harder it is to get onto.
enum PadKind {
	## Street, sidewalk or plaza level. Walk on.
	STREET,
	## A roof inside the player's jump reach.
	ROOF_JUMP,
	## A roof out of jump reach; a cloudstone is how you get up. Best sightlines in the quarter.
	ROOF_HIGH,
}

## One of the five objectives: the centre Lodestone or an outer stone. Position plus a pool plus a
## radius — a stone is never a combat entity, which is why the controller can own five of them for
## the price of the contact-damage tick it already ran for one.
class Stone:
	extends RefCounted

	## Centre column in district-local XZ, base sitting on `base_y`.
	var xz: Vector2i = Vector2i(-1, -1)
	var base_y: int = 0
	var radius_vox: int = 0
	var height_vox: int = 0

	func world(district_origin: Vector3i) -> Vector3i:
		return Vector3i(xz.x, base_y, xz.y) + district_origin


## A portal the horde walks out of. Indestructible, and the mouth blocks line of sight, so this is
## also the one place on the tile the player cannot shoot into.
class HellGate:
	extends RefCounted

	## Mouth centre column in district-local voxels: the cell a body is dropped above.
	var mouth: Vector3i = Vector3i.ZERO
	## Which way the gate faces, pointing away from the tile centre. Bodies step out along its
	## negation, and the frame is built behind the mouth along it.
	var outward: Vector2i = Vector2i(0, 1)
	## Bearing of the gate from the tile centre in radians, for the per-wave weight table.
	var bearing_rad: float = 0.0

	func world(district_origin: Vector3i) -> Vector3i:
		return mouth + district_origin


## Besieged ground in planner cells, and the same rect in district-local voxels.
var quarter_cells: Rect2i = Rect2i()
var quarter_vox: Rect2i = Rect2i()
## Top solid Y of the walk surface the quarter was measured against.
var deck_y: int = 0

## Lodestone footprint: centre column in district-local XZ, base sitting on `lodestone_base_y`.
var lodestone_xz: Vector2i = Vector2i(-1, -1)
var lodestone_base_y: int = 0
var lodestone_radius_vox: int = 0
var lodestone_height_vox: int = 0

## The four stones that shield the centre, out toward the tile corners.
var outer_stones: Array[Stone] = []

## Spawn portals, out beyond the outer stones.
var hell_gates: Array[HellGate] = []

## Gaps in the barricade ring: centre column (x, surface Y, z). These are *not* spawn points — the
## horde comes out of hell gates and walks in through these, which is why the two are named apart.
var breaches: Array[Vector3i] = []
## Inward cardinal per breach, parallel to `breaches`.
var breach_dirs: Array[Vector2i] = []

## Foundation pad surfaces (x, surface Y, z), and the kind of each, parallel arrays.
var pads: Array[Vector3i] = []
var pad_kinds: PackedInt32Array = PackedInt32Array()


func pad_count() -> int:
	return pads.size()


func breach_count() -> int:
	return breaches.size()


func hell_gate_count() -> int:
	return hell_gates.size()


func outer_stone_count() -> int:
	return outer_stones.size()


func add_pad(surface_vox: Vector3i, kind: PadKind) -> void:
	pads.append(surface_vox)
	pad_kinds.append(int(kind))


func add_breach(mouth_vox: Vector3i, inward: Vector2i) -> void:
	breaches.append(mouth_vox)
	breach_dirs.append(inward)


func add_outer_stone(xz: Vector2i, base_y: int, radius_vox: int, height_vox: int) -> void:
	var s := Stone.new()
	s.xz = xz
	s.base_y = base_y
	s.radius_vox = radius_vox
	s.height_vox = height_vox
	outer_stones.append(s)


func add_hell_gate(mouth_vox: Vector3i, outward: Vector2i, bearing_rad: float) -> void:
	var g := HellGate.new()
	g.mouth = mouth_vox
	g.outward = outward
	g.bearing_rad = bearing_rad
	hell_gates.append(g)


func pad_kind_at(index: int) -> PadKind:
	if index < 0 or index >= pad_kinds.size():
		push_error("SiegeLayout.pad_kind_at: %d is not a pad (have %d)" % [index, pad_kinds.size()])
		assert(false, "SiegeLayout: pad index out of range")
		return PadKind.STREET
	return pad_kinds[index] as PadKind


func pads_of_kind(kind: PadKind) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in range(pads.size()):
		if pad_kinds[i] == int(kind):
			out.append(pads[i])
	return out


func count_of_kind(kind: PadKind) -> int:
	var n := 0
	for i in range(pad_kinds.size()):
		if pad_kinds[i] == int(kind):
			n += 1
	return n


## Pad surface in world voxel space, which is what the live CityBrush and spawns want.
func pad_world(index: int, district_origin: Vector3i) -> Vector3i:
	if index < 0 or index >= pads.size():
		push_error("SiegeLayout.pad_world: %d is not a pad (have %d)" % [index, pads.size()])
		assert(false, "SiegeLayout: pad index out of range")
		return Vector3i.ZERO
	return pads[index] + district_origin


## Lodestone base centre in world voxel space.
func lodestone_world(district_origin: Vector3i) -> Vector3i:
	return (
		Vector3i(lodestone_xz.x, lodestone_base_y, lodestone_xz.y)
		+ district_origin
	)


func outer_stone_at(index: int) -> Stone:
	if index < 0 or index >= outer_stones.size():
		push_error(
			"SiegeLayout.outer_stone_at: %d is not a stone (have %d)"
			% [index, outer_stones.size()]
		)
		assert(false, "SiegeLayout: outer stone index out of range")
		return null
	return outer_stones[index]


func hell_gate_at(index: int) -> HellGate:
	if index < 0 or index >= hell_gates.size():
		push_error(
			"SiegeLayout.hell_gate_at: %d is not a hell gate (have %d)"
			% [index, hell_gates.size()]
		)
		assert(false, "SiegeLayout: hell gate index out of range")
		return null
	return hell_gates[index]


func breach_world(index: int, district_origin: Vector3i) -> Vector3i:
	if index < 0 or index >= breaches.size():
		push_error(
			"SiegeLayout.breach_world: %d is not a breach (have %d)"
			% [index, breaches.size()]
		)
		assert(false, "SiegeLayout: breach index out of range")
		return Vector3i.ZERO
	return breaches[index] + district_origin


## A siege the controller can actually run: five things to defend, somewhere they come from, a way
## into the quarter, and somewhere to build. Anything less is a bake that went wrong rather than a
## quiet tile.
func is_valid() -> bool:
	return (
		lodestone_xz.x >= 0
		and quarter_vox.size.x > 0
		and quarter_vox.size.y > 0
		and not breaches.is_empty()
		and not hell_gates.is_empty()
		and not outer_stones.is_empty()
		and not pads.is_empty()
	)


func describe() -> String:
	return (
		(
			"siege quarter=%s vox=%s deck_y=%d lodestone=%s r=%d h=%d"
			+ " outer=%d hell_gates=%d breaches=%d pads=%d (street=%d jump=%d high=%d)"
		)
		% [
			quarter_cells,
			quarter_vox,
			deck_y,
			lodestone_xz,
			lodestone_radius_vox,
			lodestone_height_vox,
			outer_stones.size(),
			hell_gates.size(),
			breaches.size(),
			pads.size(),
			count_of_kind(PadKind.STREET),
			count_of_kind(PadKind.ROOF_JUMP),
			count_of_kind(PadKind.ROOF_HIGH),
		]
	)
