shader_type sky;
render_mode disable_fog;

uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float dawn_factor : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_time = 0.0;
uniform float cloud_speed = 0.02;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.62;
uniform vec3 day_top : source_color = vec3(0.30, 0.56, 0.92);
uniform vec3 day_horizon : source_color = vec3(0.74, 0.86, 0.96);
uniform vec3 golden_horizon : source_color = vec3(1.0, 0.58, 0.32);
uniform vec3 night_top : source_color = vec3(0.08, 0.12, 0.26);
uniform vec3 night_horizon : source_color = vec3(0.18, 0.26, 0.42);
uniform vec3 ground_color : source_color = vec3(0.10, 0.10, 0.11);
uniform vec3 cloud_day : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_night : source_color = vec3(0.55, 0.62, 0.82);
uniform vec3 star_color : source_color = vec3(0.9, 0.95, 1.0);


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
	v += a * noise2(p); p *= 2.07; a *= 0.5;
	v += a * noise2(p); p *= 2.07; a *= 0.5;
	v += a * noise2(p); p *= 2.07; a *= 0.5;
	v += a * noise2(p); p *= 2.07; a *= 0.5;
	v += a * noise2(p);
	return v;
}


float star_field(vec3 dir) {
	vec3 n = normalize(dir);
	float h = max(n.y, 0.0);
	if (h < 0.02) {
		return 0.0;
	}
	vec2 uv = n.xz / (n.y + 0.28);
	float cells = 64.0;
	vec2 gid = floor(uv * cells);
	vec2 f = fract(uv * cells) - 0.5;
	float rnd = hash12(gid + 19.7);
	if (rnd < 0.62) {
		return 0.0;
	}
	vec2 offset = (vec2(hash12(gid + 3.1), hash12(gid + 7.9)) - 0.5) * 0.6;
	float d = length(f - offset);
	float twinkle = 0.55 + 0.45 * sin(TIME * (1.5 + rnd * 4.0) + rnd * 30.0);
	float s = smoothstep(0.07, 0.0, d) * twinkle;
	s *= mix(0.7, 2.2, step(0.9, rnd));
	return s * pow(h, 0.35);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float elev = dir.y;

	vec3 day_h = mix(day_horizon, golden_horizon, dawn_factor);
	vec3 top = mix(day_top, night_top, night_factor);
	vec3 hor = mix(day_h, night_horizon, night_factor);
	float sky_t = pow(clamp(elev, 0.0, 1.0), 0.5);
	vec3 col = mix(hor, top, sky_t);

	if (elev < 0.0) {
		float g = pow(clamp(-elev, 0.0, 1.0), 0.4);
		col = mix(hor, ground_color, g);
	} else {
		// Scrolling clouds on the upper hemisphere.
		vec2 cuv = dir.xz / max(elev + 0.35, 0.12);
		cuv += vec2(cloud_time * cloud_speed, cloud_time * cloud_speed * 0.4);
		float n1 = fbm(cuv * 0.95);
		float n2 = fbm(cuv * 2.1 + vec2(11.0, 4.0));
		float density = n1 * 0.65 + n2 * 0.35;
		float edge0 = 1.0 - cloud_cover;
		float clouds = smoothstep(edge0, edge0 + 0.35, density);
		clouds *= smoothstep(0.0, 0.22, elev);
		float shade = mix(0.7, 1.05, n2);
		vec3 ccol = mix(cloud_day, cloud_night, night_factor) * shade;
		float cloud_a = clouds * mix(0.85, 0.5, night_factor);
		col = mix(col, ccol, cloud_a);

		// Stars at night (behind / between clouds).
		if (night_factor > 0.08) {
			float stars = star_field(dir);
			float cloud_block = 1.0 - clouds * 0.92;
			col += star_color * stars * night_factor * cloud_block * 2.4;
		}
	}

	COLOR = col;
}
