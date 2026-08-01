## Voxel material palette ids (0 = air).
class_name VoxelMaterial
extends Object

const AIR := 0
const BEDROCK := 1
const ROAD := 2
const SIDEWALK := 3
const CONCRETE := 4
const BRICK := 5
const GLASS := 6
const PLAZA := 7
const PARK := 8
const ASPHALT := 9
const ROOF := 10
const PLANTER := 11
const PLASTER := 12
const METAL := 13
const BRICK_DARK := 14
const GRAVEL := 15
const DIRT := 16
const WATER := 17
const CURB := 18
const ROAD_LINE := 19
const CROSSWALK := 20
const TILES := 21
const ROOF_CLAY := 22
const BARK := 23
const LEAVES := 24
const STONE := 25
const METAL_PLATE := 26
const PAINT := 27
const GLASS_LIT := 28
const METEOR_ROCK := 29
const INFECTION := 30
const INFECTION_LEAD := 31
## Destructible Game Boy / Tetris cabinet shell.
const GAMEBOY := 32
## Hill-cave lining — damp limestone walls and packed earth floors.
const CAVE_WALL := 33
const CAVE_FLOOR := 34
## Graveyard kit. Monuments are their own materials because headstones are one or
## two voxels wide — facade maps tile far too coarsely to read as carved stone.
## Lichen-blackened granite: headstones, kerbs, mausoleum walls, gate piers.
const GRAVE_STONE := 35
## Cold pale marble with dark veins — obelisks, lids, pediments. The only bright
## value in the district, so silhouettes still read against the yew.
const GRAVE_MARBLE := 36
## Consecrated loam: near-black turned earth on the plots.
const GRAVE_SOIL := 37
## Cinder aisle grit — the walkable path surface between plots.
const GRAVE_PATH := 38
## Rusted wrought iron: railings, finials, door grilles, crosses.
const WROUGHT_IRON := 39
## Churchyard yew — nearly black evergreen for hedges and cypresses.
const YEW := 40
## 45° roof wedges. High face sits on the named axis side of the cell; the pitch
## drops toward the opposite side. Separate ids per look because the block library
## stores one mesh per type.
const ROOF_SLOPE_POS_X := 41
const ROOF_SLOPE_NEG_X := 42
const ROOF_SLOPE_POS_Z := 43
const ROOF_SLOPE_NEG_Z := 44
const ROOF_CLAY_SLOPE_POS_X := 45
const ROOF_CLAY_SLOPE_NEG_X := 46
const ROOF_CLAY_SLOPE_POS_Z := 47
const ROOF_CLAY_SLOPE_NEG_Z := 48
## Hill ore — fantasy gems, common → legendary. See rarity weights in pick_gem().
const GEM_QUARTZ := 49
const GEM_AMBER := 50
const GEM_TOPAZ := 51
const GEM_SAPPHIRE := 52
const GEM_EMERALD := 53
const GEM_DIAMOND := 54
## Castle kit: dressed ashlar for the plinth, curtain wall, towers and gatehouse, plus a
## weathered variant. Both destructible and cascading like ordinary built stone — blasting
## a breach into the curtain is meant to work.
const CASTLE_BLOCK := 55
const CASTLE_BLOCK_MOSSY := 56
## Fractal plaza deck — solid uni cubes with gem-like emission. Destructible and
## not collectible (unlike GEM_*); painted by FractalComposer only.
const FRACTAL_GLOW := 57
## Mandelbrot sculpture bands — carveable palette stops, not GEM_* collectibles.
const FRACTAL_BAND_0 := 58
const FRACTAL_BAND_1 := 59
const FRACTAL_BAND_2 := 60
const FRACTAL_BAND_3 := 61
const FRACTAL_BAND_4 := 62
const FRACTAL_BAND_5 := 63
const FRACTAL_BAND_6 := 64
const FRACTAL_BAND_7 := 65
const FRACTAL_BAND_8 := 66
const FRACTAL_BAND_9 := 67
const FRACTAL_BAND_10 := 68
const FRACTAL_BAND_11 := 69
const FRACTAL_BAND_12 := 70
const FRACTAL_BAND_13 := 71
const FRACTAL_BAND_14 := 72
const FRACTAL_BAND_15 := 73
## Mandelbrot set body (interior) — dark deck, not the glowing plaza.
const FRACTAL_INTERIOR := 74
## Sawn planks: bridge decks and the drawbridge leaf. Walkable like a pavement and
## destructible like the rest of a built structure — a bridge you can cut is the point.
const TIMBER := 75
## Room prop kit — see RoomPropCatalog / tools/gen_room_prop_catalog.py.
const PROP_FIRST := 76
const PROP_LAST := 249
const PROP_COUNT := 174
## Invisible solid filler for multi-cell prop footprints (nav / occupancy).
const PROP_FOOTPRINT := 250
## Closed door plug — solid barrier in a doorway clear (E-toggle; open restores AIR).
const DOOR := 251
## Arena pit walls / undercroft / lift shafts — looks like masonry, never digs away.
const ARENA_SHELL := 252
## Invisible, walk-through volume that still blocks combat LOS / projectiles (arena lip).
const LOS_VEIL := 253
## Oriented thin wood cylinders for landmark trees (axis = cell traversal direction).
const BRANCH_X := 254
const BRANCH_Z := 255
## Darker underside foliage for landmark canopy depth (past the old 256 soft cap).
const LEAVES_DARK := 256
## Legacy aliases (first kit) — prefer RoomPropCatalog.id_for_stem.
const PROP_CRATE := PROP_FIRST
const PROP_BARREL := PROP_FIRST + 1
const PROP_CHAIR := PROP_FIRST + 2
## Live palette size (type channel + nav tables are full 16-bit — raise freely with new ids).
const COUNT := 257
const FRACTAL_BAND_COUNT := 16
const FRACTAL_BAND_FIRST := FRACTAL_BAND_0
const FRACTAL_BAND_LAST := FRACTAL_BAND_15

## Rarity weights for pick_gem (sum = 100).
const GEM_WEIGHT_QUARTZ := 48
const GEM_WEIGHT_AMBER := 24
const GEM_WEIGHT_TOPAZ := 14
const GEM_WEIGHT_SAPPHIRE := 8
const GEM_WEIGHT_EMERALD := 4
const GEM_WEIGHT_DIAMOND := 2

## Which cell face is the tall eaves / ridge side of a slope wedge.
const SLOPE_HIGH_POS_X := 0
const SLOPE_HIGH_NEG_X := 1
const SLOPE_HIGH_POS_Z := 2
const SLOPE_HIGH_NEG_Z := 3


## Slope type for a flat roof material (`ROOF` or `ROOF_CLAY`) with the tall face
## toward `high_toward` (`SLOPE_HIGH_*`). Other base mats fall back to the cube id.
static func roof_slope(base_mat: int, high_toward: int) -> int:
	var clay := base_mat == ROOF_CLAY
	match high_toward:
		SLOPE_HIGH_POS_X:
			return ROOF_CLAY_SLOPE_POS_X if clay else ROOF_SLOPE_POS_X
		SLOPE_HIGH_NEG_X:
			return ROOF_CLAY_SLOPE_NEG_X if clay else ROOF_SLOPE_NEG_X
		SLOPE_HIGH_POS_Z:
			return ROOF_CLAY_SLOPE_POS_Z if clay else ROOF_SLOPE_POS_Z
		SLOPE_HIGH_NEG_Z:
			return ROOF_CLAY_SLOPE_NEG_Z if clay else ROOF_SLOPE_NEG_Z
		_:
			push_error("VoxelMaterial.roof_slope: unknown high_toward %d" % high_toward)
			return base_mat


static func is_roof_slope(id: int) -> bool:
	return id >= ROOF_SLOPE_POS_X and id <= ROOF_CLAY_SLOPE_NEG_Z


static func is_solid(id: int) -> bool:
	return id != AIR


static func is_los_veil(id: int) -> bool:
	return id == LOS_VEIL


static func is_walkable_surface(id: int) -> bool:
	## Pedestrians: sidewalks / plazas / parks / crosswalks / cave floors — not car asphalt.
	return (
		id == PLAZA
		or id == SIDEWALK
		or id == GRAVEL
		or id == DIRT
		or id == TILES
		or id == PARK
		or id == CROSSWALK
		or id == CAVE_FLOOR
		or id == GRAVE_PATH
		or id == GRAVE_SOIL
		or id == FRACTAL_GLOW
		or id == FRACTAL_INTERIOR
		or id == GLASS
		or id == GLASS_LIT
		or id == TIMBER
		or is_fractal_band(id)
	)


static func is_ground_surface(id: int) -> bool:
	## Outdoor ground / road deck — meteor auto-spawns land here, never on buildings.
	## Diggable STONE substrate under the deck is not a landing / ped surface.
	match id:
		ROAD, SIDEWALK, PLAZA, PARK, ASPHALT, GRAVEL, DIRT, CURB, ROAD_LINE, CROSSWALK, TILES, CAVE_FLOOR, GRAVE_PATH, GRAVE_SOIL, FRACTAL_GLOW, FRACTAL_INTERIOR:
			return true
		_:
			return false


## Stone fill under the street deck — diggable, not pavement.
static func is_diggable_substrate(id: int) -> bool:
	return id == STONE


## Soft soil and turf carry their own weight: a blast leaves a crater, never a
## collapsing column. Stone and cave fabric cascade like built structure.
static func is_self_supporting_terrain(id: int) -> bool:
	match id:
		DIRT, GRAVEL, PARK, GRAVE_SOIL, GRAVE_PATH, FRACTAL_GLOW, FRACTAL_INTERIOR:
			return true
		_:
			return is_fractal_band(id)


static func is_building_fabric(id: int) -> bool:
	## Structural / prop voxels: walls, roofs, trees, fixtures — not ground, road, or diggable stone.
	match id:
		AIR, BEDROCK, STONE, ROAD, SIDEWALK, PLAZA, PARK, ASPHALT, GRAVEL, DIRT, WATER, CURB, ROAD_LINE, CROSSWALK, TILES, CAVE_WALL, CAVE_FLOOR, GRAVE_SOIL, GRAVE_PATH, FRACTAL_GLOW, FRACTAL_INTERIOR, LOS_VEIL:
			return false
		METEOR_ROCK, INFECTION, INFECTION_LEAD, GAMEBOY:
			return true
		_:
			if is_fractal_band(id):
				return false
			return id > AIR and id < COUNT


## Walls/props an undead stomp or blast may carve — never infection, meteor rock, or park
## trees. Nothing aims at fabric on purpose; this only bounds the collateral.
static func is_undead_structure_target(id: int) -> bool:
	if is_infection(id) or id == METEOR_ROCK or is_gem(id):
		return false
	if is_vegetation(id):
		return false
	if not is_building_fabric(id):
		return false
	return is_destructible(id)


## Park / plaza greenery — giants and minions should ignore these.
static func is_vegetation(id: int) -> bool:
	return is_wood(id) or is_foliage(id) or id == PLANTER


## Trunk + oriented limb segments (landmark tree kit).
static func is_wood(id: int) -> bool:
	return id == BARK or id == BRANCH_X or id == BRANCH_Z


static func is_foliage(id: int) -> bool:
	return id == LEAVES or id == LEAVES_DARK or id == YEW


## Indoor / room furniture stamps (custom meshes in the block library).
static func is_room_prop(id: int) -> bool:
	return id >= PROP_FIRST and id <= PROP_LAST


## Visible prop mesh or its invisible multi-cell footprint filler.
static func is_prop_furniture(id: int) -> bool:
	return is_room_prop(id) or id == PROP_FOOTPRINT


static func is_door(id: int) -> bool:
	return id == DOOR


## Carve difficulty. Soft/Rock are always within the starter blaster; Reinforced and Exotic
## need hardness unlocks. Never never yields.
enum Hardness {
	SOFT = 0,
	ROCK = 1,
	REINFORCED = 2,
	EXOTIC = 3,
	NEVER = 4,
}


static func hardness(id: int) -> Hardness:
	if id == AIR or id == WATER:
		return Hardness.NEVER
	if id == BEDROCK or id == ARENA_SHELL or id == LOS_VEIL:
		return Hardness.NEVER
	if is_gem(id):
		## Collected, not carved — treated as never for carve checks.
		return Hardness.NEVER
	if (
		id == METEOR_ROCK or id == INFECTION or id == INFECTION_LEAD
		or id == FRACTAL_GLOW or id == FRACTAL_INTERIOR or is_fractal_band(id)
	):
		return Hardness.EXOTIC
	if (
		id == CONCRETE or id == METAL or id == METAL_PLATE or id == WROUGHT_IRON
		or id == CASTLE_BLOCK or id == CASTLE_BLOCK_MOSSY or id == TILES
		or id == ROOF or id == ROOF_CLAY or id == GRAVE_STONE or id == GRAVE_MARBLE
		or id == GAMEBOY
		or (id >= ROOF_SLOPE_POS_X and id <= ROOF_CLAY_SLOPE_NEG_Z)
	):
		return Hardness.REINFORCED
	if (
		id == STONE or id == BRICK or id == BRICK_DARK or id == GRAVEL
		or id == CAVE_WALL or id == CAVE_FLOOR or id == CURB or id == ROAD
		or id == ROAD_LINE or id == CROSSWALK or id == ASPHALT or id == SIDEWALK
		or id == PLAZA or id == PAINT or id == TIMBER or id == GRAVE_PATH
	):
		return Hardness.ROCK
	## Dirt, park, plaster, glass, leaves, bark, props, soil, …
	return Hardness.SOFT


static func is_destructible(id: int) -> bool:
	## Laser / melee / blast carve targets. Hardness gates rate/possibility separately —
	## this only answers "is this a solid the world may ever yield".
	if hardness(id) == Hardness.NEVER:
		return false
	if id == INFECTION:
		## Body stays immune; the glowing tip is player-killable.
		return false
	if is_gem(id):
		return false
	return id > AIR and id < COUNT


static func is_player_carve_immune(id: int) -> bool:
	return hardness(id) == Hardness.NEVER or id == INFECTION or is_gem(id)


static func is_infection(id: int) -> bool:
	return id == INFECTION or id == INFECTION_LEAD


static func is_fractal_band(id: int) -> bool:
	return id >= FRACTAL_BAND_FIRST and id <= FRACTAL_BAND_LAST


static func fractal_band(index: int) -> int:
	return FRACTAL_BAND_FIRST + clampi(index, 0, FRACTAL_BAND_COUNT - 1)


static func is_gem(id: int) -> bool:
	return id >= GEM_QUARTZ and id <= GEM_DIAMOND


## Dressed castle masonry, either course. The plinth, curtain and towers are all built
## from these two, so "is this the castle" is one predicate rather than two comparisons.
static func is_castle_block(id: int) -> bool:
	return id == CASTLE_BLOCK or id == CASTLE_BLOCK_MOSSY


static func gem_rarity_weight(id: int) -> int:
	match id:
		GEM_QUARTZ:
			return GEM_WEIGHT_QUARTZ
		GEM_AMBER:
			return GEM_WEIGHT_AMBER
		GEM_TOPAZ:
			return GEM_WEIGHT_TOPAZ
		GEM_SAPPHIRE:
			return GEM_WEIGHT_SAPPHIRE
		GEM_EMERALD:
			return GEM_WEIGHT_EMERALD
		GEM_DIAMOND:
			return GEM_WEIGHT_DIAMOND
		_:
			return 0


## Weighted roll across the fantasy gem chart (weights sum to 100).
static func pick_gem(rng: RandomNumberGenerator) -> int:
	var roll := rng.randi_range(1, 100)
	if roll <= GEM_WEIGHT_QUARTZ:
		return GEM_QUARTZ
	roll -= GEM_WEIGHT_QUARTZ
	if roll <= GEM_WEIGHT_AMBER:
		return GEM_AMBER
	roll -= GEM_WEIGHT_AMBER
	if roll <= GEM_WEIGHT_TOPAZ:
		return GEM_TOPAZ
	roll -= GEM_WEIGHT_TOPAZ
	if roll <= GEM_WEIGHT_SAPPHIRE:
		return GEM_SAPPHIRE
	roll -= GEM_WEIGHT_SAPPHIRE
	if roll <= GEM_WEIGHT_EMERALD:
		return GEM_EMERALD
	return GEM_DIAMOND


static func is_infectable(id: int) -> bool:
	## Tendrils crawl into normal fabric/ground — never infection, meteor rock, gems, or diggable stone.
	if is_infection(id) or id == METEOR_ROCK or is_gem(id) or is_diggable_substrate(id):
		return false
	return is_destructible(id)


static func color(id: int) -> Color:
	match id:
		BEDROCK:
			return Color(0.18, 0.18, 0.2)
		ROAD, ASPHALT, ROAD_LINE:
			return Color(0.16, 0.16, 0.18)
		CROSSWALK:
			return Color(0.85, 0.85, 0.82)
		CURB:
			return Color(0.55, 0.55, 0.52)
		SIDEWALK:
			return Color(0.45, 0.45, 0.48)
		CONCRETE:
			return Color(0.62, 0.62, 0.64)
		BRICK:
			return Color(0.55, 0.28, 0.22)
		BRICK_DARK:
			return Color(0.38, 0.18, 0.14)
		GLASS:
			return Color(0.45, 0.65, 0.82, 0.85)
		GLASS_LIT:
			return Color(1.0, 0.85, 0.45, 0.95)
		PLAZA:
			return Color(0.72, 0.68, 0.58)
		TILES:
			return Color(0.78, 0.74, 0.68)
		PARK, LEAVES:
			return Color(0.28, 0.48, 0.26)
		LEAVES_DARK:
			return Color(0.16, 0.32, 0.14)
		ROOF, ROOF_SLOPE_POS_X, ROOF_SLOPE_NEG_X, ROOF_SLOPE_POS_Z, ROOF_SLOPE_NEG_Z:
			return Color(0.35, 0.32, 0.3)
		ROOF_CLAY, ROOF_CLAY_SLOPE_POS_X, ROOF_CLAY_SLOPE_NEG_X, ROOF_CLAY_SLOPE_POS_Z, ROOF_CLAY_SLOPE_NEG_Z:
			return Color(0.55, 0.28, 0.2)
		PLANTER:
			return Color(0.4, 0.35, 0.28)
		PLASTER:
			return Color(0.82, 0.78, 0.72)
		METAL:
			return Color(0.55, 0.58, 0.62)
		METAL_PLATE:
			return Color(0.42, 0.44, 0.48)
		GRAVEL:
			return Color(0.55, 0.52, 0.48)
		DIRT:
			return Color(0.35, 0.28, 0.2)
		WATER:
			return Color(0.2, 0.42, 0.55, 0.75)
		BARK:
			return Color(0.32, 0.22, 0.14)
		STONE:
			return Color(0.58, 0.56, 0.52)
		PAINT:
			return Color(0.7, 0.35, 0.32)
		METEOR_ROCK:
			return Color(0.22, 0.2, 0.18)
		INFECTION:
			return Color(0.35, 0.72, 0.28)
		INFECTION_LEAD:
			return Color(0.55, 1.0, 0.35)
		GAMEBOY:
			## Classic olive DMG plastic.
			return Color(0.55, 0.62, 0.42)
		CAVE_WALL:
			return Color(0.28, 0.32, 0.31)
		CAVE_FLOOR:
			return Color(0.26, 0.22, 0.17)
		GRAVE_STONE:
			return Color(0.33, 0.34, 0.32)
		GRAVE_MARBLE:
			return Color(0.66, 0.66, 0.68)
		GRAVE_SOIL:
			return Color(0.14, 0.12, 0.1)
		GRAVE_PATH:
			return Color(0.24, 0.24, 0.25)
		WROUGHT_IRON:
			return Color(0.12, 0.12, 0.13)
		YEW:
			return Color(0.11, 0.18, 0.13)
		GEM_QUARTZ:
			return Color(0.85, 0.92, 1.0)
		GEM_AMBER:
			return Color(0.95, 0.62, 0.18)
		GEM_TOPAZ:
			return Color(1.0, 0.72, 0.28)
		GEM_SAPPHIRE:
			return Color(0.22, 0.42, 0.95)
		GEM_EMERALD:
			return Color(0.18, 0.85, 0.42)
		GEM_DIAMOND:
			return Color(0.92, 0.96, 1.0)
		CASTLE_BLOCK:
			return Color(0.52, 0.5, 0.46)
		CASTLE_BLOCK_MOSSY:
			return Color(0.4, 0.44, 0.34)
		ARENA_SHELL:
			return Color(0.78, 0.62, 0.42)
		LOS_VEIL:
			## Debug / atlas only — the block model has no mesh.
			return Color(0.0, 0.0, 0.0, 0.0)
		BRANCH_X, BRANCH_Z:
			return Color(0.42, 0.28, 0.16)
		DOOR:
			## Timber plug — reads as a shut door, not masonry.
			return Color(0.40, 0.26, 0.14)
		FRACTAL_GLOW:
			## Sapphire-leaning cyan — gem look without GEM_* collect/immune rules.
			return Color(0.18, 0.48, 0.95)
		FRACTAL_INTERIOR:
			## Mandelbrot set body — near-black, not the glowing deck.
			return Color(0.04, 0.04, 0.06)
		_:
			if is_room_prop(id):
				return Color(0.55, 0.4, 0.26)
			if is_fractal_band(id):
				return fractal_band_color(id - FRACTAL_BAND_FIRST)
			return Color(1, 0, 1)


## Sculpture exterior colours — full hue wheel so neighbouring bands read as
## distinct hues (the panel's blue→cyan→yellow ramp looked mono when quantized).
static func fractal_band_color(band_index: int) -> Color:
	var i := clampi(band_index, 0, FRACTAL_BAND_COUNT - 1)
	var h := float(i) / float(FRACTAL_BAND_COUNT)
	return Color.from_hsv(h, 0.88, 0.95)
