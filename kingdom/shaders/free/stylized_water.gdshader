// Original work written for Rising Ashes (no third-party code). Same licence as the project.
// Replaces the godotshaders.com "Water Shader 3D" candidate (site blocked automated licence verification).
// Simple stylised water for LOW/MID tiers: no screen or depth texture reads. Two-tone gradient by view angle,
// drifting cel-banded ripple highlights, sparkle, gentle vertex waves. Mobile-safe.
// For depth foam and refraction use shaders/water.gdshader (HIGH tier).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;
uniform vec4 shallow_color : source_color = vec4(0.30, 0.78, 0.80, 0.85);
uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.62, 0.92);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform float wave_height = 0.03;
uniform float speed = 0.35;
uniform float ripple_scale = 6.0;
varying vec3 wp;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(wp.x * 1.3 + TIME * 1.1) + sin(wp.z * 1.7 - TIME * 0.9)) * 0.5 * wave_height;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec4 base = mix(shallow_color, deep_color, clamp(fres * 1.2, 0.0, 1.0));
	vec2 p = wp.xz * ripple_scale * 0.25;
	float n = vn(p + vec2(TIME * speed, TIME * speed * 0.6)) + vn(p * 2.1 - vec2(TIME * speed * 0.7, 0.0));
	n *= 0.5;
	float band = smoothstep(0.62, 0.66, n);
	float spark = smoothstep(0.78, 0.8, vn(p * 4.0 + TIME * 0.5));
	vec3 c = base.rgb + foam_color.rgb * (band * 0.25 + spark * 0.5);
	ALBEDO = c;
	ALPHA = base.a;
	ROUGHNESS = 1.0;
	EMISSION = c * 0.15;
}
