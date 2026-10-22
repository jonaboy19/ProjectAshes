shader_type spatial;
// Ashsight world grade (HIGH / MEDIUM): one full-screen pass that drains the world to a warm
// sepia-ember memory: partial desaturation, a warm tint, a soft warm-dark vignette and a few
// layers of drifting ash flakes. Drawn BEFORE the ghosts (low render_priority), so the ghosts
// keep their own colours on top of the graded world. `amount` 0..1 eases it in and out.
// Storybook, not horror: the colour is drained, never blackened.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.55;
uniform vec3 warm_tint : source_color = vec3(1.0, 0.86, 0.68);   // the sepia the drained colour is poured into
uniform float warm_mix : hint_range(0.0, 1.0) = 0.62;
uniform float vignette : hint_range(0.0, 1.0) = 0.62;
uniform vec3 vignette_color : source_color = vec3(0.16, 0.07, 0.03);
uniform float contrast = 1.06;
uniform float motes : hint_range(0.0, 1.0) = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// one layer of soft drifting flakes: returns (brightness, ember mix)
vec2 flakes(vec2 uv, float aspect, float scale, float speed, float seed) {
	vec2 p = vec2(uv.x * aspect, uv.y) * scale;
	p += vec2(TIME * speed * 0.35 + sin(TIME * 0.7 + seed) * 0.25, -TIME * speed);
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	float r = h21(id + seed);
	vec2 off = vec2(h21(id + seed + 3.1), h21(id + seed + 7.7)) - 0.5;
	f -= off * 0.6;
	float sz = mix(0.022, 0.06, r);
	float d = length(f);
	float m = smoothstep(sz, sz * 0.25, d) * step(0.55, r);
	return vec2(m, step(0.86, h21(id + seed + 11.0)));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// drain the colour, then pour the luminance into a warm parchment tone (a duotone, so the
	// greens do not turn minty): the world becomes a warm memory, not a grey one
	vec3 g = mix(c, vec3(l), desaturate * amount);
	vec3 sepia = vec3(l) * warm_tint * 1.28 + vec3(0.012, 0.006, 0.0);
	g = mix(g, sepia, warm_mix * amount);
	g = (g - vec3(0.18)) * mix(1.0, contrast, amount) + vec3(0.18);
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
	float v = smoothstep(0.30, 1.05, length(d));
	g = mix(g, g * vignette_color * 3.2, clamp(v * vignette * amount, 0.0, 1.0) * 0.92);
	// ash flakes: three depths, big and slow in front, fine and quick behind
	if (motes > 0.01) {
		vec2 a = flakes(uv, aspect, 7.0, 0.05, 1.0);
		vec2 b = flakes(uv, aspect, 13.0, 0.075, 5.0);
		vec2 e = flakes(uv, aspect, 22.0, 0.11, 9.0);
		float m = clamp(a.x * 0.8 + b.x * 0.55 + e.x * 0.4, 0.0, 1.0) * amount * motes;
		vec3 ember = vec3(1.0, 0.62, 0.26) * 1.6;
		vec3 ash = vec3(0.96, 0.9, 0.82);
		float em = clamp(a.x * a.y + b.x * b.y + e.x * e.y, 0.0, 1.0);
		g = mix(g, mix(ash, ember, em), m * 0.75);
	}
	ALBEDO = g;
	ALPHA = 1.0;
}
