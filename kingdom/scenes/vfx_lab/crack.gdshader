shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Ground crack / scorch / wet decal on a quad lying on the floor (no Decal node: cheaper on mobile).
// mode 0 = cracks (dark with warm glow), 1 = scorch (soot disc), 2 = wet ring
uniform int mode = 0;
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.07, 0.045, 0.03);
uniform vec3 glow : source_color = vec3(1.0, 0.55, 0.15);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = 0.0;
	vec3 col = tint;
	if (mode == 0) {
		float w = abs(vnoise(p * 6.0 + 1.7) - 0.5);
		float crack = 1.0 - smoothstep(0.02, 0.075, w);
		a = crack * smoothstep(1.0, 0.55, d) * step(d, grow * 1.05);
		col = mix(tint, glow, smoothstep(0.02, 0.0, w) * 0.4);
	} else if (mode == 1) {
		float n = vnoise(p * 5.0);
		a = smoothstep(grow * 0.95, grow * 0.55 - 0.1, d + (n - 0.5) * 0.35) * 0.75;
	} else {
		float ring = smoothstep(0.08, 0.0, abs(d - grow * 0.9));
		a = ring * (1.0 - grow * 0.6);
		col = tint;
	}
	ALBEDO = col;
	ALPHA = a * fade;
}
