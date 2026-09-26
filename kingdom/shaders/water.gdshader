shader_type spatial;
// Stylised-realistic lake / river water for Rising Ashes (Forward+ and Mobile).
//
// - Depth-based colour: Beer-Lambert absorption of the refracted lake bed
//   (red dies first -> teal shallows -> deep blue), plus a lit scattering term.
// - Flow-mapped normals: two scrolling noise normal maps, advected along the
//   per-vertex current (COLOR.rg) with the two-phase flow-map technique.
// - Fresnel + sun specular come from Godot's PBR lighting (low roughness,
//   sky radiance reflections); transmission is weighted by (1 - fresnel).
// - Soft shore foam from the depth texture, broken up by noise, plus foam
//   streaks where rivers run fast.
// - Gentle vertex waves, damped in the shallows.
// - Cheap screen-space refraction (one extra depth tap to reject foreground).
//
// Written from scratch for this project. Techniques follow public references
// (concepts only, no code copied):
//   Flow maps: A. Vlachos, "Water Flow in Portal 2", SIGGRAPH 2010.
//   Depth-buffer shore foam / absorption: widely documented, e.g. the Godot
//   docs "Advanced post-processing" (depth reconstruction, CC BY 3.0 docs).
// Noise textures are generated at runtime (FastNoiseLite), no external assets.

render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.10, 0.36, 0.33);
uniform vec3 deep_color : source_color = vec3(0.012, 0.06, 0.10);
uniform vec3 absorption = vec3(0.55, 0.17, 0.12);   // per metre, R/G/B
uniform float scatter_depth = 3.5;                   // metres to reach deep colour
uniform float scale_a = 0.055;                       // normal map tiles per metre
uniform float scale_b = 0.16;
uniform float normal_strength = 0.35;
uniform float flow_cycle = 0.45;                     // flow-map phase speed
uniform float roughness = 0.035;
uniform float refraction = 0.035;
uniform bool use_refraction = true;
uniform vec3 foam_color : source_color = vec3(0.82, 0.86, 0.86);
uniform float foam_width = 0.4;                      // metres of depth covered by shore foam
uniform float wave_height = 0.07;

varying vec3 world_pos;
varying vec2 flow;
varying float static_depth;
varying vec3 wave_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = (COLOR.rg * 2.0 - 1.0) * COLOR.b * 2.0;   // m/s, encoded by WaterStreamer
	static_depth = UV.x;
	// Two slow swells, damped where the water is shallow or flowing.
	float amp = wave_height * smoothstep(0.0, 2.0, max(static_depth, 0.0)) * (1.0 - clamp(length(flow), 0.0, 0.8));
	vec2 d1 = normalize(vec2(1.0, 0.55));
	vec2 d2 = normalize(vec2(-0.6, 1.0));
	float k1 = 0.32, k2 = 0.57;
	float p1 = dot(d1, world_pos.xz) * k1 + TIME * 1.1;
	float p2 = dot(d2, world_pos.xz) * k2 + TIME * 1.7;
	VERTEX.y += amp * (sin(p1) + 0.55 * sin(p2));
	vec2 grad = amp * (cos(p1) * k1 * d1 + 0.55 * cos(p2) * k2 * d2);
	wave_normal = normalize(vec3(-grad.x, 1.0, -grad.y));
	world_pos.y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

vec2 sample_normals(vec2 p, vec2 drift) {
	vec2 a = texture(normal_a, p * scale_a + drift * 0.012 + TIME * vec2(0.011, 0.004)).rg * 2.0 - 1.0;
	vec2 b = texture(normal_b, p * scale_b + drift * 0.03 + TIME * vec2(-0.007, 0.016)).rg * 2.0 - 1.0;
	return a + b * 0.7;
}

vec3 world_from_depth(vec2 uv, float d, mat4 inv_proj, mat4 inv_view) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	v.xyz /= v.w;
	return (inv_view * vec4(v.xyz, 1.0)).xyz;
}

void fragment() {
	// --- Normals: two-phase flow map so rivers visibly run downstream.
	float ph0 = fract(TIME * flow_cycle);
	float ph1 = fract(TIME * flow_cycle + 0.5);
	float w0 = 1.0 - abs(1.0 - 2.0 * ph0);
	vec2 f = flow * 1.6;
	vec2 n0 = sample_normals(world_pos.xz - f * ph0 / flow_cycle * 0.5, vec2(0.0));
	vec2 n1 = sample_normals(world_pos.xz - f * ph1 / flow_cycle * 0.5 + vec2(7.3, 3.1), vec2(0.0));
	vec2 nxy = mix(n1, n0, w0) * normal_strength * (1.0 + length(flow) * 0.5);
	vec3 wn = normalize(wave_normal + vec3(nxy.x, 0.0, nxy.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// --- Depth below the surface (vertical) and along the view ray.
	vec3 surface = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - surface);
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec3 bottom = world_from_depth(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float depth_v = max(surface.y - bottom.y, 0.0);
	// No usable depth buffer (MSAA on some drivers, some mobile GPUs): fall back
	// to the per-vertex terrain depth baked by WaterStreamer.
	bool depth_ok = raw_depth > 0.0;
	if (!depth_ok) {
		depth_v = max(static_depth, 0.0);
		bottom = surface - view_w * depth_v / max(dot(view_w, vec3(0.0, 1.0, 0.0)), 0.15);
	}

	vec2 ruv = SCREEN_UV;
	if (use_refraction && depth_ok) {
		vec2 try_uv = SCREEN_UV + nxy * refraction * clamp(depth_v, 0.0, 1.5);
		vec3 b2 = world_from_depth(try_uv, texture(depth_tex, try_uv).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		if (b2.y < surface.y) {   // only refract things that are actually under water
			ruv = try_uv;
			bottom = b2;
			depth_v = max(surface.y - bottom.y, 0.0);
		}
	}
	float path = distance(surface, bottom);
	vec3 transmit = exp(-absorption * path);
	float murk = 1.0 - exp(-depth_v / scatter_depth);
	vec3 body = mix(shallow_color, deep_color, murk);

	// --- Fresnel (Schlick, water F0 ~ 0.02).
	vec3 V = VIEW;
	float ndv = clamp(dot(NORMAL, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// --- Shore foam and river streaks.
	float fn = texture(foam_noise, world_pos.xz * 0.14 - flow * TIME * 0.12 + vec2(TIME * 0.013, TIME * 0.009)).r;
	float fn2 = texture(foam_noise, world_pos.xz * 0.43 + vec2(-TIME * 0.02, TIME * 0.017)).r;
	float shore = 1.0 - smoothstep(0.0, foam_width, depth_v);
	float band = 0.5 + 0.5 * sin(depth_v * 11.0 - TIME * 1.8 + fn * 5.0);
	float foam = smoothstep(0.55, 0.9, shore * (fn * 0.9 + fn2 * 0.6) + shore * shore * 0.25);
	foam = max(foam, smoothstep(0.7, 0.95, shore * band * (0.6 + fn2)) * 0.45);
	foam = max(foam, smoothstep(0.72, 0.95, fn2 * fn * 2.0) * clamp(length(flow) - 0.8, 0.0, 1.0) * 0.7);

	vec3 behind = use_refraction ? textureLod(screen_tex, ruv, 0.0).rgb : vec3(0.0);
	float t_avg = dot(transmit, vec3(0.3333));
	ALBEDO = mix(body * (1.0 - t_avg), foam_color, foam);
	EMISSION = behind * transmit * (1.0 - fres) * (1.0 - foam);
	ROUGHNESS = mix(roughness, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// Soft contact line; without refraction the water itself is see-through.
	float edge = smoothstep(0.0, 0.12, depth_ok ? depth_v : static_depth);
	ALPHA = use_refraction ? edge : edge * clamp(1.0 - t_avg + fres + foam, 0.0, 1.0);
}
