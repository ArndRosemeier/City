## Sculpts a Lake-theme district: one natural basin of open water with wooded islands.
##
## Lake tiles keep only short arterial stubs at the edges (see DistrictPlanner), so the
## middle is a single open reserve. The waterline is a noise-perturbed contour of the
## distance-to-road field, which keeps every connector and the district seam on dry
## land while still producing bays and headlands instead of a disc.
##
## The basin is carved out of the diggable STONE under the street deck, so the water
## top sits flush with the surrounding ground and the bed never touches the world
## floor slab.
class_name LakeComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var stamper: TreeStamper
## Land-use grid — road cells come from here instead of per-voxel probes.
var planner: DistrictPlanner
var cell_size: int = 28


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper

## Dry meadow that always separates the waterline from a road or the tile seam.
const SHORE_MARGIN := 13
## Over how many further voxels of clearance the waterline is pushed back near a road,
## so a lobe that reaches a connector dies out instead of ending in a hard edge.
const SHORE_SPAN := 18.0
## Overlapping lobes that make up the basin. The outline has to come from these, not
## from the clearance field: a pure clearance contour is just an inset of the road
## grid, which reads as a rectangular reservoir.
const LOBE_MIN := 5
const LOBE_MAX := 8
## Lobe radius as a fraction of the tile's short side.
const LOBE_R_MIN_F := 0.26
const LOBE_R_MAX_F := 0.38
## How far lobe centres may wander from the tile centre, per axis.
const LOBE_SPREAD_X := 0.17
const LOBE_SPREAD_Z := 0.11
## Metaball cut. Each lobe contributes (1 - (d/r)^2), so this is where the rim sits.
const LOBE_CUT := 0.42
## Domain warp applied before sampling the lobes — bends the whole outline so no lobe
## reads as a circle.
const WARP_AMPLITUDE := 24.0
const WARP_FREQ := 0.0045
## Deepest water in voxels below the deck. The bed voxel has to stay above the
## indestructible floor slab, so this is clamped against `ground_y` at paint time.
const DEPTH_MAX := 5
## Distance from the waterline (voxels) at which full depth is reached.
const DEPTH_RAMP := 26.0
## Dry shingle ring painted around the whole waterline.
const BEACH_BAND := 4
## Water patches smaller than this are noise specks, not ponds — they stay dry.
const MIN_POOL_COLUMNS := 900
## Islands per lake, and their footprint radius in voxels (5–14 m).
const ISLAND_MIN := 3
const ISLAND_MAX := 6
const ISLAND_R_MIN := 10
const ISLAND_R_MAX := 28
## Island crown height above the deck. Even the rim keeps a step out of the water.
const ISLAND_RISE_MIN := 3
const ISLAND_RISE_MAX := 8
## Water an island needs around it so it never fuses with the shore.
const ISLAND_OFFSHORE := 10
## Reeds only grow where a walker could still stand — the first two voxels of depth.
const REED_MAX_DEPTH := 2

## Region bounds (local district voxel coords) and the per-column fields.
var _ox: int = 0
var _oz: int = 0
var _w: int = 0
var _d: int = 0
## Distance in voxels to the nearest road cell or region border.
var _clearance: PackedFloat32Array = PackedFloat32Array()
## 1 = open water column.
var _water: PackedByteArray = PackedByteArray()
## Island crown height above the deck (0 = not an island).
var _island_h: PackedInt32Array = PackedInt32Array()
## Water depth in voxels below the deck (0 on dry columns).
var _depth: PackedInt32Array = PackedInt32Array()
## Distance to the nearest dry column (meaningful on water columns).
var _dist_dry: PackedFloat32Array = PackedFloat32Array()
## Distance to the nearest water column (meaningful on dry columns).
var _dist_wet: PackedFloat32Array = PackedFloat32Array()
## Scratch seed mask for the chamfer passes.
var _seeds: PackedByteArray = PackedByteArray()
var _islands: Array[Dictionary] = []


## Crown of every island in district-local voxels: X and Z in `x`/`z`, the land height above the
## deck in `y`. The stamped dome jitters, so the crown is re-read from the finished height field
## rather than taken from the island's nominal rise.
func island_crowns() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for island: Dictionary in _islands:
		var cx := int(island["x"])
		var cz := int(island["z"])
		var radius := int(island["r"])
		var best := 0
		var best_x := cx
		var best_z := cz
		for z in range(maxi(cz - radius, 0), mini(cz + radius + 1, _d)):
			for x in range(maxi(cx - radius, 0), mini(cx + radius + 1, _w)):
				var h := _island_h[z * _w + x]
				if h <= best:
					continue
				best = h
				best_x = x
				best_z = z
		if best <= 0:
			continue
		out.append(Vector3i(_ox + best_x, best, _oz + best_z))
	return out


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	_build_basin()
	_paint_basin()
	_paint_beach()
	_paint_islands()
	_plant_islands(1.0)
	_plant_shore(1.0)
	_scatter_reeds()
	print(
		"LakeComposer: water=%d cols islands=%d max depth=%d beach=%d cols"
		% [_water_count(), _islands.size(), _max_depth(), _beach_count()]
	)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Far tiles still need the basin and the island silhouettes; detail is dropped.
	if not _begin(min_v, max_v):
		return
	_build_basin()
	_paint_basin()
	_paint_beach()
	_paint_islands()
	_plant_islands(0.2)
	_plant_shore(0.12)


## Shape pass: waterline, islands, shore distances and depth. Writes no voxels.
func _build_basin() -> void:
	_build_clearance()
	_build_water_mask()
	_prune_specks()
	## Island siting needs to know how far offshore each column is, and seating an
	## island turns water into land — so the field is rebuilt once they are placed.
	_chamfer(_dist_dry, false)
	_place_islands()
	_chamfer(_dist_dry, false)
	_chamfer(_dist_wet, true)
	_build_depth()


func _begin(min_v: Vector3i, max_v: Vector3i) -> bool:
	if rng == null or brush == null:
		push_error("LakeComposer: brush / rng not set")
		return false
	if planner == null:
		push_error("LakeComposer: planner not set")
		return false
	_ox = min_v.x
	_oz = min_v.z
	_w = max_v.x - min_v.x
	_d = max_v.z - min_v.z
	if _w < 64 or _d < 64:
		push_error("LakeComposer: lake region %dx%d is too small to sculpt" % [_w, _d])
		return false
	if ground_y - DEPTH_MAX < 1:
		push_error(
			"LakeComposer: deck at y=%d has no room for a %d-voxel basin" % [ground_y, DEPTH_MAX]
		)
		return false
	var n := _w * _d
	_clearance.resize(n)
	_water.resize(n)
	_water.fill(0)
	_island_h.resize(n)
	_island_h.fill(0)
	_depth.resize(n)
	_depth.fill(0)
	_dist_dry.resize(n)
	_dist_wet.resize(n)
	_seeds.resize(n)
	_islands.clear()
	return true


## Chamfer distance transform seeded from road cells and the region border, so the
## waterline can be placed by "how far is the nearest thing that must stay dry".
func _build_clearance() -> void:
	for z in range(_d):
		for x in range(_w):
			var edge := x == 0 or z == 0 or x == _w - 1 or z == _d - 1
			_seeds[z * _w + x] = 1 if (edge or _is_road_cell(x, z)) else 0
	_chamfer_seeds(_clearance)


## Two-pass chamfer over `_seeds` (1 = distance zero) into `out`.
func _chamfer_seeds(out: PackedFloat32Array) -> void:
	const FAR := 1.0e9
	for i in range(_w * _d):
		out[i] = 0.0 if _seeds[i] != 0 else FAR
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			var v := out[i]
			if v == 0.0:
				continue
			if x > 0:
				v = minf(v, out[i - 1] + 1.0)
			if z > 0:
				v = minf(v, out[i - _w] + 1.0)
			if x > 0 and z > 0:
				v = minf(v, out[i - _w - 1] + 1.4142)
			if x < _w - 1 and z > 0:
				v = minf(v, out[i - _w + 1] + 1.4142)
			out[i] = v
	for z in range(_d - 1, -1, -1):
		for x in range(_w - 1, -1, -1):
			var i2 := z * _w + x
			var v2 := out[i2]
			if v2 == 0.0:
				continue
			if x < _w - 1:
				v2 = minf(v2, out[i2 + 1] + 1.0)
			if z < _d - 1:
				v2 = minf(v2, out[i2 + _w] + 1.0)
			if x < _w - 1 and z < _d - 1:
				v2 = minf(v2, out[i2 + _w + 1] + 1.4142)
			if x > 0 and z < _d - 1:
				v2 = minf(v2, out[i2 + _w - 1] + 1.4142)
			out[i2] = v2


## Distance field between the wet and dry halves of the tile. `from_water` seeds the
## water columns (so dry columns learn how far the shore is) and vice versa.
func _chamfer(out: PackedFloat32Array, from_water: bool) -> void:
	for i in range(_w * _d):
		var wet := _water[i] != 0
		_seeds[i] = 1 if (wet == from_water) else 0
	_chamfer_seeds(out)


## A chain of overlapping lobes centred on the tile. Chaining each new lobe off an
## existing one keeps the basin a single body instead of a scatter of ponds.
func _pick_lobes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var span := float(mini(_w, _d))
	var cx := float(_w) * 0.5
	var cz := float(_d) * 0.5
	var lim_x := float(_w) * LOBE_SPREAD_X
	var lim_z := float(_d) * LOBE_SPREAD_Z
	var count := rng.randi_range(LOBE_MIN, LOBE_MAX)
	out.append({
		"x": cx + rng.randf_range(-0.3, 0.3) * lim_x,
		"z": cz + rng.randf_range(-0.3, 0.3) * lim_z,
		"r": span * rng.randf_range(LOBE_R_MIN_F, LOBE_R_MAX_F),
	})
	while out.size() < count:
		var base: Dictionary = out[rng.randi() % out.size()]
		var angle := rng.randf() * TAU
		var reach := float(base["r"]) * rng.randf_range(0.45, 0.95)
		out.append({
			"x": clampf(float(base["x"]) + cos(angle) * reach, cx - lim_x, cx + lim_x),
			"z": clampf(float(base["z"]) + sin(angle) * reach, cz - lim_z, cz + lim_z),
			"r": span * rng.randf_range(LOBE_R_MIN_F, LOBE_R_MAX_F),
		})
	return out


## Waterline = warped metaball rim with a noisy cut, then clipped back from the roads.
func _build_water_mask() -> void:
	var lobes := _pick_lobes()
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			var room := _clearance[i]
			if room <= float(SHORE_MARGIN):
				continue
			var wx := float(_ox + x)
			var wz := float(_oz + z)
			## Warp where the lobes are sampled, so the rim bulges and pinches.
			var warp_x := (_fbm2(wx * WARP_FREQ + 3.1, wz * WARP_FREQ - 7.4) - 0.5) * 2.0
			var warp_z := (_fbm2(wx * WARP_FREQ - 19.6, wz * WARP_FREQ + 11.2) - 0.5) * 2.0
			var sx := float(x) + warp_x * WARP_AMPLITUDE
			var sz := float(z) + warp_z * WARP_AMPLITUDE
			var field := 0.0
			for lobe: Dictionary in lobes:
				var dx := sx - float(lobe["x"])
				var dz := sz - float(lobe["z"])
				var r := float(lobe["r"])
				var t := (dx * dx + dz * dz) / (r * r)
				if t < 1.0:
					field += 1.0 - t
			## Three octaves of cut noise: bays at the lobe scale, inlets and spits at
			## the scale of a swim, crinkle at the rim.
			var bay := _fbm2(wx * 0.0125 + 21.7, wz * 0.0125 - 8.3) - 0.5
			var inlet := _fbm2(wx * 0.029 + 9.4, wz * 0.029 + 47.1) - 0.5
			var crinkle := _fbm2(wx * 0.055 - 5.1, wz * 0.055 + 3.7) - 0.5
			var cut := LOBE_CUT + bay * 0.34 + inlet * 0.18 + crinkle * 0.1
			## Near a road the rim is pushed further out, so a lobe that runs into a
			## connector fades instead of ending against it in a straight line.
			cut += clampf(1.0 - (room - float(SHORE_MARGIN)) / SHORE_SPAN, 0.0, 1.0) * 0.5
			if field > cut:
				_water[i] = 1


## Drop water patches too small to swim in — the noisy contour leaves puddles along
## the headlands, and a two-voxel pond in the middle of a meadow just looks broken.
func _prune_specks() -> void:
	var seen := PackedByteArray()
	seen.resize(_w * _d)
	seen.fill(0)
	var stack := PackedInt32Array()
	for start in range(_w * _d):
		if _water[start] == 0 or seen[start] != 0:
			continue
		var patch := PackedInt32Array()
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while stack.size() > 0:
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			patch.append(i)
			var x := i % _w
			var z := i / _w
			if x > 0 and _water[i - 1] != 0 and seen[i - 1] == 0:
				seen[i - 1] = 1
				stack.append(i - 1)
			if x < _w - 1 and _water[i + 1] != 0 and seen[i + 1] == 0:
				seen[i + 1] = 1
				stack.append(i + 1)
			if z > 0 and _water[i - _w] != 0 and seen[i - _w] == 0:
				seen[i - _w] = 1
				stack.append(i - _w)
			if z < _d - 1 and _water[i + _w] != 0 and seen[i + _w] == 0:
				seen[i + _w] = 1
				stack.append(i + _w)
		if patch.size() >= MIN_POOL_COLUMNS:
			continue
		for j in patch:
			_water[j] = 0


## Islands are seated in genuinely offshore water and given a noisy dome so their
## outline is as irregular as the shoreline.
func _place_islands() -> void:
	var want := rng.randi_range(ISLAND_MIN, ISLAND_MAX)
	var tries := 0
	while _islands.size() < want and tries < want * 120:
		tries += 1
		var radius := rng.randi_range(ISLAND_R_MIN, ISLAND_R_MAX)
		var cx := rng.randi_range(radius + 2, maxi(radius + 3, _w - radius - 3))
		var cz := rng.randi_range(radius + 2, maxi(radius + 3, _d - radius - 3))
		if cx >= _w or cz >= _d:
			continue
		var i := cz * _w + cx
		if _water[i] == 0:
			continue
		## Needs open water all the way round, or the "island" is a peninsula.
		if _dist_dry[i] < float(radius + ISLAND_OFFSHORE):
			continue
		var clash := false
		for other: Dictionary in _islands:
			var dx := float(cx - int(other["x"]))
			var dz := float(cz - int(other["z"]))
			var gap := float(radius + int(other["r"])) + 14.0
			if dx * dx + dz * dz < gap * gap:
				clash = true
				break
		if clash:
			continue
		var rise := rng.randi_range(ISLAND_RISE_MIN, ISLAND_RISE_MAX)
		if _stamp_island(cx, cz, radius, rise) <= 0:
			continue
		_islands.append({"x": cx, "z": cz, "r": radius, "rise": rise})


## Rasterises one dome. Returns the number of land columns it claimed.
func _stamp_island(cx: int, cz: int, radius: int, rise: int) -> int:
	var claimed := 0
	var phase := rng.randf() * 40.0
	for z in range(maxi(cz - radius, 0), mini(cz + radius + 1, _d)):
		for x in range(maxi(cx - radius, 0), mini(cx + radius + 1, _w)):
			var i := z * _w + x
			if _water[i] == 0:
				continue
			var dx := float(x - cx)
			var dz := float(z - cz)
			var dist := sqrt(dx * dx + dz * dz)
			## Warp the radius by angle-stable noise so the rim lobes in and out.
			var warp := _fbm2(float(_ox + x) * 0.05 + phase, float(_oz + z) * 0.05 - phase)
			var edge := float(radius) * (0.66 + 0.5 * warp)
			if dist >= edge:
				continue
			var t := dist / edge
			var dome := pow(1.0 - t * t, 1.4)
			## Jitter the crown, or the quantised dome comes out as concentric rings.
			var bumps := _fbm2(
				float(_ox + x) * 0.115 - 12.4, float(_oz + z) * 0.115 + 31.6
			)
			var h := int(round(float(rise) * dome + (bumps - 0.5) * 1.2))
			if h < 1:
				continue
			_water[i] = 0
			_island_h[i] = h
			claimed += 1
	return claimed


## Depth ramps in from the waterline so wading in is gradual, not a cliff into 2.5 m.
func _build_depth() -> void:
	var dmax := mini(DEPTH_MAX, ground_y - 1)
	for i in range(_w * _d):
		if _water[i] == 0:
			continue
		var t := clampf(_dist_dry[i] / DEPTH_RAMP, 0.0, 1.0)
		## Sqrt profile: the first metre of water is short, the middle is flat and deep.
		var d := int(round(float(dmax) * sqrt(t)))
		_depth[i] = clampi(d, 1, dmax)


func _paint_basin() -> void:
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			if _water[i] == 0:
				continue
			var d := _depth[i]
			var wx := _ox + x
			var wz := _oz + z
			var bed := ground_y - d
			brush.set_vox(
				Vector3i(wx, bed, wz),
				VoxelMaterial.DIRT if d >= 3 else VoxelMaterial.GRAVEL
			)
			brush.column(wx, wz, bed + 1, ground_y + 1, VoxelMaterial.WATER)


func _paint_beach() -> void:
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			if _water[i] != 0 or _island_h[i] > 0:
				continue
			if _dist_wet[i] > float(BEACH_BAND):
				continue
			if _is_road_cell(x, z):
				continue
			var wx := _ox + x
			var wz := _oz + z
			## Clumped shingle: per-voxel dice read as litter sprinkled on a lawn.
			var n := _fbm2(float(wx) * 0.11, float(wz) * 0.11)
			var mat := VoxelMaterial.GRAVEL if n > 0.42 else VoxelMaterial.DIRT
			brush.set_vox(Vector3i(wx, ground_y, wz), mat)


func _paint_islands() -> void:
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			var h := _island_h[i]
			if h <= 0:
				continue
			var wx := _ox + x
			var wz := _oz + z
			## Deck voxel and everything below the crown is fill, not turf.
			brush.column(wx, wz, ground_y, ground_y + h, VoxelMaterial.DIRT)
			var top := ground_y + h
			if h <= 1:
				brush.set_vox(Vector3i(wx, top, wz), VoxelMaterial.GRAVEL)
				continue
			var n := _fbm2(float(wx) * 0.1 + 17.0, float(wz) * 0.1 - 9.0)
			var mat := VoxelMaterial.PARK
			if n > 0.86:
				mat = VoxelMaterial.STONE
			elif n > 0.78:
				mat = VoxelMaterial.DIRT
			brush.set_vox(Vector3i(wx, top, wz), mat)


func _plant_islands(density: float) -> void:
	for island: Dictionary in _islands:
		var radius := int(island["r"])
		var target := int(float(radius) * 0.7 * density)
		var made := 0
		var tries := 0
		while made < target and tries < target * 8 + 12:
			tries += 1
			var x := int(island["x"]) + rng.randi_range(-radius, radius)
			var z := int(island["z"]) + rng.randi_range(-radius, radius)
			if x < 2 or z < 2 or x >= _w - 2 or z >= _d - 2:
				continue
			var h := _island_h[z * _w + x]
			## Nothing roots on the shingle rim.
			if h <= 1:
				continue
			var wx := _ox + x
			var wz := _oz + z
			var y0 := ground_y + h
			if brush.get_vox(Vector3i(wx, y0, wz)) != VoxelMaterial.PARK:
				continue
			_stamper().plant_random(wx, y0, wz)
			made += 1


func _plant_shore(density: float) -> void:
	var target := int(240.0 * density)
	var made := 0
	var tries := 0
	while made < target and tries < target * 8:
		tries += 1
		var x := rng.randi_range(4, _w - 5)
		var z := rng.randi_range(4, _d - 5)
		var i := z * _w + x
		if _water[i] != 0 or _island_h[i] > 0:
			continue
		if _is_road_cell(x, z):
			continue
		## Keep the beach itself open so the waterline stays legible from the shore.
		if _dist_wet[i] < float(BEACH_BAND) + 2.0:
			continue
		var wx := _ox + x
		var wz := _oz + z
		if brush.get_vox(Vector3i(wx, ground_y, wz)) != VoxelMaterial.PARK:
			continue
		_stamper().plant_random(wx, ground_y, wz)
		made += 1


## Reed beds in the shallows: clumped so they read as fringe, never as a lawn of spikes.
func _scatter_reeds() -> void:
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			if _water[i] == 0 or _depth[i] > REED_MAX_DEPTH:
				continue
			var wx := _ox + x
			var wz := _oz + z
			var n := _fbm2(float(wx) * 0.14 + 61.0, float(wz) * 0.14 - 27.0)
			if n < 0.74:
				continue
			## Stipple inside the clump: a filled patch of LEAVES is a hedge, not reeds.
			if rng.randf() < 0.45:
				continue
			var h := 1 + rng.randi() % 2
			brush.column(wx, wz, ground_y + 1, ground_y + 1 + h, VoxelMaterial.LEAVES)


func _is_road_cell(x: int, z: int) -> bool:
	return LandUse.is_road(planner.tag_at((_ox + x) / cell_size, (_oz + z) / cell_size))


func _water_count() -> int:
	var n := 0
	for i in range(_w * _d):
		if _water[i] != 0:
			n += 1
	return n


func _beach_count() -> int:
	var n := 0
	for i in range(_w * _d):
		if _water[i] == 0 and _island_h[i] == 0 and _dist_wet[i] <= float(BEACH_BAND):
			n += 1
	return n


func _max_depth() -> int:
	var m := 0
	for i in range(_w * _d):
		m = maxi(m, _depth[i])
	return m


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
