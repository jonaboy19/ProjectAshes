// Style Lab B ink outline: inverted hull, second pass of the toon material (next_pass). Width grows with
// distance so the line keeps a roughly constant screen thickness. The line colour is the albedo darkened
// and warmed ("coloured ink"), not black. Cost: the mesh is drawn twice (2x draw calls and vertices, but
// cheap fragments: 1 texture tap). Skip it for LOW or fall back to LOD0 only.
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool use_vertex_color = false;
uniform float width = 0.003;      // fraction of view depth: constant screen thickness
uniform vec3 ink : source_color = vec3(0.16, 0.08, 0.05);
uniform float ink_mix = 0.55;

void vertex() {
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	VERTEX += normalize(NORMAL) * width * d;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV * uv_scale + uv_offset).rgb * albedo_color.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	ALBEDO = mix(c * 0.28, ink, ink_mix);
}
