// Brazier / torch flame (AAA pass 2026-10-06): unshaded, a white-gold core fading to orange and dark red at the tips,
// a cheap vertex sway and flicker. Replaces the flat yellow cone. No textures, no transparency (mobile friendly).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float height = 0.55;     // flame height in model space (base at y0)
uniform float y0 = 0.9;
uniform float energy = 1.35;

varying float h;

void vertex() {
	h = clamp((VERTEX.y - y0) / height, 0.0, 1.0);
	float seed = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	float t = TIME * 6.0 + seed;
	VERTEX.x += sin(t + VERTEX.y * 7.0) * 0.045 * h * h;
	VERTEX.z += cos(t * 1.3 + VERTEX.y * 5.0) * 0.045 * h * h;
	VERTEX.y += (sin(t * 2.1) * 0.5 + 0.5) * 0.06 * h;
}

void fragment() {
	vec3 core = vec3(1.0, 0.78, 0.36);
	vec3 mid = vec3(1.0, 0.55, 0.12);
	vec3 tip = vec3(0.75, 0.18, 0.04);
	vec3 c = h < 0.45 ? mix(core, mid, h / 0.45) : mix(mid, tip, (h - 0.45) / 0.55);
	ALBEDO = c * energy;
}
