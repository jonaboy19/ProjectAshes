// Style Lab B "Storybook painterly": banded toon light with a coloured shadow ramp, pigment mottling and
// a soft warm grade. Keeps the object's own albedo atlas. Cost: 1 texture + 1 noise tap, ~25 ALU, custom light().
// Works on Compatibility, Mobile and Forward+.
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cut = 0.0;
uniform sampler2D paint_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 shade_color : source_color = vec3(0.60, 0.52, 0.85);
uniform float saturation = 1.18;
uniform float mottle = 0.20;
uniform float light_gain = 1.0;
uniform float band_soft = 0.05;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV * uv_scale + uv_offset);
	vec3 c = t.rgb * albedo_color.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	// pigment pooling: low-frequency blotches + a finer brush grain, so flat areas read hand painted
	float n1 = texture(paint_noise, wpos.xz * 0.23 + wpos.y * 0.31).r;
	float n2 = texture(paint_noise, wpos.xy * 1.7 + wpos.zy * 1.3).r;
	c *= 1.0 + (n1 - 0.5) * mottle + (n2 - 0.5) * mottle * 0.7;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	if (alpha_cut > 0.0) {
		ALPHA = t.a * albedo_color.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float s = ndl * mix(0.0, 1.0, ATTENUATION);
	// three soft bands: cast shadow / core shadow, half tone, lit
	float b1 = smoothstep(0.36 - band_soft, 0.36 + band_soft, s);
	float b2 = smoothstep(0.62 - band_soft, 0.62 + band_soft, s);
	vec3 ramp = mix(shade_color * 0.55, vec3(0.78), b1);
	ramp = mix(ramp, vec3(1.15), b2);
	DIFFUSE_LIGHT += LIGHT_COLOR * ramp * light_gain * 0.62;
}
