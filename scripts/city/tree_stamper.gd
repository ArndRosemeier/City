## Shared tree *shape* stamps. Composers decide where / how many; this owns bark + canopy.
## World voxel coords: `(x, y0, z)` where `y0` is the surface voxel under the trunk.
class_name TreeStamper
extends RefCounted

## How often a leafy crown hides one gem among its outer leaves. Deliberately tiny: a gem in a
## tree is meant to be something you notice once and remember, not a crop. What all the trees in
## a district can pay out together is capped by that district's gem budget anyway, so this rate
## only decides how often one is *visible* — see `DistrictEconomy`.
const CANOPY_GEM_CHANCE := 0.008
## Where in the crown it sits, as a fraction of the ellipsoid radius. Out near the rim, so it
## catches the eye from the path instead of being buried where only a carve would find it.
const CANOPY_GEM_SHELL_MIN := 0.72

var brush: CityBrush
var rng: RandomNumberGenerator


func plant_random(x: int, y0: int, z: int) -> void:
	match rng.randi() % 3:
		0:
			round_tree(x, y0, z)
		1:
			tall_tree(x, y0, z)
		_:
			wide_tree(x, y0, z)


## Voxels are 0.5 m. Park-scale deciduous: 3–7 m of trunk under an ellipsoid crown.
func round_tree(x: int, y0: int, z: int) -> void:
	var trunk_h := 5 + rng.randi() % 3
	var r := 3 + rng.randi() % 2
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	_canopy(x, y0 + trunk_h + r - 2, z, r, r - 1)


func tall_tree(x: int, y0: int, z: int) -> void:
	## Narrow upright crown — promenade rows and street accents.
	var trunk_h := 7 + rng.randi() % 3
	var ry := 3 + rng.randi() % 2
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	_canopy(x, y0 + trunk_h + ry - 2, z, 2 + rng.randi() % 2, ry)


func wide_tree(x: int, y0: int, z: int) -> void:
	## Low spreading crown — shade tree on the lawn.
	var trunk_h := 4 + rng.randi() % 3
	var r := 4 + rng.randi() % 2
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	_canopy(x, y0 + trunk_h + 1, z, r, 2)


## Churchyard cypress: bark trunk + narrow YEW spindle.
func cypress(x: int, y0: int, z: int) -> void:
	var trunk := 4 + rng.randi() % 3
	var h := 9 + rng.randi() % 7
	for dy in range(trunk):
		brush.set_vox(Vector3i(x, y0 + 1 + dy, z), VoxelMaterial.BARK)
	for dy in range(h):
		var t := float(dy) / float(h - 1)
		## Bare trunk, then a spindle crown that tapers to a point.
		var r := 1 if t < 0.15 else (2 if t < 0.6 else (1 if t < 0.9 else 0))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and r > 1:
					continue
				if rng.randf() < 0.1:
					continue
				brush.set_vox(Vector3i(x + dx, y0 + trunk + dy, z + dz), VoxelMaterial.YEW)


## Landmark evergreen: bare lower trunk, then wide horizontal whorls that taper
## toward the tip — pine silhouette, not a pole with a leaf blob.
## `height_m` is total height in metres (0.5 m cells). <= 0 picks ~14–18 m.
func landmark_tree(x: int, y0: int, z: int, height_m: float = -1.0) -> void:
	## Clearance under the first shelf (~2 m) then a tall tapering crown.
	var clear := 4
	var trunk_h: int
	if height_m <= 0.0:
		trunk_h = clear + 24 + rng.randi() % 8
	else:
		trunk_h = maxi(clear + 8, int(round(height_m / 0.5)))
	var canopy_h := trunk_h - clear
	var trunk_bot := y0 + 1
	var tip_y := trunk_bot + trunk_h - 1
	brush.column(x, z, trunk_bot, tip_y + 1, VoxelMaterial.BARK)
	## Thicker bare trunk (~1 m across) through the clearance — a single cell reads as a stick.
	for dy in range(clear + 1):
		var y := trunk_bot + dy
		for dx in [-1, 1]:
			brush.set_vox(Vector3i(x + dx, y, z), VoxelMaterial.BARK)
		for dz in [-1, 1]:
			brush.set_vox(Vector3i(x, y, z + dz), VoxelMaterial.BARK)

	var canopy_bot := trunk_bot + clear
	## Crown radius scales with height; short trees stay narrower.
	var r_base := clampi(int(round(float(trunk_h) * 0.22)), 4, 9)
	## Per-tree phase so neighbouring pines don't share one coplanar air gap.
	var layer_y := canopy_bot + rng.randi() % 2
	while layer_y <= tip_y:
		var t := float(layer_y - canopy_bot) / float(maxi(canopy_h - 1, 1))
		## Widest just above the bare trunk; gentle taper, still a little width near the tip.
		var r_max := r_base + rng.randi() % 2
		var r := maxi(1, int(round(float(r_max) * (1.0 - t * 0.78))))
		if t > 0.88:
			r = maxi(1, r - 1)
		var rays := 4 + rng.randi() % 3
		var start_ang := rng.randi() % 8
		for ri in range(rays):
			if rng.randf() < 0.12:
				continue
			var ang := (start_ang + ri * 8 / rays) % 8
			var len_steps := maxi(2, r + rng.randi_range(-1, 1))
			## Jitter attach height per ray — coplanar shelves were reading as one air-line.
			var attach_y := layer_y + rng.randi_range(-1, 1)
			attach_y = clampi(attach_y, canopy_bot, tip_y)
			## Lower arms droop; upper ones lift — weighted pine, not flat discs.
			var rise := 0
			if t < 0.35 and rng.randf() < 0.55:
				rise = -1
			elif t > 0.55 and rng.randf() < 0.6:
				rise = 1
			_whorl_ray(x, attach_y, z, ang, len_steps, rise)
		## Step by 1–2 so clumps overlap vertically; porosity comes from skipped rays, not a gap band.
		layer_y += 1 + rng.randi() % 2
	## Narrow tip tuft on the last trunk cells.
	_needle_clump(x, tip_y, z, 1)
	if tip_y - 1 > canopy_bot:
		_needle_clump(x, tip_y - 1, z, 1)


## Walk one shelf arm out from the trunk. `ang` is 0..7 (cardinals + diagonals).
func _whorl_ray(tx: int, ty: int, tz: int, ang: int, len_steps: int, rise: int) -> void:
	var step := _oct_step(ang)
	var px := tx
	var pz := tz
	var py := ty
	var tip := Vector3i(tx, ty, tz)
	for s in range(len_steps):
		px += step.x
		pz += step.y
		if rise != 0 and s > 0 and s % 2 == 0:
			py += rise
			rise = 0
		## Cardinals get a dedicated branch mesh; diagonals alternate X/Z wood.
		var mat := VoxelMaterial.BARK
		if step.x != 0 and step.y == 0:
			mat = VoxelMaterial.BRANCH_X
		elif step.y != 0 and step.x == 0:
			mat = VoxelMaterial.BRANCH_Z
		elif (s % 2) == 0:
			mat = VoxelMaterial.BRANCH_X
		else:
			mat = VoxelMaterial.BRANCH_Z
		brush.set_vox(Vector3i(px, py, pz), mat)
		tip = Vector3i(px, py, pz)
		## Mid-arm needles so vertical fill isn't only tip spheres (those left empty bands).
		if s >= len_steps / 2 and rng.randf() < 0.35:
			_needle_clump(px, py, pz, 1)
		## Short side fork on longer arms — breaks the "perfect spoke" look.
		if s >= len_steps - 2 and len_steps >= 4 and rng.randf() < 0.4:
			var side := _oct_step((ang + (2 if rng.randf() < 0.5 else 6)) % 8)
			var fx := px + side.x
			var fz := pz + side.y
			var fmat := (
				VoxelMaterial.BRANCH_X if absi(side.x) >= absi(side.y) else VoxelMaterial.BRANCH_Z
			)
			brush.set_vox(Vector3i(fx, py, fz), fmat)
			_needle_clump(fx, py, fz, 1 + rng.randi() % 2)
	## Outer third carries the needle puff; inner wood stays readable.
	var clump_r := 1 if len_steps <= 3 else (2 if len_steps <= 5 else 2 + rng.randi() % 2)
	_needle_clump(tip.x, tip.y, tip.z, clump_r)


func _oct_step(ang: int) -> Vector2i:
	match ang % 8:
		0:
			return Vector2i(1, 0)
		1:
			return Vector2i(1, 1)
		2:
			return Vector2i(0, 1)
		3:
			return Vector2i(-1, 1)
		4:
			return Vector2i(-1, 0)
		5:
			return Vector2i(-1, -1)
		6:
			return Vector2i(0, -1)
		_:
			return Vector2i(1, -1)


## Compact evergreen puff — YEW needles, darker underside for depth.
func _needle_clump(cx: int, cy: int, cz: int, r: int) -> void:
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n2 := dx * dx + dy * dy + dz * dz
				if n2 > r * r:
					continue
				if n2 > (r - 1) * (r - 1) and rng.randf() < 0.35:
					continue
				var mat := VoxelMaterial.LEAVES_DARK if dy < 0 else VoxelMaterial.YEW
				if dy == 0 and rng.randf() < 0.25:
					mat = VoxelMaterial.LEAVES_DARK
				brush.set_vox(Vector3i(cx + dx, cy + dy, cz + dz), mat)


## Bare skeleton — bark column + stub branches, no foliage.
func dead_tree(x: int, y0: int, z: int) -> void:
	var h := 8 + rng.randi() % 5
	for dy in range(h):
		brush.set_vox(Vector3i(x, y0 + 1 + dy, z), VoxelMaterial.BARK)
	for _b in range(3 + rng.randi() % 3):
		var y := y0 + 4 + rng.randi() % maxi(h - 3, 1)
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		var dir := dirs[rng.randi() % 4]
		var px := x
		var pz := z
		for step in range(1 + rng.randi() % 2):
			px += dir.x
			pz += dir.y
			brush.set_vox(Vector3i(px, y + step, pz), VoxelMaterial.BARK)


func _canopy(cx: int, cy: int, cz: int, rxz: int, ry: int) -> void:
	## Ellipsoid leaf mass with a ragged rim so crowns are not identical blobs.
	for dy in range(-ry, ry + 1):
		for dz in range(-rxz, rxz + 1):
			for dx in range(-rxz, rxz + 1):
				var n := (
					float(dx * dx + dz * dz) / float(rxz * rxz)
					+ float(dy * dy) / float(ry * ry)
				)
				if n > 1.0:
					continue
				if n > 0.68 and rng.randf() < 0.35:
					continue
				brush.set_vox(Vector3i(cx + dx, cy + dy, cz + dz), VoxelMaterial.LEAVES)
	_maybe_hide_gem(cx, cy, cz, rxz, ry)


## Occasionally swap one outer leaf for a gem. The rarity curve is the city-wide one, so the
## tree that has anything at all is most often holding quartz.
func _maybe_hide_gem(cx: int, cy: int, cz: int, rxz: int, ry: int) -> void:
	if rng.randf() >= CANOPY_GEM_CHANCE:
		return
	for _attempt in range(12):
		var dx := rng.randi_range(-rxz, rxz)
		var dy := rng.randi_range(-ry, ry)
		var dz := rng.randi_range(-rxz, rxz)
		var n := (
			float(dx * dx + dz * dz) / float(rxz * rxz)
			+ float(dy * dy) / float(ry * ry)
		)
		if n > 1.0 or n < CANOPY_GEM_SHELL_MIN:
			continue
		brush.set_vox(Vector3i(cx + dx, cy + dy, cz + dz), VoxelMaterial.pick_gem(rng))
		return
