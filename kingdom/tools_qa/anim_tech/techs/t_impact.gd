extends RefCounted
## (9) Hitstop + camera shake (lib/hitstop.gd, lib/camera_shake.gd) on a sword hit with an additive flinch on the
## victim. Three runs of the same swing: (1) plain, (2) local hitstop 0.08 s (attacker + victim animation frozen, the
## world keeps running), (3) hitstop + shake (trauma 0.55 kicked along screen x). The hit frame is the frame the
## attacking hand is fastest (measured from the clip, not guessed). Metrics: measured freeze time of the attacker's
## clip after the hit, peak camera offset.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Flinch := preload("res://tools_qa/anim_tech/lib/flinch.gd")
const CLIPS := ["Sword_Regular_A", "1H_Melee_Attack_Chop", "Sword_Attack"]
const MODES := ["plain", "hitstop 0.08 s", "hitstop + shake"]


func run(d: Node3D, my: int) -> void:
	var lines := []
	for m in 3:
		if not d.alive(my):
			return
		d._clear_stage()
		lines.append(await _run_mode(d, my, m))
	for l: String in lines:
		print("[impact] ", l)
	d.write_strip("impact", 5)


func _run_mode(d: Node3D, my: int, mode: int) -> String:
	var a: Dictionary = d.spawn(Vector3(0, 0, -0.85), 0.0)
	var v: Dictionary = d.spawn(Vector3(0, 0, 0.35), PI)
	var clip := U.find_clip(a["ap"], CLIPS)
	var ap: AnimationPlayer = a["ap"]
	var idle := U.find_clip(v["ap"], ["Idle", "Sword_Idle"])
	var f: RefCounted = Flinch.attach(v["model"], idle)
	var path := U.sample_bone(ap, a["sk"], clip, "hand_r")
	var pk := U.peak_speed(path)
	var hit_t: float = pk["time"]
	d.label3d(MODES[mode], Vector3(0, 2.35, 0))
	d.set_cam(Vector3(4.2, 1.5, -0.25), Vector3(0.0, 1.0, -0.25), 36.0)
	d.say("%s  (%s, hit frame %.2f s = frame %d, hand %.1f m/s)" % [MODES[mode], clip, hit_t, int(round(hit_t * 30.0)), pk["speed"]])
	await d.wait(0.4, my)
	ap.play(clip)
	var triggered := false
	var t_trig := 0
	var pos_at_trig := 0.0
	var resumed_ms := -1
	var shake_peak := 0.0
	var snaps := [-1.0, 0.0, 0.04, 0.12, 0.30]     # relative to the trigger
	var t0 := Time.get_ticks_msec()
	var trig_frame := 0
	while ap.is_playing() or (triggered and Time.get_ticks_msec() - t_trig < 700):
		await d.get_tree().process_frame
		if not d.alive(my):
			return ""
		var pos := ap.current_animation_position
		if not triggered and pos >= hit_t:
			triggered = true
			t_trig = Time.get_ticks_msec()
			pos_at_trig = pos
			f.hit(Vector2(0, 1), 1.5)
			if mode >= 1:
				d.hitstop.freeze_local([ap, f.tree], 0.08)
			if mode >= 2:
				d.shake.add_trauma(0.55, Vector2(1, 0))
		if triggered:
			var rel := (Time.get_ticks_msec() - t_trig) / 1000.0
			if resumed_ms < 0 and pos > pos_at_trig + 0.004:
				resumed_ms = Time.get_ticks_msec() - t_trig
			shake_peak = maxf(shake_peak, Vector2(d.cam.h_offset, d.cam.v_offset).length())
			if not snaps.is_empty() and rel >= snaps[0]:
				snaps.pop_front()
				await d.snap()
		elif not snaps.is_empty() and snaps[0] < 0.0 and pos >= hit_t - 0.07:
			snaps.pop_front()
			await d.snap()
		if not ap.is_playing() and not triggered:
			break
	return "%s: clip %s hit at %.2f s (frame %d); attacker clip frozen for %d ms after the hit; peak camera offset %.3f m" % [MODES[mode], clip, hit_t, int(round(hit_t * 30.0)), maxi(resumed_ms, 0), shake_peak]
