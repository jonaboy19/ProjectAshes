shader_type spatial;
// A faint vertical column of ember light behind an Ashsight ghost: keeps the figure readable
// in a wide replay at phone size (it widens and brightens with camera distance, and is almost
// invisible up close). Y-axis billboard, unshaded, additive-looking mix.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 ember_color : source_color = vec4(1.0, 0.6, 0.26, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

varying float v_dist;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_dist = length(origin - CAMERA_POSITION_WORLD);
	float widen = 1.0 + smoothstep(10.0, 45.0, v_dist) * 1.6;
	vec3 to_cam = normalize(vec3(CAMERA_POSITION_WORLD.x - origin.x, 0.0, CAMERA_POSITION_WORLD.z - origin.z) + vec3(1e-4));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 wpos = origin + right * VERTEX.x * sc.x * widen + vec3(0.0, VERTEX.y * sc.y, 0.0);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wpos, 1.0));
}

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float across = 1.0 - smoothstep(0.0, 1.0, x);
	across *= across;
	float up = smoothstep(0.0, 0.08, 1.0 - UV.y) * (1.0 - smoothstep(0.35, 1.0, 1.0 - UV.y));
	float far = smoothstep(9.0, 40.0, v_dist);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2 + v_dist);
	ALBEDO = ember_color.rgb * 1.3;
	ALPHA = across * up * alpha * pulse * (0.05 + 0.35 * far);
}
