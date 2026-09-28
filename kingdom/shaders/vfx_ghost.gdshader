// Dash afterimage: a frozen copy of the character drawn as a fresnel-rimmed,
// additive silhouette with horizontal scan bands, fading and dissolving
// (rim idea from VFEZ-godot color_rim, rewritten).
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float energy = 2.0;
uniform float fade = 1.0;
uniform float rim_power = 2.2;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	float bands = 0.75 + 0.25 * sin(v_world.y * 18.0 - TIME * 10.0);
	// Clean silhouette until half faded, then it frays upward from the feet.
	float n = texture(noise_tex, v_world.xz * 0.25 + vec2(0.0, v_world.y * 0.3)).r;
	float fray = clamp((0.5 - fade) * 2.0, 0.0, 1.0);
	float keep = smoothstep(0.0, 0.2, n + 0.25 - fray * 1.2);
	float a = (0.22 + rim * 0.9) * bands * keep * fade;
	ALBEDO = mix(tint.rgb, hot.rgb, rim) * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
