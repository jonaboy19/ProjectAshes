// Tier-A hero hair: layered alpha cards (UV.y root 0 -> tip 1, 4 clumps across UV.x) + the scalp cap (`cap` = true).
// Anisotropic Kajiya-Kay in light(): strand direction = mesh binormal (along UV.y), two shifted lobes (white primary,
// tinted secondary). Alpha scissor (no sorting, mobile safe). Tips sway with `sway` (model space, from HeroFaceDriver)
// plus a small idle flutter. Also used for lashes/brows (`lash` = true: no anisotropy, darker).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D strand_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec3 root_color : source_color = vec3(0.17, 0.10, 0.06);
uniform vec3 tip_color : source_color = vec3(0.42, 0.27, 0.15);
uniform vec3 spec2_color : source_color = vec3(0.75, 0.5, 0.3);
uniform bool cap = false;
uniform bool lash = false;
uniform float alpha_cut = 0.4;
uniform vec3 sway = vec3(0.0);
uniform float flutter = 0.0025;

varying vec3 v_strand;
varying float v_t;

void vertex() {
	v_t = UV.y;
	if (!cap && !lash) {
		float w = UV.y * UV.y;
		float t = TIME * 2.0 + VERTEX.x * 30.0 + VERTEX.z * 20.0;
		VERTEX += (sway + vec3(sin(t), 0.0, cos(t * 1.3)) * flutter) * w;
	}
	v_strand = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 s = cap ? vec4(0.6, 0.6, 0.6, 1.0) : texture(strand_tex, UV);
	if (lash) {
		ALBEDO = s.rgb;
		ALPHA = s.a;
		ALPHA_SCISSOR_THRESHOLD = 0.35;
		ROUGHNESS = 0.8;
		SPECULAR = 0.1;
	} else {
		vec3 c = mix(root_color, tip_color, cap ? 0.15 : smoothstep(0.0, 1.0, v_t)) * (0.75 + 0.4 * s.r);
		ALBEDO = c;
		ALPHA = s.a;
		ALPHA_SCISSOR_THRESHOLD = cap ? 0.0 : alpha_cut;
		ROUGHNESS = 0.6;
		SPECULAR = 0.3;
		AO = cap ? 0.55 : mix(0.6, 1.0, v_t);           // self-shadowing toward the roots
		AO_LIGHT_AFFECT = 0.6;
	}
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0);          // soft wrap: hair volume
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / 3.14159;
	if (!lash && !cap) {
		vec3 h = normalize(LIGHT + VIEW);
		vec3 tng = v_strand;
		float th1 = dot(normalize(tng + NORMAL * 0.12), h);
		float th2 = dot(normalize(tng - NORMAL * 0.18), h);
		float s1 = pow(sqrt(max(0.0, 1.0 - th1 * th1)), 90.0);
		float s2 = pow(sqrt(max(0.0, 1.0 - th2 * th2)), 22.0);
		SPECULAR_LIGHT += (vec3(s1) * 0.12 + spec2_color * s2 * 0.12 * ALBEDO * 3.0) * ndl * ATTENUATION * LIGHT_COLOR;
	}
}
