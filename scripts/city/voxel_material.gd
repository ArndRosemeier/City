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

const COUNT := 29


static func is_solid(id: int) -> bool:
	return id != AIR


static func is_walkable_surface(id: int) -> bool:
	## Pedestrians: sidewalks / plazas / parks / crosswalks only — not car asphalt.
	return (
		id == PLAZA
		or id == SIDEWALK
		or id == GRAVEL
		or id == DIRT
		or id == TILES
		or id == PARK
		or id == CROSSWALK
	)


static func is_building_fabric(id: int) -> bool:
	## Structural / prop voxels: walls, roofs, trees, fixtures — not ground or road.
	match id:
		AIR, BEDROCK, ROAD, SIDEWALK, PLAZA, PARK, ASPHALT, GRAVEL, DIRT, WATER, CURB, ROAD_LINE, CROSSWALK, TILES:
			return false
		_:
			return id > AIR and id < COUNT


static func is_destructible(id: int) -> bool:
	## Laser / melee carve targets: any solid voxel asset except bedrock and water.
	return id != AIR and id != BEDROCK and id != WATER and id > AIR and id < COUNT


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
		_:
			return Color(1, 0, 1)
