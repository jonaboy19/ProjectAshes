// Hero see-through for opaque world materials (AAA camera pass 2026-10-06, skill ashes-aaa-camera-hud).
// Town props, roofs and banners are batched into MultiMeshes, so the camera cannot fade one of them by node; instead the
// world shaders cut away (discard with a thin interleaved-gradient-noise rim, no blending) whatever lies right in front of the lens or inside the cone
// between the lens and the hero. player.gd writes the global `hero_cam_dist` every frame (camera -> pivot, 0 = off:
// first person, menus, cutscenes). Orthographic passes (sun shadows) are untouched so the roofs keep their shadows.
//     #include "res://shaders/camera_see_through.gdshaderinc"
//     void fragment() { if (hero_see_through(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) { discard; } ... }

global uniform float hero_cam_dist;

bool hero_see_through(vec3 view_pos, vec2 frag_coord, mat4 proj) {
	if (hero_cam_dist <= 0.0 || proj[3][3] > 0.5) {
		return false;
	}
	float depth = -view_pos.z;
	float keep = smoothstep(1.7, 2.0, length(view_pos));            // anything within ~2 m of the lens (side banners, eaves): a narrow band, so it is cut cleanly instead of screen-doored
	if (depth > 0.0 && depth < hero_cam_dist - 0.35) {
		float t = depth / hero_cam_dist;
		vec2 off = vec2(view_pos.x, view_pos.y + 0.55 * t);
		float cone = 1.05 * t + 0.25;
		keep = min(keep, smoothstep(cone * 0.85, cone, length(off)));
	}
	if (keep >= 0.999) {
		return false;
	}
	// interleaved gradient noise (Jimenez 2014): far finer grain than a 4x4 Bayer pattern, same cost; with the narrow
	// band above only a thin rim is dithered and the rest is a clean cut-out
	float ign = fract(52.9829189 * fract(dot(frag_coord, vec2(0.06711056, 0.00583715))));
	return keep < ign;
}
