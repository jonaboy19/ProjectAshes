extends Node3D
## Horses and riding proof scene (docs/anim/horses/HANDOFF.md).
##   Godot --path kingdom res://tools_qa/horses/horse_demo.tscn --write-movie out/f.png --fixed-fps 30 --quit-after N -- --mode=<mode> [opts]
## modes:
##   gait     --clip=Walk|Trot|Canter_L|Gallop_L|BackUp|...  --view=side|front|three  [--rider=1] [--coat=bay] [--frames=N]
##            one horse driven at the clip's authored speed along a straight track with 0.5 m ground ticks (slide check),
##            camera locked to the horse (orthographic side view by default). Also prints per-frame hoof heights.
##   clip     --clip=<any horse clip> plays that clip once in place (root motion applied), for actions (Rear, Buck, Jump_Full ...)
##   course   gallop with turns: waypoint loop, speed changes walk->trot->canter->gallop->stop, rider on
##   mount    rider mounts from the left, rides walk/trot/canter, halts, dismounts right, remounts, jumps off
##   combat   mounted canter pass: sword swings right and left at dummies, then bow draw / aim / release
##   crowd    20 horses in LOD (NEAR skeleton, MID stepped, FAR VAT) grazing / walking / trotting; LOD tint with --tint=1
##   bench    per-tier cost per horse (forced tiers, paired with/without) -> prints BENCH lines
##   beauty   a sunny paddock shot with coats and tack variants

var mode := "gait"
var args := {}
var cam: Camera3D
var horses: Array[HorseRig] = []
var riders := {}
var t := 0.0
var frame := 0
var hud: Label


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	mode = String(args.get("mode", "gait"))
	_environment()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	var cl := CanvasLayer.new()
	add_child(cl)
	cl.add_child(hud)
	call("_setup_" + mode)


# ------------------------------------------------------------------ environment
func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.52, 0.92)
	sm.sky_horizon_color = Color(0.72, 0.84, 0.97)
	sm.ground_horizon_color = Color(0.62, 0.72, 0.6)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.82, 0.95)
	e.fog_density = 0.004
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-50, 55, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# ground: grass with a dirt track and 0.5 m ticks across the track (foot-slide reference)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.62, 0.26)
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	var track := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(3.0, 600)
	track.mesh = tm
	var trm := StandardMaterial3D.new()
	trm.albedo_color = Color(0.72, 0.6, 0.42)
	track.material_override = trm
	track.position = Vector3(0, 0.005, 0)
	add_child(track)
	var tick := BoxMesh.new()
	tick.size = Vector3(3.0, 0.004, 0.04)
	var tickm := StandardMaterial3D.new()
	tickm.albedo_color = Color(0.3, 0.22, 0.15)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tick
	mm.instance_count = 1200
	for i in 1200:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, 0.008, (i - 600) * 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = tickm
	add_child(mmi)


func _horse(coat := "bay", tack: Array = ["saddle", "bridle", "reins"], q := 2) -> HorseRig:
	var h := HorseRig.new()
	h.coat = coat
	var ts: Array[String] = []
	ts.assign(tack)
	h.tack = ts
	h.quality = q
	add_child(h)
	horses.append(h)
	return h


func _rider(h: HorseRig, props: Array[String] = []) -> Node3D:
	var body := Assets.character("Player", 1.8, props)
	add_child(body)
	var sync := RiderSync.new()
	add_child(sync)
	sync.attach(h, body)
	var ik := RiderIK.new()
	add_child(ik)
	ik.setup(h, sync.skeleton)
	riders[h] = {"body": body, "sync": sync, "ik": ik}
	get_tree().create_timer(0.3).timeout.connect(ik.calibrate)
	return body


# ------------------------------------------------------------------ modes
var _drive_speed := 0.0
var _drive_turn := 0.0
var _clip_name := "Walk"


func _setup_gait() -> void:
	_clip_name = String(args.get("clip", "Walk"))
	var h := _horse(String(args.get("coat", "bay")), ["saddle", "bridle", "reins"] if args.get("rider", "0") == "1" else ["bridle"])
	h.rotation.y = 0.0
	if args.get("rider", "0") == "1":
		_rider(h)
	var info := HorseRig.clip_info(_clip_name)
	_drive_speed = float(info.get("speed_mps", 0.0))
	if _clip_name == "BackUp":
		_drive_speed = -_drive_speed
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4


func _setup_clip() -> void:
	_clip_name = String(args.get("clip", "Rear"))
	var h := _horse(String(args.get("coat", "bay")), ["saddle", "bridle", "reins"] if args.get("rider", "0") == "1" else ["bridle"])
	if args.get("rider", "0") == "1":
		_rider(h)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.2
	await get_tree().create_timer(0.4).timeout
	h.play_action(_clip_name, 0.0)


func _process(delta: float) -> void:
	t += delta
	frame += 1
	if has_method("_tick_" + mode):
		call("_tick_" + mode, delta)
	var lines := []
	for h in horses.slice(0, 3):
		lines.append("%s  %s  %.1f m/s  x%.2f  phase %.2f" % [h.gait, h.clip, h.speed, h.anim.speed_scale, h.phase()])
	hud.text = "Horse demo: %s   f%d  %.2fs\n%s" % [mode, frame, t, "\n".join(lines)]


func _tick_gait(delta: float) -> void:
	var h := horses[0]
	h.drive(_drive_speed, 0.0, delta)
	h.global_position += h.global_basis.z * _drive_speed * delta
	var view := String(args.get("view", "side"))
	var p := h.global_position
	if view == "side":
		cam.global_position = p + Vector3(7.0, 2.3, 0.2)
		cam.look_at(p + Vector3(0, 0.95, 0.2))
	elif view == "rider":
		cam.size = 2.3
		cam.global_position = p + Vector3(7.0, 2.6, -0.1)
		cam.look_at(p + Vector3(0, 1.62, -0.1))
	elif view == "front":
		cam.global_position = p + Vector3(0, 1.2, 7.0)
		cam.look_at(p + Vector3(0, 1.2, 0))
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 40
		cam.global_position = p + Vector3(5.0, 2.6, 4.5)
		cam.look_at(p + Vector3(0, 1.0, 0))
	if args.get("hoofs", "0") == "1":
		_print_hoofs(h)
	if args.get("dbg", "0") == "1" and riders.has(h) and frame % 10 == 5:
		var sy: RiderSync = riders[h]["sync"]
		var sk := sy.skeleton
		var pb := sk.find_bone("pelvis")
		print("DBG f%d gait=%s tree=%s act=%s lib=%d pelvis=%s rider=%s skel_rel=%s track0=%s" % [frame, sy.rider_clip_for(h.clip), sy.tree.active,
			sy._blend_gait.animation, sy._anim.get_animation_library(RiderSync.LIB).get_animation_list().size(), sk.get_bone_pose_position(pb),
			sy.rider.global_position, sy.rider.global_transform.affine_inverse() * sk.global_transform.origin,
			sy._anim.get_animation(sy._blend_gait.animation).track_get_path(0) if sy._anim.has_animation(sy._blend_gait.animation) else "-"])


const HOOF_LEN := {"hoof_F_L": 0.129, "hoof_F_R": 0.129, "hoof_H_L": 0.089, "hoof_H_R": 0.089}


## world toe points of the four hooves (for tools_qa/horses/slide_report.py)
func _print_hoofs(h: HorseRig) -> void:
	var s := []
	for b: String in HOOF_LEN:
		var bi := h.skeleton.find_bone(b)
		var tip := h.skeleton.global_transform * h.skeleton.get_bone_global_pose(bi) * Vector3(0, HOOF_LEN[b], 0)
		s.append("%s %.4f %.4f %.4f" % [b, tip.x, tip.y, tip.z])
	print("HOOF f%d %s %s" % [frame, h.clip, " | ".join(s)])


func _tick_clip(_delta: float) -> void:
	var h := horses[0]
	if not h.is_busy():
		h.drive(0.0, 0.0, 0.0)
	var rm := h.root_motion_delta()
	h.global_position += h.global_basis * rm
	var p := h.global_position
	cam.global_position = p + Vector3(7.0, 2.5, 0.0)
	cam.look_at(p + Vector3(0, 1.2, 0))


# ---- course: gallop with turns around a figure-eight of waypoints, speeds stepping up and back down
var _wp: Array[Vector3] = []
var _wi := 0
var _yaw := 0.0
var _v := 0.0
var _cam_yaw := 0.0


func _setup_course() -> void:
	var h := _horse("grey")
	_rider(h)
	for k in 16:
		var a := TAU * k / 16.0
		_wp.append(Vector3(sin(a) * 34.0, 0, sin(2 * a) * 17.0))
	# fence posts around the figure-eight (motion reference for the turns)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.08
	post.height = 1.2
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.3, 0.18)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	mm.instance_count = 160
	for k in 160:
		var a := TAU * k / 160.0
		var c := Vector3(sin(a) * 34.0, 0.6, sin(2 * a) * 17.0)
		var d := Vector3(cos(a) * 34.0, 0, 2 * cos(2 * a) * 17.0).normalized()
		var n := Vector3(d.z, 0, -d.x)
		mm.set_instance_transform(k, Transform3D(Basis(), c + n * (3.0 if k % 2 else -3.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = pm
	add_child(mmi)
	cam.fov = 50


func _tick_course(delta: float) -> void:
	var h := horses[0]
	var target_v := 1.5 if t < 5 else (3.6 if t < 10 else (5.8 if t < 15 else (11.0 if t < 23 else (5.8 if t < 26 else 0.0))))
	_v = move_toward(_v, target_v, (4.5 if target_v > _v else 6.5) * delta)
	var goal := _wp[_wi]
	var to := goal - h.global_position
	to.y = 0
	if to.length() < 3.5:
		_wi = (_wi + 1) % _wp.size()
	var want := atan2(to.x, to.z)
	var d := wrapf(want - _yaw, -PI, PI)
	var rate := lerpf(1.9, 0.75, clampf(_v / 11.0, 0, 1))
	var turn := clampf(d * 2.0, -rate, rate) if _v > 0.2 else 0.0
	_yaw += turn * delta
	h.rotation.y = _yaw
	h.drive(_v, turn, delta)
	h.global_position += Vector3(sin(_yaw), 0, cos(_yaw)) * _v * delta
	var back := Vector3(sin(_yaw), 0, cos(_yaw))
	var side := Vector3(cos(_yaw), 0, -sin(_yaw))
	_cam_yaw = lerp_angle(_cam_yaw, _yaw, 1.0 - exp(-2.5 * delta)) if frame > 2 else _yaw
	var cb := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw))
	var cs := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
	cam.global_position = h.global_position - cb * 4.4 + cs * 3.4 + Vector3(0, 1.9, 0)
	cam.look_at(h.global_position + Vector3(0, 1.3, 0) + cb * 1.5)


# ---- mount / dismount sequence
var _seq: Array = []
var _si := 0
var _st := 0.0


func _setup_mount() -> void:
	var h := _horse("chestnut")
	_rider(h)
	var s: RiderSync = riders[h]["sync"]
	s.hold_full = true
	_seq = [["full", "Horse_Ride_Mount_L", 0.0], ["drive", 1.5, 3.0], ["drive", 3.6, 3.0], ["drive", 5.8, 3.0], ["drive", 0.0, 2.5],
		["full", "Horse_Ride_Dismount_R", 0.0], ["wait", 1.0], ["full", "Horse_Ride_Mount_R", 0.0], ["wait", 1.0], ["full", "Horse_Ride_Dismount_Jump", 0.0], ["wait", 2.0]]
	cam.fov = 45


func _tick_mount(delta: float) -> void:
	_tick_seq(delta)
	var h := horses[0]
	cam.global_position = h.global_position + Vector3(6.5, 2.2, 1.5)
	cam.look_at(h.global_position + Vector3(0, 1.2, 0))


func _tick_seq(delta: float) -> void:
	var h := horses[0]
	var r: Dictionary = riders[h]
	var s: RiderSync = r["sync"]
	var ik: RiderIK = r["ik"]
	_st += delta
	if _si >= _seq.size():
		h.drive(0.0, 0.0, delta)
		return
	var step: Array = _seq[_si]
	match step[0]:
		"full":
			if _st <= delta * 1.5:
				var l := s.play_full(step[1])
				ik.feet = 0.0
				ik.hands = Vector2.ZERO
				step[2] = l if l > 0 else 0.5
			h.drive(0.0, 0.0, delta)
			if _st >= step[2]:
				if not String(step[1]).begins_with("Horse_Ride_Dismount"):
					s.stop_full()
					ik.feet = 1.0
					ik.hands = Vector2(1, 1)
				_next()
		"drive":
			h.drive(step[1], 0.0, delta)
			h.global_position += h.global_basis.z * step[1] * delta
			if _st >= step[2]:
				_next()
		"upper":
			if _st <= delta * 1.5:
				step[2] = s.play_upper(step[1])
				ik.hands = step[3]
			h.drive(step[4], 0.0, delta)
			h.global_position += h.global_basis.z * step[4] * delta
			if _st >= maxf(step[2], 0.3):
				ik.hands = Vector2(1, 1)
				_next()
		"wait":
			h.drive(0.0, 0.0, delta)
			if _st >= step[1]:
				_next()


func _next() -> void:
	_si += 1
	_st = 0.0


# ---- mounted combat pass
func _setup_combat() -> void:
	var h := _horse("warhorse", ["saddle", "bridle", "reins", "barding"])
	var props: Array[String] = ["Sword"]
	_rider(h, props)
	for z in [8.0, 16.0, 26.0]:
		for x in [-1.8, 1.8]:
			var d := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.18
			cm.bottom_radius = 0.22
			cm.height = 1.7
			d.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.75, 0.62, 0.35)
			d.material_override = m
			d.position = Vector3(x, 0.85, z)
			add_child(d)
	_seq = [["drive", 5.8, 1.0], ["upper", "Horse_Ride_Sword_Swing_R", 0.0, Vector2(1, 0), 5.8], ["upper", "Horse_Ride_Sword_Swing_L", 0.0, Vector2(1, 0), 5.8],
		["drive", 5.8, 0.4], ["upper", "Horse_Ride_Bow_Draw", 0.0, Vector2(0, 0), 5.8], ["upper", "Horse_Ride_Bow_Aim", 0.0, Vector2(0, 0), 5.8],
		["upper", "Horse_Ride_Bow_Release", 0.0, Vector2(0, 0), 5.8], ["drive", 3.6, 1.5], ["drive", 0.0, 2.0]]
	cam.fov = 48


func _tick_combat(delta: float) -> void:
	_tick_seq(delta)
	var h := horses[0]
	cam.global_position = h.global_position + Vector3(4.2, 2.3, 3.2)
	cam.look_at(h.global_position + Vector3(0, 1.6, 0.4))


# ---- crowd: 20 horses in LOD
var lod: CrowdAnimLOD
var vat: VatCrowd
var _crowd_ai := []


func _setup_crowd() -> void:
	vat = VatCrowd.new()
	add_child(vat)
	var coats := ["bay", "chestnut", "grey", "black", "dappled"]
	var looks := []
	for c in coats:
		looks.append("horse_" + c)
	vat.load_looks(looks)
	vat.camera = cam
	lod = CrowdAnimLOD.new()
	add_child(lod)
	lod.vat = vat
	lod.camera = cam
	if args.has("tier"):
		lod.set_tier(int(args["tier"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(args.get("count", "20"))
	for i in n:
		var coat: String = coats[i % coats.size()]
		var h := _horse(coat, ["bridle"] if i % 3 else ["saddle", "bridle", "reins"], 1)
		h.position = Vector3(rng.randf_range(-13, 13), 0, rng.randf_range(4, 75))
		h.rotation.y = rng.randf() * TAU
		lod.register(i, h, h.model, h.anim, null, "horse_" + coat)
		var kind: String = ["graze", "walk", "trot", "idle", "walk"][i % 5]
		_crowd_ai.append({"kind": kind, "yaw": h.rotation.y, "t": rng.randf() * 5.0})
		if kind == "graze":
			h.set_mode("graze")
	cam.fov = 55
	cam.global_position = Vector3(0, 6.0, -18)
	cam.look_at(Vector3(0, 0.5, 20))
	if args.get("tint", "0") == "1":
		vat.set_debug_tint(Color(0.2, 0.4, 1.0, 0.45))


func _tick_crowd(delta: float) -> void:
	for i in horses.size():
		var h := horses[i]
		var ai: Dictionary = _crowd_ai[i]
		var v := {"graze": 0.0, "idle": 0.0, "walk": 1.5, "trot": 3.4}[ai["kind"]] as float
		ai["t"] += delta
		var turn := 0.35 * sin(ai["t"] * 0.4 + i) if v > 0 else 0.0
		ai["yaw"] += turn * delta
		h.rotation.y = ai["yaw"]
		h.drive(v, turn, delta)
		h.global_position += Vector3(sin(ai["yaw"]), 0, cos(ai["yaw"])) * v * delta
	# slow dolly so the LOD tiers change on screen
	cam.global_position = Vector3(5.0 * sin(t * 0.15), 3.2, -8 + t * 2.4)
	cam.look_at(cam.global_position + Vector3(0, -0.18, 1))
	if args.get("dbg", "0") == "1" and frame % 30 == 0:
		for i in horses.size():
			var hh := horses[i]
			print("CDBG f%d id%d tier=%d dist=%.1f vat=%s vis=%s pos=%s" % [frame, i, lod.tier_of(i), hh.global_position.distance_to(cam.global_position),
				vat.has(i), hh.model.visible, hh.global_position])
	if lod:
		hud.text += "\nLOD near %d  mid %d  far(VAT) %d  out %d   lod cpu %d us" % [lod.counts[0], lod.counts[1], lod.counts[2], lod.counts[3], lod.cpu_usec]


# ---- bench: per-tier cost per horse (paired with / without, vsync off, best of `reps`)
var _bench_rows := []


func _setup_bench() -> void:
	_run_bench.call_deferred()


func _spawn_herd(n: int, q: int, tier: int) -> void:
	var coats := ["bay", "chestnut", "grey", "black", "dappled"]
	for i in n:
		var coat: String = coats[i % coats.size()]
		var h := _horse(coat, ["saddle", "bridle", "reins"] if tier == CrowdAnimLOD.Tier.NEAR else ["bridle"], q)
		h.position = Vector3(-9 + (i % 8) * 2.6, 0, 4 + (i / 8) * 3.2)
		h.rotation.y = PI * 0.5
		lod.register(i, h, h.model, h.anim, null, "horse_" + coat)
		_crowd_ai.append({"kind": ["walk", "trot", "graze", "idle"][i % 4], "yaw": h.rotation.y, "t": 0.0})
	lod.force_tier = tier


func _clear_herd() -> void:
	for i in horses.size():
		lod.unregister(i)
		horses[i].queue_free()
	horses.clear()
	_crowd_ai.clear()
	vat.clear()


## median wall frame time (ms). Run windowed at a tiny resolution with shadows off and vsync off, so the frame is
## CPU-bound: the difference with / without the horses is their main-thread cost (mixer, skeleton, modifiers, skin setup,
## scripts, render submission).
func _frames(n: int) -> float:
	var ft := []
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last) / 1000.0)
		last = now
	ft.sort()
	return ft[ft.size() / 2]


func _run_bench() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for l in find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = false
	vat = VatCrowd.new()
	add_child(vat)
	vat.load_looks(["horse_bay", "horse_chestnut", "horse_grey", "horse_black", "horse_dappled"])
	vat.camera = cam
	lod = CrowdAnimLOD.new()
	add_child(lod)
	lod.vat = vat
	lod.camera = cam
	cam.global_position = Vector3(0, 9.0, -14)
	cam.look_at(Vector3(0, 0.5, 8))
	var n := int(args.get("count", "32"))
	var reps := int(args.get("reps", "3"))
	var specs := [["NEAR skeletal, springs HIGH (tail+mane+belly), tack", CrowdAnimLOD.Tier.NEAR, 2], ["NEAR skeletal, springs MED (tail)", CrowdAnimLOD.Tier.NEAR, 1],
		["NEAR skeletal, no springs (LOW)", CrowdAnimLOD.Tier.NEAR, 0], ["MID stepped (1 in 2-4 frames), LOD1", CrowdAnimLOD.Tier.MID, 1],
		["FAR VAT twin (node kept, skeleton idle)", CrowdAnimLOD.Tier.FAR, 1]]
	for spec: Array in specs:
		var diffs := []
		var pair := []
		for r in reps:
			_spawn_herd(n, spec[2], spec[1])
			for k in 90:
				await get_tree().process_frame
			var w: float = await _frames(240)
			_clear_herd()
			for k in 45:
				await get_tree().process_frame
			var wo: float = await _frames(240)
			diffs.append((w - wo) * 1000.0 / n)
			pair = [w, wo]
		diffs.sort()
		var best: float = diffs[diffs.size() / 2]
		_bench_rows.append("| %s | %d | **%.1f** | %.2f / %.2f |" % [spec[0], n, best, pair[0], pair[1]])
		print("BENCH %s per-horse %.1f us (with %.2f ms, without %.2f ms)" % [spec[0], best, pair[0], pair[1]])
	# rider: RiderSync + RiderIK on one horse, 8 riders
	var rd := []
	for r in reps:
		_spawn_herd(8, 2, CrowdAnimLOD.Tier.NEAR)
		for k in 60:
			await get_tree().process_frame
		var wo: float = await _frames(240)
		for h in horses:
			_rider(h)
		for k in 60:
			await get_tree().process_frame
		var w: float = await _frames(240)
		for h in riders:
			(riders[h]["body"] as Node).queue_free()
			(riders[h]["sync"] as Node).queue_free()
			(riders[h]["ik"] as Node).queue_free()
		riders.clear()
		_clear_herd()
		rd.append((w - wo) * 1000.0 / 8.0)
	rd.sort()
	var best_r: float = rd[rd.size() / 2]
	_bench_rows.append("| rider on a horse: skinned UAL body + RiderSync (AnimationTree, 3 layers) + RiderIK (4 TwoBoneIK3D) | 8 | **%.1f** | |" % best_r)
	print("BENCH rider per-rider %.1f us" % best_r)
	var txt := "| tier | horses | main-thread us / horse (median of %d pairs) | frame ms with / without (last pair) |
|---|---:|---:|---|
" % reps + "
".join(_bench_rows)
	print("BENCH_TABLE
" + txt)
	get_tree().quit()


func _tick_bench(delta: float) -> void:
	for i in horses.size():
		var h := horses[i]
		var ai: Dictionary = _crowd_ai[i]
		var v := {"graze": 0.0, "idle": 0.0, "walk": 1.5, "trot": 3.4}[ai["kind"]] as float
		h.drive(v, 0.0, delta)


# ---- beauty
func _setup_beauty() -> void:
	var coats := ["bay", "chestnut", "grey", "black", "dappled", "warhorse"]
	var tacks := [["saddle", "bridle", "reins"], ["bridle"], ["saddle", "bridle", "reins", "saddlebags"], ["cart_harness"], ["bridle"], ["saddle", "bridle", "reins", "barding"]]
	for i in coats.size():
		var h := _horse(coats[i], tacks[i])
		h.position = Vector3((i - 2.5) * 2.4, 0, (i % 2) * 1.5)
		h.rotation.y = deg_to_rad(70 + i * 7)
		if i == 1:
			h.set_mode("graze")
		if i == 3:
			var cart: Node3D = (load("res://assets/generated/horses/horse_cart.glb") as PackedScene).instantiate()
			add_child(cart)
			cart.global_transform = h.global_transform.translated_local(Vector3(0, 0, -2.05))
	cam.fov = 40
	cam.global_position = Vector3(1.0, 2.6, 11.0)
	cam.look_at(Vector3(0, 1.0, 0))
