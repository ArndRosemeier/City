shader_type sky;
render_mode use_debanding;

uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float dawn_factor : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_time = 0.0;
uniform float cloud_speed = 0.012;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;
uniform vec3 day_top : source_color = vec3(0.30, 0.56, 0.92);
uniform vec3 day_horizon : source_color = vec3(0.74, 0.86, 0.96);
uniform vec3 golden_horizon : source_color = vec3(1.0, 0.58, 0.32);
uniform vec3 night_top : source_color = vec3(0.08, 0.12, 0.22);
uniform vec3 night_horizon : source_color = vec3(0.16, 0.22, 0.38);
uniform vec3 ground_color : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 cloud_day : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_night : source_color = vec3(0.45, 0.52, 0.72);
uniform vec3 star_color : source_color = vec3(0.85, 0.92, 1.0);


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}


float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.07 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}


float star_field(vec3 dir) {
	// Cheap spherical star dots — denser near the zenith.
	vec3 n = normalize(dir);
	float h = max(n.y, 0.0);
	if (h < 0.02) {
		return 0.0;
	}
	vec2 uv = n.xz / (n.y + 0.35);
	float cells = 48.0;
	vec2 gid = floor(uv * cells);
	vec2 f = fract(uv * cells) - 0.5;
	float rnd = hash12(gid + 19.7);
	if (rnd < 0.78) {
		return 0.0;
	}
	float d = length(f - (vec2(hash12(gid + 3.1), hash12(gid + 7.9)) - 0.5) * 0.55);
	float twinkle = 0.65 + 0.35 * sin(cloud_time * (2.0 + rnd * 5.0) + rnd * 20.0);
	float s = smoothstep(0.045, 0.0, d) * twinkle;
	// Occasional brighter stars.
	s *= mix(0.55, 1.6, step(0.93, rnd));
	return s * h;
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float elev = dir.y;

	vec3 day_h = mix(day_horizon, golden_horizon, dawn_factor);
	vec3 top = mix(day_top, night_top, night_factor);
	vec3 hor = mix(day_h, night_horizon, night_factor);
	// Softer gradient toward zenith.
	float sky_t = pow(clamp(elev, 0.0, 1.0), 0.55);
	vec3 col = mix(hor, top, sky_t);

	// Ground below the horizon.
	if (elev < 0.0) {
		float g = pow(clamp(-elev, 0.0, 1.0), 0.45);
		col = mix(hor, ground_color, g);
	}

	// Scrolling cloud layer projected on the upper hemisphere.
	if (elev > -0.02) {
		vec2 cuv = dir.xz / max(elev + 0.22, 0.08);
		cuv += vec2(cloud_time * cloud_speed, cloud_time * cloud_speed * 0.37);
		float n1 = fbm(cuv * 1.15);
		float n2 = fbm(cuv * 2.4 + vec2(13.0, 5.0));
		float clouds = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n1 * 0.7 + n2 * 0.3);
		clouds *= smoothstep(-0.02, 0.18, elev);
		// Soft underside darkening.
		float shade = mix(0.75, 1.0, n2);
		vec3 ccol = mix(cloud_day, cloud_night, night_factor) * shade;
		// Moonlit clouds keep some presence at night.
		float cloud_a = clouds * mix(0.72, 0.38, night_factor);
		col = mix(col, ccol, cloud_a);
	}

	// Stars only at night, attenuated by clouds near zenith.
	if (night_factor > 0.05 && elev > 0.05) {
		float stars = star_field(dir);
		float cloud_block = 1.0;
		vec2 cuv2 = dir.xz / max(elev + 0.22, 0.08);
		cuv2 += vec2(cloud_time * cloud_speed, cloud_time * cloud_speed * 0.37);
		float cover = smoothstep(0.45, 0.8, fbm(cuv2 * 1.15));
		cloud_block = 1.0 - cover * 0.85;
		col += star_color * stars * night_factor * cloud_block * 1.35;
	}

	COLOR = col;
}
