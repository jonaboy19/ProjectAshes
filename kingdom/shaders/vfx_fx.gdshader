// Mesh effects for the VFX library, one shader with a few modes:
//   0 SMEAR   ribbon (UV.x along, 0 = tail .. 1 = head; UV.y across, 1 = outer
//             edge): sword smears, water whips, wind blades, spiral ribbons.
//             Noise-distorted, a three-colour gradient and a dissolve with a
//             glowing burn edge (idea from VFEZ-godot and the MIT Fiery Slash
//             shader, rewritten).
//   1 COLUMN  open cylinder (UV.x around, UV.y down): fire pillar, whirlwind,
//             tidal wall, light beams. Noise scrolls upward and twists.
//   2 CRACK   ground quad: glowing fissures that spread out from the centre
//             (earthquake, Rift). Ridged noise, blue channel of vfx_noise.
//   3 ORB     camera-facing quad: swirling energy ball (fireball, qi palm).
//   4 RING    ground quad: soft expanding ring or splash crown.
//   5 BEAM    ribbon with a centred hot core (UV.y 0..1 across): lightning bolts.
//   6 TEAR    vertical quad: a jagged glowing slit in space (the Rift).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 edge : source_color = vec4(0.6, 0.1, 0.02, 1.0);
uniform float energy = 3.0;
uniform float progress = 1.0;   // SMEAR: head position; CRACK/RING: spread radius
uniform float dissolve = 0.0;   // 0 solid .. 1 gone, with a burn edge
uniform float fade = 1.0;
uniform float speed = 1.0;      // noise scroll speed
uniform float twist = 0.0;      // COLUMN: spiral twist; ORB: swirl
uniform float noise_amt = 0.35; // UV distortion strength
uniform float tail = 0.6;       // SMEAR: length of the fading tail (in UV.x)
uniform float width = 0.5;      // RING: ring thickness; CRACK: fissure width
uniform float seed = 0.0;
uniform bool billboard = false;


vec3 ramp(float v) {
	vec3 c = mix(edge.rgb, tint.rgb, smoothstep(0.0, 0.45, v));
	return mix(c, hot.rgb, smoothstep(0.6, 1.0, v));
}

float n1(vec2 uv) { return texture(noise_tex, uv).r; }

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi cell border (two-pass: nearest seed, then
// distance to the bisectors with its neighbours).
float vor_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}
float n2(vec2 uv) { return texture(noise_tex, uv).g; }

void vertex() {
	if (billboard || mode == 3) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		VERTEX *= length(MODEL_MATRIX[0].xyz);
	}
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float v = 0.0;      // heat for the ramp
	float a = 0.0;      // coverage
	float dn = 0.5;     // dissolve noise sample
	if (mode == 0) {
		vec2 d = vec2(n1(uv * vec2(1.5, 0.7) + vec2(-t * 0.9, seed)), n2(uv * vec2(3.0, 1.0) + vec2(-t * 1.6, seed * 2.0))) - 0.5;
		vec2 q = uv + d * noise_amt * vec2(0.25, 0.5);
		float behind = progress - q.x;
		float trail = smoothstep(tail, 0.0, behind) * smoothstep(-0.03, 0.02, behind);
		float across = clamp(q.y, 0.0, 1.0);
		// Sharp, bright outer edge; soft inner body.
		float body = pow(across, 1.6) * smoothstep(1.0, 0.9, across);
		float rim = exp(-pow((across - 0.9) / 0.05, 2.0));
		float streaks = 0.75 + 0.5 * n2(vec2(q.x * 0.6 - t * 0.5, q.y * 5.0 + seed));
		float head = exp(-pow(behind / 0.05, 2.0)) * across;
		a = (body * streaks + rim) * trail + head * 0.6;
		v = clamp((rim * 1.1 + body * 0.6) * (0.35 + 0.65 * trail) + head, 0.0, 1.0);
		dn = n1(uv * vec2(2.0, 0.8) + vec2(seed, -t * 0.3));
	} else if (mode == 1) {
		vec2 q = vec2(uv.x + uv.y * twist + t * 0.15 * sign(twist + 1e-4), uv.y);
		float s1 = n1(q * vec2(2.0, 1.2) + vec2(seed, t * 0.9));
		float s2 = n2(q * vec2(4.0, 2.5) + vec2(seed * 3.0, t * 1.7));
		float bottom = smoothstep(1.0, 0.8, uv.y);
		float top = smoothstep(0.0, 0.45, uv.y);
		float f = s1 * 0.65 + s2 * 0.55;
		// Flames lick upward: threshold rises toward the top.
		float shape = smoothstep(0.35 + (1.0 - uv.y) * 0.45, 0.95, f + uv.y * 0.35);
		v = clamp(shape * (0.4 + uv.y * 0.9), 0.0, 1.0);
		a = (shape * top * bottom + bottom * 0.15 * smoothstep(0.7, 1.0, uv.y)) * (0.35 + 0.65 * v);
		dn = s1;
	} else if (mode == 2) {
		vec2 p = (uv - 0.5) * 2.0;
		float r = length(p);
		// Voronoi cell edges, domain-warped: a web of sharp fissures.
		vec2 warp = vec2(n1(p * 0.3 + seed), n2(p * 0.3 - seed)) - 0.5;
		float e = vor_edge(p * 3.2 + warp * 0.9 + seed * 7.0);
		float w = (0.035 + 0.05 * width) * (1.2 - r * 0.7);
		float line = smoothstep(w, w * 0.25, e);
		float halo = exp(-e / (w * 2.5)) * 0.35;
		float reach = smoothstep(progress, progress - 0.3, r);
		float crack = (line + halo) * reach;
		float glow = exp(-pow(r / max(progress * 0.4, 0.01), 2.0)) * 0.35 * reach;
		float flick = 0.8 + 0.2 * n1(vec2(t * 0.5, seed));
		a = (crack + glow) * smoothstep(1.0, 0.8, r) * flick;
		v = clamp(line * (1.0 - r * 0.4) + glow * 0.5, 0.0, 1.0);
		dn = n1(p * 0.5 + seed);
	} else if (mode == 3) {
		vec2 p = (uv - 0.5) * 2.0;
		float r = length(p);
		float ang = atan(p.y, p.x) + r * twist * 3.0 - t * 2.0;
		vec2 sw = vec2(cos(ang), sin(ang)) * r;
		float s = n1(sw * 0.4 + vec2(seed, t * 0.3)) * 0.6 + n2(sw * 0.9 - vec2(t * 0.5)) * 0.6;
		float core = exp(-r * r * 9.0);
		float shell = smoothstep(1.0, 0.35, r + (s - 0.5) * noise_amt);
		a = shell * (0.35 + 0.65 * s) + core;
		v = clamp(core * 1.2 + shell * s * 0.7, 0.0, 1.0);
		dn = s;
	} else if (mode == 4) {
		vec2 p = (uv - 0.5) * 2.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float wob = (n1(vec2(cos(ang), sin(ang)) * 0.35 + vec2(seed, t * 0.3)) - 0.5) * noise_amt;
		float d = r + wob - progress;
		float ring = exp(-pow(d / max(width * 0.2, 0.005), 2.0));
		float inner = smoothstep(0.0, -width, d) * step(d, 0.0) * 0.25;
		float foam = n2(p * 1.5 + vec2(seed, -t)) ;
		a = (ring * (0.6 + 0.6 * foam) + inner * foam) * smoothstep(1.0, 0.92, r);
		v = clamp(ring * (0.5 + foam * 0.7), 0.0, 1.0);
		dn = foam;
	} else if (mode == 5) {
		float across = 1.0 - abs(uv.y - 0.5) * 2.0;
		float flick = n2(vec2(uv.x * 2.0 - t * 3.0, seed));
		float core = smoothstep(0.5, 0.95, across);
		a = pow(across, 1.4) * (0.5 + 0.7 * flick) + core;
		v = clamp(core + pow(across, 3.0) * 0.6, 0.0, 1.0);
		dn = n1(vec2(uv.x * 3.0, seed));
	} else {
		vec2 p = (uv - 0.5) * 2.0;
		float lens = clamp(1.0 - p.y * p.y, 0.0, 1.0);
		float jit = (n1(vec2(p.y * 0.9 + seed, t * 0.15)) - 0.5) * 0.7 * lens;
		float x = p.x + jit + (n2(vec2(p.y * 3.0, t * 0.6 + seed)) - 0.5) * 0.08;
		float w = lens * width * 0.3 + 0.004;
		float slit = smoothstep(w, w * 0.2, abs(x));
		float halo = exp(-abs(x) / (w * 1.5 + 0.02)) * lens * smoothstep(1.0, 0.5, abs(p.x));
		float sparks = smoothstep(0.8, 1.0, n2(vec2(x * 4.0, p.y * 2.0 - t))) * halo;
		a = slit + halo * 0.7 + sparks;
		v = clamp(slit * 1.1 + halo * 0.35 + sparks, 0.0, 1.0);
		dn = n1(p * 0.5 + seed);
	}
	// Dissolve with a hot burn edge.
	float cut = dn - dissolve * 1.15 + 0.1;
	float keep = smoothstep(0.0, 0.08, cut);
	float burn = smoothstep(0.18, 0.0, cut) * keep * step(0.001, dissolve);
	v = clamp(v + burn * 0.8, 0.0, 1.0);
	a *= keep;
	ALBEDO = ramp(v) * energy * (1.0 + burn);
	ALPHA = clamp(a * fade * tint.a * COLOR.a, 0.0, 1.0);
}
