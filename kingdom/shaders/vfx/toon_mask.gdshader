shader_type spatial;
// Toon noise-threshold mask (docs/research/VIDEO_STUDY_B2 #1 steps 1-3):
//   baked tileable noise -> step(threshold) hard black/white mask -> swirl (the noise slides sideways more with
//   height, plus a time offset so it spins) -> emission in core / mid colours, hard-edged, no soft gradients.
// For shells (SphereMesh / CylinderMesh): UV.x runs round, UV.y runs up. One texture read, unlit.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.7, 0.15, 0.05, 1.0);
uniform float threshold : hint_range(0.0, 1.0) = 0.5;   // animate up to shrink the mask
uniform float band : hint_range(0.0, 0.5) = 0.12;        // hot core thickness above the threshold
uniform float stripes = 4.0;                             // noise repeats round the shell (integer = seamless)
uniform float swirl = 3.0;                               // sideways shift per unit height
uniform float spin = 1.0;                                // time offset speed (the "Scene Time" node)
uniform float scroll = 0.5;                              // upward drift
uniform float energy = 2.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform float rim_power = 1.8;
uniform float steps = 4.0;                               // fade is quantised to this many steps (toon)

void fragment() {
	float t = TIME + time_offset;
	vec2 p = vec2(UV.x * stripes + UV.y * swirl + t * spin, UV.y * 2.0 - t * scroll);
	float n = texture(noise_tex, p).r;
	float m = step(threshold, n);
	float c = step(threshold + band, n);
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), rim_power);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, clamp(rim * 0.6 + 0.4, 0.0, 1.0));
	col = mix(col, core_color.rgb, c);
	ALBEDO = col * energy;
	float f = floor(fade * steps + 0.5) / steps;
	ALPHA = m * f * (0.55 + 0.45 * rim + 0.4 * c);
}
