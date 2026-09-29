// Rift creature fur (wolf, boar): recoloured albedo + a sparse cyan emissive vein mask. Plain spatial shader,
// no vertex colour data needed (the Meshy creatures are skinned meshes without wind weights).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D vein_texture : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 vein_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float vein_strength : hint_range(0.0, 3.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.6);
	EMISSION = vein_color.rgb * texture(vein_texture, UV).r * vein_strength * pulse;
}
