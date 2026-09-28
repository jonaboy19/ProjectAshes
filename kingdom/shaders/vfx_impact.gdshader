// Impact frame: a brief screen-space burst of radial speed lines around the hit
// point (manga / donghua style), with a clear centre and a thin flash ring.
// Drawn by a full-screen ColorRect on a CanvasLayer, for about 0.1 s.
shader_type canvas_item;
render_mode blend_add;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.777;
uniform float strength = 1.0;
uniform float progress = 0.0;   // 0..1 over the frame's life
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// Thin speed lines: high-frequency angular noise, only the brightest ridges.
	float l1 = texture(noise_tex, vec2(ang * 1.9099 + seed, seed * 0.37)).b;
	float l2 = texture(noise_tex, vec2(ang * 3.8197 - seed, 0.5 + seed)).b;
	float lines = smoothstep(0.78, 0.97, max(l1, l2 * 0.95));
	// Clear centre that opens up; lines thicken toward the screen edge.
	float clear = smoothstep(0.18 + progress * 0.3, 0.6 + progress * 0.3, r);
	float ring = exp(-pow((r - (0.06 + progress * 0.6)) / 0.012, 2.0)) * (1.0 - progress);
	float flash = exp(-r * r * 12.0) * (1.0 - progress) * 0.25;
	float a = (lines * clear * 0.42 + ring * 0.5 + flash) * strength * (1.0 - progress * progress);
	COLOR = vec4(tint.rgb * a, 1.0);
}
