shader_type canvas_item;
// Region 1 parchment: paper, watercolour washes and ink hill-shading from the REAL WorldGen grid.
// grid: R = height (m), G = water depth (m, >0 wet), B = forest density 0..1, A = distance to nearest road (m)
uniform sampler2D grid : filter_linear, repeat_disable;
uniform float img_px = 2048.0;
uniform float margin_px = 88.0;
uniform float terrain_px = 1872.0;
uniform float cell_m = 8.0;
uniform float grid_n = 1024.0;
uniform float ex = 3.0;              // vertical exaggeration of hill shading
uniform vec4 clear_disc = vec4(0.0); // x, y, r, feather (compass)
uniform vec4 clear_a = vec4(0.0);    // x0 y0 x1 y1 (cartouche)
uniform vec4 clear_b = vec4(0.0);    // scale bar
uniform vec4 rift_a = vec4(0.0);     // x y r (px)
uniform vec4 rift_b = vec4(0.0);
uniform float show_wash = 1.0;

float hash21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i), hash21(i+vec2(1,0)), f.x), mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p){ float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++){ s += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; } return s; }

float hatch(vec2 p, float ang, float period, float w){
	vec2 d = vec2(cos(ang), sin(ang));
	float f = abs(fract(dot(p, d) / period) - 0.5) * period;
	return 1.0 - smoothstep(w - 0.6, w + 0.6, f);
}
float rect_clear(vec2 p, vec4 r, float feather){
	if (r.z <= r.x) return 0.0;
	vec2 c = (r.xy + r.zw) * 0.5; vec2 hs = (r.zw - r.xy) * 0.5;
	vec2 q = abs(p - c) - hs;
	float d = max(q.x, q.y);
	return 1.0 - smoothstep(-feather, feather * 0.4, d + (fbm(p * 0.03) - 0.5) * feather);
}

vec4 gs(vec2 t){ return texture(grid, t); }

void fragment(){
	vec2 p = UV * img_px;
	// ---- paper ----
	float big = fbm(p * 0.0035);
	float mid = fbm(p * 0.012 + 3.0);
	float fine = vnoise(p * 0.9) * 0.5 + vnoise(p * 2.3) * 0.5;
	vec3 paper = mix(vec3(0.945, 0.870, 0.690), vec3(0.880, 0.780, 0.575), big);
	paper *= 0.965 + 0.06 * mid;
	paper *= 0.975 + 0.05 * fine;
	// fibres: thin stretched streaks
	float fib = vnoise(vec2(p.x * 0.5, p.y * 0.035) + 40.0) * vnoise(vec2(p.x * 0.035, p.y * 0.5) + 80.0);
	paper *= 1.0 - 0.06 * smoothstep(0.35, 0.8, fib);
	// water stains / foxing
	float stain = smoothstep(0.58, 0.85, fbm(p * 0.0022 + 11.0));
	paper = mix(paper, paper * vec3(0.90, 0.80, 0.62), stain * 0.55);
	float fox = smoothstep(0.78, 0.9, vnoise(p * 0.05 + 5.0)) * smoothstep(0.5, 0.75, fbm(p * 0.004 + 2.0));
	paper = mix(paper, vec3(0.68, 0.47, 0.24), fox * 0.35);

	vec3 col = paper;
	// ---- terrain ----
	vec2 t = (p - vec2(margin_px)) / terrain_px;
	float ed = min(min(p.x - margin_px, p.y - margin_px), min(margin_px + terrain_px - p.x, margin_px + terrain_px - p.y));
	float m = smoothstep(2.0, 56.0, ed + (fbm(p * 0.02) - 0.5) * 90.0);   // ragged watercolour edge
	m *= 1.0 - rect_clear(p, clear_a, 46.0);
	m *= 1.0 - rect_clear(p, clear_b, 40.0);
	if (clear_disc.z > 0.0){
		float dd = length(p - clear_disc.xy) - clear_disc.z + (fbm(p * 0.03) - 0.5) * clear_disc.w;
		m *= smoothstep(-clear_disc.w * 0.2, clear_disc.w, dd);
	}
	if (m > 0.001 && t.x > -0.02 && t.x < 1.02 && t.y > -0.02 && t.y < 1.02){
		vec2 tc = clamp(t, 0.0, 1.0);
		vec4 g = gs(tc);
		float h = g.r;
		float wetd = g.g;
		float forest = g.b;
		float texel = 1.0 / grid_n;
		float k = 2.0 * texel;
		float hl = gs(tc - vec2(k, 0)).r, hr = gs(tc + vec2(k, 0)).r, hu = gs(tc - vec2(0, k)).r, hd = gs(tc + vec2(0, k)).r;
		vec3 nrm = normalize(vec3((hl - hr) / (2.0 * cell_m * 2.0) * ex, 1.0, (hu - hd) / (2.0 * cell_m * 2.0) * ex));
		vec3 L = normalize(vec3(-0.6, 0.75, -0.45));
		float s = clamp((dot(nrm, L) - L.y) * 3.2, -1.0, 1.0);          // <0 = shade side
		float slope = 1.0 - nrm.y;

		// land wash by elevation
		vec3 lo = vec3(0.70, 0.79, 0.50), md = vec3(0.86, 0.77, 0.47), hi = vec3(0.74, 0.62, 0.46), pk = vec3(0.84, 0.79, 0.70);
		vec3 land = mix(lo, md, smoothstep(6.0, 40.0, h));
		land = mix(land, hi, smoothstep(50.0, 95.0, h));
		land = mix(land, pk, smoothstep(105.0, 140.0, h));
		float blot = fbm(p * 0.016 + 7.0);
		land *= 0.93 + 0.14 * blot;
		vec3 tcol = mix(paper, land * (paper / vec3(0.91, 0.83, 0.63)), 0.13 * show_wash);
		// forest wash (soft green pooled, granulated)
		float fw = smoothstep(0.25, 0.7, forest) * (0.55 + 0.45 * vnoise(p * 0.11));
		tcol = mix(tcol, tcol * vec3(0.66, 0.80, 0.50), fw * 0.26 * show_wash);
		// rock / steep ground
		float rockw = smoothstep(0.10, 0.3, slope) + smoothstep(100.0, 140.0, h);
		tcol = mix(tcol, tcol * vec3(0.86, 0.80, 0.74), clamp(rockw, 0.0, 1.0) * 0.35);
		// ink hill shading: soft wash + pen hatching on the shade side
		float sh = smoothstep(0.08, 0.75, -s);
		float sun = smoothstep(0.1, 0.8, s);
		tcol *= 1.0 - sh * 0.07;
		tcol = mix(tcol, tcol * vec3(1.05, 1.03, 0.92), sun * 0.4);
		vec2 wp = p + (vec2(vnoise(p * 0.045), vnoise(p * 0.045 + 9.0)) - 0.5) * 7.0;
		float hh = hatch(wp, 0.785, 5.2, 0.55) * smoothstep(0.42, 0.7, sh) * (1.0 - fw * 0.8);
		float hh2 = hatch(wp, -0.785, 5.6, 0.5) * smoothstep(0.75, 0.98, sh) * (1.0 - fw * 0.8);
		vec3 ink = vec3(0.32, 0.21, 0.11);
		tcol = mix(tcol, ink, clamp(hh * 0.24 + hh2 * 0.2, 0.0, 0.8));
		// contour hint: very faint terrace lines
		float band = fract(h / 22.0);
		float ct = (1.0 - smoothstep(0.0, 0.05, band)) * smoothstep(0.03, 0.10, slope) * (1.0 - fw);
		tcol = mix(tcol, ink, ct * 0.05);

		// Rift-touched wilds: dead violet ground bleeding out
		float rd = 0.0;
		if (rift_a.z > 0.0) rd = max(rd, smoothstep(rift_a.z, rift_a.z * 0.15, length(p - rift_a.xy) + (fbm(p * 0.02) - 0.5) * 60.0));
		if (rift_b.z > 0.0) rd = max(rd, smoothstep(rift_b.z, rift_b.z * 0.15, length(p - rift_b.xy) + (fbm(p * 0.02 + 5.0) - 0.5) * 50.0));
		float lum = dot(tcol, vec3(0.3, 0.59, 0.11));
		tcol = mix(tcol, mix(vec3(lum), vec3(0.50, 0.38, 0.62), 0.6) * 1.03, rd * 0.7);

		// water
		float wet = smoothstep(0.0, 0.25, wetd);
		if (wetd > 0.0){
			float dp = smoothstep(0.0, 5.0, wetd);
			vec3 wc = mix(vec3(0.66, 0.83, 0.84), vec3(0.42, 0.65, 0.76), dp);
			wc *= 0.94 + 0.10 * fbm(p * 0.03);
			tcol = mix(tcol, wc * (paper / vec3(0.91, 0.83, 0.63)), 0.9);
			// wave dashes
			float wv = sin((p.y + 5.0 * vnoise(p * 0.08)) * 1.05);
			float dash = smoothstep(0.93, 0.99, wv) * smoothstep(0.58, 0.7, vnoise(p * vec2(0.09, 0.32) + 3.0));
			tcol = mix(tcol, vec3(0.28, 0.42, 0.52), dash * 0.55 * dp);
		}
		// shoreline ink (edge of the wet mask), wobbly
		float e1 = 2.4 * texel;
		float w1 = gs(tc + vec2(e1, 0)).g > 0.0 ? 1.0 : 0.0;
		float w2 = gs(tc - vec2(e1, 0)).g > 0.0 ? 1.0 : 0.0;
		float w3 = gs(tc + vec2(0, e1)).g > 0.0 ? 1.0 : 0.0;
		float w4 = gs(tc - vec2(0, e1)).g > 0.0 ? 1.0 : 0.0;
		float here = wetd > 0.0 ? 1.0 : 0.0;
		float edge = (abs(here - w1) + abs(here - w2) + abs(here - w3) + abs(here - w4)) > 0.5 ? 1.0 : 0.0;
		tcol = mix(tcol, vec3(0.26, 0.24, 0.24), edge * 0.35 * (0.7 + 0.3 * vnoise(p * 0.4)));

		col = mix(paper, tcol, m);
	}
	// ---- edge burn / vignette on the paper ----
	float bd = min(min(p.x, p.y), min(img_px - p.x, img_px - p.y));
	float burn = smoothstep(120.0, 0.0, bd + (fbm(p * 0.02) - 0.5) * 70.0);
	col = mix(col, col * vec3(0.66, 0.48, 0.28), burn * 0.62);
	float vg = length((UV - 0.5) * 1.25);
	col *= 1.0 - 0.10 * smoothstep(0.35, 0.85, vg);
	float gl = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(gl) * vec3(1.07, 0.94, 0.72), 0.22);   // sepia grade, like the poster maps
	COLOR = vec4(col, 1.0);
}
