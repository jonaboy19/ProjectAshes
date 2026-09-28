// Rain splash ripples: small horizontal quads emitted on a ring around the camera
// by scripts/world/weather.gd. Each one draws two expanding rings over its short
// life (INSTANCE_CUSTOM.y = lifetime progress from ParticleProcessMaterial).
// Unshaded alpha, no depth write: a few dozen quads, a handful of ALU per pixel.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.85, 0.9, 1.0, 0.45);
uniform float ring_width = 0.09;

varying float v_life;

void vertex() {
	v_life = INSTANCE_CUSTOM.y;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;          // 0 centre .. 1 quad edge
	float life = clamp(v_life, 0.0, 1.0);
	float outer = 1.0 - smoothstep(0.0, ring_width, abs(r - life));
	float inner = 1.0 - smoothstep(0.0, ring_width, abs(r - life * 0.55));
	float a = max(outer, inner * 0.6) * (1.0 - life) * step(r, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a;
}
