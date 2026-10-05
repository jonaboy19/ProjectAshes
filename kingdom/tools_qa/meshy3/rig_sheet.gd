extends SceneTree
## Pose sheet of the Meshy batch 3 characters re-rigged onto the UAL skeleton (assets/incoming/meshy_dl3/characters_ual):
## rows = characters, columns = UAL clips at a fixed time, so a bad weight / exploding plate shows up. Loaded through the game's own
## Assets.mh_character (UAL clips, track-path rewrite), so it proves the villager looks path works.
##   xvfb-run -a -s "-screen 0 1800x1000x24" Godot --path kingdom --rendering-driver vulkan --resolution 1800x1000 \
##       -s res://tools_qa/meshy3/rig_sheet.gd -- --out=<abs png> [--only=a,b]
const DIR := "res://assets/incoming/meshy_dl3/characters_ual/"
const CLIPS := [["Idle", 0.5], ["Walk", 0.25], ["Jog_Fwd", 0.6], ["Sword_Regular_A", 0.45], ["Sit_Floor_Idle", 0.5], ["Death01", 0.9]]
var out := ""
var only: PackedStringArray = []
var line := false          # --line: one clip, characters side by side at a low camera (easier to judge weights)
var clips: Array = CLIPS
var frame := 0
var world: Node3D
var cam: Camera3D
var aps: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
		elif a.begins_with("--line="):
			line = true
			var kv := a.substr(7).split(":")
			clips = [[kv[0], float(kv[1])]]
	world = Node3D.new()
	root.add_child.call_deferred(world)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 10:
		_build()
	elif frame == 30:
		_pose()
	elif frame == 60:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


func _names() -> Array[String]:
	var res: Array[String] = []
	var files := Array(DirAccess.get_files_at(DIR))
	files.sort()
	for f: String in files:
		if f.ends_with(".glb") and not f.ends_with("_lod1.glb"):
			var n := f.get_basename()
			if only.is_empty() or only.has(n):
				res.append(n)
	return res


func _build() -> void:
	WorldGen.setup(WorldSim.SEED)
	var SG: GDScript = load("res://scripts/style_g.gd")
	var env: Environment = SG.make_environment("low")
	var sun: DirectionalLight3D = SG.make_sun("low")
	var fill: DirectionalLight3D = SG.make_fill()
	world.add_child(sun)
	world.add_child(fill)
	SG.apply_daylight(env, sun, fill, 15.0)
	env.fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fb28a")
	var names := _names()
	if line:
		for r in names.size():
			var n: Node3D = Assets.mh_character(DIR + names[r], 1.75)
			world.add_child(n)
			n.position = Vector3(r * 2.2, 0, 0)
			aps.append([Assets.animation_player(n), clips[0]])
			var l := Label3D.new()
			l.text = names[r]
			l.font_size = 28
			l.pixel_size = 0.006
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.position = n.position + Vector3(0, 2.1, 0)
			world.add_child(l)
		cam = Camera3D.new()
		cam.environment = env
		world.add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = names.size() * 2.2 * 0.56 + 1.0
		var m1 := Vector3((names.size() - 1) * 1.1, 1.0, 0)
		cam.position = m1 + Vector3(0, 3, 20)
		cam.look_at(m1)
		cam.current = true
		return
	for r in names.size():
		for c in clips.size():
			var n: Node3D = Assets.mh_character(DIR + names[r], 1.75)
			world.add_child(n)
			n.position = Vector3(c * 2.4, 0, r * 3.0)
			aps.append([Assets.animation_player(n), clips[c]])
			var l := Label3D.new()
			l.text = names[r] if c == 0 else String(clips[c][0])
			l.font_size = 30
			l.pixel_size = 0.006
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.position = n.position + Vector3(0, 2.0, 0)
			world.add_child(l)
	cam = Camera3D.new()
	cam.environment = env
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var rows := float(names.size())
	cam.size = maxf(rows * 3.0 * 0.78, clips.size() * 2.4 * 0.58) + 2.5
	var mid := Vector3((clips.size() - 1) * 1.2, 0.9, (rows - 1) * 1.5)
	cam.position = mid + Vector3(0, 19, 23)
	cam.look_at(mid)
	cam.current = true


func _pose() -> void:
	for e: Array in aps:
		var ap := e[0] as AnimationPlayer
		var clip: Array = e[1]
		if ap != null and ap.has_animation(clip[0]):
			ap.play(clip[0])
			ap.seek(float(clip[1]) * ap.get_animation(clip[0]).length, true)
			ap.pause()
		elif ap != null:
			print("missing clip ", clip[0])
