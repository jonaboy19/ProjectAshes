extends RefCounted
## (7) Synced locomotion blend space (lib/loco_tree.gd). Three runners on the same speed axis:
## naive (natural clip lengths), timeline-synced, timeline + foot-phase aligned. Speeds held for 3 s at
## the pure gaits (walk / jog / sprint) and at the mid points (walk-jog, jog-sprint).
## Metric: left-foot forward/back stride amplitude (m, skeleton space) read inside skeleton_updated, per speed.
## At a mid speed the amplitude should sit between the two pure gaits (interpolation); when the phases fight it
## collapses ("stride ratio" = measured / mean of the neighbours; ~1 good, < 0.75 the legs cancel).

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Loco := preload("res://tools_qa/anim_tech/lib/loco_tree.gd")
const NAMES := ["naive", "timeline", "timeline+phase"]
const SPEEDS := [1.4, 2.3, 3.2, 4.3, 5.4]     # walk, walk-jog, jog, jog-sprint, sprint


func run(d: Node3D, my: int) -> void:
	var xs := [-1.6, 0.0, 1.6]
	var chars: Array = []
	var locos: Array = []
	var taps: Array = []
	for k in 3:
		var c: Dictionary = d.spawn(Vector3(xs[k], 0, 0), 0.0)
		chars.append(c)
		locos.append(Loco.attach(c["model"], k))
		d.label3d(NAMES[k], Vector3(xs[k], 2.05, 0))
		var tap := {"z": 0.0}
		var sk: Skeleton3D = c["sk"]
		sk.skeleton_updated.connect(func() -> void:
			tap["z"] = sk.get_bone_global_pose(sk.find_bone("foot_l")).origin.z - sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.z)
		taps.append(tap)
	d.set_cam(Vector3(0.0, 1.5, 6.0), Vector3(0.0, 0.95, 0.0), 40.0)
	var amp := []           # [speed idx][mode] -> amplitude
	var pop := []           # largest frame-to-frame jump of the foot (m) while the speed is held
	for si in SPEEDS.size():
		d.say("speed %.1f m/s" % SPEEDS[si])
		for k in 3:
			locos[k].set_speed(SPEEDS[si])
		await d.wait(0.6, my)     # settle
		var lo := [INF, INF, INF]
		var hi := [-INF, -INF, -INF]
		var jump := [0.0, 0.0, 0.0]
		var prev := [NAN, NAN, NAN]
		var t := 0.0
		var snapped := false
		while t < 2.6:
			await d.get_tree().process_frame
			if not d.alive(my):
				return
			t += d.get_process_delta_time()
			for k in 3:
				var z: float = taps[k]["z"]
				lo[k] = minf(lo[k], z)
				hi[k] = maxf(hi[k], z)
				if not is_nan(prev[k]):
					jump[k] = maxf(jump[k], absf(z - prev[k]))
				prev[k] = z
			if not snapped and t > 0.4:
				snapped = true
				await d.snap()
		amp.append([hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]])
		pop.append(jump)
	var line := "[blendtree] left-foot stride amplitude (m) by speed [naive / timeline / timeline+phase]:"
	for si in SPEEDS.size():
		line += "  %.1f m/s: %.2f / %.2f / %.2f" % [SPEEDS[si], amp[si][0], amp[si][1], amp[si][2]]
	print(line)
	for mid: int in [1, 3]:
		var ratio := []
		for k in 3:
			ratio.append(amp[mid][k] / maxf((amp[mid - 1][k] + amp[mid + 1][k]) * 0.5, 0.001))
		print("[blendtree] stride ratio at %.1f m/s (measured / mean of the pure gaits either side): naive %.2f, timeline %.2f, timeline+phase %.2f" % [SPEEDS[mid], ratio[0], ratio[1], ratio[2]])
	print("[blendtree] cadence (cycles/s) at 1.4 / 3.2 / 5.4 m/s: %.2f / %.2f / %.2f; phase offsets (s) walk / jog / sprint: %.2f / %.2f / %.2f" % [locos[2].cadence(1.4), locos[2].cadence(3.2), locos[2].cadence(5.4), locos[2].offsets[0], locos[2].offsets[1], locos[2].offsets[2]])
	d.write_strip("blendtree", 5)
