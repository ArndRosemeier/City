shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Shared opaque terrain surface for the blocky voxel city.
///
/// The blocky mesher emits one 0..1 UV per cube face, which squeezes a whole texture
/// onto every 0.5 m face. Instead we project world space onto the dominant face axis,
/// so a brick course runs unbroken across a wall at real-world scale.
///
/// On top of that: per-lot albedo variation, building-scale grime, ground contact dirt
/// and vertical streaks — all keyed to world position, so neighbouring buildings made
/// of the same material stop looking identical.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
/// Metres of world space covered by one texture repeat (per axis, for non-square maps).
uniform vec2 tile_meters = vec2(2.0, 2.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
/// 1.0 = project in mesh-local space. Debris tumbles, so world projection would swim.
uniform float object_space : hint_range(0.0, 1.0) = 0.0;
/// Lot footprint in metres — one tint draw per building lot.
uniform float lot_meters = 14.0;
uniform float tint_variation : hint_range(0.0, 1.0) = 0.0;
/// Metre-scale mottling for the big ground planes. A photoscanned lawn carries all its
/// detail below the blade, which mipmaps average straight back to flat felt, so the only
/// structure that survives minification is structure authored at patch size.
uniform float patch_variation : hint_range(0.0, 1.0) = 0.0;
uniform float patch_meters = 2.5;
uniform float weathering : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.0;
/// World height of the street deck; grime fades out this many metres above it.
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

	// Weathering always keys off true world position, so a chunk that breaks off a
	// wall keeps roughly the shading it had in place.
	vec3 wp = v_world;
	vec3 an = abs(v_world_normal);

	if (tint_variation > 0.0) {
		// Mostly a brightness spread with only a slight warm/cool shift — enough to
		// tell two neighbouring buildings apart without tinting stone green.
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

	if (patch_variation > 0.0) {
		// Two octaves an octave apart, so a lawn reads at roughly patch_meters and a
		// third of it: shaded hollows and scorched patches instead of one flat field.
		vec3 pp = wp / max(patch_meters, 0.1);
		float patch = vx_value_noise(pp) * 0.62 + vx_value_noise(pp * 2.7) * 0.38;
		// Value noise clusters hard around 0.5, so it is worthless until stretched — at
		// unit gain this whole block is a 4% wobble, which is to say invisible.
		patch = clamp((patch - 0.5) * 3.4 + 0.5, 0.0, 1.0);
		albedo *= mix(1.0, 0.72 + 0.56 * patch, patch_variation);
		// Brightness alone reads as a lighting artefact. The dry end shifts to straw and
		// the damp end to a cooler green, which is what makes it read as ground cover.
		float dry = smoothstep(0.55, 1.0, patch) * patch_variation;
		albedo = mix(albedo, albedo * vec3(1.18, 1.06, 0.62), dry * 0.6);
		float lush = (1.0 - smoothstep(0.0, 0.45, patch)) * patch_variation;
		albedo = mix(albedo, albedo * vec3(0.82, 1.04, 0.86), lush * 0.5);
	}

	// Two octaves at building scale, shared by all three weathering effects: the
	// aerial view draws a lot of wall pixels, so the noise budget stays at three
	// samples per fragment instead of five.
	float n_lo = 0.0;
	float n_hi = 0.0;
	if (weathering > 0.0 || grime > 0.0 || streaks > 0.0) {
		n_lo = vx_value_noise(wp * 0.06);
		n_hi = vx_value_noise(wp * 0.17);
	}

	if (weathering > 0.0) {
		float w = n_lo * 0.65 + n_hi * 0.35;
		// Biased towards darkening: pale plaster and concrete blew out in daylight.
		albedo *= mix(1.0, 0.66 + 0.44 * w, weathering);
		rough = clamp(rough + (w - 0.5) * 0.22 * weathering, 0.04, 1.0);
	}

	if (grime > 0.0) {
		float h_above = wp.y - ground_y;
		float band = 1.0 - smoothstep(0.0, max(grime_height, 0.01), h_above);
		albedo *= mix(1.0, mix(1.0, 0.55, band * (0.45 + 0.55 * n_hi)), grime);
	}

	if (streaks > 0.0) {
		// Vertical wash marks on upright faces only: lane placement needs its own
		// height-independent sample, the fade along the run reuses the low octave.
		float upright = 1.0 - clamp(an.y * 2.0, 0.0, 1.0);
		float lanes = vx_value_noise(vec3(wp.x * 2.7, 0.0, wp.z * 2.7));
		float mask = smoothstep(0.58, 1.0, lanes) * (0.35 + 0.65 * n_lo) * upright * streaks;
		albedo *= 1.0 - 0.4 * mask;
		rough = clamp(rough + 0.12 * mask, 0.04, 1.0);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic_base;
}
