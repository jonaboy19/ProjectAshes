// Butterflies for scripts/world/ambient_fx.gd: GPUParticles3D draw pass on a
// small PlaneMesh (lying flat, head towards +Z, one centre column of vertices).
// The vertex shader folds the two halves up and down about the body (flap), the
// fragment shader cuts the wing shape procedurally (fore + hind wing lobes, dark
// margins and a spot), coloured by the particle's colour. Alpha scissor, so it
// renders in the opaque pass with a depth pre-pass and no sorting.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform float flap_speed = 16.0;

varying float v_seed;

void vertex() {
	v_seed = fract(sin(float(INSTANCE_ID) * 17.13) * 4375.85);
	float t = TIME * flap_speed * (0.85 + 0.3 * v_seed) + v_seed * 6.283;
	// Flutter with the odd rest: wings held up for a moment now and then.
	float ang = 0.45 + sin(t) * 1.05;
	float d = abs(VERTEX.x);
	float sx = sign(VERTEX.x);
	VERTEX = vec3(sx * d * cos(ang), d * sin(ang) + sin(t * 0.5) * 0.01, VERTEX.z);
	NORMAL = normalize(vec3(-sx * sin(ang), cos(ang), 0.0));
}

void fragment() {
	vec2 q = vec2(abs(UV.x - 0.5) * 2.0, (UV.y - 0.5) * 2.0);   // q.x 0 body .. 1 tip; q.y -1 head .. 1 tail
	float fore = length((q - vec2(0.48, -0.32)) / vec2(0.55, 0.52));
	float hind = length((q - vec2(0.38, 0.42)) / vec2(0.42, 0.46));
	float body = step(q.x, 0.07) * step(abs(q.y), 0.8);
	float wing = min(fore, hind);
	if (wing > 1.0 && body < 0.5) {
		discard;
	}
	vec3 c = COLOR.rgb;
	c *= mix(1.0, 0.35, smoothstep(0.72, 0.95, wing));           // dark margins
	c = mix(c, vec3(0.08, 0.06, 0.05), step(length((q - vec2(0.55, -0.35)) / vec2(0.12, 0.1)), 1.0) * 0.8);
	c = mix(c, vec3(0.1, 0.08, 0.07), body);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.6;
}
