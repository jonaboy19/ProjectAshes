extends Node3D
## Content review of staged AAA clips: instantiates each pack GLB (UAL skeleton + mannequin), loops the clip in place
## (root position disabled like the game does), up to 3 per page in a row, with a 1 m grid floor and a wall/edge prop
## option. Used to decide ADD?/CMP clips from frame sheets.
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim/aaa_review.tscn --write-movie o.png --fixed-fps 30
##         --quit-after N -- --clips=Locomotion:Run_Turn_Bank_L,Combat_Adv:Parry_High_Deflect [--view=q34|side|front] [--travel]

func _ready() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.84, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.58, 0.4)
	g.material_override = gm
	add_child(g)
	var clips: PackedStringArray = String(args.get("clips", "")).split(",", false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/anim/aaa_clips.json"))["packs"]
	var travel := args.has("travel")
	var n := mini(clips.size(), 3)
	for i in n:
		var pk := clips[i].get_slice(":", 0)
		var clip := clips[i].get_slice(":", 1)
		var path := "res://assets/incoming/animations/aaa/UAL_AAA_%s.glb" % pk
		var cell := Vector3((i - (n - 1) * 0.5) * 2.6, 0, 0)
		var model := Assets.mh_character(String(args.get("look", "villager_man_a")), 1.75, [])
		add_child(model)
		model.position = cell
		var ap := Assets.animation_player(model)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var skp := String(ap.get_node(ap.root_node).get_path_to(sk))
		var a: Animation
		var play_name := "rv/rv"
		var playback_len := 0.0
		if pk == "GAME" or pk == "LIFE":
			if pk == "LIFE":
				LifeLibrary.install(ap)
			if not ap.has_animation(clip):
				push_error("missing game clip " + clip)
				continue
			a = ap.get_animation(clip)
			play_name = clip
			playback_len = a.length
		else:
			var src: Node = (load(path) as PackedScene).instantiate()
			var sap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
			a = sap.get_animation(clip).duplicate(true)
			src.free()
			var decision: Dictionary = manifest.get(path, {}).get(clip, {})
			if decision.get("trim") is Array:
				AaaClips._trim(a, float(decision["trim"][0]), float(decision["trim"][1]))
			a.loop_mode = Animation.LOOP_LINEAR if bool(decision.get("loop", false)) else Animation.LOOP_NONE
			playback_len = a.length
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(skp + tp.substr(colon)))
					if not travel and tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						a.track_set_enabled(t, false)
			var lib := AnimationLibrary.new()
			lib.add_animation("rv", a)
			ap.add_animation_library("rv", lib)
		ap.play(play_name)
		var lbl := Label3D.new()
		lbl.text = "%s (%.1fs)" % [clip, playback_len]
		lbl.font_size = 36
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = cell + Vector3(0, 2.1, 0)
		lbl.modulate = Color(0.1, 0.1, 0.1)
		add_child(lbl)
		# 1 m grid cross so travel / floor contact reads.
		for k in range(-2, 3):
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.02, 0.01, 0.4)
			m.mesh = bm
			m.position = cell + Vector3(0, 0.01, k * 0.5)
			add_child(m)
	var cam := Camera3D.new()
	add_child(cam)
	var view := String(args.get("view", "q34"))
	var c := Vector3(0, 0.9, 0)
	match view:
		"side":
			cam.position = c + Vector3(-7.5, 0.5, 0)
		"front":
			cam.position = c + Vector3(0, 0.6, 7.0)
		_:
			cam.position = c + Vector3(1.0, 1.0, 7.2)
	cam.fov = 40
	cam.look_at(c)
