shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Leaf / yew card foliage. Uses mesh UVs so the texture alpha silhouette punches
/// holes in cross-plane cards. Alpha scissor keeps dense canopies out of the
/// transparent sort path (unlike glass blend).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.45;
/// Lot footprint in metres — one tint draw per building lot.
uniform float lot_meters = 14.0;
uniform float tint_variation : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float a = tex.a * COLOR.a;
	if (a < alpha_scissor) {
		discard;
	}

	vec3 albedo = tex.rgb * tint.rgb * COLOR.rgb;

	if (tint_variation > 0.0) {
		vec2 lot = floor(vec2(v_world.x, v_world.z) / max(lot_meters, 1.0));
		float h = vx_hash12(lot);
		float bright = 1.0 + (h - 0.5) * 0.28;
		vec3 vary = vec3(
			bright * (1.0 + (fract(h * 7.31) - 0.5) * 0.06),
			bright,
			bright * (1.0 - (fract(h * 13.77) - 0.5) * 0.06)
		);
		albedo *= mix(vec3(1.0), vary, tint_variation);
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	ALPHA = 1.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
