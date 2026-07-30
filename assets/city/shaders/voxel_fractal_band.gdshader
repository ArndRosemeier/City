shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

/// Mandelbrot sculpture bands — albedo-first palette colour with a mild glow.
/// `base_color` / `emission_color` are the look; do not wash toward cyan ore sparkle.
uniform vec4 base_color : source_color = vec4(0.2, 0.55, 0.85, 1.0);
uniform vec4 emission_color : source_color = vec4(0.25, 0.6, 0.9, 1.0);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.65;
uniform float pulse_hz : hint_range(0.0, 3.0) = 0.35;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.12;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cell = fract(sin(dot(floor(v_world * 2.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float pulse = 1.0;
	if (pulse_hz > 0.001) {
		pulse = 0.92 + 0.08 * sin(TIME * TAU * pulse_hz + cell * TAU);
	}
	vec3 albedo = base_color.rgb * pulse;
	ALBEDO = albedo;
	EMISSION = emission_color.rgb * emission_strength * pulse;
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	SPECULAR = 0.45;
}
