extends SceneTree
## Contact-sheet renderer + metrics for clip libraries built by tools/anim/retarget_bvh.py.
## Loads one or more clip GLBs (UAL 65-bone skeleton), adds their clips to the game's own
## Player character (Assets.character("Player", 1.8, [])) exactly like Assets._ual_for does
## (track paths rewritten to the character's skeleton, root track ignored) and renders
## side-view filmstrips: one row per clip, N frames evenly spaced (or every --dt seconds).
##
##   godot --path kingdom -s tools/anim/preview_free_library.gd -- \
##       --glb=res://assets/incoming/animations_free/kicks/UAL_Free_Kicks.glb \
##       --out=C:/out/kicks --frames=8 [--dt=0.5] [--rows=5] [--clips=A,B,C] [--cell=200]
##   --metrics  prints per-clip sanity numbers (NaN, foot sink, reach, limb swing) instead of images
##   --front    camera looks from the front instead of the side
## Runs windowed (needs a GPU / display); metrics also work with --headless.

var _glbs: Array[String] = []
var _out := "user://free_preview"
var _frames := 8
var _dt := 0.0
var _rows := 5
var _cell := 200
var _wrap := 12
var _only: Array[String] = []
var _metrics := false
var _front := false
var _stop := false            # --stopmotion: one PNG per 1/--fps s per clip, for tools/qa/video_to_sheets.sh
var _fps := 12.0
var _sm_clip := 0
var _sm_frame := 0
var _sm_model: Node3D
var _sm_ap: AnimationPlayer
var _sm_wait := 0
var _clips: Array = []          # [[name, Animation], ...]
var _sheets: Array = []
var _stage: Node3D
var _tick := 0
var _sheet_i := 0
var _ap_root: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): _glbs.append(a.substr(6))
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--frames="): _frames = int(a.substr(9))
		elif a.begins_with("--dt="): _dt = float(a.substr(5))
		elif a.begins_with("--rows="): _rows = int(a.substr(7))
		elif a.begins_with("--cell="): _cell = int(a.substr(7))
		elif a.begins_with("--wrap="): _wrap = int(a.substr(7))
		elif a.begins_with("--clips="): _only.append_array(a.substr(8).split(","))
		elif a == "--metrics": _metrics = true
		elif a == "--stopmotion": _stop = true
		elif a.begins_with("--fps="): _fps = float(a.substr(6))
		elif a == "--front": _front = true
	_load_clips()
	if _metrics:
		return
	if _stop:
		DisplayServer.window_set_size(Vector2i(240, 330))
		root.size = Vector2i(240, 330)
		DirAccess.make_dir_recursive_absolute(_out)
		return
	var lines: Array = []       # [name, Animation, t0] - long clips wrap onto several lines with --dt
	for c in _clips:
		var a: Animation = c[1]
		if _dt > 0.0:
			var t0 := 0.0
			while t0 < a.length - 0.001:
				lines.append([c[0], a, t0])
				t0 += _wrap * _dt
		else:
			lines.append([c[0], a, 0.0])
	var i := 0
	while i < lines.size():
		_sheets.append(lines.slice(i, i + _rows))
		i += _rows
	var cols := _cols_for(_clips)
	var w := cols * _cell
	var h := _rows * int(_cell * 1.375)
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	DirAccess.make_dir_recursive_absolute(_out)


func _cols_for(_clips_unused: Array) -> int:
	return _wrap if _dt > 0.0 else _frames


func _load_clips() -> void:
	_ap_root = Assets.character("Player", 1.8, [])
	var ap := Assets.animation_player(_ap_root)
	var sk_path := ""
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		if a.get_track_count() > 0:
			var tp := String(a.track_get_path(0))
			sk_path = tp.substr(0, tp.find(":"))
			break
	for f in _glbs:
		var inst: Node
		if f.begins_with("res://"):
			inst = Assets.scene(f).instantiate()
		else:   # raw file outside the project (scratch libraries): runtime glTF import
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			doc.append_from_file(f, st)
			inst = doc.generate_scene(st)
		var src: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for n in src.get_animation_list():
			if not _only.is_empty() and not (n in _only):
				continue
			var a: Animation = src.get_animation(n).duplicate(true)
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(sk_path + tp.substr(colon)))
					if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						a.track_set_enabled(t, false)
			_clips.append([n, a])
		inst.free()
	_clips.sort_custom(func(x, y): return String(x[0]) < String(y[0]))


func _process(_delta: float) -> bool:
	if _metrics:
		_run_metrics()
		return true
	if _stop:
		return _stopmotion_step()
	_tick += 1
	if _stage == null:
		if _sheet_i >= _sheets.size():
			return true
		_build(_sheets[_sheet_i])
		_tick = 0
		return false
	if _tick == 8:
		var img := root.get_texture().get_image()
		var p := "%s/sheet_%02d.png" % [_out, _sheet_i]
		img.save_png(p)
		print("SHEET ", p, " ", ", ".join(_sheets[_sheet_i].map(func(c): return c[0])))
		_stage.queue_free()
		_stage = null
		_sheet_i += 1
	return false


func _build(rows: Array) -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.85, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.2
	_stage.add_child(sun)
	var cols := _cols_for(_clips)
	var cw := 1.6
	var rh := 2.2
	var x0 := -cw * (cols - 1) * 0.5
	var y_top := rh * _rows * 0.5
	for r in rows.size():
		var name: String = rows[r][0]
		var anim: Animation = rows[r][1]
		var yb := y_top - (r + 1) * rh + 0.15            # floor height of this row
		var fl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(cw * cols, 0.03, 1.0)
		fl.mesh = bm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.5, 0.45, 0.38)
		fl.material_override = fm
		fl.position = Vector3(0, yb - 0.015, 0)
		_stage.add_child(fl)
		var lbl := Label3D.new()
		var t0: float = rows[r][2]
		lbl.text = "%s  %.2fs%s%s" % [name, anim.length, "  LOOP" if anim.loop_mode != Animation.LOOP_NONE else "",
			("   from %.1fs" % t0) if _dt > 0.0 else ""]
		lbl.font_size = 40
		lbl.pixel_size = 0.0045
		lbl.modulate = Color(0.05, 0.05, 0.05)
		lbl.outline_size = 0
		lbl.position = Vector3(x0 - cw * 0.45, yb + rh - 0.42, 0.5)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_stage.add_child(lbl)
		for c in cols:
			var t: float
			if _dt > 0.0:
				t = t0 + c * _dt
				if t > anim.length + 0.001:
					continue
				t = minf(t, anim.length)
			else:
				t = anim.length * float(c) / float(maxi(cols - 1, 1))
			var model := Assets.character("Player", 1.8, [])
			model.position = Vector3(x0 + c * cw, yb, 0)
			model.rotation_degrees.y = 0.0 if _front else 90.0
			_stage.add_child(model)
			var ap := Assets.animation_player(model)
			var lib := AnimationLibrary.new()
			lib.add_animation("clip", anim.duplicate(true))
			ap.add_animation_library("free", lib)
			ap.play("free/clip")
			ap.seek(t, true)
			ap.pause()
			var tl := Label3D.new()
			tl.text = "%.2f" % t
			tl.font_size = 28
			tl.pixel_size = 0.0045
			tl.modulate = Color(0.25, 0.25, 0.25)
			tl.position = Vector3(x0 + c * cw, yb + 0.05, 0.6)
			_stage.add_child(tl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rh * _rows
	cam.position = Vector3(0, 0, 12)
	_stage.add_child(cam)
	cam.make_current()


func _run_metrics() -> void:
	var model := Assets.character("Player", 1.8, [])
	root.add_child(model)
	var ap := Assets.animation_player(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := AnimationLibrary.new()
	for c in _clips:
		lib.add_animation(c[0], c[1])
	ap.add_animation_library("free", lib)
	var feet := ["foot_l", "foot_r", "ball_l", "ball_r"]
	var fid := {}
	var rest_y := {}
	for f: String in feet:
		fid[f] = sk.find_bone(f)
		rest_y[f] = (sk.global_transform * sk.get_bone_global_rest(fid[f])).origin.y
	var hips := sk.find_bone("pelvis")
	print("clip | len | loop | foot sink | lowest joint | max swing | reach | verdict")
	var bad_n := 0
	for c in _clips:
		var anim: Animation = c[1]
		ap.play("free/" + String(c[0]))
		var sink := 9.0
		var low := 9.0
		var swing := 0.0
		var reach := 0.0
		var nan := false
		var gy := sk.global_transform
		for i in 41:
			ap.seek(anim.length * float(i) / 40.0, true)
			for f: String in feet:
				sink = minf(sink, (gy * sk.get_bone_global_pose(fid[f])).origin.y - float(rest_y[f]))
			var hp := sk.get_bone_global_pose(hips).origin
			for b in sk.get_bone_count():
				var bn := sk.get_bone_name(b)
				var gp := sk.get_bone_global_pose(b)
				if not (gp.origin.is_finite() and gp.basis.x.is_finite()):
					nan = true
				reach = maxf(reach, gp.origin.distance_to(hp))
				if bn == "root":
					continue
				low = minf(low, (gy * gp).origin.y)
				if bn.contains("leaf") or bn == "pelvis":
					continue
				var d := sk.get_bone_rest(b).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(b)
				swing = maxf(swing, rad_to_deg(Vector3.UP.angle_to(d * Vector3.UP)))
		var bad := []
		if nan: bad.append("NaN")
		if low < -0.04: bad.append("under floor")
		if reach > 1.5: bad.append("exploding")
		if bad.size() > 0: bad_n += 1
		print("%s | %.2f | %s | %.3f | %.3f | %.0f | %.2f | %s" % [c[0], anim.length,
			"loop" if anim.loop_mode != Animation.LOOP_NONE else "-", sink, low, swing, reach,
			"OK" if bad.is_empty() else ", ".join(bad)])
	print("METRICS_DONE clips=%d flagged=%d" % [_clips.size(), bad_n])


# --- stop-motion frames ------------------------------------------------------------------
# <out>/<clip>/frame00000000.png ... at --fps (default 12), side view, 240x330, then
#   SRC_FPS=12 bash tools/qa/video_to_sheets.sh <out>/<clip> <sheets>/<clip> 12 8 3 200

func _stopmotion_step() -> bool:
	if _sm_model == null:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.86, 0.85, 0.8)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.8, 0.8, 0.85)
		e.ambient_light_energy = 0.7
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 25, 0)
		sun.light_energy = 1.2
		root.add_child(sun)
		var fl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 0.03, 2.0)
		fl.mesh = bm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.5, 0.45, 0.38)
		fl.material_override = fm
		fl.position = Vector3(0, -0.015, 0)
		root.add_child(fl)
		_sm_model = Assets.character("Player", 1.8, [])
		_sm_model.rotation_degrees.y = 0.0 if _front else 90.0
		root.add_child(_sm_model)
		_sm_ap = Assets.animation_player(_sm_model)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.size = 2.4
		cam.position = Vector3(0, 1.05, 12)
		root.add_child(cam)
		cam.make_current()
		return false
	if _sm_clip >= _clips.size():
		print("STOPMOTION_DONE ", _clips.size(), " clips -> ", _out)
		return true
	var c: Array = _clips[_sm_clip]
	var anim: Animation = c[1]
	if _sm_frame == 0 and _sm_wait == 0:
		if _sm_ap.has_animation_library("free"):
			_sm_ap.remove_animation_library("free")
		var lib := AnimationLibrary.new()
		lib.add_animation("clip", anim.duplicate(true))
		_sm_ap.add_animation_library("free", lib)
		_sm_ap.play("free/clip")
		DirAccess.make_dir_recursive_absolute("%s/%s" % [_out, c[0]])
	var t := minf(float(_sm_frame) / _fps, anim.length)
	if _sm_wait == 0:
		_sm_ap.seek(t, true)
		_sm_ap.pause()
		_sm_wait = 2
		return false
	_sm_wait -= 1
	if _sm_wait > 0:
		return false
	root.get_texture().get_image().save_png("%s/%s/frame%08d.png" % [_out, c[0], _sm_frame + 1])
	_sm_frame += 1
	if float(_sm_frame) / _fps > anim.length + 0.0001:
		_sm_clip += 1
		_sm_frame = 0
	return false
