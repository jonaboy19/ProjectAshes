shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Storybook waterfall ribbon (Region1Look, docs/regions/LOOK_R1.md): painted white-water streaks
// scrolling down the ribbon (UV.y = metres along / width), a turquoise core, bright foam edges.
// No textures: a few layered value-noise bands. Also used for the foam puff at the plunge pool.

uniform vec3 core_color : source_color = vec3(0.36, 0.72, 0.82);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform float speed = 1.35;
uniform float layer_alpha = 1.0;   // back / front sheets of the pass-3 layered falls

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	// Vertical streaks: stretched noise scrolling downward (UV.y grows downstream).
	float s1 = vnoise(vec2(uv.x * 9.0, uv.y * 1.2 - t * 1.6));
	float s2 = vnoise(vec2(uv.x * 23.0 + 3.1, uv.y * 2.6 - t * 2.4));
	float streak = smoothstep(0.45, 0.8, s1 * 0.65 + s2 * 0.45);
	float edge = smoothstep(0.32, 0.5, abs(uv.x - 0.5));
	float foam = clamp(streak + edge * 0.8, 0.0, 1.0);
	vec3 col = mix(core_color, foam_color, foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.15, 0.6, foam);
	SPECULAR = 0.6;
	EMISSION = col * 0.12;
	float fringe = 1.0 - smoothstep(0.44, 0.5, abs(uv.x - 0.5)) * (0.6 + 0.4 * vnoise(vec2(uv.y * 3.0 - t * 2.0, uv.x)));
	ALPHA = clamp(fringe * mix(0.82, 1.0, foam) * layer_alpha, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.35 * layer_alpha;
}
