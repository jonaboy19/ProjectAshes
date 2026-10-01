// Style Lab sky: vertical gradient + soft cumulus from one noise texture + sun glow. One texture tap per
// sky pixel (only where the sky is visible). posterize > 0 snaps clouds into painted bands (B).
shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color = vec3(0.2, 0.45, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.88, 1.0);
uniform vec3 ground_color : source_color = vec3(0.7, 0.65, 0.55);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.78, 0.92);
uniform float cloud_cover = 0.5;
uniform float cloud_soft = 0.22;
uniform float posterize = 0.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float sun_glow = 0.35;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, h));
	if (h > 0.02) {
		vec2 uv = d.xz / (h + 0.25) * 0.35;
		float n = texture(cloud_noise, uv).r * 0.65 + texture(cloud_noise, uv * 2.7 + 0.31).r * 0.35;
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + cloud_soft, n);
		if (posterize > 0.0) { m = mix(m, floor(m * 3.0 + 0.5) / 3.0, posterize); }
		float fade = smoothstep(0.02, 0.22, h);
		vec3 cc = mix(cloud_shade, cloud_color, smoothstep(0.35, 0.8, n));
		col = mix(col, cc, m * fade);
	}
	// sun glow toward the first directional light
	float sd = max(dot(d, normalize(LIGHT0_DIRECTION)), 0.0);
	col += sun_color * (pow(sd, 24.0) * sun_glow + pow(sd, 400.0) * 0.8);
	COLOR = col;
}
