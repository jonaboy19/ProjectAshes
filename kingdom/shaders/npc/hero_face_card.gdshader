// Hero face card: same drawing as the villagers' (face_card_common) but plain uniforms on the hero's own material, so it also
// works in the Compatibility renderer (no instance uniforms there). The hero's brows live in hero_character.gdshader and the
// lids in the Lids patch, so this card only draws the mouth by default (brows_on / lids_on = 0).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded, shadows_disabled;

#include "res://shaders/npc/face_card_common.gdshaderinc"

uniform float brow = 0.0;
uniform float lids = 0.0;
uniform float mouth_open = 0.0;
uniform float mouth_curve = 0.0;
uniform float brows_on = 0.0;
uniform float lids_on = 0.0;
uniform vec4 face_layout = vec4(-0.04, 0.024, 0.03, 0.034);
uniform vec2 card_size = vec2(0.11, 0.1);
uniform float debug = 0.0;

void fragment() {
	vec4 f = face_ink(UV, card_size, brow, lids, mouth_open, mouth_curve, brows_on, lids_on, face_layout);
	ALBEDO = mix(f.rgb, vec3(1.0, 0.0, 1.0), debug);
	ALPHA = mix(f.a, 1.0, debug);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
