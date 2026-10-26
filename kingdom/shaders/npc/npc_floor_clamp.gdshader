// NPC body material while a ground-contact clip plays (ContactIK): the standard-material look (albedo texture x colour,
// roughness, metallic) plus a floor plane limit. Skinned vertices that would go below the ground (a floor-length dress
// hem when kneeling or sitting on the ground) are laid onto it instead, so cloth pools on the floor rather than
// sinking through. Only swapped in for the few NPCs ContactIK is active on (scripts/living_world/contact_ik.gd).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_tex = true;
uniform bool vertex_color_srgb = false;  // BaseMaterial3D.vertex_color_is_srgb
uniform bool use_vertex_color = false;
uniform bool vc_to_srgb = true;           // StandardMaterial3D shows linear vertex colours this way (matched by A/B screenshots)   // BaseMaterial3D.vertex_color_use_as_albedo (NPC looks tint per vertex)
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_ao = false;
uniform float ao_light_affect = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
instance uniform float floor_y = -1000.0;     // world height of the ground under this character
uniform float floor_lift = 0.006;             // m above the ground (no z-fighting with the terrain)

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lim = floor_y + floor_lift;
	if (w.y < lim) {
		w.y = lim;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	}
}

void fragment() {
	vec4 c = albedo_color;
	if (has_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (use_vertex_color) {
		vec4 vc = COLOR;
		if (vc_to_srgb) {
			vc.rgb = mix(1.055 * pow(vc.rgb, vec3(1.0 / 2.4)) - 0.055, vc.rgb * 12.92, lessThan(vc.rgb, vec3(0.0031308)));
		} else if (vertex_color_srgb) {
			vc.rgb = mix(pow((vc.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), vc.rgb * (1.0 / 12.92), lessThan(vc.rgb, vec3(0.04045)));
		}
		c *= vc;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (has_ao) {
		AO = texture(ao_tex, UV).r;
		AO_LIGHT_AFFECT = ao_light_affect;
	}
}
