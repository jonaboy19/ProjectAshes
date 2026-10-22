// Soft contact shadow under placed objects and characters: a flat quad that darkens the ground with a radial falloff.
// AAA pass 2 (2026-10-06): alpha blend instead of blend_mul. Multiply wrote 1.0 outside the disc, and after the game's
// exposure 0.86 tonemap that "1.0" darkened the whole quad, so every blob read as a dark square. Unlit, no depth write.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.42;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	ALBEDO = vec3(0.07, 0.06, 0.09);
	ALPHA = pow(clamp(1.0 - r, 0.0, 1.0), 1.4) * strength;
}
