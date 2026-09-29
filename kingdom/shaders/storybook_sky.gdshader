shader_type sky;
// The captured Poly Haven sky, graded toward the art reference: a saturated
// storybook blue overhead with bright white cumulus, lighter haze at the horizon.
uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform float saturation = 1.7;
uniform vec3 zenith_tint : source_color = vec3(0.78, 0.9, 1.12);
uniform float energy = 1.0;

void sky() {
	vec3 c = texture(panorama, SKY_COORDS).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// Saturate the blue sky but keep clouds (bright, low-chroma) white.
	float cloud = smoothstep(0.55, 0.95, l / max(max(c.r, max(c.g, c.b)), 1e-4));
	vec3 sat = mix(vec3(l), c, saturation);
	c = mix(sat, c, cloud * 0.6);
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	c *= mix(vec3(1.0), zenith_tint, smoothstep(0.02, 0.6, up));
	COLOR = max(c, vec3(0.0)) * energy;
}
