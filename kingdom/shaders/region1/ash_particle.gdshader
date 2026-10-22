shader_type spatial;
// Soft round billboard dot for Ashsight particles (drifting ash, ember footprints).
// Colour and fade come from the particle colour ramp.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 m = mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	ALBEDO = COLOR.rgb;
	ALPHA = a * a * COLOR.a;
}
