// Soft additive glow sprites for scripts/world/ambient_fx.gd particles:
// fireflies (slow blink), pollen / dust motes (brighten when you look towards
// the sun, like motes caught in a sunbeam) and chimney embers. Camera-facing
// quad, procedural falloff (no texture), unshaded, no depth write.
// Particle COLOR carries tint and the lifetime fade.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform float energy = 2.0;
uniform float blink = 0.0;            // 0 steady .. 1 fireflies' on/off pulse
uniform float blink_speed = 1.3;
uniform float core = 0.35;            // hot centre share
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // direction TOWARDS the sun (world)
uniform float sun_boost = 0.0;        // motes: extra brightness looking into the light
uniform float near_fade = 0.6;
uniform float far_fade = 45.0;

varying float v_gain;

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= sc;
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec3 to_p = wp - CAMERA_POSITION_WORLD;
	float dist = length(to_p);
	float g = 1.0;
	if (blink > 0.0) {
		float ph = fract(sin(float(INSTANCE_ID) * 91.37) * 4375.85) * 6.283;
		float pulse = pow(max(sin(TIME * blink_speed + ph), 0.0), 3.0);
		g = mix(1.0, 0.05 + pulse * 1.3, blink);
	}
	if (sun_boost > 0.0) {
		// Forward scatter: bright when the mote sits between the eye and the sun.
		float fw = max(dot(normalize(to_p), sun_dir), 0.0);
		g *= 0.35 + sun_boost * pow(fw, 6.0);
	}
	g *= smoothstep(near_fade * 0.5, near_fade, dist) * (1.0 - smoothstep(far_fade * 0.7, far_fade, dist));
	v_gain = g;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float hot = smoothstep(core, 0.0, d);
	vec3 c = tint.rgb * COLOR.rgb;
	ALBEDO = (c * halo + vec3(1.0, 0.97, 0.85) * hot * 0.6) * energy * v_gain * COLOR.a;
	ALPHA = 1.0;
}
