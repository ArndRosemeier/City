## Architectural building grammars for 0.5m voxels.
## Footprints come from planner lots (~12–14 m mid-rise depth); height capped externally (~100 m).
class_name BuildingGrammar
extends RefCounted

const CastleDoorwayScript := preload("res://scripts/city/castle_doorway.gd")

var brush: CityBrush
var rng: RandomNumberGenerator
## Palette and archetype weights for the district this lot sits in.
var theme: DistrictTheme
var floor_height: int = 6
var ground_floor_height: int = 8
var max_height: int = 200
var park: ParkComposer
## Primitive an impostor part is drawn with. Round buildings used to get box shells,
## so a cylindrical landmark turned back into a plain block as soon as it was far away.
enum ImpostorShape {
	BOX,
	CYLINDER,
	SPHERE,
	## Triangular prism for pitched roofs. The ridge runs along the part's local Z, so
	## `yaw` turns it to face the street.
	PRISM,
}

## Top of the voxels the last `build_for_zone` actually painted, in voxels above the
## lot base. The far-LOD impostor reads this: using the height *cap* instead made
## distant shells taller than the real building.
var built_height_vox: int = 0
## Coarse massing of the last building, in district voxel space, as
## `{shape, center: Vector3, size: Vector3, yaw: float}`. The far LOD renders these
## instead of guessing a stack of boxes from the zone, so cylinders stay round, arches
## and courtyards keep their voids, and twisted stacks keep turning.
var impostor_parts: Array[Dictionary] = []
## Last L/T footprint parts from `_massed_floors` so roofs match (re-roll would diverge).
var _mass_parts_cache: Array = []
## Ground-floor street doors punched this build (district-local CastleDoorway).
var lot_doorways: Array = []
## Last massing: storey count and lot box (district-local) for elevator emit.
var last_floors: int = 0
var last_facing: int = 0
var last_bmin: Vector3i = Vector3i.ZERO
var last_bmax: Vector3i = Vector3i.ZERO


func build_for_zone(
	bmin: Vector3i,
	bmax: Vector3i,
	zone: int,
	facing: int,
	corner: bool,
	on_plaza: bool,
	on_park: bool
) -> void:
	if theme == null:
		push_error("BuildingGrammar.build_for_zone: theme not set")
		return
	_mass_parts_cache.clear()
	built_height_vox = 0
	impostor_parts.clear()
	lot_doorways.clear()
	last_floors = 0
	last_facing = facing
	last_bmin = bmin
	last_bmax = bmax
	## Wild forms need room for a hole / arch / pod cluster, and they only belong on
	## the bigger commercial zones — a twisted tower on a townhouse lot is nonsense.
	var wild_zone := (
		zone == LandUse.CORE_LOT
		or zone == LandUse.MID_LOT
		or zone == LandUse.CIVIC_LOT
	)
	if wild_zone and _footprint_wide_enough(bmin, bmax, 16, 16) and rng.randf() < theme.wild_chance:
		wild_building(bmin, bmax, facing, on_plaza)
		return
	match zone:
		LandUse.CIVIC_LOT:
			if rng.randf() < theme.spiral_chance:
				spiral_tower(bmin, bmax, facing, true)
			else:
				civic_landmark(bmin, bmax, facing)
		LandUse.CORE_LOT:
			if corner or rng.randf() < theme.tower_chance:
				## Spirals are corner landmarks — don't replace the fat podium towers
				## that carry the skyline. Non-corner lots almost always stay tower_podium.
				var spiral := rng.randf() < theme.spiral_chance and (
					corner or rng.randf() < 0.2
				)
				if spiral:
					spiral_tower(bmin, bmax, facing, false)
				else:
					tower_podium(bmin, bmax, facing, on_plaza)
			else:
				midrise_modern(bmin, bmax, facing, on_plaza)
		LandUse.MID_LOT:
			## Cylinder only after the modern/classic roll so tall midrise isn't replaced
			## by short silos on high-intensity lots.
			if rng.randf() < theme.modern_chance:
				if rng.randf() < theme.cylinder_chance:
					cylinder_midrise(bmin, bmax, facing, on_plaza)
				else:
					midrise_modern(bmin, bmax, facing, on_plaza)
			elif rng.randf() < theme.cylinder_chance:
				cylinder_midrise(bmin, bmax, facing, on_plaza)
			else:
				midrise_classic(bmin, bmax, facing, on_plaza)
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
		var floors := rng.randi_range(2, _floors_for_cap(2, 5))
		var wall := _pick_wall_mat(true)
		var eaves := _floor_y(umin.y, floors)
		## Each row unit gets its own walls-plus-pitched-roof pair, so a row reads as a
		## row of houses at distance instead of one long block.
		if rng.randf() < theme.l_mass_chance and _footprint_wide_enough(umin, umax, 10, 10):
			_massed_floors(umin, umax, floors, wall, facing, true, false)
			## Capture the wings first: _gable_roof_massed clears the cache.
			var wings := _mass_parts_cache.duplicate()
			for part: Array in wings:
				var pmin: Vector3i = part[0]
				var pmax: Vector3i = part[1]
				_note_box(Vector3i(pmin.x, umin.y, pmin.z), Vector3i(pmax.x, eaves, pmax.z))
			_gable_roof_massed(umin, umax, floors, facing)
		else:
			_box_floors(umin, umax, floors, wall, facing, true, false)
			_note_box(Vector3i(umin.x, umin.y, umin.z), Vector3i(umax.x, eaves, umax.z))
			_gable_roof(umin, umax, floors, facing)
		_stoop(umin, umax, facing)
		_add_awnings(umin, umax, facing, true)
		_add_balconies(umin, umax, floors, facing, 0.55)
		# Chimney
		if rng.randf() < 0.6:
			var chx := (umin.x + umax.x) / 2
			var chz := umin.z + 1 if facing != 1 else umax.z - 2
			var top := bmin.y + floors * floor_height + ground_floor_height - floor_height + 2
			brush.column(chx, chz, top, top + 3, theme.wall_for(rng, true))


func midrise_classic(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var max_floors := _floors_for_cap(3, 40)
	var lo := maxi(3, max_floors / 2)
	var floors := rng.randi_range(lo, maxi(lo, max_floors - 2))
	var wall := _pick_wall_mat(false)
	var base_mat := VoxelMaterial.STONE if on_plaza else theme.base_mat
	if rng.randf() < theme.l_mass_chance and _footprint_wide_enough(bmin, bmax, 12, 12):
		_massed_floors(bmin, bmax, floors, wall, facing, true, false)
	else:
		_tripartite(bmin, bmax, floors, base_mat, wall, facing, on_plaza, true)
	_retail_storefront(bmin, bmax, facing)
	_add_awnings(bmin, bmax, facing, false)
	_add_balconies(bmin, bmax, floors, facing, 0.4)
	_flat_roof_parapet_massed(bmin, bmax, floors, theme.roof_for(rng), facing)
	_roof_clutter(bmin, bmax, floors)
	_note_height(bmin.y, _floor_y(bmin.y, floors) + 2)
	_note_massed_box(bmin, bmax, _floor_y(bmin.y, floors) + 2)


func midrise_modern(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var max_floors := _floors_for_cap(3, 40)
	var lo := maxi(3, max_floors / 2)
	var floors := rng.randi_range(lo, maxi(lo, max_floors - 1))
	var wall := _pick_wall_mat(false)
	if rng.randf() < theme.l_mass_chance and _footprint_wide_enough(bmin, bmax, 12, 12):
		_massed_floors(bmin, bmax, floors, wall, facing, true, true)
	else:
		_box_floors(bmin, bmax, floors, wall, facing, true, true)
	## Stronger stepped crowns (Core / modern identity).
	_stepped_setback_stack(bmin, bmax, floors, facing, floors > 5)
	_retail_storefront(bmin, bmax, facing)
	_add_balconies(bmin, bmax, floors, facing, 0.25)
	_flat_roof_parapet_massed(bmin, bmax, floors, theme.roof_for(rng), facing)
	_roof_clutter(bmin, bmax, floors)
	var top_y := _floor_y(bmin.y, floors) + 2
	_note_height(bmin.y, top_y)
	## Split the shell at the setback line so the crown steps in at distance too.
	if _mass_parts_cache.is_empty() and floors >= 7:
		var step_y := _floor_y(bmin.y, floors * 2 / 3)
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, step_y, bmax.z))
		if facing == 0 or facing == 1:
			_note_box(Vector3i(bmin.x + 1, step_y, bmin.z), Vector3i(bmax.x - 1, top_y, bmax.z))
		else:
			_note_box(Vector3i(bmin.x, step_y, bmin.z + 1), Vector3i(bmax.x, top_y, bmax.z - 1))
	else:
		_note_massed_box(bmin, bmax, top_y)
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)


func tower_podium(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var podium_floors := 2 + rng.randi() % 2
	## Never collapse to a podium-only "house" — core towers need a real shaft.
	var shaft_floors := maxi(8, max_height / floor_height - podium_floors)
	# Podium fills lot
	_box_floors(bmin, bmax, podium_floors, VoxelMaterial.STONE if on_plaza else theme.base_mat, facing, true, true)
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
	## Two-tone shaft: spandrel bands and pilaster stripes break up the flat metal.
	var band := theme.band_for(rng)
	var band_every := 3 + rng.randi() % 3
	var built_floors := 0
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
		var mat := band if f % band_every == band_every - 1 else theme.tower_shaft_mat
		_fill_shell(fmin, fmax, mat, facing, false, true, f == 0)
		built_floors = f + 1
	## Corner pilasters over the whole shaft height (vertical rhythm).
	var shaft_top := shaft_base_y + built_floors * floor_height
	if rng.randf() < 0.7:
		_corner_pilasters(smin, smax, shaft_base_y, shaft_top, band)
	brush.fill_box(
		Vector3i(smin.x + 1, shaft_top, smin.z + 1),
		Vector3i(smax.x - 1, shaft_top + 2, smax.z - 1),
		VoxelMaterial.METAL_PLATE
	)
	_roof_clutter(
		Vector3i(smin.x, bmin.y, smin.z),
		Vector3i(smax.x, bmin.y, smax.z),
		podium_floors + built_floors
	)
	_note_height(bmin.y, shaft_top + 2)
	_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, shaft_base_y, bmax.z))
	## Shaft, then the inset crown the loop tapered to over its last floors.
	var crown_y := shaft_base_y + maxi(built_floors - 3, 0) * floor_height
	if crown_y > shaft_base_y:
		_note_box(Vector3i(smin.x, shaft_base_y, smin.z), Vector3i(smax.x, crown_y, smax.z))
	_note_box(
		Vector3i(smin.x + 2, crown_y, smin.z + 2),
		Vector3i(smax.x - 2, shaft_top + 2, smax.z - 2)
	)
	## Elevator landings span podium + shaft (not just the podium _box_floors note).
	_note_storeys(bmin, bmax, podium_floors + built_floors, facing)


func courtyard_block(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var top_floors := mini(8, _floors_for_cap(3, 40))
	var floors := rng.randi_range(mini(4, top_floors), top_floors)
	var wall := _pick_wall_mat(false)
	_box_floors(bmin, bmax, floors, wall, facing, true, false)
	# Wing depth ~3–4 m around a central court (euroblock-ish on a single lot).
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	var wing := clampi(lot_w / 4, 5, 8)
	var hole_min := bmin + Vector3i(wing, 1, wing)
	var hole_max := Vector3i(bmax.x - wing, _floor_y(bmin.y, floors), bmax.z - wing)
	if hole_max.x > hole_min.x + 3 and hole_max.z > hole_min.z + 3:
		brush.fill_box(hole_min, hole_max, VoxelMaterial.AIR)
		## Open one side toward the street → U / C court (theme-driven).
		if rng.randf() < theme.l_mass_chance:
			_open_courtyard_to_street(hole_min, hole_max, bmin, bmax, facing, floors)
		if park != null:
			park.compose_courtyard_garden(hole_min, hole_max)
		else:
			brush.fill_box(
				Vector3i(hole_min.x, bmin.y, hole_min.z),
				Vector3i(hole_max.x, bmin.y + 1, hole_max.z),
				VoxelMaterial.PARK
			)
	_add_balconies(bmin, bmax, floors, facing, 0.35)
	_flat_roof_parapet(bmin, bmax, floors, theme.roof_for(rng))
	_roof_clutter(bmin, bmax, floors)
	var top_y := _floor_y(bmin.y, floors) + 2
	_note_height(bmin.y, top_y)
	## Four perimeter wings, not one block: a solid shell would fill in the court.
	if hole_max.x > hole_min.x + 3 and hole_max.z > hole_min.z + 3:
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, top_y, hole_min.z))
		_note_box(Vector3i(bmin.x, bmin.y, hole_max.z), Vector3i(bmax.x, top_y, bmax.z))
		_note_box(Vector3i(bmin.x, bmin.y, hole_min.z), Vector3i(hole_min.x, top_y, hole_max.z))
		_note_box(Vector3i(hole_max.x, bmin.y, hole_min.z), Vector3i(bmax.x, top_y, hole_max.z))
	else:
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, top_y, bmax.z))


func civic_landmark(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var floors := rng.randi_range(4, 6)
	if rng.randf() < theme.l_mass_chance and _footprint_wide_enough(bmin, bmax, 14, 14):
		_massed_floors(bmin, bmax, floors, VoxelMaterial.STONE, facing, true, false)
	else:
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
	## Optional stone cylinder annex (campanile stub beside the hall).
	if rng.randf() < theme.cylinder_chance:
		_civic_cylinder_annex(bmin, bmax, facing, top)
	_note_height(bmin.y, top + 9)
	_note_massed_box(bmin, bmax, top)
	## Cupola drum and lantern read as a landmark against a flat skyline.
	_note_cylinder(cx, cz, top, top + 6, 3)
	_note_box(Vector3i(cx - 1, top + 6, cz - 1), Vector3i(cx + 2, top + 9, cz + 2))


## Title-art spiral: rect podium + hollow cylinder shaft + external helix stair.
## `campanile` = shorter stone civic variant.
func spiral_tower(bmin: Vector3i, bmax: Vector3i, facing: int, campanile: bool = false) -> void:
	var podium_floors := 1 if campanile else (1 + rng.randi() % 2)
	var shaft_mat := VoxelMaterial.STONE if campanile else theme.tower_shaft_mat
	var base_mat := VoxelMaterial.STONE if campanile else theme.base_mat
	_box_floors(bmin, bmax, podium_floors, base_mat, facing, true, false)
	if campanile:
		_grand_steps(bmin, bmax, facing)
	else:
		_retail_storefront(bmin, bmax, facing)
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	## Thick enough to read as a landmark (not a 1-voxel needle).
	var radius := clampi(lot_w / 2 - 1, 5, 10)
	var shaft_base := _floor_y(bmin.y, podium_floors)
	var shaft_h: int
	if campanile:
		shaft_h = rng.randi_range(floor_height * 6, floor_height * 11)
	else:
		## Same height budget as tower_podium shafts (floors × floor_height).
		var shaft_floors := maxi(12, max_height / floor_height - podium_floors)
		shaft_h = shaft_floors * floor_height
	var wall_thick := 2 if radius >= 6 else 1
	## Deck under shaft, hollow shell.
	brush.fill_disk(cx, cz, shaft_base, radius, shaft_mat)
	## Banded in floor-tall rings, plus a wider cornice ring every few floors — a
	## single-material shaft reads as a flat grey pipe from any distance.
	var band := theme.band_for(rng)
	var band_every := 3 + rng.randi() % 3
	var rings := maxi(1, shaft_h / floor_height)
	for r in range(rings):
		var ry0 := shaft_base + 1 + r * floor_height
		var ry1 := mini(ry0 + floor_height, shaft_base + shaft_h)
		if ry1 <= ry0:
			break
		var is_band := r % band_every == band_every - 1
		brush.fill_cylinder_shell(
			cx, cz, ry0, ry1, radius, band if is_band else shaft_mat, true, wall_thick
		)
		if is_band:
			brush.fill_disk_ring(cx, cz, ry1 - 1, radius + 1, 1, band)
	brush.fill_cylinder_shell(
		cx,
		cz,
		shaft_base + 1 + rings * floor_height,
		shaft_base + shaft_h,
		radius,
		shaft_mat,
		true,
		wall_thick
	)
	_punch_cylinder_windows(cx, cz, shaft_base + 2, shaft_base + shaft_h - 2, radius)
	## External spiral stair (title-art wrap) — 2-voxel-wide treads.
	var stair_r := radius + 1
	var steps_per_turn := maxi(12, int(TAU * float(stair_r)))
	var angle_step := TAU / float(steps_per_turn)
	var tread := theme.accent_mat if campanile else VoxelMaterial.STONE
	var a := 0.0
	for y in range(shaft_base, shaft_base + shaft_h):
		var sx := cx + int(round(cos(a) * float(stair_r)))
		var sz := cz + int(round(sin(a) * float(stair_r)))
		brush.set_vox(Vector3i(sx, y, sz), tread)
		var sx2 := cx + int(round(cos(a) * float(stair_r + 1)))
		var sz2 := cz + int(round(sin(a) * float(stair_r + 1)))
		brush.set_vox(Vector3i(sx2, y, sz2), tread)
		if (y - shaft_base) % 2 == 0:
			brush.set_vox(Vector3i(sx2, y + 1, sz2), VoxelMaterial.METAL)
		if (y - shaft_base) % 3 == 0:
			var rx := cx + int(round(cos(a) * float(stair_r + 2)))
			var rz := cz + int(round(sin(a) * float(stair_r + 2)))
			brush.column(rx, rz, y, y + 3, VoxelMaterial.METAL)
		a += angle_step
	var top := shaft_base + shaft_h
	brush.fill_disk(cx, cz, top, radius, shaft_mat)
	brush.fill_disk_ring(cx, cz, top + 1, radius, 1, theme.roof_for(rng))
	brush.fill_disk_ring(cx, cz, top + 2, maxi(2, radius - 1), 1, theme.accent_mat)
	brush.column(cx, cz, top + 2, top + 8, VoxelMaterial.METAL)
	_roof_clutter(
		Vector3i(cx - radius, bmin.y, cz - radius),
		Vector3i(cx + radius + 1, bmin.y, cz + radius + 1),
		podium_floors + shaft_h / maxi(floor_height, 1)
	)
	_note_height(bmin.y, top + 8)
	_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, shaft_base, bmax.z))
	## Round shaft stays round at distance — this is the whole point of the landmark.
	## The stair helix wraps one voxel wider, so the shell covers it.
	_note_cylinder(cx, cz, shaft_base, top + 2, radius + 2)


## Round midrise / silo — Waterfront identity; also Civic annexes via cylinder_chance.
func cylinder_midrise(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	## Honor the lot height cap — short "family silo" was eating midrise skyline.
	var floors := rng.randi_range(maxi(4, _floors_for_cap(4, 24) / 2), _floors_for_cap(4, 28))
	var wall := _pick_wall_mat(false)
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	var radius := clampi(lot_w / 2 - 1, 5, 10)
	var top_y := _floor_y(bmin.y, floors)
	## Low shed bar along the street when lot is wide enough (silo + warehouse).
	if _footprint_wide_enough(bmin, bmax, 14, 12) and rng.randf() < 0.65:
		var bar := _street_bar_aabb(bmin, bmax, facing)
		_box_floors(bar[0], bar[1], mini(2, floors), theme.base_mat, facing, true, false)
		_retail_storefront(bar[0], bar[1], facing)
	else:
		## Door punch on cylinder via a small porch box on the facing side.
		_cylinder_porch(bmin, bmax, facing, theme.base_mat)
	brush.fill_disk(cx, cz, bmin.y, radius, wall)
	brush.fill_cylinder_shell(cx, cz, bmin.y + 1, top_y, radius, wall, true, 2)
	_punch_cylinder_windows(cx, cz, bmin.y + 2, top_y - 1, radius)
	var roof_mat := theme.roof_for(rng)
	brush.fill_disk(cx, cz, top_y, radius, roof_mat)
	brush.fill_disk_ring(cx, cz, top_y + 1, radius, 1, roof_mat)
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)
	_note_height(bmin.y, top_y + 2)
	_note_cylinder(cx, cz, bmin.y, top_y + 2, radius)


## Pick one of the deliberately strange forms. Weighted per district by what fits:
## Core likes twists and pierced slabs, Civic the grand arch, Waterfront the blobs.
func wild_building(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var roll := rng.randf()
	match theme.id:
		DistrictTheme.CORE_HIGHRISE:
			if roll < 0.42:
				twisted_stack(bmin, bmax, facing)
			elif roll < 0.8:
				hole_tower(bmin, bmax, facing, on_plaza)
			else:
				blob_stack(bmin, bmax, facing)
		DistrictTheme.CIVIC_QUARTER:
			if roll < 0.5:
				arch_gate(bmin, bmax, facing)
			elif roll < 0.82:
				hole_tower(bmin, bmax, facing, on_plaza)
			else:
				twisted_stack(bmin, bmax, facing)
		DistrictTheme.WATERFRONT_INDUSTRIAL:
			if roll < 0.6:
				blob_stack(bmin, bmax, facing)
			elif roll < 0.85:
				arch_gate(bmin, bmax, facing)
			else:
				hole_tower(bmin, bmax, facing, on_plaza)
		DistrictTheme.OLD_TOWN:
			if roll < 0.65:
				arch_gate(bmin, bmax, facing)
			else:
				hole_tower(bmin, bmax, facing, on_plaza)
		_:
			if roll < 0.55:
				arch_gate(bmin, bmax, facing)
			else:
				blob_stack(bmin, bmax, facing)


## Slab with one or two sky holes punched clean through (Grande Arche / CCTV energy).
func hole_tower(bmin: Vector3i, bmax: Vector3i, facing: int, on_plaza: bool) -> void:
	var floors := rng.randi_range(maxi(6, _floors_for_cap(6, 26) / 2), _floors_for_cap(6, 30))
	var wall := _pick_wall_mat(false)
	var band := theme.band_for(rng)
	## Alternating material bands read as a striped megastructure, not a grey slab.
	var band_every := 2 + rng.randi() % 3
	for f in range(floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var mat := band if f % band_every == band_every - 1 else wall
		_fill_shell(
			Vector3i(bmin.x, y0, bmin.z),
			Vector3i(bmax.x, y0 + fh, bmax.z),
			mat,
			facing,
			f == 0,
			true,
			f == 0
		)
	var holes := 1 + (1 if floors >= 14 and rng.randf() < 0.55 else 0)
	## `[y0, y1, pier_inset]` per opening, reused below to cut the impostor shell.
	var hole_spans: Array[Array] = []
	for h in range(holes):
		var band_lo := 2 + h * (floors / maxi(holes, 1))
		var band_hi := mini(floors - 2, band_lo + 2 + rng.randi() % 3)
		if band_hi <= band_lo:
			continue
		var y0 := _floor_y(bmin.y, band_lo)
		var y1 := _floor_y(bmin.y, band_hi)
		var inset := 2 + rng.randi() % 3
		hole_spans.append([y0, y1, inset])
		## Punch straight through the short axis so the sky is visible from the street.
		if bmax.x - bmin.x >= bmax.z - bmin.z:
			brush.fill_box(
				Vector3i(bmin.x + inset, y0, bmin.z - 1),
				Vector3i(bmax.x - inset, y1, bmax.z + 1),
				VoxelMaterial.AIR
			)
		else:
			brush.fill_box(
				Vector3i(bmin.x - 1, y0, bmin.z + inset),
				Vector3i(bmax.x + 1, y1, bmax.z - inset),
				VoxelMaterial.AIR
			)
		## Rim the opening so the cut edges read as designed, not damaged.
		brush.fill_box(
			Vector3i(bmin.x, y1, bmin.z), Vector3i(bmax.x, y1 + 1, bmax.z), band
		)
	_corner_pilasters(bmin, bmax, bmin.y, _floor_y(bmin.y, floors), band)
	_flat_roof_parapet(bmin, bmax, floors, theme.roof_for(rng))
	_roof_clutter(bmin, bmax, floors)
	if on_plaza:
		_arcade_ground(bmin, bmax, facing)
	var top_y := _floor_y(bmin.y, floors) + 2
	_note_height(bmin.y, top_y)
	## Shell the slab in horizontal slices split around each opening, so the sky stays
	## visible through the holes at distance instead of being filled in by one block.
	var across_x := bmax.x - bmin.x >= bmax.z - bmin.z
	var prev_y := bmin.y
	for hole: Array in hole_spans:
		var hy0: int = hole[0]
		var hy1: int = hole[1]
		var inset: int = hole[2]
		if hy0 > prev_y:
			_note_box(Vector3i(bmin.x, prev_y, bmin.z), Vector3i(bmax.x, hy0, bmax.z))
		## Two piers flanking the void.
		if across_x:
			_note_box(Vector3i(bmin.x, hy0, bmin.z), Vector3i(bmin.x + inset, hy1, bmax.z))
			_note_box(Vector3i(bmax.x - inset, hy0, bmin.z), Vector3i(bmax.x, hy1, bmax.z))
		else:
			_note_box(Vector3i(bmin.x, hy0, bmin.z), Vector3i(bmax.x, hy1, bmin.z + inset))
			_note_box(Vector3i(bmin.x, hy0, bmax.z - inset), Vector3i(bmax.x, hy1, bmax.z))
		prev_y = hy1
	if top_y > prev_y:
		_note_box(Vector3i(bmin.x, prev_y, bmin.z), Vector3i(bmax.x, top_y, bmax.z))


## Two legs and a spanning deck: you can walk under the building.
func arch_gate(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var floors := rng.randi_range(maxi(4, _floors_for_cap(4, 16) / 2), _floors_for_cap(4, 18))
	var wall := _pick_wall_mat(false)
	var band := theme.band_for(rng)
	var across_x := (bmax.x - bmin.x) >= (bmax.z - bmin.z)
	var span := (bmax.x - bmin.x) if across_x else (bmax.z - bmin.z)
	var leg := clampi(span / 4, 4, 8)
	## Opening height: tall enough to walk (and drive) through.
	var arch_floors := 1 + (1 if floors >= 8 else 0)
	var arch_top := _floor_y(bmin.y, arch_floors)
	for f in range(floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var mat := band if f == arch_floors else wall
		if y0 + fh <= arch_top:
			## Legs only below the span.
			if across_x:
				_fill_shell(
					Vector3i(bmin.x, y0, bmin.z),
					Vector3i(bmin.x + leg, y0 + fh, bmax.z),
					mat, facing, f == 0, false, f == 0
				)
				_fill_shell(
					Vector3i(bmax.x - leg, y0, bmin.z),
					Vector3i(bmax.x, y0 + fh, bmax.z),
					mat, facing, f == 0, false, f == 0
				)
			else:
				_fill_shell(
					Vector3i(bmin.x, y0, bmin.z),
					Vector3i(bmax.x, y0 + fh, bmin.z + leg),
					mat, facing, f == 0, false, f == 0
				)
				_fill_shell(
					Vector3i(bmin.x, y0, bmax.z - leg),
					Vector3i(bmax.x, y0 + fh, bmax.z),
					mat, facing, f == 0, false, f == 0
				)
		else:
			_fill_shell(
				Vector3i(bmin.x, y0, bmin.z),
				Vector3i(bmax.x, y0 + fh, bmax.z),
				mat, facing, false, true, false
			)
	## Stepped soffit so the underside reads as an arch rather than a flat lintel.
	var steps := mini(3, leg - 1)
	for s in range(steps):
		var y := arch_top - 1 - s
		if y <= bmin.y:
			break
		var grow := steps - s
		if across_x:
			brush.fill_box(
				Vector3i(bmin.x + leg, y, bmin.z),
				Vector3i(bmin.x + leg + grow, y + 1, bmax.z),
				band
			)
			brush.fill_box(
				Vector3i(bmax.x - leg - grow, y, bmin.z),
				Vector3i(bmax.x - leg, y + 1, bmax.z),
				band
			)
		else:
			brush.fill_box(
				Vector3i(bmin.x, y, bmin.z + leg),
				Vector3i(bmax.x, y + 1, bmin.z + leg + grow),
				band
			)
			brush.fill_box(
				Vector3i(bmin.x, y, bmax.z - leg - grow),
				Vector3i(bmax.x, y + 1, bmax.z - leg),
				band
			)
	## Keep the passage clear of any storefront clutter.
	if across_x:
		brush.fill_box(
			Vector3i(bmin.x + leg + steps, bmin.y + 1, bmin.z),
			Vector3i(bmax.x - leg - steps, arch_top - steps, bmax.z),
			VoxelMaterial.AIR
		)
	else:
		brush.fill_box(
			Vector3i(bmin.x, bmin.y + 1, bmin.z + leg + steps),
			Vector3i(bmax.x, arch_top - steps, bmax.z - leg - steps),
			VoxelMaterial.AIR
		)
	_flat_roof_parapet(bmin, bmax, floors, theme.roof_for(rng))
	_roof_clutter(bmin, bmax, floors)
	var arch_top_y := _floor_y(bmin.y, floors) + 2
	_note_height(bmin.y, arch_top_y)
	## Two legs and the deck above them. One block would brick up the passage.
	if across_x:
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmin.x + leg, arch_top, bmax.z))
		_note_box(Vector3i(bmax.x - leg, bmin.y, bmin.z), Vector3i(bmax.x, arch_top, bmax.z))
	else:
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, arch_top, bmin.z + leg))
		_note_box(Vector3i(bmin.x, bmin.y, bmax.z - leg), Vector3i(bmax.x, arch_top, bmax.z))
	_note_box(Vector3i(bmin.x, arch_top, bmin.z), Vector3i(bmax.x, arch_top_y, bmax.z))


## Cluster of fused pods on a core — the "cell colony" look.
func blob_stack(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var lot_w := mini(bmax.x - bmin.x, bmax.z - bmin.z)
	var core_r := clampi(lot_w / 4, 3, 6)
	var wall := _pick_wall_mat(false)
	var band := theme.band_for(rng)
	var cap := maxi(_floor_y(bmin.y, 4), bmin.y + maxi(24, mini(max_height - 8, 90)))
	## Central stalk carries the pods and gives the interior a stair core.
	brush.fill_cylinder_shell(cx, cz, bmin.y, cap, core_r, wall, true, 2)
	brush.fill_disk(cx, cz, bmin.y, core_r, wall)
	_cylinder_porch(bmin, bmax, facing, theme.base_mat)
	var pods := 3 + rng.randi() % 4
	var top_reached := cap
	var max_pod_r := maxi(3, lot_w / 3)
	for p in range(pods):
		## Pods climb the stalk, alternating sides, shrinking as they go up.
		var t := float(p) / float(maxi(pods - 1, 1))
		var pod_r := clampi(max_pod_r - int(t * float(max_pod_r) * 0.45), 3, max_pod_r)
		var py := bmin.y + int(lerpf(float(core_r + 2), float(cap - bmin.y) * 0.92, t))
		var ang := rng.randf() * TAU
		var arm := float(core_r + pod_r - 2)
		var px := cx + int(round(cos(ang) * arm))
		var pz := cz + int(round(sin(ang) * arm))
		## Stay inside the lot so pods never overhang the carriageway.
		px = clampi(px, bmin.x + pod_r, bmax.x - pod_r)
		pz = clampi(pz, bmin.z + pod_r, bmax.z - pod_r)
		var radii := Vector3i(pod_r, maxi(2, pod_r - 1 + rng.randi() % 3), pod_r)
		var pod_mat := band if p % 2 == 1 else wall
		brush.fill_ellipsoid_shell(Vector3i(px, py, pz), radii, pod_mat, 2)
		_note_sphere(Vector3i(px, py, pz), radii)
		## Short neck fusing pod to stalk, and a glass eye facing out.
		brush.fill_box(
			Vector3i(mini(px, cx), py - 1, mini(pz, cz)),
			Vector3i(maxi(px, cx) + 1, py + 2, maxi(pz, cz) + 1),
			pod_mat
		)
		brush.fill_disk(px, pz, py + radii.y - 1, maxi(1, pod_r / 2), VoxelMaterial.GLASS)
		top_reached = maxi(top_reached, py + radii.y)
	## Crown pod centred on the stalk ties the colony together.
	var crown_r := maxi(3, core_r + 1)
	brush.fill_ellipsoid_shell(
		Vector3i(cx, cap, cz), Vector3i(crown_r, crown_r - 1, crown_r), band, 2
	)
	brush.column(cx, cz, cap + crown_r - 1, cap + crown_r + 4, VoxelMaterial.METAL)
	_note_height(bmin.y, maxi(top_reached, cap + crown_r + 4))
	_note_cylinder(cx, cz, bmin.y, cap, core_r)
	_note_sphere(Vector3i(cx, cap, cz), Vector3i(crown_r, crown_r - 1, crown_r))


## Rectangular floor plates rotated a little each level — a twisting tower.
func twisted_stack(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	var floors := rng.randi_range(maxi(8, _floors_for_cap(8, 28) / 2), _floors_for_cap(8, 32))
	var wall := _pick_wall_mat(false)
	var band := theme.band_for(rng)
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var half_x := (bmax.x - bmin.x) / 2 - 1
	var half_z := (bmax.z - bmin.z) / 2 - 1
	if half_x < 4 or half_z < 4:
		midrise_modern(bmin, bmax, facing, false)
		return
	## Podium keeps a normal street edge; the twist starts above it.
	_box_floors(bmin, bmax, 1, theme.base_mat, facing, true, true)
	_retail_storefront(bmin, bmax, facing)
	var step_deg := rng.randf_range(4.0, 9.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
	var built_top := _floor_y(bmin.y, 1)
	for f in range(1, floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var ang := deg_to_rad(step_deg * float(f))
		## Shrink slightly with height so the silhouette tapers.
		var shrink := 1.0 - 0.3 * float(f) / float(floors)
		var hx := maxf(float(half_x) * shrink, 3.0)
		var hz := maxf(float(half_z) * shrink, 3.0)
		var mat := band if f % 4 == 0 else wall
		_rotated_plate(cx, cz, y0, y0 + fh, hx, hz, ang, mat, bmin, bmax)
		built_top = y0 + fh
	brush.fill_disk(cx, cz, built_top, maxi(2, mini(half_x, half_z) / 2), theme.roof_for(rng))
	brush.column(cx, cz, built_top + 1, built_top + 6, VoxelMaterial.METAL)
	_note_height(bmin.y, built_top + 6)
	## A handful of rotated slabs rather than one per floor: enough for the silhouette
	## to keep turning without spending an impostor instance on every level.
	_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, _floor_y(bmin.y, 1), bmax.z))
	var chunks := clampi(floors / 4, 2, 5)
	for c in range(chunks):
		var f0 := 1 + c * (floors - 1) / chunks
		var f1 := 1 + (c + 1) * (floors - 1) / chunks
		if f1 <= f0:
			continue
		## Sample the twist mid-chunk so the slab sits inside the range it stands for.
		var f_mid := (f0 + f1) / 2
		var shrink := 1.0 - 0.3 * float(f_mid) / float(floors)
		var hx := maxf(float(half_x) * shrink, 3.0)
		var hz := maxf(float(half_z) * shrink, 3.0)
		var ang := deg_to_rad(step_deg * float(f_mid))
		## `_rotated_plate` clips its voxels to the lot, so the shell has to be shrunk to
		## the largest rotated rectangle that still fits — otherwise the distant slab
		## hangs out over the street where there is nothing to see.
		var ca := absf(cos(ang))
		var sa := absf(sin(ang))
		var fit := minf(
			float(half_x) / maxf(ca * hx + sa * hz, 0.001),
			float(half_z) / maxf(sa * hx + ca * hz, 0.001)
		)
		if fit < 1.0:
			hx *= fit
			hz *= fit
		_note_part(
			ImpostorShape.BOX,
			Vector3i(cx - maxi(int(hx), 2), _floor_y(bmin.y, f0), cz - maxi(int(hz), 2)),
			Vector3i(cx + maxi(int(hx), 2), _floor_y(bmin.y, f1), cz + maxi(int(hz), 2)),
			ang
		)


## One twisted floor plate: rotated rectangle outline, hollow inside.
func _rotated_plate(
	cx: int,
	cz: int,
	y0: int,
	y1: int,
	half_x: float,
	half_z: float,
	angle: float,
	mat: int,
	bmin: Vector3i,
	bmax: Vector3i
) -> void:
	var ca := cos(angle)
	var sa := sin(angle)
	var reach := int(ceil(maxf(half_x, half_z))) + 2
	for z in range(cz - reach, cz + reach + 1):
		if z < bmin.z or z >= bmax.z:
			continue
		for x in range(cx - reach, cx + reach + 1):
			if x < bmin.x or x >= bmax.x:
				continue
			var dx := float(x - cx)
			var dz := float(z - cz)
			## Into plate space.
			var lx := dx * ca + dz * sa
			var lz := -dx * sa + dz * ca
			var ax := absf(lx)
			var az := absf(lz)
			if ax > half_x or az > half_z:
				continue
			## Wall band near the plate edge; interior only gets slabs.
			var on_edge := ax > half_x - 1.4 or az > half_z - 1.4
			if on_edge:
				brush.fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), mat)
			else:
				brush.set_vox(Vector3i(x, y0, z), mat)
				brush.set_vox(Vector3i(x, y1 - 1, z), mat)


## Vertical accent strips on the four corners of a shaft.
func _corner_pilasters(
	bmin: Vector3i, bmax: Vector3i, y0: int, y1: int, mat: int
) -> void:
	if y1 <= y0:
		return
	var w := mini(2, maxi(1, (bmax.x - bmin.x) / 8))
	for xz in [
		Vector2i(bmin.x, bmin.z),
		Vector2i(bmax.x - w, bmin.z),
		Vector2i(bmin.x, bmax.z - w),
		Vector2i(bmax.x - w, bmax.z - w),
	]:
		brush.fill_box(
			Vector3i(xz.x, y0, xz.y),
			Vector3i(xz.x + w, y1, xz.y + w),
			mat
		)


## How many floors fit under the current height cap, clamped to an archetype's range.
## The cap now comes from the district intensity field, so it can be genuinely low —
## a garden-residential lot must produce a two-storey house, not an invalid range.
func _floors_for_cap(min_floors: int, max_floors: int) -> int:
	var fit := 1 + (max_height - ground_floor_height) / maxi(floor_height, 1)
	return clampi(fit, min_floors, max_floors)


func _floor_h(floor_index: int) -> int:
	return ground_floor_height if floor_index == 0 else floor_height


func _floor_y(base_y: int, floor_index: int) -> int:
	var y := base_y
	for f in range(floor_index):
		y += _floor_h(f)
	return y


## Remember storeys for elevator shaft emit (multi-floor lots only).
func _note_storeys(bmin: Vector3i, bmax: Vector3i, floors: int, facing: int) -> void:
	last_floors = maxi(floors, last_floors)
	last_facing = facing
	last_bmin = bmin
	last_bmax = bmax


## Walkable landing Y for storey `f` (district-local), matching InteriorRoom ground convention.
func landing_y(base_y: int, floor_index: int) -> int:
	return _floor_y(base_y, floor_index) + 1


func _footprint_wide_enough(bmin: Vector3i, bmax: Vector3i, min_w: int, min_d: int) -> bool:
	return (bmax.x - bmin.x) >= min_w and (bmax.z - bmin.z) >= min_d


## Record the tallest voxel an archetype reached so the far-LOD shell matches it.
func _note_height(base_y: int, top_y: int) -> void:
	built_height_vox = maxi(built_height_vox, top_y - base_y)


## Add one massing primitive for the far LOD, from an axis-aligned voxel span.
## `yaw` rotates about Y for twisted plates.
func _note_box(min_v: Vector3i, max_v: Vector3i, yaw: float = 0.0) -> void:
	_note_part(ImpostorShape.BOX, min_v, max_v, yaw)


## Round shaft / silo: the span is the bounding box, the shell is drawn as a cylinder.
func _note_cylinder(cx: int, cz: int, y0: int, y1: int, radius: int) -> void:
	_note_part(
		ImpostorShape.CYLINDER,
		Vector3i(cx - radius, y0, cz - radius),
		Vector3i(cx + radius + 1, y1, cz + radius + 1)
	)


func _note_sphere(center: Vector3i, radii: Vector3i) -> void:
	_note_part(ImpostorShape.SPHERE, center - radii, center + radii + Vector3i.ONE)


## Pitched roof over an `eaves_y .. eaves_y + ridge_h` band. `_gable_roof` tapers along
## the depth axis, so the ridge runs along Z for street-facing 0/1 and along X for 2/3.
## The prism's own ridge is on local Z, hence the quarter turn for the other two.
func _note_gable(umin: Vector3i, umax: Vector3i, eaves_y: int, ridge_h: int, facing: int) -> void:
	if ridge_h <= 0:
		return
	var w := umax.x - umin.x
	var d := umax.z - umin.z
	var ridge_along_z := facing == 0 or facing == 1
	var size := Vector3i(w, ridge_h, d) if ridge_along_z else Vector3i(d, ridge_h, w)
	var center := Vector3(
		float(umin.x + umax.x) * 0.5,
		float(eaves_y) + float(ridge_h) * 0.5,
		float(umin.z + umax.z) * 0.5
	)
	impostor_parts.append({
		"shape": int(ImpostorShape.PRISM),
		"center": center,
		"size": Vector3(float(size.x), float(size.y), float(size.z)),
		"yaw": 0.0 if ridge_along_z else PI * 0.5,
	})


## Massing for the plain stacked archetypes: one shell per L/T wing when `_massed_floors`
## split the footprint, otherwise a single block. Emitting the wings separately is what
## keeps an L-plan an L-plan once the voxels are swapped for shells.
func _note_massed_box(bmin: Vector3i, bmax: Vector3i, top_y: int) -> void:
	if _mass_parts_cache.is_empty():
		_note_box(Vector3i(bmin.x, bmin.y, bmin.z), Vector3i(bmax.x, top_y, bmax.z))
		return
	for part: Array in _mass_parts_cache:
		var pmin: Vector3i = part[0]
		var pmax: Vector3i = part[1]
		if pmax.x - pmin.x < 4 or pmax.z - pmin.z < 4:
			continue
		_note_box(Vector3i(pmin.x, bmin.y, pmin.z), Vector3i(pmax.x, top_y, pmax.z))


func _note_part(shape: ImpostorShape, min_v: Vector3i, max_v: Vector3i, yaw: float = 0.0) -> void:
	var size := Vector3(
		float(max_v.x - min_v.x), float(max_v.y - min_v.y), float(max_v.z - min_v.z)
	)
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_error("BuildingGrammar._note_part: degenerate part %s .. %s" % [min_v, max_v])
		return
	impostor_parts.append({
		"shape": int(shape),
		"center": Vector3(float(min_v.x), float(min_v.y), float(min_v.z)) + size * 0.5,
		"size": size,
		"yaw": yaw,
	})


## Street-facing bar AABB (y from lot). Used for silo sheds and L street wings.
func _street_bar_aabb(bmin: Vector3i, bmax: Vector3i, facing: int) -> Array[Vector3i]:
	var depth := maxi(6, mini(bmax.x - bmin.x, bmax.z - bmin.z) * 2 / 3)
	match facing:
		0:
			return [
				Vector3i(bmin.x, bmin.y, bmax.z - depth),
				Vector3i(bmax.x, bmin.y, bmax.z)
			] as Array[Vector3i]
		1:
			return [
				Vector3i(bmin.x, bmin.y, bmin.z),
				Vector3i(bmax.x, bmin.y, bmin.z + depth)
			] as Array[Vector3i]
		2:
			return [
				Vector3i(bmax.x - depth, bmin.y, bmin.z),
				Vector3i(bmax.x, bmin.y, bmax.z)
			] as Array[Vector3i]
		_:
			return [
				Vector3i(bmin.x, bmin.y, bmin.z),
				Vector3i(bmin.x + depth, bmin.y, bmax.z)
			] as Array[Vector3i]


## L or T wing parts: Array of [amin, amax] Vector3i pairs (y = lot y).
func _wing_footprint_parts(bmin: Vector3i, bmax: Vector3i, facing: int) -> Array:
	var use_t := rng.randf() < 0.35
	var parts: Array = []
	var bar := _street_bar_aabb(bmin, bmax, facing)
	parts.append(bar)
	var wing_thick := maxi(5, mini(bmax.x - bmin.x, bmax.z - bmin.z) / 3)
	if use_t:
		## T: rear stem centered.
		match facing:
			0:
				var cx := (bmin.x + bmax.x) / 2
				parts.append([
					Vector3i(cx - wing_thick / 2, bmin.y, bmin.z),
					Vector3i(cx + wing_thick / 2 + 1, bmin.y, bar[0].z)
				])
			1:
				var cx2 := (bmin.x + bmax.x) / 2
				parts.append([
					Vector3i(cx2 - wing_thick / 2, bmin.y, bar[1].z),
					Vector3i(cx2 + wing_thick / 2 + 1, bmin.y, bmax.z)
				])
			2:
				var cz := (bmin.z + bmax.z) / 2
				parts.append([
					Vector3i(bmin.x, bmin.y, cz - wing_thick / 2),
					Vector3i(bar[0].x, bmin.y, cz + wing_thick / 2 + 1)
				])
			_:
				var cz2 := (bmin.z + bmax.z) / 2
				parts.append([
					Vector3i(bar[1].x, bmin.y, cz2 - wing_thick / 2),
					Vector3i(bmax.x, bmin.y, cz2 + wing_thick / 2 + 1)
				])
	else:
		## L: wing on random side, filling remaining depth.
		var left := rng.randf() < 0.5
		match facing:
			0:
				if left:
					parts.append([
						Vector3i(bmin.x, bmin.y, bmin.z),
						Vector3i(bmin.x + wing_thick, bmin.y, bar[0].z)
					])
				else:
					parts.append([
						Vector3i(bmax.x - wing_thick, bmin.y, bmin.z),
						Vector3i(bmax.x, bmin.y, bar[0].z)
					])
			1:
				if left:
					parts.append([
						Vector3i(bmin.x, bmin.y, bar[1].z),
						Vector3i(bmin.x + wing_thick, bmin.y, bmax.z)
					])
				else:
					parts.append([
						Vector3i(bmax.x - wing_thick, bmin.y, bar[1].z),
						Vector3i(bmax.x, bmin.y, bmax.z)
					])
			2:
				if left:
					parts.append([
						Vector3i(bmin.x, bmin.y, bmin.z),
						Vector3i(bar[0].x, bmin.y, bmin.z + wing_thick)
					])
				else:
					parts.append([
						Vector3i(bmin.x, bmin.y, bmax.z - wing_thick),
						Vector3i(bar[0].x, bmin.y, bmax.z)
					])
			_:
				if left:
					parts.append([
						Vector3i(bar[1].x, bmin.y, bmin.z),
						Vector3i(bmax.x, bmin.y, bmin.z + wing_thick)
					])
				else:
					parts.append([
						Vector3i(bar[1].x, bmin.y, bmax.z - wing_thick),
						Vector3i(bmax.x, bmin.y, bmax.z)
					])
	return parts


func _massed_floors(
	bmin: Vector3i,
	bmax: Vector3i,
	floors: int,
	wall: int,
	facing: int,
	door: bool,
	ribbon: bool
) -> void:
	_mass_parts_cache = _wing_footprint_parts(bmin, bmax, facing)
	for i in range(_mass_parts_cache.size()):
		var part: Array = _mass_parts_cache[i]
		var pmin: Vector3i = part[0]
		var pmax: Vector3i = part[1]
		if pmax.x - pmin.x < 4 or pmax.z - pmin.z < 4:
			continue
		_box_floors(pmin, pmax, floors, wall, facing, door and i == 0, ribbon)


func _stepped_setback_stack(
	bmin: Vector3i, bmax: Vector3i, floors: int, facing: int, aggressive: bool
) -> void:
	## Soft upper setbacks on the side faces only — carving all four sides ate the
	## crown and made midrise read like short stubs.
	if floors < 7:
		return
	var inset_from := floors * 2 / 3 if not aggressive else floors * 3 / 5
	for f in range(inset_from, floors):
		var y0 := _floor_y(bmin.y, f)
		var fh := _floor_h(f)
		var step := 1 if not aggressive else mini(2, 1 + (f - inset_from) / 4)
		if facing == 0 or facing == 1:
			brush.fill_box(
				Vector3i(bmin.x, y0, bmin.z),
				Vector3i(bmin.x + step, y0 + fh, bmax.z),
				VoxelMaterial.AIR
			)
			brush.fill_box(
				Vector3i(bmax.x - step, y0, bmin.z),
				Vector3i(bmax.x, y0 + fh, bmax.z),
				VoxelMaterial.AIR
			)
		else:
			brush.fill_box(
				Vector3i(bmin.x, y0, bmin.z),
				Vector3i(bmax.x, y0 + fh, bmin.z + step),
				VoxelMaterial.AIR
			)
			brush.fill_box(
				Vector3i(bmin.x, y0, bmax.z - step),
				Vector3i(bmax.x, y0 + fh, bmax.z),
				VoxelMaterial.AIR
			)


func _flat_roof_parapet_massed(
	bmin: Vector3i, bmax: Vector3i, floors: int, roof_mat: int, _facing: int
) -> void:
	if not _mass_parts_cache.is_empty():
		for part in _mass_parts_cache:
			var pmin: Vector3i = part[0]
			var pmax: Vector3i = part[1]
			if pmax.x - pmin.x < 4 or pmax.z - pmin.z < 4:
				continue
			_flat_roof_parapet(pmin, pmax, floors, roof_mat)
		_mass_parts_cache.clear()
	else:
		_flat_roof_parapet(bmin, bmax, floors, roof_mat)


func _gable_roof_massed(bmin: Vector3i, bmax: Vector3i, floors: int, facing: int) -> void:
	if _mass_parts_cache.is_empty():
		_gable_roof(bmin, bmax, floors, facing)
		return
	for part in _mass_parts_cache:
		var pmin: Vector3i = part[0]
		var pmax: Vector3i = part[1]
		if pmax.x - pmin.x < 4 or pmax.z - pmin.z < 4:
			continue
		_gable_roof(pmin, pmax, floors, facing)
	_mass_parts_cache.clear()


func _punch_cylinder_windows(cx: int, cz: int, y0: int, y1: int, radius: int) -> void:
	if y1 <= y0 or radius < 2:
		return
	var r2 := radius * radius
	var inner2 := (radius - 1) * (radius - 1)
	for y in range(y0, y1):
		## Four angular sectors of glass, skipping floor plates.
		if (y - y0) % 3 == 0:
			continue
		for z in range(cz - radius, cz + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				var dx := x - cx
				var dz := z - cz
				var d2 := dx * dx + dz * dz
				if d2 > r2 or d2 < inner2:
					continue
				var ang := atan2(float(dz), float(dx))
				var sector := int(floor((ang + PI) / (PI * 0.5))) % 4
				if (x + z + y) % 5 == sector:
					var glass_id := (
						VoxelMaterial.GLASS_LIT if rng.randf() < 0.22 else VoxelMaterial.GLASS
					)
					brush.set_vox(Vector3i(x, y, z), glass_id)


func _cylinder_porch(bmin: Vector3i, bmax: Vector3i, facing: int, mat: int) -> void:
	var cx := (bmin.x + bmax.x) / 2
	var cz := (bmin.z + bmax.z) / 2
	var y0 := bmin.y
	var y1 := bmin.y + ground_floor_height
	match facing:
		0:
			brush.fill_box(
				Vector3i(cx - 2, y0, bmax.z - 1), Vector3i(cx + 3, y1, bmax.z + 1), mat
			)
			brush.fill_box(
				Vector3i(cx - 1, y0 + 1, bmax.z), Vector3i(cx + 2, y1 - 1, bmax.z + 1), VoxelMaterial.AIR
			)
		1:
			brush.fill_box(
				Vector3i(cx - 2, y0, bmin.z - 1), Vector3i(cx + 3, y1, bmin.z + 1), mat
			)
			brush.fill_box(
				Vector3i(cx - 1, y0 + 1, bmin.z - 1), Vector3i(cx + 2, y1 - 1, bmin.z), VoxelMaterial.AIR
			)
		2:
			brush.fill_box(
				Vector3i(bmax.x - 1, y0, cz - 2), Vector3i(bmax.x + 1, y1, cz + 3), mat
			)
			brush.fill_box(
				Vector3i(bmax.x, y0 + 1, cz - 1), Vector3i(bmax.x + 1, y1 - 1, cz + 2), VoxelMaterial.AIR
			)
		_:
			brush.fill_box(
				Vector3i(bmin.x - 1, y0, cz - 2), Vector3i(bmin.x + 1, y1, cz + 3), mat
			)
			brush.fill_box(
				Vector3i(bmin.x - 1, y0 + 1, cz - 1), Vector3i(bmin.x, y1 - 1, cz + 2), VoxelMaterial.AIR
			)


func _civic_cylinder_annex(bmin: Vector3i, bmax: Vector3i, facing: int, hall_top: int) -> void:
	var radius := 3
	var ax: int
	var az: int
	match facing:
		0:
			ax = bmin.x + radius + 1
			az = bmin.z + radius + 1
		1:
			ax = bmax.x - radius - 2
			az = bmax.z - radius - 2
		2:
			ax = bmin.x + radius + 1
			az = bmax.z - radius - 2
		_:
			ax = bmax.x - radius - 2
			az = bmin.z + radius + 1
	var top := hall_top + floor_height * 2
	brush.fill_cylinder_shell(ax, az, bmin.y, top, radius, VoxelMaterial.STONE, true, 2)
	brush.fill_disk(ax, az, top, radius, VoxelMaterial.STONE)
	brush.fill_disk_ring(ax, az, top + 1, radius, 1, theme.accent_mat)


func _open_courtyard_to_street(
	hole_min: Vector3i,
	hole_max: Vector3i,
	bmin: Vector3i,
	bmax: Vector3i,
	facing: int,
	floors: int
) -> void:
	var top := _floor_y(bmin.y, floors)
	match facing:
		0:
			brush.fill_box(
				Vector3i(hole_min.x, bmin.y + 1, hole_max.z),
				Vector3i(hole_max.x, top, bmax.z),
				VoxelMaterial.AIR
			)
		1:
			brush.fill_box(
				Vector3i(hole_min.x, bmin.y + 1, bmin.z),
				Vector3i(hole_max.x, top, hole_min.z),
				VoxelMaterial.AIR
			)
		2:
			brush.fill_box(
				Vector3i(hole_max.x, bmin.y + 1, hole_min.z),
				Vector3i(bmax.x, top, hole_max.z),
				VoxelMaterial.AIR
			)
		_:
			brush.fill_box(
				Vector3i(bmin.x, bmin.y + 1, hole_min.z),
				Vector3i(hole_min.x, top, hole_max.z),
				VoxelMaterial.AIR
			)


func _box_floors(
	bmin: Vector3i,
	bmax: Vector3i,
	floors: int,
	wall: int,
	facing: int,
	door: bool,
	ribbon: bool
) -> void:
	_note_storeys(bmin, bmax, floors, facing)
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
	_note_storeys(bmin, bmax, floors, facing)
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
	if door_on_ground:
		_record_lot_doorway(min_v, max_v, facing)


func _record_lot_doorway(min_v: Vector3i, max_v: Vector3i, facing: int) -> void:
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	var d: CastleDoorway = CastleDoorwayScript.new() as CastleDoorway
	d.width = 3
	d.depth = 1
	## Punch band is y in [min_v.y+1, min_v.y+ground_floor_height-1].
	d.floor_y = min_v.y
	d.height = maxi(ground_floor_height - 1, 1)
	d.arch_courses = 0
	d.leaf = CastleDoorway.LEAF_DOOR
	d.link = CastleDoorway.LINK_TREE
	match facing:
		0:
			## Door on +Z wall; walk inward toward −Z.
			d.center = Vector2i(cx, max_v.z - 1)
			d.axis = Vector2i(0, -1)
		1:
			d.center = Vector2i(cx, min_v.z)
			d.axis = Vector2i(0, 1)
		2:
			d.center = Vector2i(max_v.x - 1, cz)
			d.axis = Vector2i(-1, 0)
		_:
			d.center = Vector2i(min_v.x, cz)
			d.axis = Vector2i(1, 0)
	lot_doorways.append(d)


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


## Ridge height of the stepped gable. Shared with the impostor prism so the far shell
## can't drift from the voxels.
func _gable_ridge_h(umin: Vector3i, umax: Vector3i, facing: int) -> int:
	var depth := umax.z - umin.z if facing == 2 or facing == 3 else umax.x - umin.x
	return maxi(2, depth / 2)


func _gable_roof(umin: Vector3i, umax: Vector3i, floors: int, facing: int) -> void:
	var top := _floor_y(umin.y, floors)
	var steps := _gable_ridge_h(umin, umax, facing)
	var roof_mat := theme.roof_for(rng)
	## Emitted here rather than by the caller so the far shell only ever gets a pitch
	## where one is really painted.
	_note_gable(umin, umax, top, steps, facing)
	_note_height(umin.y, top + steps)
	for s in range(steps):
		var inset := s
		var y := top + s
		if facing == 0 or facing == 1:
			var x0 := umin.x + inset
			var x1 := umax.x - inset
			brush.fill_box(Vector3i(x0, y, umin.z), Vector3i(x1, y + 1, umax.z), roof_mat)
			## Outer eaves of each tread become 45° wedges so the silhouette is a pitch,
			## not a staircase. Ridge tread (width 1) stays a full cube.
			if x1 - x0 >= 2:
				var lo := VoxelMaterial.roof_slope(roof_mat, VoxelMaterial.SLOPE_HIGH_POS_X)
				var hi := VoxelMaterial.roof_slope(roof_mat, VoxelMaterial.SLOPE_HIGH_NEG_X)
				for z in range(umin.z, umax.z):
					brush.set_vox(Vector3i(x0, y, z), lo)
					brush.set_vox(Vector3i(x1 - 1, y, z), hi)
		else:
			var z0 := umin.z + inset
			var z1 := umax.z - inset
			brush.fill_box(Vector3i(umin.x, y, z0), Vector3i(umax.x, y + 1, z1), roof_mat)
			if z1 - z0 >= 2:
				var loz := VoxelMaterial.roof_slope(roof_mat, VoxelMaterial.SLOPE_HIGH_POS_Z)
				var hiz := VoxelMaterial.roof_slope(roof_mat, VoxelMaterial.SLOPE_HIGH_NEG_Z)
				for x in range(umin.x, umax.x):
					brush.set_vox(Vector3i(x, y, z0), loz)
					brush.set_vox(Vector3i(x, y, z1 - 1), hiz)


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
	## Per-lot palette variety from the district theme (Blocky IDs are discrete, so the
	## material choice is what carries the district's identity).
	return theme.wall_for(rng, townhouse)


func _retail_storefront(bmin: Vector3i, bmax: Vector3i, facing: int) -> void:
	## Shallow protruding storefront band + glass on the facing ground floor.
	if rng.randf() < 0.35:
		return
	var y0 := bmin.y + 1
	var y1 := mini(bmin.y + ground_floor_height - 1, bmin.y + 5)
	var mat := theme.accent_mat if rng.randf() < 0.4 else theme.base_mat
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
	var mat := theme.accent_mat if rng.randf() < 0.55 else VoxelMaterial.METAL
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
