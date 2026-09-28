// Water rings for a fish jump (scripts/world/ambient_fx.gd): one flat quad on
// the surface; `age` 0..1 (tweened) draws an expanding, fading pair of rings at
// `ring_a` (where the fish left the water) and, from `delay`, at `ring_b` (where
// it went back in). Unshaded, alpha-blended, no depth write.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float age = 1.0;
uniform float delay = 0.3;
uniform vec2 ring_a = vec2(0.0, -0.6);   // quad-local metres
uniform vec2 ring_b = vec2(0.0, 0.6);
uniform float quad_size = 4.0;
uniform vec4 tint : source_color = vec4(0.9, 0.95, 1.0, 0.7);

float rings(vec2 p, vec2 c, float t) {
	if (t <= 0.0) return 0.0;
	float d = length(p - c);
	float r1 = t * 1.4;
	float r2 = t * 0.8;
	float w = 0.04 + t * 0.05;
	float k = 1.0 - smoothstep(0.0, w, abs(d - r1));
	k += 0.6 * (1.0 - smoothstep(0.0, w, abs(d - r2)));
	float foam = (1.0 - smoothstep(0.0, 0.18 + t * 0.2, d)) * (1.0 - smoothstep(0.0, 0.35, t));
	return (k + foam) * (1.0 - t);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * quad_size;
	float a = rings(p, ring_a, age / (1.0 - delay));
	float b = rings(p, ring_b, (age - delay) / (1.0 - delay));
	ALBEDO = tint.rgb;
	ALPHA = clamp((a + b) * tint.a, 0.0, 1.0);
}
