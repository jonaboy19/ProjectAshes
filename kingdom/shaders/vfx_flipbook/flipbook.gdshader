// Flipbook (sprite sheet) billboard for the baked VFX atlases in assets/vfx/flipbooks/.
// Original code (Rising Ashes), no third-party licence. One quad, one draw call, no particles.
//   - frames are laid out row-major, left to right, top to bottom (Blender/numpy bakers write them so)
//   - optional frame blending (mix of two neighbour frames) makes 16-frame sheets play as smooth as 64
//   - alpha-blended (not additive), so effects stay saturated on the bright sunny storybook ground
//   - per-instance start time: set_instance_shader_parameter("t0", <TIME at spawn>) so one shared material
//     serves any number of quads (no material duplicates, keeps batching/state changes low on mobile)
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int hframes = 4;
uniform int vframes = 4;
uniform int frame_count = 16;      // may be < hframes * vframes
uniform float fps = 20.0;
uniform bool loop_anim = false;
uniform bool blend_frames = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;         // colour multiplier (glow/bloom feed)
uniform float alpha_boost = 1.0;
uniform float fade_out = 0.0;       // seconds of extra alpha fade at the end of a one-shot
instance uniform float t0 = 0.0;    // TIME at spawn
instance uniform float hold = -1.0; // >= 0: freeze at this normalised progress (0..1), for stills

varying float v_f;

void vertex() {
	// spherical billboard, keeps the node's scale
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
	MODELVIEW_NORMAL_MATRIX = mat3(mv);
	float n = float(frame_count);
	float f = (TIME - t0) * fps;
	if (hold >= 0.0) {
		f = hold * (n - 1.0);
	}
	v_f = loop_anim ? mod(f, n) : clamp(f, 0.0, n - 1.0);
}

vec4 frame_at(int i, vec2 uv) {
	int c = i % hframes;
	int r = i / hframes;
	vec2 cell = vec2(1.0 / float(hframes), 1.0 / float(vframes));
	// stay inside the cell so filtering never bleeds a neighbouring frame in
	vec2 p = clamp(uv, vec2(0.002), vec2(0.998));
	return textureLod(atlas, (vec2(float(c), float(r)) + p) * cell, 0.0);
}

void fragment() {
	int n = frame_count;
	int i0 = int(floor(v_f));
	float m = fract(v_f);
	vec4 a = frame_at(i0, UV);
	if (blend_frames && m > 0.001) {
		int i1 = i0 + 1;
		if (i1 >= n) {
			i1 = loop_anim ? 0 : n - 1;
		}
		vec4 b = frame_at(i1, UV);
		// premultiplied blend so colour never darkens where one frame is transparent
		vec4 pa = vec4(a.rgb * a.a, a.a);
		vec4 pb = vec4(b.rgb * b.a, b.a);
		vec4 pm = mix(pa, pb, m);
		a = vec4(pm.a > 0.0001 ? pm.rgb / pm.a : vec3(0.0), pm.a);
	}
	float fo = 1.0;
	if (!loop_anim && fade_out > 0.0) {
		fo = clamp((float(n - 1) - v_f) / (fade_out * fps), 0.0, 1.0);
	}
	ALBEDO = a.rgb * tint.rgb * energy;
	ALPHA = clamp(a.a * tint.a * alpha_boost * fo, 0.0, 1.0);
}
