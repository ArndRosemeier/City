shader_type spatial;
render_mode blend_mix, depth_draw_opaque, shadows_disabled, ambient_light_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Window / structural glass. Ambient is disabled so transparent lit albedo does not
/// wash into milky plastic. Texture is a faint mullion/variation pass over clear tint.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile_meters = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(0.75, 0.88, 1.0, 0.4);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.08;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.2;
uniform float object_space : hint_range(0.0, 1.0) = 0.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.6;
/// Size of one "window" for the lit/dark hash, in metres.
uniform float window_meters = 1.5;
/// Fraction of windows that can light up at all (0 for plain glass).
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec4 lit_warm : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform vec4 lit_cool : source_color = vec4(0.7, 0.86, 1.0, 1.0);
uniform float lit_energy : hint_range(0.0, 8.0) = 3.2;
uniform float day_sky_tint : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world;
varying vec3 v_object;
varying vec3 v_world_normal;
varying vec3 v_object_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_object = VERTEX;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_object_normal = normalize(NORMAL);
}

void fragment() {
	vec3 p = v_world;
	vec3 n = v_world_normal;
	if (object_space > 0.5) {
		p = v_object;
		n = v_object_normal;
	}

	vec2 uv;
	vec3 axis_u;
	vec3 axis_v;
	vx_project(p, n, uv, axis_u, axis_v);
	uv /= max(tile_meters, vec2(0.01, 0.01));

	vec3 pane = texture(albedo_tex, uv).rgb;
	float mullion = clamp(1.0 - dot(pane, vec3(0.299, 0.587, 0.114)) * 1.35, 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.5);
	float rim = clamp(fres * fresnel_strength, 0.0, 1.0);

	// Mostly clear tint; texture only a faint cool drift + thin frames.
	vec3 albedo = tint.rgb * 0.14;
	albedo = mix(albedo, pane * tint.rgb * 0.1, 0.35);
	albedo = mix(albedo, albedo * 0.4, mullion * 0.6);
	vec3 sky = vec3(0.5, 0.65, 0.85) * day_sky_tint * (1.0 - night_factor);
	albedo += sky * rim * 1.1;

	float alpha = clamp(tint.a * 0.38 + rim * 0.85 + mullion * 0.1, 0.07, 0.8);

	vec3 emission = sky * rim * 0.55 + vec3(1.0) * pow(fres, 6.0) * 0.4;
	if (lit_ratio > 0.0) {
		vec3 cell = floor(v_world / max(window_meters, 0.05));
		float pick = vx_hash13(cell);
		float on = step(1.0 - lit_ratio, pick);
		float warm_mix = vx_hash13(cell + 41.7);
		vec3 lamp = mix(lit_cool.rgb, lit_warm.rgb, smoothstep(0.25, 0.75, warm_mix));
		float power = smoothstep(0.15, 0.7, night_factor) * (0.65 + 0.35 * fract(pick * 31.7));
		emission += lamp * lit_energy * power * on;
		albedo = mix(albedo, lamp * 0.8, power * on * 0.6);
		alpha = clamp(alpha + power * on * 0.35, 0.0, 1.0);
	}

	ALBEDO = albedo;
	/// MultiMesh debris fades via instance COLOR.a; terrain meshes leave it at 1.
	ALPHA = alpha * COLOR.a;
	ROUGHNESS = mix(roughness_base, 0.02, fres);
	METALLIC = metallic_base * 0.3;
	SPECULAR = 1.0;
	EMISSION = emission;
}
