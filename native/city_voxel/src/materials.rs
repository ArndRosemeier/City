//! Voxel material ids / predicates — keep in sync with scripts/city/voxel_material.gd

pub const AIR: i32 = 0;
pub const BEDROCK: i32 = 1;
pub const BRICK: i32 = 5;
pub const PARK: i32 = 8;
pub const GRAVEL: i32 = 15;
pub const DIRT: i32 = 16;
pub const WATER: i32 = 17;
pub const BARK: i32 = 23;
pub const LEAVES: i32 = 24;
/// Kept for id parity with `voxel_material.gd` even when unused in native code.
#[allow(dead_code)]
pub const STONE: i32 = 25;
#[allow(dead_code)]
pub const YEW: i32 = 40;
pub const METEOR_ROCK: i32 = 29;
pub const INFECTION: i32 = 30;
pub const INFECTION_LEAD: i32 = 31;
pub const GAMEBOY: i32 = 32;
#[allow(dead_code)]
pub const CAVE_WALL: i32 = 33;
#[allow(dead_code)]
pub const CAVE_FLOOR: i32 = 34;
pub const GRAVE_SOIL: i32 = 37;
pub const GRAVE_PATH: i32 = 38;
pub const GEM_QUARTZ: i32 = 49;
pub const GEM_AMBER: i32 = 50;
pub const GEM_TOPAZ: i32 = 51;
pub const GEM_SAPPHIRE: i32 = 52;
pub const GEM_EMERALD: i32 = 53;
pub const GEM_DIAMOND: i32 = 54;
/// Castle ashlar. Ordinary built stone as far as native code is concerned: destructible
/// and cascading, which the generic rules below already give it.
#[allow(dead_code)]
pub const CASTLE_BLOCK: i32 = 55;
#[allow(dead_code)]
pub const CASTLE_BLOCK_MOSSY: i32 = 56;
/// Fractal plaza glow cubes. Ordinary destructible ground as far as native is concerned.
#[allow(dead_code)]
pub const FRACTAL_GLOW: i32 = 57;
#[allow(dead_code)]
pub const FRACTAL_BAND_0: i32 = 58;
#[allow(dead_code)]
pub const FRACTAL_BAND_15: i32 = 73;
#[allow(dead_code)]
pub const FRACTAL_INTERIOR: i32 = 74;
/// Bridge planking. Ordinary destructible, cascading structure to native code.
#[allow(dead_code)]
pub const TIMBER: i32 = 75;
#[allow(dead_code)]
pub const PROP_FIRST: i32 = 76;
#[allow(dead_code)]
pub const PROP_LAST: i32 = 249;
#[allow(dead_code)]
pub const PROP_FOOTPRINT: i32 = 250;
#[allow(dead_code)]
pub const DOOR: i32 = 251;
#[allow(dead_code)]
pub const ARENA_SHELL: i32 = 252;
/// Invisible walk-through LOS blocker (arena tribune lip). Keep in sync with GD.
#[allow(dead_code)]
pub const LOS_VEIL: i32 = 253;
#[allow(dead_code)]
pub const BRANCH_X: i32 = 254;
#[allow(dead_code)]
pub const BRANCH_Z: i32 = 255;
#[allow(dead_code)]
pub const LEAVES_DARK: i32 = 256;
/// Monster Zoo containment ring. Never yields, like the arena shell.
pub const ZOO_FENCE_FRAME: i32 = 257;
pub const ZOO_FENCE_LINE: i32 = 258;
pub const ZOO_FENCE_GLASS: i32 = 259;
/// Faction home-turf plates (undead … arcane). Soft ground: a blast craters them.
pub const ZOO_TURF_FIRST: i32 = 260;
pub const ZOO_TURF_LAST: i32 = 265;
/// Dark curb around an inset turf well.
pub const ZOO_PLATE_RIM: i32 = 266;
/// Hill-cave boss cage. Blastable (unlike ZOO_FENCE_*); crumble auras skip it in GD.
#[allow(dead_code)]
pub const CAVE_CAGE_FRAME: i32 = 267;
#[allow(dead_code)]
pub const CAVE_CAGE_LINE: i32 = 268;
#[allow(dead_code)]
pub const CAVE_CAGE_GLASS: i32 = 269;
/// Live palette size (type channel + nav tables are full 16-bit — raise freely with new ids).
pub const COUNT: i32 = 270;

#[inline]
pub fn is_zoo_fence(id: i32) -> bool {
    id == ZOO_FENCE_FRAME || id == ZOO_FENCE_LINE || id == ZOO_FENCE_GLASS
}

/// Kept for id parity with `voxel_material.gd` even when unused in native code.
#[allow(dead_code)]
#[inline]
pub fn is_cave_cage(id: i32) -> bool {
    id == CAVE_CAGE_FRAME || id == CAVE_CAGE_LINE || id == CAVE_CAGE_GLASS
}

/// Player-damage detonation flag. GDScript owns the blast; native keeps id parity.
#[allow(dead_code)]
#[inline]
pub fn is_explosive(id: i32) -> bool {
    is_cave_cage(id)
}

#[inline]
pub fn is_zoo_turf(id: i32) -> bool {
    id >= ZOO_TURF_FIRST && id <= ZOO_TURF_LAST
}

#[inline]
pub fn is_wood(id: i32) -> bool {
    id == BARK || id == BRANCH_X || id == BRANCH_Z
}

#[inline]
pub fn is_foliage(id: i32) -> bool {
    id == LEAVES || id == LEAVES_DARK || id == YEW
}

pub fn is_solid(id: i32) -> bool {
    id != AIR
}

pub fn is_gem(id: i32) -> bool {
    id >= GEM_QUARTZ && id <= GEM_DIAMOND
}

/// Rock the cave dresser may relabel as CAVE_WALL / CAVE_FLOOR.
pub fn is_cave_shellable(id: i32) -> bool {
    matches!(
        id,
        BEDROCK | STONE | BRICK | DIRT | GRAVEL | CAVE_WALL
    )
}

pub fn is_destructible(id: i32) -> bool {
    if id == AIR || id == BEDROCK || id == WATER || id == ARENA_SHELL || id == LOS_VEIL {
        return false;
    }
    if is_zoo_fence(id) {
        return false;
    }
    if id == METEOR_ROCK || id == INFECTION || is_gem(id) {
        return false;
    }
    id > AIR && id < COUNT
}

/// Soft soil and turf carry their own weight — a blast leaves a crater, never a
/// collapsing column. Stone and cave fabric cascade like built structure.
pub fn is_self_supporting_terrain(id: i32) -> bool {
    matches!(
        id,
        DIRT | GRAVEL | PARK | GRAVE_SOIL | GRAVE_PATH | FRACTAL_GLOW | ZOO_PLATE_RIM
    ) || (id >= FRACTAL_BAND_0 && id <= FRACTAL_BAND_15)
        || id == FRACTAL_INTERIOR
        || is_zoo_turf(id)
}

/// Destructible voxels cascade unless they are soft self-supporting terrain.
pub fn cascades(id: i32) -> bool {
    is_destructible(id) && !is_self_supporting_terrain(id)
}

pub fn is_infection(id: i32) -> bool {
    id == INFECTION || id == INFECTION_LEAD
}
