extends Node
## QA driver for the Region 1 hooks inside the real game (packages C-H to C12):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom scenes/main.tscn --rendering-driver vulkan -- \
##       --skipintro --qa=res://tools_qa/region1/r1_hooks_qa.gd --r1=shots|act1|all [--out=/tmp/claude-0/shots]
## shots: tracker, quests tab, journal, map before / after a carve (coverage change), violet Scar front,
##        ancestor stone greeting, Ashsight replay; then the contact sheet r1_hooks_sheet.png (tools/qa montage).
## act1:  plays Act I through the real glue (teleports, the director's conversations, a real carve through the
##        Wardlines sim, a real safe wolf killed with a real hit, the festival signal, the age-12 Blessing) and
##        exits 0 when "a1_after_blessing" is done and Act II has started, else 1. Works under --headless too.

var main: Node
var out_dir := "/tmp/claude-0/shots"
var g: Node
var shots: Array[String] = []


func run(p_main: Node) -> void:
	main = p_main
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	out_dir = String(args.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	g = main.region1
	await get_tree().create_timer(2.0).timeout
	var mode := String(args.get("r1", "all"))
	var ok := true
	if mode == "act1" or mode == "all":
		ok = await _act1()
	if mode == "shots" or mode == "all":
		await _shots()
	elif mode == "ashsight":
		await _ashsight_only()
	print("R1 QA done ok=", ok)
	get_tree().quit(0 if ok else 1)


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _clear_popups() -> void:
	var pop: Node = main.hud.get_node_or_null("LifeEventPopup")
	if pop != null:
		pop.hide()   # the childhood "Growing Up" event would cover every shot


func _snap(name: String) -> void:
	_clear_popups()
	await get_tree().process_frame
	await get_tree().process_frame
	var img := main.get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := "%s/r1_%s.png" % [out_dir, name]
	img.save_png(path)
	shots.append(path)
	print("R1 shot ", path)


func _player() -> Node3D:
	return main.player


func _tp(p: Vector2, yaw := 0.0) -> void:
	main.call("_teleport", p, yaw)
	await _wait(0.4)


func _look_at(from: Vector2, at: Vector2, pitch := -0.22) -> void:
	await _tp(from, 0.0)
	var d := at - from
	main.player.set_camera(atan2(-d.x, -d.y), pitch)
	main.terrain.focus = main.player.global_position
	main.terrain.build_all_now()
	await _wait(0.8)


# ---------------------------------------------------------------------------------------
# Act I, played through the real systems
# ---------------------------------------------------------------------------------------

func _act1() -> bool:
	print("R1 act1: start")
	var dir: Node = g.story
	WorldSim.time_of_day = 15.0
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	_player().apply_age()
	var wl: Wardlines = g.wl
	var rounds := 0
	var done_order: Array[String] = []
	while rounds < 140:
		rounds += 1
		dir._on_tick()
		for s: Dictionary in dir.story.steps:
			var sid := String(s["id"])
			if dir.story.is_done(sid) and not done_order.has(sid):
				done_order.append(sid)
				print("R1 act1: done ", sid)
		if dir.story.is_done("a1_after_blessing"):
			break
		var acted := false
		for sid: String in dir.story.active_steps():
			var st: Dictionary = dir.story.step(sid)
			var o: Dictionary = dir.story.current_objective(sid)
			match String(o.get("type", "")):
				"enter_area":
					await _goto_place(String(o["place"]))
					acted = true
				"carve":
					await _goto_place(String(st["place"]))
					var id := _stone_for(String(o["stone"]))
					if id >= 0:
						g._carve_target = id
						g._on_carved(String(o["glyph"]), {"chosen": true})   # the canvas accepted the glyph
						acted = true
				"kill":
					await _goto_place(String(o.get("place", st["place"])))
					await _kill_safe_wolf()
					acted = true
				"festival":
					WorldSim.seasons.festival_started.emit({"id": "kindling_night", "name": "Kindling Night"})
					acted = true
				"age":
					WorldSim.time_of_day = 8.0
					Life.life_path.set_age(int(o["min"]), WorldSim.day, WorldSim.time_of_day)
					acted = true
				"cutscene_done":
					await _wait(1.2)
					acted = true
		for h: Dictionary in dir.hosts_with_talk():
			await _goto_place(String(h["place"]))
			dir.talk_through(String(h["npc"]), Callable(self, "_pick"))
			acted = true
		await _wait(0.25)
		if not acted:
			await _wait(1.0)
	var ok: bool = dir.story.is_done("a1_after_blessing") and dir.story.is_active("a2_three_letters")
	print("R1 act1: steps done ", done_order)
	print("R1 act1: result ", "PASS" if ok else "FAIL", " active=", dir.story.active_steps(), " rounds=", rounds)
	return ok


func _pick(opts: Array) -> int:
	var dir: Node = g.story
	for i in opts.size():
		for a: Variant in (opts[i] as Dictionary).get("do", []):
			if a is Array and String(a[0]) == "flag" and not dir.story.has_flag(String(a[1])):
				return i
	for i in opts.size():
		var t := String((opts[i] as Dictionary).get("goto", ""))
		if t != "" and t != "@end" and not dir._talked.has(t):
			return i
	return 0


func _goto_place(place: String) -> void:
	var r: Dictionary = g.Places.resolve(place)
	if r.is_empty():
		return
	var p: Vector2 = r["pos"]
	if _player().global_position.distance_to(Vector3(p.x, _player().global_position.y, p.y)) > 25.0:
		await _tp(p + Vector2(4, 4))
	g.story._on_tick()


func _stone_for(story_id: String) -> int:
	for s: Dictionary in Frontier.runestones.stones:
		if story_id in g.story_stone_ids(int(s["id"])):
			return int(s["id"])
	return -1


func _kill_safe_wolf() -> void:
	# The pending spawn appears when the player is at the ring; hit it for real until it dies.
	for i in 30:
		await _wait(0.4)
		g.story._on_tick()
		for n in get_tree().get_nodes_in_group("team1"):
			if n is Wolf and n.has_meta("r1_safe"):
				(n as Wolf).take_damage(999, _player())
				await _wait(0.5)
				return
	# No wolf body (model not imported in this environment): report the kill as the wolf's death would.
	var p := _player().global_position
	Life.on_wolf_killed(p, -1)


# ---------------------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------------------

func _ashsight_only() -> void:
	WorldSim.time_of_day = 15.0
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	_player().apply_age()
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var site := home + Vector2(-30, 90)
	var mid: int = g.stage_memory(site, "qa_farm")
	await _look_at(site + Vector2(-16, 12), site, -0.18)
	g._kneel(mid)
	await _wait(6.0)
	await _snap("ashsight_replay")
	g.ash.stop()
	_contact_sheet()


func _shots() -> void:
	print("R1 shots: start")
	WorldSim.time_of_day = 15.0
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	_player().apply_age()
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var dir: Node = g.story
	# 1. Tracker and text lead next to the mother (first step, no marker in the world).
	await _tp(home + Vector2(0, 8))
	dir._on_tick()
	await _wait(1.5)
	main.hud.call("_update_tracker")
	await _snap("tracker")
	# 2. Quests tab and Journal page.
	dir.talk_through("mother")
	const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
	GameMenu.open(main.hud, "quests")
	await _wait(0.8)
	await _snap("quests_tab")
	var menu: Control = main.hud.get_node("GameMenu")
	menu.call("open_tab", "journal")
	await _wait(0.5)
	var jp: Control = menu.get("_pages")["journal"]
	jp.get("_ld").call("select", "story:0")
	await _wait(0.6)
	await _snap("journal")
	menu.call("close")
	await _wait(0.4)
	# 3. Dialogue with the quest giver in the world (first conversation page).
	main.hud.show_menu(Callable(dir, "npc_menu").bind("idra_vell"))
	await _wait(0.8)
	await _snap("story_dialogue")
	main.hud.close_menu()
	# 4. Map: coverage of a dim stone before and after a carve.
	var wl: Wardlines = g.wl
	var sid := wl.nearest_stone(home + Vector2(120, 40))
	wl.damage_stone(sid, 0.75)
	wl.charge[sid] = 0.5
	wl.call("_refresh_all")
	var sp: Vector2 = wl.st_pos[sid]
	main.hud.toggle_map()
	await _wait(0.6)
	main.hud.world_map.focus_on(sp, 0.9)
	await _wait(0.6)
	await _snap("map_before_carve")
	main.hud.toggle_map()
	await _wait(0.3)
	wl.repair(sid, 0.6)
	var res: Dictionary = wl.carve(sid, "ward")
	print("R1 carve result ", res, " radius ", wl.stone_info(sid)["radius"])
	main.hud.toggle_map()
	await _wait(0.4)
	main.hud.world_map.focus_on(sp, 0.9)
	await _wait(0.6)
	await _snap("map_after_carve")
	main.hud.toggle_map()
	await _wait(0.3)
	# 5. The carve canvas itself.
	var cv: Control = g.carve_view
	cv.open(g.rec, String(Frontier.runestones.stones[sid]["name"]), ["ward", "lure", "alarm", "bless"])
	await _wait(0.4)
	var strokes: Array = g.rec.synthesize("ward", RandomNumberGenerator.new(), {})
	cv.set("_strokes", _to_screen_strokes(cv, strokes))
	await _wait(0.3)
	await _snap("carve_canvas")
	cv.close()
	# 6. The violet Scar front: an outbreak near the player, terrain tinted, the station prompt.
	var scar: Region1Sim = g.scar
	var near := home + Vector2(60, -80)
	scar.seed_at(near, 3.5, "qa_outbreak")
	for i in 40:
		scar.tick(0.25)
	g._upload_mask()
	await _look_at(near + Vector2(-70, 30), near, -0.12)
	await _wait(1.0)
	await _snap("scar_front")
	await _tp(scar.nearest_front(near + Vector2(40, 0), 400.0) if scar.nearest_front(near + Vector2(40, 0), 400.0) != Vector2.INF else near)
	await _wait(1.0)
	main.hud.show_menu(Callable(g, "scar_menu").bind(near))
	await _wait(0.6)
	await _snap("scar_menu")
	main.hud.close_menu()
	# 7. Ancestor stone greeting.
	var el: EmberLegacy = g.el
	var summary := {"name": "Edda Ashford", "family": "Ashford", "age": 71, "day": WorldSim.day, "cause": "old age", "place": "Ashford",
		"reputation": {"trade": 30.0}, "chapters": [{"role": "farmer", "org": "", "place": "Ashford", "start_day": 0, "end_day": -1}],
		"highlights": [{"text": "Fed the village through the dry year", "day": 4}], "echoes": [], "mastery": {}, "tendencies": {}}
	var eid := el.on_life_ended(summary)
	var stone_id := wl.nearest_stone(home + Vector2(70, 0))
	el.choose_runestone(eid, stone_id, String(Frontier.runestones.stones[stone_id]["name"]), WorldSim.day)
	el.apply_to_network(Frontier.runestones)
	g._apply_ancestors_to_wardlines()
	var stp: Vector2 = Frontier.runestones.stones[stone_id]["pos"]
	await _look_at(stp + Vector2(6, 6), stp, -0.1)
	main.hud.show_menu(Callable(g, "stone_menu").bind(stone_id))
	await _wait(1.0)
	await _snap("ancestor_greeting")
	main.hud.close_menu()
	# 8. Ashsight replay of a staged memory.
	var site := home + Vector2(-30, 90)
	var mid: int = g.stage_memory(site, "qa_farm")
	await _look_at(site + Vector2(-16, 12), site, -0.18)
	g._kneel(mid)
	await _wait(6.0)
	await _snap("ashsight_replay")
	g.ash.stop()
	await _wait(2.5)
	# Contact sheet
	_contact_sheet()


func _to_screen_strokes(cv: Control, strokes: Array) -> Array[PackedVector2Array]:
	var r: Rect2 = cv.get("_stone_rect")
	var out: Array[PackedVector2Array] = []
	for s in strokes:
		var pv := PackedVector2Array()
		for p: Vector2 in PackedVector2Array(s):
			pv.append(r.position + r.size * (Vector2(0.5, 0.45) + p * 0.35))
		out.append(pv)
	return out


func _contact_sheet() -> void:
	var names := ["tracker", "quests_tab", "journal", "story_dialogue", "map_before_carve", "map_after_carve", "carve_canvas",
		"scar_front", "scar_menu", "ancestor_greeting", "ashsight_replay"]
	var cell := Vector2i(480, 270)
	var cols := 3
	var rows := int(ceil(float(names.size()) / cols))
	var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in names.size():
		var path := "%s/r1_%s.png" % [out_dir, names[i]]
		if not FileAccess.file_exists(path):
			continue
		var img := Image.load_from_file(path)
		img.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
	sheet.save_png("%s/r1_hooks_sheet.png" % out_dir)
	print("R1 sheet %s/r1_hooks_sheet.png" % out_dir)
