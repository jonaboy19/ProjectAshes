extends RefCounted
## (4) Ragdoll. Pass 1: PARTIAL upper-body ragdoll hit reaction (lib/partial_ragdoll.gd, influence
## tween, legs stay on the animation). Pass 2: FULL ragdoll death (scripts/actors/ragdoll.gd die()).
## Numeric checks printed: max distance of any bone from the hips (explosion), hips height at rest.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const PartialRagdoll := preload("res://tools_qa/anim_tech/lib/partial_ragdoll.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")


func run(d: Node3D, my: int) -> void:
	await _partial(d, my)
	if not d.alive(my):
		return
	d._clear_stage()
	await _full(d, my)


func _max_spread(sk: Skeleton3D) -> float:
	var h := sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
	var m := 0.0
	for i in sk.get_bone_count():
		m = maxf(m, (sk.get_bone_global_pose(i).origin - h).length())
	return m


func _partial(d: Node3D, my: int) -> void:
	# two characters take the same hit: left plain clip, right partial ragdoll
	var a: Dictionary = d.spawn(Vector3(-1.0, 0, 0), 0.0)
	var b: Dictionary = d.spawn(Vector3(1.0, 0, 0), 0.0)
	var idle := U.find_clip(a["ap"], ["Fighting_Idle", "Idle"])
	a["ap"].play(idle)
	b["ap"].play(idle)
	var rd: Node = PartialRagdoll.attach_partial(b["actor"], b["model"], [b["ap"]])
	d.label3d("no reaction", Vector3(-1.0, 2.05, 0))
	d.label3d("partial ragdoll", Vector3(1.0, 2.05, 0))
	d.set_cam(Vector3(-1.8, 1.5, 4.6), Vector3(0.0, 1.0, 0.0), 38.0)
	await d.get_tree().create_timer(0.8).timeout
	var times := [0.0, 0.07, 0.14, 0.24, 0.4, 0.7, 1.0, 1.4]
	var t0 := Time.get_ticks_msec()
	var ok: bool = await rd.hit_react(Vector3(-0.6, 0, -1.0), 3.0)
	d.say("hit from the front-right; hit_react -> %s" % ok)
	var spread := 0.0
	for tt: float in times:
		while (Time.get_ticks_msec() - t0) / 1000.0 < tt:
			await d.get_tree().process_frame
			if not d.alive(my):
				return
			spread = maxf(spread, _max_spread(b["sk"]))
		await d.snap()
	print("[ragdoll] partial hit_react ok=%s max bone distance from pelvis %.2f m (explosion check < 1.3)" % [ok, spread])
	d.write_strip("ragdoll_partial", 4)


func _full(d: Node3D, my: int) -> void:
	var a: Dictionary = d.spawn(Vector3(0, 0, 0), 0.0)
	a["ap"].play(U.find_clip(a["ap"], ["Fighting_Idle", "Idle"]))
	var rd: Node = Ragdoll.attach(a["actor"], a["model"], [a["ap"]])
	d.set_cam(Vector3(-2.2, 1.5, 4.4), Vector3(0.3, 0.7, 0.0), 42.0)
	await d.get_tree().create_timer(0.7).timeout
	var t0 := Time.get_ticks_msec()
	var ok: bool = rd.die(Vector3(2.0, 0, -5.0), Vector3(-1.5, 1.1, 3.0))
	d.say("death: Ragdoll.die() -> %s" % ok)
	var sk: Skeleton3D = a["sk"]
	var spread := 0.0
	var prev_y := INF
	var jitter := 0.0
	for tt: float in [0.0, 0.15, 0.3, 0.5, 0.8, 1.2, 2.0, 3.6]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < tt:
			await d.get_tree().process_frame
			if not d.alive(my):
				return
			spread = maxf(spread, _max_spread(sk))
			if tt > 2.0:
				var y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin).y
				if prev_y != INF:
					jitter = maxf(jitter, absf(y - prev_y))
				prev_y = y
		await d.snap()
	var hy := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin).y
	print("[ragdoll] full die ok=%s max spread %.2f m, pelvis rest height %.2f m, max per-frame pelvis jitter after 2 s %.4f m" % [ok, spread, hy, jitter])
	d.write_strip("ragdoll_full", 4)
