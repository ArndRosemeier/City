//! High-precision Mandelbrot renderer for panel zooms past fp64.
//!
//! Panels always display a baked RGBA8 texture (1000×1000). Shallow windows use a
//! direct f64 escape-time loop; deeper windows use a decimal bigfloat reference
//! orbit (dashu `DBig`) plus double-double perturbation.

use dashu_float::DBig;
use std::str::FromStr;

/// Decimal digits kept for centres / scales / reference orbits.
pub const HP_DIGITS: usize = 96;
/// Above this half-extent, direct f64 escape-time is enough. fp64 ulp near |c|≈1
/// is ~1e-16, so windows down to ~1e-13 still separate neighbouring pixels.
pub const DIRECT_F64_SCALE_THRESHOLD: f64 = 1e-13;
/// Soft floor — past this, even DD perturbation gets glitchy without series approx.
pub const MIN_SCALE: f64 = 1e-40;
pub const MAX_TEX_DIM: i32 = 2048;
/// Shared interior colour (the Mandelbrot "black spots").
const INTERIOR_RGBA: [u8; 4] = [5, 5, 13, 255];

#[derive(Clone, Copy, Default)]
struct Dd {
    hi: f64,
    lo: f64,
}

impl Dd {
    #[inline]
    fn from_f64(x: f64) -> Self {
        Self { hi: x, lo: 0.0 }
    }

    #[inline]
    fn to_f64(self) -> f64 {
        self.hi + self.lo
    }

    #[inline]
    fn add(self, other: Self) -> Self {
        let s = self.hi + other.hi;
        let v = s - self.hi;
        let t = (self.hi - (s - v)) + (other.hi - v) + self.lo + other.lo;
        let hi = s + t;
        Self { hi, lo: t - (hi - s) }
    }

    #[inline]
    fn sub(self, other: Self) -> Self {
        self.add(Self {
            hi: -other.hi,
            lo: -other.lo,
        })
    }

    #[inline]
    fn mul(self, other: Self) -> Self {
        let p = self.hi * other.hi;
        let err = f64::mul_add(self.hi, other.hi, -p)
            + self.hi * other.lo
            + self.lo * other.hi
            + self.lo * other.lo;
        let hi = p + err;
        Self { hi, lo: err - (hi - p) }
    }

    #[inline]
    fn mul_f64(self, k: f64) -> Self {
        self.mul(Self::from_f64(k))
    }
}

#[derive(Clone, Copy)]
struct CDd {
    re: Dd,
    im: Dd,
}

impl CDd {
    #[inline]
    fn zero() -> Self {
        Self {
            re: Dd::from_f64(0.0),
            im: Dd::from_f64(0.0),
        }
    }

    #[inline]
    fn from_f64s(re: f64, im: f64) -> Self {
        Self {
            re: Dd::from_f64(re),
            im: Dd::from_f64(im),
        }
    }

    #[inline]
    fn add(self, o: Self) -> Self {
        Self {
            re: self.re.add(o.re),
            im: self.im.add(o.im),
        }
    }

    #[inline]
    fn mul(self, o: Self) -> Self {
        Self {
            re: self.re.mul(o.re).sub(self.im.mul(o.im)),
            im: self.re.mul(o.im).add(self.im.mul(o.re)),
        }
    }

    #[inline]
    fn scale(self, k: f64) -> Self {
        Self {
            re: self.re.mul_f64(k),
            im: self.im.mul_f64(k),
        }
    }

    #[inline]
    fn abs2(self) -> f64 {
        let r = self.re.to_f64();
        let i = self.im.to_f64();
        r * r + i * i
    }
}

fn parse_hp(s: &str) -> Result<DBig, String> {
    let t = s.trim();
    if t.is_empty() {
        return Err("empty numeric string".into());
    }
    DBig::from_str(t)
        .map_err(|e| format!("parse '{t}': {e}"))
        .map(|v| v.with_precision(HP_DIGITS).value())
}

fn hp_to_string(v: &DBig) -> String {
    format!("{}", v.clone().with_precision(HP_DIGITS).value())
}

fn hp_to_f64(v: &DBig) -> f64 {
    hp_to_string(v).parse::<f64>().unwrap_or(0.0)
}

fn f64_to_hp(x: f64) -> DBig {
    if !x.is_finite() {
        return DBig::from(0).with_precision(HP_DIGITS).value();
    }
    parse_hp(&format!("{x:.17e}"))
        .unwrap_or_else(|_| DBig::from(0).with_precision(HP_DIGITS).value())
}

fn hp_to_dd(v: &DBig) -> Dd {
    let hi = hp_to_f64(v);
    let hi_hp = f64_to_hp(hi);
    let lo = hp_to_f64(&(v.clone() - hi_hp));
    Dd { hi, lo }
}

fn palette(t: f32) -> [u8; 4] {
    let t = t.clamp(0.0, 0.999);
    let (r, g, b) = if t < 0.5 {
        let u = t * 2.0;
        (
            0.05 + (0.20 - 0.05) * u,
            0.10 + (0.75 - 0.10) * u,
            0.35 + (0.85 - 0.35) * u,
        )
    } else {
        let u = (t - 0.5) * 2.0;
        (
            0.20 + (0.95 - 0.20) * u,
            0.75 + (0.85 - 0.75) * u,
            0.85 + (0.35 - 0.85) * u,
        )
    };
    [
        (r.clamp(0.0, 1.0) * 255.0) as u8,
        (g.clamp(0.0, 1.0) * 255.0) as u8,
        (b.clamp(0.0, 1.0) * 255.0) as u8,
        255,
    ]
}

/// Interior sentinel for `render_smooth_mu_u16` (never a valid encoded μ).
pub const MU_INTERIOR_U16: u16 = 0xFFFF;
/// Fixed-point scale: packed = round(mu * MU_U16_SCALE), max 0xFFFE.
pub const MU_U16_SCALE: f64 = 64.0;

/// Smooth escape μ (fractional iterate). Interior returns None.
fn smooth_mu(n: usize, max_iters: usize, zr: f64, zi: f64) -> Option<f64> {
    if n >= max_iters {
        return None;
    }
    let zn2 = zr * zr + zi * zi;
    let mut mu = n as f64;
    if zn2 > 1.0 {
        let log_zn = zn2.ln() * 0.5;
        let nu = (log_zn / std::f64::consts::LN_2).ln() / std::f64::consts::LN_2;
        if nu.is_finite() {
            mu = (n as f64 + 1.0 - nu).max(0.0);
        }
    }
    Some(mu)
}

fn encode_smooth_mu_u16(n: usize, max_iters: usize, zr: f64, zi: f64) -> u16 {
    match smooth_mu(n, max_iters, zr, zi) {
        None => MU_INTERIOR_U16,
        Some(mu) => (mu * MU_U16_SCALE).round().clamp(0.0, 65534.0) as u16,
    }
}

/// Smooth escape colouring — same mapping for direct and perturbation paths so
/// zooms do not jump when the solver switches.
fn color_escape(n: usize, max_iters: usize, zr: f64, zi: f64) -> [u8; 4] {
    let Some(mu) = smooth_mu(n, max_iters, zr, zi) else {
        return INTERIOR_RGBA;
    };
    // Normalise against a stable exterior band so raising max_iters with depth
    // does not re-stretch the whole palette.
    let band = (max_iters as f64).min(512.0).max(64.0);
    palette((mu / band) as f32)
}

pub fn recommended_iters(scale: f64) -> i32 {
    if !scale.is_finite() || scale <= 0.0 {
        return 256;
    }
    let depth = (-scale.log10()).max(0.0);
    // Gentle ramp — large jumps in max_iters recolour the set even with smooth μ.
    let iters = 256.0 + depth * 24.0;
    iters.clamp(256.0, 4096.0) as i32
}

pub fn complex_at_uv(
    cx: &str,
    cy: &str,
    scale: &str,
    u: f64,
    v: f64,
) -> Result<(String, String), String> {
    let cx_hp = parse_hp(cx)?;
    let cy_hp = parse_hp(cy)?;
    let scale_hp = parse_hp(scale)?;
    let du_hp = f64_to_hp((u - 0.5) * 2.0);
    let dv_hp = f64_to_hp((v - 0.5) * 2.0);
    let re = (cx_hp + scale_hp.clone() * du_hp)
        .with_precision(HP_DIGITS)
        .value();
    let im = (cy_hp + scale_hp * dv_hp)
        .with_precision(HP_DIGITS)
        .value();
    Ok((hp_to_string(&re), hp_to_string(&im)))
}

pub fn mul_decimal(a: &str, b: &str) -> Result<String, String> {
    let ah = parse_hp(a)?;
    let bh = parse_hp(b)?;
    Ok(hp_to_string(&(ah * bh).with_precision(HP_DIGITS).value()))
}

pub fn approx_f64(s: &str) -> Result<f64, String> {
    Ok(hp_to_f64(&parse_hp(s)?))
}

/// Shared view parse for RGBA / iters bakers.
fn prepare_view(
    cx: &str,
    cy: &str,
    scale: &str,
    width: i32,
    height: i32,
    max_iters: i32,
) -> Result<(DBig, DBig, f64, f64, f64, usize, usize, usize), String> {
    let w = width.clamp(16, MAX_TEX_DIM) as usize;
    let h = height.clamp(16, MAX_TEX_DIM) as usize;
    let max_iters = max_iters.clamp(16, 8000) as usize;
    let cx_hp = parse_hp(cx)?;
    let cy_hp = parse_hp(cy)?;
    let scale_hp = parse_hp(scale)?;
    let scale_f = hp_to_f64(&scale_hp).abs().max(MIN_SCALE);
    let cx_f = hp_to_f64(&cx_hp);
    let cy_f = hp_to_f64(&cy_hp);
    Ok((cx_hp, cy_hp, cx_f, cy_f, scale_f, w, h, max_iters))
}

/// RGBA8 packed image, **top-left origin** (Godot `Image` order).
pub fn render_rgba8(
    cx: &str,
    cy: &str,
    scale: &str,
    width: i32,
    height: i32,
    max_iters: i32,
) -> Result<Vec<u8>, String> {
    let (cx_hp, cy_hp, cx_f, cy_f, scale_f, w, h, max_iters) =
        prepare_view(cx, cy, scale, width, height, max_iters)?;
    if scale_f > DIRECT_F64_SCALE_THRESHOLD {
        return Ok(render_direct_f64(cx_f, cy_f, scale_f, w, h, max_iters));
    }
    render_perturbation(&cx_hp, &cy_hp, scale_f, w, h, max_iters)
}

/// Row-major top-left. Per pixel: u16 escape `n` (interior = `max_iters`).
pub fn render_iters_u16(
    cx: &str,
    cy: &str,
    scale: &str,
    width: i32,
    height: i32,
    max_iters: i32,
) -> Result<Vec<u16>, String> {
    let (cx_hp, cy_hp, cx_f, cy_f, scale_f, w, h, max_iters) =
        prepare_view(cx, cy, scale, width, height, max_iters)?;
    if scale_f > DIRECT_F64_SCALE_THRESHOLD {
        return Ok(render_iters_direct_f64(cx_f, cy_f, scale_f, w, h, max_iters));
    }
    render_iters_perturbation(&cx_hp, &cy_hp, scale_f, w, h, max_iters)
}

/// Row-major top-left. Per pixel: LE-friendly u16 smooth μ × [`MU_U16_SCALE`].
/// Interior cells are [`MU_INTERIOR_U16`].
pub fn render_smooth_mu_u16(
    cx: &str,
    cy: &str,
    scale: &str,
    width: i32,
    height: i32,
    max_iters: i32,
) -> Result<Vec<u16>, String> {
    let (cx_hp, cy_hp, cx_f, cy_f, scale_f, w, h, max_iters) =
        prepare_view(cx, cy, scale, width, height, max_iters)?;
    if scale_f > DIRECT_F64_SCALE_THRESHOLD {
        return Ok(render_mu_direct_f64(cx_f, cy_f, scale_f, w, h, max_iters));
    }
    render_mu_perturbation(&cx_hp, &cy_hp, scale_f, w, h, max_iters)
}

fn render_direct_f64(
    cx: f64,
    cy: f64,
    scale: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Vec<u8> {
    let mut out = vec![0u8; w * h * 4];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w * 4).enumerate() {
            let y0 = chunk_idx * chunk;
            scope.spawn(move || {
                let rows = row_slice.len() / (w * 4);
                for ly in 0..rows {
                    let y = y0 + ly;
                    // Top-left origin for Godot Image: y=0 is v=1 (top of set).
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let cre = cx + (u - 0.5) * 2.0 * scale;
                        let cim = cy + (v - 0.5) * 2.0 * scale;
                        let (n, zr, zi) = escape_f64(cre, cim, max_iters);
                        let rgba = color_escape(n, max_iters, zr, zi);
                        let o = (ly * w + x) * 4;
                        row_slice[o..o + 4].copy_from_slice(&rgba);
                    }
                }
            });
        }
    });
    out
}

fn render_iters_direct_f64(
    cx: f64,
    cy: f64,
    scale: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Vec<u16> {
    let mut out = vec![0u16; w * h];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w).enumerate() {
            let y0 = chunk_idx * chunk;
            scope.spawn(move || {
                let rows = row_slice.len() / w;
                for ly in 0..rows {
                    let y = y0 + ly;
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let cre = cx + (u - 0.5) * 2.0 * scale;
                        let cim = cy + (v - 0.5) * 2.0 * scale;
                        let (n, _zr, _zi) = escape_f64(cre, cim, max_iters);
                        row_slice[ly * w + x] = n as u16;
                    }
                }
            });
        }
    });
    out
}

fn render_mu_direct_f64(
    cx: f64,
    cy: f64,
    scale: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Vec<u16> {
    let mut out = vec![0u16; w * h];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w).enumerate() {
            let y0 = chunk_idx * chunk;
            scope.spawn(move || {
                let rows = row_slice.len() / w;
                for ly in 0..rows {
                    let y = y0 + ly;
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let cre = cx + (u - 0.5) * 2.0 * scale;
                        let cim = cy + (v - 0.5) * 2.0 * scale;
                        let (n, zr, zi) = escape_f64(cre, cim, max_iters);
                        row_slice[ly * w + x] = encode_smooth_mu_u16(n, max_iters, zr, zi);
                    }
                }
            });
        }
    });
    out
}

fn escape_f64(cre: f64, cim: f64, max_iters: usize) -> (usize, f64, f64) {
    let mut zr = 0.0;
    let mut zi = 0.0;
    for n in 0..max_iters {
        let x2 = zr * zr;
        let y2 = zi * zi;
        if x2 + y2 > 4.0 {
            return (n, zr, zi);
        }
        zi = 2.0 * zr * zi + cim;
        zr = x2 - y2 + cre;
    }
    (max_iters, zr, zi)
}

fn render_perturbation(
    cx_hp: &DBig,
    cy_hp: &DBig,
    scale_f: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Result<Vec<u8>, String> {
    let mut z_re = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut z_im = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut ref_z: Vec<CDd> = Vec::with_capacity(max_iters);
    let mut ref_escaped = max_iters;
    for n in 0..max_iters {
        let zr = hp_to_dd(&z_re);
        let zi = hp_to_dd(&z_im);
        ref_z.push(CDd { re: zr, im: zi });
        let r = zr.to_f64();
        let i = zi.to_f64();
        if r * r + i * i > 4.0 {
            ref_escaped = n;
            break;
        }
        let zr2 = (z_re.clone() * z_re.clone()).with_precision(HP_DIGITS).value();
        let zi2 = (z_im.clone() * z_im.clone()).with_precision(HP_DIGITS).value();
        let two_zr_zi = (DBig::from(2) * z_re.clone() * z_im.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_re = (zr2 - zi2 + cx_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_im = (two_zr_zi + cy_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
    }

    let mut out = vec![0u8; w * h * 4];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w * 4).enumerate() {
            let y0 = chunk_idx * chunk;
            let ref_z = &ref_z;
            scope.spawn(move || {
                let rows = row_slice.len() / (w * 4);
                for ly in 0..rows {
                    let y = y0 + ly;
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let du = (u - 0.5) * 2.0 * scale_f;
                        let dv = (v - 0.5) * 2.0 * scale_f;
                        let c_delta = CDd::from_f64s(du, dv);
                        let (n, zr, zi) = perturb_escape(ref_z, ref_escaped, c_delta, max_iters);
                        let rgba = color_escape(n, max_iters, zr, zi);
                        let o = (ly * w + x) * 4;
                        row_slice[o..o + 4].copy_from_slice(&rgba);
                    }
                }
            });
        }
    });
    Ok(out)
}

fn render_iters_perturbation(
    cx_hp: &DBig,
    cy_hp: &DBig,
    scale_f: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Result<Vec<u16>, String> {
    let mut z_re = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut z_im = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut ref_z: Vec<CDd> = Vec::with_capacity(max_iters);
    let mut ref_escaped = max_iters;
    for n in 0..max_iters {
        let zr = hp_to_dd(&z_re);
        let zi = hp_to_dd(&z_im);
        ref_z.push(CDd { re: zr, im: zi });
        let r = zr.to_f64();
        let i = zi.to_f64();
        if r * r + i * i > 4.0 {
            ref_escaped = n;
            break;
        }
        let zr2 = (z_re.clone() * z_re.clone()).with_precision(HP_DIGITS).value();
        let zi2 = (z_im.clone() * z_im.clone()).with_precision(HP_DIGITS).value();
        let two_zr_zi = (DBig::from(2) * z_re.clone() * z_im.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_re = (zr2 - zi2 + cx_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_im = (two_zr_zi + cy_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
    }

    let mut out = vec![0u16; w * h];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w).enumerate() {
            let y0 = chunk_idx * chunk;
            let ref_z = &ref_z;
            scope.spawn(move || {
                let rows = row_slice.len() / w;
                for ly in 0..rows {
                    let y = y0 + ly;
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let du = (u - 0.5) * 2.0 * scale_f;
                        let dv = (v - 0.5) * 2.0 * scale_f;
                        let c_delta = CDd::from_f64s(du, dv);
                        let (n, _zr, _zi) = perturb_escape(ref_z, ref_escaped, c_delta, max_iters);
                        row_slice[ly * w + x] = n as u16;
                    }
                }
            });
        }
    });
    Ok(out)
}

fn render_mu_perturbation(
    cx_hp: &DBig,
    cy_hp: &DBig,
    scale_f: f64,
    w: usize,
    h: usize,
    max_iters: usize,
) -> Result<Vec<u16>, String> {
    let mut z_re = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut z_im = DBig::from(0).with_precision(HP_DIGITS).value();
    let mut ref_z: Vec<CDd> = Vec::with_capacity(max_iters);
    let mut ref_escaped = max_iters;
    for n in 0..max_iters {
        let zr = hp_to_dd(&z_re);
        let zi = hp_to_dd(&z_im);
        ref_z.push(CDd { re: zr, im: zi });
        let r = zr.to_f64();
        let i = zi.to_f64();
        if r * r + i * i > 4.0 {
            ref_escaped = n;
            break;
        }
        let zr2 = (z_re.clone() * z_re.clone()).with_precision(HP_DIGITS).value();
        let zi2 = (z_im.clone() * z_im.clone()).with_precision(HP_DIGITS).value();
        let two_zr_zi = (DBig::from(2) * z_re.clone() * z_im.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_re = (zr2 - zi2 + cx_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
        z_im = (two_zr_zi + cy_hp.clone())
            .with_precision(HP_DIGITS)
            .value();
    }

    let mut out = vec![0u16; w * h];
    let inv_w = 1.0 / w as f64;
    let inv_h = 1.0 / h as f64;
    let chunk = ((h + 3) / 4).max(1);
    std::thread::scope(|scope| {
        for (chunk_idx, row_slice) in out.chunks_mut(chunk * w).enumerate() {
            let y0 = chunk_idx * chunk;
            let ref_z = &ref_z;
            scope.spawn(move || {
                let rows = row_slice.len() / w;
                for ly in 0..rows {
                    let y = y0 + ly;
                    let v = 1.0 - (y as f64 + 0.5) * inv_h;
                    for x in 0..w {
                        let u = (x as f64 + 0.5) * inv_w;
                        let du = (u - 0.5) * 2.0 * scale_f;
                        let dv = (v - 0.5) * 2.0 * scale_f;
                        let c_delta = CDd::from_f64s(du, dv);
                        let (n, zr, zi) = perturb_escape(ref_z, ref_escaped, c_delta, max_iters);
                        row_slice[ly * w + x] = encode_smooth_mu_u16(n, max_iters, zr, zi);
                    }
                }
            });
        }
    });
    Ok(out)
}

fn perturb_escape(
    ref_z: &[CDd],
    ref_escaped: usize,
    c_delta: CDd,
    max_iters: usize,
) -> (usize, f64, f64) {
    let mut z_delta = CDd::zero();
    let limit = ref_escaped.min(ref_z.len()).min(max_iters);
    let mut last = CDd::zero();
    for n in 0..limit {
        let zn = ref_z[n];
        let z_full = zn.add(z_delta);
        last = z_full;
        if z_full.abs2() > 4.0 {
            return (n, z_full.re.to_f64(), z_full.im.to_f64());
        }
        // δ ← 2·Z·δ + δ² + δc
        let two_z_d = zn.mul(z_delta).scale(2.0);
        let d2 = z_delta.mul(z_delta);
        z_delta = two_z_d.add(d2).add(c_delta);
        if !z_delta.re.hi.is_finite() || !z_delta.im.hi.is_finite() || z_delta.abs2() > 1.0e200 {
            // Glitch: treat as exterior at this iterate (not interior black).
            return (n, last.re.to_f64(), last.im.to_f64());
        }
    }
    // Tracked with the reference through its whole orbit without escaping → interior.
    // (Do not inherit ref_escaped: that painted the set body with exterior colours.)
    (
        max_iters,
        last.re.to_f64(),
        last.im.to_f64(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn complex_at_uv_keeps_sub_ulp_offsets() {
        let (a, _) = complex_at_uv("-1.999999999999999", "0", "1e-20", 0.0, 0.5).unwrap();
        let (b, _) = complex_at_uv("-1.999999999999999", "0", "1e-20", 1.0, 0.5).unwrap();
        assert_ne!(a, b, "HP edges must differ past fp64 ulp");
    }

    #[test]
    fn render_produces_non_flat_image() {
        let img = render_rgba8("-0.5", "0", "1.5", 64, 64, 128).unwrap();
        assert_eq!(img.len(), 64 * 64 * 4);
        let first = &img[0..4];
        let mut varied = false;
        for px in img.chunks_exact(4) {
            if px != first {
                varied = true;
                break;
            }
        }
        assert!(varied, "Mandelbrot render should not be a flat colour");
    }

    #[test]
    fn medium_deep_direct_has_variance() {
        // Past the live fp32 shader threshold, still in the direct-f64 bake band.
        let img = render_rgba8(
            "-0.743643887037151",
            "0.131825904205312",
            "1e-6",
            64,
            64,
            500,
        )
        .unwrap();
        assert_eq!(img.len(), 64 * 64 * 4);
        let r0 = img[0];
        let g0 = img[1];
        let b0 = img[2];
        let mut varied = false;
        let mut max_c = 0u8;
        for px in img.chunks_exact(4) {
            max_c = max_c.max(px[0]).max(px[1]).max(px[2]);
            if px[0] != r0 || px[1] != g0 || px[2] != b0 {
                varied = true;
            }
        }
        assert!(varied, "1e-6 seahorse render must not be flat");
        assert!(max_c > 30, "render max channel {max_c} looks black");
    }

    #[test]
    fn render_1000_square() {
        let img = render_rgba8("-0.5", "0", "1.5", 1000, 1000, 128).unwrap();
        assert_eq!(img.len(), 1000 * 1000 * 4);
    }
}
