// Style Lab C "Grounded medieval": real CC0 PBR detail (Poly Haven) projected on the dominant world axis
// (one tap per map, no triplanar blend, so 2 sets x 3 maps = 6 taps) over the object's own painted atlas, which
// is only used for colour identity (timber vs plaster vs red roof). Grime climbs from the ground, moss
// grows on upward faces, everything is desaturated toward an earthy palette.
// Cost: ~7 texture taps, ~60 ALU. HIGH tier only; MEDIUM/LOW should use a baked variant (see docs).
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
#include "res://shaders/camera_see_through.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 atlas_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cut = 0.0;
// set A = light areas (plaster, stone), set B = dark areas (timber)
uniform sampler2D a_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile_a = 2.2;
uniform float tile_b = 1.6;
uniform float detail = 0.8;          // how much PBR albedo replaces the atlas colour
uniform float chroma_keep = 0.75;    // how much of the atlas hue is kept
uniform float saturation = 0.78;
uniform float grime = 0.55;
uniform float moss = 0.5;
uniform vec3 moss_color : source_color = vec3(0.23, 0.30, 0.10);
uniform vec3 grime_color : source_color = vec3(0.10, 0.075, 0.05);
uniform float normal_depth = 1.0;
uniform float rough_bias = 0.0;
varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (hero_see_through(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)) {
		discard;
	}
	vec4 at = texture(atlas, UV * uv_scale + uv_offset);
	vec3 base = at.rgb * atlas_color.rgb;
	if (use_vertex_color) { base *= COLOR.rgb; }
	float luma = max(dot(base, vec3(0.299, 0.587, 0.114)), 0.04);
	vec3 chroma = base / luma;
	// planar projection on the dominant axis
	vec3 an = abs(wnor);
	vec2 p;
	if (an.y > an.x && an.y > an.z) { p = wpos.xz; }
	else if (an.x > an.z) { p = wpos.zy; }
	else { p = wpos.xy; }
	vec3 a = texture(a_alb, p / tile_a).rgb;
	vec3 b = texture(b_alb, p / tile_b).rgb;
	// dark atlas texels (beams, planks, iron) -> timber set, light ones -> plaster / stone set
	float wood = 1.0 - smoothstep(0.16, 0.42, luma);
	vec3 pbr = mix(a, b, wood);
	vec3 arm_a = texture(a_arm, p / tile_a).rgb;
	vec3 arm_b = texture(b_arm, p / tile_b).rgb;
	vec3 arm = mix(arm_a, arm_b, wood);
	vec3 nm = mix(texture(a_nor, p / tile_a).rgb, texture(b_nor, p / tile_b).rgb, wood);
	// colour: PBR luminance carries the detail, atlas chroma carries identity
	float pl = dot(pbr, vec3(0.299, 0.587, 0.114));
	vec3 tinted = pbr * mix(vec3(1.0), chroma, chroma_keep);
	vec3 col = mix(base, tinted * (luma / max(pl, 0.05) * 0.5 + 0.5), detail);
	// weathering: grime from the ground up, moss on upward faces and in the noise
	float nz = texture(noise_tex, wpos.xz * 0.35 + wpos.y * 0.2).r;
	float nz2 = texture(noise_tex, p * 1.3).r;
	float low = 1.0 - smoothstep(0.0, 1.6 + nz * 0.8, wpos.y);
	float streak = smoothstep(0.55, 0.9, nz2) * 0.35 * smoothstep(0.0, 4.0, wpos.y);
	col = mix(col, grime_color, clamp((low * 0.75 + streak) * grime, 0.0, 0.85));
	float up = smoothstep(0.35, 0.9, wnor.y);
	float mossy = clamp(up * smoothstep(0.35, 0.7, nz) * moss + low * smoothstep(0.55, 0.8, nz2) * moss * 0.8, 0.0, 0.9);
	col = mix(col, moss_color * (0.7 + nz2 * 0.6), mossy);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(arm.g, 1.0, mossy * 0.4) + rough_bias, 0.0, 1.0);
	METALLIC = 0.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_depth;
	if (alpha_cut > 0.0) {
		ALPHA = at.a * atlas_color.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}
