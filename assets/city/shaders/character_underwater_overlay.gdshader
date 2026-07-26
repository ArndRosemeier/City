shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_opaque, cull_back;

/// MeshInstance3D.material_overlay while swimming. Clip plane is biased above the
/// real waterline so swim-cycle bob does not flicker fragments on/off.

uniform float water_surface_y = 0.0;
/// Extra metres above the surface counted as "under" (covers anim bob).
uniform float clip_bias_m = 0.35;
uniform vec4 tint : source_color = vec4(0.12, 0.32, 0.48, 0.72);
uniform float fade_m = 0.18;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float line = water_surface_y + clip_bias_m;
	float below = 1.0 - smoothstep(line - fade_m, line + fade_m * 0.25, v_world_y);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * below;
}
