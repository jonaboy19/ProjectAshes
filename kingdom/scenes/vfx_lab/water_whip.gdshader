shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled, shadows_disabled;
// WATER WHIP: a tube that lives on a cubic Bezier (p0..p3, local space) and is built entirely in the vertex
// shader, so the CPU does nothing per frame. The mesh only carries (u along, angle around) in UV.
// Inspired by the *idea* of the MIT bending sandbox (tube hull + swell + foam cells); code written from scratch.
uniform vec3 p0 = vec3(0.0, 1.0, 0.0);
uniform vec3 p1 = vec3(0.0, 2.4, -1.5);
uniform vec3 p2 = vec3(1.6, 0.2, -3.0);
uniform vec3 p3 = vec3(0.0, 0.6, -5.0);
uniform float head : hint_range(0.0, 1.0) = 1.0;   // position of the head along the curve
uniform float tail : hint_range(0.0, 1.0) = 0.0;   // position of the tail (grows to head at the end)
uniform float radius = 0.3;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float swell_amp = 0.35;
uniform vec3 deep : source_color = vec3(0.06, 0.26, 0.6);
uniform vec3 shallow : source_color = vec3(0.35, 0.8, 0.98);
uniform vec3 foam : source_color = vec3(0.92, 0.98, 1.0);
varying float v_u;
varying float v_ripple;
varying vec3 v_n;

vec3 bez(float t) {
	float s = 1.0 - t;
	return s * s * s * p0 + 3.0 * s * s * t * p1 + 3.0 * s * t * t * p2 + t * t * t * p3;
}
vec3 bez_d(float t) {
	float s = 1.0 - t;
	return 3.0 * s * s * (p1 - p0) + 6.0 * s * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	float u = UV.x;
	float a = UV.y * 6.2831853;
	float t = mix(tail, head, u);
	vec3 c = bez(t);
	vec3 tg = normalize(bez_d(t) + vec3(0.0001));
	vec3 side = normalize(cross(tg, vec3(0.0, 1.0, 0.0)) + vec3(0.0001, 0.0, 0.0));
	vec3 up = cross(side, tg);
	// travelling swell along the body: a slow wave that makes it read as a living rope of water
	float sw = sin(t * 14.0 - TIME * 9.0) * swell_amp;
	vec3 n = side * cos(a) + up * sin(a);
	// thin tail, fat head (bulb), pinched at both ends
	float prof = (0.45 + 0.55 * pow(u, 0.7)) * (1.0 + 0.55 * smoothstep(0.8, 0.97, u)) * smoothstep(0.0, 0.06, u) * sqrt(max(1.0 - pow(max(u - 0.9, 0.0) / 0.1, 2.0), 0.0));
	float r = radius * prof * (1.0 + sw) * mix(0.2, 1.0, smoothstep(0.0, 0.15, fade));
	c += up * sw * radius * 0.5;
	VERTEX = c + n * r;
	NORMAL = n;
	v_u = u;
	v_n = n;
	v_ripple = vnoise(vec2(u * 18.0 - TIME * 6.0, UV.y * 4.0));
}
void fragment() {
	vec3 N = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(N, normalize(VIEW)), 0.0, 1.0), 2.2);
	float streak = vnoise(vec2(v_u * 26.0 - TIME * 11.0, UV.y * 6.0));
	float foam_m = smoothstep(0.78, 0.98, streak * 0.75 + fres * 0.35 + smoothstep(0.9, 1.0, v_u) * 0.35) * 0.85;
	vec3 col = mix(deep, shallow, clamp(fres * 0.7 + v_ripple * 0.5 + 0.12, 0.0, 1.0));
	col = mix(col, foam, foam_m);
	col += vec3(0.7, 0.9, 1.0) * pow(max(dot(N, normalize(vec3(0.4, 0.8, 0.5))), 0.0), 14.0) * 0.5;   // fake sun glint
	ALBEDO = col;
	ALPHA = (0.62 + 0.38 * fres + foam_m * 0.3) * fade * smoothstep(0.0, 0.12, v_u);
}
