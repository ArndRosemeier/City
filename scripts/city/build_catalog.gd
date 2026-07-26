## Fun ephemeral build recipes for the B-menu. Each recipe is a list of voxels
## relative to a ground anchor (y = 0 sits on the hit cell). Front of the piece
## faces local −Z so the placer can yaw it toward the player.
class_name BuildCatalog
extends RefCounted

class Recipe:
	var id: String = ""
	var display_name: String = ""
	var hint: String = ""
	## Packed as [ox, oy, oz, material_id] per voxel — compact and typed.
	var voxels: PackedInt32Array = PackedInt32Array()


static func all() -> Array[Recipe]:
	var out: Array[Recipe] = []
	out.append(_cottage())
	out.append(_pool())
	out.append(_hot_tub())
	out.append(_dog())
	out.append(_cat())
	out.append(_duck())
	out.append(_elephant())
	out.append(_pyramid())
	out.append(_garden_arch())
	out.append(_totem())
	return out


static func by_id(recipe_id: String) -> Recipe:
	for r in all():
		if r.id == recipe_id:
			return r
	push_error("BuildCatalog.by_id: unknown recipe '%s'" % recipe_id)
	return null


static func _recipe(id: String, name: String, hint: String) -> Recipe:
	var r := Recipe.new()
	r.id = id
	r.display_name = name
	r.hint = hint
	return r


static func _add(r: Recipe, x: int, y: int, z: int, mat: int) -> void:
	r.voxels.append(x)
	r.voxels.append(y)
	r.voxels.append(z)
	r.voxels.append(mat)


static func _fill(
	r: Recipe, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, mat: int
) -> void:
	## Inclusive box in recipe space.
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for z in range(mini(z0, z1), maxi(z0, z1) + 1):
			for x in range(mini(x0, x1), maxi(x0, x1) + 1):
				_add(r, x, y, z, mat)


static func _cottage() -> Recipe:
	## ~7×7 m footprint, ~3.5 m clear walls (voxels are 0.5 m). Door is 1.5 m
	## wide × 2.5 m tall so a standard capsule (~1.7 m) walks in.
	var r := _recipe("cottage", "Cottage", "Walk-in plaster house with a clay roof")
	var half := 7
	var wall_top := 7
	var door_half_w := 1
	var door_top := 5
	_fill(r, -half, 0, -half, half, 0, half, VoxelMaterial.TILES)
	for y in range(1, wall_top + 1):
		for z in range(-half, half + 1):
			for x in range(-half, half + 1):
				var edge := x == -half or x == half or z == -half or z == half
				if not edge:
					continue
				## Front door on −Z.
				if z == -half and absi(x) <= door_half_w and y <= door_top:
					continue
				## Windows: side (+X) and rear (+Z).
				if x == half and absi(z) <= 2 and y >= 3 and y <= 5:
					_add(r, x, y, z, VoxelMaterial.GLASS)
					continue
				if z == half and absi(x) <= 2 and y >= 3 and y <= 5:
					_add(r, x, y, z, VoxelMaterial.GLASS)
					continue
				_add(r, x, y, z, VoxelMaterial.PLASTER)
	## Gable roof along X — peaks above the long walls.
	var roof_base := wall_top + 1
	for s in range(half + 1):
		var y := roof_base + s
		var inset := s
		_fill(r, -half + inset, y, -half, half - inset, y, half, VoxelMaterial.ROOF_CLAY)
	## Chimney on the ridge.
	_fill(r, 3, roof_base, 2, 4, roof_base + half + 2, 3, VoxelMaterial.BRICK)
	return r


static func _pool() -> Recipe:
	## ~14 m diameter basin (voxels are 0.5 m); water fills 4 cells deep.
	var r := _recipe("pool", "Swimming Pool", "Large stone-rimmed pool, 4 voxels deep")
	var rad := 14
	var depth := 4
	for z in range(-rad, rad + 1):
		for x in range(-rad, rad + 1):
			var d2 := x * x + z * z
			if d2 > rad * rad:
				continue
			var rim := d2 > (rad - 1) * (rad - 1)
			_add(r, x, 0, z, VoxelMaterial.STONE)
			if rim:
				for y in range(1, depth + 1):
					_add(r, x, y, z, VoxelMaterial.STONE)
			else:
				for y in range(1, depth + 1):
					_add(r, x, y, z, VoxelMaterial.WATER)
	## Dive board above the waterline, sticking out past the rim.
	_fill(r, -1, depth + 1, rad - 1, 1, depth + 1, rad + 3, VoxelMaterial.PLANTER)
	return r


static func _hot_tub() -> Recipe:
	var r := _recipe("hot_tub", "Hot Tub", "Round stone tub with warm water")
	var rad := 3
	for z in range(-rad, rad + 1):
		for x in range(-rad, rad + 1):
			var d2 := x * x + z * z
			if d2 > rad * rad:
				continue
			var rim := d2 > (rad - 1) * (rad - 1)
			_add(r, x, 0, z, VoxelMaterial.STONE)
			if rim:
				_add(r, x, 1, z, VoxelMaterial.STONE)
				_add(r, x, 2, z, VoxelMaterial.STONE)
			else:
				_add(r, x, 1, z, VoxelMaterial.WATER)
	return r


static func _dog() -> Recipe:
	var r := _recipe("dog", "Dog Statue", "Loyal stone pup")
	## Body.
	_fill(r, -1, 1, -2, 1, 3, 1, VoxelMaterial.STONE)
	## Head.
	_fill(r, -1, 3, -4, 1, 5, -2, VoxelMaterial.STONE)
	## Snout.
	_fill(r, 0, 3, -5, 0, 4, -5, VoxelMaterial.STONE)
	## Ears.
	_add(r, -1, 6, -3, VoxelMaterial.STONE)
	_add(r, 1, 6, -3, VoxelMaterial.STONE)
	## Legs.
	for lx in [-1, 1]:
		_fill(r, lx, 0, -1, lx, 1, -1, VoxelMaterial.STONE)
		_fill(r, lx, 0, 1, lx, 1, 1, VoxelMaterial.STONE)
	## Tail.
	_add(r, 0, 3, 2, VoxelMaterial.STONE)
	_add(r, 0, 4, 3, VoxelMaterial.STONE)
	return r


static func _cat() -> Recipe:
	var r := _recipe("cat", "Cat Statue", "Sitting stone feline")
	## Haunches / body.
	_fill(r, -1, 0, -1, 1, 3, 1, VoxelMaterial.STONE)
	## Chest.
	_fill(r, -1, 1, -2, 1, 3, -1, VoxelMaterial.STONE)
	## Head.
	_fill(r, -1, 4, -3, 1, 6, -1, VoxelMaterial.STONE)
	## Pointy ears.
	_add(r, -1, 7, -2, VoxelMaterial.STONE)
	_add(r, 1, 7, -2, VoxelMaterial.STONE)
	## Tail curl.
	_add(r, 2, 2, 0, VoxelMaterial.STONE)
	_add(r, 2, 3, 1, VoxelMaterial.STONE)
	_add(r, 1, 4, 1, VoxelMaterial.STONE)
	return r


static func _duck() -> Recipe:
	var r := _recipe("duck", "Duck Statue", "Chunky park duck")
	## Body.
	_fill(r, -2, 1, -1, 2, 3, 2, VoxelMaterial.STONE)
	## Head.
	_fill(r, -1, 3, -3, 1, 5, -1, VoxelMaterial.STONE)
	## Beak.
	_fill(r, 0, 3, -4, 0, 4, -4, VoxelMaterial.PAINT)
	## Feet.
	_add(r, -1, 0, 0, VoxelMaterial.PAINT)
	_add(r, 1, 0, 0, VoxelMaterial.PAINT)
	return r


static func _elephant() -> Recipe:
	var r := _recipe("elephant", "Elephant Statue", "Stocky stone elephant")
	## Body.
	_fill(r, -2, 2, -2, 2, 6, 3, VoxelMaterial.STONE)
	## Head.
	_fill(r, -2, 4, -5, 2, 7, -2, VoxelMaterial.STONE)
	## Trunk.
	_add(r, 0, 3, -6, VoxelMaterial.STONE)
	_add(r, 0, 2, -6, VoxelMaterial.STONE)
	_add(r, 0, 1, -6, VoxelMaterial.STONE)
	_add(r, 0, 1, -7, VoxelMaterial.STONE)
	## Ears.
	_fill(r, -4, 5, -4, -3, 7, -2, VoxelMaterial.STONE)
	_fill(r, 3, 5, -4, 4, 7, -2, VoxelMaterial.STONE)
	## Legs.
	for lx in [-2, 2]:
		for lz in [-1, 2]:
			_fill(r, lx, 0, lz, lx, 2, lz, VoxelMaterial.STONE)
	## Tusks.
	_add(r, -1, 3, -6, VoxelMaterial.CONCRETE)
	_add(r, 1, 3, -6, VoxelMaterial.CONCRETE)
	return r


static func _pyramid() -> Recipe:
	var r := _recipe("pyramid", "Pyramid", "Stepped desert pyramid")
	for tier in range(6):
		var half := 6 - tier
		var y := tier
		_fill(r, -half, y, -half, half, y, half, VoxelMaterial.STONE)
	## Capstone accent.
	_add(r, 0, 6, 0, VoxelMaterial.PAINT)
	return r


static func _garden_arch() -> Recipe:
	var r := _recipe("arch", "Garden Arch", "Leafy stone archway")
	## Pillars.
	_fill(r, -3, 0, 0, -3, 6, 0, VoxelMaterial.STONE)
	_fill(r, 3, 0, 0, 3, 6, 0, VoxelMaterial.STONE)
	## Arch lintel.
	_fill(r, -3, 6, 0, 3, 7, 0, VoxelMaterial.STONE)
	## Greenery.
	for x in range(-4, 5):
		_add(r, x, 7, 0, VoxelMaterial.LEAVES)
		if absi(x) >= 2:
			_add(r, x, 8, 0, VoxelMaterial.LEAVES)
	_add(r, -3, 4, -1, VoxelMaterial.LEAVES)
	_add(r, -3, 5, -1, VoxelMaterial.LEAVES)
	_add(r, 3, 4, 1, VoxelMaterial.LEAVES)
	_add(r, 3, 5, 1, VoxelMaterial.LEAVES)
	## Planter bases.
	_fill(r, -4, 0, -1, -2, 0, 1, VoxelMaterial.PLANTER)
	_fill(r, 2, 0, -1, 4, 0, 1, VoxelMaterial.PLANTER)
	return r


static func _totem() -> Recipe:
	var r := _recipe("totem", "Totem", "Stacked animal faces")
	## Pole.
	_fill(r, -1, 0, -1, 1, 12, 1, VoxelMaterial.BARK)
	## Bottom face — wide jaw.
	_fill(r, -2, 1, -2, 2, 3, -1, VoxelMaterial.PAINT)
	## Mid face — eyes.
	_fill(r, -2, 5, -2, 2, 7, -1, VoxelMaterial.BRICK)
	_add(r, -1, 6, -2, VoxelMaterial.GLASS)
	_add(r, 1, 6, -2, VoxelMaterial.GLASS)
	## Top face — beak.
	_fill(r, -2, 9, -2, 2, 11, -1, VoxelMaterial.STONE)
	_add(r, 0, 9, -3, VoxelMaterial.PAINT)
	_add(r, 0, 10, -3, VoxelMaterial.PAINT)
	## Wings.
	_fill(r, -4, 9, 0, -2, 10, 0, VoxelMaterial.STONE)
	_fill(r, 2, 9, 0, 4, 10, 0, VoxelMaterial.STONE)
	return r
