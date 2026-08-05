## Siege Quarter tower recipes: gem costs, authored HP, combat-table ids, and voxel stamps.
##
## Rows live in `assets/gamedata.json` (`siege_towers`). Combat behaviour is a normal
## `CombatTable` monster row (`siege/…`); the visual is the stamp, not a creature mesh.
class_name SiegeTowerCatalog
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Cells between the pad surface point and the lowest stamp voxel — `stamp_at` leaves the pad
## plate solid and builds on the air cell above it.
const STAMP_BASE_CELLS := 1
## Air left between the top of a tower's stamp and its muzzle.
const MUZZLE_CLEARANCE_M := 0.35


class Def:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var combat_id: String = ""
	var gem: String = ""
	var hint: String = ""
	var hp: float = 0.0
	## item_id → count, spent from the siege pot.
	var cost: Dictionary = {}
	## Packed as [ox, oy, oz, material_id] relative to the pad surface centre.
	var voxels: PackedInt32Array = PackedInt32Array()
	## Highest voxel offset in the stamp. The combat host needs this to put its muzzle above its
	## own mass — see `muzzle_height_m`.
	var stamp_top_oy: int = 0


static var _by_id: Dictionary = {}
static var _order: Array[String] = []
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	_by_id.clear()
	_order.clear()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_order.clear()
	var rows: Dictionary = GameDataScript.siege_towers()
	var ids: Array = rows.keys()
	ids.sort()
	for id_v: Variant in ids:
		var id := str(id_v)
		var row: Dictionary = rows[id] as Dictionary
		var d := Def.new()
		d.id = id
		d.display_name = str(row.get("display_name", id))
		d.combat_id = str(row.get("combat_id", ""))
		d.gem = str(row.get("gem", ""))
		d.hint = str(row.get("hint", ""))
		d.hp = float(row.get("hp", 0.0))
		if d.combat_id.is_empty():
			push_error("SiegeTowerCatalog: '%s' missing combat_id" % id)
			assert(false, "SiegeTowerCatalog: missing combat_id")
			continue
		if d.hp <= 0.0:
			push_error("SiegeTowerCatalog: '%s' needs positive hp" % id)
			assert(false, "SiegeTowerCatalog: bad hp")
			continue
		var cost_raw: Variant = row.get("cost", {})
		if typeof(cost_raw) != TYPE_DICTIONARY:
			push_error("SiegeTowerCatalog: '%s' cost must be an object" % id)
			assert(false, "SiegeTowerCatalog: bad cost")
			continue
		d.cost = (cost_raw as Dictionary).duplicate()
		if d.cost.is_empty():
			push_error("SiegeTowerCatalog: '%s' has empty cost" % id)
			assert(false, "SiegeTowerCatalog: empty cost")
			continue
		d.voxels = _stamp_voxels(row.get("stamp", {}), id)
		if d.voxels.is_empty():
			push_error("SiegeTowerCatalog: '%s' stamp produced no voxels" % id)
			assert(false, "SiegeTowerCatalog: empty stamp")
			continue
		d.stamp_top_oy = _stamp_top_oy(d.voxels)
		_by_id[id] = d
		_order.append(id)


static func all() -> Array[Def]:
	ensure_loaded()
	var out: Array[Def] = []
	for id in _order:
		out.append(_by_id[id] as Def)
	return out


static func by_id(tower_id: String) -> Def:
	ensure_loaded()
	if not _by_id.has(tower_id):
		push_error("SiegeTowerCatalog.by_id: unknown '%s'" % tower_id)
		return null
	return _by_id[tower_id] as Def


static func ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for id in _order:
		out.append(id)
	return out


## Height above the pad surface point (`pad_world`, as handed to `stamp_at`) at which a tower's
## muzzle clears the mass it just painted, in metres.
##
## The muzzle is the eye: `UndeadGoalProvider` probes voxel line of sight from it to pick prey, and
## a probe that starts inside solid rock reaches nothing. A tower's combat host stands *within* its
## own stamp, so a muzzle derived from body span the way a creature's is would bury the eye and the
## tower would never acquire, never fire, and never look broken in any log.
static func muzzle_height_m(def: RefCounted, voxel_size: float) -> float:
	if def == null:
		push_error("SiegeTowerCatalog.muzzle_height_m: def required")
		return 0.0
	if voxel_size <= 0.0:
		push_error("SiegeTowerCatalog.muzzle_height_m: bad voxel size %f" % voxel_size)
		return 0.0
	## `stamp_at` starts one cell above the pad surface, so the top face of the highest voxel is
	## `STAMP_BASE_CELLS + top_oy + 1` cells up.
	var cells := STAMP_BASE_CELLS + int(def.get("stamp_top_oy")) + 1
	return float(cells) * voxel_size + MUZZLE_CLEARANCE_M


## Tallest voxel offset in a packed stamp.
static func _stamp_top_oy(voxels: PackedInt32Array) -> int:
	var top := 0
	var n := voxels.size() / 4
	for i in range(n):
		top = maxi(top, voxels[i * 4 + 1])
	return top


## Write the tower's voxels onto live terrain at the pad surface centre (world metres).
## Returns how many cells were painted.
static func stamp_at(
	terrain: VoxelTerrain,
	brush: CityBrush,
	def: RefCounted,
	pad_world: Vector3
) -> int:
	if terrain == null or brush == null or def == null:
		push_error("SiegeTowerCatalog.stamp_at: terrain/brush/def required")
		return 0
	var voxels: PackedInt32Array = def.get("voxels") as PackedInt32Array
	var tower_id := str(def.get("id"))
	if voxels.is_empty():
		push_error("SiegeTowerCatalog.stamp_at: empty voxels for '%s'" % tower_id)
		return 0
	var tool: VoxelTool = brush.tool
	if tool == null:
		push_error("SiegeTowerCatalog.stamp_at: brush has no tool")
		return 0
	var local := terrain.to_local(pad_world)
	var base := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	## Pad surface voxel is solid plate; tower sits on the air cell above it.
	base.y += 1
	var written := 0
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	brush.begin_edit()
	var n := voxels.size() / 4
	for i in range(n):
		var o := i * 4
		var vox := Vector3i(
			base.x + voxels[o],
			base.y + voxels[o + 1],
			base.z + voxels[o + 2]
		)
		var mat := voxels[o + 3]
		var existing := int(tool.get_voxel(vox))
		if existing == VoxelMaterial.BEDROCK:
			continue
		brush.set_vox(vox, mat)
		written += 1
	brush.end_edit()
	return written


## Compact pillar on the pad: solid footprint + a lit/coloured cap.
static func _stamp_voxels(stamp_v: Variant, tower_id: String) -> PackedInt32Array:
	if typeof(stamp_v) != TYPE_DICTIONARY:
		push_error("SiegeTowerCatalog: '%s' stamp must be an object" % tower_id)
		return PackedInt32Array()
	var stamp: Dictionary = stamp_v
	var height := maxi(int(stamp.get("height", 0)), 1)
	var radius := maxi(int(stamp.get("radius", 1)), 0)
	var mat := int(stamp.get("mat", VoxelMaterial.STONE))
	var cap_mat := int(stamp.get("cap_mat", VoxelMaterial.GLASS_LIT))
	if VoxelMaterial.is_gem(mat) or VoxelMaterial.is_gem(cap_mat):
		push_error(
			"SiegeTowerCatalog: '%s' stamp uses a collectible gem material" % tower_id
		)
		assert(false, "SiegeTowerCatalog: gem stamp material")
		return PackedInt32Array()
	var packed := PackedInt32Array()
	for y in range(height):
		var use_mat := cap_mat if y == height - 1 else mat
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if absi(dx) + absi(dz) > radius + 1:
					continue
				packed.append(dx)
				packed.append(y)
				packed.append(dz)
				packed.append(use_mat)
	return packed
