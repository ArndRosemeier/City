## Builds a Monster Zoo district: one glowing containment ring around an open battlefield
## that is carved into ~40 soft, dice-rolled faction territories.
##
## The field is authored as a place that has already been fought over. Old-town houses,
## trees, gravestones and gazebos are scattered first, then the same shapes combat uses —
## big charged-blast spheres and stomp craters — are carved through them offline. Nothing
## here is a runtime effect: the player walks in on a battlefield, not onto a clean lawn
## that ruins itself later.
##
## District-local voxel coords, like every other composer.
class_name ZooComposer
extends RefCounted

const ZooLayoutScript := preload("res://scripts/city/zoo_layout.gd")

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28

var layout: ZooLayout = null

## Voxels the containment ring is inset from the reserve edge, and how thick / tall it is.
const FENCE_INSET := 5
const FENCE_THICK := 2
const FENCE_H := 16
## Dark posts every this many voxels along a run; glass and light lines fill between.
const FENCE_POST_PITCH := 9
## Heights above the deck where the red energy line runs through the pane.
const FENCE_LINE_OFFSETS: Array[int] = [3, 8, 13]

## Visitor gate: half-width of the opening and the plate-free apron behind it.
const GATE_HALF := 5
const PLAZA_HALF := 12
const PLAZA_DEPTH := 22
## Height of the invisible viewing panes on the field-facing lip of the apron.
const PLAZA_VEIL_H := 8

## One dice-rolled territory per seed. Six factions hold ground; nobody else does.
const TERRITORY_COUNT := 40
const FACTION_COUNT := 6
## Nobody may win more than this many rolls, or one faction owns half the field.
const FACTION_CAP_SLACK := 2
## Ownership grid pitch: 2 m cells are fine for "whose ground am I standing on".
const OWNER_CELL := 4

## Summon gazebo footprint (half-extent) and the scar-clear radius around each station.
const PAD_HALF := 5
const PAD_CHAMFER := 2
## Posts this far in from the square corner along each face. Must stay on the chamfered
## deck (HALF-1 is off the footprint); mid-face between the two posts is the doorway.
const PAD_POST_INSET := 2
const PAD_COLUMN_H := 7
const PAD_ROOF_H := 4
const PAD_CLEAR := 9

## Inset 2×2 turf wells with a 1-voxel rim (4×4 footprint). Sparse on purpose — a
## dancefloor of flush tiles reads as paint; a few deliberate pads read as markers.
const PLATE_GLOW := 2
const PLATE_RIM := 1
const PLATE_FOOT := PLATE_GLOW + PLATE_RIM * 2
## One pad per this many square voxels of field, then thinned by distance to the seed.
const PLATE_PER_AREA := 2200
const PLATE_CORE_BIAS := 1.8

## Battlefield scatter budgets, as one prop per this many square voxels of field. The
## reserve is most of a district — a fixed count would leave a 350 m field with a dozen
## houses in it, which reads as empty ground rather than as a place people lived in.
const HOUSE_PER_AREA := 5500
const HOUSE_MIN_W := 10
const HOUSE_MAX_W := 17
const TREE_PER_AREA := 1400
const GRAVE_PER_AREA := 1600
const GAZEBO_PER_AREA := 28000

## Scar pass: charged-blast spheres biased at the houses, then loose stomp craters.
const BLAST_PER_AREA := 2800
const BLAST_R_MIN := 6
const BLAST_R_MAX := 12
## Fraction of blasts aimed at a scattered house rather than open ground.
const BLAST_AT_HOUSE_P := 0.75
const STOMP_PER_AREA := 1000
const STOMP_R_MIN := 3
const STOMP_R_MAX := 6
## Deepest a crater may bite below the deck — leaves substrate over the bedrock band.
const CRATER_MAX_DEPTH := 4

const HOUSE_WALL_MATS: Array[int] = [
	VoxelMaterial.BRICK, VoxelMaterial.PLASTER, VoxelMaterial.BRICK_DARK
]
const HOUSE_ROOF_MATS: Array[int] = [
	VoxelMaterial.ROOF_CLAY, VoxelMaterial.ROOF
]

## Scratch masks over `field_rect`: what may never be carved, and what is already taken.
var _mask_origin: Vector2i = Vector2i.ZERO
var _mask_size: Vector2i = Vector2i.ZERO
var _protect: PackedByteArray = PackedByteArray()
var _claim: PackedByteArray = PackedByteArray()
## Footprints of the scattered houses, so the blast pass knows what to aim at.
var _house_rects: Array[Rect2i] = []


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	layout = _plan()
	if layout == null:
		return
	_reset_masks()
	_build_field_floor()
	_build_fence()
	_build_gate_and_plaza()
	## Scatter, then scar: the ruin has to be cut out of standing geometry, not faked
	## by placing pre-broken stumps.
	var houses := _scatter_houses()
	var gazebos := _scatter_gazebos()
	var trees := _scatter_trees()
	var graves := _scatter_gravestones()
	var blasts := _scar_charged_blasts()
	var stomps := _scar_stomps()
	## Plates go down last so craters read as holes punched through claimed ground.
	_stamp_turf_plates()
	_build_spawn_pads()
	print(
		"ZooComposer: scattered %d houses, %d gazebos, %d trees, %d graves; "
		% [houses, gazebos, trees, graves]
		+ "scarred with %d charged blasts and %d stomps" % [blasts, stomps]
	)
	print("ZooComposer: %s" % layout.describe())


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	layout = _plan()
	if layout == null:
		return
	_reset_masks()
	_build_field_floor()
	## The glowing ring is the entire silhouette from another tile; the props, scars and
	## plates are all deck detail nobody can resolve at that range.
	_build_fence()
	_build_gate_and_plaza()


func _begin(_min_v: Vector3i, _max_v: Vector3i) -> bool:
	if brush == null or rng == null or planner == null:
		push_error("ZooComposer: brush / rng / planner not set")
		return false
	if planner.large_zoo.size.x <= 0:
		push_error("ZooComposer: empty large_zoo")
		return false
	return true


func _plan() -> ZooLayout:
	var lz: Rect2i = planner.large_zoo
	var rx0 := lz.position.x * cell_size
	var rz0 := lz.position.y * cell_size
	var rx1 := lz.end.x * cell_size
	var rz1 := lz.end.y * cell_size
	var fence := Rect2i(
		rx0 + FENCE_INSET,
		rz0 + FENCE_INSET,
		rx1 - rx0 - 2 * FENCE_INSET,
		rz1 - rz0 - 2 * FENCE_INSET
	)
	if fence.size.x < 80 or fence.size.y < 80:
		push_error(
			"ZooComposer: reserve %dx%d too small for a zoo" % [fence.size.x, fence.size.y]
		)
		return null
	var out: ZooLayout = ZooLayoutScript.new() as ZooLayout
	out.fence_rect = fence
	out.field_rect = fence.grow(-FENCE_THICK)
	out.deck_y = ground_y
	out.fence_top_y = ground_y + FENCE_H
	_plan_gate(out)
	_plan_seeds(out)
	_plan_factions(out)
	_plan_ownership(out)
	return out


## Put the one opening where a road stub already reaches the ring, so the walk in follows
## the street instead of ending at a blank wall.
func _plan_gate(out: ZooLayout) -> void:
	var fence := out.fence_rect
	var sides: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
	]
	var best_dir := Vector2i(0, 1)
	var best_at := fence.position.x + fence.size.x / 2
	var best_score := -1
	for dir: Vector2i in sides:
		var along_x := dir.x == 0
		var lo := fence.position.x if along_x else fence.position.y
		var hi := fence.end.x if along_x else fence.end.y
		var mid := (lo + hi) / 2
		var fixed := 0
		if dir.y > 0:
			fixed = fence.position.y
		elif dir.y < 0:
			fixed = fence.end.y - 1
		elif dir.x > 0:
			fixed = fence.position.x
		else:
			fixed = fence.end.x - 1
		for t in range(lo + GATE_HALF + 2, hi - GATE_HALF - 2):
			var x := t if along_x else fixed
			var z := fixed if along_x else t
			if not _is_road_vox(x, z):
				continue
			## Closer to the middle of a side reads as a front gate, not a corner hole.
			var score := (hi - lo) - absi(t - mid)
			if score > best_score:
				best_score = score
				best_dir = dir
				best_at = t
	out.gate_dir = best_dir
	var along_gate_x := best_dir.x == 0
	if along_gate_x:
		var gz := fence.position.y if best_dir.y > 0 else fence.end.y - FENCE_THICK
		out.gate_rect = Rect2i(best_at - GATE_HALF, gz, GATE_HALF * 2 + 1, FENCE_THICK)
	else:
		var gx := fence.position.x if best_dir.x > 0 else fence.end.x - FENCE_THICK
		out.gate_rect = Rect2i(gx, best_at - GATE_HALF, FENCE_THICK, GATE_HALF * 2 + 1)
	var gate_mid := Vector2i(
		out.gate_rect.position.x + out.gate_rect.size.x / 2,
		out.gate_rect.position.y + out.gate_rect.size.y / 2
	)
	var apron := gate_mid + best_dir * (PLAZA_DEPTH / 2 + FENCE_THICK)
	if along_gate_x:
		out.plaza_rect = Rect2i(
			apron.x - PLAZA_HALF, apron.y - PLAZA_DEPTH / 2, PLAZA_HALF * 2, PLAZA_DEPTH
		)
	else:
		out.plaza_rect = Rect2i(
			apron.x - PLAZA_DEPTH / 2, apron.y - PLAZA_HALF, PLAZA_DEPTH, PLAZA_HALF * 2
		)
	out.plaza_rect = out.plaza_rect.intersection(out.field_rect)
	## The cloak gate stands beside the opening, one step inside the ring.
	var side := Vector2i(-best_dir.y, best_dir.x)
	var mount := gate_mid + best_dir * (FENCE_THICK + 2) + side * (GATE_HALF + 1)
	out.cloak_gate_vox = Vector3i(mount.x, out.deck_y, mount.y)


func _is_road_vox(x: int, z: int) -> bool:
	return LandUse.is_road(planner.tag_at(x / cell_size, z / cell_size))


## Dart-thrown seeds with a minimum spacing — roughly equal areas, none of the grid look
## that would give the territories visible straight borders.
func _plan_seeds(out: ZooLayout) -> void:
	var inner := out.field_rect.grow(-10)
	if inner.size.x <= 0 or inner.size.y <= 0:
		push_error("ZooComposer: field too small to seed territories")
		return
	var area := float(inner.size.x * inner.size.y)
	var spacing := sqrt(area / float(TERRITORY_COUNT)) * 0.72
	var min_d2 := spacing * spacing
	var tries := TERRITORY_COUNT * 80
	while out.seed_xz.size() < TERRITORY_COUNT and tries > 0:
		tries -= 1
		var p := Vector2i(
			inner.position.x + rng.randi() % inner.size.x,
			inner.position.y + rng.randi() % inner.size.y
		)
		if out.plaza_rect.has_point(p):
			continue
		var ok := true
		for other: Vector2i in out.seed_xz:
			var dx := float(p.x - other.x)
			var dz := float(p.y - other.y)
			if dx * dx + dz * dz < min_d2:
				ok = false
				break
		if ok:
			out.seed_xz.append(p)
			out.spawner_vox.append(Vector3i(p.x, out.deck_y, p.y))
	if out.seed_xz.is_empty():
		push_error("ZooComposer: dart throwing placed no territory seeds")
		return
	out.seed_radius_vox = int(round(spacing * 0.95))


## Dice, with a cap so a lucky faction cannot take half the district.
func _plan_factions(out: ZooLayout) -> void:
	var n := out.seed_xz.size()
	var cap := int(ceil(float(n) / float(FACTION_COUNT))) + FACTION_CAP_SLACK
	var used := PackedInt32Array()
	used.resize(FACTION_COUNT)
	used.fill(0)
	out.seed_faction = PackedInt32Array()
	out.seed_faction.resize(n)
	for i in range(n):
		var open: PackedInt32Array = PackedInt32Array()
		for f in range(FACTION_COUNT):
			if used[f] < cap:
				open.append(f)
		if open.is_empty():
			push_error("ZooComposer: faction cap %d left no faction for seed %d" % [cap, i])
			assert(false, "ZooComposer: faction roll starved")
			open.append(0)
		var pick := open[rng.randi() % open.size()]
		out.seed_faction[i] = pick
		used[pick] += 1


## Nearest seed per coarse cell, with the distance jittered so borders wander instead of
## snapping to the straight bisectors a plain Voronoi would draw.
func _plan_ownership(out: ZooLayout) -> void:
	var field := out.field_rect
	out.owner_cell_vox = OWNER_CELL
	out.owner_origin = field.position
	out.owner_size = Vector2i(
		(field.size.x + OWNER_CELL - 1) / OWNER_CELL,
		(field.size.y + OWNER_CELL - 1) / OWNER_CELL
	)
	out.ownership = PackedInt32Array()
	out.ownership.resize(out.owner_size.x * out.owner_size.y)
	out.ownership.fill(-1)
	if out.seed_xz.is_empty():
		return
	for cz in range(out.owner_size.y):
		for cx in range(out.owner_size.x):
			var wx := out.owner_origin.x + cx * OWNER_CELL + OWNER_CELL / 2
			var wz := out.owner_origin.y + cz * OWNER_CELL + OWNER_CELL / 2
			var best := -1
			var best_d := INF
			for i in range(out.seed_xz.size()):
				var s := out.seed_xz[i]
				var dx := float(wx - s.x)
				var dz := float(wz - s.y)
				## Per-seed wobble on the metric: the same seed always bends the same way,
				## so the map is stable across bakes of this tile.
				var wobble := 1.0 + 0.16 * sin(float(wx) * 0.11 + float(i)) * cos(
					float(wz) * 0.09 - float(i)
				)
				var d := sqrt(dx * dx + dz * dz) * wobble
				if d < best_d:
					best_d = d
					best = i
			out.ownership[cz * out.owner_size.x + cx] = best


# --- masks ------------------------------------------------------------------

func _reset_masks() -> void:
	var field := layout.field_rect
	_mask_origin = field.position
	_mask_size = field.size
	var n := _mask_size.x * _mask_size.y
	_protect = PackedByteArray()
	_protect.resize(n)
	_protect.fill(0)
	_claim = PackedByteArray()
	_claim.resize(n)
	_claim.fill(0)
	_house_rects.clear()
	_protect_rect(layout.plaza_rect)
	## The walk from the gate to the plaza stays readable: no craters, no plates.
	var gate_mid := Vector2i(
		layout.gate_rect.position.x + layout.gate_rect.size.x / 2,
		layout.gate_rect.position.y + layout.gate_rect.size.y / 2
	)
	for step in range(0, PLAZA_DEPTH + FENCE_THICK + 2):
		var p := gate_mid + layout.gate_dir * step
		_protect_disk(p.x, p.y, GATE_HALF)
	for pad: Vector3i in layout.spawner_vox:
		_protect_disk(pad.x, pad.z, PAD_CLEAR)


## How many of something the field can carry at one per `per_area` square voxels.
func _budget(per_area: int) -> int:
	var field := layout.field_rect
	return maxi(1, (field.size.x * field.size.y) / per_area)


func _mask_index(x: int, z: int) -> int:
	var lx := x - _mask_origin.x
	var lz := z - _mask_origin.y
	if lx < 0 or lz < 0 or lx >= _mask_size.x or lz >= _mask_size.y:
		return -1
	return lz * _mask_size.x + lx


func _protect_rect(r: Rect2i) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := _mask_index(x, z)
			if i >= 0:
				_protect[i] = 1


func _protect_disk(cx: int, cz: int, radius: int) -> void:
	var r2 := radius * radius
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz > r2:
				continue
			var i := _mask_index(x, z)
			if i >= 0:
				_protect[i] = 1


func _is_protected(x: int, z: int) -> bool:
	var i := _mask_index(x, z)
	if i < 0:
		## Everything outside the field — the ring itself included — is off limits.
		return true
	return _protect[i] != 0


func _area_free(r: Rect2i) -> bool:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := _mask_index(x, z)
			if i < 0 or _protect[i] != 0 or _claim[i] != 0:
				return false
	return true


func _claim_rect(r: Rect2i) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := _mask_index(x, z)
			if i >= 0:
				_claim[i] = 1


# --- shell ------------------------------------------------------------------

func _build_field_floor() -> void:
	var field := layout.field_rect
	var deck := layout.deck_y
	brush.fill_box(
		Vector3i(field.position.x, deck, field.position.y),
		Vector3i(field.end.x, deck + 1, field.end.y),
		VoxelMaterial.DIRT
	)


## Two-voxel ring: dark posts and rails, red energy bands through the full thickness so
## they read at range, and a tinted glass pane on the outer face between the bands. The
## line is voxels, not a filament inside glass — the mesher has no way to draw the latter.
func _build_fence() -> void:
	var fence := layout.fence_rect
	var deck := layout.deck_y
	var top := layout.fence_top_y
	brush.begin_edit()
	for z in range(fence.position.y, fence.end.y):
		for x in range(fence.position.x, fence.end.x):
			var depth := _ring_depth(x, z, fence)
			if depth < 0:
				continue
			if layout.gate_rect.has_point(Vector2i(x, z)):
				continue
			var along := x if _ring_runs_along_x(x, z, fence) else z
			var post := along % FENCE_POST_PITCH == 0
			brush.set_vox(Vector3i(x, deck, z), VoxelMaterial.ZOO_FENCE_FRAME)
			for y in range(deck + 1, top + 1):
				var mat := VoxelMaterial.ZOO_FENCE_FRAME
				if FENCE_LINE_OFFSETS.has(y - deck):
					## Full-thickness red bands — these are the ring you see from the gate.
					mat = VoxelMaterial.ZOO_FENCE_LINE
				elif depth == 0 and not post and y != top and y != deck + 1:
					## Outer pane only between posts and rails; never the whole wall.
					mat = VoxelMaterial.ZOO_FENCE_GLASS
				brush.set_vox(Vector3i(x, y, z), mat)
	brush.end_edit()


## How many voxels in from the outer face this column sits, or -1 when it is not ring.
func _ring_depth(x: int, z: int, fence: Rect2i) -> int:
	var dx := mini(x - fence.position.x, fence.end.x - 1 - x)
	var dz := mini(z - fence.position.y, fence.end.y - 1 - z)
	var d := mini(dx, dz)
	if d < 0 or d >= FENCE_THICK:
		return -1
	return d


func _ring_runs_along_x(x: int, z: int, fence: Rect2i) -> bool:
	var dz := mini(z - fence.position.y, fence.end.y - 1 - z)
	var dx := mini(x - fence.position.x, fence.end.x - 1 - x)
	return dz <= dx


func _build_gate_and_plaza() -> void:
	var deck := layout.deck_y
	var g := layout.gate_rect
	## Open the ring, then hang a frame arch on the opening so it reads as a doorway.
	brush.fill_box(
		Vector3i(g.position.x, deck + 1, g.position.y),
		Vector3i(g.end.x, layout.fence_top_y + 1, g.end.y),
		VoxelMaterial.AIR
	)
	brush.fill_box(
		Vector3i(g.position.x, deck, g.position.y),
		Vector3i(g.end.x, deck + 1, g.end.y),
		VoxelMaterial.GRAVEL
	)
	var lintel := deck + 9
	brush.fill_box(
		Vector3i(g.position.x, lintel, g.position.y),
		Vector3i(g.end.x, lintel + 1, g.end.y),
		VoxelMaterial.ZOO_FENCE_FRAME
	)
	brush.fill_box(
		Vector3i(g.position.x, lintel + 1, g.position.y),
		Vector3i(g.end.x, lintel + 2, g.end.y),
		VoxelMaterial.ZOO_FENCE_LINE
	)
	var plaza := layout.plaza_rect
	if plaza.size.x > 0 and plaza.size.y > 0:
		brush.fill_box(
			Vector3i(plaza.position.x, deck, plaza.position.y),
			Vector3i(plaza.end.x, deck + 1, plaza.end.y),
			VoxelMaterial.GRAVEL
		)
	## Walk from the opening onto the apron.
	var gate_mid := Vector2i(
		g.position.x + g.size.x / 2, g.position.y + g.size.y / 2
	)
	for step in range(0, PLAZA_DEPTH):
		var p := gate_mid + layout.gate_dir * step
		brush.fill_disk(p.x, p.y, deck, GATE_HALF - 1, VoxelMaterial.GRAVEL)
	_build_plaza_panes(gate_mid)


## Invisible viewing panes across the field-facing lip of the plaza: a sightseer standing
## on the apron cannot be shot from the field, and cannot shoot into it either. The walkway
## itself is left open, so stepping off the apron is stepping into the war.
func _build_plaza_panes(gate_mid: Vector2i) -> void:
	var plaza := layout.plaza_rect
	if plaza.size.x <= 0 or plaza.size.y <= 0:
		return
	var dir := layout.gate_dir
	var deck := layout.deck_y
	var y1 := deck + 1 + PLAZA_VEIL_H
	var along_x := dir.x == 0
	var lo := plaza.position.x if along_x else plaza.position.y
	var hi := plaza.end.x if along_x else plaza.end.y
	var open_at := gate_mid.x if along_x else gate_mid.y
	var lip := 0
	if dir.y > 0:
		lip = plaza.end.y - 1
	elif dir.y < 0:
		lip = plaza.position.y
	elif dir.x > 0:
		lip = plaza.end.x - 1
	else:
		lip = plaza.position.x
	for t in range(lo, hi):
		if absi(t - open_at) <= GATE_HALF:
			continue
		var x := t if along_x else lip
		var z := lip if along_x else t
		brush.fill_box(
			Vector3i(x, deck + 1, z),
			Vector3i(x + 1, y1, z + 1),
			VoxelMaterial.LOS_VEIL
		)


# --- battlefield scatter ----------------------------------------------------

## Old-town terraces dropped across the field. They go up whole; the blast pass is what
## turns them into shells.
func _scatter_houses() -> int:
	var field := layout.field_rect.grow(-8)
	var want := _budget(HOUSE_PER_AREA)
	var made := 0
	var tries := want * 40
	while made < want and tries > 0:
		tries -= 1
		var w := HOUSE_MIN_W + rng.randi() % (HOUSE_MAX_W - HOUSE_MIN_W + 1)
		var d := HOUSE_MIN_W + rng.randi() % (HOUSE_MAX_W - HOUSE_MIN_W + 1)
		if field.size.x <= w + 2 or field.size.y <= d + 2:
			break
		var x0 := field.position.x + rng.randi() % (field.size.x - w)
		var z0 := field.position.y + rng.randi() % (field.size.y - d)
		var plot := Rect2i(x0, z0, w, d)
		if not _area_free(plot.grow(2)):
			continue
		_claim_rect(plot.grow(2))
		_build_house(plot)
		_house_rects.append(plot)
		made += 1
	return made


func _build_house(plot: Rect2i) -> void:
	var deck := layout.deck_y
	var wall_mat := HOUSE_WALL_MATS[rng.randi() % HOUSE_WALL_MATS.size()]
	var roof_mat := HOUSE_ROOF_MATS[rng.randi() % HOUSE_ROOF_MATS.size()]
	var wall_h := 11 + rng.randi() % 7
	var wall_top := deck + wall_h
	brush.begin_edit()
	## Footing and ground floor.
	brush.fill_box(
		Vector3i(plot.position.x, deck, plot.position.y),
		Vector3i(plot.end.x, deck + 1, plot.end.y),
		VoxelMaterial.STONE
	)
	## Single-voxel shell so a blast opens the façade instead of chewing a solid block.
	for z in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			var edge := (
				x == plot.position.x or x == plot.end.x - 1
				or z == plot.position.y or z == plot.end.y - 1
			)
			if not edge:
				continue
			brush.fill_box(
				Vector3i(x, deck + 1, z), Vector3i(x + 1, wall_top + 1, z + 1), wall_mat
			)
	_punch_house_openings(plot, wall_top)
	_build_house_roof(plot, wall_top, roof_mat)
	brush.end_edit()


func _punch_house_openings(plot: Rect2i, wall_top: int) -> void:
	var deck := layout.deck_y
	## One door on a random wall, then windows scattered along every face.
	var door_side := rng.randi() % 4
	var door_x := plot.position.x + 1 + rng.randi() % maxi(plot.size.x - 2, 1)
	var door_z := plot.position.y + 1 + rng.randi() % maxi(plot.size.y - 2, 1)
	match door_side:
		0:
			_clear_opening(door_x, plot.position.y, 2, 1, deck + 1, 5)
		1:
			_clear_opening(door_x, plot.end.y - 1, 2, 1, deck + 1, 5)
		2:
			_clear_opening(plot.position.x, door_z, 1, 2, deck + 1, 5)
		_:
			_clear_opening(plot.end.x - 1, door_z, 1, 2, deck + 1, 5)
	var windows := 4 + rng.randi() % 5
	for _i in range(windows):
		var y := deck + 4 + rng.randi() % maxi(wall_top - deck - 6, 1)
		if rng.randi() % 2 == 0:
			var wx := plot.position.x + 1 + rng.randi() % maxi(plot.size.x - 2, 1)
			var wz := plot.position.y if rng.randi() % 2 == 0 else plot.end.y - 1
			_clear_opening(wx, wz, 2, 1, y, 3)
		else:
			var wz2 := plot.position.y + 1 + rng.randi() % maxi(plot.size.y - 2, 1)
			var wx2 := plot.position.x if rng.randi() % 2 == 0 else plot.end.x - 1
			_clear_opening(wx2, wz2, 1, 2, y, 3)


func _clear_opening(x: int, z: int, w: int, d: int, y0: int, h: int) -> void:
	brush.fill_box(Vector3i(x, y0, z), Vector3i(x + w, y0 + h, z + d), VoxelMaterial.AIR)


## Stepped gable: cheap, reads as a pitched roof, and collapses into the shell nicely
## once a blast takes the ridge off.
func _build_house_roof(plot: Rect2i, wall_top: int, roof_mat: int) -> void:
	var steps := mini(plot.size.x, plot.size.y) / 2
	for k in range(steps):
		var band := plot.grow(-k)
		if band.size.x <= 0 or band.size.y <= 0:
			break
		var y := wall_top + 1 + k
		brush.fill_box(
			Vector3i(band.position.x, y, band.position.y),
			Vector3i(band.end.x, y + 1, band.end.y),
			roof_mat
		)


## A few bandstands. They are the most fragile thing out here and are meant to end up
## as a ring of stumps under a broken roof.
func _scatter_gazebos() -> int:
	var field := layout.field_rect.grow(-10)
	var want := _budget(GAZEBO_PER_AREA)
	var made := 0
	var tries := want * 40
	while made < want and tries > 0:
		tries -= 1
		if field.size.x <= 14 or field.size.y <= 14:
			break
		var cx := field.position.x + rng.randi() % field.size.x
		var cz := field.position.y + rng.randi() % field.size.y
		var plot := Rect2i(cx - 5, cz - 5, 11, 11)
		if not _area_free(plot.grow(2)):
			continue
		_claim_rect(plot.grow(2))
		_build_gazebo(cx, cz)
		made += 1
	return made


func _build_gazebo(cx: int, cz: int) -> void:
	var deck := layout.deck_y
	var post_top := deck + 9
	brush.begin_edit()
	brush.fill_disk(cx, cz, deck, 5, VoxelMaterial.TILES)
	## Skip the south arc (i = 4,5) so the ring has a real walk-out, not a closed cage.
	for i in range(8):
		if i == 4 or i == 5:
			continue
		var a := TAU * float(i) / 8.0
		var px := cx + int(round(cos(a) * 4.0))
		var pz := cz + int(round(sin(a) * 4.0))
		brush.fill_box(
			Vector3i(px, deck + 1, pz),
			Vector3i(px + 1, post_top + 1, pz + 1),
			VoxelMaterial.TIMBER
		)
	brush.fill_disk(cx, cz, post_top + 1, 5, VoxelMaterial.ROOF_CLAY)
	brush.fill_disk(cx, cz, post_top + 2, 3, VoxelMaterial.ROOF_CLAY)
	brush.fill_disk(cx, cz, post_top + 3, 1, VoxelMaterial.ROOF_CLAY)
	brush.end_edit()


func _scatter_trees() -> int:
	var stamper := TreeStamper.new()
	stamper.brush = brush
	stamper.rng = rng
	## Trees here are scenery in a fight, not a gem crop.
	stamper.allow_canopy_gems = false
	var field := layout.field_rect.grow(-6)
	var want := _budget(TREE_PER_AREA)
	var made := 0
	var tries := want * 30
	while made < want and tries > 0:
		tries -= 1
		var x := field.position.x + rng.randi() % maxi(field.size.x, 1)
		var z := field.position.y + rng.randi() % maxi(field.size.y, 1)
		var plot := Rect2i(x - 3, z - 3, 7, 7)
		if not _area_free(plot):
			continue
		_claim_rect(plot)
		stamper.plant_random(x, layout.deck_y, z)
		made += 1
	return made


func _scatter_gravestones() -> int:
	var field := layout.field_rect.grow(-6)
	var deck := layout.deck_y
	var want := _budget(GRAVE_PER_AREA)
	var made := 0
	var tries := want * 25
	brush.begin_edit()
	while made < want and tries > 0:
		tries -= 1
		var x := field.position.x + rng.randi() % maxi(field.size.x, 1)
		var z := field.position.y + rng.randi() % maxi(field.size.y, 1)
		var plot := Rect2i(x - 1, z - 1, 4, 4)
		if not _area_free(plot):
			continue
		_claim_rect(plot)
		brush.fill_box(
			Vector3i(x - 1, deck, z - 1),
			Vector3i(x + 3, deck + 1, z + 3),
			VoxelMaterial.GRAVE_SOIL
		)
		if rng.randf() < 0.22:
			## Obelisk — the tall marker that still shows over a crater lip.
			brush.fill_box(
				Vector3i(x, deck + 1, z),
				Vector3i(x + 1, deck + 6, z + 1),
				VoxelMaterial.GRAVE_MARBLE
			)
		else:
			brush.fill_box(
				Vector3i(x, deck + 1, z),
				Vector3i(x + 2, deck + 3, z + 1),
				VoxelMaterial.GRAVE_STONE
			)
		made += 1
	brush.end_edit()
	return made


# --- battlefield scars ------------------------------------------------------

## Big charged blasts, mostly aimed through the houses. Same sphere the player's charged
## blast carves, at the top of its radius band.
func _scar_charged_blasts() -> int:
	var field := layout.field_rect.grow(-4)
	var want := _budget(BLAST_PER_AREA)
	for _i in range(want):
		var r := BLAST_R_MIN + rng.randi() % (BLAST_R_MAX - BLAST_R_MIN + 1)
		var at := Vector2i(
			field.position.x + rng.randi() % maxi(field.size.x, 1),
			field.position.y + rng.randi() % maxi(field.size.y, 1)
		)
		if not _house_rects.is_empty() and rng.randf() < BLAST_AT_HOUSE_P:
			var house: Rect2i = _house_rects[rng.randi() % _house_rects.size()]
			at = Vector2i(
				house.position.x + rng.randi() % house.size.x,
				house.position.y + rng.randi() % house.size.y
			)
		## Sunk just under the wall line: the blast opens the façade *and* leaves a crater.
		var cy := layout.deck_y + int(round(float(r) * 0.45))
		_carve_sphere(at.x, cy, at.y, r)
		_ring_debris(at.x, at.y, r + 1, VoxelMaterial.GRAVEL)
	return want


## Foot craters: shallow, wide and everywhere, so the ground never reads as poured flat.
func _scar_stomps() -> int:
	var field := layout.field_rect.grow(-3)
	var want := _budget(STOMP_PER_AREA)
	for _i in range(want):
		var r := STOMP_R_MIN + rng.randi() % (STOMP_R_MAX - STOMP_R_MIN + 1)
		var x := field.position.x + rng.randi() % maxi(field.size.x, 1)
		var z := field.position.y + rng.randi() % maxi(field.size.y, 1)
		var depth := 1 + rng.randi() % 3
		_carve_crater(x, z, r, depth)
		_ring_debris(x, z, r, VoxelMaterial.DIRT)
	return want


func _carve_sphere(cx: int, cy: int, cz: int, radius: int) -> void:
	var r2 := radius * radius
	var y0 := maxi(cy - radius, layout.deck_y - CRATER_MAX_DEPTH)
	var y1 := cy + radius
	brush.begin_edit()
	for y in range(y0, y1 + 1):
		for z in range(cz - radius, cz + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				var dx := x - cx
				var dy := y - cy
				var dz := z - cz
				if dx * dx + dy * dy + dz * dz > r2:
					continue
				_clear_scar_vox(x, y, z)
	brush.end_edit()


func _carve_crater(cx: int, cz: int, radius: int, depth: int) -> void:
	var deck := layout.deck_y
	var floor_y := maxi(deck - depth, deck - CRATER_MAX_DEPTH)
	var r2 := radius * radius
	brush.begin_edit()
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			var d2 := dx * dx + dz * dz
			if d2 > r2:
				continue
			## Everything standing in the footprint goes, deck floor included only where
			## the foot actually sank — a rim that clears its own ground leaves a moat.
			for y in range(deck + 1, deck + 4):
				_clear_scar_vox(x, y, z)
			## Bowl, not a cylinder: the rim only sinks a voxel or two.
			var bite := int(round(float(depth) * (1.0 - sqrt(float(d2)) / float(radius))))
			for y in range(maxi(deck - bite + 1, floor_y), deck + 1):
				_clear_scar_vox(x, y, z)
	brush.end_edit()


## One cell of a scar. The containment ring, the bedrock band and everything the masks
## protect survive; anything else the world would ever yield is removed.
func _clear_scar_vox(x: int, y: int, z: int) -> void:
	if y < 1:
		return
	if _is_protected(x, z):
		return
	var id := brush.get_vox(Vector3i(x, y, z))
	if id == VoxelMaterial.AIR or id == VoxelMaterial.BEDROCK:
		return
	if VoxelMaterial.is_zoo_fence(id):
		return
	brush.set_vox(Vector3i(x, y, z), VoxelMaterial.AIR)


## Thrown-out spoil around a crater mouth, so the lip is not a clean circle in the dirt.
func _ring_debris(cx: int, cz: int, radius: int, mat: int) -> void:
	var deck := layout.deck_y
	var outer := radius + 2
	brush.begin_edit()
	for z in range(cz - outer, cz + outer + 1):
		for x in range(cx - outer, cx + outer + 1):
			var dx := x - cx
			var dz := z - cz
			var d2 := dx * dx + dz * dz
			if d2 <= radius * radius or d2 > outer * outer:
				continue
			if _is_protected(x, z):
				continue
			if rng.randf() > 0.45:
				continue
			if brush.get_vox(Vector3i(x, deck, z)) == VoxelMaterial.AIR:
				continue
			brush.set_vox(Vector3i(x, deck, z), mat)
	brush.end_edit()


# --- turf and pads ----------------------------------------------------------

## Home ground as short 2×2 glowing slabs with a slightly taller rim — same cell as the
## dirt, just not as tall. Densest near each seed, sparse at the borders.
func _stamp_turf_plates() -> void:
	if layout.seed_xz.is_empty():
		return
	var field := layout.field_rect.grow(-(PLATE_FOOT + 2))
	if field.size.x <= PLATE_FOOT or field.size.y <= PLATE_FOOT:
		return
	var radius := float(maxi(layout.seed_radius_vox, 1))
	var want := _budget(PLATE_PER_AREA)
	var stamped := 0
	var tries := want * 50
	brush.begin_edit()
	while stamped < want and tries > 0:
		tries -= 1
		var x0 := field.position.x + rng.randi() % maxi(field.size.x - PLATE_FOOT + 1, 1)
		var z0 := field.position.y + rng.randi() % maxi(field.size.y - PLATE_FOOT + 1, 1)
		var cx := x0 + PLATE_FOOT / 2
		var cz := z0 + PLATE_FOOT / 2
		if _is_protected(cx, cz):
			continue
		var t := layout.territory_at_local(cx, cz)
		if t < 0:
			continue
		var s := layout.seed_xz[t]
		var dx := float(cx - s.x)
		var dz := float(cz - s.y)
		var d := sqrt(dx * dx + dz * dz) / radius
		if d >= 1.0:
			continue
		## Prefer cores; borders stay almost bare so territories still mingle.
		if rng.randf() >= pow(1.0 - d, PLATE_CORE_BIAS):
			continue
		if not _place_turf_pad(
			x0, z0, VoxelMaterial.zoo_turf_for_faction_index(layout.seed_faction[t])
		):
			continue
		stamped += 1
	brush.end_edit()
	print(
		"ZooComposer: %d short turf pads over %d territories (seed radius %d vox)"
		% [stamped, layout.territory_count(), layout.seed_radius_vox]
	)


## One deliberate pad on the surface cell: short glowing 2×2, short dark rim around it.
## No digging into the cell below — the mesh height is what makes them sit low.
func _place_turf_pad(x0: int, z0: int, turf: int) -> bool:
	var top := _surface_y(x0, z0)
	if top < 0:
		return false
	for z in range(z0, z0 + PLATE_FOOT):
		for x in range(x0, x0 + PLATE_FOOT):
			if _is_protected(x, z):
				return false
			if _surface_y(x, z) != top:
				return false
			var id := brush.get_vox(Vector3i(x, top, z))
			if not _plateable(id):
				return false
			if id == VoxelMaterial.ZOO_PLATE_RIM or VoxelMaterial.is_zoo_turf(id):
				return false
	var inner0 := x0 + PLATE_RIM
	var inner1 := x0 + PLATE_RIM + PLATE_GLOW
	var inz0 := z0 + PLATE_RIM
	var inz1 := z0 + PLATE_RIM + PLATE_GLOW
	for z in range(z0, z0 + PLATE_FOOT):
		for x in range(x0, x0 + PLATE_FOOT):
			var edge := x < inner0 or x >= inner1 or z < inz0 or z >= inz1
			if edge:
				brush.set_vox(Vector3i(x, top, z), VoxelMaterial.ZOO_PLATE_RIM)
			else:
				brush.set_vox(Vector3i(x, top, z), turf)
	return true


## Only loose ground takes a plate — never a roof, a headstone or a house floor.
func _plateable(id: int) -> bool:
	return (
		id == VoxelMaterial.DIRT
		or id == VoxelMaterial.GRAVEL
		or id == VoxelMaterial.PARK
		or id == VoxelMaterial.GRAVE_SOIL
	)


## Topmost solid voxel in this column within reach of the deck, or -1 when the crater under
## it went deeper than a plate should follow.
func _surface_y(x: int, z: int) -> int:
	var deck := layout.deck_y
	for y in range(deck + 3, deck - CRATER_MAX_DEPTH - 1, -1):
		if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
			return y
	return -1


## One open summon gazebo per territory: a bandstand the bodies arrive under, with
## entrances on the chamfers so a fight can spill through. Built after the scars so the
## deck is always flat — the forever war needs somewhere clean to land.
func _build_spawn_pads() -> void:
	brush.begin_edit()
	for i in range(layout.spawner_vox.size()):
		_build_summon_gazebo(
			layout.spawner_vox[i],
			VoxelMaterial.zoo_turf_for_faction_index(layout.seed_faction[i])
		)
	brush.end_edit()


func _build_summon_gazebo(pad: Vector3i, turf: int) -> void:
	var deck := layout.deck_y
	var centre := Vector2i(pad.x, pad.z)
	var rim: Array[Vector2i] = []
	for dz in range(-PAD_HALF, PAD_HALF + 1):
		for dx in range(-PAD_HALF, PAD_HALF + 1):
			if absi(dx) + absi(dz) > PAD_HALF * 2 - PAD_CHAMFER:
				continue
			var x := centre.x + dx
			var z := centre.y + dz
			brush.fill_box(
				Vector3i(x, deck - 1, z), Vector3i(x + 1, deck, z + 1), VoxelMaterial.STONE
			)
			## Owner colour on the deck — the glow that says whose station this is.
			var floor_mat := turf if maxi(absi(dx), absi(dz)) <= 2 else VoxelMaterial.TILES
			brush.set_vox(Vector3i(x, deck, z), floor_mat)
			if maxi(absi(dx), absi(dz)) == PAD_HALF:
				rim.append(Vector2i(dx, dz))
	## Clear the arrival cell so a body is not born inside a tile.
	brush.set_vox(Vector3i(centre.x, deck, centre.y), turf)
	var column_top := deck + PAD_COLUMN_H
	for offset: Vector2i in rim:
		if not _summon_column_at(offset):
			continue
		brush.fill_box(
			Vector3i(centre.x + offset.x, deck + 1, centre.y + offset.y),
			Vector3i(centre.x + offset.x + 1, column_top + 1, centre.y + offset.y + 1),
			VoxelMaterial.ZOO_FENCE_FRAME
		)
		## Lit cap so the station reads as a summon ring, not a park bandstand.
		brush.set_vox(
			Vector3i(centre.x + offset.x, column_top + 1, centre.y + offset.y),
			VoxelMaterial.ZOO_FENCE_LINE
		)
	_build_summon_roof(centre, column_top, turf)


## Two posts per face at the ends — every side keeps a walkable middle so spawned
## bodies can leave the station instead of rattling around inside a cage.
func _summon_column_at(offset: Vector2i) -> bool:
	var ax := absi(offset.x)
	var az := absi(offset.y)
	var on_ns := az == PAD_HALF and ax < PAD_HALF
	var on_ew := ax == PAD_HALF and az < PAD_HALF
	if not on_ns and not on_ew:
		return false
	var along := ax if on_ns else az
	return along == PAD_HALF - PAD_POST_INSET


func _build_summon_roof(centre: Vector2i, column_top: int, turf: int) -> void:
	var y := column_top + 1
	var half := PAD_HALF
	for step in range(PAD_ROOF_H):
		for dz in range(-half, half + 1):
			for dx in range(-half, half + 1):
				if absi(dx) + absi(dz) > half * 2 - PAD_CHAMFER:
					continue
				## Outer ring of the lowest roof course is the energy rail.
				var mat := VoxelMaterial.ROOF_CLAY
				if step == 0 and maxi(absi(dx), absi(dz)) == half:
					mat = VoxelMaterial.ZOO_FENCE_LINE
				brush.set_vox(Vector3i(centre.x + dx, y, centre.y + dz), mat)
		y += 1
		half -= 1
		if half < 1:
			break
	brush.set_vox(Vector3i(centre.x, y, centre.y), turf)
