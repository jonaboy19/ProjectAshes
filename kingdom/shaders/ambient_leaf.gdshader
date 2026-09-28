// Falling leaves for scripts/world/ambient_fx.gd: GPUParticles3D draw pass on a
// small QuadMesh. The vertex shader tumbles each leaf (spin about its stem plus
// a side-to-side rocking flutter) with a per-particle phase; the fragment shader
// cuts a pointed leaf with a centre vein. Colour from the particle's colour.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform float spin = 2.2;

mat3 rot_axis(vec3 a, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	float t = 1.0 - c;
	return mat3(vec3(t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y),
		vec3(t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x),
		vec3(t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c));
}

void vertex() {
	float seed = fract(sin(float(INSTANCE_ID) * 12.77) * 4375.85);
	float t = TIME * spin * (0.7 + 0.6 * seed) + seed * 40.0;
	mat3 r = rot_axis(vec3(0.0, 1.0, 0.0), t) * rot_axis(vec3(1.0, 0.0, 0.0), 1.2 + sin(t * 1.7) * 0.9);
	VERTEX = r * VERTEX;
	NORMAL = r * NORMAL;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float w = 0.55 * (1.0 - q.y * q.y) * (1.0 - 0.25 * q.y);
	if (abs(q.x) > w || abs(q.y) > 0.98) {
		discard;
	}
	vec3 c = COLOR.rgb * mix(0.8, 1.05, abs(q.x) / max(w, 0.01));
	c *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.06, abs(q.x)));   // vein
	ALBEDO = c;
	ROUGHNESS = 0.85;
	BACKLIGHT = c * 0.5;
}
