// Rift-touched foliage: leaf / needle / grass / fern cards of region/nature/*.glb, swapped in for RG_Foliage.
// Same mesh convention and wind as region/nature/region_foliage.gdshader:
//   COLOR.r = sway weight, COLOR.g = per-cluster phase, COLOR.b = baked ambient occlusion.
// Differences: the albedo atlas is the violet/cyan recolour (textures/rift_foliage_atlas.png), a thin
// emissive vein mask (textures/rift_foliage_vein.png) shimmers cyan, and the season look is ignored (the
// Scar keeps its own weather). Kept sunny on purpose: bright albedo, the vein is a soft shimmer, not a glow.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/foliage_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D vein_texture : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 vein_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float vein_strength : hint_range(0.0, 3.0) = 0.9;
uniform float vein_pulse : hint_range(0.0, 1.0) = 0.25;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength = 0.22;
uniform float wind_speed = 1.1;
uniform float flutter = 0.035;
uniform float weather_wind = 1.0;

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
	float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
	VERTEX += (vec4(off, 0.0) * MODEL_MATRIX).xyz / max(s2, 1e-4);
}

void fragment() {
	if (foliage_fade_discard(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	vec4 t = texture(albedo_texture, UV);
	vec3 col = t.rgb * tint.rgb * mix(1.0, COLOR.b, ao_strength);
	ALBEDO = col;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * backlight_amount;
	float v = texture(vein_texture, UV).r;
	float pulse = 1.0 - vein_pulse + vein_pulse * (0.5 + 0.5 * sin(TIME * 1.4 + COLOR.g * 6.2831853));
	EMISSION = vein_color.rgb * v * vein_strength * pulse;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
