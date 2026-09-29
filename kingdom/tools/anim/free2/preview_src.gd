extends SceneTree
## Renders the ORIGINAL KayKit mannequin playing source clips (ground truth to compare a retarget with).
##   godot --path kingdom -s tools/anim/free2/preview_src.gd -- --pack=Simulation --clips=Sit_Floor_Idle,Waving --out=C:/out.png [--frames=8]
const ROOT := "res://assets/incoming/kaykit/character-animations/"
var _pack := "Simulation"
var _clips: PackedStringArray = []
var _out := "user://src.png"
var _frames := 8
var _tick := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="): _pack = a.substr(7)
		elif a.begins_with("--clips="): _clips = a.substr(8).split(",")
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--frames="): _frames = int(a.substr(9))
	DisplayServer.window_set_size(Vector2i(_frames * 200, _clips.size() * 275))
	root.size = Vector2i(_frames * 200, _clips.size() * 275)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.85, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	root.add_child(env); env.environment = e
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 25, 0); root.add_child(sun)
	var src: Node = load(ROOT + "Animations/gltf/Rig_Medium/Rig_Medium_%s.glb" % _pack).instantiate()
	var sap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var cw := 1.6; var rh := 2.2
	var rows := _clips.size()
	for r in rows:
		var m: Node3D = load(ROOT + "Mannequin Character/characters/Mannequin_Medium.glb").instantiate()
		var probe := m
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0] if m.find_children("*", "AnimationPlayer", true, false).size() > 0 else null
		m.free()
		for c in _frames:
			var mm: Node3D = load(ROOT + "Mannequin Character/characters/Mannequin_Medium.glb").instantiate()
			mm.position = Vector3(-cw * (_frames - 1) * 0.5 + c * cw, rh * rows * 0.5 - (r + 1) * rh + 0.15, 0)
			mm.rotation_degrees.y = 90
			mm.scale = Vector3.ONE * 1.2
			root.add_child(mm)
			var sk: Skeleton3D = mm.find_children("*", "Skeleton3D", true, false)[0]
			var p := AnimationPlayer.new()
			mm.add_child(p)
			p.root_node = p.get_path_to(mm)
			var a: Animation = sap.get_animation(_clips[r]).duplicate(true)
			# retarget track paths to the mannequin's skeleton
			var skpath := String(mm.get_path_to(sk))
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(skpath + tp.substr(colon)))
			var lib := AnimationLibrary.new(); lib.add_animation("c", a); p.add_animation_library("", lib)
			p.play("c"); p.seek(a.length * float(c) / float(_frames - 1), true); p.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rh * rows; cam.position = Vector3(0, 0, 12)
	root.add_child(cam); cam.make_current()

func _process(_d: float) -> bool:
	_tick += 1
	if _tick == 10:
		root.get_texture().get_image().save_png(_out)
		return true
	return false
