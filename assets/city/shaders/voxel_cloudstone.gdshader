shader_type spatial;
/// Cull disabled so overlapping puff lobes do not punch holes into each other.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Soft billowy cloud block — world-projected noise so adjacent cells share one fluff sheet.

uniform vec4 tint : source_color = vec4(0.86, 0.92, 1.0, 0.92);
uniform vec4 shadow_tint : source_color = vec4(0.55, 0.62, 0.78, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float object_space : hint_range(0.0, 1.0) = 0.0;
uniform float puff_scale : hint_range(0.1, 8.0) = 1.15;
uniform float puff_speed : hint_range(0.0, 2.0) = 0.22;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.35;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.45;

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 q = v_world * puff_scale + vec3(0.0, TIME * puff_speed, TIME * puff_speed * 0.37);
	vec3 q2 = q * 2.1 + vec3(7.0, 3.0, 11.0);
	float n0 = vx_value_noise(q);
	float n1 = vx_value_noise(q2);
	float puff = clamp(n0 * 0.65 + n1 * 0.35, 0.0, 1.0);

	float e = 0.18;
	float hx = vx_value_noise(q + vec3(e, 0.0, 0.0)) * 0.65
		+ vx_value_noise(q2 + vec3(e, 0.0, 0.0)) * 0.35;
	float hy = vx_value_noise(q + vec3(0.0, e, 0.0)) * 0.65
		+ vx_value_noise(q2 + vec3(0.0, e, 0.0)) * 0.35;
	float hz = vx_value_noise(q + vec3(0.0, 0.0, e)) * 0.65
		+ vx_value_noise(q2 + vec3(0.0, 0.0, e)) * 0.35;
	vec3 grad = vec3(hx - puff, hy - puff, hz - puff) / e;

	vec3 bent = normalize(NORMAL - grad * 0.55);
	NORMAL = bent;

	float rim = pow(1.0 - clamp(dot(bent, VIEW), 0.0, 1.0), 2.4);
	vec3 albedo = mix(shadow_tint.rgb, tint.rgb, 0.35 + 0.65 * puff);
	albedo = mix(albedo, vec3(1.0), rim * edge_softness * 0.35);

	ALBEDO = albedo;
	ALPHA = clamp(mix(tint.a * 0.78, tint.a, puff), 0.55, 1.0) * COLOR.a;
	ROUGHNESS = clamp(roughness_base + (1.0 - puff) * 0.08, 0.0, 1.0);
	METALLIC = metallic_base;
	SPECULAR = 0.2;
	EMISSION = mix(shadow_tint.rgb, tint.rgb, puff) * emission_strength * (0.35 + 0.65 * puff);
}
