extends SceneTree
## Villager face card QA (docs/art/FACES.md): every look file of Assets.MH_LOOKS with a NpcFaceCard, face shots at 1.6 m for
## neutral / angry / happy plus the debug card (solid magenta).
## godot --path kingdom --rendering-method mobile -s tools_qa/living_world/face_card_shots.gd -- --out=C:/tmp/cards [--only=villager_man_a,peasant_hooded] [--off=0,0.075,0.095 --size=0.11,0.1 --layout=-0.04,0.024,0.03,0.034]
const StyleG := preload("res://scripts/style_g.gd")
const NpcFaceCard := preload("res://scripts/living_world/npc_face_card.gd")
var out := "user://cards"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := PackedStringArray()
	var off_s := ""
	var size_s := ""
	var lay_s := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--off="):
			off_s = a.trim_prefix("--off=")
		elif a.begins_with("--layout="):
			lay_s = a.trim_prefix("--layout=")
		elif a.begins_with("--size="):
			size_s = a.trim_prefix("--size=")
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	get_root().size = Vector2i(600, 600)
	var we := WorldEnvironment.new()
	we.environment = StyleG.make_environment("high")
	root.add_child(we)
	var sun := StyleG.make_sun("high")
	root.add_child(sun)
	StyleG.apply_sun(sun, "high")
	root.add_child(StyleG.make_fill())
	var cam := Camera3D.new()
	cam.fov = 16
	root.add_child(cam)
	var files := {}
	for k in Assets.MH_LOOKS:
		for f in Assets.MH_LOOKS[k]:
			files[String(f)] = true
	for f in files:
		var short := String(f).get_file()
		if not only.is_empty() and not only.has(short):
			continue
		var body: Node3D = Assets.mh_character(String(f), 1.7, [] as Array[String], false, true)
		if body == null:
			continue
		root.add_child(body)
		var ap := Assets.animation_player(body)
		if ap and ap.has_animation("Idle"):
			ap.play("Idle")
			ap.seek(0.4, true)
			ap.speed_scale = 0.0
		var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var o := NpcFaceCard.offsets_for(short)
		var off: Array = o.get("offset", [])
		var sz: Array = o.get("size", [])
		var offv := Vector3(off[0], off[1], off[2]) if off.size() == 3 else NpcFaceCard.DEFAULT_OFFSET
		var szv := Vector2(sz[0], sz[1]) if sz.size() == 2 else NpcFaceCard.DEFAULT_SIZE
		if off_s != "":
			var v := off_s.split_floats(",")
			offv = Vector3(v[0], v[1], v[2])
		if size_s != "":
			var v2 := size_s.split_floats(",")
			szv = Vector2(v2[0], v2[1])
		var lay := NpcFaceCard.layout_of(o)
		if lay_s != "":
			var v3 := lay_s.split_floats(",")
			lay = Vector4(v3[0], v3[1], v3[2], v3[3])
		var card := NpcFaceCard.new(sk, offv, szv, false, lay)
		var sj: Array = o.get("skin", [])
		var skin_col := Color(sj[0], sj[1], sj[2]) if sj.size() == 3 else Color(0.85, 0.65, 0.55)
		for i in 10:
			await process_frame
		var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin + Vector3(0, 0.08 * body.scale.y, 0)
		cam.position = hp + Vector3(0, -0.03, 1.6)
		cam.look_at(hp + Vector3(0, -0.03, 0))
		for m in ["neutral", "angry", "happy", "surprise", "debug"]:
			card.set_debug(m == "debug")
			card.set_mood("angry" if m == "debug" else m)
			card.set_skin(skin_col)
			for i in 20:
				card.tick(1.0 / 60.0, true)
				await process_frame
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [out, short, m])

		print("LOOK ", short, " disabled=", o.get("disabled", false), " valid=", card.is_valid())
		body.queue_free()
		await process_frame
	quit()
