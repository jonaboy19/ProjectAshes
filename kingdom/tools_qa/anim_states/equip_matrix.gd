extends SceneTree
## Equipment x state test matrix (owner request: weapon / equipment handling AAA). Windowed, one Godot:
##   godot --path kingdom --resolution 1280x720 -s res://tools_qa/anim_states/equip_matrix.gd -- --out=<dir> [--only=sword,axe] [--states=idle,walk]
## For every loadout the real Player (adult) is dressed through Life.equipment.equip(), then driven through the states below with its own
## input path. Per state it records, for every prop on the hands / forearm (starter gear and Eq_* items):
##   jump_cm / jump_deg : largest one-frame change of the prop's transform RELATIVE TO ITS BONE (props must never fling or snap)
##   grip_cm            : distance prop origin <-> bone origin (the grip must sit in the fist)
##   ground_cm          : how far the prop's lowest AABB corner goes below the floor
##   body_cm            : deepest AABB corner inside the torso capsule (pelvis..neck, r = 0.16) away from the holding hand
## and saves one tile sheet per loadout (<out>/sheet_<loadout>.png) plus matrix.csv.
const BASE := 600.0
const LOADOUTS := {
	"unarmed": [],
	"dagger": ["bronze_dagger"],
	"sword": ["bronze_sword"],
	"sword_shield": ["bronze_sword", "bronze_shield"],
	"greatsword": ["iron_greatsword"],
	"axe": ["bronze_axe"],
	"warhammer": ["iron_warhammer"],
	"spear": ["bronze_spear"],
	"shortbow": ["ash_shortbow"],
	"staff": ["ash_staff"],
}
const STATES := [
	["idle", 1.0], ["walk", 1.4], ["sprint", 1.4], ["strafe_l", 1.0], ["crouch", 1.0], ["jump", 1.4], ["dodge", 1.4],
	["attack", 1.6], ["block", 1.2], ["hit", 1.0], ["death", 1.6],
]
var _p: CharacterBody3D
var _sk: Skeleton3D
var _cam: Camera3D
var _out := "user://equip"
var _prev := {}
var _rows: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _build_world() -> void:
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
	sun.rotation_degrees = Vector3(-40, 60, 0)
	r3.add_child(sun)
	var fb := StaticBody3D.new()
	fb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	fb.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	mi.position = Vector3(0, 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.52, 0.45)
	mi.material_override = m
	fb.add_child(mi)
	r3.add_child(fb)
	fb.position = Vector3(0, BASE - 0.5, 0)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	_p.view = 1
	_cam = Camera3D.new()
	r3.add_child(_cam)
	_cam.current = true
	_cam.fov = 38


func _aim_camera() -> void:
	var pp := _p.global_position
	_cam.global_position = pp + Vector3(2.3, 1.35, -2.1)
	_cam.look_at(pp + Vector3(0, 0.95, 0))


func _run() -> void:
	var only: PackedStringArray = []
	var states: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",", false)
		elif a.begins_with("--states="):
			states = a.substr(9).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	_build_world()
	var life: Node = root.get_node("Life")
	life.life_path.set_age(16, root.get_node("WorldSim").day, root.get_node("WorldSim").time_of_day)
	_p.apply_age()
	for i in 45:
		await physics_frame
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0]
	_rows.append("loadout,state,prop,jump_cm,jump_deg,grip_cm,ground_cm,body_cm")
	for lo: String in LOADOUTS:
		if not only.is_empty() and not only.has(lo):
			continue
		await _dress(life, LOADOUTS[lo])
		var tiles: Array[Image] = []
		for st: Array in STATES:
			if not states.is_empty() and not states.has(String(st[0])):
				continue
			var img := await _state(lo, String(st[0]), float(st[1]))
			if img != null:
				tiles.append(img)
		_save_sheet(lo, tiles)
	var f := FileAccess.open(_out.path_join("matrix.csv"), FileAccess.WRITE)
	f.store_string("\n".join(_rows) + "\n")
	f.close()
	print("EQUIP_MATRIX_DONE ", _rows.size())
	quit()


func _dress(life: Node, items: Array) -> void:
	var eq: Object = life.equipment
	for slot: String in ["main_hand", "off_hand"]:
		if eq.has_method("unequip"):
			eq.call("unequip", slot)
	for id in items:
		eq.call("equip", String(id))
	_reset_player()
	for i in 40:
		await physics_frame


func _reset_player() -> void:
	_p.global_position = Vector3(0, BASE, 0)
	_p.velocity = Vector3.ZERO
	_p.rotation = Vector3.ZERO
	if _p.dead:
		_p.call("revive") if _p.has_method("revive") else null
	_prev.clear()
	for a in ["move_forward", "move_left", "move_right", "sprint", "crouch", "block", "jump"]:
		Input.action_release(a)


func _props() -> Array:
	var out: Array = []
	for att in _sk.find_children("*", "BoneAttachment3D", false, false):
		var b := att as BoneAttachment3D
		if not ["hand_r", "hand_l", "lowerarm_l", "spine_03", "pelvis"].has(b.bone_name):
			continue
		for c in b.get_children():
			if c is Node3D and (c as Node3D).is_visible_in_tree():
				out.append([c, b.bone_name])
	return out


func _bone_xf(name: String) -> Transform3D:
	var i := _sk.find_bone(name)
	return _sk.global_transform * _sk.get_bone_global_pose(i) if i >= 0 else Transform3D.IDENTITY


func _measure(stats: Dictionary) -> void:
	var pel := _bone_xf("pelvis").origin
	var neck := _bone_xf("neck_01").origin
	var ab := neck - pel
	for e: Array in _props():
		var node: Node3D = e[0]
		var bone := String(e[1])
		var bxf := _bone_xf(bone)
		var key := "%s@%s" % [node.name, bone]
		var rel := bxf.affine_inverse() * node.global_transform
		var s: Dictionary = stats.get(key, {"jump": 0.0, "deg": 0.0, "grip": 0.0, "ground": 0.0, "body": 0.0})
		if _prev.has(key):
			var pr: Transform3D = _prev[key]
			s["jump"] = maxf(s["jump"], (rel.origin - pr.origin).length() * bxf.basis.get_scale().x * 100.0)
			s["deg"] = maxf(s["deg"], rad_to_deg(rel.basis.get_rotation_quaternion().angle_to(pr.basis.get_rotation_quaternion())))
		_prev[key] = rel
		s["grip"] = maxf(s["grip"], (node.global_position - bxf.origin).length() * 100.0)
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			if mi.mesh == null:
				continue
			for pt: Vector3 in _verts(mi.mesh):
				var c := mi.global_transform * pt
				if c.y < BASE - 0.005:
					s["ground"] = maxf(s["ground"], (BASE - 0.005) - c.y)
				if c.distance_to(bxf.origin) < 0.22:
					continue
				var t := clampf((c - pel).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				s["body"] = maxf(s["body"], 0.16 - c.distance_to(pel + ab * t))
		stats[key] = s


var _vcache := {}


func _verts(mesh: Mesh) -> PackedVector3Array:
	if _vcache.has(mesh):
		return _vcache[mesh]
	var f := mesh.get_faces()
	var out := PackedVector3Array()
	var step := maxi(1, f.size() / 300)
	var i := 0
	while i < f.size():
		out.append(f[i])
		i += step
	_vcache[mesh] = out
	return out


func _state(lo: String, st: String, secs: float) -> Image:
	_reset_player()
	for i in 20:
		await physics_frame
	_aim_camera()
	var stats := {}
	var t := 0.0
	var img: Image = null
	var did_cap := false
	var fired := false
	match st:
		"walk":
			Input.action_press("move_forward", 1.0)
		"sprint":
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"strafe_l":
			Input.action_press("move_left")
		"crouch":
			Input.action_press("crouch")
			Input.action_press("move_forward", 0.6)
		"block":
			Input.action_press("block")
	while t < secs:
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		_aim_camera()
		if not fired and t > 0.25:
			fired = true
			match st:
				"jump":
					_p.call("jump")
				"dodge":
					_p.call("dodge")
				"attack":
					_p.call("attack")
				"hit":
					_p.call("take_damage", 3, null, Vector3(0, 0, 3.0), true)
				"death":
					_p.call("take_damage", 9999, null, Vector3.ZERO, true)
		if st == "attack" and t > 0.9 and t < 0.92:
			_p.call("attack")
		if t > 0.3:
			_measure(stats)
		if not did_cap and t >= secs * 0.55:
			did_cap = true
			img = root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	for a in ["move_forward", "move_left", "sprint", "crouch", "block"]:
		Input.action_release(a)
	if stats.is_empty():
		_rows.append("%s,%s,(no prop),0,0,0,0,0" % [lo, st])
	for key: String in stats:
		var s: Dictionary = stats[key]
		_rows.append("%s,%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f" % [lo, st, key, s["jump"], s["deg"], s["grip"], s["ground"] * 100.0, maxf(s["body"], 0.0) * 100.0])
	if st == "death":
		_p.call("revive") if _p.has_method("revive") else null
	if img != null:
		var d := Image.create(640, 380, false, Image.FORMAT_RGB8)
		d.fill(Color.WHITE)
		d.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i(0, 20))
		_label(d, "%s / %s" % [lo, st])
		return d
	return null


func _label(img: Image, text: String) -> void:
	# no font rendering on Images in headless-free scripts: draw a coloured bar per state index instead (names are in the CSV / file order)
	img.fill_rect(Rect2i(0, 0, 640, 18), Color(0.15, 0.15, 0.2))


func _save_sheet(lo: String, tiles: Array[Image]) -> void:
	if tiles.is_empty():
		return
	var cols := 3
	var rows := (tiles.size() + cols - 1) / cols
	var sheet := Image.create(640 * cols, 380 * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color.WHITE)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 640, 380), Vector2i((i % cols) * 640, (i / cols) * 380))
	sheet.save_png(_out.path_join("sheet_%s.png" % lo))
