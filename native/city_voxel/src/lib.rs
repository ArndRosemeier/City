use godot::prelude::*;
use std::collections::HashMap;

struct CityVoxelExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CityVoxelExtension {}

const BLOCK: i32 = 16;
const BLOCK_VOXELS: usize = (BLOCK * BLOCK * BLOCK) as usize;

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct NativeOfflineVoxelVolume {
    base: Base<RefCounted>,
    /// Sparse 16³ TYPE channel (8-bit material ids), Y-major layout matching VoxelBuffer.
    blocks: HashMap<(i32, i32, i32), Vec<u8>>,
}

#[godot_api]
impl IRefCounted for NativeOfflineVoxelVolume {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            blocks: HashMap::new(),
        }
    }
}

#[godot_api]
impl NativeOfflineVoxelVolume {
    #[func]
    fn clear(&mut self) {
        self.blocks.clear();
    }

    #[func]
    fn block_count(&self) -> i32 {
        self.blocks.len() as i32
    }

    #[func]
    fn set_vox(&mut self, pos: Vector3i, material_id: i32) {
        let mat = material_id.clamp(0, 255) as u8;
        let bp = block_pos(pos);
        let data = self.ensure_block(bp);
        let lp = Vector3i::new(pos.x - bp.0 * BLOCK, pos.y - bp.1 * BLOCK, pos.z - bp.2 * BLOCK);
        data[index(lp)] = mat;
    }

    #[func]
    fn get_vox(&self, pos: Vector3i) -> i32 {
        let bp = block_pos(pos);
        match self.blocks.get(&bp) {
            Some(data) => {
                let lp =
                    Vector3i::new(pos.x - bp.0 * BLOCK, pos.y - bp.1 * BLOCK, pos.z - bp.2 * BLOCK);
                data[index(lp)] as i32
            }
            None => 0,
        }
    }

    #[func]
    fn fill_box(&mut self, min_v: Vector3i, max_v: Vector3i, material_id: i32) {
        if min_v.x >= max_v.x || min_v.y >= max_v.y || min_v.z >= max_v.z {
            return;
        }
        let mat = material_id.clamp(0, 255) as u8;
        let bx0 = div_floor(min_v.x, BLOCK);
        let by0 = div_floor(min_v.y, BLOCK);
        let bz0 = div_floor(min_v.z, BLOCK);
        let bx1 = div_floor(max_v.x - 1, BLOCK);
        let by1 = div_floor(max_v.y - 1, BLOCK);
        let bz1 = div_floor(max_v.z - 1, BLOCK);
        for bz in bz0..=bz1 {
            for by in by0..=by1 {
                for bx in bx0..=bx1 {
                    let bp = (bx, by, bz);
                    let bmin = Vector3i::new(bx * BLOCK, by * BLOCK, bz * BLOCK);
                    let bmax = Vector3i::new(bmin.x + BLOCK, bmin.y + BLOCK, bmin.z + BLOCK);
                    let x0 = min_v.x.max(bmin.x);
                    let y0 = min_v.y.max(bmin.y);
                    let z0 = min_v.z.max(bmin.z);
                    let x1 = max_v.x.min(bmax.x);
                    let y1 = max_v.y.min(bmax.y);
                    let z1 = max_v.z.min(bmax.z);
                    if x0 >= x1 || y0 >= y1 || z0 >= z1 {
                        continue;
                    }
                    if x0 == bmin.x
                        && y0 == bmin.y
                        && z0 == bmin.z
                        && x1 == bmax.x
                        && y1 == bmax.y
                        && z1 == bmax.z
                    {
                        let full = self.ensure_block(bp);
                        full.fill(mat);
                        continue;
                    }
                    let data = self.ensure_block(bp);
                    for z in z0..z1 {
                        for y in y0..y1 {
                            for x in x0..x1 {
                                let lp = Vector3i::new(x - bmin.x, y - bmin.y, z - bmin.z);
                                data[index(lp)] = mat;
                            }
                        }
                    }
                }
            }
        }
    }

    #[func]
    fn export_blocks_u16(&self) -> Dictionary<Variant, Variant> {
        let mut out = Dictionary::new();
        for (&bp, src) in &self.blocks {
            let key = Vector3i::new(bp.0, bp.1, bp.2);
            let n = src.len().min(BLOCK_VOXELS);
            let mut uniform = n > 0;
            let v0 = if n > 0 { src[0] } else { 0 };
            if uniform {
                for i in 1..n {
                    if src[i] != v0 {
                        uniform = false;
                        break;
                    }
                }
            }
            if uniform {
                let mut tiny = PackedByteArray::new();
                tiny.resize(2);
                tiny[0] = v0;
                tiny[1] = 0;
                out.set(key, &tiny);
            } else {
                let mut dst = PackedByteArray::new();
                dst.resize(BLOCK_VOXELS * 2);
                for i in 0..n {
                    dst[i * 2] = src[i];
                }
                out.set(key, &dst);
            }
        }
        out
    }
}

impl NativeOfflineVoxelVolume {
    fn ensure_block(&mut self, bp: (i32, i32, i32)) -> &mut Vec<u8> {
        self.blocks.entry(bp).or_insert_with(|| vec![0u8; BLOCK_VOXELS])
    }
}

fn block_pos(pos: Vector3i) -> (i32, i32, i32) {
    (
        div_floor(pos.x, BLOCK),
        div_floor(pos.y, BLOCK),
        div_floor(pos.z, BLOCK),
    )
}

fn index(lp: Vector3i) -> usize {
    (lp.y + lp.x * BLOCK + lp.z * BLOCK * BLOCK) as usize
}

fn div_floor(a: i32, b: i32) -> i32 {
    let q = a / b;
    let r = a % b;
    if r != 0 && a < 0 {
        q - 1
    } else {
        q
    }
}
