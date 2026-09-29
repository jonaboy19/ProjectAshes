extends RefCounted
## (1) Foot IK / ground alignment on stairs and slopes. Uses the project's ProceduralRig
## (scripts/actors/procedural_rig.gd: TwoBoneIK3D per leg + pelvis drop + foot tilt) and compares
## it with the raw clip. Two passes (IK off, IK on) over the same terrain -> two strips.
## Metric: while a ball-of-foot is planted (world speed < 0.35 m/s) its height above the surface
## under it should be a constant ~3 cm; sink < -1 cm or hover > 8 cm is a fail.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const ProceduralRig := preload("res://scripts/actors/procedural_rig.gd")
const FootIK := preload("res://tools_qa/anim_tech/lib/foot_ik.gd")
const NAMES := ["off", "rig", "toe"]
const SPEED := 1.0            # Walk clip ground speed (CharacterAnimator.WALK_CLIP_SPEED)
const X_START := -2.6
const X_END := 9.2
const SNAPS := [-1.4, 0.35, 1.1, 2.0, 3.4, 4.7, 5.7, 6.7]


func run(d: Node3D, my: int) -> void:
	for mode in [0, 1, 2]:
		if not d.alive(my):
			return
		d._clear_stage()
		await _pass(d, my, mode)


func _pass(d: Node3D, my: int, mode: int) -> void:
	var use_ik := mode > 0
	# terrain along +X: flat, 5 stairs (17 cm), plateau, 22 degree ramp down, flat
	d.add_stairs(0.0, 0.0, 0.0, 3.0, 5, 0.17, 0.45)
	d.add_box(Vector3(3.2, 0.425, 0.0), Vector3(2.0, 0.85, 3.0), Vector3.ZERO, Color(0.80, 0.74, 0.62))
	d.add_ramp(4.2, 0.85, 6.4, 0.0, 0.0, 3.0)
	var c: Dictionary = d.spawn(Vector3(X_START, 0, 0), PI * 0.5)
	var actor: Node3D = c["actor"]
	var ap: AnimationPlayer = c["ap"]
	var sk: Skeleton3D = c["sk"]
	var clip := U.find_clip(ap, ["Walk", "Walking_A", "Walk_Formal"])
	ap.play(clip)
	var rig: Node = null
	if use_ik:
		rig = ProceduralRig.attach(c["model"], null, true) if mode == 1 else FootIK.attach_toe(c["model"], null, true)
	d.say("foot IK: %s   (%s)" % [["OFF (raw clip)", "ProceduralRig (ankle probe)", "anim_tech FootIK (ankle + toe probe)"][mode], clip])
	d.set_cam(Vector3(X_START, 1.0, 5.0), Vector3(X_START + 0.5, 0.7, 0.0), 38.0)
	var balls := [sk.find_bone("ball_l"), sk.find_bone("ball_r")]
	var snaps: Array = SNAPS.duplicate()
	var worst_sink := 0.0
	var worst_hover := 0.0
	var samples := 0
	var bad := 0
	var offs: Array[float] = []
	var sum_abs := 0.0
	var last_ball: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var y := 0.0
	var world := actor.get_world_3d()
	while actor.position.x < X_END:
		if not await d.wait(0.0, my):
			return
		await d.get_tree().process_frame
		var dt: float = d.get_process_delta_time()
		actor.position.x += SPEED * dt
		var gy := U.ground_y(world, actor.global_position, 0.0)
		y = lerpf(y, gy, 1.0 - exp(-14.0 * dt))
		actor.position.y = y
		d.cam.position.x = lerpf(d.cam.position.x, actor.position.x + 0.3, 1.0 - exp(-4.0 * dt))
		d.cam.look_at(Vector3(d.cam.position.x, 0.6 + y * 0.8, 0.0))
		if actor.position.x > -1.5:
			for i in 2:
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(balls[i]).origin
				var speed := p.distance_to(last_ball[i]) / maxf(dt, 0.0001)
				last_ball[i] = p
				if speed < 0.35:   # planted: it should sit on the surface
					var off := p.y - minf(U.ground_y(world, p + Vector3(0.04, 0, 0), 0.0), U.ground_y(world, p - Vector3(0.04, 0, 0), 0.0))
					if actor.position.x > 0.2 and actor.position.x < 6.6:
						offs.append(off)
						if off < -0.02:
							bad += 1
					worst_sink = minf(worst_sink, off)
					worst_hover = maxf(worst_hover, off)
					sum_abs += absf(off - 0.03)
					samples += 1
		if not snaps.is_empty() and actor.position.x >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	offs.sort()
	var n := maxi(offs.size(), 1)
	print("[foot_ik] mode=%s planted ball height above surface (m): p5 %.3f  p50 %.3f  p95 %.3f  (n=%d; target ~0.03) toe-in-surface >2cm: %d%% of stair+ramp samples" % [NAMES[mode], offs[int(n * 0.05)], offs[int(n * 0.5)], offs[mini(int(n * 0.95), n - 1)], offs.size(), 100 * bad / n])
	d.write_strip("foot_ik_" + NAMES[mode], 4)
	if rig:
		rig.queue_free()
