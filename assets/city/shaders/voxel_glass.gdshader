shader_type spatial;
/// Opaque on purpose: true alpha glass rides the transparent pass and can sort over
/// foreground voxels (walls/furniture look see-through and flicker). Pane look comes
/// from cool tint, mullions, fresnel, and specular — same depth path as brick.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/city/shaders/voxel_projection.gdshaderinc"

/// Window / structural glass (opaque voxel). Reads as a tinted pane, not an air hole.

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

/// Lit brightness of one window cell: on/off from the cell hash, times its own dimming.
float vx_window_glow(vec3 cell) {
	float pick = vx_hash13(cell);
	return step(1.0 - lit_ratio, pick) * (0.65 + 0.35 * fract(pick * 31.7));
}

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
	/// Metre-space face UV, kept before the tile divide: the window grid needs the two
	/// axes that actually run across this face, not the world triple (the third is
	/// constant on a flat voxel face, so its derivative is zero and useless for AA).
	vec2 face_m = uv;
	uv /= max(tile_meters, vec2(0.01, 0.01));

	vec3 pane = texture(albedo_tex, uv).rgb;
	float mullion = clamp(1.0 - dot(pane, vec3(0.299, 0.587, 0.114)) * 1.35, 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.5);
	float rim = clamp(fres * fresnel_strength, 0.0, 1.0);

	/// Solid cool pane — bright enough to read as glass, not a void.
	vec3 glass_body = mix(vec3(0.42, 0.55, 0.66), tint.rgb * 0.72, 0.65);
	vec3 albedo = mix(glass_body, pane * tint.rgb * 0.7, 0.45);
	/// Darker frames so punched windows look framed, not empty.
	albedo = mix(albedo, vec3(0.16, 0.18, 0.22), mullion * 0.9);
	vec3 sky = vec3(0.55, 0.7, 0.9) * day_sky_tint * (1.0 - night_factor);
	albedo = mix(albedo, albedo * 1.15 + sky * 0.35, rim * 0.85);

	vec3 emission = sky * (0.12 + rim * 0.28) + vec3(1.0) * pow(fres, 5.0) * 0.55;
	/// Both tests are uniforms, so daylight skips the whole grid rather than filtering a
	/// window pattern that resolves to zero emission anyway (power is 0 below 0.15).
	if (lit_ratio > 0.0 && night_factor > 0.15) {
		float wm = max(window_meters, 0.05);
		vec3 cell = floor(p / wm);
		float warm_mix = vx_hash13(cell + 41.7);
		vec3 lamp = mix(lit_cool.rgb, lit_warm.rgb, smoothstep(0.25, 0.75, warm_mix));

		/// Each cell is flat-shaded, so the only detail is the hard jump at its border —
		/// exactly the one-pixel edge that crawls into moving patterns. Box-filter it:
		/// weight this cell against the neighbour the pixel footprint spills into.
		vec2 grid = face_m / wm;
		vec2 px = max(fwidth(grid), vec2(1e-5));
		vec2 f = fract(grid);
		vec2 spill_lo = max(vec2(0.0), px * 0.5 - f) / px;
		vec2 spill_hi = max(vec2(0.0), f + px * 0.5 - 1.0) / px;
		vec2 wn = min(spill_lo + spill_hi, vec2(0.5));
		vec3 du = axis_u * (spill_lo.x > 0.0 ? -1.0 : 1.0);
		vec3 dv = axis_v * (spill_lo.y > 0.0 ? -1.0 : 1.0);
		float glow = mix(
			mix(vx_window_glow(cell), vx_window_glow(cell + du), wn.x),
			mix(vx_window_glow(cell + dv), vx_window_glow(cell + du + dv), wn.x),
			wn.y
		);

		/// Past roughly one pixel per cell even a filtered grid is noise. Fade the whole
		/// thing into the steady glow it averages to: lit_ratio of the cells, at the mean
		/// brightness and a neutral lamp colour.
		float lod = smoothstep(0.35, 1.0, max(px.x, px.y));
		lamp = mix(lamp, mix(lit_cool.rgb, lit_warm.rgb, 0.5), lod);
		glow = mix(glow, lit_ratio * 0.825, lod);

		float power = smoothstep(0.15, 0.7, night_factor);
		emission += lamp * lit_energy * power * glow;
		albedo = mix(albedo, lamp * 0.85, clamp(power * glow, 0.0, 1.0) * 0.5);
	}

	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_base, 0.04, fres);
	METALLIC = mix(metallic_base * 0.45, 0.55, rim);
	SPECULAR = 1.0;
	EMISSION = emission;
}
