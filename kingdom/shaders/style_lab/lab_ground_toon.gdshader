// Style Lab ground, toon (B): cobbles -> mud -> grass splat from vertex colour (R = mud, B = cobble), with noise-broken
// edges. Painted flat colour with the toon ramp; no normal maps. Cost: 3 albedo taps + 2 noise taps.
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
	ROUGHNESS = 1.0;
}

void light() {
	float s = (dot(NORMAL, LIGHT) * 0.5 + 0.5) * ATTENUATION;
	float b1 = smoothstep(0.31, 0.41, s);
	float b2 = smoothstep(0.57, 0.67, s);
	vec3 ramp = mix(vec3(0.33, 0.29, 0.47), vec3(0.78), b1);
	ramp = mix(ramp, vec3(1.15), b2);
	DIFFUSE_LIGHT += LIGHT_COLOR * ramp * 0.62;
}
