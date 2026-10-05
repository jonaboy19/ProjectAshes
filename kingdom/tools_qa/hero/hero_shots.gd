extends SceneTree
## Tier-A hero proof shots (skill ashes-hero-character). Renders the default hero (lab_chars.hero_g path:
## G6 build_model + HeroOutfit) in Style G light, then optionally HeroTierA.upgrade():
##   turnaround (front, 3/4, side, back), face close-up, dialogue framing, gameplay shoulder camera (3.9 m, FOV 54),
##   and 6-frame clip strips (walk, run, combat, idle).
## godot --path kingdom --rendering-method mobile -s tools_qa/hero/hero_shots.gd -- --out=C:/tmp/hero/a [--baseline] [--probe] [--clips]
## Never --headless (needs a GPU). Prints PERF lines (tris per mesh, surfaces, materials).

const StyleG := preload("res://scripts/style_g.gd")
const CC := "res://scripts/ui/character_creation.gd"
const HERO_LOOK := {"sex": "male", "head": 2, "hair": 3, "hair_color": 3, "body": 0, "skin": 1}

var out := "user://hero"
var baseline := false


func _initialize() -> void:
	_run.call_deferred()


func _arg(k: String) -> bool:
	return k in OS.get_cmdline_user_args()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	baseline = _arg("--baseline")
	var root := Node3D.new()
	get_root().add_child(root)
	get_root().size = Vector2i(1200, 1200)
	var we := WorldEnvironment.new()
	we.environment = StyleG.make_environment("high")
	root.add_child(we)
	var sun := StyleG.make_sun("high")
	root.add_child(sun)
	StyleG.apply_sun(sun, "high")
	root.add_child(StyleG.make_fill())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = StyleG.material_for("ground")
	root.add_child(ground)
	if _arg("--meshy_lineup"):
		await _meshy_lineup(root)
		quit()
		return
	var meshy := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--meshy="):
			meshy = a.trim_prefix("--meshy=")
	var hero: Node3D
	if meshy != "":
		hero = Assets.mh_character(meshy if meshy.contains("/") else "res://assets/incoming/meshy_dl3/characters_ual/" + meshy, 1.78)
		root.add_child(hero)
		if not baseline:
			(load("res://scripts/actors/hero_tier_a.gd") as GDScript).call("upgrade_meshy", hero)
	else:
		hero = (load(CC) as GDScript).call("build_model", HERO_LOOK, 1.78, [] as Array[String])
		root.add_child(hero)
		var outfit: GDScript = load("res://scripts/actors/hero_outfit.gd")
		outfit.call("tint_tunic", hero)
		outfit.call("dress", hero)
	if meshy != "":
		pass
	elif baseline:
		_style_g_materials(hero)
		var ho := hero.find_children("HeroOutfit", "MeshInstance3D", true, false)
		if not ho.is_empty():
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.85
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			(ho[0] as MeshInstance3D).material_override = mat
	else:
		var tier: GDScript = load("res://scripts/actors/hero_tier_a.gd")
		tier.call("upgrade", hero)
	_perf(hero)
	if _arg("--probe"):
		quit()
		return
	var ap := Assets.animation_player(hero)
	var cam := Camera3D.new()
	root.add_child(cam)
	_pose(ap, "Idle", 0.4)
	var sk := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head_i := sk.find_bone("Head")
	for i in 4:
		await process_frame
	var head_p := (sk.global_transform * sk.get_bone_global_pose(head_i)).origin + Vector3(0, 0.08, 0)
	print("HEAD at ", head_p)
	# turnaround
	cam.fov = 30
	var views := {"front": Vector3(0, 1.2, 4.2), "front34": Vector3(-2.6, 1.3, 3.2), "side": Vector3(4.2, 1.2, 0.1), "back": Vector3(0.3, 1.3, -4.2)}
	for v in views:
		cam.position = views[v]
		cam.look_at(Vector3(0, 0.92, 0))
		await _shot("turn_" + v)
	# face close-up (front and 3/4) and dialogue framing (over the NPC's shoulder, chest-up, FOV 40)
	cam.fov = 22
	var face_p := head_p + Vector3(0, -0.05, 0.02)
	cam.position = face_p + Vector3(0.0, 0.02, 0.85)
	cam.look_at(face_p)
	await _shot("face_front")
	cam.position = face_p + Vector3(-0.55, 0.04, 0.65)
	cam.look_at(face_p)
	await _shot("face_34")
	cam.fov = 40
	cam.position = head_p + Vector3(0.45, -0.02, 1.35)
	cam.look_at(head_p + Vector3(-0.12, -0.12, 0))
	await _shot("dialogue")
	# gameplay shoulder camera: 3.9 m behind, FOV 54 (AAA camera spec), hero right of centre
	cam.fov = 54
	cam.position = Vector3(0.55, 2.0, -3.85)
	cam.look_at(Vector3(0.55, 1.35, 2.0))
	await _shot("shoulder_cam")
	if _arg("--clips"):
		await _clips(ap, cam, hero)
	quit()


func _pose(ap: AnimationPlayer, clip: String, t: float) -> void:
	if ap == null:
		return
	var c := clip
	if not ap.has_animation(c):
		for n in ap.get_animation_list():
			if String(n).contains(clip):
				c = n
				break
	if not ap.has_animation(c):
		return
	ap.play(c)
	ap.seek(t, true)
	ap.speed_scale = 0.0


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s_%s.png" % [out, name]
	get_root().get_texture().get_image().save_png(p)
	print("HERO_SHOT -> ", p)


## Frame strips for Codex's clips: 6 phases each, side view; written as separate images then tiled by the caller.
func _clips(ap: AnimationPlayer, cam: Camera3D, hero: Node3D) -> void:
	get_root().size = Vector2i(420, 560)
	cam.fov = 34
	var sets := {"walk": "Walk", "run": "Jog_Fwd", "sprint": "Sprint", "attack": "Sword_Regular_A", "roll": "Roll", "idle": "Idle"}
	for k in sets:
		var clip: String = sets[k]
		if not ap.has_animation(clip):
			print("CLIP missing ", clip)
			continue
		var ln := ap.get_animation(clip).length
		for i in 6:
			_pose(ap, clip, ln * (i + 0.5) / 6.0)
			for view in ["side", "back"]:
				cam.position = Vector3(3.6, 1.1, 0.4) if view == "side" else Vector3(0.6, 1.4, -3.4)
				cam.look_at(Vector3(0, 0.9, 0))
				await _shot("clip_%s_%s_%d" % [k, view, i])


func _style_g_materials(hero: Node3D) -> void:
	for mi in hero.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null or m.name == "HeroOutfit":
			continue
		var kind := 1
		var n := String(m.name).to_lower()
		if n.contains("hair") or n.contains("brow"):
			kind = 2
		elif n.contains("head") or n.contains("hand"):
			kind = 0
		elif n.contains("boot") or n.contains("glove"):
			kind = 3
		for si in m.mesh.get_surface_count():
			var mm := StyleG.material_for("hero_new", m.get_active_material(si), kind, "high")
			if mm:
				m.set_surface_override_material(si, mm)


func _perf(hero: Node3D) -> void:
	var total := 0
	var mats := {}
	for mi in hero.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var tris := 0
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := m.get_active_material(si)
			if mat:
				mats[mat.get_instance_id()] = true
		total += tris
		var aabb := m.get_aabb()
		print("PERF mesh %s tris=%d surf=%d aabb=%s" % [m.name, tris, m.mesh.get_surface_count(), aabb])
	print("PERF total_tris=%d materials=%d" % [total, mats.size()])


## The 7 Meshy dl3 characters already re-rigged to UAL: full body 3/4 + face, one pair of images each.
func _meshy_lineup(root: Node3D) -> void:
	var dir := "res://assets/incoming/meshy_dl3/characters_ual/"
	var cam := Camera3D.new()
	root.add_child(cam)
	for n in ["villager_green_vest", "peasant_hooded", "guardian_hooded", "merchant_cloaked", "villager_hat", "villager_white_shirt", "knight_plate_a"]:
		var m := Assets.mh_character(dir + n, 1.78)
		root.add_child(m)
		_perf(m)
		var ap := Assets.animation_player(m)
		_pose(ap, "Idle", 0.4)
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for i in 4:
			await process_frame
		var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin + Vector3(0, 0.03, 0)
		cam.fov = 30
		cam.position = Vector3(-1.8, 1.3, 3.4)
		cam.look_at(Vector3(0, 0.92, 0))
		await _shot("meshy_%s_body" % n)
		cam.fov = 22
		cam.position = hp + Vector3(-0.3, 0.02, 0.8)
		cam.look_at(hp)
		await _shot("meshy_%s_face" % n)
		m.queue_free()
