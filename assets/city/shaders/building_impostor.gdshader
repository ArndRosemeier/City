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
	vec3 an = abs(v_n);
	float roof_w = step(an.x, an.y) * step(an.z, an.y);

	float sx = max(v_custom.x, 0.5);
	float sy = max(v_custom.y, 0.5);
	float sz = max(v_custom.z, 0.5);
	float lit_chance = clamp(v_custom.a, 0.0, 1.0);

	vec2 uv_m = mix(
		vec2((v_local.x + 0.5) * sx, (v_local.y + 0.5) * sy),
		vec2((v_local.z + 0.5) * sz, (v_local.y + 0.5) * sy),
		step(an.z, an.x)
	);

	float floor_h = 3.0;
	float win_w = 2.4;
	float cell_x = floor(uv_m.x / win_w);
	float cell_y = floor(uv_m.y / floor_h);
	float fx = fract(uv_m.x / win_w);
	float fy = fract(uv_m.y / floor_h);
	float window = step(0.18, fx) * step(fx, 0.82) * step(0.26, fy) * step(fy, 0.88);
	// Skip ground retail band (first ~3.5 m) for cleaner podium read.
	window *= step(3.4, uv_m.y) * (1.0 - roof_w);

	float hash = fract(sin(dot(vec2(cell_x, cell_y), vec2(12.9898, 78.233))) * 43758.5453);
	float glass_mix = window * 0.88;
	vec3 glass_day = vec3(0.32, 0.42, 0.52);
	vec3 facade = mix(wall, glass_day, glass_mix);
	ALBEDO = mix(facade, wall * 0.58, roof_w);
	ROUGHNESS = mix(mix(0.82, 0.12, glass_mix), 0.92, roof_w);
	METALLIC = glass_mix * 0.15 * (1.0 - roof_w);

	float night = smoothstep(0.2, 0.7, night_factor);
	float lit = window * step(hash, lit_chance) * step(0.01, night);
	EMISSION = vec3(1.0, 0.82, 0.42) * (1.2 + 2.2 * night) * lit;
}
