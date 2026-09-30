shader_type spatial;
// Soft glowing ring on the ground under an Ashsight ghost: makes the figure readable at a
// distance and at phone size. A gentle pulse, warm ember colour, no textures.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ember_color : source_color = vec4(1.0, 0.64, 0.30, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	// a thin ember ring with a soft glow inside: a hint of ground contact, not a target marker
	float ring = smoothstep(0.62, 0.8, d) * (1.0 - smoothstep(0.8, 0.92, d));
	float core = (1.0 - smoothstep(0.0, 0.8, d)) * 0.22;
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = ember_color.rgb * 1.2;
	ALPHA = alpha * (ring * 0.6 + core) * pulse;
}
