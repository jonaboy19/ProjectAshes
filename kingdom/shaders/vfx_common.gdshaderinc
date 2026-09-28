// Shared sprite code for the VFX library (vfx_sprite / vfx_smoke).
// One 1024 greyscale atlas (4x4 cells, assets/incoming/vfx/atlas) coloured by a
// three-stop ramp: edge -> tint -> hot. The sprite value drives the ramp, so the
// middle of every sprite burns white-hot and its rim falls off to a deep colour.
// Particles cool down over their life (INSTANCE_CUSTOM.y), like embers.

uniform sampler2D atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 edge : source_color = vec4(0.6, 0.1, 0.02, 1.0);
uniform float energy = 3.0;
// Atlas cell 0..15; -1 soft dot, -2 crystal shard, -3 soft ring.
uniform int cell = -1;
uniform float heat = 1.0;       // ramp gain (>1 hotter)
uniform float cool = 0.6;       // how far the ramp cools over a particle's life
uniform bool particle = true;   // read INSTANCE_CUSTOM (GPUParticles3D)
uniform bool spin = false;      // rotate the quad by the particle angle
uniform float distort = 0.0;    // noise wobble of the UVs (flames, smoke)
uniform float fade = 1.0;       // global alpha (tweened)
uniform bool billboard = false; // plain MeshInstance3D facing the camera
uniform float bb_scale = 1.0;

varying vec2 v_ls;

vec3 vfx_ramp(float v) {
	vec3 c = mix(edge.rgb, tint.rgb, smoothstep(0.0, 0.45, v));
	return mix(c, hot.rgb, smoothstep(0.55, 1.0, v));
}

float vfx_sprite(vec2 uv) {
	if (cell < 0) {
		vec2 p = uv - vec2(0.5);
		if (cell == -1) {
			float d = length(p) * 2.0;
			return pow(clamp(1.0 - d, 0.0, 1.0), 1.8);
		} else if (cell == -2) {
			// Elongated diamond with a bright spine: ice shard / crystal.
			float d = abs(p.x) * 4.0 + abs(p.y) * 2.05;
			float body = smoothstep(1.0, 0.7, d);
			return body * (0.55 + 0.45 * smoothstep(0.12, 0.0, abs(p.x)));
		} else {
			float r = length(p) * 2.0;
			return exp(-pow((r - 0.75) * 7.0, 2.0));
		}
	}
	vec2 c = vec2(float(cell % 4), float(cell / 4));
	return texture(atlas, (c + clamp(uv, 0.0, 1.0)) * 0.25).r;
}

// Returns (life, seed). Varyings are written by the caller's vertex().
vec2 vfx_vertex(inout vec3 vertex, inout mat4 modelview, mat4 view, mat4 inv_view, mat4 model, vec4 custom) {
	vec2 ls = vec2(0.0);
	if (particle) {
		ls = vec2(custom.y, fract(custom.x * 1.618 + custom.w * 3.1));
		if (spin) {
			float a = custom.x;
			vertex.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * vertex.xy;
		}
	}
	if (billboard) {
		modelview = view * mat4(inv_view[0], inv_view[1], inv_view[2], model[3]);
		vertex *= bb_scale * length(model[0].xyz);
	}
	return ls;
}

// rgb = ramp colour, a = coverage. `ls` = (life 0..1, random seed).
vec4 vfx_shade(vec2 uv, vec4 color, float time, vec2 ls) {
	if (distort > 0.0) {
		vec2 n = texture(noise_tex, uv * 0.6 + vec2(ls.y, time * -0.45)).rg - vec2(0.5);
		uv += n * distort * (1.4 - uv.y);
	}
	float v = vfx_sprite(uv);
	float h = clamp(v * heat * (1.0 - ls.x * cool), 0.0, 1.0);
	return vec4(vfx_ramp(h), clamp(v * color.a * tint.a * fade, 0.0, 1.0));
}
