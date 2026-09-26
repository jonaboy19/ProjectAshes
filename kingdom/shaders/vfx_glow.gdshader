// Additive soft glow for particles and ribbons. Vertex colour carries tint and
// fade; `shape` 0 = soft round sprite, 1 = streak (UV.x along, UV.y across).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float energy = 3.0;
uniform int shape = 0;
uniform float progress = 0.0;   // slash: 0..1 sweep of the leading edge
uniform bool billboard = false; // face the camera (flash cores)
uniform float bb_scale = 1.0;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		VERTEX *= bb_scale;
	}
}

void fragment() {
	float a;
	if (shape == 0) {
		float d = length(UV - vec2(0.5)) * 2.0;
		a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	} else {
		// Ribbon: bright core across, fading tail behind the leading edge.
		float across = 1.0 - abs(UV.y - 0.5) * 2.0;
		float lead = progress;
		float behind = lead - UV.x;
		float tail = smoothstep(0.55, 0.0, behind) * step(0.0, behind + 0.02);
		a = pow(across, 1.5) * tail;
		// Thin hot edge on the outside of the arc.
		a += smoothstep(0.82, 1.0, UV.y) * tail * 0.8;
	}
	vec4 c = tint * COLOR;
	ALBEDO = c.rgb * energy;
	ALPHA = clamp(a * c.a, 0.0, 1.0);
}
