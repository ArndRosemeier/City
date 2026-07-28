shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

/// Trap — same crystalline body as a gem, but the glow contracts inward (sucking
/// toward the core) instead of blooming outward. Direction is radial from center.
uniform vec4 base_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float emission_base : hint_range(0.0, 12.0) = 1.4;
uniform float emission_peak : hint_range(0.0, 16.0) = 5.0;
uniform float pulse_hz : hint_range(0.1, 6.0) = 1.35;
uniform float sparkle_scale : hint_range(0.5, 12.0) = 4.5;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.22;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.18;

varying vec3 v_obj;
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

void vertex() {
	v_obj = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_normal);
	float cell_phase = hash13(floor(v_obj * 8.0 + 0.001));

	float facets = value_noise(v_obj * sparkle_scale + cell_phase * 3.0);
	float sparkle = smoothstep(0.62, 0.92, facets);

	/// Outward pulse value flipped: high = core bright / rim dark.
	float wave = 0.5 + 0.5 * sin(TIME * TAU * pulse_hz + cell_phase * TAU);
	float radial = clamp(length(v_obj) / 0.55, 0.0, 1.0);
	float inward = smoothstep(0.05, 0.85, (1.0 - radial) * mix(0.55, 1.35, wave));

	vec3 body = base_color.rgb;
	body = mix(body * 0.45, body * 1.2, inward);
	body = mix(body, emission_color.rgb, sparkle * 0.25 * inward);

	float em = mix(emission_base, emission_peak, inward);
	em *= mix(0.55, 1.35, wave);
	em *= (1.0 + sparkle * 0.4);

	ALBEDO = body;
	EMISSION = emission_color.rgb * em;
	ROUGHNESS = mix(roughness_base, 0.1, inward);
	METALLIC = metallic_base + sparkle * 0.15;
	SPECULAR = 0.6;
}
