shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled, shadows_disabled;
// Soft fire: flame tongues, ground glow and soot for the fire VFX (scenes/vfx/elements/fire).
// Premultiplied alpha = the body of the flame is saturated (it tints the bright ground instead of
// washing out) and the hot core is additive (it glows and blooms). No hard silhouettes: every edge
// is a wide smoothstep eroded by scrolling noise.
//   mode 0  flame tongues (mesh from build_element_scenes.gd `flame_mesh`: cylindrical billboards,
//           UV = tongue space, UV2 = base position xz in metres, COLOR = phase, height scale, delay, width scale)
//   mode 1  ground glow: eroded disc that expands with `radius_frac`, hot advancing front, ember veins
//   mode 2  soot scorch: dark soft patch under the fire (alpha)
uniform int mode = 0;
uniform vec4 col_core : source_color = vec4(1.0, 0.93, 0.62, 1.0);
uniform vec4 col_mid : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 col_edge : source_color = vec4(0.72, 0.16, 0.05, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float master : hint_range(0.0, 1.0) = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;    // 0 fresh .. 1 dissolved (noise erosion, not a fade)
uniform float grow : hint_range(0.0, 1.0) = 1.0;        // tongues rise (staggered by their delay)
uniform float spread : hint_range(0.0, 1.0) = 1.0;      // tongue bases move out from the centre
uniform float radius_frac : hint_range(0.0, 1.0) = 1.0; // ground: disc radius
uniform float mesh_r = 3.2;                             // ground: quad half size in metres
uniform float speed = 1.0;                              // flicker / scroll speed
uniform float body_alpha : hint_range(0.0, 1.0) = 0.8;  // how much the flame darkens the ground behind it
uniform float glow : hint_range(0.0, 3.0) = 0.7;        // additive hot core strength
uniform float lean = 0.15;                              // tongues lean outward with height

varying vec3 lp;
varying vec4 tc;

float h21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
	tc = COLOR;
	if (mode == 0) {
		vec3 base = vec3(UV2.x, 0.0, UV2.y) * spread;
		vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
		vec3 d = cam - base;
		d.y = 0.0;
		d = normalize(d + vec3(0.0001, 0.0, 0.0));
		vec3 right = vec3(d.z, 0.0, -d.x);
		float tg = clamp((grow - COLOR.b) / 0.4, 0.0, 1.0);
		tg = tg * tg * (3.0 - 2.0 * tg);
		float hy = VERTEX.y;
		float sway = sin(TIME * 2.6 * speed + COLOR.r * 40.0) * 0.07 * hy;
		vec3 out_dir = normalize(vec3(base.x, 0.0, base.z) + vec3(0.0001, 0.0, 0.0));
		VERTEX = base + right * (VERTEX.x * (0.55 + 0.45 * tg) + sway) + vec3(0.0, hy * tg, 0.0) + out_dir * hy * lean * tg;
	}
}

void fragment() {
	float t = TIME * speed;
	vec3 col = col_mid.rgb;
	float a = 0.0;
	float hot = 0.0;
	if (mode == 0) {
		float ph = tc.r;
		float x = (UV.x - 0.5) * 2.0;
		float y = UV.y;
		vec2 np = vec2(x * 1.2 + ph * 9.0, y * 2.1 - t * 1.5 - ph * 5.0);
		float n1 = vn(np * vec2(1.5, 1.0));
		float n2 = vn(np * vec2(3.1, 2.3) + vec2(3.7, -t * 1.8));
		float turb = (n1 - 0.5) * 0.95 + (n2 - 0.5) * 0.4;
		float xd = x + turb * (0.25 + y) * 0.9;
		float w = pow(max(1.0 - y, 0.0), 0.8) * mix(0.55, 1.0, smoothstep(0.0, 0.3, y));
		float d = abs(xd) / max(w, 0.02);
		float thr = progress * 1.15;
		float dens = (1.0 - d) * 1.05 - y * 0.32 + (n2 - 0.5) * 0.45 - thr;
		a = smoothstep(0.0, 0.42, dens);
		a *= smoothstep(0.0, 0.3, y);
		float heat = dens * (1.2 - 0.55 * y);
		col = mix(col_edge.rgb, col_mid.rgb, smoothstep(0.08, 0.42, heat));
		col = mix(col, col_core.rgb, smoothstep(0.5, 0.95, heat));
		hot = smoothstep(0.45, 1.0, heat) * (1.0 - y * 0.7);
	} else if (mode == 1) {
		vec2 g = lp.xz / mesh_r;
		float rr = length(g);
		float ang = atan(g.y, g.x);
		float n = vn(g * 4.2 + t * 0.35) * 0.65 + vn(g * 9.0 - t * 0.6) * 0.35;
		float edge = rr - radius_frac * 0.95 + (n - 0.5) * 0.4 + progress * 0.35;
		float body = 1.0 - smoothstep(-0.42, 0.04, edge);
		float front = exp(-pow((edge + 0.06) / 0.1, 2.0));
		float veins = 1.0 - smoothstep(0.0, 0.16, abs(vn(g * 6.0 + vec2(1.7, t * 0.2)) - 0.5));
		float fade = 1.0 - progress;
		float heat = clamp(front * 1.1 + veins * 0.55 * body + body * 0.28, 0.0, 1.3) * fade;
		a = body * fade * 0.6 + front * 0.4 * fade;
		a *= 1.0 - smoothstep(0.96, 1.0, rr);
		col = mix(col_edge.rgb, col_mid.rgb, smoothstep(0.12, 0.5, heat));
		col = mix(col, col_core.rgb, smoothstep(0.62, 1.0, heat));
		hot = smoothstep(0.55, 1.1, heat) * 0.8;
	} else {
		vec2 g = lp.xz / mesh_r;
		float rr = length(g);
		float n = vn(g * 3.3) * 0.6 + vn(g * 8.1) * 0.4;
		float edge = rr - radius_frac * 0.92 + (n - 0.5) * 0.45 + progress * 0.4;
		a = (1.0 - smoothstep(-0.5, 0.05, edge)) * (1.0 - progress) * (0.7 + 0.3 * n);
		col = col_edge.rgb;
	}
	a *= master;
	float occ = a * body_alpha * (1.0 - hot * 0.75);
	vec3 emit = col * intensity * (a * 0.9 + hot * glow * a);
	if (mode == 2) {
		occ = a * body_alpha;
		emit = col * a * body_alpha;
	}
	ALBEDO = emit;
	ALPHA = clamp(occ, 0.0, 1.0);
}
