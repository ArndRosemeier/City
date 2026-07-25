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
const COUNT := 5

## Districts within this many tiles of the world origin are always the high-rise core.
const CORE_RING := 0

var id: int = CORE_HIGHRISE
var display_name: String = "Core High-Rise"
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
		choices = PackedInt32Array([OLD_TOWN, CIVIC_QUARTER, GARDEN_RESIDENTIAL, WATERFRONT_INDUSTRIAL])
	else:
		choices = PackedInt32Array([GARDEN_RESIDENTIAL, OLD_TOWN, WATERFRONT_INDUSTRIAL, GARDEN_RESIDENTIAL])
	return make(choices[pick % choices.size()])


static func make(theme_id: int) -> DistrictTheme:
	var t := DistrictTheme.new()
	t.id = theme_id
	match theme_id:
		CORE_HIGHRISE:
			t.display_name = "Core High-Rise"
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
