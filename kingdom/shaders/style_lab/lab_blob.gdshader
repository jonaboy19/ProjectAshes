// Style Lab contact-shadow blob (copy of shaders/contact_shadow.gdshader + fog_disabled so height fog does not
// turn the multiply quad into a grey square). One quad per object, multiply blend, no lighting. Works everywhere.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.5;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float k = pow(clamp(1.0 - length(d), 0.0, 1.0), 1.3) * strength;
	ALBEDO = vec3(1.0 - k);
}
