//! Hill massif paint + gem scatter (ports of HillComposer `_paint_terrain` / `_scatter_gems`).

use crate::materials;
use crate::NativeOfflineVoxelVolume;
use godot::prelude::*;
use std::time::Instant;

const GEM_VOXELS_PER_CLUSTER: i32 = 250;
const GEM_CLUSTER_CAP: i32 = 880;
const GEM_SURFACE_MARGIN: i32 = 3;

/// Must match `assets/gamedata.json` → `district_gems.rarity_weights` and
/// `VoxelMaterial.random_gem` in GDScript. Native hill code cannot read gamedata;
/// keep these in lockstep when the curve changes.
const GEM_WEIGHT_QUARTZ: i32 = 48;
const GEM_WEIGHT_AMBER: i32 = 24;
const GEM_WEIGHT_TOPAZ: i32 = 14;
const GEM_WEIGHT_SAPPHIRE: i32 = 8;
const GEM_WEIGHT_EMERALD: i32 = 4;
const GEM_WEIGHT_DIAMOND: i32 = 2;
const GEM_WEIGHT_TOTAL: i32 = 100;

pub struct PaintStats {
    pub columns: i32,
    pub ms: i64,
}

pub struct GemStats {
    pub clusters: i32,
    pub voxels: i32,
    pub positions: PackedVector3Array,
    pub mats: PackedInt32Array,
    pub ms: i64,
}

/// Tiny PCG — independent of Godot RNG (looks, not bit-parity).
struct Rng {
    state: u64,
}

impl Rng {
    fn new(seed: u64) -> Self {
        Self {
            state: seed.wrapping_mul(0x9E37_79B9_7F4A_7C15).wrapping_add(1),
        }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self
            .state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1);
        (self.state >> 32) as u32
    }

    fn gen_range_i32(&mut self, lo: i32, hi: i32) -> i32 {
        if hi <= lo {
            return lo;
        }
        let span = (hi as i64 - lo as i64 + 1) as u32;
        lo + (self.next_u32() % span) as i32
    }

    fn gen_mod(&mut self, n: i32) -> i32 {
        if n <= 0 {
            return 0;
        }
        (self.next_u32() % n as u32) as i32
    }
}

pub fn paint_terrain(
    vol: &mut NativeOfflineVoxelVolume,
    ox: i32,
    oz: i32,
    w: i32,
    d: i32,
    ground_y: i32,
    height: &[i32],
    band_mats: &[i32],
    band_ends: &[i32],
) -> Result<PaintStats, String> {
    if w <= 0 || d <= 0 {
        return Err(format!("degenerate size {w}x{d}"));
    }
    if height.len() != (w * d) as usize {
        return Err(format!(
            "height len {} != {}x{}",
            height.len(),
            w,
            d
        ));
    }
    if band_mats.is_empty() || band_mats.len() != band_ends.len() {
        return Err("band_mats / band_ends mismatch".into());
    }
    let band_cycle = *band_ends.last().unwrap_or(&0);
    if band_cycle <= 0 {
        return Err("band_cycle <= 0".into());
    }

    let started = Instant::now();
    let dip_x: Vec<f32> = (0..w)
        .map(|x| 4.0 * ((ox + x) as f32 * 0.010 + 1.3).sin())
        .collect();
    let dip_z: Vec<f32> = (0..d)
        .map(|z| 3.0 * ((oz + z) as f32 * 0.013 - 0.7).sin())
        .collect();

    let mut columns = 0i32;
    for z in 0..d {
        for x in 0..w {
            let h = height[(z * w + x) as usize];
            if h <= 0 {
                continue;
            }
            columns += 1;
            paint_column(
                vol,
                ox,
                oz,
                w,
                d,
                ground_y,
                height,
                &dip_x,
                &dip_z,
                band_mats,
                band_ends,
                band_cycle,
                x,
                z,
                h,
            );
        }
    }
    Ok(PaintStats {
        columns,
        ms: started.elapsed().as_millis() as i64,
    })
}

fn paint_column(
    vol: &mut NativeOfflineVoxelVolume,
    ox: i32,
    oz: i32,
    w: i32,
    d: i32,
    ground_y: i32,
    height: &[i32],
    dip_x: &[f32],
    dip_z: &[f32],
    band_mats: &[i32],
    band_ends: &[i32],
    band_cycle: i32,
    x: i32,
    z: i32,
    h: i32,
) {
    let wx = ox + x;
    let wz = oz + z;
    let top = ground_y + h;
    let step = step_at(height, w, d, x, z);
    let mut soil = if step >= 3 { 0 } else { 2 };
    if soil > 0 && fbm2(wx as f32 * 0.045, wz as f32 * 0.045) + 0.004 * h as f32 > 0.78 {
        soil = 0;
    }
    if h >= 5 {
        vol.set_raw(Vector3i::new(wx, ground_y, wz), materials::DIRT as u16);
    }
    let rock_top = top - soil;
    let dip = (dip_x[x as usize] + dip_z[z as usize]).round() as i32;
    let mut y = ground_y + 1;
    while y <= rock_top {
        let e = y - ground_y + dip;
        let m = posmod(e, band_cycle);
        let bi = band_at(band_ends, m);
        let y_end = (rock_top + 1).min(y + (band_ends[bi] - m));
        vol.fill_box(
            Vector3i::new(wx, y, wz),
            Vector3i::new(wx + 1, y_end, wz + 1),
            band_mats[bi],
        );
        y = y_end;
    }
    if soil <= 0 {
        return;
    }
    let mut cap = materials::PARK;
    if fbm2(wx as f32 * 0.08 + 5.0, wz as f32 * 0.08 - 2.0) > 0.72 {
        cap = materials::DIRT;
    }
    for y2 in (top - soil + 1)..=top {
        vol.set_raw(Vector3i::new(wx, y2, wz), cap as u16);
    }
}

pub fn scatter_gems(
    vol: &mut NativeOfflineVoxelVolume,
    ox: i32,
    oz: i32,
    w: i32,
    d: i32,
    ground_y: i32,
    height: &[i32],
    road_mask: &[u8],
    seed: u64,
) -> Result<GemStats, String> {
    if w <= 0 || d <= 0 {
        return Err(format!("degenerate size {w}x{d}"));
    }
    let n = (w * d) as usize;
    if height.len() != n || road_mask.len() != n {
        return Err("height / road_mask size mismatch".into());
    }
    let started = Instant::now();
    let mut host_estimate = 0i32;
    for z in 0..d {
        let row = z * w;
        for x in 0..w {
            let i = (row + x) as usize;
            if road_mask[i] != 0 {
                continue;
            }
            let h = height[i];
            if h < GEM_SURFACE_MARGIN + 4 {
                continue;
            }
            host_estimate += (h - GEM_SURFACE_MARGIN * 2).max(0);
        }
    }
    let seeds = (host_estimate / GEM_VOXELS_PER_CLUSTER).clamp(0, GEM_CLUSTER_CAP);
    let mut positions = PackedVector3Array::new();
    let mut mats = PackedInt32Array::new();
    if seeds <= 0 {
        return Ok(GemStats {
            clusters: 0,
            voxels: 0,
            positions,
            mats,
            ms: started.elapsed().as_millis() as i64,
        });
    }

    let mut rng = Rng::new(seed);
    let mut placed = 0i32;
    let mut tries = 0i32;
    while placed < seeds && tries < seeds * 12 {
        tries += 1;
        let x = rng.gen_range_i32(2, w - 3);
        let z = rng.gen_range_i32(2, d - 3);
        let i = (z * w + x) as usize;
        if road_mask[i] != 0 {
            continue;
        }
        let h = height[i];
        let y_lo = ground_y + GEM_SURFACE_MARGIN;
        let y_hi = ground_y + h - GEM_SURFACE_MARGIN;
        if y_hi <= y_lo {
            continue;
        }
        let y = rng.gen_range_i32(y_lo, y_hi);
        let wx = ox + x;
        let wz = oz + z;
        let host = vol.raw(Vector3i::new(wx, y, wz)) as i32;
        if !is_gem_host(host) {
            continue;
        }
        let gem = random_gem(&mut rng);
        let cluster = 1 + rng.gen_mod(4);
        place_gem_cluster(vol, &mut rng, &mut positions, &mut mats, wx, y, wz, gem, cluster);
        placed += 1;
    }
    Ok(GemStats {
        clusters: placed,
        voxels: positions.len() as i32,
        positions,
        mats,
        ms: started.elapsed().as_millis() as i64,
    })
}

fn place_gem_cluster(
    vol: &mut NativeOfflineVoxelVolume,
    rng: &mut Rng,
    positions: &mut PackedVector3Array,
    mats: &mut PackedInt32Array,
    ox: i32,
    oy: i32,
    oz: i32,
    gem: i32,
    count: i32,
) {
    let mut cx = ox;
    let mut cy = oy;
    let mut cz = oz;
    for _ in 0..count {
        let here = vol.raw(Vector3i::new(cx, cy, cz)) as i32;
        if is_gem_host(here) {
            vol.set_raw(Vector3i::new(cx, cy, cz), gem as u16);
            positions.push(Vector3::new(cx as f32, cy as f32, cz as f32));
            mats.push(gem);
        }
        match rng.gen_mod(6) {
            0 => cx += 1,
            1 => cx -= 1,
            2 => cy += 1,
            3 => cy -= 1,
            4 => cz += 1,
            _ => cz -= 1,
        }
    }
}

fn is_gem_host(id: i32) -> bool {
    matches!(
        id,
        materials::STONE | materials::BRICK | materials::GRAVEL | materials::DIRT
    )
}

/// Weighted rarity roll — GDScript twin is `VoxelMaterial.random_gem`.
fn random_gem(rng: &mut Rng) -> i32 {
    debug_assert_eq!(
        GEM_WEIGHT_QUARTZ
            + GEM_WEIGHT_AMBER
            + GEM_WEIGHT_TOPAZ
            + GEM_WEIGHT_SAPPHIRE
            + GEM_WEIGHT_EMERALD
            + GEM_WEIGHT_DIAMOND,
        GEM_WEIGHT_TOTAL
    );
    let mut roll = rng.gen_range_i32(1, GEM_WEIGHT_TOTAL);
    if roll <= GEM_WEIGHT_QUARTZ {
        return materials::GEM_QUARTZ;
    }
    roll -= GEM_WEIGHT_QUARTZ;
    if roll <= GEM_WEIGHT_AMBER {
        return materials::GEM_AMBER;
    }
    roll -= GEM_WEIGHT_AMBER;
    if roll <= GEM_WEIGHT_TOPAZ {
        return materials::GEM_TOPAZ;
    }
    roll -= GEM_WEIGHT_TOPAZ;
    if roll <= GEM_WEIGHT_SAPPHIRE {
        return materials::GEM_SAPPHIRE;
    }
    roll -= GEM_WEIGHT_SAPPHIRE;
    if roll <= GEM_WEIGHT_EMERALD {
        return materials::GEM_EMERALD;
    }
    materials::GEM_DIAMOND
}

fn step_at(height: &[i32], w: i32, d: i32, x: i32, z: i32) -> i32 {
    let h = height_at(height, w, d, x, z);
    let mut s = 0;
    s = s.max((h - height_at(height, w, d, x - 1, z)).abs());
    s = s.max((h - height_at(height, w, d, x + 1, z)).abs());
    s = s.max((h - height_at(height, w, d, x, z - 1)).abs());
    s = s.max((h - height_at(height, w, d, x, z + 1)).abs());
    s
}

fn height_at(height: &[i32], w: i32, d: i32, x: i32, z: i32) -> i32 {
    if x < 0 || z < 0 || x >= w || z >= d {
        return 0;
    }
    height[(z * w + x) as usize]
}

fn band_at(band_ends: &[i32], offset_in_cycle: i32) -> usize {
    for (i, &end) in band_ends.iter().enumerate() {
        if offset_in_cycle < end {
            return i;
        }
    }
    band_ends.len() - 1
}

fn posmod(a: i32, b: i32) -> i32 {
    let r = a % b;
    if r < 0 {
        r + b
    } else {
        r
    }
}

fn fbm2(x: f32, z: f32) -> f32 {
    value_noise2(x, z) * 0.65 + value_noise2(x * 2.7 + 5.1, z * 2.7 - 3.3) * 0.35
}

fn value_noise2(x: f32, z: f32) -> f32 {
    let xi = x.floor() as i32;
    let zi = z.floor() as i32;
    let mut fx = x - xi as f32;
    let mut fz = z - zi as f32;
    fx = fx * fx * (3.0 - 2.0 * fx);
    fz = fz * fz * (3.0 - 2.0 * fz);
    let n00 = hash2(xi, zi);
    let n10 = hash2(xi + 1, zi);
    let n01 = hash2(xi, zi + 1);
    let n11 = hash2(xi + 1, zi + 1);
    lerp(lerp(n00, n10, fx), lerp(n01, n11, fx), fz)
}

fn hash2(x: i32, z: i32) -> f32 {
    let mut h = (x as i64 * 374761393 + z as i64 * 668265263) & 0x7fff_ffff;
    h = (h ^ (h >> 13)) * 1274126177 & 0x7fff_ffff;
    ((h ^ (h >> 16)) & 0xffff) as f32 / 65535.0
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}
