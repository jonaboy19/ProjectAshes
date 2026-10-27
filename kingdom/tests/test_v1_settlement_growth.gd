extends GdUnitTestSuite
## READY_V1 C4, settlement growth: the 120-day headless sim (tools_qa/v1/settlement_sim.gd) takes a camp with three followers to a Village
## by day 60-90 (CSV written), people and labour matter, hunger lowers contentment and drives people away, the ledger shows exactly what
## the sim computed, and the state survives a save.

const Sim := preload("res://tools_qa/v1/settlement_sim.gd")
const Growth := preload("res://scripts/realm/settlement_growth.gd")
const CSV := "user://v1_settlement_sim.csv"


func test_a_camp_with_three_followers_reaches_village_between_day_60_and_90() -> void:
	var res: Dictionary = Sim.run(120, 3)
	var lines: PackedStringArray = [Sim.HEADER]
	lines.append_array(res["rows"])
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	assert_int((res["rows"] as Array).size()).is_equal(120)
	assert_int(int(res["hamlet_day"])).is_between(1, 40)
	assert_int(int(res["village_day"])).is_between(60, 90)
	assert_int(int(res["hamlet_day"])).is_less(int(res["village_day"]))
	var hub: RefCounted = res["hub"]
	var l: Dictionary = hub.mod("growth").ledger(int(res["gid"]))
	assert_int(int(l["pop"])).is_greater_equal(Growth.VILLAGE_POP)
	assert_bool(bool(l["structures"]["well"])).is_true()
	assert_bool(bool(l["structures"]["hall"])).is_true()
	assert_float(float(l["content"])).is_greater_equal(Growth.VILLAGE_CONTENT)


func test_without_followers_nobody_builds_and_the_camp_stays_a_camp() -> void:
	var res: Dictionary = Sim.run(60, 0)
	assert_int(int(res["village_day"])).is_equal(-1)
	assert_int(int(res["hamlet_day"])).is_equal(-1)


func test_hunger_lowers_contentment_and_drives_settlers_away() -> void:
	var res: Dictionary = Sim.run(30, 3)
	var hub: RefCounted = res["hub"]
	var g: RefCounted = hub.mod("growth")
	var gid := int(res["gid"])
	var s: Dictionary = g.state_of(gid)
	var c0 := float(s["content"])
	var pop0 := int(s["pop"])
	s["food"] = 0.0
	s["food_mult"] = 0.0
	hub.mod("followers").list("present").map(func(f: Dictionary) -> void: f["status"] = "left")   # nobody forages either
	for d in 6:
		g.tick_day(31 + d, {})
	assert_bool(bool(g.ledger(gid)["starving"])).is_true()
	assert_float(float(s["content"])).is_less(c0 - 0.1)
	assert_int(int(s["pop"])).is_less(pop0)
	assert_int(int(s["left"])).is_greater(0)
	var parts: Array = g.ledger(gid)["content_parts"]
	assert_str(String(parts[0][0])).is_equal("Hunger")
	assert_float(float(parts[0][1])).is_less(0.0)


func test_the_ledger_shows_what_the_sim_computed() -> void:
	var res: Dictionary = Sim.run(40, 3)
	var g: RefCounted = (res["hub"] as RefCounted).mod("growth")
	var gid := int(res["gid"])
	var s: Dictionary = g.state_of(gid)
	var l: Dictionary = g.ledger(gid)
	assert_int(int(l["pop"])).is_equal(int(s["pop"]))
	assert_float(float(l["food"])).is_equal(float(s["food"]))
	assert_float(float(l["food_days"])).is_equal_approx(float(s["food"]) / maxf(float(s["pop"]), 1.0), 0.001)
	assert_float(float(l["content"])).is_equal(float(s["content"]))
	var sum := 0.35
	for p: Array in l["content_parts"]:
		sum += float(p[1])
	assert_float(float(l["content_target"])).is_equal_approx(clampf(sum, 0.0, 1.0), 0.001)
	assert_int(int(l["jobs"]["workers"])).is_equal(int(floor(float(s["pop"]) * Growth.WORKING_SHARE)))
	assert_int(int(l["jobs"]["followers"])).is_equal(3)
	assert_int(int(l["capacity"])).is_equal(Growth.TENT_ROOM + Growth.HOUSE_ROOM * int(l["houses"]) + int(l["beds"]))
	assert_str(String(l["tier_name"])).is_equal(Growth.TIER_WORDS[int(s["tier"])])
	assert_bool(not (l["checklist"] as Array).is_empty()).is_true()
	for c: Dictionary in l["checklist"]:
		assert_bool(bool(c["ok"])).is_equal(float(c["have"]) >= float(c["need"]))


func test_state_survives_a_save_and_the_abandoned_camp_is_forgotten() -> void:
	var res: Dictionary = Sim.run(25, 3)
	var hub: RefCounted = res["hub"]
	var g: RefCounted = hub.mod("growth")
	var gid := int(res["gid"])
	var before: Dictionary = g.ledger(gid)
	var g2: RefCounted = (load("res://scripts/realm/settlement_growth.gd") as GDScript).new()
	g2.hub = hub
	g2.deserialize(JSON.parse_string(JSON.stringify(g.serialize())))
	var after: Dictionary = g2.ledger(gid)
	for k in ["pop", "tier", "arrived", "left"]:
		assert_that(after[k]).is_equal(before[k])
	for k in ["food", "content"]:
		assert_float(float(after[k])).is_equal_approx(float(before[k]), 0.001)     # (JSON keeps six digits)
	hub.mod("build_kit").abandon(gid)
	g.tick_day(26, {})
	assert_dict(g.states).is_empty()


func test_the_daily_tick_is_cheap() -> void:
	var res: Dictionary = Sim.run(50, 3)
	var g: RefCounted = (res["hub"] as RefCounted).mod("growth")
	var t0 := Time.get_ticks_usec()
	for d in 20:
		g.tick_day(100 + d, {})
	var per_day := float(Time.get_ticks_usec() - t0) / 20.0
	assert_float(per_day).is_less(20000.0)    # a loose limit: ~1 ms here, CI runners are slow


func test_the_ledger_page_shows_the_growth_numbers() -> void:
	var res: Dictionary = Sim.run(40, 3)
	var hub: RefCounted = res["hub"]
	var panel: Control = (load("res://scripts/ui/settlement_ledger.gd") as GDScript).new()
	panel.set("realm_override", hub)
	add_child(panel)
	auto_free(panel)
	panel.call("build")
	panel.call("refresh")
	var texts: Array = panel.call("texts")
	var l: Dictionary = hub.mod("growth").ledger(int(res["gid"]))
	var joined := "\n".join(texts)
	assert_str(joined).contains("%d people, room for %d" % [int(l["pop"]), int(l["capacity"])])
	assert_str(joined).contains("%.1f days of food" % float(l["food_days"]))
	assert_str(joined).contains(String(l["tier_name"]))
	assert_str(joined).contains("Contentment")
	assert_int((panel.call("rows") as Array).size()).is_equal(1)
	var tab: GDScript = load("res://scripts/ui/gamemenu/tab_affairs.gd")
	var ids: Array = (tab.get_script_constant_map()["VIEWS"] as Array).map(func(v: Array) -> String: return String(v[0]))
	assert_array(ids).contains(["settlement"])
