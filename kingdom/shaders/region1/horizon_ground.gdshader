shader_type spatial;
render_mode cull_back, specular_disabled;
// Far horizon ground (scripts/region1/region1_horizon.gd): vertex-coloured whole-world mesh, discarded under
// the streamed terrain ring (ring_min..ring_max, updated each frame) so the real chunks own that ground.
// A soft macro mottle keeps big fields from reading as flat paint.

uniform vec2 ring_min = vec2(0.0);
uniform vec2 ring_max = vec2(0.0);
#include "res://shaders/region1/biome.gdshaderinc"
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wpos.x > ring_min.x + 1.0 && wpos.z > ring_min.y + 1.0 && wpos.x < ring_max.x - 1.0 && wpos.z < ring_max.y - 1.0) {
		discard;
	}
	float m = vnoise(wpos.xz * 0.012) * 0.6 + vnoise(wpos.xz * 0.05) * 0.4;
	// Vertex colours arrive as authored (sRGB); light them in linear space like every other albedo.
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float hedge;
	c = r1_biome(c, vec3(0.3, 0.2, 0.11), wpos.xz, r1_biome_sample(wpos.xz), hedge);
	ALBEDO = c * mix(0.86, 1.12, m);
	ROUGHNESS = 0.95;
}
