extends Node3D
## Micro-probe: CPU cost of animating 40 villager rigs at full and reduced rates.
## process_ms  = main-thread time from the first to the last _process of the frame (includes AnimationMixer internal
##               processing and our stepping script); rest_ms = the remainder of the frame on the main thread
##               (deferred skeleton updates, render setup, sync); render_cpu / gpu from the RenderingServer.
var models: Array = []
var anims: Array = []
var sks: Array = []
var acc: Array = []
var mode := ""
var frame := 0
var t_start := 0
var t_end := 0
var samples: Array = []

class EndMark extends Node:
	var probe: Node
	func _process(_d: float) -> void:
		probe.t_end = Time.get_ticks_usec()


func _ready() -> void:
	process_priority = -100000
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var em := EndMark.new()
	em.probe = self
	em.process_priority = 100000
	add_child(em)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 3, 14)
	for i in 40:
		var m := Assets.mh_character("villager_man_a", 1.75, [], false)
		add_child(m); m.position = Vector3(-6 + (i % 8) * 1.7, 0, -(i / 8) * 1.7)
		var a := Assets.animation_player(m); a.play(["Idle", "Walk", "Farm_Harvest", "TreeChopping"][i % 4])
		models.append(m); anims.append(a); acc.append(0.0)
		sks.append(m.find_children("*", "Skeleton3D", true, false)[0])
	for f in 60: await get_tree().process_frame
	var modes := ["idle_every_frame", "frozen", "active_pulse_3", "cb_pulse_3", "pmode_every_3"]
	var best := {}
	for rep in 3:
		for m: String in modes:
			_set_mode(m)
			for f in 20: await get_tree().process_frame
			var p0 := (anims[1] as AnimationPlayer).current_animation_position
			var tt0 := Time.get_ticks_usec()
			var r := await _measure(200)
			var dp := fposmod((anims[1] as AnimationPlayer).current_animation_position - p0, (anims[1] as AnimationPlayer).current_animation_length)
			r["rate"] = dp
			if not best.has(m) or r["frame"] < best[m]["frame"]:
				best[m] = r
	for m: String in modes:
		var r: Dictionary = best[m]
		var f: Dictionary = best["frozen"]
		print("PROBE %-18s pos-advance %.2f  frame %.2f  process %.3f (%+.1f us/rig)  rest %.3f (%+.1f us/rig)  render_cpu %.3f  gpu %.3f" % [m, r["rate"], r["frame"],
			r["proc"], (r["proc"] - f["proc"]) * 1000.0 / 40.0, r["rest"], (r["rest"] - f["rest"]) * 1000.0 / 40.0, r["rcpu"], r["gpu"]])
	get_tree().quit()


func _set_mode(m: String) -> void:
	mode = m
	for a: AnimationPlayer in anims:
		a.process_mode = Node.PROCESS_MODE_INHERIT
		a.active = true
		a.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if m in ["idle_every_frame", "pmode_every_3", "active_every_3", "cbmode_every_3", "active_pulse_3", "cb_pulse_3"] else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if m == "physics_30hz":
			a.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		a.speed_scale = 3.0 if m in ["pmode_every_3", "active_every_3", "cbmode_every_3", "active_pulse_3", "cb_pulse_3"] else 1.0
	Engine.physics_ticks_per_second = 30 if m == "physics_30hz" else 60


func _process(delta: float) -> void:
	t_start = Time.get_ticks_usec()
	frame += 1
	for i in anims.size():
		var a: AnimationPlayer = anims[i]
		acc[i] += delta
		match mode:
			"advance_every_1":
				a.advance(delta); acc[i] = 0.0
			"advance_every_3":
				if (frame + i) % 3 == 0:
					a.advance(acc[i]); acc[i] = 0.0
			"pmode_every_3":
				var want := Node.PROCESS_MODE_INHERIT if (frame + i) % 3 == 0 else Node.PROCESS_MODE_DISABLED
				if a.process_mode != want:
					a.process_mode = want
			"active_pulse_3":
				var ph := (frame + i) % 3
				if ph == 0:
					a.active = true
				elif ph == 1:
					a.active = false
			"cb_pulse_3":
				var ph2 := (frame + i) % 3
				if ph2 == 0:
					a.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
				elif ph2 == 1:
					a.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			"active_every_3":
				var on := (frame + i) % 3 == 0
				if a.active != on:
					a.active = on
			"cbmode_every_3":
				var want_cb := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if (frame + i) % 3 == 0 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				if a.callback_mode_process != want_cb:
					a.callback_mode_process = want_cb
			"frozen_dirty_skel":
				var sk: Skeleton3D = sks[i]
				sk.set_bone_pose_rotation(5, sk.get_bone_pose_rotation(5))


func _measure(n: int) -> Dictionary:
	var proc: Array = []
	var rest: Array = []
	var fr: Array = []
	var rc := 0.0
	var gp := 0.0
	var vp := get_viewport().get_viewport_rid()
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		fr.append((now - last) / 1000.0)
		proc.append((t_end - t_start) / 1000.0)
		rest.append((now - last) / 1000.0 - (t_end - t_start) / 1000.0)
		last = now
		rc += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gp += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	for arr: Array in [proc, rest, fr]:
		arr.sort()
	return {"frame": fr[n / 2], "proc": proc[n / 2], "rest": rest[n / 2], "rcpu": rc / n, "gpu": gp / n}
