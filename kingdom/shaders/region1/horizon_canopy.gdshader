shader_type spatial;
render_mode cull_back, specular_disabled;
// Far canopy blobs (scripts/region1/region1_horizon.gd): painted tree-clump domes for forests beyond the
// streamed ring; collapsed inside the ring, where the real trees stand. COLOR.r = height 0 (base) .. 1 (top),
// INSTANCE_CUSTOM.r = per-blob tint variation.

// Built streamed chunks around the focus (region1_horizon.gd): 1 = a real 64 m chunk covers this ground.
uniform sampler2D built_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(1e9);
uniform float mask_cells = 17.0;
bool r1_built(vec2 xz) {
	vec2 m = (xz - mask_origin) / 64.0;
	if (m.x < 0.0 || m.y < 0.0 || m.x >= mask_cells || m.y >= mask_cells) return false;
	return texture(built_mask, (floor(m) + 0.5) / mask_cells).r > 0.5;
}
uniform vec3 shade_color : source_color = vec3(0.12, 0.24, 0.12);
uniform vec3 lit_color : source_color = vec3(0.42, 0.62, 0.2);
uniform vec3 rim_color : source_color = vec3(0.72, 0.8, 0.32);
varying float v_h;
varying float v_t;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	if (r1_built(o.xz)) {
		VERTEX = vec3(0.0);
	}
	v_h = COLOR.r;
	v_t = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 lit = mix(lit_color, lit_color * vec3(0.8, 0.95, 0.8), v_t);
	vec3 c = mix(shade_color, lit, smoothstep(0.1, 0.8, v_h));
	c = mix(c, rim_color, smoothstep(0.82, 1.0, v_h) * 0.5);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
