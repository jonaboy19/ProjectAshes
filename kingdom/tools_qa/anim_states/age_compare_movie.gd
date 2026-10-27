extends SceneTree
## Owner video: the child (game start, scale 0.58) and the adult player side by side on a 0.25 m grid, walking then sprinting
## with the same input, side camera following both. Movie Maker:
##   godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie out.avi -s res://tools_qa/anim_states/age_compare_movie.gd
const BASE := 600.0
var _a: CharacterBody3D
var _b: CharacterBody3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _floor(r3: Node3D) -> void:
	var fb := StaticBody3D.new()
	fb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(600, 1, 600)
	cs.shape = sh
	fb.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	mi.mesh = pm
	mi.position = Vector3(0, 0.5, 0)
	var sm := ShaderMaterial.new()
	var shd := Shader.new()
	shd.code = """shader_type spatial;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz / 0.25 + 0.5) - 0.5) / fwidth(w.xz / 0.25);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 g2 = abs(fract(w.xz + 0.5) - 0.5) / fwidth(w.xz);
	float l2 = 1.0 - min(min(g2.x, g2.y), 1.0);
	vec3 c = vec3(0.62, 0.58, 0.5);
	c = mix(c, vec3(0.35, 0.33, 0.28), l * 0.8);
	c = mix(c, vec3(0.15, 0.1, 0.08), l2);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}"""
	sm.shader = shd
	mi.material_override = sm
	fb.add_child(mi)
	r3.add_child(fb)
	fb.position = Vector3(0, BASE - 0.5, 0)


func _run() -> void:
	var r3 := Node3D.new()
	root.add_child(r3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.82, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	r3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	r3.add_child(sun)
	_floor(r3)
	var life: Node = root.get_node("Life")
	var ws: Node = root.get_node("WorldSim")
	_a = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_a)
	_a.global_position = Vector3(0.0, BASE, 0.0)
	_a.set("view", 1)
	for i in 10:
		await physics_frame
	life.life_path.set_age(4, ws.day, ws.time_of_day)
	_a.call("apply_age")
	_b = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_b)
	_b.global_position = Vector3(0.0, BASE, 1.8)
	_b.set("view", 1)
	for i in 10:
		await physics_frame
	life.life_path.set_age(16, ws.day, ws.time_of_day)
	_b.call("apply_age")
	_a.call("apply_age")      # keeps its own model scale; re-applied below each frame through _model.scale
	(_a.get("_model") as Node3D).scale = Vector3.ONE * 0.58
	var an: Object = _a.get("_animator")
	an.set("stride_scale", 0.58)
	_cam = Camera3D.new()
	r3.add_child(_cam)
	_cam.current = true
	_cam.fov = 40
	for i in 30:
		await physics_frame
	# walk 6 s, sprint 6 s
	Input.action_press("move_forward")
	await _follow(6.0)
	Input.action_press("sprint")
	await _follow(6.0)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _follow(1.5)
	quit()


func _follow(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await process_frame
		t += 1.0 / 30.0
		for p: CharacterBody3D in [_a, _b]:
			p.set("stamina", 100.0)
		var mid := (_a.global_position + _b.global_position) * 0.5
		_cam.global_position = mid + Vector3(5.0, 1.2, 0.0)
		_cam.look_at(mid + Vector3(0, 0.8, 0))
