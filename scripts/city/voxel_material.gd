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

const COUNT := 41


static func is_solid(id: int) -> bool:
	return id != AIR


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
	)


static func is_ground_surface(id: int) -> bool:
	## Outdoor ground / road deck — meteor auto-spawns land here, never on buildings.
	## Diggable STONE substrate under the deck is not a landing / ped surface.
	match id:
		ROAD, SIDEWALK, PLAZA, PARK, ASPHALT, GRAVEL, DIRT, CURB, ROAD_LINE, CROSSWALK, TILES, CAVE_FLOOR, GRAVE_PATH, GRAVE_SOIL:
			return true
		_:
			return false


## Stone fill under the street deck — diggable, not pavement.
static func is_diggable_substrate(id: int) -> bool:
	return id == STONE


## Rock, soil and turf carry their own weight: a blast leaves a crater, never a
## collapsing column. Built fabric is the only thing the debris cascade may pull
## down — a hill is one connected massif, so cascading it eats the whole mountain.
static func is_self_supporting_terrain(id: int) -> bool:
	match id:
		STONE, DIRT, GRAVEL, PARK, CAVE_WALL, CAVE_FLOOR, GRAVE_SOIL, GRAVE_PATH:
			return true
		_:
			return false


static func is_building_fabric(id: int) -> bool:
	## Structural / prop voxels: walls, roofs, trees, fixtures — not ground, road, or diggable stone.
	match id:
		AIR, BEDROCK, STONE, ROAD, SIDEWALK, PLAZA, PARK, ASPHALT, GRAVEL, DIRT, WATER, CURB, ROAD_LINE, CROSSWALK, TILES, CAVE_WALL, CAVE_FLOOR, GRAVE_SOIL, GRAVE_PATH:
			return false
		METEOR_ROCK, INFECTION, INFECTION_LEAD, GAMEBOY:
			return true
		_:
			return id > AIR and id < COUNT


## Walls/props undead may stomp or nibble — never infection, meteor rock, or park trees.
static func is_undead_structure_target(id: int) -> bool:
	if is_infection(id) or id == METEOR_ROCK:
		return false
	if is_vegetation(id):
		return false
	if not is_building_fabric(id):
		return false
	return is_destructible(id)


## Park / plaza greenery — giants and minions should ignore these.
static func is_vegetation(id: int) -> bool:
	return id == BARK or id == LEAVES or id == PLANTER or id == YEW


static func is_destructible(id: int) -> bool:
	## Laser / melee / blast carve targets. Infection body + meteor rock are immune;
	## only the glowing tip (INFECTION_LEAD) stays player-killable.
	if id == AIR or id == BEDROCK or id == WATER:
		return false
	if id == METEOR_ROCK or id == INFECTION:
		return false
	return id > AIR and id < COUNT


static func is_player_carve_immune(id: int) -> bool:
	return id == METEOR_ROCK or id == INFECTION or id == BEDROCK or id == WATER or id == AIR


static func is_infection(id: int) -> bool:
	return id == INFECTION or id == INFECTION_LEAD


static func is_infectable(id: int) -> bool:
	## Tendrils crawl into normal fabric/ground — never infection, meteor rock, or diggable stone under the deck.
	if is_infection(id) or id == METEOR_ROCK or is_diggable_substrate(id):
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
		ROOF:
			return Color(0.35, 0.32, 0.3)
		ROOF_CLAY:
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
		_:
			return Color(1, 0, 1)
