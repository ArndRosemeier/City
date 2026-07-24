shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

/// Shared GPU "alive" look for infection voxels — TIME + world noise only (no CPU cost).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.28, 0.62, 0.22, 1.0);
uniform vec4 vein_color : source_color = vec4(0.55, 1.0, 0.28, 1.0);
uniform vec4 pulse_color : source_color = vec4(0.85, 1.0, 0.45, 1.0);
uniform float emission_base : hint_range(0.0, 8.0) = 0.55;
uniform float emission_peak : hint_range(0.0, 12.0) = 2.4;
uniform float pulse_hz : hint_range(0.1, 6.0) = 1.15;
uniform float flow_speed : hint_range(0.0, 4.0) = 0.65;
uniform float lead_boost : hint_range(0.0, 3.0) = 0.0;
uniform float texture_mix : hint_range(0.0, 1.0) = 0.45;

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
	for (int i = 0; i < 3; i++) {
		s += a * value_noise(p);
		p = p * 2.03 + 17.0;
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
	// Cheap triplanar UV for the base texture.
	vec2 uv = (an.y >= an.x && an.y >= an.z)
		? v_world.xz * 1.35
		: ((an.x >= an.z) ? v_world.zy * 1.35 : v_world.xy * 1.35);
	vec3 tex = texture(albedo_tex, uv).rgb;

	// Flowing veins in world space — desynced per voxel cell.
	float cell_phase = hash13(floor(v_world * 2.0 + 0.001));
	vec3 flow_p = v_world * 1.55
		+ vec3(TIME * flow_speed * 0.35, TIME * flow_speed, -TIME * flow_speed * 0.55)
		+ cell_phase * 6.0;
	float veins = fbm(flow_p);
	float veins2 = fbm(flow_p * 1.7 + 9.0);
	float vein_mask = smoothstep(0.38, 0.72, veins);
	float capillary = smoothstep(0.55, 0.85, veins2) * vein_mask;

	// Organic pulse — different phase per cell so the trail "breathes".
	float pulse = 0.5 + 0.5 * sin(TIME * TAU * pulse_hz + cell_phase * TAU * 2.0
		+ v_world.y * 0.9);
	float throb = 0.5 + 0.5 * sin(TIME * TAU * (pulse_hz * 1.7) + cell_phase * 5.1);

	vec3 body = mix(base_color.rgb, tex, texture_mix);
	body = mix(body, vein_color.rgb, vein_mask * 0.75);
	body = mix(body, pulse_color.rgb, capillary * 0.55 * pulse);

	// Slight darker "membrane" on edges.
	float rim = pow(1.0 - clamp(dot(n, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0), 1.4);
	body *= mix(0.82, 1.12, pulse);
	body = mix(body, body * 0.65, rim * 0.35);

	float em = mix(emission_base, emission_peak, vein_mask);
	em *= mix(0.7, 1.45, pulse);
	em *= mix(0.85, 1.25, throb);
	em *= (1.0 + lead_boost * (1.6 + capillary * 0.9));

	vec3 emit_col = mix(vein_color.rgb, pulse_color.rgb, capillary * pulse);
	emit_col = mix(emit_col, pulse_color.rgb, lead_boost * 0.35);

	ALBEDO = body;
	EMISSION = emit_col * em;
	ROUGHNESS = mix(0.62, 0.22, vein_mask + lead_boost * 0.25);
	METALLIC = 0.05 + lead_boost * 0.08;
	SPECULAR = 0.35;
}
