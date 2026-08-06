shader_type spatial;
/// Tower bars sit inside their own stamp at the foundation. Creatures clear that with
/// `camera_pull`; pulling a tower bar detaches it at an angle. Instead: no pull, no depth test —
/// the strip stays at the true base and still draws over the voxels that would bury it.
render_mode unshaded, cull_back, shadows_disabled, depth_test_disabled;

uniform float bar_aspect = 6.25;
uniform float frame_fraction : hint_range(0.0, 0.5) = 0.16;

instance uniform float fill = 1.0;
instance uniform float camera_pull = 0.0;
instance uniform float vertical = 0.0;

const float MIN_VIEW_DEPTH = 0.6;
const vec3 FRAME_COLOR = vec3(0.03, 0.03, 0.04);
const vec3 TRACK_COLOR = vec3(0.18, 0.06, 0.07);
const vec3 FILL_FULL = vec3(0.42, 0.85, 0.30);
const vec3 FILL_HALF = vec3(0.95, 0.72, 0.16);
const vec3 FILL_LOW = vec3(0.92, 0.16, 0.12);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	float depth = MODELVIEW_MATRIX[3].z;
	MODELVIEW_MATRIX[3].z = depth + min(camera_pull, max(-depth - MIN_VIEW_DEPTH, 0.0));
}

void fragment() {
	float long_frame = frame_fraction / max(bar_aspect, 0.0001);
	float short_frame = frame_fraction;
	float inside = (
		step(long_frame, UV.x) * step(UV.x, 1.0 - long_frame)
		* step(short_frame, UV.y) * step(UV.y, 1.0 - short_frame)
	);
	float along = clamp((UV.x - long_frame) / max(1.0 - 2.0 * long_frame, 0.0001), 0.0, 1.0);
	float left = clamp(fill, 0.0, 1.0);
	float spent = step(along, left);
	vec3 bar = mix(FILL_LOW, FILL_HALF, smoothstep(0.15, 0.5, left));
	bar = mix(bar, FILL_FULL, smoothstep(0.5, 0.85, left));
	ALBEDO = mix(FRAME_COLOR, mix(TRACK_COLOR, bar, spent), inside);
}
