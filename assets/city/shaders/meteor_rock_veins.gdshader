shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

/// Dark meteor rock with red glowing veins only — emission is masked; no uniform glow.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(0.42, 0.36, 0.32, 1.0);
uniform vec4 vein_color : source_color = vec4(1.0, 0.18, 0.05, 1.0);
uniform vec4 vein_hot : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform float texture_mix : hint_range(0.0, 1.0) = 0.78;
uniform float vein_emission : hint_range(0.0, 12.0) = 3.6;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.28;
uniform float vein_scale : hint_range(0.2, 6.0) = 1.85;
uniform float vein_threshold : hint_range(0.35, 0.92) = 0.62;
uniform float vein_width : hint_range(0.02, 0.35) = 0.11;
uniform float pulse_hz : hint_range(0.0, 4.0) = 0.55;

varying vec3 v_world;
varying vec3 v_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * value_noise(p);
		p = p * 2.07 + 19.0;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 an = abs(n);
	vec2 uv = (an.y >= an.x && an.y >= an.z)
		? v_world.xz * 1.15
		: ((an.x >= an.z) ? v_world.zy * 1.15 : v_world.xy * 1.15);
	vec3 tex = texture(albedo_tex, uv).rgb;
	vec3 rock = mix(rock_tint.rgb, tex * rock_tint.rgb, texture_mix);

	// Ridge-style veins: thin glowing cracks, not a filled field.
	float cell_phase = hash13(floor(v_world * 1.5 + 0.001));
	vec3 flow_p = v_world * vein_scale
		+ vec3(TIME * flow_speed * 0.22, TIME * flow_speed * 0.08, -TIME * flow_speed * 0.18)
		+ cell_phase * 4.0;
	float n1 = fbm(flow_p);
	float n2 = fbm(flow_p * 1.65 + 11.0);
	float ridge = 1.0 - abs(n1 * 2.0 - 1.0);
	float ridge2 = 1.0 - abs(n2 * 2.0 - 1.0);
	float vein_mask = smoothstep(vein_threshold, vein_threshold + vein_width, ridge);
	float capillary = smoothstep(vein_threshold + 0.04, vein_threshold + vein_width + 0.08, ridge2);
	vein_mask = max(vein_mask * 0.85, vein_mask * capillary);

	// Soft pulse only along the veins (rock body stays dark).
	float pulse = 0.72 + 0.28 * sin(TIME * TAU * pulse_hz + cell_phase * TAU + v_world.y * 1.1);

	vec3 albedo = rock;
	albedo = mix(albedo, mix(rock, vein_color.rgb, 0.35), vein_mask * 0.55);

	vec3 emit_col = mix(vein_color.rgb, vein_hot.rgb, capillary * 0.65);
	float em = vein_emission * vein_mask * pulse;

	ALBEDO = albedo;
	EMISSION = emit_col * em;
	ROUGHNESS = mix(0.94, 0.42, vein_mask);
	METALLIC = 0.04;
	SPECULAR = 0.28;
}
