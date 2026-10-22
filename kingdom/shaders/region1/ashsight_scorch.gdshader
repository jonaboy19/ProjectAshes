shader_type spatial;
// Scorched building for the Ashsight farm sandbox: the building's own painted albedo, charred
// from the base and the roof line with soot noise, ash speckle and a few slow ember cracks.
// (Sandbox dressing only; not used by the ghosts.)
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_tex = true;
uniform bool use_vertex_color = true;
uniform float scorch : hint_range(0.0, 1.0) = 0.6;
uniform float seed = 0.0;
uniform vec3 ember : source_color = vec3(1.0, 0.45, 0.14);

varying vec3 wp;
varying vec3 lp;

float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float v3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX;
}

void fragment() {
	vec3 a = albedo_color.rgb;
	if (use_tex) {
		a *= texture(albedo_tex, UV).rgb;
	}
	if (use_vertex_color) {
		a *= COLOR.rgb;
	}
	float n = v3(wp * 1.1 + seed);
	float m = v3(wp * 4.3 + seed * 2.0);
	float low = 1.0 - smoothstep(0.0, 3.2, lp.y);
	float top = smoothstep(3.5, 8.5, lp.y);
	float c = clamp(scorch * (0.25 + 0.95 * n + 0.6 * low + 0.35 * top) - 0.15 + (m - 0.5) * 0.4, 0.0, 1.0);
	vec3 charcoal = vec3(0.075, 0.062, 0.058) * (0.7 + 0.7 * m);
	a = mix(a, charcoal, smoothstep(0.25, 0.85, c) * 0.9);
	a += vec3(0.42, 0.40, 0.38) * step(0.83, m) * c * 0.35;   // ash speckle
	ALBEDO = a;
	ROUGHNESS = 1.0;
	float crack = smoothstep(0.016, 0.0, abs(v3(wp * 2.6 + seed * 3.0) - 0.5)) * smoothstep(0.7, 0.95, c);
	float pulse = 0.55 + 0.45 * sin(TIME * 1.3 + wp.x * 0.7 + wp.y * 1.9);
	EMISSION = ember * crack * pulse * 0.55;
}
