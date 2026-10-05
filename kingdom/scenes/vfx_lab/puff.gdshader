shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Soft round sprite for lab particles (drops, embers, dust). Procedural: no texture. Scale of the particle
// transform is kept (custom billboard), COLOR comes from the particle process material (alpha over life).
// uniform additive: 1 = glowing (embers, sparks), 0 = alpha-blended (dust, droplets).
uniform float additive : hint_range(0.0, 1.0) = 1.0;
uniform float softness : hint_range(0.05, 1.0) = 0.55;
uniform float intensity = 1.6;
varying vec4 vcol;
void vertex() {
	mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	m = m * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	vcol = COLOR;
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 1.0 - softness, d);
	ALBEDO = vcol.rgb * mix(1.0, intensity, additive);
	ALPHA = a * vcol.a;
}
