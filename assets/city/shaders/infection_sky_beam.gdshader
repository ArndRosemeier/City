shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

/// Slim violet skyward beam — fast upward streaks (energy to space).
uniform vec4 beam_color : source_color = vec4(0.72, 0.28, 1.0, 0.75);
uniform float emission_mul : hint_range(0.0, 12.0) = 4.0;
uniform float scroll_speed : hint_range(0.0, 12.0) = 4.5;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float fade_top : hint_range(0.0, 1.0) = 0.75;
uniform float streak_count : hint_range(1.0, 16.0) = 7.0;

varying float v_h;

void vertex() {
	v_h = UV.y;
}

void fragment() {
	float h = clamp(v_h, 0.0, 1.0);
	// Fast directed rise: tight streaks racing up the column.
	float scroll = fract(h * streak_count - TIME * scroll_speed);
	float band = smoothstep(0.0, 0.06, scroll) * smoothstep(0.28, 0.08, scroll);
	float secondary = fract(h * (streak_count * 1.7) - TIME * scroll_speed * 1.35);
	float band2 = smoothstep(0.0, 0.04, secondary) * smoothstep(0.18, 0.05, secondary);
	float soft = 0.22 + band * 1.15 + band2 * 0.7;
	// Stronger near the source, thinning into space.
	float height_fade = mix(1.2, 1.0 - fade_top, h);
	float edge = 1.0 - abs(UV.x - 0.5) * 1.7;
	edge = clamp(edge, 0.0, 1.0);
	float a = beam_color.a * soft * height_fade * edge * intensity;
	vec3 col = beam_color.rgb * (0.4 + band * 1.1 + band2 * 0.55);
	ALBEDO = col;
	EMISSION = col * emission_mul * intensity * (0.55 + band * 1.2 + band2 * 0.6);
	ALPHA = clamp(a, 0.0, 1.0);
}
