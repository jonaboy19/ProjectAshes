// Additive atlas sprite for particles and glow billboards (fire, sparks, qi,
// lightning, motes). See vfx_common.gdshaderinc for the ramp and atlas cells.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/vfx_common.gdshaderinc"

void vertex() {
	v_ls = vfx_vertex(VERTEX, MODELVIEW_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX, INSTANCE_CUSTOM);
}

void fragment() {
	vec4 s = vfx_shade(UV, COLOR, TIME, v_ls);
	ALBEDO = s.rgb * COLOR.rgb * energy;
	ALPHA = s.a;
}
