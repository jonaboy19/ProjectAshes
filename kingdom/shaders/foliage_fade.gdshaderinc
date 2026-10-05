// Camera see-through for foliage: an ordered (Bayer 4x4) dither discard, so
// leaves and bushes right in front of the lens, or between the chase camera and
// the player, thin out instead of filling the screen. Opaque alpha-scissor only:
// no blending, no sorting, one smoothstep pair and a 16-entry lookup per
// fragment. Include it in a spatial shader and call, at the top of fragment():
//     if (foliage_fade_discard(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) { discard; }
// VERTEX in fragment() is the view-space position (camera at the origin, looking
// down -Z). The third-person camera arm points at the player's pivot (1.55 m up,
// player.gd), so the player sits on the view axis `occlude_distance` metres out;
// the cone from the lens to that body is dithered away. Orthographic passes
// (directional-light shadows) are left untouched so shadows keep their leaves.

uniform float fade_near = 2.6;         // metres from the camera: fully cut inside (visual pass: was 1.5, a canopy at 3 m still filled the lens)
uniform float fade_far = 5.4;          // fully solid beyond (was 3.0; boulders at 3-5 m next to the player filled a third of the frame)
uniform float occlude_distance = 5.5;  // camera -> player on the view axis; 0 turns the cone off
uniform float occlude_radius = 1.3;    // cone half-width at the player's depth
uniform float occlude_drop = 0.6;      // cone centre sits this far below the pivot (body centre)

const float FOLIAGE_BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

// 1 = keep, 0 = cut.
float foliage_fade_amount(vec3 view_pos, mat4 proj) {
	if (proj[3][3] > 0.5) {
		return 1.0;     // orthographic: shadow map, not the player's view
	}
	float keep = smoothstep(fade_near, fade_far, length(view_pos));
	float depth = -view_pos.z;
	if (occlude_distance > 0.0 && depth > 0.0 && depth < occlude_distance) {
		float t = depth / occlude_distance;
		vec2 off = vec2(view_pos.x, view_pos.y + occlude_drop * t);
		float cone = occlude_radius * t + 0.2;
		float side = smoothstep(cone * 0.55, cone, length(off));
		float front = smoothstep(occlude_distance - 0.9, occlude_distance - 0.3, depth);
		keep = min(keep, max(side, front));
	}
	return keep;
}

bool foliage_fade_discard(vec3 view_pos, vec2 frag_coord, mat4 proj) {
	float keep = foliage_fade_amount(view_pos, proj);
	if (keep >= 0.999) {
		return false;
	}
	ivec2 cell = ivec2(mod(frag_coord, 4.0));
	float threshold = (FOLIAGE_BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	return keep < threshold;
}
