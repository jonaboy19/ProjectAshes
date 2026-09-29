// Original work written for Rising Ashes (no third-party code). Same licence as the project.
// Replaces the godotshaders.com "fluffy tree leaves" candidate (site blocked automated licence verification).
// Fluffy storybook foliage for blob/card canopies: alpha-scissor (no sorting), warm yellow-green rim on the
// lit side, cool blue-violet underside, wind sway. A noise texture gives the leafy cut-out edge.
// Mobile: 1 texture tap, cutout, no blending. Cheap.
shader_type spatial;
render_mode cull_back, depth_prepass_alpha, diffuse_lambert;
uniform sampler2D leaf_mask : filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.30, 0.62, 0.16, 1.0);
uniform vec4 rim_color : source_color = vec4(0.85, 0.90, 0.30, 1.0);
uniform vec4 shade_color : source_color = vec4(0.16, 0.30, 0.38, 1.0);
uniform float cutoff : hint_range(0.0, 1.0) = 0.3;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.4;
uniform float mask_scale = 2.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = wpos.x * 0.7 + wpos.z * 0.5;
	VERTEX += vec3(sin(TIME * wind_speed + ph), 0.3 * sin(TIME * wind_speed * 1.3 + ph), cos(TIME * wind_speed * 0.8 + ph)) * wind_strength;
}

void fragment() {
	float m = texture(leaf_mask, UV * mask_scale + wpos.xz * 0.05).r;
	if (m < cutoff) {
		discard;
	}
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 c = mix(shade_color.rgb, base_color.rgb, smoothstep(0.15, 0.85, up));
	c = mix(c, rim_color.rgb, clamp(rim * 0.9, 0.0, 1.0) * up);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
