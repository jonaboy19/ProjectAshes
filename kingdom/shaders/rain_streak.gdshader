// Rain streaks (and snow flakes) for the one camera-following GPUParticles3D in
// scripts/world/weather.gd. Each particle is a unit QuadMesh rebuilt here as a
// thin quad stretched along the particle's velocity (ParticleProcessMaterial
// align_y puts velocity on the particle's Y axis), turned about that axis to
// face the camera. Unshaded, no depth write, no shadows: one tiny alpha quad per
// drop, so 1500 of them cost about as much as a UI panel.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec4 tint : source_color = vec4(0.78, 0.82, 0.9, 0.32);
uniform float streak_length = 0.85;   // metres
uniform float streak_width = 0.016;   // metres (grows a little with distance so far drops don't alias away)
uniform float flake_size = 0.06;      // snow mode quad size
uniform float snow = 0.0;             // 0 = rain streaks, 1 = soft round flakes facing the camera
uniform float near_fade = 1.4;        // drops closer than this fade out (no giant streaks on the lens)
uniform float far_fade = 22.0;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float dist = max(length(to_cam), 0.001);
	vec2 q = UV - vec2(0.5);
	if (snow > 0.5) {
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		VERTEX = center + (right * q.x - up * q.y) * flake_size;
	} else {
		vec3 up = normalize(MODEL_MATRIX[1].xyz);
		vec3 side = normalize(cross(up, to_cam / dist));
		float w = streak_width * (1.0 + dist * 0.035);
		VERTEX = center + side * (q.x * w) - up * (q.y * streak_length);
	}
	v_fade = smoothstep(near_fade * 0.5, near_fade, dist) * (1.0 - smoothstep(far_fade * 0.75, far_fade, dist));
}

void fragment() {
	vec2 q = UV - vec2(0.5);
	float shape;
	if (snow > 0.5) {
		shape = 1.0 - smoothstep(0.15, 0.5, length(q));
	} else {
		float across = 1.0 - smoothstep(0.0, 0.5, abs(q.x));
		float along = 1.0 - abs(q.y) * 2.0;           // taper both ends
		shape = across * sqrt(max(along, 0.0));
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a * shape * v_fade;
}
