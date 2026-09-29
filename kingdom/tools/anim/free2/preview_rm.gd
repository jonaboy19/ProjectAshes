extends SceneTree
## Filmstrip renderer WITH root motion and simple collision props (ladder, ledge, vault box, horse).
## Character faces +X (right of the image). One row per clip, N columns = N moments of the clip.
##   godot --path kingdom -s tools/anim/free2/preview_rm.gd -- --glb=<abs glb> --out=<png> --clip=Name --prop=ladder \
##         [--frames=8] [--cell=1.6] [--height=3.0] [--from=0] [--to=1] [--front]
var _glb := ""
var _out := "user://rm.png"
var _clip := ""
var _prop := ""
var _frames := 8
var _cell := 1.6
var _height := 3.0
var _t0 := 0.0
var _t1 := 1.0
var _front := false
var _tick := 0
var _anim: Animation
var _sk_path := ""
var _w := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): _glb = a.substr(6)
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--clip="): _clip = a.substr(7)
		elif a.begins_with("--prop="): _prop = a.substr(7)
		elif a.begins_with("--frames="): _frames = int(a.substr(9))
		elif a.begins_with("--cell="): _cell = float(a.substr(7))
		elif a.begins_with("--height="): _height = float(a.substr(9))
		elif a.begins_with("--from="): _t0 = float(a.substr(7))
		elif a.begins_with("--to="): _t1 = float(a.substr(5))
		elif a == "--front": _front = true
	var probe := Assets.character("Player", 1.8, [])
	var ap0 := Assets.animation_player(probe)
	for n in ap0.get_animation_list():
		var a0 := ap0.get_animation(n)
		if a0.get_track_count() > 0:
			var tp := String(a0.track_get_path(0))
			_sk_path = tp.substr(0, tp.find(":"))
			break
	probe.free()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(_glb, st)
	var inst := doc.generate_scene(st)
	var src: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	for n in src.get_animation_list():
		if n == _clip or n == _clip + "_Loop":
			_anim = src.get_animation(n).duplicate(true)
	if _anim == null:
		print("CLIP NOT FOUND ", _clip, " in ", src.get_animation_list())
		quit()
		return
	for t in _anim.get_track_count():
		var tp := String(_anim.track_get_path(t))
		var colon := tp.find(":")
		if colon > 0:
			_anim.track_set_path(t, NodePath(_sk_path + tp.substr(colon)))
	inst.free()
	var w := int(_frames * _cell * 130)
	_w = w
	var h := int(_height * 130)
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)

func _build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.85, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.7
	root.add_child(env); env.environment = e
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 25, 0); sun.light_energy = 1.2; root.add_child(sun)
	var x0 := -_cell * (_frames - 1) * 0.5
	var y_bot := -_height * 0.5 + 0.1
	# floor
	var fl := _box(Vector3(_cell * _frames, 0.04, 1.0), Vector3(0, y_bot - 0.02, 0), Color(0.5, 0.45, 0.38))
	for c in _frames:
		var t := _t0 * _anim.length + (_t1 - _t0) * _anim.length * float(c) / float(maxi(_frames - 1, 1))
		var cx := x0 + c * _cell
		_props(Vector3(cx, y_bot, 0))
		var m := Assets.character("Player", 1.8, [])
		m.position = Vector3(cx, y_bot, 0)
		m.rotation_degrees.y = 0.0 if _front else 90.0
		root.add_child(m)
		var ap := Assets.animation_player(m)
		var lib := AnimationLibrary.new()
		lib.add_animation("clip", _anim.duplicate(true))
		ap.add_animation_library("rm", lib)
		ap.play("rm/clip"); ap.seek(t, true); ap.pause()
		var tl := Label3D.new()
		tl.text = "%.2f" % t; tl.font_size = 26; tl.pixel_size = 0.004; tl.modulate = Color(0.2, 0.2, 0.2)
		tl.position = Vector3(cx - 0.4, y_bot + 0.06, 0.7)
		root.add_child(tl)
	var lbl := Label3D.new()
	lbl.text = "%s  %.2fs  prop=%s" % [_clip, _anim.length, _prop]
	lbl.font_size = 40; lbl.pixel_size = 0.004; lbl.modulate = Color(0.05, 0.05, 0.05)
	lbl.position = Vector3(x0 - _cell * 0.4, y_bot + _height - 0.3, 0.8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(lbl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = _height; cam.position = Vector3(0, 0, 12)
	root.add_child(cam); cam.make_current()

func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi

func _props(o: Vector3) -> void:
	# o = floor point under the character; character faces +X; z axis = depth (toward camera)
	match _prop:
		"ladder":
			var wood := Color(0.55, 0.38, 0.2)
			for rz in [-0.22, 0.22]:
				_box(Vector3(0.05, 6.0, 0.05), o + Vector3(0.30, 3.0, rz), wood)
			for i in range(1, 20):
				_box(Vector3(0.09, 0.07, 0.5), o + Vector3(0.30, 0.3 * i, 0), Color(0.35, 0.22, 0.1))
		"ledge":
			_box(Vector3(1.0, 2.1, 1.2), o + Vector3(0.25 + 0.5, 1.05, 0), Color(0.6, 0.58, 0.55))
		"wall":
			_box(Vector3(0.3, 6.0, 1.4), o + Vector3(0.15 + 0.22, 3.0, 0), Color(0.6, 0.58, 0.55))
		"vault":
			_box(Vector3(0.5, 0.9, 1.6), o + Vector3(1.0, 0.45, 0), Color(0.6, 0.45, 0.3))
		"horse":
			var hc := Color(0.45, 0.28, 0.16)
			_box(Vector3(1.9, 0.5, 0.55), o + Vector3(0.0, 1.1 - 0.2, 0), hc)          # body
			_box(Vector3(0.3, 0.7, 0.35), o + Vector3(1.05, 1.55, 0), hc)              # neck
			_box(Vector3(0.5, 0.25, 0.25), o + Vector3(1.35, 1.9, 0), hc)              # head
			for lx in [-0.7, 0.7]:
				for lz in [-0.18, 0.18]:
					_box(Vector3(0.12, 0.85, 0.12), o + Vector3(lx, 0.42, lz), hc.darkened(0.2))
			_box(Vector3(0.55, 0.06, 0.6), o + Vector3(0.0, 0.96, 0), Color(0.3, 0.2, 0.1))   # saddle

func _process(_d: float) -> bool:
	_tick += 1
	if _tick == 2:
		_build()
	if _tick == 14:
		root.get_texture().get_image().save_png(_out)
		print("SAVED ", _out)
		return true
	return false
