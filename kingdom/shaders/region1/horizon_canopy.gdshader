shader_type spatial;
render_mode cull_back, specular_disabled;
// Far canopy blobs (scripts/region1/region1_horizon.gd): painted tree-clump domes for forests beyond the
// streamed ring; collapsed inside the ring, where the real trees stand. COLOR.r = height 0 (base) .. 1 (top),
// INSTANCE_CUSTOM.r = per-blob tint variation.

uniform vec2 ring_min = vec2(0.0);
uniform vec2 ring_max = vec2(0.0);
uniform vec3 shade_color : source_color = vec3(0.12, 0.24, 0.12);
uniform vec3 lit_color : source_color = vec3(0.42, 0.62, 0.2);
uniform vec3 rim_color : source_color = vec3(0.72, 0.8, 0.32);
varying float v_h;
varying float v_t;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	if (o.x > ring_min.x && o.z > ring_min.y && o.x < ring_max.x && o.z < ring_max.y) {
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
