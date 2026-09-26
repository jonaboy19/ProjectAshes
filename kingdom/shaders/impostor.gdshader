shader_type spatial;
render_mode unshaded, cull_disabled;
// Directional sprite impostor. A camera-facing (Y-axis) quad that picks one of
// four baked views (front, left, back, right) from the angle between the camera
// and the unit's facing, so a distant soldier turns like an old-school sprite.

uniform sampler2D atlas : source_color, filter_nearest;
uniform float frames = 4.0;
uniform float light = 1.0;
varying flat float v_frame;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 world = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	vec3 fwd = MODEL_MATRIX[2].xyz;
	float ang = atan(to_cam.x, to_cam.z) - atan(fwd.x, fwd.z);
	v_frame = mod(floor(mod(ang + PI * 0.25 + TAU * 4.0, TAU) / (PI * 0.5)), frames);
}

void fragment() {
	vec4 c = texture(atlas, vec2((UV.x + v_frame) / frames, UV.y));
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * light;
}
