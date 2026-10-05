// Tier-A hero garment shader (HeroOutfit skinned mesh + G6 armour/boots).
// Material identity comes from ROUGHNESS + NORMAL, not colour: UV2.x = material id
//   0 linen (fine plain weave), 1 wool (felted, fuzzy sheen), 2 leather (pebbled grain, satin, edge wear),
//   3 metal (brushed brass/iron, metallic), 4 textured asset (albedo_tex, kind from `asset_kind`)
// UV = garment coords in metres-ish (u around, v down) for weave/stitch; UV2.y = sway weight (0 rigid .. 1 free hem/hood tip).
// Stitching: dashed seam where fract(UV.y * stitch_rows) is near 0 on leather (vertex alpha < 0.5 = no seams).
// Secondary motion: model-space offset `sway` (set per frame by HeroTierA from capsule acceleration) * UV2.y, plus idle flutter.
// Cost: 1 noise tap + ~70 ALU; no extra passes. Mobile-safe (no SSS/transmission features).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;   // tileable grey noise 256
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;
uniform bool use_vertex_color = true;
uniform int asset_kind = 0;           // material id used when UV2 is absent (G6 meshes)
uniform bool has_uv2 = true;
uniform vec3 sway = vec3(0.0);        // model-space metres at weight 1
uniform float flutter = 0.004;
uniform float weave_scale = 340.0;
uniform float grain_scale = 60.0;
uniform float stitch_rows = 9.0;
uniform float saturation = 1.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.66);

varying float v_mat;
varying float v_sway;

void vertex() {
	v_mat = has_uv2 ? UV2.x : float(asset_kind);
	v_sway = has_uv2 ? UV2.y : 0.0;
	if (v_sway > 0.0) {
		float w = v_sway * v_sway;
		float t = TIME * 2.3 + VERTEX.y * 9.0 + VERTEX.x * 5.0;
		VERTEX += sway * w + vec3(sin(t), 0.0, cos(t * 0.8)) * flutter * w;
	}
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 c = use_vertex_color ? COLOR.rgb : vec3(1.0);
	vec2 uvt = UV;
	if (use_albedo_tex) { c *= texture(albedo_tex, UV).rgb; uvt = UV * 6.0; }
	int id = int(v_mat + 0.5);
	float n1 = texture(noise_tex, uvt * 3.1).r;
	float n2 = texture(noise_tex, uvt * 0.7 + 0.37).r;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	float rough = 0.9;
	float spec = 0.25;
	float metal = 0.0;
	float sheen = 0.0;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	if (id == 0) {                       // linen: crossing threads, very rough, slight slub variation
		vec2 w = uvt * weave_scale;
		float wx = sin(w.x * 3.14159), wy = sin(w.y * 3.14159);
		float cross = step(0.0, sin(floor(w.x) * 3.14159 + floor(w.y) * 3.14159 + 1.57));
		nrm.xy = vec2(wx * cross, wy * (1.0 - cross)) * 0.35 + (n1 - 0.5) * 0.25;
		c *= 0.92 + 0.12 * n2 + 0.05 * (wx * wy);
		rough = 0.93; spec = 0.18; sheen = 0.25;
	} else if (id == 1) {                // wool: felted, low-frequency lumps, strong fuzzy rim
		nrm.xy = vec2(n1 - 0.5, n2 - 0.5) * 0.7;
		c *= 0.86 + 0.22 * n1;
		rough = 1.0; spec = 0.08; sheen = 0.75;
	} else if (id == 2) {                // leather: pebbled grain, satin sheen, lighter worn edges, stitched seams
		vec2 g = uvt * grain_scale;
		float cell = texture(noise_tex, g * 0.05).r;
		nrm.xy = (vec2(texture(noise_tex, g * 0.05 + vec2(0.003, 0.0)).r, texture(noise_tex, g * 0.05 + vec2(0.0, 0.003)).r) - cell) * 7.0;
		float wear = smoothstep(0.55, 0.85, n2 + (1.0 - COLOR.a) * 0.0);
		float edge = smoothstep(0.75, 1.0, abs(fract(UV.y * stitch_rows * 0.5) * 2.0 - 1.0));   // rolled panel edges
		c = mix(c, c * 1.3 + 0.02, clamp(wear * 0.3 + edge * 0.3, 0.0, 1.0));
		c *= (0.82 + 0.16 * cell) * 0.85;
		rough = mix(0.55, 0.78, n1) + edge * 0.1; spec = 0.3;
		// dashed stitch line just inside each panel edge
		float row = abs(fract(UV.y * stitch_rows) - 0.12);
		float dash = step(0.5, fract(UV.x * 140.0));
		float st = (1.0 - smoothstep(0.008, 0.02, row)) * dash * step(0.5, COLOR.a);
		c = mix(c, vec3(0.62, 0.5, 0.34), st * 0.55);
		nrm.xy += vec2(0.0, st * 0.6);
	} else if (id == 3) {                // metal: brushed, darker in recesses, bright worn highlights
		nrm.xy = vec2((texture(noise_tex, vec2(uvt.x * 40.0, uvt.y * 0.5)).r - 0.5) * 0.25, 0.0);
		c *= 0.8 + 0.3 * n1;
		rough = 0.32 + 0.2 * n2; spec = 0.5; metal = 0.85;
	} else if (id == 5) {                // hair tufts: strand normal + Kajiya-style shifted band (anisotropic look, no light())
		float strands = texture(noise_tex, vec2(uvt.x * 30.0, uvt.y * 1.5)).r;
		nrm.xy = vec2((strands - 0.5) * 0.9, 0.0);
		c *= 0.75 + 0.45 * strands;
		float band = pow(clamp(1.0 - abs(dot(normalize(NORMAL + VIEW * 0.4), vec3(0.0, 1.0, 0.0)) - 0.35) * 3.0, 0.0, 1.0), 3.0);
		rough = 0.55; spec = 0.35; sheen = 0.5;
		c += vec3(0.16, 0.11, 0.07) * band * strands;
	} else {                             // generic textured cloth (G6 asset)
		nrm.xy = vec2(n1 - 0.5, n2 - 0.5) * 0.3;
		rough = 0.88; sheen = 0.4;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c;
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = (c * 0.7 + rim_color * 0.3) * fres * sheen * 0.35;
}
