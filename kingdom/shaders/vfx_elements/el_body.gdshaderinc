// Shared body for the elemental VFX shaders (el_add / el_mix / el_solid).
// One shader drives every big shape: columns, cones, shells, orbs, ground rings, ribbons.
// Colour comes from three stops (core / mid / edge) driven by a "heat" value built from
// scrolling 3D noise (object space, so no UV seams), fresnel, and a dissolve threshold.
// `cel` snaps the heat into bands for the hand-painted storybook look.
// Object-space conventions: column mode assumes a mesh centred on the origin with height
// `mesh_h`; ground mode a flat mesh in XZ with radius `mesh_r`; ribbon mode uses UV
// (x = along, 0 tail .. 1 head; y = across).

uniform int shape_mode = 0;             // 0 column, 1 ground ring/disc, 2 orb/shell, 3 ribbon (uv)
uniform vec4 col_core : source_color = vec4(1.0, 0.93, 0.62, 1.0);
uniform vec4 col_mid : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 col_edge : source_color = vec4(0.7, 0.12, 0.04, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float master : hint_range(0.0, 1.0) = 1.0;      // fade in/out of the whole effect
uniform float progress : hint_range(0.0, 1.0) = 0.0;    // 0 = fresh, 1 = dissolved
uniform float dissolve_amt = 1.0;
uniform float alpha_mul = 1.0;
uniform float noise_amt : hint_range(0.0, 1.0) = 0.7;
uniform vec3 noise_scale = vec3(3.0, 3.0, 3.0);
uniform vec3 scroll = vec3(0.0, -1.5, 0.0);
uniform float cel : hint_range(0.0, 1.0) = 0.75;
uniform float bands = 3.0;
uniform float fresnel_pow = 2.0;
uniform float rim_alpha = 0.0;          // brighter/more opaque at the silhouette (shells)
uniform float core_facing = 0.0;        // hotter where the surface faces the camera (orbs)
uniform float mesh_h = 1.0;
uniform float mesh_r = 1.0;
uniform vec2 fade_y = vec2(0.15, 0.3);  // column: fade in over the first / out over the last fraction
uniform float ring_r = 0.7;             // ground: ring radius (fraction of mesh_r)
uniform float ring_w = 0.15;            // ground: ring thickness
uniform float ring_fill = 0.0;          // ground: 0..1 filled disc inside the ring
uniform float ticks = 0.0;              // ground: angular dash count (rune-like ring), 0 = off
uniform float tick_amt = 0.0;
uniform vec3 spiral = vec3(0.0, 0.0, 0.0);   // arms, pitch per height, speed
uniform float spiral_amt = 0.0;
uniform float wobble = 0.0;             // vertex push along the normal
uniform float wobble_scale = 2.0;
uniform float twist = 0.0;              // radians of twist over the height
uniform float spin = 0.0;               // rad/s the noise rotates around Y
uniform float flicker = 0.0;            // 0..1 hard on/off electric flicker
uniform float fake_light = 0.0;         // cel light from a fixed sun (solid shapes)
uniform float flat_shade = 0.0;         // faceted normals (crystals, spikes)
uniform vec3 light_dir = vec3(0.4, 0.8, 0.35);
uniform float reveal = 1.0;             // ribbon: head position 0..1 (sweep in)
uniform float tail_len = 0.6;           // ribbon: length of the fading tail
uniform float pulse = 0.0;              // brightness pulse amount
uniform float pulse_speed = 6.0;
uniform float heat_scale = 0.8;         // scales heat before the colour ramp (lower = more body colour, less white core)

varying vec3 lp;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x),
				   mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x),
				   mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm2(vec3 p) {
	return vnoise(p) * 0.62 + vnoise(p * 2.13 + vec3(5.2, 1.3, 8.1)) * 0.38;
}

vec2 rot2(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	lp = VERTEX;
	float y01 = VERTEX.y / mesh_h + 0.5;
	if (twist != 0.0) {
		VERTEX.xz = rot2(VERTEX.xz, twist * y01);
	}
	if (wobble > 0.0) {
		float n = vnoise(lp * wobble_scale + scroll * TIME * 0.7);
		VERTEX += NORMAL * (n - 0.5) * wobble;
	}
}

void fragment() {
	vec3 q = lp;
	q.xz = rot2(q.xz, spin * TIME);
	float y01 = clamp(lp.y / mesh_h + 0.5, 0.0, 1.0);
	float rr = length(lp.xz) / mesh_r;
	float ang = atan(q.z, q.x);
	float shape = 1.0;
	if (shape_mode == 0) {
		shape = smoothstep(0.0, max(fade_y.x, 0.001), y01) * (1.0 - smoothstep(1.0 - fade_y.y, 1.0, y01));
	} else if (shape_mode == 1) {
		float d = abs(rr - ring_r);
		float ring = 1.0 - smoothstep(ring_w * 0.35, ring_w * 0.5, d);
		float fill = ring_fill * (1.0 - smoothstep(ring_r - 0.05, ring_r + ring_w * 0.4, rr));
		shape = max(ring, fill);
		float tk = step(0.45, fract(ang / 6.2831853 * max(ticks, 1.0)));
		shape *= mix(1.0, tk, tick_amt * step(0.5, ticks));
		shape *= 1.0 - smoothstep(0.92, 1.0, rr);
	} else if (shape_mode == 3) {
		float across = 1.0 - abs(UV.y * 2.0 - 1.0);
		shape = smoothstep(0.0, 0.45, across);
		float behind = clamp((UV.x - (reveal - tail_len)) / max(tail_len, 0.001), 0.0, 1.0);
		shape *= behind * step(UV.x, reveal + 0.0001);
		shape *= 1.0 - smoothstep(0.92, 1.0, UV.x) * 0.5;
	}
	vec3 np = q * noise_scale + scroll * TIME;
	if (flicker > 0.0) {
		np += vec3(floor(TIME * 22.0) * 1.7, floor(TIME * 22.0) * 0.9, 0.0);
	}
	float n = fbm2(np);
	float density = shape * mix(1.0, n * 1.75, noise_amt);
	if (spiral_amt > 0.0) {
		float sp = 0.5 + 0.5 * sin(ang * spiral.x + y01 * spiral.y - TIME * spiral.z);
		density *= mix(1.0, sp * 1.35, spiral_amt);
	}
	vec3 N = normalize(NORMAL);
	if (flat_shade > 0.0) {
		N = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	}
	float ndv = clamp(abs(dot(N, normalize(VIEW))), 0.0, 1.0);
	float facing = pow(ndv, fresnel_pow);
	density += (1.0 - facing) * rim_alpha * shape;
	float heat = (density + core_facing * facing * shape) * heat_scale;
	float thr = progress * dissolve_amt;
	float a = smoothstep(thr, thr + 0.1, density);
	heat = clamp(heat - thr * 0.6, 0.0, 1.4);
	float hq = floor(clamp(heat, 0.0, 0.999) * bands) / max(bands - 1.0, 1.0);
	heat = mix(heat, min(hq, 1.2), cel);
	if (flicker > 0.0) {
		float fl = step(flicker * 0.6, h31(vec3(floor(TIME * 26.0), 3.1, 7.7)));
		a *= mix(1.0, fl, flicker);
	}
	vec3 col = mix(col_edge.rgb, col_mid.rgb, smoothstep(0.15, 0.55, heat));
	col = mix(col, col_core.rgb, smoothstep(0.62, 1.0, heat));
	if (fake_light > 0.0) {
		vec3 fn = (INV_VIEW_MATRIX * vec4(N, 0.0)).xyz;
		float l = dot(normalize(fn), normalize(light_dir)) * 0.5 + 0.5;
		float lq = mix(l, floor(l * 3.0 + 0.5) / 3.0, cel);
		col *= mix(1.0, 0.45 + 0.85 * lq, fake_light);
	}
	float pl = 1.0 + pulse * sin(TIME * pulse_speed);
	ALBEDO = col * intensity * pl;
#ifdef SOLID_MODE
	ALPHA = a * master > 0.5 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#else
	ALPHA = clamp(a * alpha_mul * master, 0.0, 1.0);
#endif
}
