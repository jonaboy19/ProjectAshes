// Leaf / needle cards of the Blender trees and bushes: alpha-cut, double-sided,
// soft light through the leaves, and a gentle wind sway that grows with height
// (trunk base still, crown moving) with a per-tree phase from its world position.
// Leaves near the lens or between the chase camera and the player are dithered
// away (foliage_fade.gdshaderinc): alpha-scissor discard only, no sorting.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

#include "res://shaders/foliage_fade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float alpha_cut = 0.4;
uniform float sway = 0.12;          // metres at the crown top per 10 m of height
uniform float flutter = 0.03;       // small per-leaf shimmer
uniform float speed = 1.1;
uniform float backlight_amount = 0.35;
// Set by scripts/world/weather.gd on the shared leaf materials (1 = calm default, ~2.4 in a storm).
uniform float weather_wind = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.137, 0.091));
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * 0.01;
	float t = TIME * speed + phase;
	vec3 wind = vec3(sin(t) + 0.35 * sin(t * 2.3), 0.0, cos(t * 0.8) * 0.6) * sway * bend * weather_wind;
	wind += vec3(sin(TIME * 5.1 + VERTEX.x * 3.0 + VERTEX.z * 2.0), 0.0, 0.0) * flutter * weather_wind * min(h, 3.0) * 0.3;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
}

void fragment() {
	if (foliage_fade_discard(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV) * albedo * COLOR;
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = c.rgb * backlight_amount;
}
