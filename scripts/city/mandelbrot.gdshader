shader_type spatial;
render_mode unshaded, cull_disabled;

// Shallow Mandelbrot path (fp32). Deep zooms bake via NativeMandelbrot instead.
// Complex-plane window (centre + half-extent). Texture UV (0,0)=bottom-left of the set.
uniform vec2 view_center = vec2(-0.5, 0.0);
uniform float view_scale = 1.5;
uniform int max_iters = 96;

vec3 palette(float t) {
	if (t >= 1.0) {
		return vec3(0.02, 0.02, 0.05);
	}
	if (t < 0.5) {
		return mix(vec3(0.05, 0.10, 0.35), vec3(0.20, 0.75, 0.85), t * 2.0);
	}
	return mix(vec3(0.20, 0.75, 0.85), vec3(0.95, 0.85, 0.35), (t - 0.5) * 2.0);
}

void fragment() {
	// QuadMesh UV: V is top-down; flip so V=0 is the bottom of the fractal view.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 c = view_center + (uv - vec2(0.5)) * (2.0 * view_scale);
	vec2 z = vec2(0.0);
	int n = 0;
	while (n < max_iters) {
		float x2 = z.x * z.x;
		float y2 = z.y * z.y;
		if (x2 + y2 > 4.0) {
			break;
		}
		z = vec2(x2 - y2 + c.x, 2.0 * z.x * z.y + c.y);
		n += 1;
	}
	float t = float(n) / float(max_iters);
	ALBEDO = palette(t);
}
