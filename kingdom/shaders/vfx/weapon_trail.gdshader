shader_type spatial;
// Weapon trail ribbon: per-vertex colour carries element tint (rgb) and age/edge fade (a).
// Premultiplied mix with a slight glow boost so it reads on bright storybook daylight
// (pure additive washes out to white on sky). Shared by every pooled ribbon.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 2.0) = 1.15;

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * COLOR.a * glow;
	ALPHA = COLOR.a;
}
