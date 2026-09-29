// Original work written for Rising Ashes (no third-party code). Same licence as the project.
// Replaces the godotshaders.com Kuwahara candidates: that site blocked automated licence verification.
// Painterly Kuwahara post-process (classic 4-sector Kuwahara). Put on a full-screen ColorRect in a CanvasLayer.
// Cost: (radius+1)^2 * 4 taps per pixel. radius 2 = 36 taps: DESKTOP/HIGH only, not for phones.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform int radius : hint_range(1, 5) = 2;
uniform float saturation : hint_range(0.5, 1.6) = 1.1;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 mean[4];
	vec3 sq[4];
	for (int i = 0; i < 4; i++) {
		mean[i] = vec3(0.0);
		sq[i] = vec3(0.0);
	}
	float n = float((radius + 1) * (radius + 1));
	for (int j = -radius; j <= radius; j++) {
		for (int i = -radius; i <= radius; i++) {
			vec3 c = texture(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px).rgb;
			if (i <= 0 && j <= 0) { mean[0] += c; sq[0] += c * c; }
			if (i >= 0 && j <= 0) { mean[1] += c; sq[1] += c * c; }
			if (i <= 0 && j >= 0) { mean[2] += c; sq[2] += c * c; }
			if (i >= 0 && j >= 0) { mean[3] += c; sq[3] += c * c; }
		}
	}
	float best = 1e9;
	vec3 col = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		vec3 m = mean[k] / n;
		vec3 v = sq[k] / n - m * m;
		float s = v.r + v.g + v.b;
		if (s < best) {
			best = s;
			col = m;
		}
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(l), col, saturation), 1.0);
}
