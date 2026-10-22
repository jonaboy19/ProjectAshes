shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_disabled;
// EARTH SPIKES: one MultiMesh of low-poly rock spikes (one draw call). INSTANCE_CUSTOM per spike:
//   x = start delay (0..1 of the effect timeline), y = height scale, z = width scale, w = lean (radians).
// The rise (ease-out-back overshoot), the hold and the sink are computed here from the global `t` uniform, so
// the CPU only sets one float per frame.
uniform float t : hint_range(0.0, 1.0) = 0.0;       // effect timeline 0..1
uniform float rise_time = 0.18;
uniform float sink_start = 0.72;
uniform vec3 rock_a : source_color = vec3(0.72, 0.6, 0.44);
uniform vec3 rock_b : source_color = vec3(0.46, 0.36, 0.27);
uniform vec3 moss : source_color = vec3(0.34, 0.4, 0.2);
varying float v_h;
varying vec3 v_obj;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float back_out(float x) {
	float c1 = 1.9; float c3 = c1 + 1.0;
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0);
}
void vertex() {
	float delay = INSTANCE_CUSTOM.x;
	float up = back_out(clamp((t - delay) / rise_time, 0.0, 1.0));
	float down = smoothstep(sink_start + delay * 0.25, 1.0, t);
	float h = max(up * (1.0 - down), 0.0001);
	v_h = VERTEX.y;
	v_obj = VERTEX;
	vec3 p = VERTEX;
	p.xz *= INSTANCE_CUSTOM.z * mix(0.55, 1.0, clamp(h, 0.0, 1.0));
	p.y *= INSTANCE_CUSTOM.y * h;
	float lean = INSTANCE_CUSTOM.w * clamp(p.y, 0.0, 3.0) * 0.35;
	p.x += lean;
	VERTEX = p;
}
void fragment() {
	float n = vnoise(v_obj * 5.0 + 3.0) * 0.6 + vnoise(v_obj * 12.0) * 0.4;
	vec3 col = mix(rock_b, rock_a, smoothstep(0.25, 0.75, n));
	col = mix(col, rock_a * 1.25, smoothstep(0.55, 1.0, v_h) * 0.5);     // lighter, fractured tip
	col = mix(col, moss, smoothstep(0.35, 0.0, v_h) * 0.55 * smoothstep(0.4, 0.7, n)); // mossy foot
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
