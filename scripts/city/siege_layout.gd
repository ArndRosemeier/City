## Planned geometry for a Siege-theme district (district-local voxel coords).
##
## Survives the composer so the runtime controller can find the Lodestone, the foundation pads
## and the breach gates. Unlike every other themed layout this describes an *overlay* rather
## than a landmark: the quarter is a rectangle of ordinary street grid that the barricade pass
## sealed off, so roads, lots and sidewalks underneath it are the normal urban output.
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

## Breach mouths the horde walks in through: centre column (x, surface Y, z).
var gates: Array[Vector3i] = []
## Inward cardinal per gate, parallel to `gates`.
var gate_dirs: Array[Vector2i] = []

## Foundation pad surfaces (x, surface Y, z), and the kind of each, parallel arrays.
var pads: Array[Vector3i] = []
var pad_kinds: PackedInt32Array = PackedInt32Array()


func pad_count() -> int:
	return pads.size()


func gate_count() -> int:
	return gates.size()


func add_pad(surface_vox: Vector3i, kind: PadKind) -> void:
	pads.append(surface_vox)
	pad_kinds.append(int(kind))


func add_gate(mouth_vox: Vector3i, inward: Vector2i) -> void:
	gates.append(mouth_vox)
	gate_dirs.append(inward)


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


func gate_world(index: int, district_origin: Vector3i) -> Vector3i:
	if index < 0 or index >= gates.size():
		push_error("SiegeLayout.gate_world: %d is not a gate (have %d)" % [index, gates.size()])
		assert(false, "SiegeLayout: gate index out of range")
		return Vector3i.ZERO
	return gates[index] + district_origin


## A siege the controller can actually run: somewhere to defend, somewhere they come from, and
## somewhere to build. Anything less is a bake that went wrong rather than a quiet tile.
func is_valid() -> bool:
	return (
		lodestone_xz.x >= 0
		and quarter_vox.size.x > 0
		and quarter_vox.size.y > 0
		and not gates.is_empty()
		and not pads.is_empty()
	)


func describe() -> String:
	return (
		"siege quarter=%s vox=%s deck_y=%d lodestone=%s r=%d h=%d gates=%d pads=%d (street=%d jump=%d high=%d)"
		% [
			quarter_cells,
			quarter_vox,
			deck_y,
			lodestone_xz,
			lodestone_radius_vox,
			lodestone_height_vox,
			gates.size(),
			pads.size(),
			count_of_kind(PadKind.STREET),
			count_of_kind(PadKind.ROOF_JUMP),
			count_of_kind(PadKind.ROOF_HIGH),
		]
	)
