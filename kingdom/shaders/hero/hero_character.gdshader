// Tier-A material for a single-atlas (Meshy / AI-textured) character, skill ashes-hero-character.
// The atlas has no material IDs, so each texel is classified from its colour + where it sits on the body:
//   skin   (warm, mid saturation; any height)          -> faked SSS (wrapped, red-shifted terminator), pores, flush, T-zone sheen
//   hair   (dark warm brown above the neck)             -> anisotropic shifted highlight band, strand micro-normal
//   linen  (light, low saturation, below the neck)      -> fine weave normal, very rough, soft sheen
//   wool   (green / dyed, below the neck)               -> felted lumps, fully rough, fuzzy rim
//   leather(dark warm brown below the neck)             -> pebbled grain, satin roughness 0.5-0.7, worn highlights
//   metal  (grey, low saturation, bright spec in texture)-> metallic 0.8, roughness 0.35
// Class weights are soft (smoothstep), so seams in the atlas never show a hard line. Masks go to BACKLIGHT (skin) for light().
// Cost: 4 texture taps (albedo + 3 noise), ~90 ALU fragment, ~30 ALU per light. One material, one draw call.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float neck_y = 1.45;                 // skeleton-space height of the neck (set by HeroTierA)
uniform float saturation = 0.92;             // Style G: slightly muted
uniform float detail_scale = 1.0;
uniform vec3 flush_color : source_color = vec3(0.9, 0.42, 0.36);
uniform vec3 scatter_color : source_color = vec3(1.0, 0.38, 0.24);
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.68);
uniform float ambient_lift = 0.26;          // hero readability in back-lit shadow (character fill)
uniform float painterly = 0.7;
uniform float detail_strength = 0.5;        // calmer normals (close-up noise)
uniform bool use_mask = true;                // vertex COLOR.r = forced matte wool (hood), from hero_fix.py
uniform float debug_classes = 0.0;           // 1 = show the class map (QA)

varying vec3 v_pos;

void vertex() { v_pos = VERTEX; }

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV, 0.6).rgb * tint.rgb;          // slight mip bias: calmer AI texture noise
	vec3 c_soft = texture(albedo_tex, UV, 1.6).rgb * tint.rgb;      // painterly: skin uses a softer mip (Style G, not photo)
	vec3 hsv = rgb2hsv(c);
	float head = smoothstep(neck_y - 0.03, neck_y + 0.02, v_pos.y);
	float warm = 1.0 - smoothstep(0.08, 0.14, abs(hsv.x - 0.06));             // orange/red-brown hues
	float skin = warm * smoothstep(mix(0.34, 0.18, head), mix(0.44, 0.3, head), hsv.y) * (1.0 - smoothstep(0.62, 0.75, hsv.y)) * smoothstep(0.38, 0.55, hsv.z);
	float darkbrown = warm * (1.0 - smoothstep(0.3, 0.45, hsv.z)) * smoothstep(0.12, 0.25, hsv.y);
	float hair = head * darkbrown * (1.0 - skin);
	float leather = (1.0 - head) * darkbrown * (1.0 - skin);
	float metal = (1.0 - smoothstep(0.06, 0.14, hsv.y)) * smoothstep(0.35, 0.5, hsv.z) * (1.0 - head) * (1.0 - smoothstep(0.75, 0.85, hsv.z));
	float green = (1.0 - smoothstep(0.06, 0.12, abs(hsv.x - 0.22))) * smoothstep(0.08, 0.2, hsv.y);
	float wool = (1.0 - head) * green * (1.0 - skin);
	float linen = (1.0 - head) * smoothstep(0.5, 0.65, hsv.z) * (1.0 - smoothstep(0.15, 0.3, hsv.y)) * (1.0 - metal);
	skin *= 1.0 - wool;
	c = mix(c, c_soft, skin * painterly);
	// tame painted lipstick-red: very saturated red skin texels -> muted warm lip tone
	float lipred = (1.0 - smoothstep(0.03, 0.06, abs(hsv.x - 0.0) * (hsv.x > 0.5 ? 0.0 : 1.0) + (hsv.x > 0.9 ? 0.0 : 0.0))) * smoothstep(0.5, 0.7, hsv.y);
	c = mix(c, vec3(dot(c, vec3(0.333))) * vec3(1.12, 0.82, 0.74), clamp(lipred, 0.0, 1.0) * 0.6);
	c *= vec3(1.04, 1.0, 0.95);                                     // Style G warm grade
	if (use_mask && COLOR.r > 0.5) { skin = 0.0; hair = 0.0; leather = 0.0; metal = 0.0; linen = 0.0; wool = 1.0; }
	float other = clamp(1.0 - skin - hair - leather - metal - wool - linen, 0.0, 1.0);

	vec2 duv = UV * 2048.0 / 64.0 * detail_scale;          // ~1 noise tile per 64 atlas texels
	float n1 = texture(noise_tex, duv).r;
	float n2 = texture(noise_tex, duv * 0.37 + 0.31).r;
	float n3 = texture(noise_tex, duv * 2.9 + 0.7).r;
	vec2 nrm = vec2(0.0);
	// skin: pores + flush where the painted skin is already reddish (cheeks, nose, ears)
	nrm += vec2(n3 - 0.5, n1 - 0.5) * 0.08 * skin;
	float redness = smoothstep(0.02, 0.06, 0.06 - hsv.x) * smoothstep(0.3, 0.45, hsv.y);
	c = mix(c, c * flush_color * 1.6, redness * skin * 0.25);
	// hair: strands along the atlas V, shifted highlight added in light() via ROUGHNESS band
	nrm += vec2((n3 - 0.5) * 0.9, 0.0) * hair;
	// linen weave
	vec2 w = UV * 2048.0 * 0.5;
	nrm += vec2(sin(w.x * 3.14159), sin(w.y * 3.14159)) * 0.18 * linen + vec2(n1 - 0.5, 0.0) * 0.2 * linen;
	// wool felt
	nrm += vec2(n1 - 0.5, n2 - 0.5) * 0.6 * wool;
	c *= 1.0 + (n2 - 0.5) * 0.18 * wool;
	// leather grain + worn lighter patches
	nrm += vec2(n3 - n1, n3 - n2) * 0.9 * leather;
	c = mix(c, c * 1.25, smoothstep(0.62, 0.8, n2) * 0.5 * leather);
	// metal: brushed
	nrm += vec2((n3 - 0.5) * 0.3, 0.0) * metal;

	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	ALBEDO = mix(c, skin * vec3(1, 0.6, 0.5) + hair * vec3(0.4, 0.25, 0.1) + leather * vec3(0.5, 0.3, 0.1) + metal * vec3(0.7) + wool * vec3(0.2, 0.6, 0.2) + linen * vec3(0.9, 0.9, 0.7), debug_classes);
	NORMAL_MAP = normalize(vec3(nrm * detail_strength, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = skin * mix(0.52, 0.42, smoothstep(0.55, 0.75, hsv.z)) + hair * 0.5 + leather * mix(0.5, 0.72, n1) + metal * 0.35
		+ wool * 1.0 + linen * 0.92 + other * mix(0.85, 0.8, head);
	METALLIC = metal * 0.8;
	SPECULAR = 0.35 + 0.15 * leather - 0.2 * (wool + linen) - 0.25 * other * head;
	BACKLIGHT = vec3(skin, hair, wool + linen);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (c * 0.7 + rim_color * 0.3) * fres * (0.2 * (wool + linen) + 0.08 * skin) + c * ambient_lift;
}

void light() {
	float skin = BACKLIGHT.r;
	float hair = BACKLIGHT.g;
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp(ndl, 0.0, 1.0);
	float wrap = 0.4 * skin + 0.45 * BACKLIGHT.b + 0.3 * (1.0 - skin - hair);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 diff = vec3(d) + scatter_color * (w - d) * skin * 0.6 + vec3(w - d) * (1.0 - skin) * 0.5;
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / 3.14159;
	vec3 h = normalize(LIGHT + VIEW);
	float a = max(ROUGHNESS * ROUGHNESS, 0.02);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float dd = ndh * ndh * (a * a - 1.0) + 1.0;
	float ggx = (a * a) / (3.14159 * dd * dd);
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 spec = f0 * ggx * d * (1.0 - hair);
	// hair: Kajiya-Kay band around the strand axis (atlas V ~ up the head), tinted by the hair colour
	vec3 up = normalize((INV_VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 tng = normalize(up - NORMAL * dot(up, NORMAL) + NORMAL * 0.1);
	float th = dot(tng, h);
	float kk = pow(sqrt(max(0.0, 1.0 - th * th)), 60.0);
	spec += (vec3(0.25) + ALBEDO * 1.5) * kk * 0.35 * hair * d;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR;
}
