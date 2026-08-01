## Sculpts a Hill-theme district as a slope-limited heightfield of layered rock.
##
## Hill tiles keep only short arterial stubs at the edges (see DistrictPlanner), so the
## middle is a single open massif. Terrain height is still capped by distance to the
## nearest road or tile seam: the ground ramps down to meet every connector and the
## district border stays flat so neighbouring tiles join without a step.
class_name HillComposer
extends RefCounted

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var stamper: TreeStamper
## Land-use grid — road cells come from here instead of 400k voxel probes.
var planner: DistrictPlanner
var cell_size: int = 28
## Prefer Rust paint + gems + cave carve when baking into an offline volume.
## When true there is no GDScript fallback — failures assert so crashes are visible.
## When false the original GDScript paths run (A/B / tools without a volume).
var use_native_hill: bool = true


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
		## Ore on hills comes only from the district gem quota, not tree crowns.
		stamper.allow_canopy_gems = false
	return stamper

## Flat verge kept beside every road and along the tile seam before the ground climbs.
const VERGE := 7
## Steepest average rise per horizontal voxel away from a road. Kept well under 45°:
## a voxel hill that climbs a step per column is a staircase, not a hillside.
const ROAD_SLOPE := 0.6
## Hard cap on the height step between neighbouring columns. Generous on purpose: a
## scarp has to be a couple of metres tall before any bedding is visible on it.
const MAX_STEP := 5
## Tallest summit in voxels above the deck (0.5 m each) — 36 m.
const PEAK_MAX := 72
## Columns lower than this stay flat meadow rather than a one-voxel crust.
const MIN_RELIEF := 2
## Terrain height a summit needs before it is worth boring a cave into.
const CAVE_MIN_ROOF := 20
## Half-width of corridor tunnels (rooms are deliberately wider).
const CAVE_RADIUS := 2
## Vertical carve radius for passages — must leave ≥6 air voxels above the deck so
## the walker capsule (~2.65 m to crown at 0.5 m voxels) can stand.
const CAVE_CLEARANCE_RY := 4
## How far below the street deck a crypt room may sink.
const CAVE_PIT_DEPTH := 3
## Keep this many air voxels clear of stalactites above the floor.
const CAVE_WALK_CLEARANCE := 6
## Daylight mouths must reach this low or the tunnel never breaks the hillside.
const CAVE_MOUTH_HEIGHT := 12
## Horizontal run (voxels) before a corridor must bend and sprout a side niche.
const CAVE_LONG_RUN := 16
## Max sideways swing of a meander bend, as a fraction of corridor length.
const CAVE_MEANDER_FRAC := 0.32

## ── Swiss-cheese cavern network ──
## Rock left between any cavern and the hillside surface. The skin stays solid so
## the hill still reads as a hill; only the daylight mouths are allowed through it.
const CAVE_SHELL := 6
## Lattice pitch of the cavern network. Wide cells so the halls come out big.
const CAVE_CELL_XZ := 22
const CAVE_CELL_Y := 15
const CAVE_MAX_LEVELS := 6
## Chamber half-extents — these are halls, not the old four-voxel closets.
const CAVE_ROOM_R_MIN := 6
const CAVE_ROOM_R_MAX := 11
## Extra ceiling height a chamber may roll on top of the walking clearance.
const CAVE_ROOM_RY_EXTRA := 4
## Odds of keeping a lattice edge the spanning pass did not already require.
const CAVE_LINK_P_HORZ := 0.55
const CAVE_LINK_P_VERT := 0.5
const CAVE_LINK_R_MIN := 2
const CAVE_LINK_R_MAX := 4
## Spiral shaft geometry: helix radius, and rise per full turn. 12 voxels over a
## ~44-voxel lap is one step per ~3.5 forward, inside the walker's step budget.
const CAVE_SHAFT_RADIUS := 7.0
const CAVE_SHAFT_RISE := 12
## Vertical drop that turns a "horizontal" lattice link into a spiral shaft.
const CAVE_STEEP_DROP := 7
## Share of the protected core (deck → shell) that should end up hollow.
const CAVE_HOLLOW_TARGET := 0.30

## Gem ore: one cluster seed per this many solid host voxels (interior only).
const GEM_VOXELS_PER_CLUSTER := 250
## Max cluster seeds attempted relative to the estimate (caps runaway rolls).
const GEM_CLUSTER_CAP := 880
## Keep gems off the meadow skin and the outer CAVE_SHELL band.
const GEM_SURFACE_MARGIN := 3

## Region bounds (local district voxel coords) and the per-column fields.
var _ox: int = 0
var _oz: int = 0
var _w: int = 0
var _d: int = 0
## Distance in voxels to the nearest road cell or region border.
var _clearance: PackedFloat32Array = PackedFloat32Array()
## Terrain height in voxels above the deck.
var _height: PackedInt32Array = PackedInt32Array()
## Separable bedding-plane fold, one entry per column of each axis.
var _dip_x: PackedFloat32Array = PackedFloat32Array()
var _dip_z: PackedFloat32Array = PackedFloat32Array()
## Lowest / highest voxel the cave carve opened per column (-1 = never touched), so
## dressing walks only the hollow columns instead of the whole massif bounding box.
var _cave_lo: PackedInt32Array = PackedInt32Array()
var _cave_hi: PackedInt32Array = PackedInt32Array()
## Cleared while boring a daylight mouth — the only carve allowed through the shell.
var _shell_guard: bool = true
## World-voxel positions / material ids of gem ore placed this compose (for lights).
var gem_positions: PackedVector3Array = PackedVector3Array()
var gem_mats: PackedInt32Array = PackedInt32Array()
## Exact gems to paint this bake: district constant, or constant minus harvested. Empty = none.
var gem_mats_to_place: PackedInt32Array = PackedInt32Array()
## Daylight cave mouths in *district-local* XZ (for spawn at an entrance).
var cave_mouths: PackedVector2Array = PackedVector2Array()
## Summit the mouths were bored from (district-local XZ); used to stand outside.
var cave_summit: Vector2i = Vector2i(-1, -1)
## Highest column of the massif: district-local X and Z in `x`/`z`, terrain height above the
## deck in `y`. `x` is -1 when the tile grew no hill at all. This is the true peak of the
## finished heightfield rather than a summit seed, so something standing on it is on the top.
var summit_top: Vector3i = Vector3i(-1, 0, -1)

## Rock beds from the bottom of the stack upward, repeated all the way to the summits
## so every hill in the tile shows the same geology.
var _band_mats: PackedInt32Array = PackedInt32Array()
var _band_ends: PackedInt32Array = PackedInt32Array()
var _band_cycle: int = 0


func _init() -> void:
	## Hard grey bands use STONE (destructible). BEDROCK is reserved for the world
	## floor slab — never for hillside fill, or blasting into a peak hits an immortal shelf.
	_band_mats = PackedInt32Array([
		VoxelMaterial.STONE,
		VoxelMaterial.GRAVEL,
		VoxelMaterial.BRICK,
		VoxelMaterial.DIRT,
		VoxelMaterial.STONE,
		VoxelMaterial.STONE,
		VoxelMaterial.GRAVEL,
		VoxelMaterial.BRICK,
		VoxelMaterial.DIRT,
		VoxelMaterial.STONE,
	])
	## Weighted so the grey rock carries the cliff and the buff beds read as marker
	## bands. An even split just turns every exposed face into a tan shelf.
	var thickness := PackedInt32Array([9, 2, 3, 2, 7, 6, 3, 2, 2, 8])
	if thickness.size() != _band_mats.size():
		push_error("HillComposer: strata thickness/material count mismatch")
		return
	_band_ends.resize(thickness.size())
	var acc := 0
	for i in range(thickness.size()):
		acc += thickness[i]
		_band_ends[i] = acc
	_band_cycle = acc


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	_build_clearance()
	var summits := _pick_summits()
	_build_heightfield(summits)
	_limit_steps()
	_record_summit_top()
	_report(summits)
	_paint_meadow()
	if use_native_hill:
		_paint_terrain_native()
	else:
		_paint_terrain()
	## Budget owns the count: paint exactly the remaining list, never a host-estimate ghost vein.
	_scatter_gems_from_quota()
	_carve_caves(summits)
	_scatter_boulders()
	_plant_trees(1.0)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Far tiles still need the silhouette — only the detail passes are dropped.
	if not _begin(min_v, max_v):
		return
	_build_clearance()
	var summits := _pick_summits()
	_build_heightfield(summits)
	_limit_steps()
	_record_summit_top()
	if use_native_hill:
		_paint_terrain_native()
	else:
		_paint_terrain()
	_plant_trees(0.12)


## Shape-only entry point for tools/probe_hill_height.gd — no voxels are written.
func probe_heightfield(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v, false):
		return
	_build_clearance()
	var summits := _pick_summits()
	_build_heightfield(summits)
	_limit_steps()
	_report(summits)


func probe_width() -> int:
	return _w


func probe_depth() -> int:
	return _d


func probe_heights() -> PackedInt32Array:
	return _height


func _begin(min_v: Vector3i, max_v: Vector3i, need_brush: bool = true) -> bool:
	if rng == null or (need_brush and brush == null):
		push_error("HillComposer: brush / rng not set")
		return false
	if planner == null:
		push_error("HillComposer: planner not set")
		return false
	_ox = min_v.x
	_oz = min_v.z
	_w = max_v.x - min_v.x
	_d = max_v.z - min_v.z
	if _w < 64 or _d < 64:
		push_error("HillComposer: hill region %dx%d is too small to sculpt" % [_w, _d])
		return false
	_clearance.resize(_w * _d)
	_height.resize(_w * _d)
	_cave_lo.resize(_w * _d)
	_cave_hi.resize(_w * _d)
	_cave_lo.fill(-1)
	_cave_hi.fill(-1)
	gem_positions = PackedVector3Array()
	gem_mats = PackedInt32Array()
	cave_mouths = PackedVector2Array()
	cave_summit = Vector2i(-1, -1)
	summit_top = Vector3i(-1, 0, -1)
	_shell_guard = true
	_build_bed_dip()
	return true


## Chamfer distance transform seeded from road cells and the region border, so the
## terrain can be capped by "how far is the nearest thing I must not bury".
func _build_clearance() -> void:
	const FAR := 1.0e9
	for z in range(_d):
		for x in range(_w):
			var edge := x == 0 or z == 0 or x == _w - 1 or z == _d - 1
			_clearance[z * _w + x] = 0.0 if (edge or _is_road_cell(x, z)) else FAR
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			var v := _clearance[i]
			if v == 0.0:
				continue
			if x > 0:
				v = minf(v, _clearance[i - 1] + 1.0)
			if z > 0:
				v = minf(v, _clearance[i - _w] + 1.0)
			if x > 0 and z > 0:
				v = minf(v, _clearance[i - _w - 1] + 1.4142)
			if x < _w - 1 and z > 0:
				v = minf(v, _clearance[i - _w + 1] + 1.4142)
			_clearance[i] = v
	for z in range(_d - 1, -1, -1):
		for x in range(_w - 1, -1, -1):
			var i2 := z * _w + x
			var v2 := _clearance[i2]
			if v2 == 0.0:
				continue
			if x < _w - 1:
				v2 = minf(v2, _clearance[i2 + 1] + 1.0)
			if z < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w] + 1.0)
			if x < _w - 1 and z < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w + 1] + 1.4142)
			if x > 0 and z < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w - 1] + 1.4142)
			_clearance[i2] = v2


## One massif in the middle of the tile. Edge stubs leave the centre with the most
## clearance, so the summit sits near the geometric centre (nudged toward the widest
## pocket) and its radius is sized to fill most of the open hillside.
func _pick_summits() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cx := _w / 2
	var cz := _d / 2
	var best_x := cx
	var best_z := cz
	var best_room := _clearance[cz * _w + cx]
	## Search a window around centre — do not walk the whole tile or the summit
	## drifts out to whichever stub-free corner happens to be widest.
	var window := mini(_w, _d) / 5
	var step := 4
	var z := maxi(2, cz - window)
	while z <= mini(_d - 3, cz + window):
		var x := maxi(2, cx - window)
		while x <= mini(_w - 3, cx + window):
			var room := _clearance[z * _w + x]
			if room > best_room:
				best_room = room
				best_x = x
				best_z = z
			x += step
		z += step
	if best_room < float(VERGE) + 12.0:
		push_error(
			"HillComposer: centre clearance %.1f is too tight for a summit" % best_room
		)
		return out
	var sx := clampi(best_x + rng.randi_range(-8, 8), 2, _w - 3)
	var sz := clampi(best_z + rng.randi_range(-8, 8), 2, _d - 3)
	var room2 := _clearance[sz * _w + sx]
	if room2 < best_room * 0.85:
		## Jitter landed on a stub skirt — snap back.
		sx = best_x
		sz = best_z
		room2 = best_room
	## Use most of the available cone; leave a little headroom so noise can still
	## roughen the crown without hitting the road clamp on every column.
	var peak := int((room2 - float(VERGE)) * ROAD_SLOPE * rng.randf_range(0.82, 0.95))
	## Oversized on purpose: the road/border cone is what actually stops the skirts,
	## so a generous radius lets the massif fill the open middle instead of dying as
	## a steep freestanding cone.
	var radius := room2 * rng.randf_range(2.2, 2.6)
	out.append({
		"x": sx,
		"z": sz,
		"room": room2,
		"peak": float(clampi(peak, 24, PEAK_MAX)),
		"radius": radius,
		"portal": Vector2i(-1, -1),
	})
	return out


func _build_heightfield(summits: Array[Dictionary]) -> void:
	_height.fill(0)
	if summits.is_empty():
		return
	## The summit bumps and the noise are smooth, so they are evaluated on a coarse
	## lattice and interpolated — a per-voxel fBm over 400k columns is not worth it.
	const COARSE := 2
	var cw := _w / COARSE + 2
	var cd := _d / COARSE + 2
	var coarse := PackedFloat32Array()
	coarse.resize(cw * cd)
	## Per-node multiplier on the road cone. Without it the lower slopes are a perfect
	## cone, and anything terraced on a cone comes out as concentric ziggurat steps.
	var cone := PackedFloat32Array()
	cone.resize(cw * cd)
	## Where the surface gets snapped onto the bedding planes.
	var terr := PackedFloat32Array()
	terr.resize(cw * cd)
	## Short-wavelength wobble, applied after the cone clamp — see below.
	var det := PackedFloat32Array()
	det.resize(cw * cd)
	for cz in range(cd):
		for cx in range(cw):
			var fx := float(cx * COARSE)
			var fz := float(cz * COARSE)
			cone[cz * cw + cx] = 0.7 + 0.6 * _fbm2(fx * 0.026 + 91.0, fz * 0.026 + 13.0)
			det[cz * cw + cx] = _fbm2(fx * 0.085 - 33.0, fz * 0.085 + 57.0) * 2.0 - 1.0
			terr[cz * cw + cx] = smoothstep(
				0.58, 0.70, _fbm2(fx * 0.011 + 11.0, fz * 0.011 + 7.0)
			)
			var raw := 0.0
			for s: Dictionary in summits:
				var dx := fx - float(s["x"])
				var dz := fz - float(s["z"])
				var r := float(s["radius"])
				var t := sqrt(dx * dx + dz * dz) / r
				if t >= 1.0:
					continue
				var falloff := (1.0 - t * t)
				raw += float(s["peak"]) * falloff * falloff
			if raw > 0.05:
				## Light relief only — heavy ridging used to shatter one summit into a
				## mini mountain range. Keep the dome readable as a single massif.
				var gate := clampf(raw / 8.0, 0.0, 1.0)
				var n1 := _fbm2(fx * 0.014, fz * 0.014)
				var n2 := _fbm2(fx * 0.055 + 41.0, fz * 0.055 - 29.0)
				raw *= 0.78 + 0.35 * n1
				raw += (n2 - 0.5) * 3.0 * gate
				raw += _ridge(fx * 0.02 + 3.0, fz * 0.02 - 8.0) * 5.0 * gate
			coarse[cz * cw + cx] = maxf(raw, 0.0)

	for z in range(_d):
		var fz2 := float(z) / float(COARSE)
		var cz0 := int(fz2)
		var tz := fz2 - float(cz0)
		for x in range(_w):
			var i := z * _w + x
			var room := _clearance[i]
			if room <= float(VERGE):
				continue
			var fx2 := float(x) / float(COARSE)
			var cx0 := int(fx2)
			var tx := fx2 - float(cx0)
			var ci := cz0 * cw + cx0
			var raw2 := lerpf(
				lerpf(coarse[ci], coarse[ci + 1], tx),
				lerpf(coarse[ci + cw], coarse[ci + cw + 1], tx),
				tz
			)
			var slope := lerpf(
				lerpf(cone[ci], cone[ci + 1], tx),
				lerpf(cone[ci + cw], cone[ci + cw + 1], tx),
				tz
			)
			var cap := (room - float(VERGE)) * ROAD_SLOPE * slope
			var hf := minf(raw2, cap)
			## Nearly the whole flank sits on `cap`, a smooth ramp in road distance, and all
			## the shaping noise above lives in `raw2` where the clamp discards it. Quantise
			## that ramp and every contour becomes an evenly spaced terrace, so the wobble
			## has to go on after the clamp. Fading it in over the first few metres keeps
			## the verge flat for the road.
			var wob := 0.0
			if hf > 2.0:
				wob = 2.2 * minf(hf / 10.0, 1.0) * lerpf(
					lerpf(det[ci], det[ci + 1], tx),
					lerpf(det[ci + cw], det[ci + cw + 1], tx),
					tz
				)
				hf = maxf(hf + wob, 1.0)
			## Snap part of the massif onto the bedding planes, at full resolution so the
			## riser lands in one column and exposes a whole bed. Bed thickness varies, so
			## the scarps come out irregular the way real ones are; everywhere else keeps
			## the smooth grassy dome.
			if hf > 6.0:
				var mix := lerpf(
					lerpf(terr[ci], terr[ci + 1], tx),
					lerpf(terr[ci + cw], terr[ci + cw + 1], tx),
					tz
				)
				if mix > 0.5:
					hf = minf(_snap_to_bed(hf, _bed_dip(x, z)), cap + maxf(wob, 0.0))
			var h := int(minf(hf, float(PEAK_MAX)))
			_height[i] = h if h >= MIN_RELIEF else 0


## Fast-sweep clamp so no column ever stands more than MAX_STEP above its neighbour.
func _limit_steps() -> void:
	for _pass in range(2):
		for z in range(_d):
			for x in range(_w):
				var i := z * _w + x
				var v := _height[i]
				if v <= 0:
					continue
				if x > 0:
					v = mini(v, _height[i - 1] + MAX_STEP)
				if z > 0:
					v = mini(v, _height[i - _w] + MAX_STEP)
				_height[i] = v
		for z2 in range(_d - 1, -1, -1):
			for x2 in range(_w - 1, -1, -1):
				var i2 := z2 * _w + x2
				var v2 := _height[i2]
				if v2 <= 0:
					continue
				if x2 < _w - 1:
					v2 = mini(v2, _height[i2 + 1] + MAX_STEP)
				if z2 < _d - 1:
					v2 = mini(v2, _height[i2 + _w] + MAX_STEP)
				_height[i2] = v2


## Peak of the finished heightfield, in district-local columns. Run after `_limit_steps`, which
## is free to shave the tallest column, so the seed summit is not necessarily the high point.
func _record_summit_top() -> void:
	summit_top = Vector3i(-1, 0, -1)
	var best := 0
	for z in range(_d):
		var row := z * _w
		for x in range(_w):
			var h := _height[row + x]
			if h <= best:
				continue
			best = h
			summit_top = Vector3i(_ox + x, h, _oz + z)


func _report(summits: Array[Dictionary]) -> void:
	var peak := 0
	var raised := 0
	for i in range(_height.size()):
		var h := _height[i]
		if h > 0:
			raised += 1
			peak = maxi(peak, h)
	print(
		"HillComposer: %d summits, peak %d vox (%d m), %d%% of tile raised"
		% [summits.size(), peak, peak / 2, raised * 100 / maxi(1, _height.size())]
	)


func _paint_meadow() -> void:
	## Scuff the flat ground between the hills so the valleys are not billiard-table green.
	for z in range(_d):
		for x in range(_w):
			if _height[z * _w + x] > 0 or _is_road_cell(x, z):
				continue
			var wx := _ox + x
			var wz := _oz + z
			## Clumped, not speckled — per-voxel dice read as litter scattered on a lawn.
			var n := _fbm2(float(wx) * 0.09, float(wz) * 0.09)
			if n > 0.88:
				brush.set_vox(Vector3i(wx, ground_y, wz), VoxelMaterial.GRAVEL)
			elif n > 0.78:
				brush.set_vox(Vector3i(wx, ground_y, wz), VoxelMaterial.DIRT)


func _paint_terrain() -> void:
	for z in range(_d):
		for x in range(_w):
			_paint_column(x, z)


func _paint_column(x: int, z: int) -> void:
	var h := _height[z * _w + x]
	if h <= 0:
		return
	var wx := _ox + x
	var wz := _oz + z
	var top := ground_y + h
	var step := _step_at(x, z)
	## Turf is two voxels thick so the side face of an ordinary quantisation step is
	## still grass. Only real scarps and outcrop patches go bare.
	##
	## Both tests are deliberately independent of `step` beyond the scarp cut-off: on a
	## quantised slope the stepped columns line up along the contours, so keying any
	## material choice off steepness paints the hill in horizontal stripes.
	var soil := 0 if step >= 3 else 2
	if soil > 0 and _fbm2(float(wx) * 0.045, float(wz) * 0.045) + 0.004 * float(h) > 0.78:
		soil = 0
	## Footing under the mass, and the floor of anything carved into it later.
	if h >= 5:
		brush.set_vox(Vector3i(wx, ground_y, wz), VoxelMaterial.DIRT)

	var rock_top := top - soil
	var dip := _bed_dip(x, z)
	var y := ground_y + 1
	while y <= rock_top:
		var e := y - ground_y + dip
		var m := posmod(e, _band_cycle)
		var bi := _band_at(m)
		var y_end := mini(rock_top + 1, y + (_band_ends[bi] - m))
		brush.fill_box(Vector3i(wx, y, wz), Vector3i(wx + 1, y_end, wz + 1), _band_mats[bi])
		y = y_end
	if soil <= 0:
		return
	## One material for the whole turf layer, chosen from a clumped field: a per-voxel
	## dice would speckle the slope and the exposed side face would not match its top.
	var cap := VoxelMaterial.PARK
	if _fbm2(float(wx) * 0.08 + 5.0, float(wz) * 0.08 - 2.0) > 0.72:
		cap = VoxelMaterial.DIRT
	for y2 in range(top - soil + 1, top + 1):
		brush.set_vox(Vector3i(wx, y2, wz), cap)


## Raise a height onto the top of whichever rock bed it currently falls inside.
func _snap_to_bed(h: float, dip: int) -> float:
	var e := h + float(dip)
	var cycles := floorf(e / float(_band_cycle))
	var m := e - cycles * float(_band_cycle)
	var top := _band_cycle
	for i in range(_band_ends.size()):
		if float(_band_ends[i]) > m:
			top = _band_ends[i]
			break
	return cycles * float(_band_cycle) + float(top) - float(dip)


## Ridged noise: peaks along creases instead of at blobs, which is what gives crags.
func _ridge(x: float, z: float) -> float:
	var r := 1.0 - absf(_fbm2(x, z) * 2.0 - 1.0)
	return r * r


func _band_at(offset_in_cycle: int) -> int:
	for i in range(_band_ends.size()):
		if offset_in_cycle < _band_ends[i]:
			return i
	return _band_ends.size() - 1


## Gently folded bedding planes — flat pancake layers look printed, not geological.
## Separable, so it is baked into two 1-D tables and read per column for free.
func _bed_dip(x: int, z: int) -> int:
	return int(round(_dip_x[x] + _dip_z[z]))


func _build_bed_dip() -> void:
	_dip_x.resize(_w)
	for x in range(_w):
		_dip_x[x] = 4.0 * sin(float(_ox + x) * 0.010 + 1.3)
	_dip_z.resize(_d)
	for z in range(_d):
		_dip_z[z] = 3.0 * sin(float(_oz + z) * 0.013 - 0.7)


## One cheese network per tile, not per summit: the lattice already spans the whole
## region and only seats chambers where there is rock, so every massif in the tile
## gets hollowed by the same pass. Summits only contribute their daylight mouths.
func _carve_caves(summits: Array[Dictionary]) -> void:
	var portals: Array[Vector2i] = []
	cave_mouths = PackedVector2Array()
	cave_summit = Vector2i(-1, -1)
	for s: Dictionary in summits:
		var sx := int(s["x"])
		var sz := int(s["z"])
		if _height_at(sx, sz) < CAVE_MIN_ROOF:
			continue
		var mouths := _find_portals(sx, sz, 2 + rng.randi() % 2)
		if mouths.is_empty():
			continue
		s["portal"] = mouths[0]
		if cave_summit.x < 0:
			cave_summit = Vector2i(_ox + sx, _oz + sz)
		for mouth: Vector2i in mouths:
			portals.append(mouth)
			cave_mouths.append(Vector2(_ox + mouth.x, _oz + mouth.y))
	if portals.is_empty():
		return
	if use_native_hill:
		_carve_cheese_native(portals)
	else:
		_carve_cheese(portals)


## Offline volume + loaded extension required. Asserts on failure (no GDScript fallback).
func _native_hill() -> Object:
	assert(use_native_hill)
	assert(brush != null and brush.volume != null, "HillComposer: native hill needs offline volume")
	CityVoxelNativeScript.require_loaded()
	var native: Object = CityVoxelNativeScript.make_hill_caves()
	assert(native != null, "HillComposer: NativeHillCaves missing")
	return native


func _paint_terrain_native() -> void:
	var native := _native_hill()
	var stats: Dictionary = native.call(
		"paint_terrain",
		brush.volume,
		_ox,
		_oz,
		_w,
		_d,
		ground_y,
		_height,
		_band_mats,
		_band_ends
	) as Dictionary
	assert(bool(stats.get("ok", false)), "HillComposer: native paint_terrain failed")
	print(
		"HillComposer: paint[native] columns=%d in %d ms"
		% [int(stats.get("columns", 0)), int(stats.get("ms", 0))]
	)


func _scatter_gems_native() -> void:
	var native := _native_hill()
	var road_mask := PackedByteArray()
	road_mask.resize(_w * _d)
	for z in range(_d):
		for x in range(_w):
			road_mask[z * _w + x] = 1 if _is_road_cell(x, z) else 0
	var seed_i: int = rng.randi()
	var stats: Dictionary = native.call(
		"scatter_gems",
		brush.volume,
		_ox,
		_oz,
		_w,
		_d,
		ground_y,
		_height,
		road_mask,
		seed_i
	) as Dictionary
	assert(bool(stats.get("ok", false)), "HillComposer: native scatter_gems failed")
	gem_positions = stats.get("positions", PackedVector3Array()) as PackedVector3Array
	gem_mats = stats.get("mats", PackedInt32Array()) as PackedInt32Array
	print(
		"HillComposer: gem[native] clusters=%d voxels=%d in %d ms"
		% [
			int(stats.get("clusters", 0)),
			int(stats.get("voxels", 0)),
			int(stats.get("ms", 0)),
		]
	)


func _carve_cheese_native(portals: Array[Vector2i]) -> void:
	var native := _native_hill()
	var portals_xz := PackedInt32Array()
	portals_xz.resize(portals.size() * 2)
	for i in range(portals.size()):
		portals_xz[i * 2] = portals[i].x
		portals_xz[i * 2 + 1] = portals[i].y
	var seed_i: int = rng.randi()
	var stats: Dictionary = native.call(
		"carve_cheese",
		brush.volume,
		_ox,
		_oz,
		_w,
		_d,
		ground_y,
		_height,
		portals_xz,
		seed_i
	) as Dictionary
	assert(bool(stats.get("ok", false)), "HillComposer: native carve_cheese failed")
	print(
		(
			"HillComposer: cheese[native] chambers=%d links=%d mouths=%d swells=%d"
			+ " core hollow=%.1f%% reachable=%.1f%% in %d ms"
		)
		% [
			int(stats.get("chambers", 0)),
			int(stats.get("links", 0)),
			int(stats.get("mouths", 0)),
			int(stats.get("swells", 0)),
			float(stats.get("hollow", 0.0)) * 100.0,
			float(stats.get("reachable", 0.0)) * 100.0,
			int(stats.get("ms", 0)),
		]
	)


## Hollow the massif like swiss cheese: a jittered 3-D lattice of big chambers wired
## together by galleries and spiral shafts, so the cave system is open in every axis
## instead of being one branching corridor at deck height.
func _carve_cheese(portals: Array[Vector2i]) -> void:
	var started := Time.get_ticks_msec()
	var nodes := _build_cavern_nodes()
	if nodes.size() < 2:
		return
	var by_key: Dictionary = {}
	for i in range(nodes.size()):
		var n: Dictionary = nodes[i]
		by_key[Vector3i(int(n["gx"]), int(n["gy"]), int(n["gz"]))] = i
	for node: Dictionary in nodes:
		_carve_room(node)
	_bulge_caverns(nodes)
	var links := _link_caverns(nodes, by_key)
	for link: Dictionary in links:
		if bool(link["vertical"]):
			_carve_shaft(link["from"] as Vector3i, link["to"] as Vector3i)
		else:
			_carve_passage(
				link["from"] as Vector3i, link["to"] as Vector3i, int(link["radius"]), true
			)
	_carve_mouths(portals, nodes)
	var hollow := _measure_core_hollow()
	var swells := 0
	while hollow < CAVE_HOLLOW_TARGET and swells < 4:
		hollow = _widen_caverns(nodes)
		swells += 1
	var reachable := _audit_reachable(portals)
	_dress_cave_system(nodes)
	print(
		(
			"HillComposer: cheese chambers=%d links=%d mouths=%d swells=%d"
			+ " core hollow=%.1f%% reachable=%.1f%% in %d ms"
		)
		% [
			nodes.size(),
			links.size(),
			portals.size(),
			swells,
			hollow * 100.0,
			reachable * 100.0,
			Time.get_ticks_msec() - started,
		]
	)


## Share of hollowed columns the player can walk to from a mouth. A full 3-D flood of
## the carve would be tens of millions of cells, so this floods the hollow *footprint*
## instead: it catches whole wings left stranded, which is the failure that matters.
func _audit_reachable(portals: Array[Vector2i]) -> float:
	var seen := PackedByteArray()
	seen.resize(_w * _d)
	var open := 0
	for i in range(_w * _d):
		if _cave_hi[i] >= 0:
			open += 1
	if open == 0:
		return 0.0
	var queue: Array[int] = []
	for portal: Vector2i in portals:
		var start := portal.y * _w + portal.x
		if _cave_hi[start] < 0 or seen[start] == 1:
			continue
		seen[start] = 1
		queue.append(start)
	var reached := queue.size()
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var x := idx % _w
		var z := idx / _w
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + step.x
			var nz := z + step.y
			if nx < 0 or nz < 0 or nx >= _w or nz >= _d:
				continue
			var n := nz * _w + nx
			if seen[n] == 1 or _cave_hi[n] < 0:
				continue
			seen[n] = 1
			reached += 1
			queue.append(n)
	return float(reached) / float(open)


## Seat a chamber in every lattice cell that has rock to spare, stacking upward until
## the shell cuts the column off. X/Z jitter is per level, so stacked chambers lean
## against each other instead of forming a straight silo.
func _build_cavern_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var margin := CAVE_ROOM_R_MAX + 4
	if _w < margin * 3 or _d < margin * 3:
		return out
	var jit := CAVE_CELL_XZ / 4
	var gz := 0
	var bz := margin
	while bz < _d - margin:
		var gx := 0
		var bx := margin
		while bx < _w - margin:
			var gy := 0
			var level_y := ground_y + CAVE_CLEARANCE_RY + 3
			while gy < CAVE_MAX_LEVELS:
				var x := clampi(bx + rng.randi_range(-jit, jit), margin, _w - margin - 1)
				var z := clampi(bz + rng.randi_range(-jit, jit), margin, _d - margin - 1)
				var rx := rng.randi_range(CAVE_ROOM_R_MIN, CAVE_ROOM_R_MAX)
				var rz := rng.randi_range(CAVE_ROOM_R_MIN, CAVE_ROOM_R_MAX)
				var ry := CAVE_CLEARANCE_RY + rng.randi() % (CAVE_ROOM_RY_EXTRA + 1)
				var cy := level_y + rng.randi_range(-1, 2)
				var ceiling := ground_y + _min_height_in_rect(x, z, rx, rz) - CAVE_SHELL
				if cy + ry > ceiling:
					break
				## Sump pools only make sense on the bottom deck.
				var kind := "chamber"
				if gy == 0 and rng.randf() < 0.18:
					kind = "crypt"
				out.append({
					"x": x,
					"y": cy,
					"z": z,
					"rx": rx,
					"ry": ry,
					"rz": rz,
					"kind": kind,
					"gx": gx,
					"gy": gy,
					"gz": gz,
				})
				gy += 1
				level_y += CAVE_CELL_Y
			gx += 1
			bx += CAVE_CELL_XZ
		gz += 1
		bz += CAVE_CELL_XZ
	return out


## Thinnest roof over a chamber footprint, sampled coarsely — this is a placement
## quality gate, not a safety net: _carve_ellipsoid clamps the shell per column.
func _min_height_in_rect(cx: int, cz: int, rx: int, rz: int) -> int:
	var lo := PEAK_MAX * 2
	var z := maxi(cz - rz, 0)
	var z_end := mini(cz + rz, _d - 1)
	var x_end := mini(cx + rx, _w - 1)
	while z <= z_end:
		var row := z * _w
		var x := maxi(cx - rx, 0)
		while x <= x_end:
			lo = mini(lo, _height[row + x])
			x += 3
		z += 3
	return lo


## Every chamber grows a few lobes so the walls read as eroded rock, not as the
## ellipsoid they were carved from.
func _bulge_caverns(nodes: Array[Dictionary]) -> void:
	for node: Dictionary in nodes:
		var cx := int(node["x"])
		var cy := int(node["y"])
		var cz := int(node["z"])
		var rx := int(node["rx"])
		var ry := int(node["ry"])
		var rz := int(node["rz"])
		for _lobe in range(2 + rng.randi() % 3):
			var ang := rng.randf() * TAU
			var ox := cx + int(round(cos(ang) * float(rx) * 0.8))
			var oz := cz + int(round(sin(ang) * float(rz) * 0.8))
			var oy := cy + rng.randi_range(-ry / 2, ry / 2)
			_carve_ellipsoid(
				Vector3i(_ox + ox, oy, _oz + oz),
				Vector3i(3 + rng.randi() % 4, CAVE_CLEARANCE_RY, 3 + rng.randi() % 4),
				ground_y - CAVE_PIT_DEPTH
			)


## Wire the lattice. A shuffled union-find pass guarantees one connected system, then
## the leftover edges are kept at random so the network has loops, not just a tree.
func _link_caverns(nodes: Array[Dictionary], by_key: Dictionary) -> Array[Dictionary]:
	var parent: Array[int] = []
	parent.resize(nodes.size())
	for i in range(nodes.size()):
		parent[i] = i
	var dirs: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0)]
	var cands: Array[Vector3i] = []
	for i2 in range(nodes.size()):
		var n: Dictionary = nodes[i2]
		for dir: Vector3i in dirs:
			var key := Vector3i(
				int(n["gx"]) + dir.x, int(n["gy"]) + dir.y, int(n["gz"]) + dir.z
			)
			if not by_key.has(key):
				continue
			cands.append(Vector3i(i2, int(by_key[key]), 1 if dir.y != 0 else 0))
	for i3 in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i3 + 1)
		var swap := cands[i3]
		cands[i3] = cands[j]
		cands[j] = swap
	var links: Array[Dictionary] = []
	for cand: Vector3i in cands:
		var ra := _uf_find(parent, cand.x)
		var rb := _uf_find(parent, cand.y)
		var needed := ra != rb
		if not needed:
			var keep := CAVE_LINK_P_VERT if cand.z == 1 else CAVE_LINK_P_HORZ
			if rng.randf() >= keep:
				continue
		else:
			parent[ra] = rb
		links.append(_link_between(nodes[cand.x], nodes[cand.y]))
	_join_islands(nodes, parent, links)
	return links


## Cells separated by a thin neck of the massif form their own lattice islands. Tie
## each one back to the main body so no chamber is ever a sealed pocket.
func _join_islands(
	nodes: Array[Dictionary], parent: Array[int], links: Array[Dictionary]
) -> void:
	var groups: Dictionary = {}
	for i in range(nodes.size()):
		var root := _uf_find(parent, i)
		if not groups.has(root):
			groups[root] = ([] as Array[int])
		var members: Array[int] = groups[root]
		members.append(i)
	if groups.size() <= 1:
		return
	var main_root := -1
	var main_size := -1
	for root2: int in groups.keys():
		var group: Array[int] = groups[root2]
		if group.size() > main_size:
			main_size = group.size()
			main_root = root2
	var main: Array[int] = groups[main_root]
	for root3: int in groups.keys():
		if root3 == main_root:
			continue
		var island: Array[int] = groups[root3]
		var pick: int = island[0]
		var here: Dictionary = nodes[pick]
		var best := -1
		var best_d := 1.0e12
		for cand_i: int in main:
			var other: Dictionary = nodes[cand_i]
			var dx := float(int(other["x"]) - int(here["x"]))
			var dy := float(int(other["y"]) - int(here["y"]))
			var dz := float(int(other["z"]) - int(here["z"]))
			var d := dx * dx + dy * dy + dz * dz
			if d < best_d:
				best_d = d
				best = cand_i
		if best < 0:
			continue
		links.append(_link_between(here, nodes[best]))
		parent[_uf_find(parent, pick)] = _uf_find(parent, best)


func _uf_find(parent: Array[int], i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	var walk := i
	while parent[walk] != walk:
		var next := parent[walk]
		parent[walk] = root
		walk = next
	return root


func _link_between(a: Dictionary, b: Dictionary) -> Dictionary:
	var from_l := Vector3i(int(a["x"]), int(a["y"]), int(a["z"]))
	var to_l := Vector3i(int(b["x"]), int(b["y"]), int(b["z"]))
	return {
		"from": from_l,
		"to": to_l,
		## Anything with a real drop becomes a ramped shaft, whatever the lattice
		## direction was — a sloped tube that steep is not walkable.
		"vertical": absi(to_l.y - from_l.y) >= CAVE_STEEP_DROP,
		"radius": rng.randi_range(CAVE_LINK_R_MIN, CAVE_LINK_R_MAX),
	}


## Vertical link: a helical ramp between the two decks, shallow enough that the
## walker climbs it on one-voxel steps. Sometimes an open chimney drops alongside it.
func _carve_shaft(a: Vector3i, b: Vector3i) -> void:
	var lo := a
	var hi := b
	if lo.y > hi.y:
		lo = b
		hi = a
	var rise := hi.y - lo.y
	if rise < CAVE_STEEP_DROP:
		_carve_passage(lo, hi, CAVE_RADIUS + 1, true)
		return
	var cx := float(lo.x + hi.x) * 0.5
	var cz := float(lo.z + hi.z) * 0.5
	var rad := CAVE_SHAFT_RADIUS + rng.randf() * 2.0
	var turns := maxf(float(rise) / float(CAVE_SHAFT_RISE), 1.0)
	var steps := maxi(int(turns * 44.0), 32)
	var ang0 := rng.randf() * TAU
	var spin := 1.0 if rng.randf() < 0.5 else -1.0
	var first := lo
	var last := lo
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := ang0 + spin * t * turns * TAU
		var x := clampi(int(round(cx + cos(ang) * rad)), 4, _w - 5)
		var z := clampi(int(round(cz + sin(ang) * rad)), 4, _d - 5)
		var y := int(round(lerpf(float(lo.y), float(hi.y), t)))
		var p := Vector3i(x, _clamp_cave_y(x, z, y, CAVE_RADIUS), z)
		_carve_passage_slice(_ox + p.x, p.y, _oz + p.z, CAVE_RADIUS)
		if i == 0:
			first = p
		last = p
	_carve_passage_segment(lo, first, CAVE_RADIUS, 1)
	_carve_passage_segment(last, hi, CAVE_RADIUS, 2)
	if rng.randf() < 0.4:
		var mx := clampi(int(round(cx)), 4, _w - 5)
		var mz := clampi(int(round(cz)), 4, _d - 5)
		_carve_passage_segment(Vector3i(mx, lo.y, mz), Vector3i(mx, hi.y, mz), CAVE_RADIUS, 3)


## Daylight mouths are the only sanctioned holes in the skin, so the first stretch is
## bored with the shell guard down; inland the clamped meander takes over.
func _carve_mouths(portals: Array[Vector2i], nodes: Array[Dictionary]) -> void:
	for portal: Vector2i in portals:
		var target := _nearest_node(portal, nodes)
		var inner := Vector3i(int(target["x"]), int(target["y"]), int(target["z"]))
		var mouth := Vector3i(portal.x, ground_y + CAVE_CLEARANCE_RY + 1, portal.y)
		var throat := _step_toward(mouth, inner, 14)
		## Start on the meadow side of the portal so the opening reads as a hillside
		## face, not a buried tube that never clears the skin.
		var outer := _mouth_outer(portal, throat, 8)
		_shell_guard = false
		_carve_passage_segment(outer, throat, CAVE_RADIUS + 1, 0)
		_shell_guard = true
		_carve_passage(throat, inner, CAVE_RADIUS + 1, true)


## Step from the portal downhill (away from the inland throat) onto lower ground.
func _mouth_outer(portal: Vector2i, throat: Vector3i, dist: int) -> Vector3i:
	var dx := float(portal.x - throat.x)
	var dz := float(portal.y - throat.z)
	var run := maxf(sqrt(dx * dx + dz * dz), 1.0)
	var x := clampi(portal.x + int(round(dx / run * float(dist))), 4, _w - 5)
	var z := clampi(portal.y + int(round(dz / run * float(dist))), 4, _d - 5)
	return Vector3i(x, ground_y + CAVE_CLEARANCE_RY + 1, z)


func _nearest_node(portal: Vector2i, nodes: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = nodes[0]
	var best_d := 1.0e12
	for node: Dictionary in nodes:
		var dx := float(int(node["x"]) - portal.x)
		var dz := float(int(node["z"]) - portal.y)
		## Bias toward the lowest deck so the entrance is not a climb from the door.
		var dy := float(int(node["y"]) - ground_y) * 2.0
		var d := dx * dx + dz * dz + dy * dy
		if d < best_d:
			best_d = d
			best = node
	return best


func _step_toward(from_l: Vector3i, to_l: Vector3i, dist: int) -> Vector3i:
	var dx := float(to_l.x - from_l.x)
	var dz := float(to_l.z - from_l.z)
	var run := maxf(sqrt(dx * dx + dz * dz), 1.0)
	if run <= float(dist):
		return to_l
	var t := float(dist) / run
	var x := clampi(from_l.x + int(round(dx * t)), 4, _w - 5)
	var z := clampi(from_l.z + int(round(dz * t)), 4, _d - 5)
	return Vector3i(x, _clamp_cave_y(x, z, from_l.y, CAVE_RADIUS), z)


## Keep a passage centre above the deck and under the protected skin.
func _clamp_cave_y(x: int, z: int, y: int, ry: int) -> int:
	var low := ground_y + ry
	var high := ground_y + _height_at(x, z) - CAVE_SHELL - ry
	if high <= low:
		return low
	return clampi(y, low, high)


## Fraction of the protected core that is already open. Sampled on a coarse lattice —
## an exact count would walk tens of millions of voxels per district.
func _measure_core_hollow() -> float:
	var open := 0
	var total := 0
	var z := 4
	while z < _d - 4:
		var row := z * _w
		var x := 4
		while x < _w - 4:
			var top := ground_y + _height[row + x] - CAVE_SHELL
			var y := ground_y + 1
			while y <= top:
				total += 1
				if brush.get_vox(Vector3i(_ox + x, y, _oz + z)) == VoxelMaterial.AIR:
					open += 1
				y += 2
			x += 4
		z += 4
	if total == 0:
		return 0.0
	return float(open) / float(total)


## Still too solid: swell every chamber a notch and re-measure. Cheaper and more
## organic than re-planning the lattice at a tighter pitch.
func _widen_caverns(nodes: Array[Dictionary]) -> float:
	for node: Dictionary in nodes:
		node["rx"] = int(node["rx"]) + 1
		node["rz"] = int(node["rz"]) + 1
		if rng.randf() < 0.5:
			node["ry"] = int(node["ry"]) + 1
		_carve_room(node)
	return _measure_core_hollow()


func _corridor_run_xz(from_l: Vector3i, to_l: Vector3i) -> int:
	var dx := to_l.x - from_l.x
	var dz := to_l.z - from_l.z
	return int(round(sqrt(float(dx * dx + dz * dz))))


## Real daylight mouths: walk downhill until the surface is low enough for the
## tunnel to break out. The dungeon itself is then built inland from the mouth,
## so a long flank never has to be walked as a featureless pipe.
func _find_portals(sx: int, sz: int, want: int) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for i in range(dirs.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp := dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp
	var found: Array[Vector2i] = []
	for dir: Vector2i in dirs:
		if found.size() >= want:
			break
		var x := sx
		var z := sz
		var hit := Vector2i(-1, -1)
		var prev_h := _height_at(sx, sz)
		for _stepi in range(_w + _d):
			x += dir.x
			z += dir.y
			if x < 4 or z < 4 or x >= _w - 4 or z >= _d - 4:
				break
			var h := _height_at(x, z)
			if prev_h > CAVE_MOUTH_HEIGHT and h <= CAVE_MOUTH_HEIGHT:
				hit = Vector2i(x, z)
				break
			prev_h = h
		if hit.x < 0:
			continue
		var ok := true
		for p: Vector2i in found:
			if hit.distance_squared_to(p) < 36 * 36:
				ok = false
				break
		if ok:
			found.append(hit)
	return found


func _carve_room(room: Dictionary) -> void:
	var center := Vector3i(_ox + int(room["x"]), int(room["y"]), _oz + int(room["z"]))
	var radii := Vector3i(int(room["rx"]), int(room["ry"]), int(room["rz"]))
	_carve_ellipsoid(center, radii, ground_y - CAVE_PIT_DEPTH)


## Spur / ad-hoc segment carve (no pre-baked waypoints).
func _carve_passage(
	from_l: Vector3i, to_l: Vector3i, radius: int, force_meander: bool = false
) -> void:
	var points := _meander_waypoints(from_l, to_l, force_meander)
	for pi in range(points.size() - 1):
		_carve_passage_segment(points[pi], points[pi + 1], radius, pi)


## Build an S-curve (or single bend) between two cave points. Waypoints stay inside
## the tile and under enough roof that the carve does not daylight mid-hill.
func _meander_waypoints(
	from_l: Vector3i, to_l: Vector3i, force_meander: bool
) -> Array[Vector3i]:
	var out: Array[Vector3i] = [from_l]
	var run := _corridor_run_xz(from_l, to_l)
	if run < 8 and not force_meander:
		out.append(to_l)
		return out
	var dx := float(to_l.x - from_l.x)
	var dz := float(to_l.z - from_l.z)
	var plen := maxf(sqrt(dx * dx + dz * dz), 1.0)
	var px := -dz / plen
	var pz := dx / plen
	var bends := 1
	if run >= CAVE_LONG_RUN or force_meander:
		bends = 2
	if run >= CAVE_LONG_RUN + 14:
		bends = 3
	var amp := maxf(float(run) * CAVE_MEANDER_FRAC, 5.0)
	if force_meander:
		amp = maxf(amp, 8.0)
	var sign := 1.0 if rng.randf() < 0.5 else -1.0
	for bi in range(bends):
		var t := (float(bi) + 1.0) / (float(bends) + 1.0)
		## Alternate sides for an S-curve; jitter so two corridors never match.
		var side := sign * (1.0 if bi % 2 == 0 else -1.0)
		var swing := amp * (0.55 + rng.randf() * 0.55) * side
		var y_wob := rng.randi_range(-1, 1)
		var x := clampi(
			int(round(lerpf(float(from_l.x), float(to_l.x), t) + px * swing)),
			4,
			_w - 5
		)
		var z := clampi(
			int(round(lerpf(float(from_l.z), float(to_l.z), t) + pz * swing)),
			4,
			_d - 5
		)
		var y := _clamp_cave_y(
			x, z, int(round(lerpf(float(from_l.y), float(to_l.y), t))) + y_wob, CAVE_CLEARANCE_RY
		)
		## Prefer solid cover; if the bend breaks daylight, pull it back toward the axis.
		if _height_at(x, z) < CAVE_MOUTH_HEIGHT + 4:
			x = clampi(
				int(round(lerpf(float(from_l.x), float(to_l.x), t) + px * swing * 0.35)),
				4,
				_w - 5
			)
			z = clampi(
				int(round(lerpf(float(from_l.z), float(to_l.z), t) + pz * swing * 0.35)),
				4,
				_d - 5
			)
		out.append(Vector3i(x, y, z))
	out.append(to_l)
	return out


func _carve_passage_segment(
	from_l: Vector3i, to_l: Vector3i, radius: int, seed_i: int
) -> void:
	var dx := to_l.x - from_l.x
	var dy := to_l.y - from_l.y
	var dz := to_l.z - from_l.z
	var steps := maxi(maxi(absi(dx), absi(dz)), absi(dy))
	if steps <= 0:
		_carve_passage_slice(_ox + from_l.x, from_l.y, _oz + from_l.z, radius)
		return
	var phase := float(from_l.x) * 0.11 + float(from_l.z) * 0.07 + float(seed_i) * 1.7
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := int(round(lerpf(float(from_l.x), float(to_l.x), t)))
		var y := int(round(lerpf(float(from_l.y), float(to_l.y), t)))
		var z := int(round(lerpf(float(from_l.z), float(to_l.z), t)))
		## Endpoints stay exact so rooms / spur mouths are never missed by wobble.
		var at_end := i == 0 or i == steps
		if not at_end:
			var wob := int(
				round(
					2.2 * sin(t * TAU * 1.1 + phase)
					+ 1.1 * sin(t * TAU * 2.7 + phase * 1.3)
				)
			)
			if absi(dx) >= absi(dz):
				z += wob
			else:
				x += wob
			var pulse := sin(t * TAU * 1.6 + phase * 0.5)
			if int(round(sin(t * 9.0 + phase))) != 0:
				y = _clamp_cave_y(x, z, y + (1 if pulse > 0.0 else -1), CAVE_CLEARANCE_RY)
		var r := radius
		if not at_end:
			var pulse_r := sin(t * TAU * 1.6 + phase * 0.5)
			if pulse_r > 0.55:
				r = radius + 1
			elif pulse_r < -0.7 and radius > 2:
				r = radius - 1
		_carve_passage_slice(_ox + x, y, _oz + z, r)


## Line exposed rock with cave wall and lay cave floor under every open deck. Only
## columns the carve actually opened are visited: the cheese network spans the whole
## massif, so a bounding-box sweep would walk millions of untouched voxels.
func _dress_cave_system(rooms: Array[Dictionary]) -> void:
	var deck_floor := ground_y - CAVE_PIT_DEPTH
	for z in range(_d):
		var row := z * _w
		for x in range(_w):
			var hi := _cave_hi[row + x]
			if hi < 0:
				continue
			var wx := _ox + x
			var wz := _oz + z
			for y in range(maxi(_cave_lo[row + x] - 1, deck_floor), hi + 2):
				var here := brush.get_vox(Vector3i(wx, y, wz))
				if VoxelMaterial.is_gem(here):
					continue
				if here == VoxelMaterial.AIR:
					## Every deck in the column gets a floor, not just the lowest one —
					## stacked caverns are the whole point of the network.
					var below := brush.get_vox(Vector3i(wx, y - 1, wz))
					if VoxelMaterial.is_gem(below):
						continue
					if _is_cave_shellable(below):
						brush.set_vox(Vector3i(wx, y - 1, wz), VoxelMaterial.CAVE_FLOOR)
					continue
				if not _is_cave_shellable(here):
					continue
				if _air_neighbour(wx, y, wz):
					brush.set_vox(Vector3i(wx, y, wz), VoxelMaterial.CAVE_WALL)

	## Stalagmites / stalactites and the odd pillar.
	for room: Dictionary in rooms:
		_dress_cave_room(room)


## Boundary probe for the wall lining. Vertical neighbours come first: in a hollowed
## massif most exposed rock is a floor or a ceiling, so that ordering short-circuits.
func _air_neighbour(wx: int, y: int, wz: int) -> bool:
	return (
		brush.get_vox(Vector3i(wx, y - 1, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y + 1, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx + 1, y, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx - 1, y, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y, wz + 1)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y, wz - 1)) == VoxelMaterial.AIR
	)


func _dress_cave_room(room: Dictionary) -> void:
	var sx := int(room["x"])
	var sz := int(room["z"])
	var cy := int(room["y"])
	var rx := int(room["rx"])
	var ry := int(room["ry"])
	var rz := int(room["rz"])
	var kind: String = room["kind"]
	## Crypts get a shallow water pool; other rooms get damp floor patches.
	if kind == "crypt":
		var pool_r := mini(rx, rz) - 1
		if pool_r >= 2:
			for z in range(sz - pool_r, sz + pool_r + 1):
				for x in range(sx - pool_r, sx + pool_r + 1):
					if (x - sx) * (x - sx) + (z - sz) * (z - sz) > pool_r * pool_r:
						continue
					var wx := _ox + x
					var wz := _oz + z
					var fy := cy - ry
					if brush.get_vox(Vector3i(wx, fy + 1, wz)) == VoxelMaterial.AIR:
						brush.set_vox(Vector3i(wx, fy, wz), VoxelMaterial.WATER)
	var features := 3 + rng.randi() % 5
	for _f in range(features):
		var px := sx + rng.randi_range(-rx + 1, rx - 1)
		var pz := sz + rng.randi_range(-rz + 1, rz - 1)
		var wx2 := _ox + px
		var wz2 := _oz + pz
		## Short floor nubs only — tall stalagmites steal standing room.
		if rng.randf() < 0.55:
			var base_y := cy - ry
			while base_y < cy + ry and brush.get_vox(Vector3i(wx2, base_y, wz2)) != VoxelMaterial.AIR:
				base_y += 1
			if brush.get_vox(Vector3i(wx2, base_y, wz2)) == VoxelMaterial.AIR:
				var h := 1 + rng.randi() % 2
				for dy in range(h):
					var p := Vector3i(wx2, base_y + dy, wz2)
					if brush.get_vox(p) != VoxelMaterial.AIR:
						break
					brush.set_vox(p, VoxelMaterial.CAVE_WALL)
		## Stalactite down from the ceiling — stop above walk clearance.
		else:
			var top_y := cy + ry
			while top_y > cy - ry and brush.get_vox(Vector3i(wx2, top_y, wz2)) != VoxelMaterial.AIR:
				top_y -= 1
			## Relative to this chamber's own deck — upper caverns sit far above ground_y.
			var clear_floor := cy - ry + CAVE_WALK_CLEARANCE
			if brush.get_vox(Vector3i(wx2, top_y, wz2)) == VoxelMaterial.AIR:
				var h2 := 2 + rng.randi() % 4
				for dy2 in range(h2):
					var p2 := Vector3i(wx2, top_y - dy2, wz2)
					if p2.y <= clear_floor:
						break
					if brush.get_vox(p2) != VoxelMaterial.AIR:
						break
					brush.set_vox(p2, VoxelMaterial.CAVE_WALL)
	## Chunky pillars hold up the bigger halls.
	if rx >= 6:
		for _pillar in range(1 + rng.randi() % 3):
			if rng.randf() > 0.55:
				continue
			var qx := _ox + sx + rng.randi_range(-rx / 2, rx / 2)
			var qz := _oz + sz + rng.randi_range(-rz / 2, rz / 2)
			for y in range(cy - ry + 1, cy + ry - 1):
				## Ore is budgeted: the tile owes exactly the gems embedded before the carve,
				## so a pillar grows around a nugget rather than through it.
				if VoxelMaterial.is_gem(brush.get_vox(Vector3i(qx, y, qz))):
					continue
				brush.set_vox(Vector3i(qx, y, qz), VoxelMaterial.CAVE_WALL)


func _is_cave_shellable(id: int) -> bool:
	match id:
		VoxelMaterial.BEDROCK, VoxelMaterial.STONE, VoxelMaterial.BRICK, VoxelMaterial.DIRT, VoxelMaterial.GRAVEL, VoxelMaterial.CAVE_WALL:
			return true
		_:
			return false


func _carve_passage_slice(cx: int, cy: int, cz: int, rxz: int) -> void:
	## Duck under a thin roof instead of letting the shell clamp shave the top off the
	## tube: a shaved tube is a crawl space the walker cannot pass, i.e. a dead link.
	var lx := cx - _ox
	var lz := cz - _oz
	var y := cy
	var ry := CAVE_CLEARANCE_RY
	if _shell_guard:
		y = _clamp_cave_y(lx, lz, cy, CAVE_CLEARANCE_RY)
	else:
		## Daylight mouth: previous code left the shell clamp on, so portals at
		## CAVE_MOUTH_HEIGHT (~12) never broke the surface (carve top ~ deck+9).
		## Clear from the walk deck through the turf into open air.
		var surface := ground_y + _height_at(lx, lz)
		var floor_y := ground_y + 1
		var top := surface + 1
		ry = maxi(CAVE_CLEARANCE_RY, int(ceil(float(top - floor_y) * 0.5)) + 1)
		y = floor_y + ry
	## Taller than wide so corridors stay walkable without becoming halls.
	_carve_ellipsoid(
		Vector3i(cx, y, cz), Vector3i(rxz, ry, rxz), ground_y - CAVE_PIT_DEPTH
	)


func _carve_ellipsoid(center: Vector3i, radii: Vector3i, floor_min_y: int) -> void:
	if radii.x <= 0 or radii.y <= 0 or radii.z <= 0:
		return
	var fx := float(radii.x)
	var fy := float(radii.y)
	var fz := float(radii.z)
	var y0 := maxi(center.y - radii.y, floor_min_y)
	for z in range(center.z - radii.z, center.z + radii.z + 1):
		var lz := z - _oz
		if lz < 0 or lz >= _d:
			continue
		var row := lz * _w
		var nz := float(z - center.z) / fz
		for x in range(center.x - radii.x, center.x + radii.x + 1):
			var lx := x - _ox
			if lx < 0 or lx >= _w:
				continue
			var nx := float(x - center.x) / fx
			## The massif keeps its skin: no carve may come within CAVE_SHELL of the
			## surface, so the hill still reads as a hill from outside. Only the mouth
			## bore drops the guard.
			var y1 := center.y + radii.y
			if _shell_guard:
				y1 = mini(y1, ground_y + _height[row + lx] - CAVE_SHELL)
			for y in range(y0, y1 + 1):
				var ny := float(y - center.y) / fy
				if nx * nx + ny * ny + nz * nz > 1.0:
					continue
				var at := Vector3i(x, y, z)
				## Leave gem ore as protruding nuggets instead of deleting it with the cave.
				if VoxelMaterial.is_gem(brush.get_vox(at)):
					continue
				brush.set_vox(at, VoxelMaterial.AIR)
				if _cave_hi[row + lx] < 0:
					_cave_lo[row + lx] = y
					_cave_hi[row + lx] = y
					continue
				_cave_lo[row + lx] = mini(_cave_lo[row + lx], y)
				_cave_hi[row + lx] = maxi(_cave_hi[row + lx], y)


## Embed exactly `gem_mats_to_place` in solid rock before caves open. Carve skips gem voxels
## so nuggets stick into chambers; buried ones stay excavatable.
func _scatter_gems_from_quota() -> void:
	gem_positions = PackedVector3Array()
	gem_mats = PackedInt32Array()
	var quota := gem_mats_to_place.size()
	if quota <= 0:
		return
	var placed := 0
	var tries := 0
	var max_tries := maxi(quota * 24, 64)
	while placed < quota and tries < max_tries:
		tries += 1
		var x := rng.randi_range(2, _w - 3)
		var z := rng.randi_range(2, _d - 3)
		if _is_road_cell(x, z):
			continue
		var h := _height[z * _w + x]
		var y_lo := ground_y + GEM_SURFACE_MARGIN
		var y_hi := ground_y + h - GEM_SURFACE_MARGIN
		if y_hi <= y_lo:
			continue
		var y := rng.randi_range(y_lo, y_hi)
		var cursor := Vector3i(_ox + x, y, _oz + z)
		if not _is_gem_host(brush.get_vox(cursor)):
			continue
		var gem := int(gem_mats_to_place[placed])
		brush.set_vox(cursor, gem)
		gem_positions.append(Vector3(float(cursor.x), float(cursor.y), float(cursor.z)))
		gem_mats.append(gem)
		placed += 1
	if placed < quota:
		push_error(
			"HillComposer: only placed %d of %d budgeted gem voxels after %d tries"
			% [placed, quota, tries]
		)
	print("HillComposer: gem voxels=%d (quota %d)" % [gem_mats.size(), quota])


func _is_gem_host(id: int) -> bool:
	match id:
		VoxelMaterial.STONE, VoxelMaterial.BRICK, VoxelMaterial.GRAVEL:
			return true
		_:
			return false


func _place_gem_cluster(origin: Vector3i, gem: int, count: int) -> void:
	var cursor := origin
	for i in range(count):
		var here := brush.get_vox(cursor)
		if _is_gem_host(here):
			brush.set_vox(cursor, gem)
			gem_positions.append(Vector3(float(cursor.x), float(cursor.y), float(cursor.z)))
			gem_mats.append(gem)
		## Step to a random 6-neighbour for the next nugget.
		match rng.randi() % 6:
			0:
				cursor.x += 1
			1:
				cursor.x -= 1
			2:
				cursor.y += 1
			3:
				cursor.y -= 1
			4:
				cursor.z += 1
			_:
				cursor.z -= 1


func _scatter_boulders() -> void:
	var target := 26 + rng.randi() % 18
	var made := 0
	var tries := 0
	while made < target and tries < target * 8:
		tries += 1
		var x := rng.randi_range(3, _w - 4)
		var z := rng.randi_range(3, _d - 4)
		if _is_road_cell(x, z):
			continue
		var h := _height[z * _w + x]
		## Boulders sit on slopes and at the foot of scarps, not on the flat meadow.
		if h < 2 and rng.randf() < 0.7:
			continue
		var rx := 1 + rng.randi() % 3
		var ry := 1 + rng.randi() % 2
		var rz := 1 + rng.randi() % 3
		var mat := VoxelMaterial.STONE if rng.randf() < 0.65 else VoxelMaterial.GRAVEL
		## Sink it a voxel so it reads as bedrock breaking through, not a dropped egg.
		brush.fill_ellipsoid(
			Vector3i(_ox + x, ground_y + h + ry - 1, _oz + z), Vector3i(rx, ry, rz), mat
		)
		made += 1


func _plant_trees(density: float) -> void:
	var target := int(float(170) * density)
	var tries := 0
	var made := 0
	while made < target and tries < target * 6:
		tries += 1
		var x := rng.randi_range(4, _w - 5)
		var z := rng.randi_range(4, _d - 5)
		if _is_road_cell(x, z):
			continue
		var h := _height[z * _w + x]
		## Nothing roots on a scarp, and summits stay wind-blown and bare.
		if _step_at(x, z) >= 2:
			continue
		if h > PEAK_MAX * 3 / 4 and rng.randf() < 0.8:
			continue
		var wx := _ox + x
		var wz := _oz + z
		var y0 := ground_y + h
		var surface := brush.get_vox(Vector3i(wx, y0, wz))
		if surface != VoxelMaterial.PARK and surface != VoxelMaterial.DIRT:
			continue
		_stamper().plant_random(wx, y0, wz)
		made += 1


func _height_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= _w or z >= _d:
		return 0
	return _height[z * _w + x]


## Largest height difference to a 4-neighbour — the terrain's local steepness.
func _step_at(x: int, z: int) -> int:
	var h := _height_at(x, z)
	var s := 0
	s = maxi(s, absi(h - _height_at(x - 1, z)))
	s = maxi(s, absi(h - _height_at(x + 1, z)))
	s = maxi(s, absi(h - _height_at(x, z - 1)))
	s = maxi(s, absi(h - _height_at(x, z + 1)))
	return s


func _is_road_cell(x: int, z: int) -> bool:
	return LandUse.is_road(planner.tag_at((_ox + x) / cell_size, (_oz + z) / cell_size))


func _fbm2(x: float, z: float) -> float:
	return _value_noise2(x, z) * 0.65 + _value_noise2(x * 2.7 + 5.1, z * 2.7 - 3.3) * 0.35


func _value_noise2(x: float, z: float) -> float:
	var xi := floori(x)
	var zi := floori(z)
	var fx := x - float(xi)
	var fz := z - float(zi)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var n00 := _hash2(xi, zi)
	var n10 := _hash2(xi + 1, zi)
	var n01 := _hash2(xi, zi + 1)
	var n11 := _hash2(xi + 1, zi + 1)
	return lerpf(lerpf(n00, n10, fx), lerpf(n01, n11, fx), fz)


func _hash2(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0
