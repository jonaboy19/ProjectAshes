extends GdUnitTestSuite
## MN-8..11: settlement reactions to monster residents (comfort -> complaint, petition, protest, leaving, arrivals), prejudice and
## generations, fame/infamy by culture, status-aware gossip, save round trip and cost.

const Society := preload("res://scripts/realm/monster_society.gd")
const Barks := preload("res://scripts/realm/monster_barks.gd")
const Status := preload("res://scripts/realm/status.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


func _ms(seed_v := 1) -> Object:
	var m: Object = Society.new()
	m.seed_value = seed_v
	return m


func _homes(n: int, culture: String) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": "h%d" % i, "culture": culture})
	return out


func _orcs(n: int, harmed := false) -> Array:
	var out: Array = []
	for i in n:
		out.append({"species": "orc", "harmed": harmed})
	return out


func test_baseline_prejudice_differs_by_culture() -> void:
	assert_float(Society.baseline("solenne", "orc")).is_greater(Society.baseline("caldric", "orc"))
	assert_float(Society.baseline("urrokai", "wolf")).is_less(Society.baseline("solenne", "wolf"))
	var ms := _ms()
	assert_float(ms.prejudice(1, "solenne", "orc")).is_equal(Society.baseline("solenne", "orc"))


func test_one_year_of_positive_contact_softens_by_one_hundredth_and_atrocity_adds_two_tenths() -> void:
	var ms := _ms()
	var p0: float = ms.prejudice(3, "caldric", "goblin")
	for d in 360:
		ms.contact(3, "caldric", "goblin")
		ms.tick_day(d, {})
	assert_float(p0 - ms.prejudice(3, "caldric", "goblin")).is_equal_approx(0.01, 0.0005)
	var p1: float = ms.prejudice(3, "caldric", "goblin")
	ms.atrocity(3, "caldric", "goblin")
	assert_float(ms.prejudice(3, "caldric", "goblin") - p1).is_equal_approx(0.2, 0.0001)
	assert_float(ms.tension(3)).is_greater(0.0)
	assert_float(Society.child_prejudice(0.7)).is_equal_approx(0.55, 0.0001)
	assert_float(Society.child_prejudice(0.1)).is_equal(0.0)
	ms.doctrine_shift(3, "caldric", "goblin", -0.1)
	assert_float(ms.prejudice(3, "caldric", "goblin")).is_less(p1 + 0.2 - 0.05)


func test_prejudiced_households_petition_then_leave_with_reason_monsters() -> void:
	var ms := _ms()
	var homes := _homes(6, "solenne")
	var seen := {}
	var left_week := -1
	for w in 40:
		for e: Dictionary in ms.weekly_reaction(9, homes, _orcs(3), 100 + w * 7):
			seen[e["type"]] = int(seen.get(e["type"], 0)) + 1
			if e["type"] == "leave" and left_week < 0:
				left_week = w
	assert_int(int(seen.get("complain", 0))).is_greater(0)
	assert_int(int(seen.get("petition", 0))).is_greater(0)
	assert_int(int(seen.get("leave", 0))).is_greater(0)
	assert_int(left_week).is_between(2, 30)
	var deps: Array = ms.take_departures()
	assert_int(deps.size()).is_equal(int(seen["leave"]))
	assert_str(deps[0]["reason"]).is_equal("monsters")
	assert_int(ms.take_departures().size()).is_equal(0)
	assert_bool(ms.has_left(deps[0]["hid"])).is_true()
	assert_int(ms.petitions().size()).is_greater(0)
	assert_float(ms.tension(9)).is_greater(0.0)


func test_tolerant_culture_stays_and_friendly_households_arrive() -> void:
	var ms := _ms()
	var wolves: Array = [{"species": "wolf", "harmed": false}]
	var arrived := 0
	for w in 40:
		for e: Dictionary in ms.weekly_reaction(4, _homes(6, "urrokai"), wolves, 50 + w * 7):
			assert_str(e["type"]).is_not_equal("leave")
			if e["type"] == "arrive":
				arrived += 1
	assert_int(arrived).is_greater(0)
	assert_int(ms.take_arrivals().size()).is_equal(arrived)


func test_no_monsters_no_trouble_and_grudges_cool() -> void:
	var ms := _ms()
	var homes := _homes(4, "solenne")
	for w in 6:
		ms.weekly_reaction(2, homes, _orcs(3), w * 7)
	var mid: String = ms.stage_of("h0")
	assert_str(mid).is_not_equal("content")
	for w in 12:
		assert_array(ms.weekly_reaction(2, homes, [], 100 + w * 7)).is_empty()
	assert_str(ms.stage_of("h0")).is_equal("content")


func test_reactions_are_deterministic() -> void:
	var a := _ms(5)
	var b := _ms(5)
	var ra: Array = []
	var rb: Array = []
	for w in 20:
		ra.append(a.weekly_reaction(1, _homes(5, "solenne"), _orcs(2, true), 10 + w * 7))
		rb.append(b.weekly_reaction(1, _homes(5, "solenne"), _orcs(2, true), 10 + w * 7))
	assert_array(ra).is_equal(rb)


func test_riot_needs_high_tension_and_an_incident() -> void:
	var ms := _ms()
	for i in 12:
		ms.incident(5, "solenne", "orc", 0.2)
	assert_float(ms.tension(5)).is_greater(0.8)
	var evs: Array = ms.weekly_reaction(5, _homes(3, "solenne"), _orcs(3), 5, true)
	assert_bool(evs.any(func(e: Dictionary) -> bool: return e["type"] == "riot")).is_true()
	var calm := _ms()
	assert_bool(calm.weekly_reaction(5, _homes(3, "solenne"), _orcs(3), 5, true).any(func(e: Dictionary) -> bool: return e["type"] == "riot")).is_false()


func test_fame_and_infamy_are_read_by_culture_with_a_delay() -> void:
	var ms := _ms()
	var b := {"species": "orc", "kind": "monster", "form": 2, "grade": "true"}
	ms.on_name_story("player", 5, b, 10)
	assert_float(ms.fame_of("player", 5)).is_greater(0.0)
	var far0: float = ms.infamy_of("player", 5)
	ms.tick_day(11, {})
	assert_float(ms.infamy_of("player", 5)).is_equal(far0)
	ms.tick_day(10 + Society.NEWS_DELAY, {})
	assert_float(ms.infamy_of("player", 5)).is_greater_equal(far0)
	# Church culture hears infamy where wild-faith culture hears fame.
	var cn: Array = []
	for row: Array in ms.serialize()["fame"].keys().map(func(k: String) -> Array: return [k, ms.serialize()["fame"][k]]):
		cn.append(row)
	var inf_sol := 0.0
	var inf_uro := 0.0
	for row: Array in cn:
		if String(row[0]).ends_with("c:solenne"):
			inf_sol = float(row[1][1])
		if String(row[0]).ends_with("c:urrokai"):
			inf_uro = float(row[1][1])
	assert_float(inf_sol).is_greater(inf_uro)
	ms.add_infamy("player", 5, 10.0)
	assert_float(ms.infamy_of("player", 5)).is_greater(far0)


func test_repeated_bribes_raise_infamy_faster() -> void:
	var ms := _ms()
	ms.log_bribe("player", 3, 30, 1, false)
	var one: float = ms.infamy_of("player", 3)
	ms.log_bribe("player", 3, 30, 2, true)
	ms.log_bribe("player", 3, 30, 3, false)
	ms.log_bribe("player", 3, 30, 4, false)
	assert_float(ms.infamy_of("player", 3) - one).is_greater(3.5)
	assert_int(ms.bribes_of("player").size()).is_equal(4)


func test_every_status_band_has_at_least_five_lines() -> void:
	for band in ["outcast", "low", "common", "respected", "noble", "exalted"]:
		var n := 0
		for sit in ["greet", "gossip", "gate", "companion"]:
			n += Barks.lines_for(band, sit, "any", "any").size()
		assert_int(n).is_greater_equal(5)
	assert_int((Barks.lines_for("outcast", "greet", "solenne", "orc")).size()).is_greater(Barks.lines_for("outcast", "greet", "caldric", "orc").size())


func test_gossip_never_repeats_inside_three_hours_and_respects_band() -> void:
	var ms := _ms(3)
	var first: Dictionary = ms.gossip("npc1", 0.05, "greet", "caldric", "orc", 4, 10)
	assert_bool(first["ok"]).is_true()
	assert_bool(ms.gossip("npc1", 0.05, "greet", "caldric", "orc", 4, 12)["ok"]).is_false()
	assert_bool(ms.gossip("npc1", 0.05, "greet", "caldric", "orc", 4, 13)["ok"]).is_true()
	var low_lines: Array = Barks.lines_for("outcast", "greet", "caldric", "orc").map(func(d: Dictionary) -> String: return d["t"])
	assert_bool(first["line"] in low_lines).is_true()
	var high: Dictionary = ms.gossip("npc2", 0.95, "greet", "caldric", "orc", 4, 10)
	var high_lines: Array = Barks.lines_for("exalted", "greet", "caldric", "orc").map(func(d: Dictionary) -> String: return d["t"])
	assert_bool(high["line"] in high_lines).is_true()
	# Hour budget: no more than 24 lines in one hour.
	var spoken := 0
	for i in 40:
		if bool(ms.gossip("crowd%d" % i, 0.5, "greet", "caldric", "", 9, 8)["ok"]):
			spoken += 1
	assert_int(spoken).is_less_equal(Barks.BUDGET)


func test_hub_week_tick_reacts_to_stationed_monsters_and_saves() -> void:
	var hub = Hub.new()
	var mb: Object = hub.mod("monster_bonds")
	var ms: Object = hub.mod("monster_society")
	for i in 3:
		var b: Dictionary = mb._new_bond("lesser", "orc", "O%d" % i, "player", 3, 1, {"level": 3, "station": 0})
		b["harmed"] = 1
	assert_int(mb.stationed(0).size()).is_equal(3)
	var t0 := Time.get_ticks_usec()
	for w in 20:
		ms._day = 7 * w
		ms.tick_week(w, {})
	var per_week := float(Time.get_ticks_usec() - t0) / 20.0
	assert_float(per_week).is_less(20000.0)
	var js := JSON.stringify(ms.serialize())
	var copy := _ms()
	copy.deserialize(JSON.parse_string(js))
	assert_int(copy.take_departures().size()).is_equal(ms.take_departures().size())
	var mjs := JSON.stringify(mb.serialize())
	var mcopy: Object = hub.mod("monster_bonds").get_script().new()
	mcopy.deserialize(JSON.parse_string(mjs))
	assert_int(mcopy.count()).is_equal(3)
	assert_int(mcopy.stationed(0).size()).is_equal(3)


func test_status_gather_reads_hub_modules() -> void:
	var hub = Hub.new()
	var ms: Object = hub.mod("monster_society")
	ms.on_name_story("player", 5, {"species": "wolf", "kind": "beast", "form": 1, "grade": "lesser"}, 1)
	var st: Dictionary = ms.status_of("player", 5, "urrokai")
	assert_float(st["parts"]["fame"]).is_greater(0.0)
	assert_str(st["band"]).is_not_empty()
