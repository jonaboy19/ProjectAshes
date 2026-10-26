extends SceneTree
## Movie Maker rig for the locomotion feet (B3 visual gate): the real Player walks / sprints along a 0.25 m grid, side camera
## follows at constant distance, so a skating planted foot slides against the grid lines.
##   godot --path kingdom --fixed-fps 30 --write-movie out.png -s res://tools_qa/anim_states/loco_movie.gd -- --case=walk|sprint|slow [--no-lock] --seconds=4
const BASE := 600.0
var _p: CharacterBody3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case := "walk"
	var seconds := 4.0
	var lock := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case = a.substr(7)
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a == "--no-lock":
			lock = false
	var r3 := Node3D.new()
	root.add_child(r3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	r3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	r3.add_child(sun)
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
render_mode unshaded;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz / 0.25 + 0.5) - 0.5) / fwidth(w.xz / 0.25);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 g2 = abs(fract(w.xz + 0.5) - 0.5) / fwidth(w.xz);
	float l2 = 1.0 - min(min(g2.x, g2.y), 1.0);
	vec3 c = vec3(0.62, 0.58, 0.5);
	c = mix(c, vec3(0.35, 0.33, 0.28), l * 0.8);
	c = mix(c, vec3(0.1, 0.05, 0.05), l2);
	ALBEDO = c;
}"""
	sm.shader = shd
	mi.material_override = sm
	fb.add_child(mi)
	r3.add_child(fb)
	fb.position = Vector3(0, BASE - 0.5, 0)
	# vertical grid wall behind the walker (camera looks along -X): its lines are fixed in world Z, so a skating planted foot slides across them
	var wall := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(120, 6)
	wall.mesh = qm
	wall.rotation_degrees = Vector3(0, 90, 0)
	wall.position = Vector3(-3.0, BASE + 2.0, -40.0)
	var wsm := ShaderMaterial.new()
	var wsh := Shader.new()
	wsh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = vec2(w.z, w.y);
	vec2 g = abs(fract(q / 0.25 + 0.5) - 0.5) / fwidth(q / 0.25);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 g2 = abs(fract(q + 0.5) - 0.5) / fwidth(q);
	float l2 = 1.0 - min(min(g2.x, g2.y), 1.0);
	vec3 c = vec3(0.85, 0.87, 0.9);
	c = mix(c, vec3(0.45, 0.5, 0.58), l * 0.9);
	c = mix(c, vec3(0.8, 0.1, 0.1), l2);
	ALBEDO = c;
}"""
	wsm.shader = wsh
	wall.material_override = wsm
	r3.add_child(wall)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	_p.view = 1
	_cam = Camera3D.new()
	r3.add_child(_cam)
	_cam.current = true
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.4
	for i in 40:
		await physics_frame
	var rig: Node = _p.get("_rig")
	if OS.get_cmdline_user_args().has("--only_hands"):
		for n in _p.find_children("*", "MeshInstance3D", true, false):
			if not String(n.name).contains("hands"):
				(n as Node3D).visible = false
	if OS.get_cmdline_user_args().has("--list_attach"):
		for n in _p.find_children("*", "MeshInstance3D", true, false):
			var mi3 := n as MeshInstance3D
			if mi3.is_visible_in_tree():
				var bb := mi3.global_transform * mi3.get_aabb()
				print("MESH %s size=%s centre=%s" % [str(mi3.get_path()).get_slice("@Node3D@35/", 1), bb.size.snapped(Vector3(0.01, 0.01, 0.01)), bb.get_center().snapped(Vector3(0.01, 0.01, 0.01))])
		for att in _p.find_children("*", "BoneAttachment3D", true, false):
			var names: Array = []
			for c in att.get_children():
				names.append("%s rot=%s pos=%s" % [c.name, (c as Node3D).rotation_degrees, (c as Node3D).position])
			print("ATT ", att.name, " bone=", (att as BoneAttachment3D).bone_name, " ", names)
	if OS.get_cmdline_user_args().has("--adult"):
		var life: Node = root.get_node("Life")
		life.life_path.set_age(16, root.get_node("WorldSim").day, root.get_node("WorldSim").time_of_day)
		_p.apply_age()
	if case != "idle":
		Input.action_press("move_forward", 0.4 if case == "slow" else 1.0)
	if case == "sprint":
		Input.action_press("sprint")
	var t := 0.0
	var fired := false
	while t < seconds:
		if OS.get_cmdline_user_args().has("--attack") and t > 0.8 and not fired:
			fired = true
			(_p.get("_animator") as RefCounted).call("play_full", "Sword_Regular_A", 1.0)
		await physics_frame
		await process_frame
		_apply_sword_rot()
		t += 1.0 / 60.0
		var pp := _p.global_position
		if OS.get_cmdline_user_args().has("--front"):
			_cam.global_position = Vector3(pp.x, BASE + 0.9, pp.z - 4.0)      # the player walks toward -Z: this camera sees the face
		elif OS.get_cmdline_user_args().has("--three_quarter"):
			_cam.global_position = Vector3(pp.x + 3.0, BASE + 1.0, pp.z - 3.0)
		else:
			_cam.global_position = Vector3(pp.x + 4.0, BASE + 0.9, pp.z)
		_cam.look_at(Vector3(pp.x, BASE + 0.9, pp.z))
	Input.action_release("move_forward")
	Input.action_release("sprint")
	quit()


func _apply_sword_rot() -> void:
	# The rig's prop springs rewrite every prop's transform from its captured rest transform each frame: change the rest.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sword_rot="):
			var v := a.substr(12).split(",")
			var rig: Node = _p.get("_rig")
			if rig == null:
				return
			for pr: Dictionary in rig.get("_props"):
				var node: Node3D = pr["node"]
				if not is_instance_valid(node) or not String(node.name).begins_with("Sword"):
					continue
				if not pr.has("rest0"):
					pr["rest0"] = pr["rest"]
				var r0: Transform3D = pr["rest0"]
				var sc := r0.basis.get_scale()
				pr["rest"] = Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(v[0])), deg_to_rad(float(v[1])), deg_to_rad(float(v[2])))).scaled(sc), r0.origin)
