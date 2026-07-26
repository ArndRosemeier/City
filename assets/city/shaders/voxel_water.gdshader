shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Pond / pool water. UVs and ripples are locked to world XZ so a multi-voxel
/// body shares one continuous sheet instead of restarting per cube face.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile_meters = vec2(4.0, 4.0);
uniform vec4 tint : source_color = vec4(0.35, 0.62, 0.78, 0.62);
uniform vec4 deep_tint : source_color = vec4(0.08, 0.2, 0.3, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.06;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.05;
/// Kept for material API parity with other voxel surface shaders (unused here).
uniform float object_space : hint_range(0.0, 1.0) = 0.0;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.045;
uniform float wave_scale : hint_range(0.1, 8.0) = 1.6;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.55;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.7;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.45;
uniform float sparkle : hint_range(0.0, 4.0) = 1.2;

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 tile = max(tile_meters, vec2(0.01, 0.01));
	vec2 uv = v_world.xz / tile;

	vec2 drift = vec2(TIME * scroll_speed, TIME * scroll_speed * 0.6);
	// The water albedo map is nearly flat, so the look comes from the ripple field;
	// the texture only contributes a faint colour drift.
	vec3 surface = mix(
		texture(albedo_tex, uv + drift).rgb,
		texture(albedo_tex, uv * 1.37 - drift * 0.8).rgb,
		0.5
	);

	// Two octaves of animated noise, finite-differenced into ripple normals.
	vec3 q = vec3(v_world.x, v_world.z, TIME * wave_speed) * vec3(wave_scale, wave_scale, 1.0);
	vec3 q2 = q * 2.7 + vec3(11.0, 5.0, 0.0);
	float e = 0.3;
	float h0 = vx_value_noise(q) * 0.7 + vx_value_noise(q2) * 0.3;
	float hx = vx_value_noise(q + vec3(e, 0.0, 0.0)) * 0.7 + vx_value_noise(q2 + vec3(e, 0.0, 0.0)) * 0.3;
	float hz = vx_value_noise(q + vec3(0.0, e, 0.0)) * 0.7 + vx_value_noise(q2 + vec3(0.0, e, 0.0)) * 0.3;
	vec2 grad = vec2(hx - h0, hz - h0) / e;

	// Bend in view space using a fixed XZ tangent frame (same on every face).
	vec3 tv = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 bv = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 nv = normalize(NORMAL);
	vec3 bent = normalize(nv - (tv * grad.x + bv * grad.y) * wave_strength);
	NORMAL = bent;

	float fres = pow(1.0 - clamp(dot(bent, VIEW), 0.0, 1.0), 4.0);
	// Side walls of a deep pool face mostly sideways — still tint from the same sheet.
	float upness = clamp(abs(v_world_normal.y), 0.0, 1.0);
	vec3 albedo = mix(deep_tint.rgb, surface * tint.rgb, 0.35 + 0.5 * fres * upness);
	albedo *= 0.85 + 0.3 * h0;

	ALBEDO = albedo;
	/// MultiMesh debris fades via instance COLOR.a; terrain meshes leave it at 1.
	ALPHA = clamp(tint.a + fres * fresnel_strength * upness, 0.0, 1.0) * COLOR.a;
	ROUGHNESS = clamp(roughness_base + h0 * 0.05, 0.0, 1.0);
	METALLIC = metallic_base;
	SPECULAR = 1.0;
	EMISSION = vec3(0.06, 0.12, 0.16) * sparkle * pow(h0, 6.0) * upness;
}
