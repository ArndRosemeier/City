/// Shared helpers for the voxel city surface shaders.
///
/// Blocky voxel faces are always axis-aligned, so a world-space projection onto the
/// dominant face axis is exact: one texture sample, no triplanar blend, and patterns
/// run continuously across a whole wall instead of restarting on every 0.5 m cube.

float vx_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vx_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vx_value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = vx_hash13(i);
	float n100 = vx_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = vx_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = vx_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = vx_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = vx_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = vx_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = vx_hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

/// Face-axis projection. Returns metre-space UV plus the two in-plane world axes
/// (used to rebuild a tangent frame for normal mapping without mesh tangents).
void vx_project(vec3 p, vec3 n, out vec2 uv, out vec3 axis_u, out vec3 axis_v) {
	vec3 an = abs(n);
	if (an.y >= an.x && an.y >= an.z) {
		uv = vec2(p.x, p.z);
		axis_u = vec3(1.0, 0.0, 0.0);
		axis_v = vec3(0.0, 0.0, 1.0);
	} else if (an.x >= an.z) {
		uv = vec2(p.z, -p.y);
		axis_u = vec3(0.0, 0.0, 1.0);
		axis_v = vec3(0.0, -1.0, 0.0);
	} else {
		uv = vec2(p.x, -p.y);
		axis_u = vec3(1.0, 0.0, 0.0);
		axis_v = vec3(0.0, -1.0, 0.0);
	}
}
