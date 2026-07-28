shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

/// Per-instance recolour for authored creature bodies, aimed at one art-directed palette band.
///
/// Every Quaternius monster shares one Atlas_Monsters.png and each KayKit skeleton has its own
/// skeleton_texture.png, so the roster is fifty models wearing a handful of textures. The band
/// is an instance uniform rather than a material uniform: one ShaderMaterial per source
/// material is kept for the whole army and each MeshInstance3D carries its own band, so a
/// varied crowd costs a few floats per body instead of a material per body.
///
/// The band is aimed rather than rotated. Turning hue preserves the source's saturation and
/// its distance from every other hue, so any rotation wide enough to vary the roster also
/// walks it through mint, lilac, rose and powder blue. Here hue is pulled toward the band's
/// own hue and saturation and value are remapped into the band's ranges, so a body lands where
/// the band says however the atlas region it started from was coloured.
///
/// The remap runs in gamma space, not in the linear space the sampler decodes to. Saturating
/// a linear colour pulls its weaker channels down, which is what left recolours of the already
/// mid-dark atlas regions dimmer than the vendored art. Band values also read as an artist
/// means them here: 0.9 is bone, 0.5 is a bruise.
///
/// Nothing here writes ALPHA. A spatial shader that touches it is compiled into the
/// transparent pipeline, and a transparent body casts no shadow — which is exactly how a
/// recoloured skeleton first came out looking like it was made of glass and standing on
/// nothing.

const float GAMMA = 2.2;

uniform sampler2D albedo_tex : source_color, hint_default_white,
	filter_linear_mipmap_anisotropic, repeat_disable;
/// The source material's own albedo colour. Not every part is textured — the KayKit eyes are
/// flat-coloured — and those still have to take the band with the rest of the body.
uniform vec4 albedo_base : source_color = vec4(1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
/// The source's emission, flattened to a strength. The KayKit eye sockets are the only
/// emitters in the roster, and a recolour that drops their glow throws away most of what makes
/// a skeleton read as a threat rather than as a toy.
uniform float emission_strength = 0.0;

/// Where the band sits on the wheel, in turns.
instance uniform float band_hue = 0.0;
/// How much of the source's own hue spread survives around `band_hue`. Not zero: the KayKit
/// bone, rags and steel are three hues on one texture, and flattening them to one makes a body
/// read as a single moulded plastic shape.
instance uniform float band_hue_keep = 0.12;
/// Output saturation where the source is grey, and where it is fully vivid.
instance uniform float band_sat_low = 0.0;
instance uniform float band_sat_high = 0.5;
/// Output value where the source is black, and where it is white.
instance uniform float band_value_low = 0.1;
instance uniform float band_value_high = 0.8;
/// What this band's emissive parts glow.
instance uniform vec3 band_ember = vec3(1.0);

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

/// `src` moved most of the way to `target`, the short way round the wheel. Keeping a fraction
/// of the distance rather than snapping preserves the order of the source's hues, so a body's
/// rags stay a different colour from its bones inside the one band.
float hue_toward(float src, float target, float keep) {
	float delta = fract(src - target + 0.5) - 0.5;
	return fract(target + delta * keep);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_base;
	vec3 gamma = pow(clamp(tex.rgb, 0.0, 1.0), vec3(1.0 / GAMMA));
	vec3 hsv = rgb_to_hsv(gamma);
	hsv.x = hue_toward(hsv.x, band_hue, band_hue_keep);
	hsv.y = clamp(mix(band_sat_low, band_sat_high, hsv.y), 0.0, 1.0);
	hsv.z = clamp(mix(band_value_low, band_value_high, hsv.z), 0.0, 1.0);
	ALBEDO = pow(hsv_to_rgb(hsv), vec3(GAMMA));
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	EMISSION = band_ember * emission_strength;
}
