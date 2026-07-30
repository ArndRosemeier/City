//! Godot bindings for deep Mandelbrot rendering.

use godot::prelude::*;

use crate::mandelbrot;

type Dict = Dictionary<Variant, Variant>;

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct NativeMandelbrot {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for NativeMandelbrot {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl NativeMandelbrot {
    #[func]
    fn min_scale() -> f64 {
        mandelbrot::MIN_SCALE
    }

    #[func]
    fn direct_f64_scale_threshold() -> f64 {
        mandelbrot::DIRECT_F64_SCALE_THRESHOLD
    }

    #[func]
    fn recommended_iters(scale: f64) -> i32 {
        mandelbrot::recommended_iters(scale)
    }

    #[func]
    fn approx_f64(value: GString) -> f64 {
        match mandelbrot::approx_f64(&value.to_string()) {
            Ok(v) => v,
            Err(e) => {
                godot_error!("NativeMandelbrot.approx_f64: {e}");
                0.0
            }
        }
    }

    #[func]
    fn mul_decimal(a: GString, b: GString) -> GString {
        match mandelbrot::mul_decimal(&a.to_string(), &b.to_string()) {
            Ok(s) => GString::from(s.as_str()),
            Err(e) => {
                godot_error!("NativeMandelbrot.mul_decimal: {e}");
                GString::from("0")
            }
        }
    }

    /// High-precision complex plane point for fractal UV in [0,1]² (bottom-left origin).
    /// Returns `{ "re": String, "im": String }`.
    #[func]
    fn complex_at_uv(cx: GString, cy: GString, scale: GString, u: f64, v: f64) -> Dict {
        let mut out = Dict::new();
        match mandelbrot::complex_at_uv(&cx.to_string(), &cy.to_string(), &scale.to_string(), u, v)
        {
            Ok((re, im)) => {
                out.set("re", &GString::from(re.as_str()));
                out.set("im", &GString::from(im.as_str()));
            }
            Err(e) => {
                godot_error!("NativeMandelbrot.complex_at_uv: {e}");
                out.set("re", &cx);
                out.set("im", &cy);
            }
        }
        out
    }

    /// Bake an RGBA8 image (row-major, top-left / Godot Image order).
    /// Returns raw bytes only — callers already know width/height. Returning a
    /// Dictionary of multi‑MB PackedByteArray was arriving empty/black in GDScript.
    #[func]
    fn render_rgba8(
        cx: GString,
        cy: GString,
        scale: GString,
        width: i32,
        height: i32,
        max_iters: i32,
    ) -> PackedByteArray {
        match mandelbrot::render_rgba8(
            &cx.to_string(),
            &cy.to_string(),
            &scale.to_string(),
            width,
            height,
            max_iters,
        ) {
            Ok(bytes) => {
                // Index writes — as_mut_slice()+copy_from_slice left the Godot
                // buffer zeroed (correct size, all black) across the boundary.
                let mut packed = PackedByteArray::new();
                packed.resize(bytes.len());
                for (i, b) in bytes.iter().enumerate() {
                    packed[i] = *b;
                }
                packed
            }
            Err(e) => {
                godot_error!("NativeMandelbrot.render_rgba8: {e}");
                PackedByteArray::new()
            }
        }
    }
}
