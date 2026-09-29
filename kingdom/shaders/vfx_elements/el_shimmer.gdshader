shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
// Heat shimmer: a soft camera-facing patch that wobbles the pixels behind it (fire AOE, HIGH+ only:
// it reads the screen texture, so it is hidden on LOW / MEDIUM through the `tier_min` node meta).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.010;
uniform float master : hint_range(0.0, 1.0) = 1.0;
uniform float speed = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	mat4 bill = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bill = bill * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bill;
}

void fragment() {
	vec2 u = UV * 2.0 - 1.0;
	float mask = (1.0 - smoothstep(0.25, 1.0, length(u * vec2(1.0, 0.9)))) * smoothstep(0.0, 0.25, UV.y);
	float t = TIME * speed;
	vec2 p = UV * vec2(5.0, 4.0);
	vec2 off = vec2(vn(p + vec2(0.0, -t * 2.4)) - 0.5, vn(p * 1.3 + vec2(7.3, -t * 3.1)) - 0.5);
	vec3 c = texture(screen_tex, SCREEN_UV + off * strength * mask * master).rgb;
	ALBEDO = c;
	ALPHA = clamp(mask * 1.6, 0.0, 1.0) * master;
}
