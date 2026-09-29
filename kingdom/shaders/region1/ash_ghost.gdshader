shader_type spatial;
// Ashsight ghost (N4): a soft grey-ember figure. Warm and storybook, not horror: pale ash body,
// a gentle amber (or, per role, blue-white) rim, feet that crumble into wisps, drifting ember
// specks, and a dissolve that eats the figure away with a glowing edge. No textures.
// One alpha-blended pass, unshaded, no lights: cheap on mobile.
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 ash_color : source_color = vec4(0.82, 0.79, 0.75, 1.0);
uniform vec4 core_color : source_color = vec4(0.60, 0.58, 0.58, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.64, 0.30, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float model_height = 1.8;
uniform float rim_power = 2.0;
uniform float rim_strength = 1.0;
uniform float base_opacity = 0.50;
uniform float feather : hint_range(0.05, 0.9) = 0.42;
uniform float drift_speed = 0.55;
uniform float noise_scale = 3.4;
uniform float seed = 0.0;

varying vec3 v_local;
varying vec3 v_world;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	v_local = VERTEX;
	float h = clamp(VERTEX.y / model_height, 0.0, 1.0);
	// a slow ripple, strongest near the feet, like heat haze over embers
	float sway = sin(TIME * 1.7 + VERTEX.y * 3.0 + seed * 6.28) * 0.03 * (1.0 - h * 0.6);
	VERTEX.x += sway;
	VERTEX.z += sway * 0.7;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp(v_local.y / model_height, 0.0, 1.0);
	vec3 q = v_world * noise_scale + vec3(seed * 13.0, -TIME * drift_speed, seed * 7.0);
	float n = vnoise(q);
	float n2 = vnoise(q * 2.3 + 7.1);

	// ragged, crumbling feet
	float foot = smoothstep(0.0, feather, h + (n - 0.5) * 0.34);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

	// dissolve: noise plus a slight top-first bias, eaten away with a glowing edge
	float field = n * 0.65 + (1.0 - h) * 0.35;
	float cut = dissolve * 1.18 - 0.08;
	float keep = smoothstep(cut, cut + 0.05, field);
	float edge = (1.0 - smoothstep(0.0, 0.11, field - cut)) * step(0.001, dissolve);

	vec3 col = mix(core_color.rgb, ash_color.rgb, clamp(fres * 0.7 + h * 0.35 + 0.2, 0.0, 1.0));
	col += ember_color.rgb * (fres * rim_strength * 0.6 + (1.0 - h) * 0.12);
	col = mix(col, ember_color.rgb * 1.2, edge * keep);

	// drifting ember specks
	float spark = smoothstep(0.84, 0.93, n2) * (0.55 + 0.45 * sin(TIME * 4.0 + n * 20.0));
	col += ember_color.rgb * spark * 0.9;

	ALBEDO = col;
	ALPHA = clamp(alpha * keep * foot * (base_opacity + fres * 0.55 + spark * 0.4 + edge * 0.35), 0.0, 1.0);
}
