extends Node3D
## Standalone capture of the player's technique casts with the CMU bending clips: builds only the character (Assets.character
## + CharacterAnimator, the same as Player), a floor, a light and a camera, and runs the REAL TechniqueCaster on a stub body
## (no world, no HUD: about 1 GB instead of the 8 GB of a full game boot). One technique per element, a frame every
## third engine frame at the fixed 30 fps step as 480x270 JPG: <out>/<row>_<id>_<n>.jpg. Never --headless.
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan --fixed-fps 30 \
##       res://tools_qa/anim_tech/bending_cast_standalone.tscn -- --out=/tmp/claude-0/shots/bending_frames
## Tile with /tmp/claude-0/wireanims/make_sheet.py (session notes) or tools/qa/video_to_sheets.sh.

const Caster := preload("res://scripts/actors/technique_caster.gd")
const Skills := preload("res://scripts/sim/skills.gd")
const CASTS := [
	["fire_flame_wave", 2.4],        # Fire_Box_Combo_A (full)
	["water_tidal_crash", 2.4],      # Water_Dance_ArmsHigh (full)
	["wind_whirlwind", 2.4],         # Air_SpinJump_360 (full)
	["earth_quake", 2.4],            # Earth_PunchSeq_Deep (full)
	["lightning_spark", 2.4],        # Lightning_Point_Snap (upper)
	["qi_gathering", 3.0],           # Cultivate_Yoga_Floor_Flow (full), sect meditation
]
const STEP := 3


class StubBody extends Node3D:
	var stamina := 100.0
	var health := 100
	var dead := false
	var _animator: CharacterAnimator
	var _model: Node3D

	func facing() -> Vector3:
		return Vector3.FORWARD

	func heal(n: int) -> void:
		health += n

	func set_health(v: int) -> void:
		health = v


var out := "/tmp/claude-0/shots/bending_frames"
var body: StubBody
var caster: Node
var skills: RefCounted
var _anim_speed := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.4, 0.34)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	# A grid of marks on the floor so sliding and sinking read in the frames.
	for i in range(-4, 5):
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.01, 8.0)
		mark.mesh = box
		mark.position = Vector3(float(i) * 0.5, 0.006, 0.0)
		add_child(mark)
	body = StubBody.new()
	add_child(body)
	var model := Assets.character("Player", 1.8, [])
	body.add_child(model)
	model.rotation.y = PI
	body._model = model
	body._animator = CharacterAnimator.new(model, 5.8, 2.4, "Walking_A", "Running_A", "Idle", true, true)
	var cam := Camera3D.new()
	cam.position = Vector3(1.5, 1.2, -2.3)
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	skills = Skills.new()
	caster = Caster.new()
	caster.skills = skills
	body.add_child(caster)
	_run()


func _physics_process(delta: float) -> void:
	if body != null and body._animator != null:
		body._animator.update(delta, 0.0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _grab(tag: String, i: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(480, 270, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out.path_join("%s_%03d.jpg" % [tag, i]), 0.85)


func _run() -> void:
	await _frames(40)
	for row in CASTS.size():
		var id: String = CASTS[row][0]
		skills.grant(id)
		skills.qi = skills.qi_max()
		body.stamina = 100.0
		Life.magicules.max_pool = 400.0
		Life.magicules.current = 400.0
		await _frames(45)
		var r: Dictionary = caster.cast_technique(id)
		var d: Dictionary = (r.get("def", {}) as Dictionary)
		print("BENDCAP row=%d id=%s ok=%s reason=%s clip=%s" % [row, id, str(r.get("ok")), str(r.get("reason", "")), str(d.get("anim", ""))])
		var n := int(float(CASTS[row][1]) * 30.0)
		var i := 0
		for f in n:
			if f % STEP == 0:
				await _grab("%d_%s" % [row, id], i)
				i += 1
			else:
				await get_tree().process_frame
	print("BENDCAP DONE")
	get_tree().quit()
