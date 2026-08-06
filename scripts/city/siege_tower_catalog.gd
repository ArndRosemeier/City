## Siege Quarter tower recipes: gem costs, authored HP, combat-table ids, and voxel stamps.
##
## Rows live in `assets/gamedata.json` (`siege_towers`). Combat behaviour is a normal
## `CombatTable` monster row (`siege/…`); the visual is the stamp, not a creature mesh.
##
## A row with `buildable: false` is the same kind of structure with no gem price and no pad
## listing — the world stamps it (crypt / castle-dungeon spawn spires) and only its hit points
## take it down.
class_name SiegeTowerCatalog
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Cells between the pad surface point and the lowest stamp voxel — `stamp_at` leaves the pad
## plate solid and builds on the air cell above it.
const STAMP_BASE_CELLS := 1
## Air left between the top of a tower's stamp and its muzzle.
const MUZZLE_CLEARANCE_M := 0.35
## Extra metres past the solid stamp face so a body pressed against the voxels can still count as
## touching the host. Stones solve the same job with `vuln_radius_m`; towers take living combat
## damage, so this lands on `UndeadUnit.hit_radius` instead.
const STRUCTURE_HIT_SLACK_M := 1.2


class Def:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var combat_id: String = ""
	var gem: String = ""
	var hint: String = ""
	var hp: float = 0.0
	## False for towers the world places (crypt / dungeon spawn spires): no gem cost, never
	## offered on a siege pad.
	var buildable: bool = true
	## item_id → count, spent from the player's inventory. Empty on a world-placed tower.
	var cost: Dictionary = {}
	## Packed as [ox, oy, oz, material_id] relative to the pad surface centre.
	var voxels: PackedInt32Array = PackedInt32Array()
	## Highest voxel offset in the stamp. The combat host needs this to put its muzzle above its
	## own mass — see `muzzle_height_m`.
	var stamp_top_oy: int = 0
	## Authored stamp radius in voxels (manhattan diamond). Drives `structure_hit_radius_m`.
	var stamp_radius_vox: int = 1
	## Tip material (always `ORB` for live towers). Used by `muzzle_height_m`.
	var cap_mat: int = VoxelMaterial.ORB


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
		d.buildable = bool(row.get("buildable", true))
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
		if d.buildable and d.cost.is_empty():
			push_error("SiegeTowerCatalog: '%s' has empty cost" % id)
			assert(false, "SiegeTowerCatalog: empty cost")
			continue
		if not d.buildable and not d.cost.is_empty():
			push_error("SiegeTowerCatalog: world-placed '%s' must not carry a gem cost" % id)
			assert(false, "SiegeTowerCatalog: cost on a world tower")
			continue
		var stamp_raw: Variant = row.get("stamp", {})
		if typeof(stamp_raw) == TYPE_DICTIONARY:
			d.stamp_radius_vox = maxi(int((stamp_raw as Dictionary).get("radius", 1)), 0)
		d.voxels = _stamp_voxels(stamp_raw, id)
		if d.voxels.is_empty():
			push_error("SiegeTowerCatalog: '%s' stamp produced no voxels" % id)
			assert(false, "SiegeTowerCatalog: empty stamp")
			continue
		d.stamp_top_oy = _stamp_top_oy(d.voxels)
		if typeof(stamp_raw) == TYPE_DICTIONARY:
			d.cap_mat = int((stamp_raw as Dictionary).get("cap_mat", VoxelMaterial.ORB))
		_by_id[id] = d
		_order.append(id)


static func all() -> Array[Def]:
	ensure_loaded()
	var out: Array[Def] = []
	for id in _order:
		out.append(_by_id[id] as Def)
	return out


## The rows a siege pad may offer. World-placed towers are stamped by their district and never
## sold, so they are not part of the pot economy at all.
static func buildable() -> Array[Def]:
	var out: Array[Def] = []
	for def: Def in all():
		if def.buildable:
			out.append(def)
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
## muzzle sits, in metres.
##
## The muzzle is the eye: `UndeadGoalProvider` probes voxel line of sight from it to pick prey, and
## a probe that starts inside solid rock reaches nothing. A tower's combat host stands *within* its
## own stamp, so a muzzle derived from body span the way a creature's is would bury the eye and the
## tower would never acquire, never fire, and never look broken in any log.
##
## The tip cell is `ORB` — a sphere mesh, but a full solid voxel for LOS. The eye must sit in the
## air above that cell's top face, not in the mesh crown inside the cell.
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


## Flat metres from pad centre within which a melee body can treat the tower as in reach.
## Clears the solid stamp face (`radius + 0.5` cells) plus capsule slack — not a physics hitbox,
## the same kind of volume stones expose as `vuln_radius_m`.
static func structure_hit_radius_m(def: RefCounted, voxel_size: float) -> float:
	if def == null:
		push_error("SiegeTowerCatalog.structure_hit_radius_m: def required")
		return 0.0
	if voxel_size <= 0.0:
		push_error("SiegeTowerCatalog.structure_hit_radius_m: bad voxel size %f" % voxel_size)
		return 0.0
	var radius_vox := maxi(int(def.get("stamp_radius_vox")), 0)
	return (float(radius_vox) + 0.5) * voxel_size + STRUCTURE_HIT_SLACK_M


## Tallest voxel offset in a packed stamp.
static func _stamp_top_oy(voxels: PackedInt32Array) -> int:
	var top := 0
	var n := voxels.size() / 4
	for i in range(n):
		top = maxi(top, voxels[i * 4 + 1])
	return top


## Write the tower's voxels onto live terrain at the pad surface centre (world metres).
##
## Returns the cells it painted, in world voxel coordinates. The caller needs them, not just a
## count: a standing tower holds its own stamp against damage (`VoxelWard`), and the only place that
## knows which cells the stamp actually landed on is here.
static func stamp_at(
	terrain: VoxelTerrain,
	brush: CityBrush,
	def: RefCounted,
	pad_world: Vector3
) -> Array[Vector3i]:
	var written: Array[Vector3i] = []
	if terrain == null or brush == null or def == null:
		push_error("SiegeTowerCatalog.stamp_at: terrain/brush/def required")
		return written
	var voxels: PackedInt32Array = def.get("voxels") as PackedInt32Array
	var tower_id := str(def.get("id"))
	if voxels.is_empty():
		push_error("SiegeTowerCatalog.stamp_at: empty voxels for '%s'" % tower_id)
		return written
	var tool: VoxelTool = brush.tool
	if tool == null:
		push_error("SiegeTowerCatalog.stamp_at: brush has no tool")
		return written
	var local := terrain.to_local(pad_world)
	var base := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	## Pad surface voxel is solid plate; tower sits on the air cell above it.
	base.y += 1
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
		written.append(vox)
	brush.end_edit()
	return written


## Futuristic fractal spire: tapering glowing shaft + a single ORB tip that fires.
##
## Body `mat` must be a fractal-display id (band / glow / interior). Cap must be `ORB` — the
## reusable energy sphere, not a GEM_* (those are collectible ore).
static func _stamp_voxels(stamp_v: Variant, tower_id: String) -> PackedInt32Array:
	if typeof(stamp_v) != TYPE_DICTIONARY:
		push_error("SiegeTowerCatalog: '%s' stamp must be an object" % tower_id)
		return PackedInt32Array()
	var stamp: Dictionary = stamp_v
	## Height includes the orb layer. Need at least shaft + tip.
	var height := maxi(int(stamp.get("height", 0)), 2)
	var radius := maxi(int(stamp.get("radius", 1)), 0)
	var mat := int(stamp.get("mat", VoxelMaterial.FRACTAL_GLOW))
	var cap_mat := int(stamp.get("cap_mat", VoxelMaterial.ORB))
	if VoxelMaterial.is_gem(mat) or VoxelMaterial.is_gem(cap_mat):
		push_error(
			"SiegeTowerCatalog: '%s' stamp uses a collectible gem material" % tower_id
		)
		assert(false, "SiegeTowerCatalog: gem stamp material")
		return PackedInt32Array()
	if not VoxelMaterial.is_fractal_display(mat):
		push_error(
			"SiegeTowerCatalog: '%s' body mat %d must be fractal-display" % [tower_id, mat]
		)
		assert(false, "SiegeTowerCatalog: non-fractal tower body")
		return PackedInt32Array()
	if cap_mat != VoxelMaterial.ORB:
		push_error(
			"SiegeTowerCatalog: '%s' tip must be ORB, got %d" % [tower_id, cap_mat]
		)
		assert(false, "SiegeTowerCatalog: non-orb tower tip")
		return PackedInt32Array()
	var packed := PackedInt32Array()
	var shaft_h := height - 1
	for y in range(shaft_h):
		## Taper the diamond from the authored base radius down to a single column.
		var t := 0.0 if shaft_h <= 1 else float(y) / float(shaft_h - 1)
		var layer_r := maxi(0, int(round(lerpf(float(radius), 0.0, t))))
		for dx in range(-layer_r, layer_r + 1):
			for dz in range(-layer_r, layer_r + 1):
				var man := absi(dx) + absi(dz)
				if man > layer_r:
					continue
				## Fat layers keep a plus silhouette — open corners read as a pylon, not a brick.
				if layer_r >= 2 and dx != 0 and dz != 0 and man > 1:
					continue
				packed.append(dx)
				packed.append(y)
				packed.append(dz)
				packed.append(mat)
	## Firing tip: one orb centred on the pad.
	packed.append(0)
	packed.append(shaft_h)
	packed.append(0)
	packed.append(cap_mat)
	return packed
