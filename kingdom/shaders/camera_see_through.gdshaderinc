// Hero see-through for opaque world materials (AAA camera pass 2026-10-06, skill ashes-aaa-camera-hud).
// Town props, roofs and banners are batched into MultiMeshes, so the camera cannot fade one of them by node; instead the
// world shaders dither away (Bayer 4x4 discard, no blending) whatever lies right in front of the lens or inside the cone
// between the lens and the hero. player.gd writes the global `hero_cam_dist` every frame (camera -> pivot, 0 = off:
// first person, menus, cutscenes). Orthographic passes (sun shadows) are untouched so the roofs keep their shadows.
//     #include "res://shaders/camera_see_through.gdshaderinc"
//     void fragment() { if (hero_see_through(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) { discard; } ... }

global uniform float hero_cam_dist;

const float SEE_BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

bool hero_see_through(vec3 view_pos, vec2 frag_coord, mat4 proj) {
	if (hero_cam_dist <= 0.0 || proj[3][3] > 0.5) {
		return false;
	}
	float depth = -view_pos.z;
	float keep = smoothstep(1.0, 2.4, length(view_pos));            // anything within ~2 m of the lens (side banners, eaves)
	if (depth > 0.0 && depth < hero_cam_dist - 0.35) {
		float t = depth / hero_cam_dist;
		vec2 off = vec2(view_pos.x, view_pos.y + 0.55 * t);
		float cone = 1.05 * t + 0.25;
		keep = min(keep, smoothstep(cone * 0.6, cone, length(off)));
	}
	if (keep >= 0.999) {
		return false;
	}
	ivec2 cell = ivec2(mod(frag_coord, 4.0));
	return keep < (SEE_BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
}
