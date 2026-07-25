//! Voxel material ids / predicates — keep in sync with scripts/city/voxel_material.gd

pub const AIR: i32 = 0;
pub const BEDROCK: i32 = 1;
pub const BARK: i32 = 23;
pub const LEAVES: i32 = 24;
pub const METEOR_ROCK: i32 = 29;
pub const INFECTION: i32 = 30;
pub const INFECTION_LEAD: i32 = 31;
pub const COUNT: i32 = 32;

pub fn is_solid(id: i32) -> bool {
    id != AIR
}

pub fn is_destructible(id: i32) -> bool {
    if id == AIR || id == BEDROCK || id == 17 {
        // WATER
        return false;
    }
    if id == METEOR_ROCK || id == INFECTION {
        return false;
    }
    id > AIR && id < COUNT
}

pub fn is_infection(id: i32) -> bool {
    id == INFECTION || id == INFECTION_LEAD
}
