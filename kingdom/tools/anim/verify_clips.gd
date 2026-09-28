extends SceneTree
## Verifies the retargeted clip libraries in assets/incoming/animations/ on a real
## game character (Assets.character("Player", 1.8, []), the MakeHuman player on the
## UAL skeleton) through the game's own clip path (Assets._ual_for):
##   metrics:  every clip exists, loops when it should, no NaN bone transforms,
##             feet not under the floor, no bone rotated > 150 deg from rest,
##             no exploding bones (max joint distance from the hips).
##   --render: contact sheets of clips at mid-pose -> /tmp/claude-0/shots/anim_<sheet>.png
##
## headless metrics:  godot --headless --path kingdom -s tools/anim/verify_clips.gd
## render (GPU/xvfb): xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan \
##                        --path kingdom -s tools/anim/verify_clips.gd -- --render [--sheet=souls]

const LIBS := ["res://assets/incoming/animations/souls_cat/UAL_Souls_Cat.glb.clips.json",
	"res://assets/incoming/animations/cmu_mocap/UAL_CMU_Mocap.glb.clips.json"]
const OUT_DIR := "/tmp/claude-0/shots/"
## sheet name -> [[clip, fraction of the clip], ...]
const SHEETS := {
	"souls": [["Souls_Light_Attack_1", 0.45], ["Souls_Heavy_Attack_1", 0.5], ["Souls_Thrust_Attack_2", 0.45],
		["Souls_Fist_Attack", 0.45], ["Shield_Bash", 0.4], ["Souls_Guard", 0.5], ["Parry_Quick", 0.4], ["Souls_Roll", 0.4]],
	"magic": [["Magic_Attack_1", 0.5], ["Magic_Attack_2", 0.5], ["Magic_Cast_L", 0.5], ["Magic_Cast_R", 0.5],
		["Magic_Casting", 0.5], ["Magic_Idle_L", 0.5], ["Drink_Potion", 0.5], ["Torch_Idle", 0.5]],
	"interact": [["Open_Door", 0.5], ["Open_Chest", 0.5], ["Open_Gate", 0.5], ["Lever_Pull_Floor", 0.5],
		["Lever_Pull_Wall", 0.5], ["Stand_From_Floor", 0.35], ["Souls_Strafe_L", 0.5], ["Souls_Fall_Attack", 0.5]],
	"karate": [["Karate_Mae_Geri", 0.45], ["Karate_Mawashi_Geri", 0.42], ["Karate_Yoko_Geri", 0.4], ["Karate_Oi_Zuki", 0.5],
		["Karate_Gedan_Barai", 0.5], ["Karate_Shuto_Uke", 0.5], ["Kata_Heian_Shodan", 0.3], ["Kata_Bassai", 0.5]],
	"mocap": [["Taichi_Idle", 0.3], ["Taichi_Form", 0.5], ["Swordplay_A", 0.4], ["Swim_Breaststroke", 0.3],
		["Swim_Freestyle", 0.3], ["Swim_Backstroke", 0.3], ["Chore_Sweep", 0.5], ["Chore_Stool_Sit_Stand", 0.35]],
	# fraction < 0: pose at the lowest joint (worst floor contact) of the clip
	"problems": [["Lie_Down", -1], ["Lie_Down_Get_Up", -1], ["Souls_Roll", -1], ["Stand_From_Floor", -1],
		["Magic_Cast_L", -1], ["Souls_Strafe_L", -1], ["Kata_Empi", -1], ["Souls_Thrust_Special", -1]],
	"chores": [["Chore_Pick_Up_Box", 0.45], ["Lie_Down", 0.6], ["Lie_Down_Idle", 0.5], ["Lie_Down_Get_Up", 0.8],
		["Kata_Empi", 0.4], ["Swordplay_B", 0.5], ["Swordplay_C", 0.5], ["Taichi_Idle", 0.6]],
}

var _render := false
var _only_sheet := ""
var _frames := 0
var _queue: Array = []
var _stage: Node3D
var _vp_ready := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--render":
			_render = true
		elif a.begins_with("--sheet="):
			_only_sheet = a.substr(8)
	if not _render:
		return
	for s: String in SHEETS:
		if _only_sheet == "" or s == _only_sheet:
			_queue.append(s)
	DisplayServer.window_set_size(Vector2i(1920, 660))
	root.size = Vector2i(1920, 660)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _render:
		if _frames == 2:
			_metrics()
			return true
		return false
	if _stage == null:
		if _queue.is_empty():
			return true
		_build_sheet(_queue[0])
		_frames = 0
		return false
	if _frames == 8:
		var img := root.get_texture().get_image()
		var path: String = OUT_DIR + "anim_" + String(_queue[0]) + ".png"
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		img.save_png(path)
		print("SHEET ", path)
		_stage.queue_free()
		_stage = null
		_queue.pop_front()
	return false


# --- metrics -------------------------------------------------------------------------

func _clip_list() -> Array:
	var out := []
	for f: String in LIBS:
		var data: Array = JSON.parse_string(FileAccess.get_file_as_string(f))
		for c: Dictionary in data:
			out.append(c)
	return out


func _metrics() -> void:
	var model := Assets.character("Player", 1.8, [])
	root.add_child(model)
	var ap := Assets.animation_player(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var feet := ["foot_l", "foot_r", "ball_l", "ball_r"]
	var rest_y := {}
	var fid := {}
	for f: String in feet:
		fid[f] = sk.find_bone(f)
		rest_y[f] = (sk.global_transform * sk.get_bone_global_rest(fid[f])).origin.y
	var hips := sk.find_bone("pelvis")
	var height := (sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Head"))).origin.y
	var worst := []
	var n_ok := 0
	print("clip | len s | loop | foot sink vs rest (m) | lowest joint y (m) | max swing deg (bone) | max twist deg | reach (m) | root track | verdict")
	for c: Dictionary in _clip_list():
		var clip: String = c["name"]
		if not ap.has_animation(clip):
			print("MISSING ", clip)
			worst.append(clip + " missing")
			continue
		var anim := ap.get_animation(clip)
		var loop_ok := (anim.loop_mode != Animation.LOOP_NONE) == bool(c["loop"])
		var root_track := "none"
		for t in anim.get_track_count():
			if String(anim.track_get_path(t)).ends_with(":root") and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				root_track = "off" if not anim.track_is_enabled(t) else "ON"
		ap.play(clip)
		var sink := 9.0          # lowest foot/ball joint relative to its standing rest height
		var low := 9.0           # lowest joint centre above the floor (any bone)
		var low_bone := ""
		var max_swing := 0.0
		var swing_bone := ""
		var max_twist := 0.0
		var reach := 0.0
		var nan := false
		var steps := 30
		var gy := sk.global_transform
		for i in steps + 1:
			ap.seek(anim.length * float(i) / steps, true)
			for f: String in feet:
				sink = minf(sink, (gy * sk.get_bone_global_pose(fid[f])).origin.y - float(rest_y[f]))
			var hp := sk.get_bone_global_pose(hips).origin
			for b in sk.get_bone_count():
				var bn := sk.get_bone_name(b)
				var gp := sk.get_bone_global_pose(b)
				if not (gp.origin.is_finite() and gp.basis.x.is_finite() and gp.basis.y.is_finite() and gp.basis.z.is_finite()):
					nan = true
				reach = maxf(reach, gp.origin.distance_to(hp) * gy.basis.get_scale().x)
				if bn == "root":
					continue
				var y := (gy * gp).origin.y
				if y < low:
					low = y
					low_bone = bn
				if bn.contains("leaf") or bn == "pelvis":
					continue
				# local rotation away from rest, split into swing (bone direction) and twist
				var d := sk.get_bone_rest(b).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(b)
				var sw := rad_to_deg(Vector3.UP.angle_to(d * Vector3.UP))
				var tw := absf(rad_to_deg(2.0 * atan2(d.y, d.w)))
				tw = minf(tw, 360.0 - tw)
				if sw > max_swing:
					max_swing = sw
					swing_bone = bn
				max_twist = maxf(max_twist, tw)
		var bad := []
		if nan: bad.append("NaN")
		if not loop_ok: bad.append("loop flag")
		if low < -0.03: bad.append("under floor (%s)" % low_bone)
		if max_swing > 150.0: bad.append("limb swing >150 (%s)" % swing_bone)
		if reach > height * 0.75: bad.append("exploding")
		var verdict := "OK" if bad.is_empty() else ", ".join(bad)
		if bad.is_empty():
			n_ok += 1
		else:
			worst.append(clip + ": " + verdict)
		print("%s | %.2f | %s | %.3f | %.3f (%s) | %.0f (%s) | %.0f | %.2f | %s | %s" % [clip, anim.length,
			"loop" if anim.loop_mode != Animation.LOOP_NONE else "-", sink, low, low_bone, max_swing, swing_bone,
			max_twist, reach, root_track, verdict])
	print("VERIFY_DONE ok=%d problems=%d" % [n_ok, worst.size()])
	for w: String in worst:
		print("PROBLEM ", w)


# --- contact sheet -------------------------------------------------------------------

func _build_sheet(sheet: String) -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.8, 0.76)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.3
	_stage.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.5, 0.42)
	floor.material_override = fm
	_stage.add_child(floor)
	var clips: Array = SHEETS[sheet]
	var spacing := 1.75
	var x0 := -spacing * (clips.size() - 1) * 0.5
	for i in clips.size():
		var clip: String = clips[i][0]
		var model := Assets.character("Player", 1.8, [])
		model.position = Vector3(x0 + i * spacing, 0, 0)
		model.rotation_degrees.y = 60.0
		_stage.add_child(model)
		var ap := Assets.animation_player(model)
		if ap.has_animation(clip):
			ap.play(clip)
			var t := ap.get_animation(clip).length * float(clips[i][1])
			if float(clips[i][1]) < 0.0:
				t = _lowest_time(model, ap, clip)
			ap.seek(t, true)
			ap.pause()
		var lbl := Label3D.new()
		lbl.text = clip + ("" if ap.has_animation(clip) else " (MISSING)")
		lbl.font_size = 30
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.1, 0.1, 0.1)
		lbl.outline_size = 0
		lbl.position = Vector3(x0 + i * spacing, 0.05, 1.1)
		lbl.rotation_degrees.x = -60
		_stage.add_child(lbl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14.4
	cam.position = Vector3(0, 2.2, 8)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	_stage.add_child(cam)
	cam.make_current()
	cam.keep_aspect = Camera3D.KEEP_WIDTH


func _lowest_time(model: Node3D, ap: AnimationPlayer, clip: String) -> float:
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var a := ap.get_animation(clip)
	var best := 9.0
	var best_t := 0.0
	for i in 61:
		var t := a.length * i / 60.0
		ap.seek(t, true)
		for b in sk.get_bone_count():
			var y := (sk.global_transform * sk.get_bone_global_pose(b)).origin.y
			if y < best:
				best = y
				best_t = t
	return best_t
