shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

/// Moulded DMG plastic: every voxel reads as its own bevelled panel with a recessed
/// seam, fine surface grain, an LCD scanline wash and a slow power-LED breath.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 plastic_tint : source_color = vec4(0.56, 0.66, 0.42, 1.0);
uniform vec4 seam_color : source_color = vec4(0.16, 0.2, 0.13, 1.0);
uniform vec4 lcd_glow : source_color = vec4(0.4, 0.98, 0.45, 1.0);
uniform vec4 lcd_deep : source_color = vec4(0.1, 0.24, 0.08, 1.0);
uniform float texture_mix : hint_range(0.0, 1.0) = 0.5;
/// World size of one voxel cell — panel/seam layout is keyed to it.
uniform float cell_size = 0.5;
uniform float seam_width : hint_range(0.0, 0.3) = 0.07;
uniform float bevel : hint_range(0.0, 0.5) = 0.22;
uniform float grain_scale : hint_range(0.5, 24.0) = 6.5;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float cell_tint_variation : hint_range(0.0, 0.5) = 0.12;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.3;
uniform float emission_base : hint_range(0.0, 4.0) = 0.16;
uniform float emission_peak : hint_range(0.0, 4.0) = 0.5;
uniform float pulse_hz : hint_range(0.0, 3.0) = 0.35;
uniform float sheen : hint_range(0.0, 2.0) = 0.5;

varying vec3 v_world;
varying vec3 v_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * value_noise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 an = abs(n);

	// Triplanar face coords + the world axes spanning this face.
	vec2 uv;
	vec3 wt;
	vec3 wb;
	if (an.y >= an.x && an.y >= an.z) {
		uv = v_world.xz;
		wt = vec3(1.0, 0.0, 0.0);
		wb = vec3(0.0, 0.0, 1.0);
	} else if (an.x >= an.z) {
		uv = v_world.zy;
		wt = vec3(0.0, 0.0, 1.0);
		wb = vec3(0.0, 1.0, 0.0);
	} else {
		uv = v_world.xy;
		wt = vec3(1.0, 0.0, 0.0);
		wb = vec3(0.0, 1.0, 0.0);
	}

	vec3 tex = texture(albedo_tex, uv * 1.1).rgb;
	vec3 plastic = mix(plastic_tint.rgb, tex * plastic_tint.rgb, texture_mix);

	// Per-cell panel: -1..1 across each voxel face.
	vec2 cell = fract(uv / max(cell_size, 0.001)) * 2.0 - 1.0;
	float e = max(abs(cell.x), abs(cell.y));
	float aa = fwidth(e) + 0.0001;

	float bev = smoothstep(1.0 - bevel - aa, 1.0 - aa, e);
	vec3 vt = normalize((VIEW_MATRIX * vec4(wt, 0.0)).xyz);
	vec3 vb = normalize((VIEW_MATRIX * vec4(wb, 0.0)).xyz);
	vec3 bent = normalize(normalize(NORMAL) + (vt * cell.x + vb * cell.y) * bev * 0.85);
	NORMAL = bent;

	float seam_m = smoothstep(1.0 - seam_width - aa, 1.0 - aa, e);
	plastic = mix(plastic, seam_color.rgb, seam_m * 0.85);
	plastic = mix(plastic, plastic * 1.08, bev * 0.5);

	// Slight per-cell shade spread so a large shell never looks like flat sheeting.
	float cell_id = hash13(floor(v_world / max(cell_size, 0.001)) + 0.5);
	plastic *= 1.0 + (cell_id - 0.5) * 2.0 * cell_tint_variation;

	// Injection-moulding grain.
	float grain = fbm(v_world * grain_scale);
	plastic *= mix(1.0 - grain_strength * 0.35, 1.0 + grain_strength * 0.2, grain);

	// LCD wash on the upright faces only.
	float upright = smoothstep(0.3, 0.85, an.x + an.z);
	float scan = 0.5 + 0.5 * sin(v_world.y * 42.0 - TIME * 1.1);
	plastic = mix(plastic, lcd_deep.rgb, scan * scan_strength * upright * 0.28);

	float cell_phase = hash13(floor(v_world / max(cell_size, 0.001)));
	float pulse = 0.5 + 0.5 * sin(TIME * TAU * pulse_hz + cell_phase * TAU);
	float fres = pow(1.0 - clamp(dot(bent, VIEW), 0.0, 1.0), 3.5);

	ALBEDO = plastic;
	ROUGHNESS = mix(0.72, 0.42, bev);
	METALLIC = 0.03;
	SPECULAR = 0.45;
	EMISSION = lcd_glow.rgb * (mix(emission_base, emission_peak, pulse) * (1.0 - seam_m))
		+ lcd_glow.rgb * fres * sheen * 0.35;
}
