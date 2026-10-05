// Warm light pool on the ground under torches and lamps at night (AAA pass 5, 2026-10-06): a flat additive radial disc,
// unlit, no depth write, one MultiMesh per town (lamp_glow.gd), shown with the glow batch (night only). Fakes the omni
// light pools the Mobile tier cannot afford.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 pool_color : source_color = vec3(1.0, 0.6, 0.28);
uniform float strength = 0.55;

void fragment() {
	float r = length((UV - vec2(0.5)) * 2.0);
	float k = pow(clamp(1.0 - r, 0.0, 1.0), 2.0) * strength;
	ALBEDO = pool_color * k;
}
