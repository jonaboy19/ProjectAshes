shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;
// FIRE BLAST: an erupting cone/tongue of flame built in the vertex shader (tube along -Z that widens), with
// a scrolling-noise dissolve in the fragment shader. Additive, so no sorting trouble and cheap blending.
// The MIT sandbox ray-marches a density field; here one noise lookup per pixel on a shell is the mobile version.
uniform float length_m = 5.0;
uniform float base_radius = 0.28;
uniform float spread = 1.25;                         // end radius = base_radius * (1 + spread * 3)
uniform float progress : hint_range(0.0, 1.0) = 1.0; // how far the front has travelled
uniform float life : hint_range(0.0, 1.0) = 1.0;     // 1 = full, 0 = burnt out
uniform float core_mix : hint_range(0.0, 1.0) = 0.0; // 1 = hot white-yellow inner shell, 0 = orange outer
uniform vec3 c_core : source_color = vec3(1.0, 0.95, 0.65);
uniform vec3 c_mid : source_color = vec3(1.0, 0.5, 0.1);
uniform vec3 c_edge : source_color = vec3(0.7, 0.12, 0.03);
uniform float flicker = 8.0;
varying float v_u;
varying float v_a;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	float u = UV.x;                // 0 at the hand, 1 at the front
	float a = UV.y * 6.2831853;
	float len = length_m * progress * u;
	float rr = base_radius * (1.0 + spread * 3.0 * pow(u, 1.3)) * mix(1.0, 0.62, core_mix);
	float wob = 1.0 + 0.18 * sin(u * 11.0 - TIME * flicker + a * 2.0) + 0.1 * sin(a * 3.0 + TIME * 5.0);
	// lick upwards (buoyancy) toward the front
	float lift = pow(u, 2.0) * 0.45 * progress;
	VERTEX = vec3(cos(a) * rr * wob, sin(a) * rr * wob + lift, -len);
	v_u = u;
	v_a = UV.y;
}
void fragment() {
	float n1 = vnoise(vec3(v_a * 6.0, v_u * 7.0 - TIME * flicker * 0.55, TIME * 1.3));
	float n2 = vnoise(vec3(v_a * 13.0 + 3.0, v_u * 15.0 - TIME * flicker, TIME * 2.1));
	float n = n1 * 0.65 + n2 * 0.35;
	float heat = clamp(1.0 - v_u * 0.9 + (n - 0.5) * 0.7 - (1.0 - life) * 0.9 + core_mix * 0.35, 0.0, 1.0);
	float dissolve = smoothstep(0.18, 0.5, n + life * 0.55 - v_u * 0.55);
	vec3 col = mix(c_edge, c_mid, smoothstep(0.1, 0.5, heat));
	col = mix(col, c_core, smoothstep(0.55, 0.95, heat));
	float a = dissolve * smoothstep(0.0, 0.07, v_u) * (1.0 - smoothstep(0.82, 1.0, v_u)) * life;
	ALBEDO = col * (0.75 + heat * 0.55);
	ALPHA = clamp(a, 0.0, 1.0) * mix(0.8, 0.5, core_mix);
}
