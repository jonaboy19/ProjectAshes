// Original work written for Rising Ashes (no third-party code). Same licence as the project.
// Replaces the godotshaders.com "stylized multimesh grass" candidate (site blocked automated licence verification).
// Blade cards for MultiMesh: gradient dark root -> bright yellow-green tip, tapered blade cut-out, wind waves.
// Mesh convention: a QuadMesh with UV.y = 0 at the tip and 1 at the root (Godot default), pivot at the root
// (use center_offset so the quad sits on the ground). Mobile: vertex-only animation, cutout. Cheap; chunk instances.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert;
uniform vec4 root_color : source_color = vec4(0.14, 0.36, 0.12, 1.0);
uniform vec4 tip_color : source_color = vec4(0.72, 0.86, 0.25, 1.0);
uniform float wind_strength = 0.22;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(1.0, 0.4);
varying float h;
varying vec3 wp;

void vertex() {
	h = 1.0 - UV.y;
	wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float gust = sin(dot(wp.xz, normalize(wind_dir)) * 0.6 - TIME * wind_speed) * 0.5 + 0.5;
	float flut = sin(TIME * wind_speed * 3.0 + wp.x * 4.0) * 0.25;
	vec2 d = normalize(wind_dir) * (gust + flut) * wind_strength * h * h;
	VERTEX.x += d.x;
	VERTEX.z += d.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float w = abs(UV.x - 0.5) * 2.0;
	if (w > 1.0 - h * 0.95) {
		discard;
	}
	float patch_v = sin(wp.x * 0.8) * sin(wp.z * 0.7) * 0.5 + 0.5;
	vec3 c = mix(root_color.rgb, tip_color.rgb, h);
	c = mix(c, c * vec3(1.15, 1.05, 0.7), patch_v * 0.35);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
