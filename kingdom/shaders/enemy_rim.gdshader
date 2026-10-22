// Cheap red rim for the locked or currently striking enemy: one additive fresnel pass used as a
// material_overlay on that actor's meshes (at most a few actors at a time, see enemy_highlight.gd).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.08, 1.0);
uniform float strength = 1.0;
uniform float rim_power = 1.5;
uniform float body = 0.1;      // faint fill so the whole silhouette warms, not just the edge

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = color.rgb * 1.6;
	ALPHA = clamp((f + body) * strength, 0.0, 1.0);
}
