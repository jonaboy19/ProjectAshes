// Tier-A hero eye: procedural sclera + iris + pupil on a UV sphere whose UV is radial around the front pole
// (UV distance from (0.5,0.5): 0 = pupil centre, 0.5 = back of the ball). Wet cornea: low roughness + a catchlight so the
// eye "lights up" even in shadow; lid occlusion darkens the top of the ball. No textures except the shared noise.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 iris_color : source_color = vec3(0.33, 0.22, 0.11);
uniform vec3 iris_outer : source_color = vec3(0.16, 0.12, 0.07);
uniform vec3 sclera_color : source_color = vec3(0.86, 0.82, 0.76);
uniform float iris_r = 0.062;
uniform float pupil_r = 0.022;
uniform vec3 catch_dir = vec3(0.35, 0.45, 0.82);     // view-space catchlight direction

varying vec3 v_obj;

void vertex() { v_obj = VERTEX; }

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float fib = texture(noise_tex, vec2(ang * 0.6, r * 3.0)).r;
	vec3 iris = mix(iris_color * (0.75 + 0.6 * fib), iris_outer, smoothstep(iris_r * 0.55, iris_r, r));
	iris = mix(iris, iris_color * 1.6 + 0.04, smoothstep(pupil_r * 1.6, pupil_r * 1.1, r) * 0.35);    // collarette
	vec3 sclera = sclera_color * (0.97 + 0.06 * fib);
	sclera = mix(sclera, vec3(0.85, 0.55, 0.5), smoothstep(0.1, 0.22, r) * 0.25);                 // warmer at the corners
	vec3 c = mix(iris, sclera, smoothstep(iris_r - 0.006, iris_r + 0.004, r));
	c = mix(c, vec3(0.08, 0.06, 0.05), smoothstep(iris_r - 0.012, iris_r, r) * (1.0 - smoothstep(iris_r, iris_r + 0.008, r)) * 0.7);   // limbal ring
	c = mix(vec3(0.015), c, smoothstep(pupil_r - 0.004, pupil_r + 0.002, r));
	// lid occlusion: the upper part of the visible ball sits in the lid's shadow
	float lid = smoothstep(0.02, 0.16, q.y) * 0.5 + smoothstep(0.09, 0.2, r) * 0.35;
	c *= 1.0 - lid;
	ALBEDO = c;
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	// catchlight: small sharp highlight fixed in view space (reads as the sky reflection on a wet cornea)
	float cl = pow(clamp(dot(normalize(NORMAL), normalize(catch_dir)), 0.0, 1.0), 900.0);
	EMISSION = vec3(1.0, 0.97, 0.9) * cl * 1.6 * step(r, 0.2);
}
