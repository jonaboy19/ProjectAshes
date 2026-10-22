extends Node3D
## Flipbook VFX gallery: the six baked sheets in a row on the storybook stage, replayed every PERIOD seconds.
##   --mode=new   (default) the new flipbooks
##   --mode=old   the closest existing ElementFX effect for each slot (for side-by-side review)
##   --mode=grid  the raw atlases laid out flat, no animation (sanity check of the sheets)
## Capture (windowed, never --headless):
##   Godot --path kingdom --rendering-method mobile --resolution 1280x720 --write-movie <dir>/f.png --fixed-fps 30 --quit-after 150 res://tools_qa/vfx_flipbooks/flipbook_gallery.tscn -- --mode=new
##   Then tools/qa/video_to_sheets.sh <dir> <out> 10 4 3
## Extra user args: --tier=0..3, --perf (average CPU/GPU render ms + draw calls over 180 frames, then quit).

const FX := preload("res://scripts/vfx/flipbook_fx.gd")
const PERIOD := 2.4
const SLOTS := [
	# new flipbook, closest existing element effect (element, type)
	[&"fire_burst", &"fire", &"impact"],
	[&"smoke_puff", &"dark", &"impact"],
	[&"dust_burst", &"earth", &"impact"],
	[&"water_splash", &"water", &"impact"],
	[&"lightning_sheet", &"lightning", &"aoe"],
	[&"magic_swirl", &"light", &"aoe"],
]

var _mode := "new"
var _t := 0.0
var _live: Array = []
var _perf := false
var _pf := 0
var _pcpu := 0.0
var _pgpu := 0.0
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a == "--perf":
			_perf = true
		elif a.begins_with("--tier="):
			var q := get_node_or_null("/root/Quality")
			if q:
				q.set("tier", int(a.substr(7)))
	_build_stage()
	if _mode == "grid":
		_build_grid()
	else:
		_spawn()


func _slot_x(i: int) -> float:
	return -6.25 + i * 2.5


func _spawn() -> void:
	_t = 0.0
	for i in SLOTS.size():
		var pos := Vector3(_slot_x(i), 0.0, 0.0)
		if _mode == "new":
			FX.play(SLOTS[i][0], pos, 1.0, Color.WHITE, self)
		else:
			ElementFX.play(SLOTS[i][1], SLOTS[i][2], pos, Vector3.ZERO, 1.0, self)


func _process(delta: float) -> void:
	if _mode == "grid":
		return
	_t += delta
	if _t >= PERIOD:
		_spawn()
	if _perf:
		var vp := get_viewport().get_viewport_rid()
		if _pf == 0:
			RenderingServer.viewport_set_measure_render_time(vp, true)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		_pf += 1
		if _pf > 60:
			_pcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			_pgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if _pf == 240:
			var n := 180.0
			print("PERF mode=%s cpu_ms=%.2f gpu_ms=%.2f draw_calls=%d fps=%d" % [_mode, _pcpu / n, _pgpu / n,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), Engine.get_frames_per_second()])
			get_tree().quit()


func _build_grid() -> void:
	for i in SLOTS.size():
		var m := FX.material_for(SLOTS[i][0])
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.8, 2.8)
		q.mesh = qm
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_texture = m.get_shader_parameter("atlas")
		q.material_override = sm
		q.position = Vector3(_slot_x(i), 1.5, 0)
		add_child(q)


func _build_stage() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/free/storybook_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.95)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.46, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	# warm stone pads under each effect, like the elements gallery
	for i in SLOTS.size():
		var d := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.05
		cyl.bottom_radius = 1.05
		cyl.height = 0.02
		d.mesh = cyl
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.6, 0.52, 0.4)
		sm.roughness = 1.0
		d.material_override = sm
		d.position = Vector3(_slot_x(i), 0.01, 0)
		add_child(d)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	add_child(_cam)
	_cam.position = Vector3(0, 2.2, 14.6)
	_cam.look_at(Vector3(0, 1.3, 0))
