shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

/// Landing preview outline. Additive + no depth write, so it is order-independent
/// and can never flicker against the falling piece or the stack behind it.
uniform vec4 ghost_color : source_color = vec4(0.75, 0.95, 0.65, 1.0);
uniform float mesh_half = 0.225;
uniform float frame_width : hint_range(0.02, 0.5) = 0.14;
uniform float strength : hint_range(0.0, 3.0) = 0.55;
uniform float fill : hint_range(0.0, 1.0) = 0.08;
uniform float pulse_hz : hint_range(0.0, 4.0) = 1.1;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 q = v_local / max(mesh_half, 0.0001);
	vec3 aq = abs(q);
	vec2 fc;
	if (aq.x >= aq.y && aq.x >= aq.z) {
		fc = vec2(q.z, q.y);
	} else if (aq.y >= aq.z) {
		fc = vec2(q.x, q.z);
	} else {
		fc = vec2(q.x, q.y);
	}
	float e = max(abs(fc.x), abs(fc.y));
	float aa = fwidth(e) + 0.0001;
	float frame = smoothstep(1.0 - frame_width - aa, 1.0 - aa, e);
	float pulse = 0.65 + 0.35 * sin(TIME * TAU * pulse_hz);
	ALBEDO = ghost_color.rgb * (frame + fill) * strength * pulse;
	ALPHA = 1.0;
}
