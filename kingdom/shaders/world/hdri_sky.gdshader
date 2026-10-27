// W6 slice gate (ref 01): the visible sky is a CC0 Poly Haven HDRI (kloofendal_48d_partly_cloudy_puresky), rotated every frame so
// the sun in the photo sits where the game's sun (LIGHT0) is: deep blue between crisp cumulus, no tiling. Sun pixels are clamped so
// they do not blow the radiance; the game's own sun disk stays the DirectionalLight. The lab_sky uniforms are kept as no-ops so
// style_g / weather can keep writing them.
shader_type sky;
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float sun_u = 0.5951;           // horizontal position of the sun in the HDRI (tools: hdr_sun.py)
uniform float energy = 0.85;
uniform float clamp_max = 14.0;
uniform vec3 ground_color : source_color = vec3(0.32, 0.36, 0.28);
// lab_sky compatibility (unused)
uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 cloud_color : source_color;
uniform vec3 cloud_shade : source_color;
uniform float cloud_cover;
uniform float cloud_soft;
uniform float posterize;
uniform vec3 sun_color : source_color;
uniform float sun_glow;
uniform sampler2D cloud_noise;

void sky() {
	vec3 d = normalize(EYEDIR);
	float la = atan(LIGHT0_DIRECTION.x, -LIGHT0_DIRECTION.z);
	float a = atan(d.x, -d.z);
	float u = fract((a - la) / (2.0 * PI) + sun_u);
	float v = acos(clamp(d.y, -1.0, 1.0)) / PI;
	vec3 c = min(texture(panorama, vec2(u, min(v, 0.499))).rgb, vec3(clamp_max)) * energy;
	// below the horizon: fade to a muted ground colour (the terrain covers it almost everywhere)
	c = mix(c, ground_color * energy, smoothstep(0.0, -0.08, d.y));
	COLOR = c;
}
