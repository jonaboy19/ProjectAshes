// Region nature foliage (leaf / needle / grass / fern cards of region/nature/*.glb).
// Mesh convention (written by kingdom/tools/blender/make_region_nature.py):
//   COLOR.r = sway weight: 0 = rigid (trunk base, grass roots) .. 1 = free (crown rim, blade tips)
//   COLOR.g = per-cluster phase 0..1 (so clumps don't move in lock-step)
//   COLOR.b = baked ambient occlusion (inner / lower cards darker), multiplied into albedo
//   COLOR.a = 1
// COLOR is data here, never a tint. Canopy normals point out of the crown; back faces keep them
// (no automatic flip) so a crown shades as one soft painterly volume from every side.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/foliage_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec2 wind_direction = vec2(1.0, 0.35);   // world XZ
uniform float wind_strength = 0.22;               // metres of sway where COLOR.r = 1
uniform float wind_speed = 1.1;
uniform float flutter = 0.035;                    // small per-cluster shimmer (metres)
uniform float weather_wind = 1.0;                 // scripts/world/weather.gd: 1 = calm default, ~2.4 storm

// Season look, set by scripts/sim/seasons.gd (RenderingServer globals). All defaults
// are neutral, so with no seasons node the canopy looks exactly as it did before.
global uniform vec3 season_tint;
global uniform float autumn_amount;
global uniform float winter_amount;
global uniform float snow_amount;
global uniform float bloom_amount;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = COLOR.r;
	float ph = COLOR.g * 6.2831853;
	vec2 dir = normalize(wind_direction);
	float t = TIME * wind_speed + dot(origin.xz, vec2(0.131, 0.073));
	float gust = 0.45 + 0.4 * sin(t) + 0.15 * sin(t * 2.3 + 1.3);
	vec3 off = vec3(dir.x, 0.0, dir.y) * gust * wind_strength * weather_wind * sway;
	off += vec3(sin(TIME * 4.1 + ph + wp.x * 1.3), 0.4 * sin(TIME * 3.3 + ph * 1.7),
			cos(TIME * 3.7 + ph + wp.z * 1.1)) * flutter * weather_wind * sway;
	// world offset -> local (valid for rotation + uniform scale)
	float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
	VERTEX += (vec4(off, 0.0) * MODEL_MATRIX).xyz / max(s2, 1e-4);
}

void fragment() {
	if (foliage_fade_discard(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	vec4 t = texture(albedo_texture, UV);
	vec3 col = t.rgb * tint.rgb * season_tint * mix(1.0, COLOR.b, ao_strength);
	// Autumn: gold/orange/red, varied per cluster by COLOR.g.
	if (autumn_amount > 0.0) {
		vec3 fall = mix(vec3(0.85, 0.55, 0.08), vec3(0.75, 0.14, 0.06), COLOR.g);
		col = mix(col, fall * (0.6 + 0.4 * col), autumn_amount);
	}
	// Winter: desaturated, bare-looking canopy.
	if (winter_amount > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(l) * vec3(0.85, 0.82, 0.8), winter_amount * 0.7);
	}
	// Snow on the top-facing canopy cards.
	if (snow_amount > 0.0) {
		float top = clamp(NORMAL.y, 0.0, 1.0);
		col = mix(col, vec3(0.96, 0.97, 1.0), snow_amount * top * top * 0.85);
	}
	// Spring blossom: sparse speckles on broadleaf clumps only (never the spruce and
	// pine atlas cells), so trees read as flowering, not frosted.
	if (bloom_amount > 0.0) {
		vec2 cell = floor(UV * 4.0);
		bool conifer = cell.y == 1.0 && cell.x < 2.0;
		float speck = fract(sin(dot(floor(UV * 384.0), vec2(12.9898, 78.233))) * 43758.5453);
		if (!conifer && COLOR.g > 0.55 && speck > 0.86) {
			col = mix(col, vec3(0.98, 0.86, 0.91), bloom_amount * 0.55);
		}
	}
	ALBEDO = col;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * backlight_amount;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;   // undo Godot's back-face flip: keep the authored canopy normal
	}
}
