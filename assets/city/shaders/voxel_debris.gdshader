shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Debris-only surface: same look as voxel_surface, but MultiMesh instance COLOR.a
/// drives a fade so piles can despawn without forcing terrain into the transparent path.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform vec2 tile_meters = vec2(2.0, 2.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float object_space : hint_range(0.0, 1.0) = 1.0;
uniform float lot_meters = 14.0;
uniform float tint_variation : hint_range(0.0, 1.0) = 0.0;
uniform float weathering : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform float ground_y = 1.0;
uniform float grime_height = 4.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.0;

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

	vec3 albedo = texture(albedo_tex, uv).rgb * tint.rgb * COLOR.rgb;
	float rough = roughness_base;

	if (use_normal) {
		vec3 nm = texture(normal_tex, uv).xyz * 2.0 - 1.0;
		mat4 to_view = VIEW_MATRIX;
		if (object_space > 0.5) {
			to_view = VIEW_MATRIX * MODEL_MATRIX;
		}
		vec3 tv = normalize((to_view * vec4(axis_u, 0.0)).xyz);
		vec3 bv = normalize((to_view * vec4(axis_v, 0.0)).xyz);
		vec3 nv = normalize(NORMAL);
		NORMAL = normalize((tv * nm.x + bv * nm.y) * normal_strength + nv * max(nm.z, 0.1));
	}

	vec3 wp = v_world;
	vec3 an = abs(v_world_normal);

	if (tint_variation > 0.0) {
		vec2 lot = floor(vec2(wp.x, wp.z) / max(lot_meters, 1.0));
		float h = vx_hash12(lot);
		float bright = 1.0 + (h - 0.5) * 0.3;
		vec3 vary = vec3(
			bright * (1.0 + (fract(h * 7.31) - 0.5) * 0.07),
			bright,
			bright * (1.0 - (fract(h * 13.77) - 0.5) * 0.07)
		);
		albedo *= mix(vec3(1.0), vary, tint_variation);
	}

	float n_lo = 0.0;
	float n_hi = 0.0;
	if (weathering > 0.0 || grime > 0.0 || streaks > 0.0) {
		n_lo = vx_value_noise(wp * 0.06);
		n_hi = vx_value_noise(wp * 0.17);
	}

	if (weathering > 0.0) {
		float w = n_lo * 0.65 + n_hi * 0.35;
		albedo *= mix(1.0, 0.66 + 0.44 * w, weathering);
		rough = clamp(rough + (w - 0.5) * 0.22 * weathering, 0.04, 1.0);
	}

	if (grime > 0.0) {
		float h_above = wp.y - ground_y;
		float band = 1.0 - smoothstep(0.0, max(grime_height, 0.01), h_above);
		albedo *= mix(1.0, mix(1.0, 0.55, band * (0.45 + 0.55 * n_hi)), grime);
	}

	if (streaks > 0.0) {
		float upright = 1.0 - clamp(an.y * 2.0, 0.0, 1.0);
		float lanes = vx_value_noise(vec3(wp.x * 2.7, 0.0, wp.z * 2.7));
		float mask = smoothstep(0.58, 1.0, lanes) * (0.35 + 0.65 * n_lo) * upright * streaks;
		albedo *= 1.0 - 0.4 * mask;
		rough = clamp(rough + 0.12 * mask, 0.04, 1.0);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic_base;
	ALPHA = COLOR.a;
}
