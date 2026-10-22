// Blink lid patch for a painted (Meshy) face: samples the upper-lid skin of the hero atlas (UV), soft border and a dark
// lash line on the closing edge from the lid-local UV2 (0..1 across, 0 = lower edge .. 1 = crease). Only visible while
// blinking (HeroFaceDriver), so the alpha pass costs ~nothing.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec3 c = texture(albedo_tex, UV, 2.0).rgb * tint.rgb * vec3(1.02, 0.96, 0.93);
	float lash = 1.0 - smoothstep(0.0, 0.22, UV2.y);
	c = mix(c, vec3(0.1, 0.06, 0.05), lash * 0.8);
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.25, UV2.x) * smoothstep(1.0, 0.75, UV2.x) * smoothstep(1.0, 0.7, UV2.y);
	ROUGHNESS = 0.5;
	SPECULAR = 0.3;
}
