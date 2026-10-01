// Style Lab E
// "Low-end safe polished": lab_polished without rim and hemispheric bounce emission, lit per vertex
// (vertex_lighting), so the fragment shader is one texture tap and ~10 ALU. Works on Compatibility.
// Keeps the saturation grade, warm tint and the height-based contact-AO ramp (all baked into albedo).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx, vertex_lighting;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cut = 0.0;
uniform float saturation = 1.22;
uniform float value_gain = 1.04;
uniform vec3 warm_tint : source_color = vec3(1.04, 1.0, 0.94);
uniform vec3 sky_bounce : source_color = vec3(0.50, 0.62, 0.95);
uniform vec3 ground_bounce : source_color = vec3(0.95, 0.72, 0.42);
uniform float bounce = 0.22;
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float rim_amount = 0.35;
uniform float ao_height = 0.9;
uniform float ao_strength = 0.30;
uniform float roughness = 0.72;
uniform float spec = 0.35;
// Style G weathering (2026-10-01): world-projected Poly Haven detail pack (R plaster, G wood grain, B grime noise,
// A stone) picked per pixel from the atlas colour class; relief tints the albedo, bumps the normal (HIGH/MEDIUM),
// adds roughness variation, grime climbing from the wall foot, rain streaks and lighter worn edges along atlas seams.
uniform sampler2D weather_tex : filter_linear_mipmap, repeat_enable;
uniform float weather = 0.0;
uniform float weather_scale = 0.32;
uniform float grime_height = 2.2;
uniform float grime_amount = 0.38;
uniform float edge_wear = 0.35;
uniform float vao_strength = 0.0;   // baked vertex AO in COLOR.a (StyleG.bake_vertex_ao)
uniform float bump_amount = 0.6;
varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


vec4 weather_sample(vec3 p, vec3 n, float s) {
	vec3 a = abs(n);
	vec2 uv = a.y > 0.7 ? p.xz : (a.x > a.z ? p.zy : p.xy);
	return texture(weather_tex, uv * s, 0.8);   // +0.8 mip bias: no shimmer/sparkle at distance
}

// returns weathered albedo; h = signed relief height for bump
vec3 weather_albedo(vec3 c, vec3 p, vec3 n, float lum_in, float foot_y, out float h, out float rough_add) {
	vec4 w = weather_sample(p, n, weather_scale);
	float streak = texture(weather_tex, vec2(p.x + p.z, p.y * 0.12) * 0.35).b;
	float wood = smoothstep(0.42, 0.22, lum_in) * step(c.b * 1.1, c.r);
	float plaster = smoothstep(0.5, 0.72, lum_in);
	float stone = clamp(1.0 - wood - plaster, 0.0, 1.0);
	h = (w.r - 0.5) * plaster + (w.g - 0.5) * wood * 1.4 + (w.a - 0.5) * stone;
	c *= 1.0 + h * 0.4 * weather;
	// grime from the foot, broken by noise; rain streaks on walls
	float g = clamp(1.0 - (p.y - foot_y) / grime_height + (w.b - 0.5) * 0.9, 0.0, 1.0);
	float vert = 1.0 - abs(n.y);
	g = max(g * g, smoothstep(0.62, 0.85, streak) * 0.45 * vert * plaster);
	c = mix(c, c * vec3(0.66, 0.6, 0.52), g * grime_amount * weather);
	// stains: large blotches darken slightly everywhere (lived-in, not flat)
	c *= 1.0 - (smoothstep(0.55, 0.85, w.b) * 0.12) * weather;
	rough_add = (0.5 - w.b) * 0.15 + g * 0.1;
	return c;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV * uv_scale + uv_offset);
	vec3 c = t.rgb * albedo_color.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * value_gain * warm_tint;
	float ao = 1.0 - ao_strength * (1.0 - smoothstep(0.0, ao_height, wpos.y));
	float wh = 0.0;
	float wr = 0.0;
	if (weather > 0.0) {
		// edge wear: atlas seams (timber/plaster borders, block joints) get a lighter chipped rim, masked by noise
		float seam = clamp(fwidth(l) * 6.0, 0.0, 1.0);
		c = weather_albedo(c, wpos, wnor, l, NODE_POSITION_WORLD.y, wh, wr);
		c = mix(c, c * 1.22 + vec3(0.025, 0.02, 0.01), seam * edge_wear * weather * step(0.45, wh + 0.5));
	}
	c *= ao * mix(1.0, COLOR.a, vao_strength);
	ALBEDO = c;
	ROUGHNESS = clamp(mix(roughness, 0.9, weather * 0.7) + wr * weather, 0.0, 1.0);
	SPECULAR = spec;
	// cheap hemispheric fill baked into albedo-ish emission (no fresnel, no pow)
	EMISSION = c * mix(ground_bounce, sky_bounce, wnor.y * 0.5 + 0.5) * bounce;
	if (alpha_cut > 0.0) {
		ALPHA = t.a * albedo_color.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
}
