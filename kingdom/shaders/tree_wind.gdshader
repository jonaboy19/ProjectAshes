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

// Season look, set by scripts/sim/seasons.gd (RenderingServer globals). All defaults
// are neutral (white tint, everything else 0), so with no seasons node the look is
// unchanged. COLOR.g (where the mesh has it) varies the autumn colour per tree/leaf.
global uniform vec3 season_tint;
global uniform float autumn_amount;
global uniform float winter_amount;
global uniform float snow_amount;
global uniform float bloom_amount;

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
	vec3 col = c.rgb * season_tint;
	// Autumn: gold/orange/red, varied per leaf by COLOR.g so a crown isn't one flat hue.
	if (autumn_amount > 0.0) {
		vec3 fall = mix(vec3(0.85, 0.55, 0.08), vec3(0.75, 0.14, 0.06), COLOR.g);
		col = mix(col, fall * (0.6 + 0.4 * col), autumn_amount);
	}
	// Winter: bare, desaturated crowns (leaves that remain read as dry and grey).
	if (winter_amount > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(l) * vec3(0.85, 0.82, 0.8), winter_amount * 0.7);
	}
	// Snow settling on the top-facing leaf cards.
	if (snow_amount > 0.0) {
		float top = clamp(NORMAL.y, 0.0, 1.0);
		col = mix(col, vec3(0.96, 0.97, 1.0), snow_amount * top * top * 0.85);
	}
	// Spring: sparse blossom speckles, thinning out as bloom fades.
	if (bloom_amount > 0.0) {
		float speck = fract(sin(dot(floor(UV * 96.0), vec2(12.9898, 78.233))) * 43758.5453);
		if (COLOR.g > 0.55 && speck > 0.88) {
			col = mix(col, vec3(0.98, 0.86, 0.91), bloom_amount * 0.7);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * backlight_amount;
}
