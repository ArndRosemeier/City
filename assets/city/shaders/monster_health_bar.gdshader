shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

/// The strip of health a monster has left, drawn just under its feet and turned to face the camera.
/// Siege towers use the same strip stood on end (`vertical` instance flag): fill runs bottom→top.
///
/// One material draws every bar in the city. How full a bar is, and how far in front of its own
/// body it floats, are instance uniforms rather than material ones, so forty living monsters
/// cost a handful of floats instead of forty materials — the same reason `creature_palette.gdshader`
/// carries its band per instance.
///
/// The billboard is the construction BaseMaterial3D generates for BILLBOARD_ENABLED with
/// `keep_scale`: the first assignment aims the quad's axes down the camera's, the second puts the
/// node's own scale back, and it is that scale which makes the bar a strip rather than a square.
///
/// `camera_pull` then slides the finished quad toward the camera, in view space so the shape
/// never changes with the angle. Without it a bar drawn under a body's feet is swallowed by that
/// body — a skeleton's legs cut it in half and a blob, which is as broad as it is tall, hides it
/// completely. The slide stops `MIN_VIEW_DEPTH` short of the camera, so walking up to a giant
/// whose bar is pulled several metres forward can never push that bar behind the near plane.

/// Long axis over short axis. Set from `monster_health_bar.gd`, which owns the proportion.
uniform float bar_aspect = 6.25;
/// Frame thickness as a fraction of the bar's short axis, divided down on the long axis so the
/// border is the same number of metres all the way round.
uniform float frame_fraction : hint_range(0.0, 0.5) = 0.16;

instance uniform float fill = 1.0;
instance uniform float camera_pull = 0.0;
/// 0 = horizontal creature strip (fill along UV.x). 1 = vertical tower strip (fill up UV.y).
instance uniform float vertical = 0.0;

const float MIN_VIEW_DEPTH = 0.6;
const vec3 FRAME_COLOR = vec3(0.03, 0.03, 0.04);
const vec3 TRACK_COLOR = vec3(0.18, 0.06, 0.07);
/// Green at full through amber to red, which is not the player's crimson corner bar: the two
/// pools are read at the same moment and must never be mistaken for each other.
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
	float inside;
	float along;
	if (vertical > 0.5) {
		/// QuadMesh UV.y is 1 at the bottom and 0 at the top — flip so fill grows upward.
		inside = (
			step(short_frame, UV.x) * step(UV.x, 1.0 - short_frame)
			* step(long_frame, UV.y) * step(UV.y, 1.0 - long_frame)
		);
		along = clamp((1.0 - UV.y - long_frame) / max(1.0 - 2.0 * long_frame, 0.0001), 0.0, 1.0);
	} else {
		inside = (
			step(long_frame, UV.x) * step(UV.x, 1.0 - long_frame)
			* step(short_frame, UV.y) * step(UV.y, 1.0 - short_frame)
		);
		along = clamp((UV.x - long_frame) / max(1.0 - 2.0 * long_frame, 0.0001), 0.0, 1.0);
	}
	float left = clamp(fill, 0.0, 1.0);
	float spent = step(along, left);
	vec3 bar = mix(FILL_LOW, FILL_HALF, smoothstep(0.15, 0.5, left));
	bar = mix(bar, FILL_FULL, smoothstep(0.5, 0.85, left));
	ALBEDO = mix(FRAME_COLOR, mix(TRACK_COLOR, bar, spent), inside);
}
