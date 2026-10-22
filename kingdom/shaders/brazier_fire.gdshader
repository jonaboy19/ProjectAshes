// Brazier / torch flame (AAA pass 2, 2026-10-06): a looping 8x4 flipbook (assets/vfx/flipbooks/flame_loop.png, baked by
// tools_qa/vfx_flipbooks/bake_flame_loop.gd) on one Y-axis billboard quad, additive and unshaded. One quad per fire,
// no sorting issues, no light; each fire starts on its own frame. The quad is a surface of the merged brazier mesh,
// centred on the model's vertical axis, so the billboard turns about that axis.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D flipbook : source_color, filter_linear_mipmap, repeat_disable;
uniform float fps = 24.0;
uniform float energy = 1.6;

varying float seed;

void vertex() {
	seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291) * 32.0;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = normalize(cross(right, up));
	mat4 bb = mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	float f = mod(floor(TIME * fps + seed), 32.0);
	vec2 cell = vec2(mod(f, 8.0), floor(f / 8.0));
	vec4 c = texture(flipbook, (UV + cell) / vec2(8.0, 4.0));
	ALBEDO = c.rgb * energy;
	ALPHA = c.a;
}
