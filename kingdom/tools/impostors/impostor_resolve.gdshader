// Resolve pass of the impostor baker: supersampled atlas -> final atlas.
//  * coverage-weighted box filter: anti-aliased alpha, colour is not darkened by transparent neighbours
//  * colour dilation: fully transparent texels take the colour of the nearest opaque texel of the SAME tile (never crosses a tile border)
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D src : filter_nearest;
uniform int grid = 7;
uniform int ss = 2;
uniform vec2 src_size = vec2(2464.0);
uniform int dilate_px = 12;   // output pixels

vec4 tap(vec2 uv, vec2 tmin, vec2 tmax, vec2 sp) {
	return texture(src, clamp(uv, tmin + sp * 0.5, tmax - sp * 0.5));
}

void fragment() {
	vec2 uv = UV;
	float g = float(grid);
	vec2 tile = floor(uv * g);
	vec2 tmin = tile / g;
	vec2 tmax = (tile + 1.0) / g;
	vec2 sp = 1.0 / src_size;                    // one source texel
	vec2 op = sp * float(ss);                    // one output texel
	// box filter
	vec3 csum = vec3(0.0);
	float asum = 0.0;
	for (int j = 0; j < ss; j++) {
		for (int i = 0; i < ss; i++) {
			vec2 o = (vec2(float(i), float(j)) + 0.5) / float(ss) - 0.5;
			vec4 c = tap(uv + o * op, tmin, tmax, sp);
			csum += c.rgb * c.a;
			asum += c.a;
		}
	}
	float a = asum / float(ss * ss);
	vec3 col = asum > 0.0001 ? csum / asum : vec3(0.0);
	if (a < 0.02) {
		// dilate: ring search over the output-resolution neighbourhood, nearest opaque texel wins
		vec3 found = vec3(0.0);
		bool hit = false;
		for (int r = 1; r <= dilate_px && !hit; r++) {
			float fr = float(r);
			vec3 acc = vec3(0.0);
			float w = 0.0;
			for (int k = 0; k < 16; k++) {
				float ang = 6.2831853 * float(k) / 16.0;
				vec2 p = uv + vec2(cos(ang), sin(ang)) * fr * op;
				vec4 c = tap(p, tmin, tmax, sp);
				if (c.a > 0.5) {
					acc += c.rgb;
					w += 1.0;
				}
			}
			if (w > 0.0) {
				found = acc / w;
				hit = true;
			}
		}
		col = found;
	}
	COLOR = vec4(col, a);
}
