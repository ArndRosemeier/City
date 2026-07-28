## Per-material surface description for the shared voxel surface shaders.
##
## `tile_meters` is how much world space one texture repeat covers. It is a Vector2
## because brick / concrete maps are 2:1 — mapping those isotropically would stretch
## the courses vertically.
class_name VoxelSurfaceSpec
extends RefCounted

enum Kind {
	## voxel_surface.gdshader
	OPAQUE,
	## voxel_glass.gdshader
	GLASS,
	## voxel_water.gdshader
	WATER,
	## voxel_foliage.gdshader — UV alpha cutout on leaf / yew cards
	FOLIAGE,
}

var kind: Kind = Kind.OPAQUE
var albedo_file: String = ""
var normal_file: String = ""
var tile_meters: Vector2 = Vector2(2.0, 2.0)
var tint: Color = Color(1, 1, 1, 1)
var roughness: float = 0.88
var metallic: float = 0.0
var normal_strength: float = 0.85
## Per-lot albedo spread so identical materials differ between buildings.
var tint_variation: float = 0.0
## Metre-scale mottling for large ground planes, and the patch size it works at. A
## photoscanned lawn has no structure above blade scale, so minification flattens it.
var patch_variation: float = 0.0
var patch_meters: float = 2.5
## Building-scale dirt/fade that breaks up texture repetition.
var weathering: float = 0.0
## Ground contact grime strength, and how far up it reaches in metres.
var grime: float = 0.0
var grime_height: float = 4.0
## Vertical wash marks on upright faces.
var streaks: float = 0.0
## GLASS only: fraction of windows that may light up at night.
var lit_ratio: float = 0.0


## Materials with their own bespoke shader (infection, meteor rock, Game Boy, gems).
static func has_bespoke_shader(id: int) -> bool:
	if VoxelMaterial.is_gem(id):
		return true
	match id:
		VoxelMaterial.INFECTION, VoxelMaterial.INFECTION_LEAD, VoxelMaterial.METEOR_ROCK, VoxelMaterial.GAMEBOY:
			return true
		_:
			return false


static func for_id(id: int) -> VoxelSurfaceSpec:
	var s := VoxelSurfaceSpec.new()
	match id:
		VoxelMaterial.BEDROCK:
			s.albedo_file = "rock.jpg"
			s.normal_file = "rock_normal.jpg"
			s.tile_meters = Vector2(4.0, 4.0)
			s.roughness = 0.95
			s.normal_strength = 1.0
			s.weathering = 0.5
		VoxelMaterial.ROAD, VoxelMaterial.ASPHALT:
			s.albedo_file = "asphalt.jpg"
			s.normal_file = "asphalt_normal.jpg"
			s.tile_meters = Vector2(5.0, 5.0)
			## The source map is a light grey aggregate; darken it to read as tarmac
			## against the pale sidewalk setts.
			s.tint = Color(0.5, 0.51, 0.56, 1.0)
			s.roughness = 0.92
			## Patchy repairs and oil staining on the carriageway.
			s.weathering = 0.45
		VoxelMaterial.SIDEWALK:
			s.albedo_file = "sidewalk.jpg"
			s.normal_file = "sidewalk_normal.jpg"
			s.tile_meters = Vector2(2.0, 2.0)
			s.roughness = 0.9
			s.weathering = 0.3
		VoxelMaterial.CURB:
			## Cast concrete kerbstone. It used to carry per-pixel white noise under the
			## sidewalk's paving-herringbone relief, which put a noise slab embossed with
			## setts along every street edge — all of it in the near field.
			s.albedo_file = "concrete.jpg"
			s.normal_file = "concrete_normal.jpg"
			s.tile_meters = Vector2(2.0, 1.0)
			## A stop below the paving it edges, or the kerb reads as a white line.
			s.tint = Color(0.72, 0.72, 0.74, 1.0)
			s.roughness = 0.9
			s.weathering = 0.25
			s.grime = 0.45
			s.grime_height = 0.6
		VoxelMaterial.CONCRETE:
			s.albedo_file = "concrete.jpg"
			s.normal_file = "concrete_normal.jpg"
			s.tile_meters = Vector2(4.0, 2.0)
			s.tint = Color(0.88, 0.88, 0.9, 1.0)
			s.roughness = 0.9
			s.tint_variation = 0.5
			s.weathering = 0.55
			s.grime = 0.7
			s.streaks = 0.45
		VoxelMaterial.BRICK:
			## Despite the name this map is rough stone masonry — blocks read ~0.35 m,
			## so one repeat covers 3 x 1.5 m.
			s.albedo_file = "brick.jpg"
			s.normal_file = "brick_normal.jpg"
			s.tile_meters = Vector2(3.0, 1.5)
			s.roughness = 0.85
			s.tint_variation = 0.6
			s.weathering = 0.5
			s.grime = 0.75
			s.streaks = 0.4
		VoxelMaterial.BRICK_DARK:
			## Real brick: ~16 courses over the map height at 0.075 m per course. The
			## relief has to come from the same ambientCG asset as the albedo, or the
			## bump runs across the courses instead of along them.
			s.albedo_file = "brick_dark.jpg"
			s.normal_file = "brick_dark_normal.jpg"
			s.tile_meters = Vector2(2.4, 1.2)
			s.roughness = 0.85
			s.tint_variation = 0.55
			s.weathering = 0.55
			s.grime = 0.8
			s.streaks = 0.45
		VoxelMaterial.PLASTER:
			s.albedo_file = "plaster.jpg"
			s.normal_file = "plaster_normal.jpg"
			s.tile_meters = Vector2(3.0, 3.0)
			s.tint = Color(0.86, 0.85, 0.82, 1.0)
			s.roughness = 0.9
			s.tint_variation = 0.8
			s.weathering = 0.6
			s.grime = 0.8
			s.streaks = 0.55
		VoxelMaterial.STONE:
			s.albedo_file = "stone.jpg"
			s.normal_file = "stone_normal.jpg"
			s.tile_meters = Vector2(2.5, 2.5)
			s.roughness = 0.88
			s.tint_variation = 0.35
			s.weathering = 0.5
			s.grime = 0.65
			s.streaks = 0.3
		VoxelMaterial.PLAZA:
			s.albedo_file = "plaza.jpg"
			s.normal_file = "plaza_normal.jpg"
			s.tile_meters = Vector2(3.0, 3.0)
			s.roughness = 0.88
			s.normal_strength = 0.95
			s.weathering = 0.3
		VoxelMaterial.TILES:
			## 0.36 m glazed tiles: the diamond lattice is authored at that pitch in
			## generate_city_textures.py (see tile_meters.json).
			s.albedo_file = "tiles.jpg"
			s.normal_file = "tiles_normal.jpg"
			s.tile_meters = Vector2(5.76, 5.76)
			s.roughness = 0.55
			s.normal_strength = 0.9
			s.tint_variation = 0.45
			s.weathering = 0.3
			s.streaks = 0.25
		VoxelMaterial.PARK:
			s.albedo_file = "grass.jpg"
			s.normal_file = "grass_normal.jpg"
			## The largest surface in the game. Blade detail in the photoscan is a texel
			## wide, so mipmaps average it to felt whatever the tiling is; the structure
			## that survives is the patch mottling, and the tile is sized so the source's
			## own clumps land at ~10 cm rather than under a millimetre.
			s.tile_meters = Vector2(2.6, 2.6)
			s.roughness = 0.95
			s.normal_strength = 0.7
			s.tint_variation = 0.22
			s.patch_variation = 0.85
			s.patch_meters = 2.6
			s.weathering = 0.3
		VoxelMaterial.GRAVEL:
			s.albedo_file = "gravel.jpg"
			s.normal_file = "gravel_normal.jpg"
			s.tile_meters = Vector2(2.0, 2.0)
			## Warm sand tone: untinted gravel read as bright white concrete next to lawn.
			s.tint = Color(0.82, 0.74, 0.62, 1.0)
			s.roughness = 0.95
			s.normal_strength = 1.0
			s.tint_variation = 0.2
			s.weathering = 0.45
		VoxelMaterial.DIRT:
			s.albedo_file = "dirt.jpg"
			s.normal_file = "dirt_normal.jpg"
			s.tile_meters = Vector2(3.0, 3.0)
			s.roughness = 0.95
			s.normal_strength = 0.9
			s.patch_variation = 0.45
			s.patch_meters = 3.2
			s.weathering = 0.4
		VoxelMaterial.ROOF, VoxelMaterial.ROOF_SLOPE_POS_X, VoxelMaterial.ROOF_SLOPE_NEG_X, VoxelMaterial.ROOF_SLOPE_POS_Z, VoxelMaterial.ROOF_SLOPE_NEG_Z:
			## Standing seam at a 0.4 m rib pitch — authored in
			## generate_city_textures.py, published in tile_meters.json. At the old 2.5 m
			## repeat the ribs landed 0.117 m apart, a quarter of a voxel, so a whole roof
			## read as corduroy.
			s.albedo_file = "roof.jpg"
			s.normal_file = "roof_normal.jpg"
			s.tile_meters = Vector2(6.4, 6.4)
			s.roughness = 0.55
			s.metallic = 0.35
			s.normal_strength = 1.05
			s.tint_variation = 0.45
			s.weathering = 0.7
		VoxelMaterial.ROOF_CLAY, VoxelMaterial.ROOF_CLAY_SLOPE_POS_X, VoxelMaterial.ROOF_CLAY_SLOPE_NEG_X, VoxelMaterial.ROOF_CLAY_SLOPE_POS_Z, VoxelMaterial.ROOF_CLAY_SLOPE_NEG_Z:
			## Warm terracotta pantiles — authored courses so pitched roofs read at
			## distance instead of crushing into a flat slate slab. One pantile is
			## 0.24 x 0.34 m, which is what fixes this repeat size.
			s.albedo_file = "roof_clay.jpg"
			s.normal_file = "roof_clay_normal.jpg"
			s.tile_meters = Vector2(3.84, 5.44)
			s.roughness = 0.78
			s.normal_strength = 1.0
			s.tint_variation = 0.4
			s.weathering = 0.35
		VoxelMaterial.METAL:
			## Glazing bays of 1.4 x 2.8 m. The old repeat made them 0.3 x 0.6 m, so a
			## forty-storey tower was clad in something the size of bathroom tiling.
			s.albedo_file = "metal.jpg"
			s.normal_file = "metal_normal.jpg"
			s.tile_meters = Vector2(11.2, 11.2)
			## Curtain-wall metal covers whole tower shafts, so it needs the strongest
			## per-lot spread and weathering of any material or every tower matches.
			s.roughness = 0.38
			s.metallic = 0.82
			s.normal_strength = 0.95
			s.tint_variation = 0.55
			s.weathering = 0.5
			s.grime = 0.4
			s.grime_height = 6.0
			s.streaks = 0.5
		VoxelMaterial.METAL_PLATE:
			## 0.9 m plates on 22 mm rivets. At the old repeat the plate was 0.15 m and
			## the rivet 8 mm, which is jewellery, not structure.
			s.albedo_file = "metal_plate.jpg"
			s.normal_file = "metal_plate_normal.jpg"
			s.tile_meters = Vector2(7.2, 7.2)
			s.roughness = 0.48
			s.metallic = 0.78
			s.normal_strength = 1.1
			s.tint_variation = 0.6
			s.weathering = 0.55
			s.grime = 0.45
			s.grime_height = 5.0
			s.streaks = 0.5
		VoxelMaterial.PLANTER:
			s.albedo_file = "wood.jpg"
			s.normal_file = "wood_normal.jpg"
			s.tile_meters = Vector2(1.2, 1.2)
			s.roughness = 0.8
			s.normal_strength = 0.75
			s.tint_variation = 0.3
			s.weathering = 0.4
		VoxelMaterial.BARK:
			s.albedo_file = "bark.jpg"
			s.normal_file = "bark_normal.jpg"
			s.tile_meters = Vector2(1.0, 1.0)
			s.roughness = 0.92
			s.normal_strength = 1.1
			s.tint_variation = 0.35
			s.weathering = 0.35
		VoxelMaterial.LEAVES:
			s.kind = Kind.FOLIAGE
			s.albedo_file = "leaves.png"
			s.tile_meters = Vector2(1.0, 1.0)
			s.roughness = 0.88
			s.tint_variation = 0.4
		VoxelMaterial.PAINT:
			## Accent bands and pilasters: the widest colour spread in the palette, so a
			## banded shaft picks up a different accent hue per lot.
			s.albedo_file = "paint.jpg"
			s.normal_file = "paint_normal.jpg"
			s.tile_meters = Vector2(1.8, 1.8)
			s.roughness = 0.72
			s.normal_strength = 0.55
			s.tint_variation = 0.85
			s.weathering = 0.35
			s.streaks = 0.3
		VoxelMaterial.ROAD_LINE:
			s.albedo_file = "road_line.jpg"
			## One repeat per voxel: the stripe art is authored per cell.
			s.tile_meters = Vector2(VoxelBlockLibrary.VOXEL_WORLD_SIZE, VoxelBlockLibrary.VOXEL_WORLD_SIZE)
			s.roughness = 0.85
			s.weathering = 0.5
		VoxelMaterial.CROSSWALK:
			s.albedo_file = "crosswalk.jpg"
			s.tile_meters = Vector2(VoxelBlockLibrary.VOXEL_WORLD_SIZE, VoxelBlockLibrary.VOXEL_WORLD_SIZE)
			s.roughness = 0.85
			s.weathering = 0.55
		VoxelMaterial.GLASS:
			## One mullion bay per metre, matching the shader's window_meters, so the
			## frames line up with the panes that light at night. The old repeat put a
			## mullion every 0.19 m and drew a fan of diagonal scratches with them.
			s.kind = Kind.GLASS
			s.albedo_file = "glass.jpg"
			s.tile_meters = Vector2(4.0, 4.0)
			s.tint = Color(0.72, 0.86, 1.0, 0.38)
			s.roughness = 0.08
			s.metallic = 0.2
		VoxelMaterial.GLASS_LIT:
			s.kind = Kind.GLASS
			s.albedo_file = "glass.jpg"
			s.tile_meters = Vector2(4.0, 4.0)
			s.tint = Color(0.8, 0.88, 1.0, 0.4)
			s.roughness = 0.12
			s.metallic = 0.15
			s.lit_ratio = 0.62
		VoxelMaterial.WATER:
			s.kind = Kind.WATER
			s.albedo_file = "water.jpg"
			## Large tile so a pool shares one ripple sheet, not a per-metre quilt.
			s.tile_meters = Vector2(8.0, 8.0)
			s.tint = Color(0.5, 0.78, 0.9, 0.62)
			s.roughness = 0.06
			s.metallic = 0.05
		VoxelMaterial.CAVE_WALL:
			s.albedo_file = "cave_wall.jpg"
			s.normal_file = "cave_wall_normal.jpg"
			s.tile_meters = Vector2(3.2, 3.2)
			s.roughness = 0.94
			s.normal_strength = 1.05
			s.tint_variation = 0.25
			s.weathering = 0.55
			s.grime = 0.5
			s.grime_height = 2.5
			s.streaks = 0.65
		VoxelMaterial.CAVE_FLOOR:
			s.albedo_file = "cave_floor.jpg"
			s.normal_file = "cave_floor_normal.jpg"
			s.tile_meters = Vector2(2.4, 2.4)
			s.roughness = 0.96
			s.normal_strength = 0.85
			s.tint_variation = 0.2
			s.weathering = 0.4
		VoxelMaterial.GRAVE_STONE:
			## Headstones are 1-2 voxels wide, so the grain has to repeat per metre or
			## a whole monument samples one flat patch of the map.
			s.albedo_file = "grave_stone.jpg"
			s.normal_file = "grave_stone_normal.jpg"
			s.tile_meters = Vector2(1.0, 1.0)
			## Below mid grey, but no further: at 0.42 the tint stacked with weathering
			## and a 0.8 grime band over a 1.2 m headstone, which put the whole marker
			## inside the darkest part of the wash. Granite, soil, cinder and iron all
			## landed on the same near-black and the district had one material in it.
			s.tint = Color(0.64, 0.63, 0.6, 1.0)
			s.roughness = 0.93
			s.normal_strength = 1.0
			## Low spread: a field of markers that swings from white to black per plot
			## reads as a bug, not as weathering.
			s.tint_variation = 0.18
			s.weathering = 0.45
			s.grime = 0.45
			s.grime_height = 0.7
			s.streaks = 0.5
		VoxelMaterial.GRAVE_MARBLE:
			s.albedo_file = "grave_marble.jpg"
			s.normal_file = "grave_marble_normal.jpg"
			s.tile_meters = Vector2(0.9, 0.9)
			## The pale end of the churchyard: a clear stop above the granite, since the
			## marble monuments are what give a plan of black plots any relief at all.
			s.tint = Color(0.86, 0.86, 0.88, 1.0)
			s.roughness = 0.6
			s.normal_strength = 0.6
			s.tint_variation = 0.12
			s.weathering = 0.4
			s.grime = 0.55
			s.grime_height = 1.4
			s.streaks = 0.6
		VoxelMaterial.GRAVE_SOIL:
			## The one warm material in the kit, so a plot reads as turned earth against
			## the cold grey of the aisle beside it rather than as more black slab.
			s.albedo_file = "grave_soil.jpg"
			s.normal_file = "grave_soil_normal.jpg"
			s.tile_meters = Vector2(1.8, 1.8)
			s.tint = Color(1.0, 0.94, 0.86, 1.0)
			s.roughness = 0.96
			s.normal_strength = 0.9
			s.tint_variation = 0.2
			s.patch_variation = 0.35
			s.patch_meters = 2.0
			s.weathering = 0.35
		VoxelMaterial.GRAVE_PATH:
			## Mid grey and slightly cool: the aisles are the lightest ground in the
			## churchyard, which is what makes the plan of the plots legible from a path.
			s.albedo_file = "grave_path.jpg"
			s.normal_file = "grave_path_normal.jpg"
			s.tile_meters = Vector2(1.6, 1.6)
			s.tint = Color(0.86, 0.87, 0.9, 1.0)
			s.roughness = 0.95
			s.normal_strength = 0.8
			s.tint_variation = 0.15
			s.weathering = 0.35
		VoxelMaterial.WROUGHT_IRON:
			## Railings and finials are single voxels — one repeat per voxel face.
			s.albedo_file = "wrought_iron.jpg"
			s.normal_file = "wrought_iron_normal.jpg"
			s.tile_meters = Vector2(0.5, 0.5)
			## Stays the darkest material in the kit — it is painted iron — but the
			## weathering and grime no longer take it to the same black as the soil.
			s.tint = Color(0.82, 0.8, 0.82, 1.0)
			s.roughness = 0.52
			## Painted iron is a dielectric. At 0.7 metallic the near-black albedo became
			## the reflectance too, so the railings had neither diffuse nor a usable
			## specular and rendered as holes in the scene whatever the tint was set to.
			s.metallic = 0.2
			s.normal_strength = 1.1
			s.tint_variation = 0.2
			s.weathering = 0.4
			s.grime = 0.3
			s.grime_height = 1.0
			s.streaks = 0.45
		VoxelMaterial.YEW:
			s.kind = Kind.FOLIAGE
			s.albedo_file = "yew.png"
			s.tile_meters = Vector2(0.9, 0.9)
			s.tint = Color(0.6, 0.68, 0.62, 1.0)
			s.roughness = 0.92
			s.tint_variation = 0.3
		VoxelMaterial.CASTLE_BLOCK:
			## Dressed ashlar: tile at roughly one course per metre so a curtain wall reads
			## as coursed blocks rather than one smeared cliff of rock.
			s.albedo_file = "stone.jpg"
			s.normal_file = "stone_normal.jpg"
			s.tile_meters = Vector2(1.5, 1.0)
			s.tint = Color(0.62, 0.6, 0.55, 1.0)
			s.roughness = 0.9
			s.normal_strength = 1.1
			s.tint_variation = 0.22
			s.weathering = 0.55
			s.grime = 0.7
			## Tall walls: the wash has to run much further down than a two-storey facade.
			s.grime_height = 8.0
			s.streaks = 0.5
		VoxelMaterial.CASTLE_BLOCK_MOSSY:
			## Same ashlar, greened. Used for lower courses and weathered patches, so it has
			## to read as the *same* wall at a different age, not as a second material.
			s.albedo_file = "stone.jpg"
			s.normal_file = "stone_normal.jpg"
			s.tile_meters = Vector2(1.5, 1.0)
			s.tint = Color(0.42, 0.47, 0.36, 1.0)
			s.roughness = 0.95
			s.normal_strength = 1.1
			s.tint_variation = 0.28
			s.weathering = 0.75
			s.grime = 0.85
			s.grime_height = 8.0
			s.streaks = 0.65
		_:
			push_error(
				"VoxelSurfaceSpec.for_id: no surface spec for voxel material %d — showing magenta"
				% id
			)
			s.albedo_file = "plaster.jpg"
			s.tint = Color(1, 0, 1, 1)
	return s
