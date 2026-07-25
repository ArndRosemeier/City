shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

/// Moulded arcade tetromino tile: fake-bevelled edges, inset panel, glowing rim
/// and a stud grid. All masks are derivative-anti-aliased so moving cubes never shimmer.
uniform vec4 block_color : source_color = vec4(0.2, 0.85, 0.95, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
/// Half edge length of the cube mesh in local units (set from GDScript).
uniform float mesh_half = 0.225;
uniform float bevel : hint_range(0.02, 0.45) = 0.2;
uniform float seam : hint_range(0.0, 0.2) = 0.05;
uniform float ring_radius : hint_range(0.2, 0.9) = 0.56;
uniform float ring_width : hint_range(0.01, 0.25) = 0.07;
uniform float stud_scale : hint_range(1.0, 6.0) = 3.0;
uniform float stud_size : hint_range(0.0, 0.5) = 0.17;
uniform float emission_base : hint_range(0.0, 6.0) = 0.45;
uniform float emission_peak : hint_range(0.0, 8.0) = 1.35;
uniform float pulse_hz : hint_range(0.0, 4.0) = 0.8;
uniform float gloss : hint_range(0.0, 1.0) = 0.6;

varying vec3 v_local;
varying vec3 v_origin;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	v_local = VERTEX;
	/// Per-instance origin — desyncs the pulse for MultiMesh cells and single meshes alike.
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 q = v_local / max(mesh_half, 0.0001);
	vec3 aq = abs(q);

	// Face-local coords plus the two world axes spanning this face.
	vec2 fc;
	vec3 wt;
	vec3 wb;
	if (aq.x >= aq.y && aq.x >= aq.z) {
		fc = vec2(q.z, q.y);
		wt = vec3(0.0, 0.0, 1.0);
		wb = vec3(0.0, 1.0, 0.0);
	} else if (aq.y >= aq.z) {
		fc = vec2(q.x, q.z);
		wt = vec3(1.0, 0.0, 0.0);
		wb = vec3(0.0, 0.0, 1.0);
	} else {
		fc = vec2(q.x, q.y);
		wt = vec3(1.0, 0.0, 0.0);
		wb = vec3(0.0, 1.0, 0.0);
	}

	float e = max(abs(fc.x), abs(fc.y));
	float aa = fwidth(e) + 0.0001;

	// Rounded-edge shading without extra geometry.
	float bev = smoothstep(1.0 - bevel - aa, 1.0 - aa, e);
	vec3 nrm = normalize(NORMAL);
	vec3 vt = normalize((VIEW_MATRIX * vec4(wt, 0.0)).xyz);
	vec3 vb = normalize((VIEW_MATRIX * vec4(wb, 0.0)).xyz);
	vec3 bent = normalize(nrm + (vt * fc.x + vb * fc.y) * bev * 1.15);
	NORMAL = bent;

	float seam_m = smoothstep(1.0 - seam - aa, 1.0 - aa, e);
	float ring = smoothstep(ring_radius - ring_width - aa, ring_radius, e)
		* (1.0 - smoothstep(ring_radius, ring_radius + ring_width + aa, e));

	// Stud grid on the inset panel.
	vec2 sg = fract((fc * 0.5 + 0.5) * stud_scale) - 0.5;
	float sd = length(sg);
	float sa = fwidth(sd) + 0.0001;
	float stud = (1.0 - smoothstep(stud_size - sa, stud_size + sa, sd))
		* (1.0 - smoothstep(ring_radius - 0.1, ring_radius, e));

	float phase = hash11(floor(v_origin.x * 3.3 + v_origin.y * 7.1 + v_origin.z * 11.7));
	float pulse = 0.5 + 0.5 * sin(TIME * TAU * pulse_hz + phase * TAU);

	vec3 base = block_color.rgb * mix(0.82, 1.1, pulse);
	base = mix(base, base * 0.55, seam_m);
	base = mix(base, edge_color.rgb, bev * 0.28);
	base = mix(base, core_color.rgb, stud * 0.3);

	float fres = pow(1.0 - clamp(dot(bent, VIEW), 0.0, 1.0), 3.0);
	float emit = mix(emission_base, emission_peak, pulse);

	ALBEDO = base;
	ROUGHNESS = mix(0.55, 0.14, gloss);
	METALLIC = 0.12;
	SPECULAR = 0.6;
	EMISSION = block_color.rgb * emit * 0.5
		+ edge_color.rgb * ring * (0.8 + 0.7 * pulse)
		+ core_color.rgb * stud * 0.45
		+ edge_color.rgb * fres * 0.4;
}
