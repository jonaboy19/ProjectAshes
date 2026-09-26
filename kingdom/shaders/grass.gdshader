shader_type spatial;
render_mode cull_disabled;
// Grass blades drawn by MultiMesh. Two-layer wind sway weighted by blade
// height, colour gradient root -> tip with per-clump variation, soft
// translucency so backlit grass glows.

uniform vec3 root_color : source_color = vec3(0.13, 0.22, 0.07);
uniform vec3 tip_color : source_color = vec3(0.52, 0.62, 0.24);
uniform float wind_strength = 0.28;

varying float height;
varying float variation;

void vertex() {
	height = UV.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	variation = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float gust = sin(TIME * 1.3 + origin.x * 0.05 + origin.z * 0.04) * 0.5 + 0.5;
	float sway = sin(TIME * 2.2 + origin.x * 0.6 + origin.z * 0.4) * (0.5 + gust);
	VERTEX.x += sway * wind_strength * height * height;
	VERTEX.z += sway * wind_strength * 0.5 * height * height;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 tip = mix(tip_color, tip_color * vec3(1.25, 1.1, 0.7), variation * 0.7);
	ALBEDO = mix(root_color, tip, height);
	ROUGHNESS = 0.85;
	BACKLIGHT = vec3(0.25, 0.3, 0.12) * height;
	AO = mix(0.4, 1.0, height);
	AO_LIGHT_AFFECT = 0.6;
}
