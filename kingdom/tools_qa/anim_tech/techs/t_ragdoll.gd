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


func _max_spread(rd: Node) -> float:
	var hips: PhysicalBone3D = rd.get("_hips")
	var m := 0.0
	if is_instance_valid(hips):
		for b: PhysicalBone3D in rd.get("_bodies"):
			m = maxf(m, (b.global_position - hips.global_position).length())
	return m

## The simulator writes its result through the skeleton modifier stack, which get_bone_global_pose() does
## not report, so measure on the PhysicalBone3D bodies: largest offset (m, hips-relative) between a
## simulated body and the same bone on the un-hit twin's skeleton (same rig, same clip, same yaw).
func _pose_dev(rd: Node, twin: Skeleton3D) -> float:
	var hips: PhysicalBone3D = rd.get("_hips")
	if not is_instance_valid(hips):
		return 0.0
	var oa := twin.global_transform * twin.get_bone_global_pose(twin.find_bone(hips.bone_name)).origin
	var m := 0.0
	for b: PhysicalBone3D in rd.get("_bodies"):
		var ta := twin.global_transform * twin.get_bone_global_pose(twin.find_bone(b.bone_name)).origin
		m = maxf(m, ((ta - oa) - (b.global_position - hips.global_position)).length())
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
	var dev70 := 0.0       # max bone offset (pelvis space) vs the un-hit twin in the first 70 ms
	var dev_peak := 0.0
	var jump := 0.0        # largest frame-to-frame change of the deviation (a snap shows here)
	var prev_dv := 0.0
	for tt: float in times:
		while (Time.get_ticks_msec() - t0) / 1000.0 < tt:
			await d.get_tree().process_frame
			if not d.alive(my):
				return
			spread = maxf(spread, _max_spread(rd))
			var dv := _pose_dev(rd, a["sk"])
			jump = maxf(jump, absf(dv - prev_dv))
			prev_dv = dv
			dev_peak = maxf(dev_peak, dv)
			if (Time.get_ticks_msec() - t0) / 1000.0 < 0.07:
				dev70 = maxf(dev70, dv)
		await d.snap()
	print("[ragdoll] partial hit_react ok=%s max body distance from hips %.2f m (explosion check < 1.3); pose deviation vs unhit twin: first 70 ms max %.3f m, peak %.3f m, largest single-frame change %.3f m" % [ok, spread, dev70, dev_peak, jump])
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
	var prev_p := Vector3.INF
	var jitter := 0.0
	var jsum := 0.0
	var jn := 0
	var hy := 0.0
	for tt: float in [0.0, 0.15, 0.3, 0.5, 0.8, 1.2, 2.0, 3.6]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < tt:
			await d.get_tree().process_frame
			if not d.alive(my):
				return
			spread = maxf(spread, _max_spread(rd))
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			if not is_instance_valid(rd.get("_hips")):
				continue
			hy = (rd.get("_hips") as PhysicalBone3D).global_position.y
			if el >= 2.0 and el <= 2.9:      # settled window (the 3.0 s bake teleports the root, so stop before it)
				var p: Vector3 = (rd.get("_hips") as PhysicalBone3D).global_position
				if prev_p != Vector3.INF:
					var st := p.distance_to(prev_p)
					jitter = maxf(jitter, st)
					jsum += st
					jn += 1
				prev_p = p
		await d.snap()
	print("[ragdoll] full die ok=%s max spread %.2f m, pelvis rest height %.2f m, pelvis per-frame movement over 2.0-2.9 s: max %.4f m, mean %.4f m (%d frames)" % [ok, spread, hy, jitter, jsum / maxf(jn, 1), jn])
	d.write_strip("ragdoll_full", 4)
