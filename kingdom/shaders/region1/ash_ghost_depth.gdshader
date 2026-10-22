shader_type spatial;
// Ashsight ghost depth pre-pass (HIGH tier): writes the near surface of the figure only, so
// the translucent colour pass draws ONE layer (no doubled arms over the torso, a clean
// silhouette at phone size). Colour pass = ash_ghost.gdshader via next_pass.
// The depth is pushed 3 cm away from the camera so the colour pass always wins the depth test.
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

#include "res://shaders/region1/ash_ghost_common.gdshaderinc"

uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float model_height = 1.8;
uniform float noise_scale = 5.2;
uniform float drift_speed = 0.55;
uniform float feather : hint_range(0.05, 0.9) = 0.40;
uniform float seed = 0.0;

varying vec3 v_rel;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((w.y - NODE_POSITION_WORLD.y) / model_height, 0.0, 1.0);
	VERTEX += ghost_sway(VERTEX, h, seed, TIME);
	v_rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.z -= 0.03;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float h = clamp(v_rel.y / model_height, 0.0, 1.0);
	vec3 q = v_rel * noise_scale + vec3(seed * 13.0, -TIME * drift_speed, seed * 7.0);
	float n = vnoise(q);
	float field = ghost_field(n, h);
	float cut = dissolve * 1.18 - 0.08;
	float keep = smoothstep(cut, cut + 0.05, field);
	float foot = smoothstep(0.0, feather, h + (n - 0.5) * 0.34);
	// only nearly solid pixels write depth; a fading figure must not hide its own ash
	if (alpha * keep * foot < 0.62) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
