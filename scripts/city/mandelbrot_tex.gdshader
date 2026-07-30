shader_type spatial;
render_mode unshaded, cull_disabled;

// Displays the native TEX_RES² Mandelbrot bake. Nearest keeps texel grid crisp.
uniform sampler2D bake_tex : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec4 s = texture(bake_tex, UV);
	ALBEDO = s.rgb;
	ALPHA = 1.0;
}
