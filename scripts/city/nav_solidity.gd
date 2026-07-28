## Passability table for voxel navigation, derived once from VoxelBlockLibrary models.
## No hand-maintained material lists — collision_mask / collision_aabbs are the source of truth.
class_name NavSolidity
extends RefCounted

## Self-preload so static factories type-check before global class_cache picks us up.
const _Self := preload("res://scripts/city/nav_solidity.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")

## Values match the `SOL_*` constants in native/city_voxel/src/nav.rs — this enum is the
## wire format of the exported tables, not a private label.
enum Kind {
	PASSABLE = 0,
	WATER = 1,
	SOLID = 2,
	PARTIAL = 3,
}

## Materials are one byte in the voxel volume, so the Rust tables are always 256 long.
const TABLE_SIZE := 256

## Indexed by VoxelMaterial id. Length is always VoxelMaterial.COUNT.
var kind: PackedByteArray = PackedByteArray()
## Sub-cell top of the collision solid in [0, 1]. SOLID/PASSABLE/WATER use 1.0 / 0.0 / 1.0.
## PARTIAL stores the highest AABB top (curb 0.4, roof-slope steps up to 1.0).
var top_frac: PackedFloat32Array = PackedFloat32Array()


static func build(library: VoxelBlockyLibrary = null) -> _Self:
	if VoxelMaterial.COUNT > TABLE_SIZE:
		push_error(
			"NavSolidity.build: VoxelMaterial.COUNT=%d exceeds the %d-entry nav table"
			% [VoxelMaterial.COUNT, TABLE_SIZE]
		)
	var lib: VoxelBlockyLibrary = library
	if lib == null:
		lib = VoxelBlockLibraryScript.build()
	var models: Array = lib.models
	if models.size() < VoxelMaterial.COUNT:
		push_error(
			"NavSolidity.build: library has %d models, need VoxelMaterial.COUNT=%d"
			% [models.size(), VoxelMaterial.COUNT]
		)
	var out: _Self = _Self.new()
	out.kind.resize(VoxelMaterial.COUNT)
	out.top_frac.resize(VoxelMaterial.COUNT)
	for id in range(VoxelMaterial.COUNT):
		if id >= models.size():
			out.kind[id] = Kind.PASSABLE
			out.top_frac[id] = 0.0
			continue
		var model: VoxelBlockyModel = models[id]
		var entry := _classify_model(id, model)
		out.kind[id] = int(entry["kind"])
		out.top_frac[id] = float(entry["top_frac"])
	return out


func is_blocker(id: int) -> bool:
	var k := int(kind[id])
	return k == Kind.SOLID or k == Kind.PARTIAL


func is_traversable(id: int) -> bool:
	var k := int(kind[id])
	return k == Kind.PASSABLE or k == Kind.WATER


func kind_name(id: int) -> String:
	match int(kind[id]):
		Kind.PASSABLE:
			return "PASSABLE"
		Kind.WATER:
			return "WATER"
		Kind.SOLID:
			return "SOLID"
		Kind.PARTIAL:
			return "PARTIAL"
		_:
			push_error("NavSolidity.kind_name: bad kind %d for id %d" % [kind[id], id])
			return "?"


func count_by_kind() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(4)
	counts.fill(0)
	for id in range(kind.size()):
		counts[int(kind[id])] += 1
	return counts


## `solid_class` for the Rust bake. Ids past VoxelMaterial.COUNT read SOLID, matching the
## Rust default: an agent refusing to walk is a visible bug, one walking through a wall is
## a silent one.
func export_class() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TABLE_SIZE)
	out.fill(Kind.SOLID)
	for id in range(kind.size()):
		out[id] = kind[id]
	return out


## `solid_top` for the Rust bake — sub-cell collision top, only read for PARTIAL cells.
func export_top() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(TABLE_SIZE)
	out.fill(1.0)
	for id in range(top_frac.size()):
		out[id] = top_frac[id]
	return out


## `solid_destructible` for the Rust bake. Spans resting on carveable fabric are flagged
## fragile, so routing can price a floor that a blast may remove.
func export_destructible() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TABLE_SIZE)
	out.fill(0)
	for id in range(kind.size()):
		out[id] = 1 if VoxelMaterial.is_destructible(id) else 0
	return out


## `solid_climbable` for the Rust bake. Only full-cell collision offers a facade to climb;
## a curb lip or roof wedge is a step the walk rules already cover.
func export_climbable() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TABLE_SIZE)
	out.fill(0)
	for id in range(kind.size()):
		out[id] = 1 if int(kind[id]) == Kind.SOLID else 0
	return out


## The four tables NativeNavBake.bake_from_volume and NativeNavWorld.configure take,
## keyed as DistrictBakeJob expects them in `nav_solidity`.
func export_tables() -> Dictionary:
	return {
		"class": export_class(),
		"top": export_top(),
		"destructible": export_destructible(),
		"climbable": export_climbable(),
	}


static func _classify_model(id: int, model: VoxelBlockyModel) -> Dictionary:
	if model is VoxelBlockyModelEmpty:
		return {"kind": Kind.PASSABLE, "top_frac": 0.0}

	var mask: int = model.collision_mask
	## Walk-through props (leaves, yew, bark, planters, flowers) and air.
	if mask == 0:
		return {"kind": Kind.PASSABLE, "top_frac": 0.0}
	## Swim volume — passable to swimmers, blocking otherwise. Mask wins over AABB shape.
	if mask == 2:
		return {"kind": Kind.WATER, "top_frac": _aabb_top(model.collision_aabbs)}

	var boxes: Array = model.collision_aabbs
	if boxes.is_empty():
		## VoxelBlockyModelCube and any solid mesh without explicit AABBs = full cell.
		return {"kind": Kind.SOLID, "top_frac": 1.0}

	if boxes.size() == 1 and _is_full_cell(boxes[0]):
		return {"kind": Kind.SOLID, "top_frac": 1.0}

	var top := _aabb_top(boxes)
	if top <= 0.0:
		push_error(
			"NavSolidity: material %d has collision AABBs but top_frac=%.4f" % [id, top]
		)
	return {"kind": Kind.PARTIAL, "top_frac": top}


static func _is_full_cell(box: AABB) -> bool:
	return box.position.is_equal_approx(Vector3.ZERO) and box.size.is_equal_approx(Vector3.ONE)


static func _aabb_top(boxes: Array) -> float:
	if boxes.is_empty():
		return 1.0
	var top := 0.0
	for item: Variant in boxes:
		var box: AABB = item
		top = maxf(top, box.position.y + box.size.y)
	return clampf(top, 0.0, 1.0)
