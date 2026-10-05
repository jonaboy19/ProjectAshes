// Soft contact shadow under placed objects: a flat quad that darkens the ground
// with a radial falloff (multiply blend, no lighting, no depth write). One
// MultiMesh per object type, so it costs a single draw call per kind.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.42;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float k = pow(clamp(1.0 - r, 0.0, 1.0), 1.4) * strength;
	ALBEDO = vec3(1.0 - k);
}
