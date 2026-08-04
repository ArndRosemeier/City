## Japanese-garden dressing for the Go zone of a Gaming plaza.
##
## Torii gates on the four approaches, stone lanterns along the walk and on the giant
## board's apron corners, a raked gravel court with a rock group, a koi pond with an
## arched crossing, clipped shrubs and pines.
##
## Deliberately bounded to a band around the board pad and the play table. The composer
## wraps Go + Tetris + chess in a zoo fence and maze-fills outside that ring; this band
## is published as `GamingLayout.garden_min/garden_max` so satellites and the ring share
## one footprint.
class_name GamingGarden
extends RefCounted

## How far the garden reaches past the Go furniture, in voxels (0.5 m each).
const BAND := 16
## Walk-through kept free of props: spawn → table → board pad. Half-width in voxels.
const CORRIDOR_HW := 6

## Torii (myōjin style): clear opening, post thickness, clear height under the tie beam.
const TORII_GAP := 10
const TORII_POST_T := 2
const TORII_CLEAR_H := 9
## The tie beam (nuki) overhangs the posts a little and the top rail (kasagi) further,
## whose ends then lift a voxel — that upward sweep is what reads as "torii" at distance.
const TORII_NUKI_OUT := 2
const TORII_KASAGI_OUT := 4
const TORII_KASAGI_T := 2
## Vermillion. ROOF_CLAY is the palette's only dependable red-orange; PAINT only jitters
## brightness around whatever its atlas base is, so a "red" gate would drift per tile.
const TORII_MAT := VoxelMaterial.ROOF_CLAY
const TORII_FOOT_MAT := VoxelMaterial.STONE

## Fence wing (sode-gaki) flanking a gate: length either side, height, post pitch.
const WING_LEN := 9
const WING_H := 4
const WING_PITCH := 3
const WING_MAT := VoxelMaterial.PLANTER

## Raked bed: every third ripple ring around the rock group is combed pale.
const RAKE_PITCH := 3
const RAKE_MAT := VoxelMaterial.SIDEWALK
const BED_MAT := VoxelMaterial.GRAVEL

## Planting for the near pass. Shrubs come in clumps: singles scattered over a band this
## wide read as weeds, while grouped domes read as clipped karikomi.
const PINES := 14
const BLOSSOMS := 8
const SHRUB_CLUMPS := 12
const SHRUBS_PER_CLUMP := 4
## Rejection sampling gives up rather than looping forever on a crowded band.
const PLACE_TRIES := 40
## `_free_spot` sentinel for "the band had no room left".
const NO_SPOT := -2147483648

var brush: CityBrush
var rng: RandomNumberGenerator
var stamper: TreeStamper
var ground_y: int = 6
## Table footprint, passed in by the composer. Reading GamingComposer's constants from
## here would make the two scripts cyclic.
var table_w: int = 18
var table_d: int = 10

var _layout: GamingLayout = null
## District-local voxel bounds of the Gaming reserve (XZ only, max exclusive).
var _bounds: Rect2i = Rect2i()
## The garden band itself, clipped to `_bounds`.
var _band: Rect2i = Rect2i()
## Footprints something already owns, so planting never grows out of a rock or a table.
var _claimed: Array[Rect2i] = []
var _gates_built: int = 0
var _lanterns_built: int = 0
var _plants: int = 0


## Publish `garden_min` / `garden_max` from pad + table without dressing. GamingComposer
## needs the band before the maze so it can cut the Go installment hole.
func plan_band(layout: GamingLayout, min_v: Vector3i, max_v: Vector3i) -> bool:
	if layout == null:
		push_error("GamingGarden: no layout")
		return false
	if min_v.x >= max_v.x or min_v.z >= max_v.z:
		push_error("GamingGarden: empty bounds %s..%s" % [min_v, max_v])
		return false
	_layout = layout
	_bounds = Rect2i(min_v.x, min_v.z, max_v.x - min_v.x, max_v.z - min_v.z)
	var pad := _pad_rect()
	var table := _table_rect()
	var core := pad.merge(table)
	_band = core.grow(BAND).intersection(_bounds)
	if _band.size.x <= 0 or _band.size.y <= 0:
		push_error("GamingGarden: garden band falls outside the reserve")
		return false
	_layout.garden_min = Vector3i(_band.position.x, ground_y, _band.position.y)
	_layout.garden_max = Vector3i(_band.end.x, ground_y + 1, _band.end.y)
	return true


## Full dressing for a walk-up district.
func decorate(layout: GamingLayout, min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(layout, min_v, max_v):
		return
	_lay_walk()
	_build_court()
	_build_pond()
	_build_gates()
	_place_lanterns()
	_plant(PINES, BLOSSOMS, SHRUB_CLUMPS)
	print(
		"GamingGarden: band=%s gates=%d lanterns=%d plants=%d"
		% [_band, _gates_built, _lanterns_built, _plants]
	)


## Horizon pass: only what has a silhouette worth streaming in from far away.
func decorate_far(layout: GamingLayout, min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(layout, min_v, max_v):
		return
	_build_gates()
	_plant(4, 0, 0)


func _begin(layout: GamingLayout, min_v: Vector3i, max_v: Vector3i) -> bool:
	if brush == null or rng == null:
		push_error("GamingGarden: brush / rng not set")
		return false
	if not plan_band(layout, min_v, max_v):
		return false
	_claimed = []
	_gates_built = 0
	_lanterns_built = 0
	_plants = 0

	## Nothing plants on the board pad, on the table, or in the walk between them.
	_claimed.append(_pad_rect().grow(2))
	_claimed.append(_table_rect().grow(3))
	_claimed.append(_corridor_rect())
	return true


func _pad_rect() -> Rect2i:
	var p0 := _layout.pad_min
	var p1 := _layout.pad_max
	return Rect2i(p0.x, p0.z, p1.x - p0.x, p1.z - p0.z)


func _table_rect() -> Rect2i:
	var o := _layout.main_table_origin
	return Rect2i(o.x, o.z, table_w, table_d)


## Approach lane: south of the table up to the pad's south edge, then it meets the apron.
func _corridor_rect() -> Rect2i:
	var table := _table_rect()
	var cx := table.position.x + table.size.x / 2
	return Rect2i(
		cx - CORRIDOR_HW,
		_band.position.y,
		CORRIDOR_HW * 2,
		_layout.pad_min.z - _band.position.y
	)


## Stepping stones (tobi-ishi) up the approach, and a gravel walk around the table.
func _lay_walk() -> void:
	var table := _table_rect()
	var cx := table.position.x + table.size.x / 2
	## Gravel verge hugging the table, so the timber deck sits in a court rather than on
	## bare lawn. Kept narrow — the corridor stays the thing you walk on.
	_fill_ground(table.grow(3), BED_MAT)
	## Stones every third voxel: south approach, then the gap between table and pad.
	var z := _band.position.y + 2
	while z < table.position.y - 1:
		_stepping_stone(cx, z)
		z += RAKE_PITCH
	z = table.end.y + 1
	while z < _layout.pad_min.z:
		_stepping_stone(cx, z)
		z += RAKE_PITCH


## One metre square, so it reads as a laid stone rather than a strip of paving.
func _stepping_stone(cx: int, cz: int) -> void:
	_fill_ground(Rect2i(cx - 1, cz, 2, 2), VoxelMaterial.STONE)


## Dry court (karesansui) west of the table, paired with the pond to its east. Both live
## in the forecourt strip between the approach and the pad, never under either of them.
func _build_court() -> void:
	var table := _table_rect()
	var bed_w := 20
	var bed_d := 16
	_rock_court(
		Rect2i(table.position.x - 6 - bed_w, table.position.y - 2, bed_w, bed_d)
	)


## Gravel bed, one rock group, and pale ripple rings combed around it. The rings are
## built by scanning the bed, so they are clipped to it and never spill onto the lawn.
func _rock_court(bed: Rect2i) -> void:
	var clipped := bed.intersection(_band)
	if clipped.size.x < 8 or clipped.size.y < 8:
		return
	_fill_ground(clipped, BED_MAT)
	var focus := Vector2i(
		clipped.position.x + clipped.size.x / 2,
		clipped.position.y + clipped.size.y / 2
	)
	brush.begin_edit()
	for z in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var dx := x - focus.x
			var dz := z - focus.y
			var d := int(round(sqrt(float(dx * dx + dz * dz))))
			if d >= 4 and d % RAKE_PITCH == 0:
				brush.set_vox(Vector3i(x, ground_y, z), RAKE_MAT)
	brush.end_edit()
	## Classic uneven triad: one tall stone with two lower companions.
	_rock(focus.x, focus.y, 3)
	_rock(focus.x - 3, focus.y + 2, 2)
	_rock(focus.x + 2, focus.y - 3, 1)
	_claimed.append(clipped)


## Half-buried garden rock — placed, not dropped.
func _rock(x: int, z: int, r: int) -> void:
	brush.fill_ellipsoid(
		Vector3i(x, ground_y + 1, z), Vector3i(r + 1, r, r), VoxelMaterial.STONE
	)


## Koi pond east of the table: set stones around the lip, a metre of water, plank crossing.
func _build_pond() -> void:
	var table := _table_rect()
	var rx := 9
	var rz := 6
	var cx := table.end.x + 6 + rx
	var cz := table.position.y + 5
	var foot := Rect2i(cx - rx - 2, cz - rz - 2, (rx + 2) * 2, (rz + 2) * 2)
	if not _band.encloses(foot) or _overlaps_claimed(foot):
		return
	var fx := float(rx)
	var fz := float(rz)
	brush.begin_edit()
	for z in range(cz - rz - 1, cz + rz + 2):
		for x in range(cx - rx - 1, cx + rx + 2):
			var nx := float(x - cx) / fx
			var nz := float(z - cz) / fz
			var d := nx * nx + nz * nz
			if d > 1.35:
				continue
			if d > 1.0:
				## Set stones around the lip rather than a poured kerb.
				brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.STONE)
				continue
			brush.set_vox(Vector3i(x, ground_y - 1, z), VoxelMaterial.WATER)
			brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.WATER)
	brush.end_edit()
	_bridge(cx, cz, rz)
	## Lanterns read best mirrored in water.
	_lantern(cx - rx - 1, cz - rz - 1)
	_lantern(cx + rx, cz + rz)
	_claimed.append(foot)


## Arched plank crossing (taiko-bashi) over the pond's short axis. The camber is what
## separates a bridge from a plank lying in the water — one voxel of rise per two of run,
## flattened over the middle so it is still walkable.
func _bridge(cx: int, cz: int, rz: int) -> void:
	var span := rz + 1
	brush.begin_edit()
	for dz in range(-span, span + 1):
		var t := 1.0 - absf(float(dz)) / float(span)
		var rise := int(round(t * 2.0))
		var z := cz + dz
		for dx in range(-1, 2):
			for y in range(ground_y + 1, ground_y + 2 + rise):
				brush.set_vox(Vector3i(cx + dx, y, z), VoxelMaterial.TIMBER)
		## Kerb rails so the deck edge catches light instead of reading as a black slab.
		brush.set_vox(Vector3i(cx - 2, ground_y + 1 + rise, z), VoxelMaterial.PLANTER)
		brush.set_vox(Vector3i(cx + 2, ground_y + 1 + rise, z), VoxelMaterial.PLANTER)
	brush.end_edit()


## Torii on each approach that fits inside the reserve.
func _build_gates() -> void:
	var pad := _pad_rect()
	var table := _table_rect()
	var cx := table.position.x + table.size.x / 2
	var pad_cz := pad.position.y + pad.size.y / 2
	## South is the walk-up from the spawn, so it gets the tall gate.
	_torii(Vector3i(cx, ground_y + 1, table.position.y - 12), true, TORII_GAP + 2, TORII_CLEAR_H + 2)
	_torii(Vector3i(cx, ground_y + 1, pad.end.y + 6), true, TORII_GAP, TORII_CLEAR_H)
	_torii(Vector3i(pad.position.x - 6, ground_y + 1, pad_cz), false, TORII_GAP, TORII_CLEAR_H)
	_torii(Vector3i(pad.end.x + 6, ground_y + 1, pad_cz), false, TORII_GAP, TORII_CLEAR_H)


## `center` is the gate's middle at the first air voxel. `axis_x` spans the gate across
## X (you walk through along Z); otherwise it is mirrored.
func _torii(center: Vector3i, axis_x: bool, gap: int, clear_h: int) -> void:
	var half := gap / 2
	var post_t := TORII_POST_T if gap <= 12 else 3
	var outer := half + post_t
	## Widest course is the top rail plus the fence wings it hands off to.
	var reach := outer + TORII_KASAGI_OUT + WING_LEN + 2
	var footprint: Rect2i
	if axis_x:
		footprint = Rect2i(center.x - reach, center.z - 3, reach * 2, 6)
	else:
		footprint = Rect2i(center.x - 3, center.z - reach, 6, reach * 2)
	if not _band.encloses(footprint):
		return
	var base := center.y
	var nuki_y := base + clear_h
	var kasagi_y := nuki_y + 2
	var top := kasagi_y + TORII_KASAGI_T
	var depth_lo := -post_t / 2 - 1
	var depth_hi := depth_lo + post_t

	for side_i in range(2):
		var dir := -1 if side_i == 0 else 1
		var u_in := half * dir
		var u_out := outer * dir
		var u0 := mini(u_in, u_out)
		var u1 := maxi(u_in, u_out)
		## Stone footing (kamebara), then the painted post up to the top rail.
		_gate_box(center, axis_x, u0 - 1, u1 + 1, base, base + 2, depth_lo - 1, depth_hi + 1, TORII_FOOT_MAT)
		_gate_box(center, axis_x, u0, u1, base + 2, top, depth_lo, depth_hi, TORII_MAT)

	## Tie beam pierces the posts and overhangs a little.
	var nuki := outer + TORII_NUKI_OUT
	_gate_box(center, axis_x, -nuki, nuki, nuki_y, nuki_y + 1, depth_lo, depth_hi, TORII_MAT)
	## Centre strut (gakuzuka) between tie beam and top rail.
	_gate_box(center, axis_x, 0, 1, nuki_y + 1, kasagi_y, depth_lo, depth_hi, TORII_MAT)
	## Top rail, deeper than the posts, with its ends lifted into the sweep.
	var kasagi := outer + TORII_KASAGI_OUT
	_gate_box(
		center, axis_x, -kasagi, kasagi, kasagi_y, top, depth_lo - 1, depth_hi + 1, TORII_MAT
	)
	_gate_box(
		center, axis_x, -kasagi, -kasagi + 3, top, top + 1, depth_lo - 1, depth_hi + 1, TORII_MAT
	)
	_gate_box(
		center, axis_x, kasagi - 3, kasagi, top, top + 1, depth_lo - 1, depth_hi + 1, TORII_MAT
	)
	_fence_wings(center, axis_x, kasagi)
	_lantern_pair(center, axis_x, kasagi + 2)
	_claimed.append(footprint.grow(1))
	_gates_built += 1


## Short sleeve fences either side of a gate: they frame the view instead of walling it.
func _fence_wings(center: Vector3i, axis_x: bool, from_u: int) -> void:
	var base := center.y
	for side_i in range(2):
		var dir := -1 if side_i == 0 else 1
		for step in range(0, WING_LEN, WING_PITCH):
			var u := (from_u + step) * dir
			_gate_box(center, axis_x, mini(u, u + dir), maxi(u, u + dir), base, base + WING_H, 0, 1, WING_MAT)
		var u0 := from_u * dir
		var u1 := (from_u + WING_LEN) * dir
		## Two rails between the posts.
		_gate_box(center, axis_x, mini(u0, u1), maxi(u0, u1), base + 1, base + 2, 0, 1, WING_MAT)
		_gate_box(center, axis_x, mini(u0, u1), maxi(u0, u1), base + WING_H - 1, base + WING_H, 0, 1, WING_MAT)


func _lantern_pair(center: Vector3i, axis_x: bool, u: int) -> void:
	if axis_x:
		_lantern(center.x - u, center.z)
		_lantern(center.x + u, center.z)
	else:
		_lantern(center.x, center.z - u)
		_lantern(center.x, center.z + u)


## Box in gate-local axes: `u` runs along the gate's width, `w` across its depth.
func _gate_box(
	center: Vector3i,
	axis_x: bool,
	u0: int,
	u1: int,
	y0: int,
	y1: int,
	w0: int,
	w1: int,
	mat: int
) -> void:
	if axis_x:
		brush.fill_box(
			Vector3i(center.x + u0, y0, center.z + w0),
			Vector3i(center.x + u1, y1, center.z + w1),
			mat
		)
		return
	brush.fill_box(
		Vector3i(center.x + w0, y0, center.z + u0),
		Vector3i(center.x + w1, y1, center.z + u1),
		mat
	)


## Lanterns on the board pad's apron corners and along the approach walk.
func _place_lanterns() -> void:
	var pad := _pad_rect()
	var inset := 4
	_lantern(pad.position.x + inset, pad.position.y + inset)
	_lantern(pad.end.x - inset - 1, pad.position.y + inset)
	_lantern(pad.position.x + inset, pad.end.y - inset - 1)
	_lantern(pad.end.x - inset - 1, pad.end.y - inset - 1)
	## Pairs flanking the approach, spaced so the walk is lit rather than fenced.
	var table := _table_rect()
	var cx := table.position.x + table.size.x / 2
	var z := table.position.y - 6
	while z > _band.position.y + 3:
		_lantern(cx - CORRIDOR_HW - 1, z)
		_lantern(cx + CORRIDOR_HW, z)
		z -= 12


## Stone lantern (tōrō): footing, slim shaft, a lit fire cell floating under an
## overhanging cap, finial. 3 m tall and 1.5 m across the cap — any bigger and a path
## lined with them reads as a row of monuments instead of garden lighting. The lit cell
## is deliberately one voxel: at 0.5 m cells a wider fire box swallows the cap overhang,
## which is the whole silhouette.
func _lantern(x: int, z: int) -> void:
	if not _band.encloses(Rect2i(x - 1, z - 1, 3, 3)):
		return
	var base := ground_y + 1
	brush.fill_box(
		Vector3i(x - 1, base, z - 1), Vector3i(x + 2, base + 1, z + 2), VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(x, base + 1, z), Vector3i(x + 1, base + 3, z + 1), VoxelMaterial.STONE
	)
	brush.set_vox(Vector3i(x, base + 3, z), VoxelMaterial.GLASS_LIT)
	brush.fill_box(
		Vector3i(x - 1, base + 4, z - 1), Vector3i(x + 2, base + 5, z + 2), VoxelMaterial.STONE
	)
	brush.set_vox(Vector3i(x, base + 5, z), VoxelMaterial.STONE)
	_claimed.append(Rect2i(x - 1, z - 1, 3, 3))
	_lanterns_built += 1


## Pines for silhouette, blossom trees for colour, clumps of clipped domes for the
## ground plane. Spots are rejected against everything already built, so nothing grows
## out of a lantern, a rock or the board pad.
func _plant(pines: int, blossoms: int, clumps: int) -> void:
	var tree := _tree_stamper()
	for _i in range(pines):
		var pine_at := _free_spot(4)
		if pine_at.x == NO_SPOT:
			continue
		## Layered whorls read as a garden pine, not a park lollipop.
		tree.landmark_tree(pine_at.x, ground_y, pine_at.y, rng.randf_range(7.0, 11.0))
		_claimed.append(Rect2i(pine_at.x - 4, pine_at.y - 4, 9, 9))
		_plants += 1
	for _i in range(blossoms):
		var blossom_at := _free_spot(4)
		if blossom_at.x == NO_SPOT:
			continue
		tree.round_tree(blossom_at.x, ground_y, blossom_at.y)
		_claimed.append(Rect2i(blossom_at.x - 4, blossom_at.y - 4, 9, 9))
		_plants += 1
	for _i in range(clumps):
		var seed_at := _free_spot(5)
		if seed_at.x == NO_SPOT:
			continue
		for _j in range(SHRUBS_PER_CLUMP):
			var r := 2 + rng.randi() % 2
			var at := Vector2i(
				seed_at.x + rng.randi_range(-4, 4), seed_at.y + rng.randi_range(-4, 4)
			)
			if not _band.encloses(Rect2i(at.x - r, at.y - r, r * 2 + 1, r * 2 + 1)):
				continue
			if _overlaps_claimed(Rect2i(at.x - r, at.y - r, r * 2 + 1, r * 2 + 1)):
				continue
			_shrub(at.x, at.y, r)
			_plants += 1


## Clipped shrub (karikomi): a dark dome with no trunk showing.
func _shrub(x: int, z: int, r: int) -> void:
	brush.fill_ellipsoid(
		Vector3i(x, ground_y + r, z),
		Vector3i(r, maxi(r - 1, 1), r),
		VoxelMaterial.LEAVES_DARK
	)
	_claimed.append(Rect2i(x - r, z - r, r * 2 + 1, r * 2 + 1))


## Random spot in the band whose `pad`-voxel footprint is still unclaimed.
func _free_spot(pad: int) -> Vector2i:
	for _try in range(PLACE_TRIES):
		var x := rng.randi_range(_band.position.x + pad, _band.end.x - pad - 1)
		var z := rng.randi_range(_band.position.y + pad, _band.end.y - pad - 1)
		var foot := Rect2i(x - pad, z - pad, pad * 2 + 1, pad * 2 + 1)
		if _overlaps_claimed(foot):
			continue
		return Vector2i(x, z)
	return Vector2i(NO_SPOT, NO_SPOT)


func _overlaps_claimed(foot: Rect2i) -> bool:
	for taken in _claimed:
		if taken.intersects(foot):
			return true
	return false


## Repaint one voxel course of ground inside the band.
func _fill_ground(rect: Rect2i, mat: int) -> void:
	var clipped := rect.intersection(_band)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	brush.fill_box(
		Vector3i(clipped.position.x, ground_y, clipped.position.y),
		Vector3i(clipped.end.x, ground_y + 1, clipped.end.y),
		mat
	)


func _tree_stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper
