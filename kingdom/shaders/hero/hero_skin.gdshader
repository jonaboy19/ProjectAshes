// Tier-A hero skin (face + hands). Mobile-renderer safe faked subsurface:
//  - light(): wrapped diffuse whose terminator is shifted toward red (light bleeding through skin), + a soft GGX-ish lobe
//  - flush map (vertex colour R: nose, cheeks, ears; B: lips) adds blood colour; G = cavity AO multiplier
//  - roughness zones: T-zone (nose / forehead) oilier, cheeks / lips matte-ish; pore + fine-wrinkle detail normal from noise
// Cost: albedo + noise taps, custom light ~25 ALU per light. One material for face, one for hands (same shader).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_masks = true;              // false for meshes without the baked vertex masks (G6 hands)
uniform vec3 flush_color : source_color = vec3(0.86, 0.36, 0.30);
uniform float flush_amount = 0.14;
uniform vec3 scatter_color : source_color = vec3(1.0, 0.36, 0.22);
uniform float wrap = 0.45;
uniform float pore_scale = 90.0;
uniform float pore_strength = 0.28;
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.66);

varying vec3 v_mask;

void vertex() {
	v_mask = use_masks ? COLOR.rgb : vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	float flush = v_mask.r;
	float lip = v_mask.b;
	c = mix(c, c * flush_color * 1.9, clamp(flush * flush_amount, 0.0, 0.6));
	c = mix(c, c * vec3(1.05, 0.62, 0.58), lip * 0.5);
	float ao = mix(1.0, v_mask.g, 0.6);
	vec2 puv = UV * pore_scale;
	float n0 = texture(noise_tex, puv).r;
	float n1 = texture(noise_tex, puv + vec2(0.011, 0.0)).r;
	float n2 = texture(noise_tex, puv + vec2(0.0, 0.011)).r;
	NORMAL_MAP = normalize(vec3((n0 - n1) * 6.0 * pore_strength, (n0 - n2) * 6.0 * pore_strength, 1.0)) * 0.5 + 0.5;
	// T-zone: shinier where flush is low but cavity is open (forehead / nose bridge); lips semi-gloss
	float tz = smoothstep(0.25, 0.9, n0) * 0.08;
	ROUGHNESS = clamp(0.56 - tz - flush * 0.04 + (1.0 - ao) * 0.2 - lip * 0.12, 0.3, 0.8);
	SPECULAR = 0.35;
	ALBEDO = c * ao;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * c * fres * 0.18;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// wrapped diffuse; the wrap region (terminator + just past it) is tinted by the scatter colour
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float d = clamp(ndl, 0.0, 1.0);
	vec3 sss = scatter_color * (w - d) * 0.55;
	DIFFUSE_LIGHT += (vec3(d) + sss) * ATTENUATION * LIGHT_COLOR / 3.14159;
	vec3 h = normalize(LIGHT + VIEW);
	float a = ROUGHNESS * ROUGHNESS;
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float dd = ndh * ndh * (a * a - 1.0) + 1.0;
	float spec = (a * a) / (3.14159 * dd * dd) * d * 0.25;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR * 0.06;
}
