shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Cave / Rift rock shell (ashes-environment-look, 2026-10-05). Replaces the single albedo-only
// triplanar StandardMaterial (muddy, stretched at 4.5 m per tile, no relief).
//  - World-space triplanar with sharpened blend weights (no stretching on any face), Poly Haven CC0
//    rocky_terrain_02 albedo + normal (whiteout-style blend) + ARM.
//  - Two scales: 2.6 m base and a 9 m macro tint, so walls do not repeat.
//  - Vertex colour (the dungeon theme tint and baked AO) still multiplies in.
//  - Up-facing ledges and the floor gather dust / grit (floor_tint); low walls get a damp band.
//  - LOW (ashes_ground_detail = 0): one dominant-axis tap, no normal map.
global uniform float ashes_ground_detail;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap, repeat_enable;
uniform float tile = 4.0;
// Large-scale breakup: the old generated rock blotch texture, triplanar at macro_tile, high contrast.
uniform sampler2D macro_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform float macro_tile = 7.0;
uniform float macro_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 rock_tint : source_color = vec3(1.05, 1.0, 0.98);
uniform vec3 floor_tint : source_color = vec3(0.86, 0.8, 0.74);
uniform vec3 damp_tint : source_color = vec3(0.55, 0.55, 0.60);
uniform float vcol_amount : hint_range(0.0, 1.0) = 0.0;
uniform float floor_y = 0.0;   // object-space floor level (the damp band sits just above it)

varying vec3 wp;
varying vec3 wn;
varying vec3 lp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lp = VERTEX;
}

void fragment() {
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec2 ux = wp.zy / tile, uy = wp.xz / tile, uz = wp.xy / tile;
	vec3 alb;
	vec3 arm;
	vec3 nw = wn;
	if (ashes_ground_detail > 0.0) {
		alb = texture(rock_albedo, ux).rgb * bw.x + texture(rock_albedo, uy).rgb * bw.y + texture(rock_albedo, uz).rgb * bw.z;
		arm = texture(rock_arm, ux).rgb * bw.x + texture(rock_arm, uy).rgb * bw.y + texture(rock_arm, uz).rgb * bw.z;
		// Whiteout triplanar normal blend in world space.
		vec3 tx = texture(rock_normal, ux).rgb * 2.0 - 1.0;
		vec3 ty = texture(rock_normal, uy).rgb * 2.0 - 1.0;
		vec3 tz = texture(rock_normal, uz).rgb * 2.0 - 1.0;
		vec3 s = sign(wn);
		vec3 nx = vec3(tx.xy + wn.zy, abs(tx.z) * wn.x);
		vec3 ny = vec3(ty.xy + wn.xz, abs(ty.z) * wn.y);
		vec3 nz = vec3(tz.xy + wn.xy, abs(tz.z) * wn.z);
		nw = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
	} else {
		vec2 u = bw.y > max(bw.x, bw.z) ? uy : (bw.x > bw.z ? ux : uz);
		alb = texture(rock_albedo, u).rgb;
		arm = texture(rock_arm, u).rgb;
	}
	// Macro breakup: big light/dark rock masses (triplanar, dominant axis) so walls read as stone, not gravel paint.
	vec2 mu = (bw.y > max(bw.x, bw.z) ? wp.xz : (bw.x > bw.z ? wp.zy : wp.xy)) / macro_tile;
	float mr = dot(texture(macro_rock, mu).rgb, vec3(0.33));
	float mr2 = dot(texture(macro_rock, mu * 0.31 + 0.5).rgb, vec3(0.33));
	float mm = smoothstep(0.15, 0.75, mr * 0.6 + mr2 * 0.6);
	alb *= rock_tint * mix(1.0, mix(0.45, 1.35, mm), macro_amount);
	// The scan is low-contrast: stretch it so pebbles and cracks read at gameplay distance.
	float l = dot(alb, vec3(0.3, 0.59, 0.11));
	alb = mix(vec3(l), alb, 0.45) * (1.0 + (l - 0.28) * 1.6);
	// Cool the warm scan toward Rift violet-grey in the shadows, keep warm highlights.
	alb = mix(alb * vec3(0.86, 0.84, 1.0), alb, smoothstep(0.2, 0.55, l));
	alb = mix(alb, alb * COLOR.rgb * 1.6, vcol_amount);
	float up = smoothstep(0.55, 0.9, wn.y);
	alb = mix(alb, alb * floor_tint, up);
	float damp = (1.0 - smoothstep(0.0, 1.1, lp.y - floor_y)) * (1.0 - up);
	alb = mix(alb, alb * damp_tint, damp * 0.6);
	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = mix(arm.g, 0.45, damp * 0.6);
	SPECULAR = 0.35;
}
