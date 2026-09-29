shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;
// Camera-facing glow / flare sprite that keeps node scale (Godot 4.6.3 particle billboards drop it).
// Used for the big soft glows, ray bursts and halos of the elemental VFX; `master` fades it.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float master : hint_range(0.0, 1.0) = 1.0;
uniform float spin = 0.0;    // rad/s roll of the sprite

void vertex() {
	mat4 bill = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bill = bill * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	float a = spin * TIME;
	float c = cos(a);
	float s = sin(a);
	vec3 v = vec3(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y, VERTEX.z);
	MODELVIEW_MATRIX = VIEW_MATRIX * bill;
	VERTEX = v;
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = tint.rgb * intensity * t.rgb;
	ALPHA = clamp(t.a * tint.a * master, 0.0, 1.0);
}
