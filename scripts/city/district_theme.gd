## Per-district personality: material palette, height profile and grammar weights.
##
## Without this every district tile came out of the same recipe — same bullseye of
## towers in the middle, same wall materials everywhere. A theme is picked
## deterministically from the district coordinate, weighted by distance from the world
## origin, so the world reads as one downtown surrounded by older and lower quarters.
##
## All palettes use existing VoxelMaterial ids, so the native material mirror
## (native/city_voxel/src/materials.rs) does not need to change.
class_name DistrictTheme
extends RefCounted

const CORE_HIGHRISE := 0
const OLD_TOWN := 1
const WATERFRONT_INDUSTRIAL := 2
const GARDEN_RESIDENTIAL := 3
const CIVIC_QUARTER := 4
## Outer-ring wilderness: arterial roads, no mid-tile housing, sculpted hills + caves.
const HILL := 5
## Outer-ring necropolis: edge stubs only, elevated yard, chapel, catacombs.
const GRAVEYARD := 6
## Outer-ring water: edge stubs only, one natural lake with wooded islands.
const LAKE := 7
## Outer-ring fortress: edge stubs only, walled castle on a plinth reached by a causeway.
const CASTLE := 8
const COUNT := 9

## Districts within this many tiles of the world origin are always the high-rise core.
const CORE_RING := 0

var id: int = CORE_HIGHRISE
var display_name: String = "Core High-Rise"
## One-line pitch for the district-type picker (J hop).
var blurb: String = ""
## Walls for midrise / large buildings, and for low row housing.
var wall_mats: PackedInt32Array = PackedInt32Array([VoxelMaterial.CONCRETE])
var townhouse_mats: PackedInt32Array = PackedInt32Array([VoxelMaterial.BRICK])
var roof_mats: PackedInt32Array = PackedInt32Array([VoxelMaterial.ROOF])
## Plinth / podium, tower shaft, and trim on awnings and storefronts.
var base_mat: int = VoxelMaterial.CONCRETE
var tower_shaft_mat: int = VoxelMaterial.METAL
var accent_mat: int = VoxelMaterial.PAINT
## Contrasting band / pilaster materials so a shaft is never one flat colour.
var band_mats: PackedInt32Array = PackedInt32Array([VoxelMaterial.CONCRETE])
## Ground surfaces. All must satisfy VoxelMaterial.is_walkable_surface — pedestrians
## sample the deck. The carriageway itself stays ASPHALT for the traffic layer.
var sidewalk_mat: int = VoxelMaterial.SIDEWALK
var plaza_mat: int = VoxelMaterial.PLAZA
var plaza_inner_mat: int = VoxelMaterial.TILES
## Shifts the zoning intensity field up (denser, taller) or down (looser, lower).
var intensity_bias: float = 0.0
## Scales the building height cap for the whole district.
var height_scale: float = 1.0
## Grammar weights: chance of a tower on a core lot, of a modern box on a mid lot.
var tower_chance: float = 0.55
var modern_chance: float = 0.45
## Eccentri massing: spiral landmark among towers; L/T footprints; cylinder midrise.
var spiral_chance: float = 0.0
var l_mass_chance: float = 0.0
var cylinder_chance: float = 0.0
## Chance a lot becomes an outright weird building: sky hole, arch gate, blob cluster,
## twisted stack. This is the district's "creativity dial".
var wild_chance: float = 0.0
## Planner density knobs.
var park_count: int = 6
var road_density: float = 0.85
var median_planting: bool = true


static func for_district(world_seed: int, coord: Vector2i) -> DistrictTheme:
	var ring := maxi(absi(coord.x), absi(coord.y))
	var pick := DistrictCoord.district_seed(world_seed, coord) >> 7
	var choices: PackedInt32Array
	if ring <= CORE_RING:
		choices = PackedInt32Array([CORE_HIGHRISE])
	elif ring == 1:
		choices = PackedInt32Array([CORE_HIGHRISE, CIVIC_QUARTER, OLD_TOWN, CORE_HIGHRISE])
	elif ring == 2:
		choices = PackedInt32Array([
			OLD_TOWN, CIVIC_QUARTER, GARDEN_RESIDENTIAL, WATERFRONT_INDUSTRIAL, HILL,
			GRAVEYARD, LAKE, CASTLE
		])
	else:
		choices = PackedInt32Array([
			GARDEN_RESIDENTIAL, HILL, OLD_TOWN, WATERFRONT_INDUSTRIAL, GRAVEYARD,
			GARDEN_RESIDENTIAL, LAKE, OLD_TOWN, CASTLE,
		])
	return make(choices[pick % choices.size()])


## Nearest district tile (Chebyshev spiral from the origin) whose theme matches `theme_id`.
static func find_coord_for_theme(
	world_seed: int, theme_id: int, max_ring: int = 24
) -> Vector2i:
	if theme_id < 0 or theme_id >= COUNT:
		push_error("DistrictTheme.find_coord_for_theme: unknown theme id %d" % theme_id)
		return Vector2i.ZERO
	for ring in range(0, max_ring + 1):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if maxi(absi(cx), absi(cz)) != ring:
					continue
				var coord := Vector2i(cx, cz)
				if for_district(world_seed, coord).id == theme_id:
					return coord
	push_error(
		"DistrictTheme.find_coord_for_theme: no %s within ring %d (seed %d)"
		% [make(theme_id).display_name, max_ring, world_seed]
	)
	return Vector2i.ZERO


## Accepts a display name, slug ("hill", "old-town"), or integer id string.
static func parse_theme_id(raw: String) -> int:
	var s := raw.strip_edges()
	if s.is_valid_int():
		var id := int(s)
		if id >= 0 and id < COUNT:
			return id
		push_error("DistrictTheme.parse_theme_id: id %d out of range" % id)
		return -1
	var key := s.to_lower().replace(" ", "").replace("_", "").replace("-", "")
	var aliases := {
		"core": CORE_HIGHRISE,
		"corehighrise": CORE_HIGHRISE,
		"highrise": CORE_HIGHRISE,
		"oldtown": OLD_TOWN,
		"waterfront": WATERFRONT_INDUSTRIAL,
		"waterfrontindustrial": WATERFRONT_INDUSTRIAL,
		"industrial": WATERFRONT_INDUSTRIAL,
		"garden": GARDEN_RESIDENTIAL,
		"gardenresidential": GARDEN_RESIDENTIAL,
		"civic": CIVIC_QUARTER,
		"civicquarter": CIVIC_QUARTER,
		"hill": HILL,
		"graveyard": GRAVEYARD,
		"cemetery": GRAVEYARD,
		"necropolis": GRAVEYARD,
		"churchyard": GRAVEYARD,
		"lake": LAKE,
		"lakeside": LAKE,
		"water": LAKE,
		"lagoon": LAKE,
		"castle": CASTLE,
		"fortress": CASTLE,
		"keep": CASTLE,
		"citadel": CASTLE,
	}
	if aliases.has(key):
		return int(aliases[key])
	for theme_id in range(COUNT):
		var name_key := (
			make(theme_id).display_name.to_lower()
			.replace(" ", "").replace("_", "").replace("-", "")
		)
		if key == name_key:
			return theme_id
	push_error("DistrictTheme.parse_theme_id: unknown theme '%s'" % raw)
	return -1


static func make(theme_id: int) -> DistrictTheme:
	var t := DistrictTheme.new()
	t.id = theme_id
	match theme_id:
		CORE_HIGHRISE:
			t.display_name = "Core High-Rise"
			t.blurb = "Downtown towers, dense streets, and the wildest skyline."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.CONCRETE, VoxelMaterial.PLASTER, VoxelMaterial.METAL
			])
			t.townhouse_mats = PackedInt32Array([VoxelMaterial.CONCRETE, VoxelMaterial.PLASTER])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.METAL
			t.accent_mat = VoxelMaterial.METAL_PLATE
			t.band_mats = PackedInt32Array([
				VoxelMaterial.METAL_PLATE, VoxelMaterial.CONCRETE, VoxelMaterial.STONE,
				VoxelMaterial.PAINT
			])
			t.sidewalk_mat = VoxelMaterial.SIDEWALK
			t.plaza_mat = VoxelMaterial.TILES
			t.plaza_inner_mat = VoxelMaterial.PLAZA
			t.intensity_bias = 0.28
			t.height_scale = 1.0
			t.tower_chance = 0.72
			t.modern_chance = 0.7
			t.spiral_chance = 0.28
			t.l_mass_chance = 0.1
			## Keep downtown midrise as towers/boxes — silos are a waterfront look.
			t.cylinder_chance = 0.0
			t.wild_chance = 0.3
			t.park_count = 3
			t.road_density = 0.9
		OLD_TOWN:
			t.display_name = "Old Town"
			t.blurb = "Brick lanes, clay roofs, and crooked medieval massing."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK, VoxelMaterial.PLASTER,
				VoxelMaterial.STONE
			])
			t.townhouse_mats = PackedInt32Array([
				VoxelMaterial.BRICK_DARK, VoxelMaterial.BRICK, VoxelMaterial.PLASTER
			])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF_CLAY])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.STONE
			t.accent_mat = VoxelMaterial.PAINT
			t.band_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.BRICK_DARK, VoxelMaterial.PLASTER,
				VoxelMaterial.PLANTER
			])
			t.sidewalk_mat = VoxelMaterial.TILES
			t.plaza_mat = VoxelMaterial.TILES
			t.plaza_inner_mat = VoxelMaterial.STONE
			t.intensity_bias = -0.1
			t.height_scale = 0.5
			t.tower_chance = 0.05
			t.modern_chance = 0.12
			t.spiral_chance = 0.08
			t.l_mass_chance = 0.45
			t.cylinder_chance = 0.05
			## Old Town weirdness is medieval: arches and pierced walls, not twists.
			t.wild_chance = 0.16
			t.park_count = 5
			t.road_density = 0.95
		WATERFRONT_INDUSTRIAL:
			t.display_name = "Waterfront Industrial"
			t.blurb = "Metal sheds, tanks, and gravel yards by the docks."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.METAL_PLATE, VoxelMaterial.CONCRETE, VoxelMaterial.BRICK_DARK,
				VoxelMaterial.METAL
			])
			t.townhouse_mats = PackedInt32Array([
				VoxelMaterial.BRICK_DARK, VoxelMaterial.METAL_PLATE, VoxelMaterial.CONCRETE
			])
			t.roof_mats = PackedInt32Array([VoxelMaterial.METAL_PLATE, VoxelMaterial.ROOF])
			t.base_mat = VoxelMaterial.CONCRETE
			t.tower_shaft_mat = VoxelMaterial.METAL_PLATE
			t.accent_mat = VoxelMaterial.METAL
			t.band_mats = PackedInt32Array([
				VoxelMaterial.METAL, VoxelMaterial.BRICK_DARK, VoxelMaterial.PAINT,
				VoxelMaterial.CONCRETE
			])
			t.sidewalk_mat = VoxelMaterial.SIDEWALK
			t.plaza_mat = VoxelMaterial.GRAVEL
			t.plaza_inner_mat = VoxelMaterial.DIRT
			t.intensity_bias = -0.22
			t.height_scale = 0.42
			t.tower_chance = 0.08
			t.modern_chance = 0.8
			t.spiral_chance = 0.05
			t.l_mass_chance = 0.35
			t.cylinder_chance = 0.4
			## Tanks, clustered vessels and pipe gantries — the organic/blob district.
			t.wild_chance = 0.34
			t.park_count = 2
			t.road_density = 0.7
			t.median_planting = false
		GARDEN_RESIDENTIAL:
			t.display_name = "Garden Residential"
			t.blurb = "Low housing, pocket parks, and calm leafy blocks."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.PLASTER, VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK
			])
			t.townhouse_mats = PackedInt32Array([
				VoxelMaterial.PLASTER, VoxelMaterial.BRICK, VoxelMaterial.PLANTER
			])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF_CLAY, VoxelMaterial.ROOF])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.PLASTER
			t.accent_mat = VoxelMaterial.PAINT
			t.band_mats = PackedInt32Array([
				VoxelMaterial.BRICK, VoxelMaterial.PLANTER, VoxelMaterial.PAINT,
				VoxelMaterial.STONE
			])
			t.sidewalk_mat = VoxelMaterial.SIDEWALK
			t.plaza_mat = VoxelMaterial.GRAVEL
			t.plaza_inner_mat = VoxelMaterial.PLAZA
			t.intensity_bias = -0.34
			t.height_scale = 0.3
			t.tower_chance = 0.0
			t.modern_chance = 0.25
			t.spiral_chance = 0.0
			t.l_mass_chance = 0.4
			t.cylinder_chance = 0.0
			## Garden quarters stay calm — the odd pierced villa, nothing towering.
			t.wild_chance = 0.12
			t.park_count = 10
			t.road_density = 0.75
		CIVIC_QUARTER:
			t.display_name = "Civic Quarter"
			t.blurb = "Stone monuments, grand plazas, and ceremonial streets."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.PLASTER, VoxelMaterial.CONCRETE
			])
			t.townhouse_mats = PackedInt32Array([VoxelMaterial.STONE, VoxelMaterial.PLASTER])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF, VoxelMaterial.ROOF_CLAY])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.STONE
			t.accent_mat = VoxelMaterial.METAL_PLATE
			t.band_mats = PackedInt32Array([
				VoxelMaterial.METAL_PLATE, VoxelMaterial.TILES, VoxelMaterial.PLASTER,
				VoxelMaterial.PAINT
			])
			t.sidewalk_mat = VoxelMaterial.PLAZA
			t.plaza_mat = VoxelMaterial.PLAZA
			t.plaza_inner_mat = VoxelMaterial.TILES
			t.intensity_bias = 0.02
			t.height_scale = 0.62
			t.tower_chance = 0.2
			t.modern_chance = 0.3
			t.spiral_chance = 0.35
			t.l_mass_chance = 0.28
			t.cylinder_chance = 0.18
			## Monuments: grand arches and pierced slabs over the plazas.
			t.wild_chance = 0.32
			t.park_count = 6
			t.road_density = 0.85
		HILL:
			t.display_name = "Hill"
			t.blurb = "One big hill, rock strata, caves — roads only at the edges."
			## Unused for massing (no lots), but keep a stone palette for any edge props.
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.BRICK, VoxelMaterial.CONCRETE
			])
			t.townhouse_mats = PackedInt32Array([VoxelMaterial.STONE, VoxelMaterial.DIRT])
			t.roof_mats = PackedInt32Array([VoxelMaterial.STONE])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.STONE
			t.accent_mat = VoxelMaterial.GRAVEL
			t.band_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.DIRT, VoxelMaterial.BRICK,
				VoxelMaterial.GRAVEL, VoxelMaterial.BRICK_DARK, VoxelMaterial.CONCRETE
			])
			t.sidewalk_mat = VoxelMaterial.GRAVEL
			t.plaza_mat = VoxelMaterial.DIRT
			t.plaza_inner_mat = VoxelMaterial.GRAVEL
			t.intensity_bias = -0.5
			t.height_scale = 0.0
			t.tower_chance = 0.0
			t.modern_chance = 0.0
			t.spiral_chance = 0.0
			t.l_mass_chance = 0.0
			t.cylinder_chance = 0.0
			t.wild_chance = 0.0
			t.park_count = 0
			## No interior streets — planner stamps short edge stubs only.
			t.road_density = 0.0
			t.median_planting = true
		GRAVEYARD:
			t.display_name = "Graveyard"
			t.blurb = "An elevated churchyard, hedges and graves — roads only at the edges."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.GRAVE_STONE, VoxelMaterial.STONE, VoxelMaterial.BRICK_DARK
			])
			t.townhouse_mats = PackedInt32Array([
				VoxelMaterial.GRAVE_STONE, VoxelMaterial.BRICK_DARK
			])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF, VoxelMaterial.GRAVE_STONE])
			t.base_mat = VoxelMaterial.GRAVE_STONE
			t.tower_shaft_mat = VoxelMaterial.GRAVE_STONE
			t.accent_mat = VoxelMaterial.WROUGHT_IRON
			t.band_mats = PackedInt32Array([
				VoxelMaterial.GRAVE_STONE, VoxelMaterial.GRAVE_MARBLE,
				VoxelMaterial.BRICK_DARK, VoxelMaterial.STONE
			])
			t.sidewalk_mat = VoxelMaterial.GRAVE_PATH
			t.plaza_mat = VoxelMaterial.GRAVE_SOIL
			t.plaza_inner_mat = VoxelMaterial.GRAVE_PATH
			t.intensity_bias = -0.5
			t.height_scale = 0.0
			t.tower_chance = 0.0
			t.modern_chance = 0.0
			t.spiral_chance = 0.0
			t.l_mass_chance = 0.0
			t.cylinder_chance = 0.0
			t.wild_chance = 0.0
			t.park_count = 0
			t.road_density = 0.0
			t.median_planting = false
		LAKE:
			t.display_name = "Lake"
			t.blurb = "One big natural lake with wooded islands — roads only at the edges."
			## No lots here either, but shore props still read from the palette.
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.PLASTER, VoxelMaterial.BRICK
			])
			t.townhouse_mats = PackedInt32Array([VoxelMaterial.PLASTER, VoxelMaterial.STONE])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF_CLAY])
			t.base_mat = VoxelMaterial.STONE
			t.tower_shaft_mat = VoxelMaterial.STONE
			t.accent_mat = VoxelMaterial.GRAVEL
			t.band_mats = PackedInt32Array([
				VoxelMaterial.STONE, VoxelMaterial.GRAVEL, VoxelMaterial.DIRT,
				VoxelMaterial.PLASTER
			])
			t.sidewalk_mat = VoxelMaterial.GRAVEL
			t.plaza_mat = VoxelMaterial.GRAVEL
			t.plaza_inner_mat = VoxelMaterial.DIRT
			t.intensity_bias = -0.5
			t.height_scale = 0.0
			t.tower_chance = 0.0
			t.modern_chance = 0.0
			t.spiral_chance = 0.0
			t.l_mass_chance = 0.0
			t.cylinder_chance = 0.0
			t.wild_chance = 0.0
			t.park_count = 0
			## No interior streets — planner stamps short edge stubs only.
			t.road_density = 0.0
			t.median_planting = true
		CASTLE:
			t.display_name = "Castle"
			t.blurb = "A walled fortress on a plinth, reached by a causeway — roads only at the edges."
			t.wall_mats = PackedInt32Array([
				VoxelMaterial.CASTLE_BLOCK, VoxelMaterial.CASTLE_BLOCK_MOSSY,
				VoxelMaterial.STONE
			])
			t.townhouse_mats = PackedInt32Array([
				VoxelMaterial.CASTLE_BLOCK, VoxelMaterial.STONE
			])
			t.roof_mats = PackedInt32Array([VoxelMaterial.ROOF_CLAY, VoxelMaterial.CASTLE_BLOCK])
			t.base_mat = VoxelMaterial.CASTLE_BLOCK
			t.tower_shaft_mat = VoxelMaterial.CASTLE_BLOCK
			t.accent_mat = VoxelMaterial.WROUGHT_IRON
			t.band_mats = PackedInt32Array([
				VoxelMaterial.CASTLE_BLOCK, VoxelMaterial.CASTLE_BLOCK_MOSSY,
				VoxelMaterial.STONE, VoxelMaterial.BRICK_DARK
			])
			t.sidewalk_mat = VoxelMaterial.GRAVEL
			t.plaza_mat = VoxelMaterial.GRAVEL
			t.plaza_inner_mat = VoxelMaterial.DIRT
			t.intensity_bias = -0.5
			t.height_scale = 0.0
			t.tower_chance = 0.0
			t.modern_chance = 0.0
			t.spiral_chance = 0.0
			t.l_mass_chance = 0.0
			t.cylinder_chance = 0.0
			t.wild_chance = 0.0
			t.park_count = 0
			## No interior streets — planner stamps short edge stubs only.
			t.road_density = 0.0
			t.median_planting = false
		_:
			push_error("DistrictTheme.make: unknown theme id %d" % theme_id)
	return t


func wall_for(rng: RandomNumberGenerator, townhouse: bool) -> int:
	var pool := townhouse_mats if townhouse else wall_mats
	if pool.is_empty():
		push_error("DistrictTheme %s: empty wall palette" % display_name)
		return VoxelMaterial.CONCRETE
	return pool[rng.randi() % pool.size()]


func roof_for(rng: RandomNumberGenerator) -> int:
	if roof_mats.is_empty():
		push_error("DistrictTheme %s: empty roof palette" % display_name)
		return VoxelMaterial.ROOF
	return roof_mats[rng.randi() % roof_mats.size()]


## Band / pilaster material for shafts and wild massing.
func band_for(rng: RandomNumberGenerator) -> int:
	if band_mats.is_empty():
		push_error("DistrictTheme %s: empty band palette" % display_name)
		return VoxelMaterial.CONCRETE
	return band_mats[rng.randi() % band_mats.size()]
