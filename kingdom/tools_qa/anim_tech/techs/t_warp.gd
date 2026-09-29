extends RefCounted
## (10) Motion warping (lib/motion_warp.gd). The same jump-kick lunge (MA_Kick_Jump_R, 1.19 m of root travel) against
## three targets at 1.0 m / 2.4 m / 3.4 m and 0 / 35 / -50 degrees off the facing. Left: raw root motion (goes 1.19 m
## straight ahead, misses). Right: warped (turns to the target, stretches or squashes the travel to land at the stop
## distance). Metric: end distance to the stop point and end facing error, raw vs warped.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const MotionWarp := preload("res://tools_qa/anim_tech/lib/motion_warp.gd")
const CASES := [[1.0, 0.0], [2.4, 35.0], [3.4, -50.0]]     # [distance m, angle deg from +Z]
const STOP := 0.85
const CLIP := "MA_Kick_Jump_R"


func run(d: Node3D, my: int) -> void:
	var rows := []
	for c: Array in CASES:
		if not d.alive(my):
			return
		d._clear_stage()
		rows.append(await _case(d, my, c))
	for r: Dictionary in rows:
		print("[warp] target %.1f m at %.0f deg: raw ends %.2f m from the stop point (facing error %.0f deg); warped ends %.2f m (facing error %.0f deg), travel scale used %.2f..%.2f" % [r["dist"], r["ang"], r["raw_err"], r["raw_yaw"], r["warp_err"], r["warp_yaw"], r["smin"], r["smax"]])
	d.write_strip("warp", 4)


func _case(d: Node3D, my: int, c: Array) -> Dictionary:
	var xs := [-2.0, 2.0]
	var cs: Array = []
	for k in 2:
		cs.append(d.spawn(Vector3(xs[k], 0, 0), 0.0))
	var names: Array[String] = []
	for k in 2:
		names.append(U.import_clips(cs[k]["ap"], cs[k]["sk"], U.FREE_DIR + "kicks/UAL_Free_Kicks.glb", [CLIP], true)[0])
	var ap0: AnimationPlayer = cs[0]["ap"]
	var ap1: AnimationPlayer = cs[1]["ap"]
	var anim: Animation = ap0.get_animation(names[0])
	U.enable_root_motion(ap0, cs[0]["sk"], anim)
	U.enable_root_motion(ap1, cs[1]["sk"], ap1.get_animation(names[1]))
	var ang := deg_to_rad(c[1])
	var targets: Array[Vector3] = []
	for k in 2:
		var tp: Vector3 = Vector3(xs[k], 0, 0) + Vector3(sin(ang), 0, cos(ang)) * float(c[0])
		targets.append(tp)
		var dm := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.28
		cm.height = 1.7
		dm.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.3, 0.25)
		dm.material_override = mat
		d.stage.add_child(dm)
		dm.position = tp + Vector3(0, 0.85, 0)
	d.label3d("raw root motion", Vector3(xs[0], 2.4, 0))
	d.label3d("warped", Vector3(xs[1], 2.4, 0))
	d.set_cam(Vector3(0.0, 4.6, -3.2), Vector3(0.0, 0.6, 1.4), 55.0)
	d.say("target %.1f m at %.0f deg" % [c[0], c[1]])
	await d.wait(0.3, my)
	var w := MotionWarp.new()
	w.begin(ap1, cs[1]["sk"], cs[1]["actor"], names[1], targets[1], STOP)
	ap0.play(names[0])
	var act0: Node3D = cs[0]["actor"]
	var t := 0.0
	var smin := 9.0
	var smax := 0.0
	var snaps := [0.02, 0.35, 0.7, anim.length - 0.05]
	while t < anim.length + 0.05:
		await d.get_tree().process_frame
		if not d.alive(my):
			return {}
		var dt: float = d.get_process_delta_time()
		t += dt
		U.apply_root_motion(ap0, cs[0]["sk"], act0)
		w.step(dt)
		if t > w.window().x and t < w.window().y:
			smin = minf(smin, w.scale_used)
			smax = maxf(smax, w.scale_used)
		if not snaps.is_empty() and t >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	var res := {"dist": c[0], "ang": c[1], "smin": smin, "smax": smax}
	for k in 2:
		var act: Node3D = cs[k]["actor"]
		var to := targets[k] - act.position
		to.y = 0.0
		var stop_pt := targets[k] - to.normalized() * STOP
		var err := (stop_pt - act.position).length()
		var yaw_err := rad_to_deg(absf(angle_difference(act.rotation.y, atan2(to.x, to.z))))
		res["raw_err" if k == 0 else "warp_err"] = err
		res["raw_yaw" if k == 0 else "warp_yaw"] = yaw_err
	return res
