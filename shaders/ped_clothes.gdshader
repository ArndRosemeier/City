shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D skin_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 skin_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shirt_color : source_color = vec4(0.35, 0.42, 0.55, 1.0);
uniform vec4 pants_color : source_color = vec4(0.22, 0.24, 0.28, 1.0);
uniform vec4 shoes_color : source_color = vec4(0.12, 0.10, 0.09, 1.0);
uniform float head_y = 1.40;
uniform float shirt_bottom_y = 0.90;
uniform float pants_bottom_y = 0.10;
uniform float cloth_mix = 0.88;

varying float body_y;

void vertex() {
	// Skeleton-local height after skinning — upright body bands for crowd clothes.
	body_y = VERTEX.y;
}

void fragment() {
	vec3 skin = texture(skin_tex, UV).rgb * skin_tint.rgb;
	vec3 out_c = skin;
	if (body_y > head_y) {
		out_c = skin;
	} else if (body_y > shirt_bottom_y) {
		out_c = mix(skin, shirt_color.rgb, cloth_mix);
	} else if (body_y > pants_bottom_y) {
		out_c = mix(skin, pants_color.rgb, cloth_mix);
	} else {
		out_c = mix(skin, shoes_color.rgb, 0.95);
	}
	ALBEDO = out_c;
	ROUGHNESS = 0.72;
	METALLIC = 0.0;
}
