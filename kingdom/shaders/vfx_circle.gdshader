// Procedural rune circle drawn on a flat ground quad (UV 0..1 across its width).
// Rings, a counter-rotating star polygon {sides/skip}, a band of pseudo-glyphs,
// radial ticks and element accents (water ripples, wind spiral arms). It draws
// itself on along an angular sweep (`progress` 0..1) and fades with `fade`.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 edge : source_color = vec4(0.6, 0.1, 0.02, 1.0);
uniform float energy = 2.5;
uniform float progress = 1.0;
uniform float fade = 1.0;
uniform int sides = 6;
uniform int skip = 2;
uniform float spin = 0.25;      // turns per second of the outer band
uniform float waves = 0.0;      // water: ripple rings
uniform float spiral = 0.0;     // wind: spiral arms
uniform float glyph_seed = 1.0;
uniform float fill = 0.12;      // faint disc glow under the lines


float line(float d, float w) {
	float aa = fwidth(d) * 1.2 + 1e-4;
	return smoothstep(w + aa, w, abs(d)) + exp(-pow(d / (w * 4.0), 2.0)) * 0.35;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 rot(vec2 p, float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
}

// A row of little glyphs in the band between r0 and r1 (angle in turns).
float glyphs(vec2 p, float r0, float r1, float count, float turn) {
	float r = length(p);
	float a = fract(atan(p.y, p.x) / TAU + turn);
	float id = floor(a * count);
	vec2 q = vec2(fract(a * count), (r - r0) / (r1 - r0));
	if (q.y < 0.0 || q.y > 1.0) return 0.0;
	float h = hash(vec2(id, glyph_seed));
	float g = 0.0;
	float w = 0.07;
	// Stroke vocabulary: vertical bar, bar top/bottom, diagonal, dot, hook.
	g += step(0.3, h) * smoothstep(w, 0.0, abs(q.x - 0.5)) * step(0.15, q.y) * step(q.y, 0.85);
	g += step(fract(h * 7.0), 0.5) * smoothstep(w, 0.0, abs(q.y - 0.8)) * step(0.25, q.x) * step(q.x, 0.75);
	g += step(0.5, fract(h * 13.0)) * smoothstep(w, 0.0, abs(q.y - 0.2)) * step(0.2, q.x) * step(q.x, 0.8);
	g += step(0.6, fract(h * 29.0)) * smoothstep(w, 0.0, abs((q.x - 0.5) - (q.y - 0.5) * 0.6)) * step(0.2, q.y) * step(q.y, 0.8);
	g += step(0.7, fract(h * 41.0)) * smoothstep(0.12, 0.05, length(q - vec2(0.5, 0.5)));
	return clamp(g, 0.0, 1.0) * step(0.08, q.x) * step(q.x, 0.92);
}

// Distance to a regular star polygon {n/k} with circumradius R.
float star(vec2 p, float R, int n, int k) {
	float d = 1e3;
	float fn = float(n);
	float apo = R * cos(3.14159265 * float(k) / fn);
	for (int i = 0; i < 12; i++) {
		if (i >= n) break;
		float a = (float(i) + 0.5) * TAU / fn;
		vec2 dir = vec2(cos(a), sin(a));
		float s = abs(dot(p, dir) - apo);
		// Clip each edge to the segment inside the circumcircle.
		vec2 foot = dir * apo;
		vec2 along = vec2(-dir.y, dir.x);
		float half_len = sqrt(max(R * R - apo * apo, 0.0));
		float t = dot(p - foot, along);
		s = max(s, abs(t) - half_len);
		d = min(d, s);
	}
	return d;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.02) discard;
	float t = TIME * spin;
	float a01 = fract(atan(p.y, p.x) / TAU + 0.25);

	float i = 0.0;
	// Rings
	i += line(r - 0.96, 0.012);
	i += line(r - 0.90, 0.006) * 0.8;
	i += line(r - 0.72, 0.01);
	i += line(r - 0.34, 0.008);
	i += line(r - 0.28, 0.005) * 0.7;
	// Glyph bands (outer turns one way, inner the other)
	i += glyphs(p, 0.74, 0.88, 28.0, t) * 0.95;
	i += glyphs(p, 0.29, 0.335, 12.0, -t * 1.7) * 0.6;
	// Ticks between the outer rings
	float ticks = smoothstep(0.35, 0.0, abs(fract(a01 * 56.0 + t * 56.0 * 0.0) - 0.5) * 2.0 - 0.6);
	i += ticks * step(0.9, r) * step(r, 0.96) * 0.5;
	// Star polygon, counter-rotating
	vec2 ps = rot(p, -t * TAU * 0.6);
	i += line(star(ps, 0.72, sides, skip), 0.01) * 1.1;
	// Inner polygon {n/1} rotating forward
	vec2 pi2 = rot(p, t * TAU);
	i += line(star(pi2, 0.34, sides, 1), 0.008) * 0.8;
	// Element accents
	if (waves > 0.0) {
		float wv = sin((r * 14.0 - TIME * 3.0)) * 0.5 + 0.5;
		i += waves * pow(wv, 12.0) * step(0.36, r) * step(r, 0.7) * 0.6;
	}
	if (spiral > 0.0) {
		float arm = fract(a01 * 5.0 + r * 1.6 - TIME * 0.8);
		i += spiral * smoothstep(0.08, 0.0, abs(arm - 0.5) - 0.02) * step(0.36, r) * step(r, 0.7) * 0.7;
	}
	// Faint swirling disc fill
	float n = texture(noise_tex, rot(p, TIME * 0.2) * 0.35 + vec2(TIME * 0.02)).r;
	i += fill * smoothstep(1.0, 0.2, r) * (0.5 + n);
	// Centre glow
	i += exp(-r * r * 30.0) * 0.8;

	// Draw-on sweep, then a slow breathing pulse.
	float sweep = progress * 1.35 - (a01 * 0.7 + (1.0 - r) * 0.3);
	float reveal = smoothstep(0.0, 0.04, sweep);
	float bright_edge = exp(-pow(sweep / 0.035, 2.0)) * step(progress, 0.999);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	float v = clamp(i * reveal * pulse + bright_edge * 0.8 * step(r, 0.98), 0.0, 1.6);

	vec3 c = mix(edge.rgb, tint.rgb, smoothstep(0.0, 0.5, v));
	c = mix(c, hot.rgb, smoothstep(0.7, 1.3, v));
	ALBEDO = c * energy;
	ALPHA = clamp(v, 0.0, 1.0) * fade * tint.a;
}
