// Region nature opaque surfaces (RG_Bark, RG_Rock, RG_Moss of region/nature/*.glb).
// COLOR.r = sway weight (branches > 0, trunks ~0 at the base, rocks 0), COLOR.g = phase,
// COLOR.b = baked ambient occlusion. Same wind as region_foliage.gdshader so branches and their
// leaf cards move together (keep wind_* uniforms equal on both materials).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/foliage_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength = 0.22;
uniform float wind_speed = 1.1;
uniform float weather_wind = 1.0;   // scripts/world/weather.gd (keep equal to the foliage material)

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 dir = normalize(wind_direction);
	float t = TIME * wind_speed + dot(origin.xz, vec2(0.131, 0.073));
	float gust = 0.45 + 0.4 * sin(t) + 0.15 * sin(t * 2.3 + 1.3);
	vec3 off = vec3(dir.x, 0.0, dir.y) * gust * wind_strength * weather_wind * COLOR.r;
	float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
	VERTEX += (vec4(off, 0.0) * MODEL_MATRIX).xyz / max(s2, 1e-4);
}

void fragment() {
	if (foliage_fade_discard(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb * mix(1.0, COLOR.b, ao_strength);
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
}
