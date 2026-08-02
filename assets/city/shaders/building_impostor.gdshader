shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

/// 0 = day, 1 = night — drives window emission.
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_n;
/// INSTANCE_CUSTOM is vertex-only — pass size.xyz + lit chance.
varying flat vec4 v_custom;

void vertex() {
	v_local = VERTEX;
	v_n = NORMAL;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 wall = COLOR.rgb;
	vec3 an = abs(normalize(v_n));
	/// Soft face weights. A hard step() on an interpolated normal flips the whole window
	/// grid the instant the camera crosses a face boundary on cylinders and spheres.
	float roof_w = smoothstep(-0.05, 0.05, an.y - max(an.x, an.z));
	float side_w = smoothstep(-0.05, 0.05, an.x - an.z);

	float sx = max(v_custom.x, 0.5);
	float sy = max(v_custom.y, 0.5);
	float sz = max(v_custom.z, 0.5);
	float lit_chance = clamp(v_custom.a, 0.0, 1.0);

	vec2 uv_m = mix(
		vec2((v_local.x + 0.5) * sx, (v_local.y + 0.5) * sy),
		vec2((v_local.z + 0.5) * sz, (v_local.y + 0.5) * sy),
		side_w
	);

	float floor_h = 3.0;
	float win_w = 2.4;
	const float WIN_U0 = 0.18;
	const float WIN_U1 = 0.82;
	const float WIN_V0 = 0.26;
	const float WIN_V1 = 0.88;

	vec2 grid = vec2(uv_m.x / win_w, uv_m.y / floor_h);
	/// Edge softness tracks the on-screen size of one window cell, so the pane borders
	/// stay a fixed pixel width instead of aliasing into crawling patterns when moving.
	vec2 aa = max(fwidth(grid), vec2(0.0005));
	vec2 f = fract(grid);
	float wx = (
		smoothstep(WIN_U0 - aa.x, WIN_U0 + aa.x, f.x)
		* (1.0 - smoothstep(WIN_U1 - aa.x, WIN_U1 + aa.x, f.x))
	);
	float wy = (
		smoothstep(WIN_V0 - aa.y, WIN_V0 + aa.y, f.y)
		* (1.0 - smoothstep(WIN_V1 - aa.y, WIN_V1 + aa.y, f.y))
	);
	// Skip ground retail band (first ~3.5 m) for cleaner podium read.
	float band_aa = max(fwidth(uv_m.y), 0.01);
	float facade = smoothstep(3.4 - band_aa, 3.4 + band_aa, uv_m.y) * (1.0 - roof_w);

	float window = wx * wy * facade;
	/// What the grid averages out to once a cell is smaller than a pixel.
	float window_avg = (WIN_U1 - WIN_U0) * (WIN_V1 - WIN_V0) * facade;
	/// Ramps in as one window cell shrinks from ~3 px to ~1 px on screen. Below a pixel the
	/// binary grid is pure noise that crawls with the camera, so fade it into its own
	/// average and let the facade just glow; above it, keep the real windows.
	float lod = smoothstep(0.35, 1.0, max(aa.x, aa.y));

	float hash = fract(sin(dot(vec2(floor(grid.x), floor(grid.y)), vec2(12.9898, 78.233))) * 43758.5453);
	float glass_mix = mix(window, window_avg, lod) * 0.88;
	vec3 glass_day = vec3(0.32, 0.42, 0.52);
	vec3 facade_col = mix(wall, glass_day, glass_mix);
	ALBEDO = mix(facade_col, wall * 0.58, roof_w);
	ROUGHNESS = mix(mix(0.82, 0.12, glass_mix), 0.92, roof_w);
	METALLIC = glass_mix * 0.15 * (1.0 - roof_w);

	float night = smoothstep(0.2, 0.7, night_factor);
	float lit = mix(window * step(hash, lit_chance), window_avg * lit_chance, lod);
	EMISSION = vec3(1.0, 0.82, 0.42) * (1.2 + 2.2 * night) * lit * step(0.01, night);
}
