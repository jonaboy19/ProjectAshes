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
	["idle", 1.0], ["dodge_fwd", 1.4], ["walk", 1.4], ["sprint", 1.4], ["strafe_l", 1.0], ["crouch", 1.0], ["jump", 1.4], ["dodge", 1.4],
	["attack", 1.6], ["block", 1.2], ["hit", 1.0], ["death", 1.6],
	["block_hit", 1.8], ["hit_front", 1.4], ["hit_back", 1.4], ["hit_left", 1.4], ["hit_heavy", 2.0],
]
var _p: CharacterBody3D
var _sk: Skeleton3D
var _cam: Camera3D
var _out := "user://equip"
var _prev := {}
var _rows: PackedStringArray = []
var _strip := ""          # --strip=dodge_fwd: 8 frames of that state per loadout -> strip_<loadout>_<state>.png
var _strip_imgs: Array[Image] = []
var _skin_check := false   # --skin: body_cm against the real skinned body (CPU-skinned vertices) instead of the capsule
var _cam_off := Vector3(2.3, 1.35, -2.1)   # --cam=back / --cam=side


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
	_cam.global_position = pp + _cam_off
	_cam.look_at(pp + Vector3(0, 0.95, 0))


func _run() -> void:
	var only: PackedStringArray = []
	var states: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",", false)
		elif a.begins_with("--strip="):
			_strip = a.substr(8)
		elif a == "--skin":
			_skin_check = true
		elif a == "--cam=back":
			_cam_off = Vector3(-2.3, 1.45, 2.1)
		elif a == "--cam=side":
			_cam_off = Vector3(3.1, 1.2, 0.0)
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
		_p.call("set_sheathed", lo == "unarmed", true)   # unarmed = the sheathed stance (owner: no fists item)
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
		_p.call("revive", false) if _p.has_method("revive") else null
	_prev.clear()
	_p.set("_shield_ready", 0.0)   # no combat linger carried over from the previous state (shield back on the back)
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
		# a prop on a back socket rides the back, not the hand: the jump is the smaller of the bone and spine_03 frames
		var sxf := _bone_xf("spine_03")
		var rel_s := sxf.affine_inverse() * node.global_transform
		var s: Dictionary = stats.get(key, {"jump": 0.0, "deg": 0.0, "grip": 0.0, "ground": 0.0, "body": 0.0})
		if _prev.has(key):
			var pr: Transform3D = _prev[key]
			var ps: Transform3D = _prev[key + "#s"]
			var j_b := (rel.origin - pr.origin).length() * bxf.basis.get_scale().x * 100.0
			var j_s := (rel_s.origin - ps.origin).length() * sxf.basis.get_scale().x * 100.0
			var d_b := rad_to_deg(rel.basis.get_rotation_quaternion().angle_to(pr.basis.get_rotation_quaternion()))
			var d_s := rad_to_deg(rel_s.basis.get_rotation_quaternion().angle_to(ps.basis.get_rotation_quaternion()))
			s["jump"] = maxf(s["jump"], minf(j_b, j_s))
			s["deg"] = maxf(s["deg"], minf(d_b, d_s))
		_prev[key] = rel
		_prev[key + "#s"] = rel_s
		s["grip"] = maxf(s["grip"], (node.global_position - bxf.origin).length() * 100.0)
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			if mi.mesh == null:
				continue
			for pt: Vector3 in _verts(mi.mesh):
				var c := mi.global_transform * pt
				if c.y < BASE - 0.005:
					s["ground"] = maxf(s["ground"], (BASE - 0.005) - c.y)
					if OS.has_environment("EQ_DEBUG"):
						var rig: Node = _p.get("_rig")
						print("GROUNDDBG ", node.name, " y=", c.y - BASE, " floor=", _p.is_on_floor(), " gy=", rig.get("ground_guard_y") if rig else -1, " f=", Engine.get_physics_frames(), " stale=", (_bone_xf(bone).origin - (node.get_parent() as Node3D).global_position).length())
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
		"block", "block_hit":
			Input.action_press("block")
		"dodge_fwd":
			Input.action_press("move_forward")
	while t < secs:
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		_aim_camera()
		if not fired and t > (0.6 if st == "block_hit" else 0.25):
			fired = true
			match st:
				"jump":
					_p.call("jump")
				"dodge", "dodge_fwd":
					_p.call("dodge")
				"attack":
					_p.call("attack")
				"hit":
					_p.call("take_damage", 3, null, Vector3(0, 0, 3.0), true)
				"block_hit", "hit_front", "hit_back", "hit_left", "hit_heavy":
					# an attacker 1.5 m away on that side (front for the block), real (non-forced) blow
					var side := {"block_hit": 0.0, "hit_front": 0.0, "hit_heavy": 0.0, "hit_back": PI, "hit_left": PI * 0.5}
					var dir: Vector3 = _p.call("facing")
					var foe := Node3D.new()
					root.add_child(foe)
					foe.global_position = _p.global_position + dir.rotated(Vector3.UP, float(side[st])) * 1.5
					_p.call("take_damage", 40 if st == "hit_heavy" else 8, foe, Vector3.ZERO, false)
					foe.queue_free()
				"death":
					_p.call("take_damage", 9999, null, Vector3.ZERO, true)
		if st == "attack" and t > 0.9 and t < 0.92:
			_p.call("attack")
		if t > 0.3:
			_measure(stats)
			if OS.has_environment("EQ_DEBUG") and Engine.get_process_frames() % 3 == 0:
				print("POSDBG ", lo, " ", st, " y=", snappedf(_p.global_position.y - BASE, 0.01), " floor=", _p.is_on_floor(), " layer=", _p.collision_layer, " dead=", _p.dead, " lean=", _p.get("_rig").get("_lean") if _p.get("_rig") else null, " stun=", _p.get("_stunned"))
			if _skin_check and Engine.get_process_frames() % 4 == 0:
				_measure_skin(stats)
		if st == _strip and _strip_imgs.size() < 8 and t >= 0.25 + _strip_imgs.size() * (secs - 0.3) / 8.0:
			var si := root.get_texture().get_image()
			si.convert(Image.FORMAT_RGB8)
			si.resize(480, 270, Image.INTERPOLATE_LANCZOS)
			_strip_imgs.append(si)
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
		var body := maxf(float(s.get("skin", 0.0)) if _skin_check else float(s["body"]), 0.0) * 100.0
		_rows.append("%s,%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f" % [lo, st, key, s["jump"], s["deg"], s["grip"], s["ground"] * 100.0, body])
	if st == _strip and not _strip_imgs.is_empty():
		var sh := Image.create(480 * 4, 270 * 2, false, Image.FORMAT_RGB8)
		for i in _strip_imgs.size():
			sh.blit_rect(_strip_imgs[i], Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
		sh.save_png(_out.path_join("strip_%s_%s.png" % [lo, st]))
		_strip_imgs.clear()
	if st == "death":
		_p.call("revive", false) if _p.has_method("revive") else null
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


## Real-skin penetration (--skin): CPU-skins the body meshes (every 3rd vertex) and, for each prop vertex, finds the nearest body
## vertex; a prop vertex counts as inside when it lies on the inner side of that vertex's normal. Reports the deepest (cm) as
## skin_cm in the stats (column body_cm is replaced when --skin is on). Ignores the holding hand / forearm region (0.12 m).
var _body_cache := {}


func _skinned(mi: MeshInstance3D) -> Array:
	var key := mi.get_instance_id()
	if not _body_cache.has(key):
		var arr := mi.mesh.surface_get_arrays(0)
		_body_cache[key] = arr
	var a: Array = _body_cache[key]
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bs.size() / maxi(vs.size(), 1)
	var skin := mi.skin
	var sk := _sk
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mats.append(sk.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(b))
	var xf := mi.global_transform
	var out_p := PackedVector3Array()
	var out_n := PackedVector3Array()
	var i := 0
	while i < vs.size():
		var m := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		for k in per:
			var w := ws[i * per + k]
			if w <= 0.0:
				continue
			var t: Transform3D = mats[bs[i * per + k]]
			m.basis.x += t.basis.x * w
			m.basis.y += t.basis.y * w
			m.basis.z += t.basis.z * w
			m.origin += t.origin * w
		out_p.append(xf * (m * vs[i]))
		out_n.append((xf.basis * (m.basis * ns[i])).normalized())
		i += 3
	return [out_p, out_n]


func _measure_skin(stats: Dictionary) -> void:
	var body_p := PackedVector3Array()
	var body_n := PackedVector3Array()
	for mi: MeshInstance3D in _sk.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var r := _skinned(mi)
		body_p.append_array(r[0])
		body_n.append_array(r[1])
	for e: Array in _props():
		var node: Node3D = e[0]
		var bone := String(e[1])
		var hand := _bone_xf(bone).origin
		var key := "%s@%s" % [node.name, bone]
		var deepest := 0.0
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			if mi.mesh == null:
				continue
			for pt: Vector3 in _verts(mi.mesh):
				var c := mi.global_transform * pt
				if c.distance_to(hand) < 0.2 or (bone == "lowerarm_l" and c.distance_to(_bone_xf("hand_l").origin) < 0.2):   # the grip / strap: worn contact
					continue
				# the 4 nearest skin vertices within 8 cm: inside only when the point is behind ALL of their surfaces (one tilted normal
				# near a fold must not count), depth = the smallest of the four
				var near: Array = []
				for j in body_p.size():
					var d := c.distance_squared_to(body_p[j])
					if d < 0.0064:
						near.append([d, j])
				if near.size() < 4:
					continue
				near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				var depth := 1e9
				for q in 4:
					var j: int = near[q][1]
					depth = minf(depth, (body_p[j] - c).dot(body_n[j]))
				deepest = maxf(deepest, depth)
				if OS.has_environment("SKIN_DBG") and depth > 0.03:
					var sx := _bone_xf("spine_03")
					print("SKINDBG ", node.name, " d=", snappedf(depth, 0.001), " prop_in_spine=", (sx.affine_inverse() * c).snapped(Vector3(0.01,0.01,0.01)) * sx.basis.get_scale().x, " skin_y_above_floor=", snappedf(body_p[near[0][1]].y - BASE, 0.01), " t=", Engine.get_physics_frames())
		var s: Dictionary = stats.get(key, {})
		s["skin"] = maxf(float(s.get("skin", 0.0)), deepest)
		stats[key] = s
