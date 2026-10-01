extends GdUnitTestSuite
## Tactical battle view, siege view and the smaller war screens (scripts/ui/war/tactical_view.gd, siege_view.gd, war_extras.gd).

const TView := preload("res://scripts/ui/war/tactical_view.gd")
const SView := preload("res://scripts/ui/war/siege_view.gd")
const Extras := preload("res://scripts/ui/war/war_extras.gd")
const Tac := preload("res://scripts/realm/tactical.gd")
const Siege := preload("res://scripts/realm/siege.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const WarMap := preload("res://scripts/ui/war/war_map.gd")


func before_test() -> void:
	WorldGen.setup(2024)


func _side(player: bool, fac: String) -> Dictionary:
	var kinds := ["infantry", "infantry", "spear", "archer", "heavy_cav", "light_cav", "mage"]
	var units: Array = []
	for i in kinds.size():
		units.append({"cid": 0, "name": "%s %d" % [kinds[i], i], "kind": kinds[i], "men": 200, "quality": 0.6, "morale": 0.75, "fatigue": 0.0})
	return {"faction": fac, "player": player, "name": "Your army" if player else "Enemy", "units": units, "supply": 3.0,
		"elites": [{"kind": "champion", "name": "Champion", "men": 1, "quality": 0.9, "morale": 0.9}],
		"cmd": {"name": "Gen", "personality": "loyal", "skill": 2, "tactics": 48, "experience": 48}}


func _battle(deploy := true) -> RefCounted:
	return Tac.create({"seed": 4, "name": "Battle of Test", "center": [-1274.0, -2318.0], "deploy": deploy, "attacker": "b", "sides": {"a": _side(true, "caldrenn"), "b": _side(false, "ongur_khanate")}})


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _view(tt: RefCounted) -> Control:
	var v: Control = TView.new()
	v.set("tt", tt)
	v.size = Vector2(1280, 720)
	add_child(auto_free(v))
	return v


func test_deployment_then_start_battle_with_drag_orders_and_time_controls() -> void:
	var tt := _battle()
	var v := _view(tt)
	var txt := "\n".join(PackedStringArray(_texts(v)))
	assert_str(txt).contains("Battle Deployment")
	assert_str(txt).contains("Start Battle")
	assert_str(txt).contains("Pause")
	assert_str(txt).contains("x5")
	assert_str(txt).contains("Range")
	assert_str(txt).contains("Contours")
	assert_bool(v.call("is_deploying")).is_true()
	# fog: the enemy army is not on the map before anyone has seen it
	var enemies := (v.get("_units") as Array).filter(func(u: Dictionary) -> bool: return int(u["side"]) == 1)
	assert_int(enemies.size()).is_equal(0)
	v.call("select_unit", 0)
	assert_int((v.get("sel") as Array).size()).is_equal(1)
	# drag in deployment moves the piece
	var before := Vector2(tt.u_x[0], tt.u_y[0])
	var pos := v.call("to_screen", before + Vector2(0, 0)) as Vector2
	v.call("_canvas_input", _mb(pos, true))
	v.call("_canvas_input", _mm(pos + Vector2(30, 0)))
	v.call("_canvas_input", _mb(pos + Vector2(30, 0), false))
	assert_bool(Vector2(tt.u_x[0], tt.u_y[0]).distance_to(before) > 5.0).is_true()
	v.call("start_battle")
	assert_str(tt.phase).is_equal("battle")
	# orders go through the signal system
	v.call("select_unit", 0)
	var res: Array = v.call("issue", "advance", Vector2(700, 700))
	assert_bool(bool((res[0] as Dictionary)["ok"])).is_true()
	assert_int((tt.orders_view(0) as Array).size()).is_equal(1)
	var r2: Array = v.call("quick_order", "hold")
	assert_bool(r2.size() > 0).is_true()
	# time passes at the chosen speed and the clock text follows
	v.call("set_speed", 4)
	v.call("_process", 1.0)
	assert_float(tt.t).is_greater(0.0)
	assert_str(String((v.get("_clock") as Label).text)).contains("Time:")
	v.call("set_speed", 0)
	var t0: float = tt.t
	v.call("_process", 2.0)
	assert_float(tt.t).is_equal(t0)
	# display styles
	for s in 3:
		v.call("set_style", s)
		assert_int(int(v.get("style"))).is_equal(s)
	assert_int(int(v.call("contour_count"))).is_greater(0)
	# range / contour toggles redraw without error
	v.set("show_range", true)
	v.set("show_contours", true)
	(v.get("_layer") as Control).queue_redraw()
	await get_tree().process_frame


func _mb(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func _mm(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func test_formation_editor_applies_and_shows_preview_stats() -> void:
	var tt := _battle()
	var v := _view(tt)
	v.call("select_unit", 1)
	v.call("open_formation_editor")
	var pop: Control = v.get("_form_popup")
	assert_object(pop).is_not_null()
	var txt := "\n".join(PackedStringArray(_texts(pop)))
	for w in ["Line", "Wedge", "Square", "Column", "Layered", "Loose", "Circle", "Custom", "Attack", "Defense", "Mobility", "Vs Cavalry", "Vs Ranged", "Keep ranged behind", "Apply"]:
		assert_str(txt.to_lower()).contains(w.to_lower())
	(v.get("_form_state") as Dictionary)["name"] = "wedge"
	v.call("_apply_formation")
	assert_str(String(tt.unit_view(1)["formation"])).is_equal("wedge")
	(v.get("_form_state") as Dictionary)["name"] = "custom"
	(v.get("_form_state") as Dictionary)["depth"] = 5
	v.call("_apply_formation")
	assert_str(String(tt.unit_view(1)["formation"])).is_equal("custom")
	var pts: PackedVector2Array = Extras.formation_points("wedge", 30)
	assert_int(pts.size()).is_equal(30)


func test_battle_panel_shows_forces_terrain_weather_orders_and_aftermath() -> void:
	var tt := _battle(false)
	var v := _view(tt)
	tt.auto = [true, true]
	tt.advance(60)
	v.call("_refresh", true)
	var txt := "\n".join(PackedStringArray(_texts(v.get("_panel"))))
	for w in ["Battle Information", "Our Forces", "Enemy Forces", "Terrain", "Weather", "Visibility", "Advisors", "Reports"]:
		assert_str(txt).contains(w)
	tt.run_to_end()
	v.call("_refresh", true)
	var t2 := "\n".join(PackedStringArray(_texts(v.get("_panel"))))
	assert_bool(t2.contains("Victory") or t2.contains("Defeat") or t2.contains("Stalemate")).is_true()
	assert_str(t2).contains("Killed")
	assert_str(t2).contains("Return to Camp")
	var st := Extras.aftermath_stats(tt.result, 0)
	assert_int(int(st["mine"]["killed"]) + int(st["mine"]["wounded"]) + int(st["mine"]["missing"])).is_equal(int(st["total_mine"]))


func test_duel_prompt_reaches_the_player() -> void:
	var tt := _battle(false)
	var v := _view(tt)
	var elite := -1
	for i in tt.side_units(0):
		if bool(tt.u_meta[i]["elite"]):
			elite = i
	tt.pending_duel = {"mine": elite, "theirs": tt.side_units(1)[tt.side_units(1).size() - 1], "t": 0.0, "side": 0}
	v.call("_refresh", true)
	var txt := "\n".join(PackedStringArray(_texts(v.get("_panel"))))
	assert_str(txt).contains("challenges")
	assert_str(txt).contains("Send champion")
	assert_str(txt).contains("Avoid")


func test_siege_view_tabs_actions_and_fall() -> void:
	var p: Vector2 = WorldGen.settlements[2]["pos"]
	var sg := Siege.create({"key": "t", "name": "Greyford Keep", "pos": [p.x, p.y], "kind": "town", "defender": "caldrenn", "attacker": "player", "seed": 3, "garrison": 300, "food_days": 30.0,
		"camp": {"men": 1200, "engineers": 30, "guards": 200, "medical": 30}, "tech": 2, "timber": 0.8})
	var v: Control = SView.new()
	v.set("sg", sg)
	v.size = Vector2(1280, 720)
	add_child(auto_free(v))
	var txt := "\n".join(PackedStringArray(_texts(v)))
	for w in ["Overview", "Siege Engines", "Garrison", "Plan", "Siege Plan", "Build Battering Ram", "Build Siege Tower", "Dig Tunnel", "Walls", "Supplies", "Morale", "Assault"]:
		assert_str(txt).contains(w)
	v.call("set_tab", "engines")
	var t2 := "\n".join(PackedStringArray(_texts(v)))
	assert_str(t2).contains("Siege Progress")
	assert_str(t2).contains("Battering ram")
	v.call("_build_engine", "ram")
	assert_int((sg.s["engines"] as Array).size()).is_equal(1)
	v.call("set_tab", "garrison")
	assert_str("\n".join(PackedStringArray(_texts(v)))).contains("Assign Troops")
	v.call("set_tab", "plan")
	v.call("_toggle_approach", true, "starve")
	assert_bool(bool(sg.s["approaches"]["starve"])).is_true()
	v.call("_wait", 3)
	assert_int(int(sg.s["day"])).is_equal(3)
	sg.s["garrison"] = 5
	sg.s["morale"] = 0.0
	sg.s["food_days"] = 0.0
	v.call("_negotiate")
	assert_str(String(sg.s["status"])).is_equal("fallen")
	v.call("refresh")
	assert_str("\n".join(PackedStringArray(_texts(v)))).contains("Territory Occupation")


func test_war_map_battle_card_offers_command_battle_and_opens_the_tactical_view() -> void:
	var h: RefCounted = Hub.new()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 0, {})
	var a: int = cm.call("spawn_army", "player", 0, 900, "aggressive", "Ashford Host")
	var b: int = cm.call("spawn_army", "ongur_khanate", 1, 600, "loyal", "Ongur Vanguard")
	var ia: Array = []
	var ib: Array = []
	for u: Dictionary in cm.call("army_units", a):
		ia.append(int(u["id"]))
		cm.call("detach", int(u["id"]))
	for u2: Dictionary in cm.call("army_units", b):
		ib.append(int(u2["id"]))
	var pos: Vector2 = cm.call("node_pos", 0) + Vector2(300, 200)
	cm.call("open_engagement", ia, ib, pos.x, pos.y)
	var m: Control = WarMap.new()
	m.set("realm_override", h)
	m.size = Vector2(1280, 720)
	add_child(auto_free(m))
	m.call("set_tab", "battles")
	assert_str("\n".join(PackedStringArray(_texts(m.get("_panel"))))).contains("Command battle")
	var eid := int((m.get("engs") as Array)[0]["id"])
	var tv: Control = m.call("open_tactical", eid)
	assert_object(tv).is_not_null()
	assert_bool(bool(cm.call("has_tactical", eid))).is_true()
	assert_str("\n".join(PackedStringArray(_texts(tv)))).contains("Battle Deployment")
	tv.call("start_battle")
	tv.call("close")
	assert_str(String(cm.call("engagement_view", eid)["control"])).is_equal("commander")


func test_logistics_occupation_and_officer_cards() -> void:
	var h: RefCounted = Hub.new()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 0, {})
	var a: int = cm.call("spawn_army", "player", 0, 1200, "aggressive", "Ashford Host")
	var box := VBoxContainer.new()
	add_child(auto_free(box))
	var li: Dictionary = Extras.logistics_info(cm, a)
	Extras.build_logistics(box, li, "Ashford Host")
	Extras.build_occupation(box, Extras.occupation_info(h, 1, 200), Callable())
	Extras.build_officer(box, cm, a)
	Extras.build_scout_report(box, "Enemy Army Sighted", 800, 1200, 360, {"infantry": 400})
	var txt := "\n".join(PackedStringArray(_texts(box)))
	for w in ["Logistics & Supplies", "Food", "Ammunition", "Medicine", "Horse Feed", "Engineers", "Supply route", "Territory Occupation", "Loyalty", "Rebel Risk", "Command capacity", "Enemy Army Sighted"]:
		assert_str(txt).contains(w)
