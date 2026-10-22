// Procedural face deviations over a painted face (docs/art/FACES.md). The card draws NOTHING at neutral with a closed mouth:
// only soft brow shading wedges, an eyelid cap in the skin tone (blink / squint), an open-mouth cavity and two corner marks.
// p = metres from the quad centre (x right, y up). Colours are linear (ALBEDO): ink = timber 4a3220, cavity = 3a1a16.
const vec3 INK = vec3(0.069, 0.032, 0.014);
const vec3 CAVITY = vec3(0.042, 0.010, 0.008);

float seg_d(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

vec4 over(vec4 d, vec3 c, float a) {
	float oa = a + d.a * (1.0 - a);
	return vec4((c * a + d.rgb * d.a * (1.0 - a)) / max(oa, 0.0001), oa);
}

// returns rgb + alpha (straight)
vec4 face_ink(vec2 uv, vec2 size, float brow, float lids, float mouth_open, float mouth_curve, float brows_on, float lids_on, vec4 lay, vec3 skin) {
	// lay = (mouth_y, mouth_half_width, eye_x, brow_y) metres from the centre
	vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y) * size;
	vec2 q = vec2(abs(p.x), p.y);                       // mirrored features
	vec4 o = vec4(0.0);
	// eyelid cap: skin coloured, closing from the top, soft edge (blink = 1)
	float lid = clamp(lids, 0.0, 1.0);
	vec2 e = (q - vec2(lay.z, lay.w - 0.016)) / vec2(0.0125, 0.0095);
	float inside = 1.0 - smoothstep(0.8, 1.0, length(e));
	float edge_y = 0.0095 * (1.0 - 2.0 * lid);
	float covered = smoothstep(edge_y - 0.0012, edge_y + 0.0012, q.y - (lay.w - 0.016));
	float lid_a = lids_on * smoothstep(0.55, 0.9, lid) * inside * covered * 0.92;
	o = over(o, skin, lid_a);
	float ledge = lids_on * smoothstep(0.55, 0.9, lid) * inside * (1.0 - smoothstep(0.0006, 0.0022, abs(q.y - (lay.w - 0.016 + edge_y))));
	o = over(o, INK, ledge * 0.3);
	// brow shading wedge above each eye, tilting with `brow` (negative: inner end down and darker; positive: raised, lighter)
	float by = lay.w + brow * 0.004;
	vec2 b_in = vec2(lay.z - 0.016, by + min(brow, 0.0) * 0.010 + max(brow, 0.0) * 0.001);
	vec2 b_out = vec2(lay.z + 0.016, by + max(brow, 0.0) * 0.006 + max(-brow, 0.0) * 0.003);
	float bt;
	float bd = seg_d(q, b_in, b_out, bt);
	float thick = mix(0.0030, 0.0014, bt);
	float s = smoothstep(0.08, 0.3, abs(brow));
	float ba = mix(0.25, 0.45, step(brow, 0.0)) * s * (1.0 - smoothstep(thick - 0.0012, thick + 0.0014, bd));
	o = over(o, INK, brows_on * ba);
	// open mouth: warm dark cavity, soft edge, never wider than the lips
	float mo = smoothstep(0.15, 0.3, mouth_open);
	float oy = 0.002 + 0.010 * mouth_open;
	vec2 m = vec2(p.x / (lay.y * 0.8), (p.y - (lay.x - oy * 0.4)) / oy);
	float cav = (1.0 - smoothstep(0.7, 1.0, length(m))) * mo;
	o = over(o, CAVITY, cav * 0.9);
	// closed mouth: two small corner marks only (up = smile, down = frown), ~1/5 of the mouth width each
	float cm = smoothstep(0.2, 0.45, abs(mouth_curve)) * (1.0 - mo);
	float dir = sign(mouth_curve);
	vec2 c0 = vec2(lay.y, lay.x + dir * 0.0035);
	vec2 c1 = vec2(lay.y - 0.4 * lay.y, lay.x - dir * 0.0008);
	float ct;
	float cd = seg_d(q, c0, c1, ct);
	o = over(o, INK, cm * 0.6 * (1.0 - smoothstep(0.0012, 0.0027, cd)));
	return o;
}
