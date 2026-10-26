extends SceneTree
## Measures ContactIK (scripts/living_world/contact_ik.gd) on real villager bodies: for each look x clip, plays the clip on a
## flat floor with and without the modifier and reports the lowest contact joint (knees/ankles/balls minus skin radius,
## wrists/finger tips) relative to the floor: float (> +2 cm is visible) and penetration (< -2 cm), plus ms per NPC.
##   godot --headless --path kingdom -s res://tools_qa/anim_states/contact_ik_probe.gd -- --clips=A,B --looks=villager_man_a
## Joint based (skin radii from ContactIK), not vertex based: a dress hem is not a body contact.

var clips := PackedStringArray(["Life_Mx_Pull_Plant", "Life_Mx_Pick_Ground", "Life_Mx_Pray_Kneel"])
var looks := PackedStringArray(["villager_man_a", "villager_woman_a", "villager_man_b", "villager_woman_b"])


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = PackedStringArray(a.substr(8).split(","))
		elif a.begins_with("--looks="):
			looks = PackedStringArray(a.substr(8).split(","))
	_run.call_deferred()


func _contacts(sk: Skeleton3D) -> Vector2:
	# x = lowest leg contact above floor (m), y = lowest hand contact above floor (m)
	var leg := INF
	var hand := INF
	var xf := sk.global_transform
	for s in ["l", "r"]:
		leg = minf(leg, (xf * sk.get_bone_global_pose(sk.find_bone("calf_" + s)).origin).y - ContactIK.R_KNEE)
		leg = minf(leg, (xf * sk.get_bone_global_pose(sk.find_bone("foot_" + s)).origin).y - ContactIK.R_ANKLE)
		leg = minf(leg, (xf * sk.get_bone_global_pose(sk.find_bone("ball_" + s)).origin).y - ContactIK.R_BALL)
		hand = minf(hand, (xf * sk.get_bone_global_pose(sk.find_bone("hand_" + s)).origin).y - ContactIK.R_WRIST)
		for f in ["thumb", "index", "middle", "ring", "pinky"]:
			var i := sk.find_bone("%s_03_%s" % [f, s])
			if i >= 0:
				hand = minf(hand, (xf * sk.get_bone_global_pose(i).origin).y - ContactIK.R_TIP)
	return Vector2(leg, hand)


func _run() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.5, 4)
	cam.current = true
	print("CONTACT_IK_PROBE look clip | without: leg_float hand_min | with: leg_float hand_min | ms/npc")
	for look in looks:
		for clip in clips:
			var res := []
			for use_ik in [false, true]:
				var m := Assets.mh_character(look, 1.7)
				root.add_child(m)
				var ap := Assets.animation_player(m)
				LifeLibrary.install(ap)
				if not ap.has_animation(clip):
					print("MISSING ", clip)
					m.queue_free()
					break
				var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
				var ik: ContactIK = null
				if use_ik:
					ik = ContactIK.new()
					sk.add_child(ik)
					ik.ground_y = 0.0
					ik.hand_contact = bool(LifeLibrary.info(clip).get("hand_contact", false))
					ik.set_process(false)      # flat floor: no ground probe / range release in the probe
				ap.play(clip)
				var lo := Vector2(INF, INF)
				var legs := PackedFloat32Array()
				var hands := PackedFloat32Array()
				var hi := Vector2(-INF, -INF)
				var a := ap.get_animation(clip)
				ContactIK.cost_usec = 0
				ContactIK.cost_calls = 0
				var n := int(a.length * 30.0)
				var got := [Vector2(INF, INF)]
				var cb := func() -> void: got[0] = _contacts(sk)      # read the pose after the modifiers ran
				var sig: Signal = ik.modification_processed if ik != null else sk.skeleton_updated
				sig.connect(cb)
				for f in n:
					ap.seek(float(f) / 30.0, true)
					await process_frame
					var c: Vector2 = got[0]
					legs.append(c.x)
					hands.append(c.y)
					lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
					hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
				sig.disconnect(cb)
				legs.sort()
				hands.sort()
				var k := legs.size()
				# p5 / p50 of the lowest leg and hand contact over the frames (contact clips: ~0 means touching)
				res.append([Vector2(legs[int(k * 0.05)], hands[int(k * 0.05)]), Vector2(legs[k / 2], hands[k / 2]), (float(ContactIK.cost_usec) / maxf(ContactIK.cost_calls, 1)) / 1000.0])
				m.queue_free()
				await process_frame
			if res.size() == 2:
				# leg float: the lowest leg contact over the clip (kneeling clips: knees down); hand: lowest hand contact
				print("CIK %s %s | off: leg p5 %+.1f p50 %+.1f hand p5 %+.1f | on: leg p5 %+.1f p50 %+.1f hand p5 %+.1f cm | %.3f ms" % [look, clip,
					res[0][0].x * 100.0, res[0][1].x * 100.0, res[0][0].y * 100.0, res[1][0].x * 100.0, res[1][1].x * 100.0, res[1][0].y * 100.0, res[1][2]])
	quit()
