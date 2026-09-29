// Rift-touched bark / rock / moss: swapped in for RG_Bark, RG_Rock and RG_Moss. Same wind data as
// region/nature/region_nature_opaque.gdshader (COLOR.r sway, COLOR.b baked AO), plus an optional
// emissive vein mask (cracks in the bark). Leave vein_texture empty for rock and moss: no glow.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/foliage_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D vein_texture : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 vein_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float vein_strength : hint_range(0.0, 3.0) = 0.8;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength = 0.22;
uniform float wind_speed = 1.1;
uniform float weather_wind = 1.0;

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
	EMISSION = vein_color.rgb * texture(vein_texture, UV).r * vein_strength;
}
