extends Node3D
## Seated smart-object check: one villager body uses a bench slot through a real SmartObjects.Session (approach ->
## align -> root-motion enter -> sit loops -> root-motion exit). The body follows move_to like an NPC and applies
## snap / snap_hard / exit_to exactly like villager.gd. Prints the largest per-frame jump of the pelvis (a pop) per
## phase and the pelvis-to-seat distance while seated; --shots=<dir> saves pictures at phase changes (windowed).
##   godot --path kingdom res://tools_qa/living_world/sit_check.tscn -- --look=villager_woman_a [--type=bench] [--shots=dir]

var look := "villager_man_a"
var type := "bench"
var shots := ""
var bed_at := -1.0
var bed_node: Node3D = null   # --type=bed: moved under the lying body when the loop starts
var exit_clip := ""   # --exit=<clip>: exit clip override (e.g. a get-out-of-bed take)
var loop_clip := ""   # --loop=<clip>: only this loop clip (the variant bag is seeded per person/day)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			look = a.substr(7)
		elif a.begins_with("--type="):
			type = a.substr(7)
		elif a.begins_with("--shots="):
			shots = a.substr(8)
		elif a.begins_with("--exit="):
			exit_clip = a.substr(7)
		elif a.begins_with("--loop="):
			loop_clip = a.substr(7)
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.78, 0.84)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	fl.mesh = pm
	add_child(fl)
	var so := SmartObjects.new()
	if exit_clip != "":
		so.types[type]["activity"]["exit"] = exit_clip
	if loop_clip != "":
		so.types[type]["activity"]["loop"] = [loop_clip]
	var spot := so.add(type, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var prop_path := "res://assets/generated/props/bench.glb" if type == "bench" else "res://assets/generated/life_props/table.glb"
	if type == "bed":
		prop_path = "res://assets/incoming/build_kit/bed_simple_lod0.glb"
	if ResourceLoader.exists(prop_path):
		var pr := (load(prop_path) as PackedScene).instantiate()
		add_child(pr)
		bed_node = pr as Node3D
		var bb := AABB()
		for mi: MeshInstance3D in pr.find_children("*", "MeshInstance3D", true, false):
			bb = bb.merge(mi.global_transform * mi.get_aabb()) if bb.size != Vector3.ZERO else mi.global_transform * mi.get_aabb()
		print("SITPROP %s aabb pos=%s size=%s" % [prop_path.get_file(), bb.position, bb.size])
	var m := Assets.mh_character(look, 1.7)
	add_child(m)
	var ap := Assets.animation_player(m)
	LifeLibrary.install(ap)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var pel := sk.find_bone("pelvis")
	var sx0 := so.stand_xform(spot, 0)
	m.global_position = so.approach_point(spot, 0) + sx0.basis.z * 1.5
	so.claim(spot, 0, 1)
	var s := so.session(1, spot, 0, 7)
	s.time_left = 6.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = sx0.origin + Vector3(2.6, 1.1, 1.2)
	cam.look_at(sx0.origin + Vector3(0, 0.6, 0))
	cam.current = true
	var clip := ""
	ap.play("Idle")
	ap.advance(0.0)
	var last_pel := Vector3.INF
	var worst := {}
	var seat_err := 0.0
	var last_phase := -1
	var done_clip := false
	var t := 0.0
	var shot_i := 0
	while t < 40.0:
		var dt := 1.0 / 30.0
		t += dt
		var out := s.update(dt, m.global_position, done_clip)
		done_clip = false
		if out["move_to"] != null:
			var to: Vector3 = out["move_to"]
			var d := Vector3(to.x - m.global_position.x, 0, to.z - m.global_position.z)
			m.global_position += d.limit_length(1.2 * dt)
		if not is_nan(float(out["face"])):
			m.rotation.y = float(out["face"])
		var snap: Variant = out.get("snap")
		if snap != null:
			var st := (snap as Transform3D).origin
			if bool(out.get("snap_hard", false)):
				m.global_position = Vector3(st.x, 0, st.z)
			else:
				m.global_position = m.global_position.lerp(Vector3(st.x, 0, st.z), 1.0 - exp(-8.0 * dt))
		if out.get("exit_to") != null:
			var et: Vector3 = out["exit_to"]
			m.global_position = Vector3(et.x, 0, et.z)
		var c: String = out["clip"]
		if c != "" and c != clip:
			ap.play(c, float(LifeLibrary.info(c).get("blend_in", 0.25)))
			print("SITCLIP t=%.1f phase=%d %s" % [t, int(out["phase"]), c])
			if bed_node != null and int(out["phase"]) == 3:
				bed_at = t + 0.6
			clip = c
		elif c == "" and clip != "":
			ap.play("Idle", 0.25)
			clip = ""
		elif c == "" and out["move_to"] != null and ap.current_animation != "Walk" and ap.has_animation("Walk"):
			ap.play("Walk", 0.2)
		elif c == "" and out["move_to"] == null and ap.current_animation == "Walk":
			ap.play("Idle", 0.2)
		ap.advance(dt)
		if bed_at > 0.0 and t >= bed_at:
			bed_at = -1.0
			var hp := m.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
			var fp := m.global_transform * ((sk.get_bone_global_pose(sk.find_bone("foot_l")).origin + sk.get_bone_global_pose(sk.find_bone("foot_r")).origin) * 0.5)
			var ax := Vector3(hp.x - fp.x, 0, hp.z - fp.z).normalized()
			bed_node.global_position = Vector3((hp.x + fp.x) * 0.5, 0, (hp.z + fp.z) * 0.5) - ax * 0.05
			bed_node.rotation.y = atan2(ax.z, -ax.x)   # bed model: long axis X, headboard at -X
			var side := Vector3(-ax.z, 0, ax.x)
			cam.global_position = bed_node.global_position + side * 3.4 + Vector3(0, 1.5, 0) - ax * 0.4
			cam.look_at(bed_node.global_position + Vector3(0, 0.5, 0))
			print("SITBED centre=%s head_dir=%s (slot frame: stand at origin facing +Z)" % [bed_node.global_position, ax])
		if clip != "" and not ap.is_playing():
			done_clip = true
		elif clip != "" and ap.current_animation_position + dt >= ap.current_animation_length - 1e-3:
			done_clip = true
		var phase := int(out["phase"])
		var p := m.global_transform * sk.get_bone_global_pose(pel).origin
		if last_pel != Vector3.INF:
			var j := Vector2(p.x - last_pel.x, p.z - last_pel.z).length() * 30.0
			worst[phase] = maxf(float(worst.get(phase, 0.0)), j)
		last_pel = p
		if phase == SmartObjects.Session.LOOP:
			# seat point = slot stand - forward * SEAT_REF (where the bench seat is)
			var seat := sx0.origin - sx0.basis.z * SmartObjects.SEAT_REF
			seat_err = maxf(seat_err, Vector2(p.x - seat.x, p.z - seat.z).length())
		if phase != last_phase:
			if shots != "" and DisplayServer.get_name() != "headless":
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("%s/%s_%s_%d_phase%d.png" % [shots, type, look, shot_i, phase])
				shot_i += 1
			last_phase = phase
		if phase == SmartObjects.Session.DONE:
			break
		await get_tree().process_frame
	var names := ["APPROACH", "ALIGN", "ENTER", "LOOP", "BETWEEN", "EXIT", "DONE"]
	var txt := ""
	for k in worst:
		txt += "%s %.2f m/s  " % [names[k] if k < names.size() else str(k), worst[k]]
	print("SITCHECK %s %s | max pelvis speed per phase: %s| seated pelvis-to-seat max %.1f cm | ended t=%.1fs" % [type, look, txt, seat_err * 100.0, t])
	get_tree().quit()
