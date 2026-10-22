extends RefCounted
## (5) Additive directional hit flinch (lib/flinch.gd). Two characters walk side by side; the right one has the
## Flinch tree. Both are hit from the front, the left, the back and the right (one hit per ~1 s). The base walk never
## stops (feet keep stepping), only the upper body recoils. Left = plain Walk (no reaction).
## Numeric check (read inside skeleton_updated, the only place modifier / tree output is visible): the chest offset
## (pelvis relative) vs the un-hit twin must deviate, the foot offset must stay ~0 (legs are filtered out).

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Flinch := preload("res://tools_qa/anim_tech/lib/flinch.gd")
const HITS := [[Vector2(0, 1), "front"], [Vector2(-1, 0), "left"], [Vector2(0, -1), "back"], [Vector2(1, 0), "right"]]


func run(d: Node3D, my: int) -> void:
	var a: Dictionary = d.spawn(Vector3(-0.9, 0, 0), 0.0)
	var b: Dictionary = d.spawn(Vector3(0.9, 0, 0), 0.0)
	var walk := U.find_clip(a["ap"], ["Walk", "Walking_A"])

	var f0: RefCounted = Flinch.attach(a["model"], walk)   # same tree, never hit: phase-locked reference
	var f: RefCounted = Flinch.attach(b["model"], walk)
	d.label3d("plain Walk", Vector3(-0.9, 2.05, 0))
	d.label3d("Walk + additive flinch", Vector3(0.9, 2.05, 0))
	d.set_cam(Vector3(0.0, 1.5, 5.2), Vector3(0.0, 1.0, 0.0), 36.0)
	var skb: Skeleton3D = b["sk"]
	var ska: Skeleton3D = a["sk"]
	var tap := {"leg": 0.0, "chest": 0.0}
	var pose_a := {}
	var pose_b := {}
	var grab := func(sk: Skeleton3D, into: Dictionary) -> void:
		into["pelvis"] = sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
		into["chest"] = sk.get_bone_global_pose(sk.find_bone("spine_03")).origin
		into["foot"] = sk.get_bone_global_pose(sk.find_bone("foot_l")).origin
	ska.skeleton_updated.connect(func() -> void: grab.call(ska, pose_a))
	skb.skeleton_updated.connect(func() -> void: grab.call(skb, pose_b))
	d.get_tree().process_frame.connect(func() -> void:
		if pose_a.is_empty() or pose_b.is_empty():
			return
		tap["chest"] = maxf(tap["chest"], ((pose_b["chest"] - pose_b["pelvis"]) - (pose_a["chest"] - pose_a["pelvis"])).length())
		tap["leg"] = maxf(tap["leg"], ((pose_b["foot"] - pose_b["pelvis"]) - (pose_a["foot"] - pose_a["pelvis"])).length()))
	await d.wait(0.5, my)
	for h: Array in HITS:
		if not d.alive(my):
			return
		d.say("hit from the %s" % h[1])
		f.hit(h[0], 1.6)
		var t := 0.0
		for snap_at: float in [0.0, 0.07, 0.16, 0.3]:
			await d.wait(snap_at - t, my)
			t = snap_at
			await d.snap()
		await d.wait(0.6, my)
	print("[flinch] max chest offset vs un-hit twin %.3f m, max foot offset %.3f m (legs keep walking with the twin), flinching at end: %s" % [tap["chest"], tap["leg"], f.is_flinching()])
	d.write_strip("flinch", 4)
	f.tree.queue_free()
	f0.tree.queue_free()
