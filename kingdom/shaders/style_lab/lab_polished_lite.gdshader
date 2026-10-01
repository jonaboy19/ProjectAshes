// Style Lab E
// "Low-end safe polished": lab_polished without rim and hemispheric bounce emission, lit per vertex
// (vertex_lighting), so the fragment shader is one texture tap and ~10 ALU. Works on Compatibility.
// Keeps the saturation grade, warm tint and the height-based contact-AO ramp (all baked into albedo).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx, vertex_lighting;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cut = 0.0;
uniform float saturation = 1.22;
uniform float value_gain = 1.04;
uniform vec3 warm_tint : source_color = vec3(1.04, 1.0, 0.94);
uniform vec3 sky_bounce : source_color = vec3(0.50, 0.62, 0.95);
uniform vec3 ground_bounce : source_color = vec3(0.95, 0.72, 0.42);
uniform float bounce = 0.22;
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float rim_amount = 0.35;
uniform float ao_height = 0.9;
uniform float ao_strength = 0.30;
uniform float roughness = 0.72;
uniform float spec = 0.35;
varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV * uv_scale + uv_offset);
	vec3 c = t.rgb * albedo_color.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * value_gain * warm_tint;
	float ao = 1.0 - ao_strength * (1.0 - smoothstep(0.0, ao_height, wpos.y));
	c *= ao;
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = spec;
	// cheap hemispheric fill baked into albedo-ish emission (no fresnel, no pow)
	EMISSION = c * mix(ground_bounce, sky_bounce, wnor.y * 0.5 + 0.5) * bounce;
	if (alpha_cut > 0.0) {
		ALPHA = t.a * albedo_color.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}
