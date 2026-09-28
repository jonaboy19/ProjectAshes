shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
// Meadow grass for Rising Ashes: the painted alpha-card clumps from
// assets/generated/nature (grass_clump*, flowers_a), drawn by GrassField's
// MultiMeshes. Mesh convention (tools/blender/make_nature.py):
//   COLOR.r = bend weight, 0 at the ground -> 1 at the tips (linear in height)
//   COLOR.g = per-card random phase
//   TANGENT = the card's horizontal side axis; NORMAL is a custom mostly-up normal
// COLOR is wind data here, never albedo.
//
// On top of the imported foliage_wind look (same uniforms, same defaults):
//  - Clumping: low-frequency noise drifts colour between lush and sun-dried
//    patches, a second octave varies tuft height, so the meadow reads in drifts
//    instead of a uniform carpet.
//  - View-space widening: cards turning edge-on to the camera are pushed out
//    along the camera's right axis, so blades never collapse into slivers.
//    Far clumps also fill out a little to hide thinning density.
//  - Wind: a warped value-noise gust field that travels downwind (visible
//    waves rolling across the field) plus per-card flutter that climbs the
//    blade, with a small cross-wind sway.
//  - Fake subsurface: a warm glow when looking toward the sun through the
//    tips, plus soft wrap lighting (custom light()).
//  - Trampling: up to 8 interactors (player, villagers, critters) in shader
//    globals bend clumps away and press them flat, keeping blade length.
// Shadow casting is off on the instances; per-vertex work is a handful of
// hashes and at most 8 distance tests per clump vertex.
//
// Ideas (clumping, view-space thickening, SSS term, wind turbulence) follow
// 2Retr0/GodotGrass (MIT, (c) 2024 Ethan Truong), reimplemented for card clumps;
// no code copied. See CREDITS.md.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec2 wind_direction = vec2(1.0, 0.35);   // world XZ
uniform float wind_strength = 0.12;               // metres of tip sway
uniform float wind_speed = 1.4;
uniform float gust_scale = 0.07;                  // spatial frequency of gust waves (1/m)
uniform float weather_wind = 1.0;                 // Weather.wind_strength: 1 calm, ~2.4 storm (GrassField sets it)

// Season look, set by scripts/sim/seasons.gd (RenderingServer globals). All defaults
// are neutral, so with no seasons node the meadow looks exactly as it did before.
global uniform vec3 season_tint;
global uniform float autumn_amount;
global uniform float winter_amount;
global uniform float snow_amount;
global uniform float bloom_amount;

group_uniforms clumping;
uniform float clump_scale = 0.09;                 // colour patches per metre
uniform float clump_height : hint_range(0.0, 0.5) = 0.16;
uniform vec3 lush_tint : source_color = vec3(0.90, 1.0, 0.92);
uniform vec3 dry_tint : source_color = vec3(1.10, 1.03, 0.80);
uniform float clump_tint_amount : hint_range(0.0, 1.0) = 0.7;
uniform float root_shade : hint_range(0.0, 1.0) = 0.22;   // darker roots ground the clumps
uniform float tip_lift : hint_range(0.0, 0.5) = 0.10;     // lighter tips

group_uniforms shape;
uniform float widen_amount : hint_range(0.0, 1.5) = 0.6;
uniform float distance_fill : hint_range(0.0, 1.0) = 0.3;
uniform float gust_warp : hint_range(0.0, 2.0) = 0.8;

group_uniforms lighting;
uniform vec3 sss_color : source_color = vec3(1.0, 0.78, 0.32);
uniform float sss_strength : hint_range(0.0, 2.0) = 0.55;
uniform float wrap_light : hint_range(0.0, 0.6) = 0.2;
uniform float sheen : hint_range(0.0, 0.3) = 0.05;

group_uniforms trampling;
uniform float trample_bend : hint_range(0.0, 1.5) = 1.15;   // max lean in radians
uniform float trample_reach_y = 1.3;                        // ignore bodies this far above/below

// Shared with water.gdshader; set by scripts/world/grass_interactors.gd.
global uniform vec4 ashes_interactor_0;
global uniform vec4 ashes_interactor_1;
global uniform vec4 ashes_interactor_2;
global uniform vec4 ashes_interactor_3;
global uniform vec4 ashes_interactor_4;
global uniform vec4 ashes_interactor_5;
global uniform vec4 ashes_interactor_6;
global uniform vec4 ashes_interactor_7;
global uniform int ashes_interactor_count;

varying float blade_h;
varying float clump;
varying float flatten;

float hash21(vec2 p) {
	p = mod(p, 289.0);
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// World offset -> local offset for a rotation * per-axis scale basis.
vec3 to_local(mat4 m, vec3 w) {
	vec3 s2 = vec3(dot(m[0].xyz, m[0].xyz), dot(m[1].xyz, m[1].xyz), dot(m[2].xyz, m[2].xyz));
	return (vec4(w, 0.0) * m).xyz / max(s2, vec3(1e-4));
}

vec2 trample_push(vec4 it, vec3 origin) {
	vec2 dv = origin.xz - it.xz;
	float d = length(dv);
	float f = (1.0 - smoothstep(it.w * 0.3, it.w, d))
			* (1.0 - smoothstep(0.5, trample_reach_y, abs(origin.y - it.y)));
	return (d > 1e-3 ? dv / d : vec2(0.7071)) * f * step(0.001, it.w);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	blade_h = COLOR.r;
	float w2 = COLOR.r * COLOR.r;                  // stiff base, soft tips
	float ph = COLOR.g * 6.2831853;

	// --- Clumping: patch colour + tuft height (per instance).
	clump = vnoise(origin.xz * clump_scale);
	float tuft = vnoise(origin.xz * clump_scale * 3.7 + vec2(17.0, 5.0));
	VERTEX.y *= 1.0 + (tuft * 0.7 + clump * 0.3 - 0.5) * 2.0 * clump_height;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rel = wp - origin;
	vec3 moved = rel;

	// --- Trampling: lean the clump away from nearby bodies, keeping length.
	vec2 push = vec2(0.0);
	int n = clamp(ashes_interactor_count, 0, 8);
	if (n > 0) push += trample_push(ashes_interactor_0, origin);
	if (n > 1) push += trample_push(ashes_interactor_1, origin);
	if (n > 2) push += trample_push(ashes_interactor_2, origin);
	if (n > 3) push += trample_push(ashes_interactor_3, origin);
	if (n > 4) push += trample_push(ashes_interactor_4, origin);
	if (n > 5) push += trample_push(ashes_interactor_5, origin);
	if (n > 6) push += trample_push(ashes_interactor_6, origin);
	if (n > 7) push += trample_push(ashes_interactor_7, origin);
	flatten = clamp(length(push), 0.0, 1.0);
	if (flatten > 0.001) {
		vec2 pd = normalize(push);
		float a = flatten * trample_bend;
		float along = dot(rel.xz, pd);
		float na = along * cos(a) + rel.y * sin(a);
		moved.y = rel.y * cos(a) - along * sin(a) + 0.02 * flatten;   // stays just above ground
		moved.xz += pd * (na - along);
	}

	// --- Wind: travelling, domain-warped gust field + climbing flutter.
	vec2 dir = normalize(wind_direction);
	vec2 q = origin.xz * gust_scale * 1.6;
	vec2 warp = vec2(sin(q.y * 2.3 + TIME * 0.7), cos(q.x * 1.9 - TIME * 0.6)) * gust_warp;
	float drift = TIME * wind_speed * gust_scale * 1.6 * 2.2;
	float gust = smoothstep(0.15, 0.85, vnoise(q + warp - dir * drift));
	// Storms sway further and flutter harder. (Amplitude only: scaling a
	// TIME frequency would make blades jump whenever weather_wind changes.)
	float ww = max(weather_wind, 0.0);
	float flutter = sin(TIME * wind_speed * 3.3 + ph + wp.x * 0.9 + wp.z * 0.6 - COLOR.r * 1.5) * 0.3;
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 off = (dir * (0.25 + gust * 0.75 + flutter) + perp * flutter * (0.5 + 0.25 * max(ww - 1.0, 0.0))) * wind_strength * ww * w2;
	off *= 1.0 - flatten * 0.85;
	moved += vec3(off.x, -dot(off, off) * 1.5 * COLOR.r, off.y);   // tips dip as they bend

	// --- View-space widening (edge-on cards) and distance fill.
	vec3 side_w = mat3(MODEL_MATRIX) * TANGENT;
	vec3 face = cross(normalize(side_w + vec3(0.0, 1e-4, 0.0)), vec3(0.0, 1.0, 0.0));
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	float cam_dist = length(to_cam);
	float edge = 1.0 - abs(dot(normalize(face + vec3(1e-4, 0.0, 0.0)), to_cam / max(cam_dist, 1e-3)));
	edge *= edge;
	edge *= edge;
	float side = dot(rel, normalize(side_w + vec3(0.0, 1e-4, 0.0)));
	moved += INV_VIEW_MATRIX[0].xyz * side * edge * widen_amount;
	float fill = smoothstep(25.0, 70.0, cam_dist) * distance_fill;
	moved.xz += rel.xz * fill;

	VERTEX += to_local(MODEL_MATRIX, moved - rel);
}

void fragment() {
	vec4 t = texture(albedo_texture, UV);
	vec3 col = t.rgb * tint.rgb * season_tint;
	vec3 patch_tint = mix(lush_tint, dry_tint, smoothstep(0.3, 0.75, clump));
	col *= mix(vec3(1.0), patch_tint, clump_tint_amount);
	col *= mix(1.0 - root_shade, 1.0, smoothstep(0.0, 0.55, blade_h));
	col *= 1.0 + tip_lift * smoothstep(0.5, 1.0, blade_h);
	col *= 1.0 - flatten * 0.08;                   // pressed grass sits in its own shade
	// Autumn: grass yellows, more so near the tips.
	if (autumn_amount > 0.0) {
		vec3 yellow = vec3(0.72, 0.6, 0.22);
		col = mix(col, col * yellow * 1.6, autumn_amount * mix(0.6, 1.0, blade_h));
	}
	// Winter: short, frosty, desaturated grass.
	if (winter_amount > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(l) * vec3(0.82, 0.84, 0.86), winter_amount * 0.65);
	}
	if (snow_amount > 0.0) {
		col = mix(col, vec3(0.95, 0.97, 1.0), snow_amount * smoothstep(0.5, 1.0, blade_h) * 0.8);
	}
	if (bloom_amount > 0.0) {
		col = mix(col, col * vec3(0.9, 1.05, 0.88), bloom_amount * 0.5);
	}
	ALBEDO = col;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness - 0.15 * blade_h;
	SPECULAR = 0.25;
	// BACKLIGHT carries the per-pixel subsurface colour into light().
	BACKLIGHT = sss_color * sss_strength * smoothstep(0.2, 1.0, blade_h);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;                          // undo the automatic back-face flip
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = clamp((ndl + wrap_light) / (1.0 + wrap_light), 0.0, 1.0);
	// Godot's own view-independent translucency (as foliage_wind's BACKLIGHT).
	vec3 trans = ALBEDO * backlight_amount * (1.0 - clamp(ndl, 0.0, 1.0));
	// Fake subsurface: light shining through the tips toward the camera.
	float vdl = clamp(-dot(VIEW, LIGHT), 0.0, 1.0);
	vec3 sss = BACKLIGHT * vdl * vdl * vdl;
	vec3 lit = LIGHT_COLOR * ATTENUATION / PI;
	DIFFUSE_LIGHT += lit * (vec3(diffuse) + trans + sss);
	vec3 h = normalize(VIEW + LIGHT);
	SPECULAR_LIGHT += lit * pow(clamp(dot(NORMAL, h), 0.0, 1.0), 24.0) * sheen * (1.0 - ROUGHNESS) * 4.0 * clamp(ndl + 0.3, 0.0, 1.0);
}
