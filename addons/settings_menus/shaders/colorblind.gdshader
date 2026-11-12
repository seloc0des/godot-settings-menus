shader_type canvas_item;

// Colorblind filter, drawn over the whole screen by the Settings autoload.
//
// Daltonize: work out what a player with this kind of colour blindness sees, take
// the difference between that and the real picture, and move the difference into
// colours they can still tell apart. A simulation alone would show a designer what
// is lost; this gives the player some of it back.
//
// mode: 0 none, 1 protanopia (red), 2 deuteranopia (green), 3 tritanopia (blue).
// The same order as Settings.COLORBLIND_FILTERS.
//
// hdr_linear: the project has HDR 2D on, so the screen holds linear light and can
// go past 1.0 for glow. The correction is worked out on the colours as shown, then
// handed back linear and unclamped at the top, so highlights still bloom.

uniform int mode = 0;
uniform bool hdr_linear = false;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

vec3 linear_to_srgb(vec3 c) {
	return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 rgb_to_lms(vec3 c) {
	return vec3(
		dot(c, vec3(17.8824, 43.5161, 4.11935)),
		dot(c, vec3(3.45565, 27.1554, 3.86714)),
		dot(c, vec3(0.0299566, 0.184309, 1.46709)));
}

vec3 lms_to_rgb(vec3 lms) {
	return vec3(
		dot(lms, vec3(0.0809444479, -0.130504409, 0.116721066)),
		dot(lms, vec3(-0.0102485335, 0.0540193266, -0.113614708)),
		dot(lms, vec3(-0.000365296938, -0.00412161469, 0.693511405)));
}

// What the missing cone type would have reported, rebuilt from the other two.
vec3 as_seen(vec3 lms) {
	if (mode == 1) {
		return vec3(2.02344 * lms.y - 2.52581 * lms.z, lms.y, lms.z);
	}
	if (mode == 2) {
		return vec3(lms.x, 0.494207 * lms.x + 1.24827 * lms.z, lms.z);
	}
	return vec3(lms.x, lms.y, -0.395913 * lms.x + 0.801109 * lms.y);
}

void fragment() {
	vec3 screen = texture(screen_texture, SCREEN_UV).rgb;
	if (mode == 0) {
		COLOR = vec4(screen, 1.0);
	} else {
		vec3 c = hdr_linear ? linear_to_srgb(max(screen, 0.0)) : screen;
		vec3 lost = c - lms_to_rgb(as_seen(rgb_to_lms(c)));
		vec3 shift = vec3(0.0, 0.7 * lost.r + lost.g, 0.7 * lost.r + lost.b);
		vec3 fixed_c = max(c + shift, 0.0);
		COLOR = vec4(hdr_linear ? srgb_to_linear(fixed_c) : min(fixed_c, 1.0), 1.0);
	}
}
