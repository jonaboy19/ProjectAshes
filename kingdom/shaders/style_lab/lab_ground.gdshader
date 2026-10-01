// Style Lab ground (C grounded / D,E polished): cobbles -> mud -> grass splat from vertex colour (R = mud, B = cobble), with noise-broken
// edges. mode 1 = PBR grounded (C: normal + roughness + puddles), 2 = clean polished (D/E). Toon version: lab_ground_toon.gdshader.
// Cost: 3 layers x (albedo [+ normal + arm in mode 1]) taps. Mode 1 is the expensive one.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform int mode = 2;
uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 2.6;
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 mud_tint : source_color = vec3(1.0);
uniform vec3 cobble_tint : source_color = vec3(1.0);
uniform float saturation = 1.0;
uniform float posterize = 0.0;
uniform float puddles = 0.0;
varying vec3 wpos;

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 uv = wpos.xz / tile;
	float nz = texture(noise_tex, wpos.xz * 0.11).r;
	float nz2 = texture(noise_tex, wpos.xz * 0.9).r;
	float wm = clamp(COLOR.r + (nz - 0.5) * 0.7, 0.0, 1.0);
	float wc = clamp(COLOR.b + (nz2 - 0.5) * 0.45 + (nz - 0.5) * 0.3, 0.0, 1.0);
	wm = smoothstep(0.38, 0.62, wm);
	wc = smoothstep(0.42, 0.58, wc);
	vec3 g = texture(grass_a, uv * 1.15).rgb * grass_tint;
	vec3 m = texture(mud_a, uv * 0.9).rgb * mud_tint;
	vec3 k = texture(cobble_a, uv * 0.8).rgb * cobble_tint;
	vec3 c = mix(g, m, wm);
	c = mix(c, k, wc);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	if (posterize > 0.0) {
		float steps = 10.0;
		c = mix(c, floor(c * steps + 0.5) / steps, posterize);
	}
	ALBEDO = c;
	if (mode == 1) {
		vec3 ng = texture(grass_n, uv * 1.15).rgb;
		vec3 nm = texture(mud_n, uv * 0.9).rgb;
		vec3 nk = texture(cobble_n, uv * 0.8).rgb;
		vec3 n = mix(mix(ng, nm, wm), nk, wc);
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = 1.0;
		float rg = texture(grass_r, uv * 1.15).g;
		float rm = texture(mud_r, uv * 0.9).g;
		float rk = texture(cobble_r, uv * 0.8).g;
		float rough = mix(mix(rg, rm, wm), rk, wc);
		float pud = smoothstep(0.55, 0.75, nz) * puddles * (wm * 0.8 + wc * 0.4);
		ROUGHNESS = mix(rough, 0.08, pud);
		ALBEDO *= 1.0 - pud * 0.35;
		AO = mix(1.0, mix(mix(texture(grass_r, uv * 1.15).r, texture(mud_r, uv * 0.9).r, wm), texture(cobble_r, uv * 0.8).r, wc), 0.8);
		AO_LIGHT_AFFECT = 0.4;
	} else {
		ROUGHNESS = 0.95;
		SPECULAR = 0.15;
	}
}
