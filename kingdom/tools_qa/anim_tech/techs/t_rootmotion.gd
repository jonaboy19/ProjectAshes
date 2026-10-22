extends RefCounted
## (8) Root-motion attacks. The stock clips are in place (the `root` position track is disabled); here the track is
## re-enabled on a per-player copy, AnimationMixer.root_motion_track points at it, and the travel the player reports
## each frame (get_root_motion_position) moves the actor. Left attacker: in-place clip (stands where it started);
## right attacker: root motion (closes the gap). Three lunging clips, one dummy each, placed just out of reach of
## the in-place version. Metric per clip: the gap between the attacker's body and the dummy at the hit frame (the
## frame the striking limb is fastest), in place vs root motion, and the total distance travelled.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
## [label, source ("" = stock UAL clip, else a GLB under animations_free), clip, striking bone]
const ATTACKS := [
	["Karate_Oi_Zuki", "", "Karate_Oi_Zuki", "hand_r"],
	["MA_Kick_Jump_R", "kicks/UAL_Free_Kicks.glb", "MA_Kick_Jump_R", "foot_r"],
	["MA_Kick_JumpHigh_A", "kicks/UAL_Free_Kicks.glb", "MA_Kick_JumpHigh_A", "foot_r"],
]


func run(d: Node3D, my: int) -> void:
	var results := []
	for atk: Array in ATTACKS:
		if not d.alive(my):
			return
		d._clear_stage()
		await _one(d, my, atk, results)
	for r: Dictionary in results:
		print("[rootmotion] %s: travel %.2f m over %.2f s, hit at %.2f s (limb peak %.1f m/s); body-to-dummy gap at the hit frame: in place %.2f m, root motion %.2f m" % [r["clip"], r["travel"], r["len"], r["hit"], r["speed"], r["gap_in"], r["gap_rm"]])
	d.write_strip("rootmotion", 4)


func _one(d: Node3D, my: int, atk: Array, results: Array) -> void:
	var xs := [-1.5, 1.5]
	var cs: Array = []
	for k in 2:
		cs.append(d.spawn(Vector3(xs[k], 0, -1.8), 0.0))
	# clip on both players; the second gets root motion
	var names: Array[String] = []
	for k in 2:
		var ap: AnimationPlayer = cs[k]["ap"]
		var sk: Skeleton3D = cs[k]["sk"]
		if atk[1] == "":
			names.append(U.own_copy(ap, atk[2], k == 1))
		else:
			names.append(U.import_clips(ap, sk, U.FREE_DIR + atk[1], [atk[2]], k == 1)[0])
	var ap0: AnimationPlayer = cs[0]["ap"]
	var ap1: AnimationPlayer = cs[1]["ap"]
	var anim1 := ap1.get_animation(names[1])
	var travel := U.root_at(anim1, anim1.length)
	U.enable_root_motion(ap1, cs[1]["sk"], anim1)
	# hit frame = fastest striking limb (in place skeleton space)
	var path := U.sample_bone(ap0, cs[0]["sk"], names[0], atk[3])
	var pk := U.peak_speed(path)
	var hit_t: float = pk["time"]
	var reach := (path[int(hit_t * 30.0)] - path[0]).z   # how far the limb goes past its start (skeleton z)
	var dummy_z := -1.8 + maxf(reach, 0.3) + travel.z * 0.75 + 0.35
	for k in 2:
		var dm := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.28
		cm.height = 1.7
		dm.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.3, 0.25)
		dm.material_override = mat
		d.stage.add_child(dm)
		dm.position = Vector3(xs[k], 0.85, dummy_z)
	d.label3d("%s  in place" % atk[0], Vector3(xs[0], 2.3, -1.8))
	d.label3d("root motion (+%.2f m)" % travel.z, Vector3(xs[1], 2.3, -1.8))
	d.set_cam(Vector3(2.2, 2.3, -1.8 - 4.2), Vector3(0.0, 0.9, (dummy_z - 1.8) * 0.5 + 0.2), 50.0)
	d.say(atk[0])
	await d.wait(0.3, my)
	var act1: Node3D = cs[1]["actor"]
	var start_z := act1.position.z
	ap0.play(names[0])
	ap1.play(names[1])
	var t := 0.0
	var snaps := [0.05, hit_t * 0.5, hit_t, minf(hit_t + 0.25, anim1.length - 0.05)]
	var gap_rm := -1.0
	var gap_in := -1.0
	var len := anim1.length
	while t < len + 0.05:
		await d.get_tree().process_frame
		if not d.alive(my):
			return
		var dt: float = d.get_process_delta_time()
		t += dt
		U.apply_root_motion(ap1, cs[1]["sk"], act1)
		if gap_rm < 0.0 and t >= hit_t:
			gap_rm = dummy_z - (cs[1]["actor"] as Node3D).position.z
			gap_in = dummy_z - (cs[0]["actor"] as Node3D).position.z
		if not snaps.is_empty() and t >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	results.append({"clip": atk[0], "travel": act1.position.z - start_z, "len": len, "hit": hit_t, "speed": pk["speed"], "gap_in": gap_in, "gap_rm": gap_rm})
