// Fish for scripts/world/ambient_fx.gd. The mesh is a flat PlaneMesh (width
// across X, length along Z, head at +Z) subdivided along its length so the tail
// can swish; the fragment shader cuts the silhouette (body + forked tail fin).
//   jump = false  a school under the clear water by the pier: a MultiMesh whose
//                 instances all sit at the node origin; INSTANCE_CUSTOM seeds
//                 give each fish its lane in a slow, loose circling school.
//   jump = true   one leaping fish: `progress` 0..1 (tweened by ambient_fx.gd)
//                 carries it along a short arc from `jump_from` to `jump_to`
//                 (node-local), nose following the arc. Plane stood up on edge.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, shadows_disabled;

uniform bool jump = false;
uniform vec4 albedo : source_color = vec4(0.06, 0.09, 0.09, 1.0);
uniform float school_radius = 2.6;
uniform float swim_speed = 0.35;
uniform float progress = 0.0;
uniform vec3 jump_from = vec3(0.0, -0.3, -0.6);
uniform vec3 jump_to = vec3(0.0, -0.3, 0.6);
uniform float jump_height = 0.7;

varying float v_along;
varying float v_top;

vec3 school_pos(float t, vec4 s) {
	float a = t * swim_speed * (0.9 + 0.2 * s.y) + s.x * 2.4;
	float r = school_radius * (0.55 + 0.6 * s.z);
	return vec3(cos(a) * r, (s.w - 0.5) * 0.35 + sin(t * 0.6 + s.x * 9.0) * 0.05, sin(a) * r)
		+ vec3(sin(t * 0.7 + s.w * 7.0), 0.0, cos(t * 0.5 + s.y * 5.0)) * 0.35;
}

vec3 arc(float p) {
	return mix(jump_from, jump_to, p) + vec3(0.0, 4.0 * jump_height * p * (1.0 - p), 0.0);
}

void vertex() {
	vec3 v = VERTEX;
	float half_len = 0.5;                      // mesh depth is 1: scaled below
	float along = v.z / half_len;             // -1 tail .. 1 head
	v_along = along;
	float seed = jump ? 0.3 : INSTANCE_CUSTOM.x;
	float t = TIME;
	// Tail swish: lateral wave growing towards the tail.
	float swish = sin(t * (jump ? 16.0 : 7.0) + along * 3.0 + seed * 20.0) * 0.12 * pow((1.0 - along) * 0.5, 1.5);
	v.x += swish;
	vec3 p;
	vec3 fwd;
	if (jump) {
		// Stand the fish on edge: across-X becomes up-Y.
		v = vec3(swish, VERTEX.x, VERTEX.z);
		p = arc(progress);
		fwd = normalize(arc(min(progress + 0.02, 1.0)) - arc(max(progress - 0.02, 0.0)) + vec3(0.0, 0.0, 0.0001));
	} else {
		vec4 s = INSTANCE_CUSTOM;
		p = school_pos(t, s);
		fwd = normalize(school_pos(t + 0.1, s) - p + vec3(0.0001));
	}
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd) + vec3(0.0001, 0.0, 0.0));
	vec3 up = cross(fwd, right);
	float sc = jump ? 0.45 : (0.28 + 0.12 * INSTANCE_CUSTOM.z);
	VERTEX = p + (right * v.x + up * v.y + fwd * v.z) * sc;
	NORMAL = jump ? right : up;
	v_top = jump ? VERTEX.y : 0.0;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float a = v_along;
	float w;
	if (a > -0.55) {
		float k = (a - 0.15) / 0.85;
		w = 0.85 * sqrt(max(1.0 - k * k, 0.0));
	} else {
		w = (-0.55 - a) * 2.0;                  // forked tail
		w = w > 0.2 ? w : 0.0;
		if (across < 0.35 * (a + 1.0) / 0.45 && a < -0.85) w = 0.0;
	}
	if (across > w) {
		discard;
	}
	vec3 c = albedo.rgb;
	if (jump) {
		// Silver belly, darker back, a wet highlight.
		c = mix(vec3(0.75, 0.78, 0.76), vec3(0.2, 0.28, 0.3), smoothstep(-0.1, 0.5, UV.x - 0.5));
		METALLIC = 0.5;
		ROUGHNESS = 0.25;
	} else {
		ROUGHNESS = 1.0;
	}
	ALBEDO = c;
}
