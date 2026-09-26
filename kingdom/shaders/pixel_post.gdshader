shader_type canvas_item;
// Pixel-art finish for the low-resolution 3D render: limits colour depth with a
// light ordered dither so gradients band like hand-made pixel art.

uniform float color_levels : hint_range(4.0, 64.0) = 20.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.35;
uniform float saturation : hint_range(0.0, 2.0) = 0.92;
// The Compatibility renderer already writes sRGB into the SubViewport, and the
// canvas converts again when drawing it; undo one conversion so colours match.
uniform bool undo_double_srgb = true;

const mat4 BAYER = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0));

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (undo_double_srgb) {
		c.rgb = mix(c.rgb / 12.92, pow((c.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, c.rgb));
	}
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(luma), c.rgb, saturation);
	ivec2 p = ivec2(mod(floor(UV / TEXTURE_PIXEL_SIZE), 4.0));
	float threshold = (BAYER[p.x][p.y] / 16.0 - 0.5) * dither_strength;
	c.rgb = floor(c.rgb * color_levels + 0.5 + threshold) / color_levels;
	COLOR = vec4(c.rgb, 1.0);
}
