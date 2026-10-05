extends Node3D
## P1 powers and VFX capture harness (standalone: no world boot, ~1 GB). Plays 4 techniques with the shared timing
## template (fire, water, earth, knight aura) and a torch-lit street at dusk, and logs draw calls.
##   xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan --write-movie /tmp/x/f.png \
##       --fixed-fps 30 --quit-after 450 res://tools_qa/aaa_vfx/vfx_standalone.tscn -- --tier=1
## Frames 0..~359 are the techniques (3 s each = 90 frames), the rest is the street. `--part=tech|street` runs one.

const TechniqueVfx := preload("res://scripts/vfx/technique_vfx.gd")
const LampGlow := preload("res://scripts/world/lamp_glow.gd")
const TorchProps := preload("res://scripts/world/torch_props.gd")
const Decals := preload("res://scripts/vfx/ground_decals.gd")

const SEG := 3.0
const TECHS := [
	{"id": "fire_bolt", "element": "fire", "shape": "projectile", "windup": 0.5, "radius": 2.5, "to": Vector3(0, 0, -6.5), "path": "magic"},
	{"id": "water_ring", "element": "water", "shape": "aoe", "windup": 0.5, "radius": 3.2, "to": Vector3(0, 0, -5.0), "path": "bending"},
	{"id": "earth_quake", "element": "earth", "shape": "aoe", "windup": 0.5, "radius": 4.0, "to": Vector3(0, 0, -4.5), "path": "bending"},
	{"id": "aura_cut", "element": "none", "shape": "melee", "windup": 0.4, "radius": 2.5, "to": Vector3(0, 0, -2.4), "path": "knight"},
]

var cam: Camera3D
var part := "both"
var tier := 1
var t := 0.0
var _tv: Node
var _char: Node3D
var _stage: Node3D
var _street: Node3D
var _seg := -1
var _max_draws := 0
var _street_started := false
var _lamps: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--part="):
			part = a.substr(7)
		elif a.begins_with("--tier="):
			tier = int(a.substr(7))
	var q := get_node_or_null("/root/Quality")
	if q:
		q.set("tier", tier)
	_env(false)
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	_stage = Node3D.new()
	add_child(_stage)
	_street = Node3D.new()
	add_child(_street)
	_street.visible = false
	_build_stage()
	_build_street()
	if part == "street":
		_start_street()


func _env(dusk: bool) -> void:
	var we := get_node_or_null("WE") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WE"
		add_child(we)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 30.0
		add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = tier >= 2
	env.glow_intensity = 0.45
	var sun_n := get_node("Sun") as DirectionalLight3D
	if dusk:
		env.background_color = Color(0.2, 0.15, 0.22)
		env.ambient_light_color = Color(0.32, 0.3, 0.42)
		env.ambient_light_energy = 0.7
		sun_n.light_color = Color(1.0, 0.55, 0.3)
		sun_n.light_energy = 0.35
		sun_n.rotation_degrees = Vector3(-8, -60, 0)
	else:
		env.background_color = Color(0.62, 0.74, 0.9)
		env.ambient_light_color = Color(0.62, 0.7, 0.95)
		env.ambient_light_energy = 0.9
		sun_n.light_color = Color(1.0, 0.86, 0.66)
		sun_n.light_energy = 1.4
		sun_n.rotation_degrees = Vector3(-42, -30, 0)
	we.environment = env


func _mat(c: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_stage() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	g.material_override = _mat(Color(0.62, 0.52, 0.4))
	g.position = Vector3(0, 0, -6)
	_stage.add_child(g)
	_char = Assets.character("Guard", 1.8, [])
	if _char == null:
		_char = Node3D.new()
		_box(_char, Vector3(0.5, 1.6, 0.3), Vector3(0, 0.8, 0), Color(0.2, 0.36, 0.72))
	_char.name = "Caster"
	_stage.add_child(_char)
	_char.rotation.y = PI    # the rig faces +Z; Godot forward is -Z
	for p in [Vector3(0, 0, -6.5), Vector3(0, 0, -5.0), Vector3(0, 0, -4.5), Vector3(0, 0, -2.4)]:
		pass
	var dummy := _box(_stage, Vector3(0.5, 1.5, 0.5), Vector3(0, 0.75, -7.0), Color(0.5, 0.35, 0.2))
	dummy.name = "Dummy"
	_tv = TechniqueVfx.new()
	_char.add_child(_tv)
	_tv.ctx = {
		"origin": func() -> Vector3: return _char.global_position + Vector3(0, 1.2, 0),
		"aim": func() -> Vector3: return Vector3.FORWARD,
		"world": func() -> Node: return self,
		"is_player": true, "skeleton_root": _char,
	}
	cam.position = Vector3(2.6, 1.7, 1.8)
	cam.look_at(Vector3(0, 1.0, -3.0))


func _build_street() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 60)
	g.mesh = pm
	g.material_override = _mat(Color(0.42, 0.36, 0.3))
	_street.add_child(g)
	var specs: Array = []
	for i in 6:
		var z := -2.0 - i * 5.0
		for side in [-1.0, 1.0]:
			var wall := _box(_street, Vector3(4.0, 5.0 + (i % 2), 4.5), Vector3(side * 5.2, 2.6, z), Color(0.72, 0.6, 0.45) if i % 2 == 0 else Color(0.62, 0.5, 0.4))
			wall.name = "House"
			_box(_street, Vector3(4.4, 0.5, 5.0), Vector3(side * 5.2, 5.4 + (i % 2), z), Color(0.5, 0.2, 0.15))
			_box(_street, Vector3(0.14, 3.0, 0.14), Vector3(side * 2.9, 1.5, z + 2.5), Color(0.25, 0.2, 0.17))   # lamp post
			specs.append({"pos": Vector3(side * 2.75, 3.1, z + 2.5), "color": Color(1.0, 0.7, 0.35), "range": 8.0, "size": 1.5})
			# lit window
			var win := _box(_street, Vector3(0.9, 1.0, 0.05), Vector3(side * 3.15, 2.6, z), Color(1.0, 0.7, 0.35))
			win.material_override = _mat(Color(1.0, 0.7, 0.35))
			(win.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			win.rotation.y = PI * 0.5
	for z in [-4.0, -14.0]:
		var br: Dictionary = TorchProps.brazier(_street, Vector3(0, 0, z))
		specs.append({"pos": br["glow_pos"], "color": Color(1.0, 0.55, 0.2), "range": 7.0, "size": 2.2})
	_lamps = LampGlow.build(_street, specs)


func _start_street() -> void:
	_street_started = true
	_stage.visible = false
	_street.visible = true
	_env(true)
	for l in _lamps:
		l.light_energy = 1.6
		(l as Node3D).visible = true
	cam.position = Vector3(0.0, 1.7, 3.5)
	cam.look_at(Vector3(0, 2.0, -16))


func _process(delta: float) -> void:
	t += delta
	var d := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_max_draws = maxi(_max_draws, d)
	if part != "street" and t < SEG * TECHS.size():
		var s := int(t / SEG)
		if s != _seg:
			_seg = s
			var row: Dictionary = TECHS[s]
			_tv.begin(String(row["id"]), _def(row), {"to": row["to"]})
			print("DRAWS before %s: %d (max so far %d)" % [row["id"], d, _max_draws])
	elif part != "tech" and not _street_started:
		_start_street()
		print("TECH max draws %d" % _max_draws)
		_max_draws = 0
	if _street_started:
		cam.position.z = 3.5 - minf(t - SEG * TECHS.size() if part != "street" else t, 4.0) * 0.8
	if int(t * 30.0) % 30 == 0:
		print("t=%.1f draws=%d prims=%d tier=%d live=%d decals=%d" % [t, d,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), tier,
			TechniqueVfx.Toon.live_count(), Decals.active_count()])


func _def(row: Dictionary) -> Dictionary:
	return {"id": row["id"], "element": row["element"], "path": row["path"], "tier": 3, "windup": row["windup"],
		"targeting": {"kind": row["shape"], "range": 8.0, "radius": row["radius"]}}
