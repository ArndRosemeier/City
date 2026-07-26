//! Voxel material ids / predicates — keep in sync with scripts/city/voxel_material.gd

pub const AIR: i32 = 0;
pub const BEDROCK: i32 = 1;
pub const PARK: i32 = 8;
pub const GRAVEL: i32 = 15;
pub const DIRT: i32 = 16;
pub const WATER: i32 = 17;
pub const BARK: i32 = 23;
pub const LEAVES: i32 = 24;
pub const STONE: i32 = 25;
pub const METEOR_ROCK: i32 = 29;
pub const INFECTION: i32 = 30;
pub const INFECTION_LEAD: i32 = 31;
pub const GAMEBOY: i32 = 32;
pub const CAVE_WALL: i32 = 33;
pub const CAVE_FLOOR: i32 = 34;
pub const COUNT: i32 = 35;

pub fn is_solid(id: i32) -> bool {
    id != AIR
}

pub fn is_destructible(id: i32) -> bool {
    if id == AIR || id == BEDROCK || id == WATER {
        return false;
    }
    if id == METEOR_ROCK || id == INFECTION {
        return false;
    }
    id > AIR && id < COUNT
}

/// Rock, soil and turf carry their own weight — a blast leaves a crater, never a
/// collapsing column.
pub fn is_self_supporting_terrain(id: i32) -> bool {
    matches!(id, STONE | DIRT | GRAVEL | PARK | CAVE_WALL | CAVE_FLOOR)
}

/// Only built fabric may be pulled down by the debris cascade. A hill is one
/// connected massif, so letting rock cascade lets a single shot inside a cave eat
/// the whole mountain column by column.
pub fn cascades(id: i32) -> bool {
    is_destructible(id) && !is_self_supporting_terrain(id)
}

pub fn is_infection(id: i32) -> bool {
    id == INFECTION || id == INFECTION_LEAD
}
