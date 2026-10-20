// Villager face card: one shared material, per-instance brow / lids / mouth (Mobile + Forward+ only; LOW/Compatibility never creates it).
// ~25 ALU, one draw per NEAR villager, no shadow, unshaded ink (Style G: timber ink, never black). docs/art/FACES.md
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded, shadows_disabled;

#include "res://shaders/npc/face_card_common.gdshaderinc"

instance uniform float brow = 0.0;
instance uniform float lids = 0.0;
instance uniform float mouth_open = 0.0;
instance uniform float mouth_curve = 0.0;
instance uniform vec4 face_layout = vec4(-0.04, 0.024, 0.03, 0.034);
instance uniform vec3 skin : source_color = vec3(0.85, 0.65, 0.55);
uniform vec2 card_size = vec2(0.11, 0.1);
uniform float debug = 0.0;

void fragment() {
	vec4 f = face_ink(UV, card_size, brow, lids, mouth_open, mouth_curve, 1.0, 1.0, face_layout, skin);
	ALBEDO = mix(f.rgb, vec3(1.0, 0.0, 1.0), debug);
	ALPHA = mix(f.a, 1.0, debug);
}
