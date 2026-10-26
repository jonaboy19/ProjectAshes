shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Existing project tree atlas, with ambient/direct scene lighting and normal fog.
// Atlas contains baked daylight; upward canopy normals avoid extra card-facing bands.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D built_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(1e9);
uniform float mask_cells = 17.0;
uniform sampler2D ground_built_mask : filter_nearest, repeat_disable;
uniform vec2 ground_mask_origin = vec2(1e9);
uniform float ground_mask_cells = 54.0;
varying float tree_tint;
bool covered(vec2 root, sampler2D mask, vec2 origin, float cells) {
	vec2 m = (root - origin) / 64.0;
	if (m.x < 0.0 || m.y < 0.0 || m.x >= cells || m.y >= cells) return false;
	return texture(mask, (floor(m) + 0.5) / cells).r > 0.5;
}
void vertex() {
	// UV2 holds tree root, so every vertex of one tree uses the same visibility decision.
	if (covered(UV2, built_mask, mask_origin, mask_cells)) {
		VERTEX = vec3(0.0);
	} else if (covered(UV2, ground_built_mask, ground_mask_origin, ground_mask_cells)) {
		VERTEX.y += CUSTOM0.r;
	}
	tree_tint = CUSTOM0.g;
}
void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * tree_tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	NORMAL = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	ROUGHNESS = 1.0;
	BACKLIGHT = c.rgb * 0.12;
}
