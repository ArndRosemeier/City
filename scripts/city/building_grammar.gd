## Architectural building grammars for 0.5m voxels.
## Footprints come from planner lots (~12–14 m mid-rise depth); height capped externally (~100 m).
class_name BuildingGrammar
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var floor_height: int = 6
var ground_floor_height: int = 8
var max_height: int = 200
var park: ParkComposer


func build_for_zone(
	bmin: Vector3i,
	bmax: Vector3i,
	zone: int,
	facing: int,
	corner: bool,
	on_plaza: bool,
	on_park: bool
) -> void:
	match zone:
		LandUse.CIVIC_LOT:
			civic_landmark(bmin, bmax, facing)
		LandUse.CORE_LOT:
			if corner or rng.randf() < 0.55:
				tower_podium(bmin, bmax, facing, on_plaza)
			else:
				midrise_modern(bmin, bmax, facing, on_plaza)
		LandUse.MID_LOT:
			if rng.randf() < 0.55:
				midrise_classic(bmin, bmax, facing, on_plaza)
			else:
				midrise_modern(bmin, bmax, facing, on_plaza)
		LandUse.TOWN_LOT:
			townhouse_row(bmin, bmax, facing)
		LandUse.COURTYARD_LOT:
			courtyard_block(bmin, bmax, facing)
		_:
			if on_park:
				townhouse_row(bmin, bmax, facing)
			else:
				midrise_classic(bmin, bmax, facing, on_plaza)


func townhouse_row(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var w := bmax.x - bmin.x
	# ~5.5–6.5 m frontage per townhouse (common mid-density row width).
	var unit_w_target := 12
	var units := maxi(1, w / unit_w_target)
	var unit_w := w / units
	for u in range(units):
		var umin := Vector3i(bmin.x + u * unit_w, bmin.y, bmin.z)
		var umax := Vector3i(bmin.x + (u + 1) * unit_w, bmin.y, bmax.z)
		if u == units - 1:
			umax.x = bmax.x
		var floors := rng.randi_range(3, 5)
		var wall := _pick_wall_mat(true)
		_box_floors(umin, umax, floors, wall, facing, true, false)
		_gable_roof(umin, umax, floors, facing)
		_stoop(umin, umax, facing)
		_add_awnings(umin, umax, facing, true)
		_add_balconies(umin, umax, floors, facing, 0.55)
		# Chimney
		if rng.randf() < 0.6:
			var chx := (umin.x + umax.x) / 2
			var chz := umin.z + 1 if facing != 1 else umax.z - 2
			var top := bmin.y + floors * floor_height + ground_floor_height - floor_height + 2
			brush.column(chx, chz, top, top + 3, VoxelMaterial.BRICK_DARK)


func midrise_classic(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var max_floors := maxi(5, max_height / floor_height)
	var floors := rng.randi_range(maxi(5, max_floors / 2), max_floors - 2)
	var wall := _pick_wall_mat(false)
	var base_mat := VoxelMaterial.STONE if on_plaza else VoxelMaterial.CONCRETE
	_tripartite(bmin, bmax, floors, base_mat, wall, facing, on_plaza, true)
	_retail_storefront(bmin, bmax, facing)
	_add_awnings(bmin, bmax, facing, false)
	_add_balconies(bmin, bmax, floors, facing, 0.4)
	_flat_roof_parapet(bmin, bmax, floors, VoxelMaterial.ROOF)
	_roof_clutter(bmin, bmax, floors)


func midrise_modern(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var max_floors := maxi(5, max_height / floor_height)
	var floors := rng.randi_range(maxi(5, max_floors / 2), max_floors - 1)
	var wall := VoxelMaterial.PLASTER if rng.randf() < 0.45 else (
		VoxelMaterial.CONCRETE if rng.randf() < 0.55 else VoxelMaterial.METAL
	)
	_box_floors(bmin, bmax, floors, wall, facing, true, true)
	# Soft upper setbacks
	if floors > 6:
		var inset_from := floors * 2 / 3
		for f in range(inset_from, floors):
			var y0 := _floor_y(bmin.y, f)
			var fh := _floor_h(f)
			brush.fill_box(
				Vector3i(bmin.x, y0, bmin.z),
				Vector3i(bmin.x + 1, y0 + fh, bmax.z),
				VoxelMaterial.AIR
			)
			brush.fill_box(
				Vector3i(bmax.x - 1, y0, bmin.z),
				Vector3i(bmax.x, y0 + fh, bmax.z),
				VoxelMaterial.AIR
			)
	_retail_storefront(bmin, bmax, facing)
	_add_balconies(bmin, bmax, floors, facing, 0.25)
	_flat_roof_parapet(bmin, bmax, floors, VoxelMaterial.ROOF)
	_roof_clutter(bmin, bmax, floors)
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)


func tower_podium(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var podium_floors := 2 + rng.randi() % 2
	var shaft_floors := max_height / floor_height - podium_floors
	# Podium fills lot
	_box_floors(bmin, bmax, podium_floors, VoxelMaterial.STONE if on_plaza else VoxelMaterial.CONCRETE, facing, true, true)
	_retail_storefront(bmin, bmax, facing)
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)
	# Shaft stays substantial (~8–12 m): inset scales with lot, not a tiny needle.
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	var inset := clampi(lot_w / 8, 2, 6)
	var smin := bmin + Vector3i(inset, 0, inset)
	var smax := bmax - Vector3i(inset, 0, inset)
	if smax.x - smin.x < 10 or smax.z - smin.z < 10:
		inset = maxi(1, inset - 1)
		smin = bmin + Vector3i(inset, 0, inset)
		smax = bmax - Vector3i(inset, 0, inset)
	var shaft_base_y := _floor_y(bmin.y, podium_floors)
	smin.y = shaft_base_y
	smax.y = shaft_base_y
	for f in range(shaft_floors):
		var y0 := shaft_base_y + f * floor_height
		var crown_inset := 0
		if f > shaft_floors - 4:
			crown_inset = 1
		if f > shaft_floors - 2:
			crown_inset = 2
		var fmin := Vector3i(smin.x + crown_inset, y0, smin.z + crown_inset)
		var fmax := Vector3i(smax.x - crown_inset, y0 + floor_height, smax.z - crown_inset)
		if fmax.x - fmin.x < 6 or fmax.z - fmin.z < 6:
			break
		_fill_shell(fmin, fmax, VoxelMaterial.METAL, facing, false, true, f == 0)
	var top := shaft_base_y + shaft_floors * floor_height
	brush.fill_box(
		Vector3i(smin.x + 1, top, smin.z + 1),
		Vector3i(smax.x - 1, top + 2, smax.z - 1),
		VoxelMaterial.METAL_PLATE
	)
	_roof_clutter(
		Vector3i(smin.x, bmin.y, smin.z),
		Vector3i(smax.x, bmin.y, smax.z),
		podium_floors + shaft_floors
	)


func courtyard_block(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var floors := rng.randi_range(4, mini(8, max_height / floor_height - 2))
	var wall := _pick_wall_mat(false)
	_box_floors(bmin, bmax, floors, wall, facing, true, false)
	# Wing depth ~3–4 m around a central court (euroblock-ish on a single lot).
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	var wing := clampi(lot_w / 4, 5, 8)
	var hole_min := bmin + Vector3i(wing, 1, wing)
	var hole_max := Vector3i(bmax.x - wing, _floor_y(bmin.y, floors), bmax.z - wing)
	if hole_max.x > hole_min.x + 3 and hole_max.z > hole_min.z + 3:
		brush.fill_box(hole_min, hole_max, VoxelMaterial.AIR)
		if park != null:
			park.compose_courtyard_garden(hole_min, hole_max)
		else:
			brush.fill_box(
				Vector3i(hole_min.x, bmin.y, hole_min.z),
				Vector3i(hole_max.x, bmin.y + 1, hole_max.z),
				VoxelMaterial.PARK
			)
	_add_balconies(bmin, bmax, floors, facing, 0.35)
	_flat_roof_parapet(bmin, bmax, floors, VoxelMaterial.ROOF_CLAY if rng.randf() < 0.4 else VoxelMaterial.ROOF)
	_roof_clutter(bmin, bmax, floors)


func civic_landmark(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var floors := rng.randi_range(4, 6)
	_tripartite(bmin, bmax, floors, VoxelMaterial.STONE, VoxelMaterial.STONE, facing, true, false)
	# Symmetrical grand steps on facing side
	_grand_steps(bmin, bmax, facing)
	# Cupola / clock mass at center roof
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var top := _floor_y(bmin.y, floors)
	brush.fill_box(
		Vector3i(cx - 2, top, cz - 2),
		Vector3i(cx + 3, top + 1, cz + 3),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(cx - 1, top + 1, cz - 1),
		Vector3i(cx + 2, top + 6, cz + 2),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(cx, top + 6, cz),
		Vector3i(cx + 1, top + 9, cz + 1),
		VoxelMaterial.METAL_PLATE
	)


func _floor_h(floor_index: int) -> int:
	return ground_floor_height if floor_index == 0 else floor_height


func _floor_y(base_y: int, floor_index: int) -> int:
	var y := base_y
	for f in range(floor_index):
		y += _floor_h(f)
	return y


func _box_floors(
	bmin: Vector3i,
	bmax: Vector3i,
	floors: int,
	wall: int,
	facing: int,
	door: bool,
	ribbon: bool
) -> void:
	for f in range(floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var fmin := Vector3i(bmin.x, y0, bmin.z)
		var fmax := Vector3i(bmax.x, y0 + fh, bmax.z)
		_fill_shell(fmin, fmax, wall, facing, door and f == 0, ribbon, f == 0)


func _tripartite(
	bmin: Vector3i,
	bmax: Vector3i,
	floors: int,
	base_mat: int,
	shaft_mat: int,
	facing: int,
	on_plaza: bool,
	punched: bool
) -> void:
	var base_floors := 1
	var crown_floors := 1 if floors > 4 else 0
	var shaft_floors := floors - base_floors - crown_floors
	for f in range(floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var mat := shaft_mat
		var ribbon := not punched
		if f < base_floors:
			mat = base_mat
			ribbon = on_plaza
		elif f >= floors - crown_floors and crown_floors > 0:
			mat = shaft_mat
			ribbon = false
		var inset := 0
		if f >= floors - crown_floors and crown_floors > 0:
			inset = 1
		var fmin := Vector3i(bmin.x + inset, y0, bmin.z + inset)
		var fmax := Vector3i(bmax.x - inset, y0 + fh, bmax.z - inset)
		_fill_shell(fmin, fmax, mat, facing, f == 0, ribbon, f == 0)
		# Cornice ring under crown
		if crown_floors > 0 and f == floors - crown_floors - 1:
			_cornice(fmin, Vector3i(fmax.x, y0 + fh, fmax.z))
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)


func _fill_shell(
	min_v: Vector3i,
	max_v: Vector3i,
	wall_mat: int,
	facing: int,
	door_on_ground: bool,
	ribbon_windows: bool,
	is_ground: bool
) -> void:
	## Face slabs via fill_box (O(faces)) instead of walking the full AABB volume.
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	var fh := max_v.y - min_v.y
	## Floor deck.
	brush.fill_box(
		Vector3i(min_v.x, min_v.y, min_v.z),
		Vector3i(max_v.x, min_v.y + 1, max_v.z),
		wall_mat
	)
	## Solid ground-floor fill (matches old lower_fill interior).
	if is_ground:
		var fill_h := mini(2, fh)
		if fill_h > 1:
			brush.fill_box(
				Vector3i(min_v.x + 1, min_v.y + 1, min_v.z + 1),
				Vector3i(max_v.x - 1, min_v.y + fill_h, max_v.z - 1),
				wall_mat
			)
	## Ceiling / top slab when tall enough.
	if fh >= 2:
		brush.fill_box(
			Vector3i(min_v.x, max_v.y - 1, min_v.z),
			Vector3i(max_v.x, max_v.y, max_v.z),
			wall_mat
		)
	## Four walls (full height). Corners overlap — fine.
	brush.fill_box(
		Vector3i(min_v.x, min_v.y, min_v.z),
		Vector3i(min_v.x + 1, max_v.y, max_v.z),
		wall_mat
	)
	brush.fill_box(
		Vector3i(max_v.x - 1, min_v.y, min_v.z),
		Vector3i(max_v.x, max_v.y, max_v.z),
		wall_mat
	)
	brush.fill_box(
		Vector3i(min_v.x, min_v.y, min_v.z),
		Vector3i(max_v.x, max_v.y, min_v.z + 1),
		wall_mat
	)
	brush.fill_box(
		Vector3i(min_v.x, min_v.y, max_v.z - 1),
		Vector3i(max_v.x, max_v.y, max_v.z),
		wall_mat
	)
	## Windows / doors only on façade strips (not the volume interior).
	_punch_facades(min_v, max_v, facing, door_on_ground, ribbon_windows, is_ground)


func _punch_facades(
	min_v: Vector3i,
	max_v: Vector3i,
	facing: int,
	door_on_ground: bool,
	ribbon_windows: bool,
	is_ground: bool
) -> void:
	for y in range(min_v.y, max_v.y):
		for x in range(min_v.x, max_v.x):
			_punch_facade_cell(x, y, min_v.z, min_v, max_v, facing, door_on_ground, ribbon_windows, is_ground)
			if max_v.z - 1 != min_v.z:
				_punch_facade_cell(x, y, max_v.z - 1, min_v, max_v, facing, door_on_ground, ribbon_windows, is_ground)
		for z in range(min_v.z + 1, max_v.z - 1):
			_punch_facade_cell(min_v.x, y, z, min_v, max_v, facing, door_on_ground, ribbon_windows, is_ground)
			if max_v.x - 1 != min_v.x:
				_punch_facade_cell(max_v.x - 1, y, z, min_v, max_v, facing, door_on_ground, ribbon_windows, is_ground)


func _punch_facade_cell(
	x: int,
	y: int,
	z: int,
	min_v: Vector3i,
	max_v: Vector3i,
	facing: int,
	door_on_ground: bool,
	ribbon_windows: bool,
	is_ground: bool
) -> void:
	if door_on_ground and _is_door_cell(x, y, z, min_v, max_v, facing):
		brush.set_vox(Vector3i(x, y, z), VoxelMaterial.AIR)
		return
	if _is_window_cell(x, y, z, min_v, max_v, ribbon_windows, is_ground):
		## A fraction of panes stay lit at night (emissive glass variant).
		var glass_id := VoxelMaterial.GLASS_LIT if rng.randf() < 0.28 else VoxelMaterial.GLASS
		brush.set_vox(Vector3i(x, y, z), glass_id)


func _is_door_cell(x: int, y: int, z: int, min_v: Vector3i, max_v: Vector3i, facing: int) -> bool:
	if y < min_v.y + 1 or y > min_v.y + ground_floor_height - 1:
		return false
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	match facing:
		0:
			return z == max_v.z - 1 and absi(x - cx) <= 1
		1:
			return z == min_v.z and absi(x - cx) <= 1
		2:
			return x == max_v.x - 1 and absi(z - cz) <= 1
		_:
			return x == min_v.x and absi(z - cz) <= 1


func _is_window_cell(
	x: int,
	y: int,
	z: int,
	min_v: Vector3i,
	max_v: Vector3i,
	ribbon: bool,
	is_ground: bool
) -> bool:
	var on_side := x == min_v.x or x == max_v.x - 1 or z == min_v.z or z == max_v.z - 1
	if not on_side:
		return false
	var fh := max_v.y - min_v.y
	var local_y := y - min_v.y
	if local_y <= 0:
		return false
	if fh >= 4 and local_y >= fh - 1:
		return false
	if is_ground and local_y < 2:
		return local_y >= 1 and (x + z) % 2 == 0
	if ribbon:
		var along := x if (z == min_v.z or z == max_v.z - 1) else z
		return along % 3 != 0
	if fh >= 4 and local_y == 1:
		return false
	var along2 := x if (z == min_v.z or z == max_v.z - 1) else z
	return along2 % 3 == 1


func _flat_roof_parapet(bmin: Vector3i, bmax: Vector3i, floors: int, roof_mat: int) -> void:
	var top := _floor_y(bmin.y, floors)
	brush.fill_box(
		Vector3i(bmin.x + 1, top, bmin.z + 1),
		Vector3i(bmax.x - 1, top + 1, bmax.z - 1),
		roof_mat
	)
	## Parapet ring as four edge slabs.
	brush.fill_box(Vector3i(bmin.x, top + 1, bmin.z), Vector3i(bmax.x, top + 2, bmin.z + 1), roof_mat)
	brush.fill_box(Vector3i(bmin.x, top + 1, bmax.z - 1), Vector3i(bmax.x, top + 2, bmax.z), roof_mat)
	brush.fill_box(Vector3i(bmin.x, top + 1, bmin.z + 1), Vector3i(bmin.x + 1, top + 2, bmax.z - 1), roof_mat)
	brush.fill_box(Vector3i(bmax.x - 1, top + 1, bmin.z + 1), Vector3i(bmax.x, top + 2, bmax.z - 1), roof_mat)


func _gable_roof(umin: Vector3i, umax: Vector3i, floors: int, facing: int) -> void:
	var top := _floor_y(umin.y, floors)
	var depth := umax.z - umin.z if facing == 2 or facing == 3 else umax.x - umin.x
	var steps := maxi(2, depth / 2)
	for s in range(steps):
		var inset := s
		var y := top + s
		if facing == 0 or facing == 1:
			brush.fill_box(
				Vector3i(umin.x + inset, y, umin.z),
				Vector3i(umax.x - inset, y + 1, umax.z),
				VoxelMaterial.ROOF_CLAY
			)
		else:
			brush.fill_box(
				Vector3i(umin.x, y, umin.z + inset),
				Vector3i(umax.x, y + 1, umax.z - inset),
				VoxelMaterial.ROOF_CLAY
			)


func _stoop(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var y0 := bmin.y
	match facing:
		0:
			brush.fill_box(Vector3i(cx - 1, y0, bmax.z), Vector3i(cx + 2, y0 + 1, bmax.z + 1), VoxelMaterial.STONE)
			brush.fill_box(Vector3i(cx - 1, y0 + 1, bmax.z), Vector3i(cx + 2, y0 + 2, bmax.z + 1), VoxelMaterial.STONE)
		1:
			brush.fill_box(Vector3i(cx - 1, y0, bmin.z - 1), Vector3i(cx + 2, y0 + 1, bmin.z), VoxelMaterial.STONE)
			brush.fill_box(Vector3i(cx - 1, y0 + 1, bmin.z - 1), Vector3i(cx + 2, y0 + 2, bmin.z), VoxelMaterial.STONE)
		2:
			brush.fill_box(Vector3i(bmax.x, y0, cz - 1), Vector3i(bmax.x + 1, y0 + 1, cz + 2), VoxelMaterial.STONE)
			brush.fill_box(Vector3i(bmax.x, y0 + 1, cz - 1), Vector3i(bmax.x + 1, y0 + 2, cz + 2), VoxelMaterial.STONE)
		_:
			brush.fill_box(Vector3i(bmin.x - 1, y0, cz - 1), Vector3i(bmin.x, y0 + 1, cz + 2), VoxelMaterial.STONE)
			brush.fill_box(Vector3i(bmin.x - 1, y0 + 1, cz - 1), Vector3i(bmin.x, y0 + 2, cz + 2), VoxelMaterial.STONE)


func _arcade_ground(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	## Carve arcade niches on ground facing street.
	var y0 := bmin.y + 1
	var y1 := bmin.y + ground_floor_height - 1
	match facing:
		0:
			for x in range(bmin.x + 1, bmax.x - 1, 2):
				brush.fill_box(Vector3i(x, y0, bmax.z - 1), Vector3i(x + 1, y1, bmax.z), VoxelMaterial.AIR)
		1:
			for x in range(bmin.x + 1, bmax.x - 1, 2):
				brush.fill_box(Vector3i(x, y0, bmin.z), Vector3i(x + 1, y1, bmin.z + 1), VoxelMaterial.AIR)
		2:
			for z in range(bmin.z + 1, bmax.z - 1, 2):
				brush.fill_box(Vector3i(bmax.x - 1, y0, z), Vector3i(bmax.x, y1, z + 1), VoxelMaterial.AIR)
		_:
			for z in range(bmin.z + 1, bmax.z - 1, 2):
				brush.fill_box(Vector3i(bmin.x, y0, z), Vector3i(bmin.x + 1, y1, z + 1), VoxelMaterial.AIR)


func _cornice(min_v: Vector3i, max_v: Vector3i) -> void:
	var y := max_v.y - 1
	brush.fill_box(Vector3i(min_v.x, y, min_v.z), Vector3i(max_v.x, y + 1, min_v.z + 1), VoxelMaterial.STONE)
	brush.fill_box(Vector3i(min_v.x, y, max_v.z - 1), Vector3i(max_v.x, y + 1, max_v.z), VoxelMaterial.STONE)
	brush.fill_box(Vector3i(min_v.x, y, min_v.z + 1), Vector3i(min_v.x + 1, y + 1, max_v.z - 1), VoxelMaterial.STONE)
	brush.fill_box(Vector3i(max_v.x - 1, y, min_v.z + 1), Vector3i(max_v.x, y + 1, max_v.z - 1), VoxelMaterial.STONE)


func _grand_steps(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	for s in range(3):
		match facing:
			0:
				brush.fill_box(
					Vector3i(cx - 3 + s, bmin.y + s, bmax.z + s),
					Vector3i(cx + 4 - s, bmin.y + s + 1, bmax.z + s + 1),
					VoxelMaterial.STONE
				)
			1:
				brush.fill_box(
					Vector3i(cx - 3 + s, bmin.y + s, bmin.z - s - 1),
					Vector3i(cx + 4 - s, bmin.y + s + 1, bmin.z - s),
					VoxelMaterial.STONE
				)
			2:
				brush.fill_box(
					Vector3i(bmax.x + s, bmin.y + s, cz - 3 + s),
					Vector3i(bmax.x + s + 1, bmin.y + s + 1, cz + 4 - s),
					VoxelMaterial.STONE
				)
			_:
				brush.fill_box(
					Vector3i(bmin.x - s - 1, bmin.y + s, cz - 3 + s),
					Vector3i(bmin.x - s, bmin.y + s + 1, cz + 4 - s),
					VoxelMaterial.STONE
				)


func _pick_wall_mat(townhouse: bool) -> int:
	## Per-lot palette variety standing in for albedo tint (Blocky IDs are discrete).
	var roll := rng.randf()
	if townhouse:
		if roll < 0.35:
			return VoxelMaterial.BRICK
		if roll < 0.6:
			return VoxelMaterial.BRICK_DARK
		if roll < 0.85:
			return VoxelMaterial.PLASTER
		return VoxelMaterial.STONE
	if roll < 0.28:
		return VoxelMaterial.BRICK
	if roll < 0.48:
		return VoxelMaterial.BRICK_DARK
	if roll < 0.72:
		return VoxelMaterial.PLASTER
	if roll < 0.88:
		return VoxelMaterial.CONCRETE
	return VoxelMaterial.STONE


func _retail_storefront(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	## Shallow protruding storefront band + glass on the facing ground floor.
	if rng.randf() < 0.35:
		return
	var y0 := bmin.y + 1
	var y1 := mini(bmin.y + ground_floor_height - 1, bmin.y + 5)
	var mat := VoxelMaterial.METAL_PLATE if rng.randf() < 0.4 else VoxelMaterial.STONE
	match facing:
		0:
			brush.fill_box(Vector3i(bmin.x + 1, y0, bmax.z), Vector3i(bmax.x - 1, y1, bmax.z + 1), mat)
			for x in range(bmin.x + 2, bmax.x - 2, 2):
				brush.fill_box(Vector3i(x, y0 + 1, bmax.z), Vector3i(x + 1, y1 - 1, bmax.z + 1), VoxelMaterial.GLASS)
		1:
			brush.fill_box(Vector3i(bmin.x + 1, y0, bmin.z - 1), Vector3i(bmax.x - 1, y1, bmin.z), mat)
			for x in range(bmin.x + 2, bmax.x - 2, 2):
				brush.fill_box(Vector3i(x, y0 + 1, bmin.z - 1), Vector3i(x + 1, y1 - 1, bmin.z), VoxelMaterial.GLASS)
		2:
			brush.fill_box(Vector3i(bmax.x, y0, bmin.z + 1), Vector3i(bmax.x + 1, y1, bmax.z - 1), mat)
			for z in range(bmin.z + 2, bmax.z - 2, 2):
				brush.fill_box(Vector3i(bmax.x, y0 + 1, z), Vector3i(bmax.x + 1, y1 - 1, z + 1), VoxelMaterial.GLASS)
		_:
			brush.fill_box(Vector3i(bmin.x - 1, y0, bmin.z + 1), Vector3i(bmin.x, y1, bmax.z - 1), mat)
			for z in range(bmin.z + 2, bmax.z - 2, 2):
				brush.fill_box(Vector3i(bmin.x - 1, y0 + 1, z), Vector3i(bmin.x, y1 - 1, z + 1), VoxelMaterial.GLASS)


func _add_awnings(bmin: Vector3i, bmax: Vector3i, facing: int, dense: bool) -> void:
	if rng.randf() < (0.25 if dense else 0.45):
		return
	var y := bmin.y + ground_floor_height - 1
	var mat := VoxelMaterial.PAINT if rng.randf() < 0.55 else VoxelMaterial.METAL
	match facing:
		0:
			brush.fill_box(Vector3i(bmin.x + 1, y, bmax.z), Vector3i(bmax.x - 1, y + 1, bmax.z + 2), mat)
		1:
			brush.fill_box(Vector3i(bmin.x + 1, y, bmin.z - 2), Vector3i(bmax.x - 1, y + 1, bmin.z), mat)
		2:
			brush.fill_box(Vector3i(bmax.x, y, bmin.z + 1), Vector3i(bmax.x + 2, y + 1, bmax.z - 1), mat)
		_:
			brush.fill_box(Vector3i(bmin.x - 2, y, bmin.z + 1), Vector3i(bmin.x, y + 1, bmax.z - 1), mat)


func _add_balconies(bmin: Vector3i, bmax: Vector3i, floors: int, facing: int, chance: float) -> void:
	if floors < 3 or rng.randf() > chance:
		return
	var start_f := 1
	var end_f := floors - 1
	var step := 1 if chance > 0.45 else 2
	for f in range(start_f, end_f, step):
		if rng.randf() < 0.35:
			continue
		var y0 := _floor_y(bmin.y, f) + 1
		var slab := VoxelMaterial.CONCRETE
		var rail := VoxelMaterial.METAL
		var cx := (bmin.x + bmax.x) / 2
		var cz := (bmin.z + bmax.z) / 2
		var half := 2 if (bmax.x - bmin.x) > 14 else 1
		match facing:
			0:
				brush.fill_box(Vector3i(cx - half, y0, bmax.z), Vector3i(cx + half + 1, y0 + 1, bmax.z + 2), slab)
				brush.fill_box(Vector3i(cx - half, y0 + 1, bmax.z + 1), Vector3i(cx + half + 1, y0 + 2, bmax.z + 2), rail)
			1:
				brush.fill_box(Vector3i(cx - half, y0, bmin.z - 2), Vector3i(cx + half + 1, y0 + 1, bmin.z), slab)
				brush.fill_box(Vector3i(cx - half, y0 + 1, bmin.z - 2), Vector3i(cx + half + 1, y0 + 2, bmin.z - 1), rail)
			2:
				brush.fill_box(Vector3i(bmax.x, y0, cz - half), Vector3i(bmax.x + 2, y0 + 1, cz + half + 1), slab)
				brush.fill_box(Vector3i(bmax.x + 1, y0 + 1, cz - half), Vector3i(bmax.x + 2, y0 + 2, cz + half + 1), rail)
			_:
				brush.fill_box(Vector3i(bmin.x - 2, y0, cz - half), Vector3i(bmin.x, y0 + 1, cz + half + 1), slab)
				brush.fill_box(Vector3i(bmin.x - 2, y0 + 1, cz - half), Vector3i(bmin.x - 1, y0 + 2, cz + half + 1), rail)


func _roof_clutter(bmin: Vector3i, bmax: Vector3i, floors: int) -> void:
	var top := _floor_y(bmin.y, floors) + 1
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	## AC / mechanical boxes
	if rng.randf() < 0.75:
		var ox := rng.randi_range(-3, 3)
		var oz := rng.randi_range(-3, 3)
		brush.fill_box(
			Vector3i(cx + ox - 1, top, cz + oz - 1),
			Vector3i(cx + ox + 2, top + 2, cz + oz + 2),
			VoxelMaterial.METAL_PLATE
		)
	if rng.randf() < 0.45:
		brush.fill_box(
			Vector3i(cx - 4, top, cz + 2),
			Vector3i(cx - 2, top + 1, cz + 4),
			VoxelMaterial.METAL
		)
	## Rail stubs along one parapet edge
	if rng.randf() < 0.5:
		brush.fill_box(
			Vector3i(bmin.x + 2, top + 1, bmin.z + 1),
			Vector3i(bmax.x - 2, top + 2, bmin.z + 2),
			VoxelMaterial.METAL
		)
	## Water-tower stub on taller buildings
	if floors >= 8 and rng.randf() < 0.4:
		brush.fill_box(
			Vector3i(cx - 1, top, cz - 1),
			Vector3i(cx + 2, top + 4, cz + 2),
			VoxelMaterial.METAL_PLATE
		)
		brush.column(cx, cz, top + 4, top + 6, VoxelMaterial.METAL)
