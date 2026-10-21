extends Node3D
## Effekseer demo + perf probe (plugin 1.80.5.1, GDExtension). The effect is the CC0 "Aura01" sample from the
## Effekseer editor, converted with tools_qa/vfx_flipbooks/efk_import.gd. NOT wired into the game.
##   Godot --path kingdom --rendering-method mobile --resolution 1280x720 res://tools_qa/vfx_flipbooks/effekseer_demo.tscn -- --n=6 [--perf] [--shot=<png>]
## On gl_compatibility the extension loads but draws nothing (needs RenderingDevice): gate on RenderingServer.get_current_rendering_method().
const EFFECT := "res://assets/vfx/effekseer/00_Version16/aura01.res"
var _n := 6
var _perf := false
var _shot := ""
var _pf := 0
var _pcpu := 0.0
var _pgpu := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			_n = int(a.substr(4))
		elif a == "--perf":
			_perf = true
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
	if not ClassDB.class_exists("EffekseerEmitter3D"):
		printerr("Effekseer extension not loaded")
		get_tree().quit(1)
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.position = Vector3(0, 2.4, 13.0)
	cam.look_at(Vector3(0, 1.5, 0))
	var eff := load(EFFECT)
	for i in _n:
		var em: Node3D = ClassDB.instantiate("EffekseerEmitter3D")
		em.set("effect", eff)
		em.position = Vector3(-7.5 + (i % 6) * 3.0, 0, -(i / 6) * 2.5)
		add_child(em)
		em.call("play")
	print("EFK rendering_method=", RenderingServer.get_current_rendering_method(), " n=", _n)


func _process(_d: float) -> void:
	_pf += 1
	var vp := get_viewport().get_viewport_rid()
	if _perf:
		if _pf == 1:
			RenderingServer.viewport_set_measure_render_time(vp, true)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		if _pf > 60:
			_pcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			_pgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if _pf == 240:
			print("PERF efekseer n=%d cpu_ms=%.2f gpu_ms=%.2f draw_calls=%d fps=%d" % [_n, _pcpu / 180.0, _pgpu / 180.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), Engine.get_frames_per_second()])
			get_tree().quit()
	elif _shot != "" and _pf == 90:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
