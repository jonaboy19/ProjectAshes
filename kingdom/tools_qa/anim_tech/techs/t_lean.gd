extends RefCounted
## (6) Velocity lean + spine aim twist (lib/lean_aim.gd). Two runners weave along a slalom towards the camera;
## the right one has LeanAim. Phase 1: lean only (tips into the turns). Phase 2: also aims its torso at an orbiting
## target while the legs keep running. Left = plain clip. Metrics: peak spine_03 roll vs the twin, and how well the
## chest points at the target (angle between chest forward and the target direction), twin vs aimed.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const LeanAim := preload("res://tools_qa/anim_tech/lib/lean_aim.gd")
const RADIUS := 1.3
const OMEGA := 1.9            # rad/s -> 2.5 m/s
const Z0 := 0.0


func _x(z: float, x0: float) -> float:
	return x0 + 0.9 * sin(z * 1.35)


func run(d: Node3D, my: int) -> void:
	var xs := [-1.9, 1.9]
	var a: Dictionary = d.spawn(Vector3(xs[0], 0, 0), 0.0)
	var b: Dictionary = d.spawn(Vector3(xs[1], 0, 0), 0.0)
	var run_clip := U.find_clip(a["ap"], ["Running_A", "Jog_Fwd", "Sprint"])
	a["ap"].play(run_clip)
	b["ap"].play(run_clip)
	var target := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	target.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.25, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.2, 0.1)
	target.material_override = mat
	d.stage.add_child(target)
	var m: SkeletonModifier3D = LeanAim.attach(b["model"], b["actor"])
	m.aim_weight = 0.0
	m.set("aim_target", target)
	d.label3d("plain run", Vector3(-1.9, 2.4, -1.3))
	var lab: Label3D = d.label3d("LeanAim", Vector3(1.9, 2.4, -1.3))
	d.set_cam(Vector3(0.0, 2.6, 6.4), Vector3(0.0, 0.9, -0.6), 40.0)
	var ska: Skeleton3D = a["sk"]
	var skb: Skeleton3D = b["sk"]
	var pa := {}
	var pb := {}
	var grab := func(sk: Skeleton3D, into: Dictionary) -> void:
		var q := sk.get_bone_global_pose(sk.find_bone("spine_03")).basis
		into["roll"] = q * Vector3.UP
		into["fwd"] = q * Vector3.BACK
	ska.skeleton_updated.connect(func() -> void: grab.call(ska, pa))
	skb.skeleton_updated.connect(func() -> void: grab.call(skb, pb))
	var roll_a := 0.0
	var roll_b := 0.0
	var aim_err_a := 0.0
	var aim_err_b := 0.0
	var n_aim := 0
	var snaps: Array = [0.5, 1.1, 1.7, 2.3, 2.9, 3.5, 4.1, 4.7, 5.3, 5.9]
	var t := 0.0
	var z := Z0
	var total := 7.0
	var phase2 := false
	while t < total:
		await d.get_tree().process_frame
		if not d.alive(my):
			return
		var dt: float = d.get_process_delta_time()
		t += dt
		for k in 2:
			var act: Node3D = (a if k == 0 else b)["actor"]
			var ang := t * OMEGA * (1.0 if k == 1 else 1.0)
			var c := Vector3(xs[k], 0, 0)
			act.position = c + Vector3(sin(ang), 0, cos(ang)) * RADIUS - Vector3(0, 0, RADIUS)
			act.rotation.y = ang + PI * 0.5      # tangent of the circle
		phase2 = t > total * 0.5
		m.aim_weight = 1.0 if phase2 else 0.0
		var actor_b: Node3D = b["actor"]
		var tgt_ang := 1.3 * sin(t * 1.4)
		target.position = actor_b.position + Basis(Vector3.UP, actor_b.rotation.y) * Vector3(sin(tgt_ang) * 2.2, 1.5, cos(tgt_ang) * 2.2)
		lab.text = "LeanAim + aim twist" if phase2 else "LeanAim (lean only)"
		if not pa.is_empty() and not pb.is_empty():
			roll_a = maxf(roll_a, absf(pa["roll"].x))
			roll_b = maxf(roll_b, absf(pb["roll"].x))
			if phase2:
				var tw_a := rad_to_deg(atan2((pa["fwd"] as Vector3).x, (pa["fwd"] as Vector3).z))
				var tw_b := rad_to_deg(atan2((pb["fwd"] as Vector3).x, (pb["fwd"] as Vector3).z))
				var want := rad_to_deg(clampf(tgt_ang, -deg_to_rad(m.aim_limit), deg_to_rad(m.aim_limit)))
				aim_err_a += absf(tw_a - tw_a)
				aim_err_b += absf((tw_b - tw_a) - want * 0.75)
				n_aim += 1
		if not snaps.is_empty() and t >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	print("[lean] peak spine_03 sideways tilt (sin roll): plain %.3f, LeanAim %.3f; phase 2 mean error of the extra chest twist vs 75%% of the wanted angle (spine share): aimed %.1f deg (plain would be ~mean |wanted| = 53 deg)" % [roll_a, roll_b, aim_err_b / maxf(n_aim, 1)])
	d.write_strip("lean", 5)
