// Wind + soft shading for the generated grass / flower card meshes (nature/*.glb).
// Mesh convention (written by kingdom/tools/blender/make_nature.py):
//   COLOR.r = bend weight: 0 at the ground, 1 at the blade tip (linear in height)
//   COLOR.g = per-card random phase 0..1
//   COLOR.b = 0.5 reserved, COLOR.a = 1
// COLOR is wind data here, NOT albedo, so this shader never multiplies it into ALBEDO.
// Custom normals point mostly up (terrain-like lighting); the back face keeps the same normal
// instead of Godot's automatic flip, so grass seen from either side shades the same.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec2 wind_direction = vec2(1.0, 0.35);   // world XZ
uniform float wind_strength = 0.12;               // metres of tip sway
uniform float wind_speed = 1.4;
uniform float gust_scale = 0.07;                  // spatial frequency of gust waves (1/m)

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.r * COLOR.r;                   // stiff base, soft tips
	float ph = COLOR.g * 6.2831853;
	vec2 dir = normalize(wind_direction);
	float gust = sin(TIME * wind_speed + dot(wp.xz, dir) * gust_scale * 6.2831853) * 0.5 + 0.5;
	float flutter = sin(TIME * wind_speed * 3.3 + ph + wp.x * 0.9 + wp.z * 0.6) * 0.3;
	vec2 off = dir * (0.25 + gust * 0.75 + flutter) * wind_strength * w;
	// world-space offset -> local (transpose == inverse for rotation; fine for ~uniform scale 1)
	vec3 off_l = (vec4(off.x, 0.0, off.y, 0.0) * MODEL_MATRIX).xyz;
	VERTEX += off_l;
	VERTEX.y -= dot(off, off) * 1.5 * w;           // tips dip a little as they bend
}

void fragment() {
	vec4 t = texture(albedo_texture, UV);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * backlight_amount;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;                          // undo the automatic back-face flip
	}
}
