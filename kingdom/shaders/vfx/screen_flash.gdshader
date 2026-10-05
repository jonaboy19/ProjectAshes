shader_type canvas_item;
// Cheap screen flash for a technique's flash phase. `blur` > 0 adds a 5-tap radial blur of the screen (HIGH tiers
// only; LOW / MEDIUM pass 0 and never read the screen texture's copy, so the flash is a tinted radial streak only).
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 flash_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float blur = 0.0;
uniform vec2 center = vec2(0.5, 0.5);

void fragment() {
	vec2 d = SCREEN_UV - center;
	float r = length(d);
	float ang = atan(d.y, d.x) / 6.2831853 + 0.5;
	float rays = step(0.45, texture(noise_tex, vec2(ang * 6.0, 0.3)).r);
	float edge = smoothstep(0.1, 0.9, r);
	vec3 col = vec3(0.0);
	float a = amount * (0.22 + 0.5 * edge * (0.4 + 0.6 * rays));
	if (blur > 0.0) {
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 5; i++) {
			acc += texture(screen_tex, SCREEN_UV - d * blur * amount * float(i) * 0.25).rgb;
		}
		col = mix(acc / 5.0, flash_color.rgb, a);
		COLOR = vec4(col, amount > 0.01 ? 1.0 : 0.0);
	} else {
		COLOR = vec4(flash_color.rgb, a);
	}
}
