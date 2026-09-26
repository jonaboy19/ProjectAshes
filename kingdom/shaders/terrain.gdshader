shader_type spatial;
// Terrain surface: biome colour from the world generator (vertex colour),
// broken up with multi-scale procedural detail, rock on steep slopes and a
// detail normal map so the ground reads as soil and grass, not flat polygons.

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 rock_color : source_color = vec3(0.42, 0.40, 0.36);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float fine = texture(detail_noise, world_pos.xz * 0.45).r;
	float mid = texture(detail_noise, world_pos.xz * 0.08).r;
	float macro = texture(macro_noise, world_pos.xz * 0.004).r;
	vec3 col = base * (0.72 + 0.56 * fine) * (0.8 + 0.4 * mid);
	col = mix(col, col * vec3(1.18, 1.08, 0.72), smoothstep(0.45, 0.8, macro) * 0.6);   // dry patches
	float slope = 1.0 - world_normal.y;
	float rock_detail = texture(detail_noise, vec2(world_pos.x + world_pos.z, world_pos.y) * 0.25).r;
	vec3 rock = rock_color * rock_color * (0.6 + 0.8 * rock_detail);
	col = mix(col, rock, smoothstep(0.32, 0.5, slope));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	NORMAL_MAP = texture(detail_normal, world_pos.xz * 0.3).rgb;
	NORMAL_MAP_DEPTH = 0.8;
}
