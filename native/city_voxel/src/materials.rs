//! Voxel material ids / predicates — keep in sync with scripts/city/voxel_material.gd

pub const AIR: i32 = 0;
pub const BEDROCK: i32 = 1;
pub const PARK: i32 = 8;
pub const GRAVEL: i32 = 15;
pub const DIRT: i32 = 16;
pub const WATER: i32 = 17;
pub const BARK: i32 = 23;
pub const LEAVES: i32 = 24;
/// Kept for id parity with `voxel_material.gd` even when unused in native code.
#[allow(dead_code)]
pub const STONE: i32 = 25;
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
#[allow(dead_code)]
pub const PROP_FIRST: i32 = 75;
#[allow(dead_code)]
pub const PROP_LAST: i32 = 179;
pub const COUNT: i32 = 180;

pub fn is_solid(id: i32) -> bool {
    id != AIR
}

pub fn is_gem(id: i32) -> bool {
    id >= GEM_QUARTZ && id <= GEM_DIAMOND
}

pub fn is_destructible(id: i32) -> bool {
    if id == AIR || id == BEDROCK || id == WATER {
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
        DIRT | GRAVEL | PARK | GRAVE_SOIL | GRAVE_PATH | FRACTAL_GLOW
    ) || (id >= FRACTAL_BAND_0 && id <= FRACTAL_BAND_15)
        || id == FRACTAL_INTERIOR
}

/// Destructible voxels cascade unless they are soft self-supporting terrain.
pub fn cascades(id: i32) -> bool {
    is_destructible(id) && !is_self_supporting_terrain(id)
}

pub fn is_infection(id: i32) -> bool {
    id == INFECTION || id == INFECTION_LEAD
}
