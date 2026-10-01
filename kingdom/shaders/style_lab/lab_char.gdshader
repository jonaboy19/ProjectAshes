// Style Lab D character shader: skin / cloth / hair / leather separated by `kind`.
// skin = faked subsurface (warm emission, no SSS pass: SSS is Forward+ only) + warm rim, cloth = rough with a fuzzy sheen rim, hair = glossy band + rim,
// leather = satin. Lambert-wrap diffuse for soft form shading. Skinned meshes are fine: only the normal is used.
// Cost: 1 texture tap, ~40 ALU. Cheap everywhere (no extra passes).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform int kind = 1;               // 0 skin, 1 cloth, 2 hair, 3 leather
uniform float saturation = 1.2;
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.65);
uniform float rim_amount = 0.5;

void fragment() {
	vec4 t = texture(albedo_tex, UV * uv_scale + uv_offset);
	vec3 c = t.rgb * albedo_color.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	if (kind == 0) {
		c = mix(vec3(l), c, saturation * 0.95) * vec3(1.06, 0.98, 0.93);
		ROUGHNESS = 0.55; SPECULAR = 0.3;
		EMISSION = vec3(1.0, 0.55, 0.40) * c * 0.10 + rim_color * fres * rim_amount * 0.25;
	} else if (kind == 2) {
		c = mix(vec3(l), c, saturation);
		ROUGHNESS = 0.38; SPECULAR = 0.65;
		EMISSION = rim_color * fres * rim_amount * 0.45 + c * 0.06;
	} else if (kind == 3) {
		c = mix(vec3(l), c, saturation);
		ROUGHNESS = 0.5; SPECULAR = 0.5;
		EMISSION = rim_color * fres * rim_amount * 0.25;
	} else {
		c = mix(vec3(l), c, saturation);
		ROUGHNESS = 0.95; SPECULAR = 0.12;
		// fuzzy sheen: rim in the cloth's own colour, so it reads as fibre not plastic
		EMISSION = (c * 0.8 + rim_color * 0.3) * fres * rim_amount * 0.5;
	}
	ALBEDO = c;
}
