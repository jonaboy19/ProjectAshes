shader_type spatial;
// Sandbox ground for the Ashsight farm scene: painterly meadow, dirt road, trampled yard,
// plough rows and scorched earth, all from vertex colour (a = plough-row mask) plus two
// octaves of value noise for a hand-painted mottle and blade grain. Lit, no textures.
render_mode cull_back, diffuse_burley, specular_disabled;

varying vec3 wp;

float h2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float mottle = n2(wp.xz * 0.28) * 0.6 + n2(wp.xz * 0.9 + 4.0) * 0.4;
	float grain = n2(wp.xz * vec2(9.0, 4.5));
	float patch = n2(wp.xz * 0.06 + 11.0);
	vec3 a = base * (0.7 + 0.6 * mottle) * (0.88 + 0.24 * grain);
	a = mix(a, a * vec3(1.18, 1.05, 0.7), smoothstep(0.55, 0.85, patch) * 0.5);   // sun-dried patches
	// plough rows in the field mask
	float rows = 0.5 + 0.5 * sin(wp.x * 3.4 + n2(wp.xz * 0.4) * 2.0);
	a = mix(a, a * (0.7 + 0.5 * rows), COLOR.a);
	ALBEDO = a;
	ROUGHNESS = 1.0;
}
