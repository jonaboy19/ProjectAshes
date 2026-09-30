shader_type spatial;
// Vertex Animation Texture crowd (scripts/living_world/vat_crowd.gd, VatAsset).
// Every MultiMesh instance plays its own clip at its own phase and speed, so a field of workers never moves in
// lockstep. Per-instance INSTANCE_CUSTOM (all exact integers in float32):
//   x = sign * (row * 1024 + frames)   sign < 0: a one-shot that holds its last frame; > 0: a loop
//   y = phase in seconds (the clip time at vat_time == 0; VatCrowd sets it so a skeletal -> VAT hand-off keeps
//       the exact pose)
//   z = playback speed (0 = frozen)
//   w = clothing tint packed as r*65536 + g*256 + b (0..255 each, 128 = unchanged); skin/hair (mask 0) untinted
// Mesh: COLOR.rgb = baked albedo (linear), COLOR.a = tint mask; UV2.x = texture column of the vertex.
render_mode cull_back, specular_disabled, diffuse_lambert;

uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform float vat_fps = 10.0;
uniform vec4 debug_tint = vec4(0.0);   // QA: LOD visualisation (a = strength)
global uniform float vat_time;

varying vec3 v_albedo;

void vertex() {
	float packed = INSTANCE_CUSTOM.x;
	float loops = packed >= 0.0 ? 1.0 : 0.0;
	float pk = abs(packed);
	float row = floor(pk / 1024.0);
	float frames = pk - row * 1024.0;
	float t = (vat_time * INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.y) * vat_fps;
	float fa = loops > 0.5 ? mod(t, frames) : clamp(t, 0.0, frames - 1.0);
	float fl = floor(fa);
	float w = fa - fl;
	int a = int(fl);
	int b = loops > 0.5 ? int(mod(fl + 1.0, frames)) : min(a + 1, int(frames) - 1);
	int col = int(UV2.x + 0.5);
	int r = int(row + 0.5);
	vec3 pa = texelFetch(vat_pos, ivec2(col, r + a), 0).xyz;
	vec3 pb = texelFetch(vat_pos, ivec2(col, r + b), 0).xyz;
	VERTEX = mix(pa, pb, w);
	vec3 na = texelFetch(vat_nrm, ivec2(col, r + a), 0).xyz * 2.0 - 1.0;
	vec3 nb = texelFetch(vat_nrm, ivec2(col, r + b), 0).xyz * 2.0 - 1.0;
	NORMAL = normalize(mix(na, nb, w));
	float tp = INSTANCE_CUSTOM.w;
	vec3 tint = vec3(floor(tp / 65536.0), mod(floor(tp / 256.0), 256.0), mod(tp, 256.0)) / 128.0;
	v_albedo = COLOR.rgb * mix(vec3(1.0), tint, COLOR.a);
}

void fragment() {
	ALBEDO = mix(v_albedo, debug_tint.rgb, debug_tint.a);
	ROUGHNESS = 0.9;
}
