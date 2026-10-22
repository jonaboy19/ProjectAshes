extends GdUnitTestSuite
## War Map UI smoke test (scripts/ui/war/war_map.gd): builds from a realm hub with armies, switches display
## styles and zoom levels, selects / splits / merges / orders pieces, opens the radial menu and every panel tab,
## hosts from the Realm tab, and does no per-frame work once terrain is baked.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const WarMap := preload("res://scripts/ui/war/war_map.gd")
const TabRealm := preload("res://scripts/ui/gamemenu/tab_realm.gd")
const ENEMY := "ongur_khanate"


func _hub() -> RefCounted:
	WorldGen.setup(1066)
	var h: RefCounted = Hub.new()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 0, {})
	var mine: int = cm.call("spawn_army", "player", 0, 1240, "aggressive", "Ashford Host")
	cm.call("set_army_owner", mine, "personal")
	cm.call("spawn_army", "player", 2, 600, "cautious", "Millbrook Levy")
	var foe: int = cm.call("spawn_army", ENEMY, 1, 700, "loyal", "Ongur Vanguard")
	cm.call("report_sighting", foe, "merchant", 0.4)
	for i in 3:
		cm.call("tick_hour", i, {})
	return h


func _map(h: RefCounted) -> Control:
	var m: Control = WarMap.new()
	m.set("realm_override", h)
	m.size = Vector2(1280, 720)
	add_child(auto_free(m))
	return m


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func test_builds_with_pieces_enemy_sightings_and_a_panel() -> void:
	var h := _hub()
	var m := _map(h)
	assert_object(m.get("cm")).is_not_null()
	var toks: Array = m.call("tokens")
	assert_bool(toks.size() > 0).is_true()
	var kinds := {}
	for t: Dictionary in toks:
		kinds[t["t"]] = true
	assert_bool(kinds.has("army") or kinds.has("anchor")).is_true()
	assert_bool(kinds.has("enemy")).is_true()                      # only the fogged sighting, never the truth
	var txt := "\n".join(PackedStringArray(_texts(m.get("_panel"))))
	assert_str(txt).contains("Ashford Host")
	assert_str(txt).contains("Formations")
	assert_str(txt).contains("Split")
	assert_int((m.get("pieces") as Array).size()).is_greater(9)


func test_three_styles_and_three_zoom_levels_render_their_layers() -> void:
	var h := _hub()
	var m := _map(h)
	for lv in 3:
		m.call("set_level", lv)
		assert_int(int(m.get("level"))).is_equal(lv)
		for st in 3:
			m.call("set_style", st)
			assert_int(int(m.get("style"))).is_equal(st)
			m.call("refresh_view")
	m.call("set_level", 2)
	m.call("bake_now")
	assert_bool(m.call("terrain_ready")).is_true()
	# after baking nothing runs per frame
	assert_bool(m.is_processing()).is_false()
	# local level lays every unit out as its own token
	var units := 0
	for t: Dictionary in m.call("tokens"):
		if t["t"] == "unit":
			units += 1
	assert_int(units).is_greater(9)


func test_tap_selects_and_split_merge_conserve_men() -> void:
	var h := _hub()
	var m := _map(h)
	m.call("set_level", 2)
	var cm: RefCounted = m.get("cm")
	var target := {}
	for t: Dictionary in m.call("tokens"):
		if t["t"] == "unit" and t["kind"] == "infantry":
			target = t
			break
	assert_bool(target.is_empty()).is_false()
	var hit: Dictionary = m.call("token_at", (target["scr"] as Vector2) + Vector2(0, -float(target["r"]) * 0.9))
	assert_int(int(hit["id"])).is_equal(int(target["id"]))
	m.call("_tap", (target["scr"] as Vector2) + Vector2(0, -float(target["r"]) * 0.9))
	assert_array(m.get("sel_units")).contains([int(target["id"])])
	var before: int = int(cm.call("unit", int(target["id"]))["men"])
	var army_before := 0
	for p: Dictionary in cm.call("own_pieces"):
		army_before += int(p["men"])
	var nid: int = m.call("do_split", 60)
	assert_int(nid).is_greater(0)
	var army_after := 0
	for p: Dictionary in cm.call("own_pieces"):
		army_after += int(p["men"])
	assert_int(army_after).is_equal(army_before)
	assert_int(int(cm.call("unit", int(target["id"]))["men"])).is_equal(before - 60)
	m.call("select_units", [int(target["id"]), nid])
	assert_bool(m.call("do_merge")).is_true()
	assert_int(int(cm.call("unit", int(target["id"]))["men"])).is_equal(before)


func test_dragging_to_a_place_opens_the_radial_and_an_order_rides_by_courier() -> void:
	var h := _hub()
	var m := _map(h)
	var cm: RefCounted = m.get("cm")
	var cav := 0
	for p: Dictionary in cm.call("own_pieces"):
		if p["kind"] == "light_cav" and bool(p["can_command"]):
			cav = int(p["id"])
	m.call("select_units", [cav])
	var dest: Vector2 = (cm.call("node_pos", 1) as Vector2) + Vector2(100, 100)
	m.call("open_menu", dest, 0)
	assert_bool(m.call("radial_open")).is_true()
	m.call("_on_radial_cancelled")
	var res: Array = m.call("issue", "flank", dest)
	assert_int(res.size()).is_equal(1)
	assert_bool(res[0]["ok"]).is_true()
	assert_int((cm.call("couriers") as Array).size()).is_equal(1)
	assert_int((m.get("orders") as Array).size()).is_equal(1)
	assert_str(String((m.get("orders") as Array)[0]["text"])).contains("Courier riding")
	# the piece keeps its old order until the courier arrives
	assert_str(String(cm.call("unit", cav)["order"]["behavior"])).is_equal("hold")
	# units outside the player's command are not ordered: their superior is asked
	var levy := 0
	for p: Dictionary in cm.call("own_pieces"):
		if not bool(p["can_command"]):
			levy = int(p["id"])
	m.call("select_units", [levy])
	var res2: Array = m.call("issue", "advance", dest)
	assert_bool(res2.size() == 1 and res2[0].has("decision")).is_true()
	assert_str(String(m.get("status_text"))).is_not_empty()


func test_every_panel_tab_builds_and_time_passes_on_the_map() -> void:
	var h := _hub()
	var m := _map(h)
	for tab in ["units", "orders", "intel", "battles"]:
		m.call("set_tab", tab)
		var box: Node = m.get("_panel")
		assert_int(_texts(box).size()).is_greater(3)
	var cm: RefCounted = m.get("cm")
	var t0: int = cm.call("now_hours")
	m.call("advance", 6)
	assert_int(int(cm.call("now_hours"))).is_equal(t0 + 6)
	assert_str((m.get("_clock") as Label).text).contains("Day")
	m.call("set_tab", "intel")
	assert_str("\n".join(PackedStringArray(_texts(m.get("_panel"))))).contains("Force")


func test_realm_tab_opens_and_closes_the_war_map() -> void:
	var h := _hub()
	var t: Control = TabRealm.new()
	t.set("realm_override", h)
	add_child(auto_free(t))
	t.call("build")
	t.call("on_show")
	var m: Control = t.call("open_war_map")
	assert_object(m).is_not_null()
	assert_object(m.get("cm")).is_not_null()
	assert_object(t.call("open_war_map")).is_same(m)
	m.call("close")
	await get_tree().process_frame
	assert_object(t.get("war_map")).is_null()
	t.call("on_hide")


func test_display_with_no_campaign_degrades_gracefully() -> void:
	var m: Control = WarMap.new()
	var empty := RefCounted.new()
	m.set("realm_override", empty)
	add_child(auto_free(m))
	assert_object(m.get("cm")).is_null()
	assert_int((m.call("tokens") as Array).size()).is_equal(0)
	m.call("set_tab", "units")
	assert_int(_texts(m.get("_panel")).size()).is_greater(0)
