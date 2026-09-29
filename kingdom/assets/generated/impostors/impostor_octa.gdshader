// Hemi-octahedral impostor (billboard that shows the pre-rendered view nearest to the camera direction).
// Baked by tools/impostors/impostor_baker.gd. Own implementation of the public octahedral-impostor technique
// (see shaderbits.com/blog/octahedral-impostors); no third-party code. One albedo+alpha atlas, 4-frame bilinear blend.
// Works per-instance, so it can be used on a MeshInstance3D or a MultiMesh (rotation about Y and uniform scale are honoured).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int grid = 8;                       // frames per side (grid x grid views over the upper hemisphere)
uniform vec3 center = vec3(0.0);            // bounding-sphere centre in object space
uniform float radius = 1.0;                 // bounding-sphere radius in object space
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float up_lighting : hint_range(0.0, 1.0) = 0.7;   // 0 = flat lit toward camera, 1 = lit like an upward normal (foliage)
uniform vec4 tint : source_color = vec4(1.0);

varying flat vec2 v_base;    // lower-left frame index
varying flat vec2 v_frac;    // bilinear weights between frames
varying vec2 v_uv;

void vertex() {
	mat3 m = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c_world = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	vec3 fwd = normalize(CAMERA_POSITION_WORLD - c_world);
	vec3 up_ref = abs(fwd.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up_ref, fwd));
	vec3 up = cross(fwd, right);
	// quad local coordinates in [-radius, radius] (QuadMesh centred on `center`)
	vec2 q = VERTEX.xy - center.xy;
	vec3 w = c_world + (right * q.x + up * q.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	v_uv = vec2(q.x, -q.y) / (2.0 * radius) + 0.5;
	// view direction in object space (undo yaw/scale of the instance) -> hemi-octahedral frame coordinates
	vec3 d = normalize(transpose(m) * fwd);
	d.y = max(d.y, 0.0);
	d = normalize(d + vec3(0.0, 1e-4, 0.0));
	vec2 p = d.xz / (abs(d.x) + abs(d.y) + abs(d.z));
	vec2 uv = vec2(p.x + p.y, p.x - p.y) * 0.5 + 0.5;
	vec2 g = clamp(uv, 0.0, 1.0) * float(grid - 1);
	v_base = min(floor(g), vec2(float(grid - 2)));
	v_frac = g - v_base;
}

vec4 frame(vec2 idx) {
	vec2 t = (idx + clamp(v_uv, 0.002, 0.998)) / float(grid);
	return texture(atlas, t);
}

void fragment() {
	vec4 a = frame(v_base);
	vec4 b = frame(v_base + vec2(1.0, 0.0));
	vec4 c = frame(v_base + vec2(0.0, 1.0));
	vec4 d = frame(v_base + vec2(1.0, 1.0));
	float wa = (1.0 - v_frac.x) * (1.0 - v_frac.y) * a.a;
	float wb = v_frac.x * (1.0 - v_frac.y) * b.a;
	float wc = (1.0 - v_frac.x) * v_frac.y * c.a;
	float wd = v_frac.x * v_frac.y * d.a;
	float wsum = wa + wb + wc + wd;
	// alpha = plain bilinear of frame alphas (each frame is hard-edged)
	float alpha = (1.0 - v_frac.x) * (1.0 - v_frac.y) * a.a + v_frac.x * (1.0 - v_frac.y) * b.a
		+ (1.0 - v_frac.x) * v_frac.y * c.a + v_frac.x * v_frac.y * d.a;
	if (alpha < alpha_cut) {
		discard;
	}
	vec3 col = (a.rgb * wa + b.rgb * wb + c.rgb * wc + d.rgb * wd) / max(wsum, 1e-4);
	ALBEDO = col * tint.rgb;
	ROUGHNESS = 1.0;
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), up_view, up_lighting));
}
