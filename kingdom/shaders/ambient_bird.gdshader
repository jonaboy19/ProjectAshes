// Bird flocks for scripts/world/ambient_fx.gd, animated entirely here.
// One MultiMeshInstance3D per flock: the node sits at the flock's anchor (on the
// ground), every instance transform is identity and INSTANCE_CUSTOM holds four
// random seeds per bird. The vertex shader places, orients and flaps each bird:
//   mode 0  circling flock: loose orbit round the anchor at `height`, slow drift
//           with the wind, individual swirl, flap / glide cycles, banking.
//   mode 1  landed flock: birds walk and peck on the ground, wings folded, until
//           the player comes near. Then ambient_fx.gd sets `scatter_origin` and
//           runs `scatter_age` from 0: birds burst up and away from the origin,
//           join a circling orbit, and glide back down after ~30 s.
// No per-bird script: the only uniforms written at runtime are presence / wind
// (4 Hz) and scatter_age (per frame, only for the ~35 s after a scatter).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform int mode = 0;
uniform vec4 albedo : source_color = vec4(0.12, 0.10, 0.09, 1.0);
uniform float height = 16.0;          // circling height above the anchor
uniform float orbit = 16.0;           // circling radius
uniform float speed = 0.22;           // orbit angular speed (rad/s)
uniform float spread = 5.0;           // landed flock footprint (m)
uniform float bird_scale = 1.0;
uniform float presence = 1.0;         // 0..1: birds shrink away (night, rain)
uniform vec2 wind = vec2(0.0);        // world XZ drift direction * strength
uniform vec3 scatter_origin = vec3(1.0e6);
uniform float scatter_age = 1000.0;   // seconds since the last scatter
uniform float scatter_radius = 16.0;

varying float v_shade;

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec3 circle_pos(float t, vec4 s, float fh) {
	float dir = fh > 0.5 ? 1.0 : -1.0;
	float a = t * speed * (0.9 + 0.2 * s.y) * dir + s.x * 2.2;
	float r = orbit * (0.7 + 0.6 * fract(fh * 7.31)) * (0.7 + 0.6 * s.z);
	float h = height * (0.75 + 0.6 * fract(fh * 3.17));
	vec3 p = vec3(cos(a) * r, h + (s.z - 0.5) * 5.0 + sin(t * 0.45 + s.w * 6.283) * 1.4, sin(a) * r);
	p += vec3(sin(t * 0.9 + s.w * 9.0), 0.5 * sin(t * 1.3 + s.x * 7.0), cos(t * 0.8 + s.y * 8.0)) * 1.3;
	// Whole flock wanders over minutes and leans downwind.
	p.xz += vec2(sin(t * 0.013 + fh * 20.0), cos(t * 0.011 + fh * 13.0)) * 14.0 + wind * 5.0;
	return p;
}

vec3 ground_pos(float t, vec4 s) {
	vec3 p = vec3((s.x - 0.5) * spread, 0.02, (s.y - 0.5) * spread);
	p.xz += vec2(sin(t * 0.21 + s.z * 6.283), cos(t * 0.17 + s.w * 6.283)) * 0.7;
	return p;
}

// Returns the bird's model-space position and how much it is airborne (0..1).
vec3 bird_pos(float t, float age, vec4 s, float fh, bool near, out float fly) {
	if (mode == 0) {
		fly = 1.0;
		return circle_pos(t, s, fh);
	}
	vec3 g = ground_pos(t, s);
	fly = 0.0;
	if (!near || age > 40.0) {
		return g;
	}
	float delay = s.w * 0.35;                   // not all at once
	float a = max(age - delay, 0.0);
	fly = smoothstep(0.0, 0.5, a) * (1.0 - smoothstep(25.0 + s.z * 4.0, 34.0 + s.z * 4.0, a));
	vec2 away = g.xz + vec2(s.x - 0.5, s.y - 0.5) * 2.0;
	away = normalize(away + vec2(0.001, 0.0));
	vec3 flee = g + vec3(away.x, 0.0, away.y) * (a * 6.5) + vec3(0.0, a * (4.0 + s.z * 2.0), 0.0);
	vec3 c = circle_pos(t, s, fh) * vec3(0.8, 0.7, 0.8);
	vec3 air = mix(flee, c, smoothstep(1.2, 6.0, a));
	return mix(g, air, fly);
}

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float fh = hash1(floor(anchor * 0.1));      // per-flock variety
	bool near = length(anchor.xz - scatter_origin.xz) < scatter_radius;
	float t = TIME;
	float fly;
	float fly2;
	vec3 p = bird_pos(t, scatter_age, s, fh, near, fly);
	vec3 p2 = bird_pos(t + 0.12, scatter_age + 0.12, s, fh, near, fly2);
	vec3 vel = p2 - p;
	float yaw = s.z * 6.283 + sin(t * 0.1 + s.x * 5.0) * 1.5;
	vec3 fwd_ground = vec3(sin(yaw), 0.0, cos(yaw));
	vec3 fwd = length(vel) > 0.004 ? normalize(vel) : fwd_ground;
	fwd = normalize(mix(fwd_ground, fwd, smoothstep(0.05, 0.4, fly)) + vec3(0.0001));
	// Bank into turns: roll from the horizontal turn rate.
	vec3 up0 = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up0, fwd) + vec3(0.0001, 0.0, 0.0));
	vec3 up = cross(fwd, right);
	float bank = (mode == 0 ? (fh > 0.5 ? -0.35 : 0.35) : 0.0) * fly;
	right = normalize(right * cos(bank) + up * sin(bank));
	up = cross(fwd, right);

	vec3 v = VERTEX * bird_scale * presence;
	float wing = COLOR.r;                       // 0 body .. 1 wing tip
	if (wing > 0.0) {
		float sx = sign(v.x);
		float d = abs(v.x);
		// Flap vs glide: periods of flapping with glides between.
		float flap_rate = 11.0 + s.y * 4.0 + (mode == 1 ? 4.0 : 0.0);
		float glide = smoothstep(0.2, 0.7, sin(t * 0.35 + s.x * 6.283));
		float amp = mode == 0 ? mix(1.0, 0.18, glide) : 1.0;
		float ang = sin(t * flap_rate + s.w * 6.283) * 0.85 * amp * (1.0 + wing * 0.35);
		ang = mix(-0.2, ang, smoothstep(0.0, 0.25, fly));
		// Folded on the ground: wings tucked along the body.
		float fold = 1.0 - smoothstep(0.0, 0.3, fly);
		d *= mix(1.0, 0.18, fold);
		v.x = sx * d * cos(ang);
		v.y += d * sin(ang);
	}
	if (mode == 1) {
		// Peck: nose dips now and then while landed.
		float peck = max(sin(t * 3.0 + s.x * 20.0), 0.0) * step(0.6, sin(t * 0.7 + s.y * 9.0)) * (1.0 - fly);
		v.y -= max(v.z, 0.0) * peck * 0.9;
		v.y += 0.06 * (1.0 - fly) * bird_scale * presence;
	}
	VERTEX = p + right * v.x + up * v.y + fwd * v.z;
	NORMAL = up;
	v_shade = 0.75 + 0.25 * wing;
}

void fragment() {
	ALBEDO = albedo.rgb * v_shade;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.15);
}
