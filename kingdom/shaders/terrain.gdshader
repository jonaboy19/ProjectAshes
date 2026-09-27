shader_type spatial;
// PBR terrain splat (Poly Haven CC0 textures). Material weights come from the
// world generator via vertex colour: R = dirt path, G = rock, B = cobblestone
// street, A = forest floor; grass fills the rest. Rock is projected sideways so
// cliffs don't stretch, and every layer is sampled at two scales blended by a
// macro noise so tiling doesn't show over large fields.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float tile_size = 4.0;            // metres per texture repeat
uniform vec3 grass_tint : source_color = vec3(0.85, 1.0, 0.7);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Samples one layer at two scales, blended by macro noise to hide repetition.
void layer(sampler2D alb, sampler2D nrm, sampler2D arm, vec2 uv, float mix_amt,
		out vec3 a, out vec3 n, out vec3 o) {
	vec2 uv2 = uv * 0.37 + vec2(0.31, 0.77);
	a = mix(texture(alb, uv).rgb, texture(alb, uv2).rgb, mix_amt);
	n = mix(texture(nrm, uv).rgb, texture(nrm, uv2).rgb, mix_amt);
	o = mix(texture(arm, uv).rgb, texture(arm, uv2).rgb, mix_amt);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	float macro = texture(macro_noise, world_pos.xz * 0.003).r;
	float m2 = smoothstep(0.3, 0.7, macro) * 0.5;

	vec3 ga, gn, go, fa, fn, fo, pa, pn, po, ca, cn, co;
	layer(grass_albedo, grass_normal, grass_arm, uv, m2, ga, gn, go);
	// Natural variation: broad dry/lush patches plus finer mottling, so a field
	// never reads as one flat carpet.
	float dry = smoothstep(0.55, 0.9, texture(macro_noise, world_pos.xz * 0.0011 + vec2(0.4, 0.1)).r) * 0.45;
	float mottle = texture(macro_noise, world_pos.xz * 0.023).r;
	vec3 lush = vec3(0.62, 1.05, 0.40);
	vec3 parched = vec3(0.95, 1.0, 0.55);
	ga *= mix(lush, parched, dry) * mix(0.82, 1.12, macro) * mix(0.9, 1.08, mottle);
	layer(forest_albedo, forest_normal, forest_arm, uv * 0.8, m2, fa, fn, fo);
	layer(path_albedo, path_normal, path_arm, uv * 0.9, m2, pa, pn, po);
	layer(cobble_albedo, cobble_normal, cobble_arm, uv * 1.4, 0.0, ca, cn, co);
	// Rock: side projection chosen by the dominant horizontal axis of the normal.
	vec2 ruv = (abs(world_normal.x) > abs(world_normal.z) ? world_pos.zy : world_pos.xy) / (tile_size * 1.5);
	vec3 ra = texture(rock_albedo, ruv).rgb;
	vec3 rn = texture(rock_normal, ruv).rgb;
	vec3 ro = texture(rock_arm, ruv).rgb;

	// Weights, sharpened with the albedo luminance for a height-blend feel.
	vec4 w = COLOR;
	float slope = 1.0 - world_normal.y;
	w.g = max(w.g, smoothstep(0.3, 0.5, slope));
	float grain = texture(macro_noise, world_pos.xz * 0.11).r - 0.5;
	w = clamp(w + vec4(grain * 0.35) * step(0.02, w), 0.0, 1.0);
	float wg = max(0.0, 1.0 - (w.r + w.g + w.b + w.a));
	float total = wg + w.r + w.g + w.b + w.a + 0.0001;

	vec3 albedo = (ga * wg + pa * w.r + ra * w.g + ca * w.b + fa * w.a) / total;
	vec3 normal = (gn * wg + pn * w.r + rn * w.g + cn * w.b + fn * w.a) / total;
	vec3 orm = (go * wg + po * w.r + ro * w.g + co * w.b + fo * w.a) / total;

	ALBEDO = albedo;
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = 1.0;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
}
