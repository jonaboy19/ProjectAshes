// Procedural ink face (docs/art/FACES.md): brows, upper lids and a mouth on a small quad over a painted face.
// p = metres from the quad centre (x right, y up). Palette: ink = timber 4a3220 (never black), lid fill = warm skin.
const vec3 INK = vec3(0.069, 0.032, 0.014);      // timber 4a3220, in linear (ALBEDO is linear)
const vec3 LID_SKIN = vec3(0.60, 0.30, 0.22);
const vec3 CAVITY = vec3(0.045, 0.012, 0.008);

float seg_d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// returns rgb + coverage (a)
vec4 face_ink(vec2 uv, vec2 size, float brow, float lids, float mouth_open, float mouth_curve, float brows_on, float lids_on, vec4 lay) {   // lay = (mouth_y, mouth_half_width, eye_x, brow_y) metres from the centre
	vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y) * size;
	vec2 q = vec2(abs(p.x), p.y);                       // mirrored features
	float cov = 0.0;
	vec3 col = INK;
	// brows: stroke from the inner end (x 0.014) to the outer end (x 0.046); brow>0 raises the outer end, brow<0 drops the inner end
	float by = lay.w + brow * 0.006;
	vec2 b_in = vec2(lay.z - 0.018, by + min(brow, 0.0) * 0.012 + max(brow, 0.0) * 0.003);
	vec2 b_out = vec2(lay.z + 0.016, by + max(brow, 0.0) * 0.006 + max(-brow, 0.0) * 0.004);
	float bd = seg_d(q, b_in, b_out);
	cov = max(cov, brows_on * (1.0 - smoothstep(0.0040, 0.0056, bd)));
	// upper lids over the painted eyes (eyes at x 0.03, y 0.014): a skin-coloured cap closing from the top, ink edge
	float lid = clamp(lids, 0.0, 1.0);
	vec2 e = (q - vec2(lay.z, lay.w - 0.016)) / vec2(0.0125, 0.0095);
	float inside = 1.0 - smoothstep(0.92, 1.0, length(e));
	float edge_y = 0.0095 * (1.0 - 2.0 * lid);           // lid edge descends from the top of the eye
	float covered = step(edge_y, q.y - (lay.w - 0.016));
	float lid_fill = lids_on * step(0.02, lid) * inside * covered;
	float lid_edge = lids_on * step(0.02, lid) * (1.0 - smoothstep(0.0013, 0.0026, abs(q.y - (lay.w - 0.016 + edge_y)))) * (1.0 - smoothstep(0.85, 1.05, length(e)));
	// mouth
	float my = lay.x;
	float w = lay.y;
	float closed = (1.0 - smoothstep(0.0034, 0.0050, abs(p.y - (my + mouth_curve * 0.016 * ((p.x / w) * (p.x / w) - 0.4))))) * step(abs(p.x), w);
	float oy = 0.0035 + 0.011 * mouth_open;
	vec2 mo = vec2(p.x / (w * 0.75), (p.y - (my - oy * 0.5)) / oy);
	float od = length(mo);
	float open_fill = 1.0 - smoothstep(0.92, 1.0, od);
	float open_rim = (1.0 - smoothstep(1.0, 1.25, od));
	float mo_k = smoothstep(0.04, 0.12, mouth_open);
	float mouth_cov = mix(closed, open_rim, mo_k);
	vec3 mouth_col = mix(INK, CAVITY, open_fill * mo_k);
	cov = max(cov, mouth_cov);
	float ink_a = cov;
	col = mix(col, mouth_col, mouth_cov * mo_k * open_fill);
	// compose: lid fill under the ink strokes
	float a = max(max(ink_a, lid_fill), lid_edge);
	vec3 c = mix(LID_SKIN, col, step(0.001, ink_a));
	c = mix(c, INK, lid_edge * (1.0 - step(0.5, ink_a)));
	return vec4(c, a);
}
