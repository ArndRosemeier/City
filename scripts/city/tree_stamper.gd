## Shared tree *shape* stamps. Composers decide where / how many; this owns bark + canopy.
## World voxel coords: `(x, y0, z)` where `y0` is the surface voxel under the trunk.
class_name TreeStamper
extends RefCounted

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
