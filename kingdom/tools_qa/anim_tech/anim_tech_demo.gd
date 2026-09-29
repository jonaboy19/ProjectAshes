extends Node3D
## Advanced runtime animation techniques on Godot 4.6 built-ins, one demo per technique, all on
## the Quaternius UAL 65-bone character (Assets.character). See docs/anim/advanced/tech/README.md.
##
## Interactive (F5 / F6 on anim_tech_demo.tscn):
##   1..0 = technique demo, T = toggle the technique ON/OFF on the demo character (where it applies),
##   H = hit the demo dummy (flinch / ragdoll / shake demos), N/P = next/previous technique.
##
## Headless-friendly capture (writes PNG frame strips; needs a real renderer, hidden window is fine):
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim_tech/anim_tech_demo.tscn \
##         -- --capture=<absolute dir> [--tech=foot_ik,look_at | all]
## Perf (ms per character per frame, N = 1/10/25/50):
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim_tech/anim_tech_demo.tscn \
##         -- --bench=<absolute json path> [--tech=...]
## Each technique lives in techs/t_<id>.gd (extends RefCounted, `run(d)` coroutine) and the reusable
## parts in lib/.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Hitstop := preload("res://tools_qa/anim_tech/lib/hitstop.gd")
const CameraShake := preload("res://tools_qa/anim_tech/lib/camera_shake.gd")
const TECH_DIR := "res://tools_qa/anim_tech/techs/"
## id -> title. The order is the key order (1..0) too.
const TECHS := [
	["foot_ik", "1 Foot IK / ground alignment (TwoBoneIK3D)"],
	["look_at", "2 Head look-at (LookAtModifier3D)"],
	["springs", "3 Cape / hair spring bones (SpringBoneSimulator3D)"],
	["ragdoll", "4 Full ragdoll + partial (upper-body) ragdoll"],
	["flinch", "5 Additive directional hit flinch (OneShot ADD)"],
	["lean", "6 Velocity lean + spine twist to aim"],
	["blendtree", "7 Synced locomotion blend space"],
	["rootmotion", "8 Root-motion attack lunge"],
	["impact", "9 Hitstop + camera shake"],
	["warp", "10 Motion warping to a target"],
	["ik_survey", "11 IK solver survey (Two-bone / CCD / FABRIK / Jacobian / Spline)"],
]

var cam: Camera3D
var shake: Node
var hitstop: Node
var stage: Node3D            # everything a technique adds; freed between techniques
var hud: Label
var caption: Label
var tech_on := true          # T key: technique on/off for interactive use
var last_hit := false        # H key latch (techs poll it)
var out_dir := ""
var bench_path := ""
var only: PackedStringArray = []
var gen := 0                 # incremented to cancel a running technique
var capturing := false
var frames: Array[Image] = []
var _current := ""
var _sun: DirectionalLight3D

const WIN := Vector2i(800, 600)
const TILE := Vector2i(400, 300)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			out_dir = a.substr(10)
		elif a.begins_with("--bench="):
			bench_path = a.substr(8)
		elif a.begins_with("--tech="):
			only = a.substr(7).split(",", false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	capturing = out_dir != ""
	_build_environment()
	_build_ui()
	hitstop = Hitstop.new()
	add_child(hitstop)
	shake = CameraShake.new()
	shake.camera = cam
	add_child(shake)
	if capturing or bench_path != "":
		get_window().size = WIN
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_batch.call_deferred()
	else:
		start_tech.call_deferred("foot_ik")


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		start_tech(TECHS[k - KEY_1][0])
	elif k == KEY_0:
		start_tech(TECHS[9][0])
	elif k == KEY_N or k == KEY_P:
		var i := 0
		for j in TECHS.size():
			if TECHS[j][0] == _current:
				i = j
		start_tech(TECHS[(i + (1 if k == KEY_N else TECHS.size() - 1)) % TECHS.size()][0])
	elif k == KEY_T:
		tech_on = not tech_on
	elif k == KEY_H:
		last_hit = true


# --- batch (capture / bench) ---------------------------------------------------------

func _batch() -> void:
	await get_tree().create_timer(1.0).timeout
	var ids: Array[String] = []
	for t: Array in TECHS:
		if only.is_empty() or only.has("all") or only.has(t[0]):
			ids.append(t[0])
	if capturing:
		DirAccess.make_dir_recursive_absolute(out_dir)
		for id in ids:
			print("[anim_tech] capture ", id)
			await start_tech(id)
	else:
		var Bench := load("res://tools_qa/anim_tech/bench.gd")
		await Bench.new().run(self, ids, bench_path)
	print("[anim_tech] done")
	get_tree().quit()


## Starts a technique demo (cancels the running one). In batch mode this awaits its completion.
func start_tech(id: String) -> void:
	gen += 1
	var my := gen
	_current = id
	_clear_stage()
	tech_on = true
	last_hit = false
	frames.clear()
	Engine.time_scale = 1.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	var title := ""
	for t: Array in TECHS:
		if t[0] == id:
			title = t[1]
	hud.text = title + ("" if capturing else "   [T] on/off  [H] hit  [N/P] next/prev  [1-0] pick")
	var script := load(TECH_DIR + "t_%s.gd" % id) as GDScript
	if script == null:
		push_error("missing technique script for " + id)
		return
	var t: RefCounted = script.new()
	await t.run(self, my)
	if not capturing and my == gen:
		# Interactive: loop the scripted demo until another one is picked.
		while my == gen:
			_clear_stage()
			await t.run(self, my)


func alive(my: int) -> bool:
	return my == gen and is_inside_tree()


## Waits `sec` (real scene time). Returns false when the demo was cancelled.
func wait(sec: float, my: int) -> bool:
	if sec > 0.0:
		await get_tree().create_timer(sec, true, false, false).timeout
	return alive(my)


# --- stage helpers -------------------------------------------------------------------

func _clear_stage() -> void:
	if stage and is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	for l in caption.get_children():
		l.queue_free()
	caption.text = ""


func set_cam(pos: Vector3, look: Vector3, fov := 40.0) -> void:
	cam.fov = fov
	cam.position = pos
	cam.look_at(look, Vector3.UP)


## Static collider + visible box. `rot_deg` in degrees (XYZ). Returns the body.
func add_box(pos: Vector3, size: Vector3, rot_deg := Vector3.ZERO, color := Color(0.78, 0.72, 0.6)) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.transform = Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	b.add_child(mi)
	stage.add_child(b)
	return b


## Stairs along +X starting at (x0, base_y): `steps` treads of `run` x `rise`, width `w` (z).
func add_stairs(x0: float, base_y: float, z: float, w: float, steps: int, rise: float, run: float) -> void:
	for i in steps:
		var top := base_y + rise * (i + 1)
		add_box(Vector3(x0 + run * (i + 0.5), (base_y + top) * 0.5 - 0.0, z), Vector3(run, top - base_y, w), Vector3.ZERO, Color(0.80, 0.74, 0.62))


## Ramp whose top surface goes from (x0, y0) to (x1, y1) along X (either direction), width `w`.
func add_ramp(x0: float, y0: float, x1: float, y1: float, z: float, w: float, color := Color(0.55, 0.72, 0.38)) -> void:
	var d := Vector2(x1 - x0, y1 - y0)
	var dn := d.normalized()
	var n := Vector2(-dn.y, dn.x)
	var thick := 0.5
	var c := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5) - n * thick * 0.5
	var basis := Basis(Vector3(dn.x, dn.y, 0), Vector3(n.x, n.y, 0), Vector3.BACK)
	var b := add_box(Vector3(c.x, c.y, z), Vector3(d.length(), thick, w), Vector3.ZERO, color)
	b.transform = Transform3D(basis, Vector3(c.x, c.y, z))


## Loads a UAL character standing at `pos` facing `yaw` (radians, 0 = +Z). Returns
## {actor, model, sk, ap} (actor is the Node3D you move; model its child).
func spawn(pos: Vector3, yaw := 0.0, height := 1.8, look := "Player") -> Dictionary:
	var actor := Node3D.new()
	actor.name = "Actor"
	stage.add_child(actor)
	actor.position = pos
	actor.rotation.y = yaw
	var model: Node3D = Assets.character(look, height, [])
	actor.add_child(model)
	var ap := Assets.animation_player(model)
	return {"actor": actor, "model": model, "sk": U.skeleton_of(model), "ap": ap}


func label3d(text: String, at: Vector3, size := 0.0035) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = size
	l.font_size = 40
	l.outline_size = 12
	l.no_depth_test = true
	l.modulate = Color(1, 1, 1)
	stage.add_child(l)
	l.position = at
	return l


func say(text: String) -> void:
	caption.text = text


# --- capture -------------------------------------------------------------------------

## Grabs the current frame into the strip (capture mode only).
func snap() -> void:
	if not capturing:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	frames.append(img)


## Writes the collected frames as one strip (`cols` per row) to <out>/<name>.png and clears them.
func write_strip(strip_name: String, cols := 5) -> void:
	if not capturing or frames.is_empty():
		return
	var rows := ceili(float(frames.size()) / cols)
	var img := Image.create_empty(TILE.x * mini(cols, frames.size()), TILE.y * rows, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for i in frames.size():
		img.blit_rect(frames[i], Rect2i(Vector2i.ZERO, TILE), Vector2i((i % cols) * TILE.x, (i / cols) * TILE.y))
	var path := out_dir.path_join(strip_name + ".png")
	img.save_png(path)
	print("[anim_tech] wrote ", path, " (", frames.size(), " frames)")
	frames.clear()


# --- environment / ui ----------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.36, 0.60, 0.92)
	pm.sky_horizon_color = Color(0.80, 0.88, 0.96)
	pm.ground_bottom_color = Color(0.45, 0.55, 0.35)
	pm.ground_horizon_color = Color(0.80, 0.88, 0.96)
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.95, 0.82)
	_sun.light_energy = 1.4
	_sun.rotation_degrees = Vector3(-48, 35, 0)
	_sun.shadow_enabled = true
	add_child(_sun)
	# permanent floor: top at y = 0, layer 1 (what ragdoll.gd / procedural_rig.gd probe)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 1, 80)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.74, 0.36)
	mat.roughness = 1.0
	mi.material_override = mat
	floor_body.add_child(mi)
	add_child(floor_body)
	cam = Camera3D.new()
	cam.current = true
	cam.far = 200.0
	add_child(cam)
	cam.position = Vector3(0, 1.5, 6)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 6)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud)
	caption = Label.new()
	caption.position = Vector2(10, WIN.y - 34)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(caption)
