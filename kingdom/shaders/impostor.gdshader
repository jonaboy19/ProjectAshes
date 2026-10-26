shader_type spatial;
render_mode unshaded, cull_disabled;
// Directional sprite impostor. A camera-facing (Y-axis) quad that picks one of
// four baked views (front, left, back, right) from the angle between the camera
// and the unit's facing, so a distant soldier turns like an old-school sprite.

uniform sampler2D atlas : source_color, filter_nearest;
uniform float frames = 4.0;
uniform float light = 1.0;
// Distance dither fade (PopulationLOD sets it to its sprite band): residents entering / leaving the band fade in /
// out over fade_len metres instead of popping. 0 = off (other users of the shader).
uniform float fade_far = 0.0;
uniform float fade_len = 18.0;
varying flat float v_frame;
varying float v_cam_d;

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
	v_cam_d = length(INV_VIEW_MATRIX[3].xyz - origin);
	v_frame = mod(floor(mod(ang + PI * 0.25 + TAU * 4.0, TAU) / (PI * 0.5)), frames);
}

void fragment() {
	vec4 c = texture(atlas, vec2((UV.x + v_frame) / frames, UV.y));
	if (c.a < 0.5) {
		discard;
	}
	if (fade_far > 0.0) {
		float k = clamp((fade_far - v_cam_d) / fade_len, 0.0, 1.0);
		// 4x4 ordered dither
		int x = int(FRAGCOORD.x) % 4;
		int y = int(FRAGCOORD.y) % 4;
		float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if (k < (bayer[y * 4 + x] + 0.5) / 16.0) {
			discard;
		}
	}
	ALBEDO = c.rgb * light;
}
