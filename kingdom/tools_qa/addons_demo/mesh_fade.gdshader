// Full-mesh side of the impostor crossfade (QA demo). Same dither noise as impostor_octa.gdshader but complementary:
// the mesh keeps pixel p while noise(p) < keep, the impostor keeps it otherwise, so the two never leave a hole or double-draw.
// Godot's own visibility-range fade did NOT fade MultiMesh cells in the Mobile renderer (hard switch), hence this shader pair.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform vec3 center = vec3(0.0);           // same bounding-sphere centre as the impostor
uniform float fade_out_start = 42.5;       // camera distance where the mesh starts to dither out
uniform float fade_len = 5.0;              // metres until it is gone

varying float v_dist;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	v_dist = distance(CAMERA_POSITION_WORLD, (MODEL_MATRIX * vec4(center, 1.0)).xyz);
}

void fragment() {
	float keep = 1.0 - clamp((v_dist - fade_out_start) / fade_len, 0.0, 1.0);
	if (keep <= ign(FRAGCOORD.xy)) {
		discard;
	}
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb * albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
}
