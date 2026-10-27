// Benchmark slice (AAA gate: no flat colours): the modular interior kit's "solid" surface. The kit bakes every box of a room into
// one vertex-coloured mesh; this keeps that colour and multiplies in CC0 real-scan detail (Poly Haven, assets/cc0/textures),
// world-triplanar, chosen per pixel from the vertex colour: light colours = plaster, dark saturated browns = wood, greys = stone.
// One draw call, no UVs needed. Luminance-only detail, so the kit's palette stays the designer's.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D plaster_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D beam_tex : source_color, filter_linear_mipmap, repeat_enable;   // dark frame timbers (beam_wall_01)
uniform float beam_mean = 0.241;
uniform sampler2D mottle_tex : source_color, filter_linear_mipmap, repeat_enable;   // big soft blotches in the limewash (worn_mossy_plasterwall, low freq)
uniform vec3 hearth_pos = vec3(0.0, -1000.0, 0.0);   // world position of the fire: soot on walls and joists above it
uniform float floor_y = 0.0;                        // world floor height of the room: grime climbs the wall foot
uniform float plaster_scale = 0.45;   // repeats per metre
uniform float wood_scale = 0.7;
uniform float stone_scale = 0.5;
uniform float amount = 0.85;
uniform float plaster_mean = 0.456;   // linear mean luminance of the scans (measured): plastered_wall_02 (limewash), old_wood_floor, rustic_stone_wall
uniform float wood_mean = 0.07;
uniform float stone_mean = 0.145;

varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_lum(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 a = texture(t, p.zy * s).rgb * w.x + texture(t, p.xz * s).rgb * w.y + texture(t, p.xy * s).rgb * w.z;
	return dot(a, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec3 c = COLOR.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float mx = max(c.r, max(c.g, c.b));
	float sat = mx > 0.0 ? (mx - min(c.r, min(c.g, c.b))) / mx : 0.0;
	// walls are the large warm-light surfaces: plaster; only clearly dark browns are wood, only near-neutral greys are stone
	float wood_all = smoothstep(0.36, 0.26, l) * smoothstep(0.1, 0.25, sat);   // floors (l 0.28) and furniture are wood
	float beam = wood_all * smoothstep(0.24, 0.2, l);                         // the darkest browns: frame timbers, joists
	float wood = wood_all - beam;
	float stone = (1.0 - wood_all) * smoothstep(0.09, 0.04, sat) * smoothstep(0.12, 0.25, l);
	float plaster = clamp(1.0 - wood_all - stone, 0.0, 1.0);
	float d = 0.0;
	// limewash: soft relief only (a full-contrast scan read as rubble stone); wood and stone keep their grain
	if (plaster > 0.01) { d += plaster * mix(1.0, tri_lum(plaster_tex, wpos, wnor, plaster_scale) / plaster_mean, 1.0) * mix(1.0, tri_lum(mottle_tex, wpos, wnor, 0.16) / 0.222, 0.32); }
	if (wood > 0.01) { d += wood * tri_lum(wood_tex, wpos, wnor, wood_scale) / wood_mean; }
	if (stone > 0.01) { d += stone * tri_lum(stone_tex, wpos, wnor, stone_scale) / stone_mean; }
	if (beam > 0.01) { d += beam * tri_lum(beam_tex, wpos, wnor, 0.9) / beam_mean; }
	vec3 col = c * mix(1.0, clamp(d, 0.3, 1.8), amount);
	// soot: walls and timbers above and around the hearth go smoke-black, strongest high up (smoke rises)
	vec3 hv = wpos - hearth_pos;
	float soot = (1.0 - smoothstep(0.6, 3.6, length(hv.xz))) * smoothstep(-0.4, 1.6, hv.y);
	soot = max(soot, smoothstep(1.2, 0.0, length(hv.xz)) * 0.6);
	// grime: the plaster's foot (splashes, knocks) and a general darkening under the ceiling from years of smoke
	float foot = (1.0 - smoothstep(0.0, 0.7, wpos.y - floor_y)) * plaster;
	float ceil_smoke = smoothstep(1.8, 3.2, wpos.y - floor_y) * 0.25 * (plaster + beam);
	col *= 1.0 - clamp(soot * 0.85 + foot * 0.3 + ceil_smoke, 0.0, 0.88);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, wood);
	SPECULAR = 0.25;
}
