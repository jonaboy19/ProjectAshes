// Original work written for Rising Ashes (no third-party code). Same licence as the project.
// Replaces the godotshaders.com "stylized sky with clouds" candidate (site blocked automated licence verification).
// Sunny storybook sky: saturated blue zenith to light-blue haze horizon, sun glow, soft white cumulus
// (3-octave value-noise fbm, no texture reads). Keep clouds at 3 octaves on phones.
shader_type sky;
uniform vec3 zenith : source_color = vec3(0.16, 0.42, 0.86);
uniform vec3 horizon : source_color = vec3(0.68, 0.84, 0.97);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.6);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.68, 0.74, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.01;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * vn(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float t = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(t, 0.6));
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = clamp(dot(d, sun_dir), 0.0, 1.0);
	col += sun_color * (pow(sd, 400.0) * 3.0 + pow(sd, 12.0) * 0.25);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.25) * 1.5 + vec2(TIME * cloud_speed, 0.0);
		float c = fbm(uv * 1.3);
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, c);
		float lit = fbm(uv * 1.3 + sun_dir.xz * 0.15) < c ? 1.0 : 0.0;
		vec3 cc = mix(cloud_shade, cloud_lit, 0.35 + 0.65 * lit);
		col = mix(col, cc, m * smoothstep(0.0, 0.25, d.y));
	} else {
		col = horizon;
	}
	COLOR = col;
}
