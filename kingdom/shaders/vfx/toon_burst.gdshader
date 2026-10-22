shader_type spatial;
// 1 s ease-out ring / burst (VIDEO_STUDY_B2 #1 step 4): a flat quad, `progress` 0..1 is driven by an ease-out tween.
// The ring radius follows progress, its thickness shrinks with it, its edge is cut by noise (hard, toon), and a
// white-hot core disc shows in the first frames. Unlit, one draw call per ring.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.7, 0.15, 0.05, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.22;
uniform float energy = 2.4;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float teeth = 5.0;       // noise repeats round the ring
uniform float seed = 0.0;
uniform float steps = 4.0;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float ang = atan(q.y, q.x) / 6.2831853 + 0.5;
	float n = texture(noise_tex, vec2(ang * teeth, d * 1.5 + seed)).r;
	float r = progress;
	float th = thickness * (1.0 - 0.75 * progress) * (0.45 + 0.9 * n);
	float ring = step(abs(d - r * 0.92), th);
	float inner = step(abs(d - r * 0.92), th * 0.45);
	float core = (1.0 - smoothstep(0.0, 0.28, progress)) * step(d, 0.5 * (1.0 - progress * 2.0) + 0.1);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, inner);
	col = mix(col, core_color.rgb, clamp(core + inner * 0.35, 0.0, 1.0));
	ALBEDO = col * energy;
	float f = floor(fade * steps + 0.5) / steps;
	ALPHA = clamp(ring + core, 0.0, 1.0) * f * step(d, 1.0);
}
