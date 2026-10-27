extends SceneTree
## MPFB pilot clip check (CHARACTER_PLAN.md step 6): the pilot body plays UAL / Mixamo-retargeted clips through the normal
## Assets.mh_character path (same AnimationPlayer library as every UAL character). One clip after another, side camera.
##   godot --path kingdom --fixed-fps 30 --write-movie out.avi -s res://tools_qa/anim_states/mpfb_clip_check.gd -- [--file=res://...glb]
const CLIPS := ["Idle", "Walk", "Jog_Fwd", "Mx_Run_Fast", "Sitting_Idle", "Life_Farm_Hoe", "Sword_Regular_A", "Mx_Walk_Standard", "Crouch_Fwd"]
const SECS := 1.6
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var file := "res://assets/generated/characters/mpfb/villager_man"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			file = a.substr(7).trim_suffix(".glb")
	var r3 := Node3D.new()
	root.add_child(r3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	r3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	r3.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.38, 0.32)
	floor_mi.material_override = fm
	r3.add_child(floor_mi)
	var body: Node3D = Assets.mh_character(file, 1.78, [])
	r3.add_child(body)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(si) as BaseMaterial3D
			if mat and (String(m3.name).contains("eyebrow") or String(m3.name).contains("short")):
				var c := mat.duplicate() as BaseMaterial3D
				c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				c.alpha_scissor_threshold = 0.5
				m3.set_surface_override_material(si, c)
	var ap: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
	_cam = Camera3D.new()
	_cam.fov = 38.0
	r3.add_child(_cam)
	_cam.global_position = Vector3(3.4, 1.05, 0.9)
	_cam.look_at(Vector3(0, 0.9, 0))
	_cam.current = true
	for c in CLIPS:
		if not ap.has_animation(c):
			print("MPFBCHECK missing ", c)
			continue
		ap.play(c)
		print("MPFBCHECK ", c, " len ", ap.get_animation(c).length)
		var t := 0.0
		while t < SECS:
			await process_frame
			t += 1.0 / 30.0
			body.position = Vector3.ZERO
	quit()
