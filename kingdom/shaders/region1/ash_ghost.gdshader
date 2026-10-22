shader_type spatial;
// Ashsight ghost (N4): a warm ember-grey translucent silhouette on a real humanoid mesh.
//  - fresnel rim in the role's ember colour (readable at phone size),
//  - glowing ember cracks (ridged noise, pulsing, HDR so bloom picks them up),
//  - ash flaking off the edges (noise holes that grow with the fresnel term) and a full
//    dissolve (`dissolve` 0..1) that eats the figure from the head down with a glowing rim,
//  - a soft fake key light so limbs and armour keep their form.
// Warm storybook tone, not horror. No textures, no lights. One alpha pass (plus the optional
// depth pre-pass in ash_ghost_depth.gdshader).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/region1/ash_ghost_common.gdshaderinc"

uniform vec4 ash_color : source_color = vec4(0.93, 0.82, 0.68, 1.0);
uniform vec4 core_color : source_color = vec4(0.34, 0.27, 0.25, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.55, 0.20, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float model_height = 1.8;
uniform float rim_power = 3.0;
uniform float rim_strength = 1.9;
uniform float base_opacity = 0.74;
uniform float feather : hint_range(0.05, 0.9) = 0.40;
uniform float drift_speed = 0.55;
uniform float noise_scale = 5.2;
uniform float crack_amount : hint_range(0.0, 2.0) = 1.0;
uniform float crack_scale = 4.5;
uniform float flake_amount : hint_range(0.0, 1.5) = 1.0;
uniform float cheap : hint_range(0.0, 1.0) = 0.0;   // 1 = LOW tier: one noise lookup fewer
uniform float seed = 0.0;

varying vec3 v_rel;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((w.y - NODE_POSITION_WORLD.y) / model_height, 0.0, 1.0);
	VERTEX += ghost_sway(VERTEX, h, seed, TIME);
	v_rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
}

void fragment() {
	float h = clamp(v_rel.y / model_height, 0.0, 1.0);
	vec3 nrm = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(nrm, normalize(VIEW)), 0.0, 1.0), rim_power);

	// erosion noise drifts upward (ash carried by warm air)
	vec3 q = v_rel * noise_scale + vec3(seed * 13.0, -TIME * drift_speed, seed * 7.0);
	float n = vnoise(q);
	float n2 = cheap > 0.5 ? n : vnoise(q * 2.3 + 7.1);

	float foot = smoothstep(0.0, feather, h + (n - 0.5) * 0.34);
	// edge flaking: silhouette pixels where the fine noise is high are torn away
	float flake = flake_amount * fres * smoothstep(0.42, 0.95, n2) * 0.9;
	float field = ghost_field(n, h) - flake * 0.5;
	float cut = dissolve * 1.18 - 0.08;
	float keep = smoothstep(cut, cut + 0.05, field);
	float edge = (1.0 - smoothstep(0.0, 0.10, field - cut)) * step(0.001, dissolve);
	// a thin ember rim on the flaked edges too
	float flake_rim = (1.0 - smoothstep(0.0, 0.07, field - 0.02)) * flake_amount * 0.7;

	// body colour with a soft fake key light (view space, from above-left)
	float lit = clamp(dot(nrm, normalize(vec3(-0.35, 0.75, 0.55))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(core_color.rgb, ash_color.rgb, clamp(smoothstep(0.25, 0.85, lit) * 0.85 + h * 0.1, 0.0, 1.0));
	col += ember_color.rgb * (fres * rim_strength * 0.5 + (1.0 - h) * (1.0 - h) * 0.12);

	// glowing ember cracks: contour lines of two noise octaves, pulsing slowly
	vec3 cp = v_rel * crack_scale + vec3(seed * 5.0, 0.0, seed * 3.0);
	float c1 = abs(vnoise(cp) - 0.5);
	float crack = smoothstep(0.038, 0.0, c1);
	if (cheap < 0.5) {
		crack = max(crack, 0.7 * smoothstep(0.028, 0.0, abs(vnoise(cp * 2.1 + 3.3) - 0.5)));
	}
	float pulse = 0.62 + 0.38 * sin(TIME * 1.8 + v_rel.y * 3.0 + seed * 6.28);
	crack *= crack_amount * pulse * (0.55 + 0.45 * (1.0 - h * 0.5));
	col = mix(col, ember_color.rgb * 2.3, clamp(crack, 0.0, 1.0));
	col = mix(col, ember_color.rgb * 1.7, clamp(edge * keep + flake_rim * keep * 0.6, 0.0, 1.0));

	ALBEDO = col;
	ALPHA = clamp(alpha * keep * foot * (base_opacity + fres * 0.5 + crack * 0.35 + edge * 0.4), 0.0, 1.0);
}
