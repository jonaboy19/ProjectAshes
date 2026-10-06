shader_type spatial;
// Flickering billboard glow for torches, braziers and lanterns: replaces the omni light on LOW / MEDIUM tiers.
// A camera-facing quad with a hard toon flame teardrop and a soft halo; the flicker is per-instance (INSTANCE_CUSTOM.x
// is a random phase) so a whole street is ONE MultiMesh draw call. `lit` fades the glow in at dusk (set by the lamp
// nodes from main.gd's night amount).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.62, 0.25, 1.0);
uniform float lit : hint_range(0.0, 1.0) = 1.0;
uniform float energy = 1.6;
uniform float halo_size = 1.0;

varying float v_flick;
varying vec3 v_col;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	v_col = dot(INSTANCE_CUSTOM.yzw, vec3(1.0)) > 0.01 ? INSTANCE_CUSTOM.yzw : glow_color.rgb;
	v_flick = 0.86 + 0.1 * sin(TIME * 13.0 + phase) + 0.06 * sin(TIME * 23.7 + phase * 2.3);
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= sc * halo_size * (0.94 + 0.12 * v_flick);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	// teardrop flame: narrower toward the top (UV.y 0 is the top of the quad)
	float h = 1.0 - UV.y;
	float flame = step(abs(q.x), (0.22 - 0.16 * h) * v_flick) * step(0.28, h) * step(h, 0.34 + 0.3 * v_flick);
	float core = step(d, 0.16);
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	vec3 hot = mix(v_col, vec3(1.0, 0.95, 0.75), 0.7);
	vec3 col = v_col * halo * 0.9 + hot * max(flame, core);
	// AAA pass 7: a lamp right next to the lens blew out into a white slab: fade within ~3 m of the camera
	float near_k = smoothstep(1.2, 3.2, length(VERTEX));
	ALBEDO = col * energy * v_flick * lit * near_k;
}
