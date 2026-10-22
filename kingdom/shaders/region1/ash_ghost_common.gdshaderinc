// Shared by ash_ghost.gdshader (colour pass) and ash_ghost_depth.gdshader (depth pre-pass).
// Cheap value noise plus the ghost's "erosion" field. No textures.

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

// Gentle heat-haze ripple, strongest near the feet.
vec3 ghost_sway(vec3 v, float h, float seed, float t) {
	float sway = sin(t * 1.7 + v.y * 3.0 + seed * 6.28) * 0.025 * (1.0 - h * 0.6);
	return vec3(sway, 0.0, sway * 0.7);
}

// Erosion field: high = survives. Feet survive longest, the head and hands crumble first,
// so the figure flakes away upwards like ash lifted by a draught.
float ghost_field(float n, float h) {
	return n * 0.62 + (1.0 - h) * 0.38;
}
