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
// Rain soak, driven by scripts/world/weather.gd (0 = dry: the look is unchanged).
// Flat ground darkens and turns glossy, streets and paths more than grass, and
// low spots in the macro noise collect mirror-smooth puddles.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Season look, set by scripts/sim/seasons.gd (RenderingServer globals). All defaults
// are neutral, so with no seasons node the ground looks exactly as it did before.
global uniform vec3 season_tint;
global uniform float autumn_amount;
global uniform float winter_amount;
global uniform float snow_amount;
global uniform float bloom_amount;

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
	layer(cobble_albedo, cobble_normal, cobble_arm, uv * 0.8, 0.0, ca, cn, co);
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

	float rough = orm.g;
	if (wetness > 0.0) {
		float flat_amt = smoothstep(0.8, 0.96, world_normal.y);
		float hard = clamp(w.r + w.g + w.b, 0.0, 1.0);          // path, rock, cobble take the shine
		float wet = wetness * mix(0.35, 1.0, flat_amt);
		albedo *= mix(1.0, mix(0.72, 0.58, hard), wet);
		rough = mix(rough, mix(0.5, 0.22, hard), wet * flat_amt);
		float hollow = smoothstep(0.42, 0.3, macro + grain * 0.3);
		float puddle = clamp(wetness * wetness * flat_amt * hollow * mix(0.35, 1.0, hard), 0.0, 1.0);
		albedo *= mix(1.0, 0.8, puddle);
		rough = mix(rough, 0.05, puddle);
		normal = mix(normal, vec3(0.5, 0.5, 1.0), puddle);
	}

	albedo *= season_tint;
	// Autumn: a warm tint and a scatter of leaf litter on soft ground.
	if (autumn_amount > 0.0) {
		float litter = smoothstep(0.55, 0.85, texture(macro_noise, world_pos.xz * 0.07).r) * (1.0 - clamp(w.r + w.b, 0.0, 1.0));
		albedo = mix(albedo, albedo * vec3(1.15, 0.75, 0.35), autumn_amount * 0.35);
		albedo = mix(albedo, vec3(0.55, 0.32, 0.12), autumn_amount * litter * 0.5);
	}
	// Winter: snow settles on flat ground, thinner on slopes, with paths and
	// rock/cobble still slightly visible through it (never fully buried).
	if (snow_amount > 0.0) {
		float flat_amt = smoothstep(0.55, 0.9, world_normal.y);
		float hard = clamp(w.r + w.g + w.b, 0.0, 1.0);       // path / rock / cobble peek through
		float cover = snow_amount * flat_amt * mix(1.0, 0.45, hard);
		vec3 snow_col = vec3(0.92, 0.95, 1.0);
		albedo = mix(albedo, snow_col, clamp(cover, 0.0, 0.92));
		rough = mix(rough, 0.75, clamp(cover, 0.0, 1.0));
	} else if (winter_amount > 0.0) {
		float l = dot(albedo, vec3(0.299, 0.587, 0.114));
		albedo = mix(albedo, vec3(l) * vec3(0.85, 0.85, 0.88), winter_amount * 0.35);
	}
	if (bloom_amount > 0.0) {
		albedo = mix(albedo, albedo * vec3(0.92, 1.04, 0.9), bloom_amount * 0.3);
	}
	ALBEDO = albedo;
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = 1.0;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
