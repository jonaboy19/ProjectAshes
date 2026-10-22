extends GdUnitTestSuite
## In-world realm events (ACADEMY_PLAN P4): which offer is delivered next, never twice, saved and
## restored safely; the drill yard finds free ground; the academy campus is a named region site.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Enc := preload("res://scripts/world/realm_encounters.gd")
const Yard := preload("res://scripts/world/drill_yard.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 200, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _enc() -> Node:
	WorldGen.setup(2024)
	var e: Node = Enc.new()
	e.hub_override = Hub.new()
	return auto_free(e)


func _offer(id: String, template: String, deadline: int, delivered := false) -> Dictionary:
	return {"id": id, "template": template, "kind": "hunt", "from": "neighbour", "npc": "", "npc_name": "Orla Pike", "text": "Orla Pike: \"Wolves!\"",
		"sid": 0, "place": "Ashford", "reward": {"gold": 20, "rep": 2.0, "item": ""}, "deadline": deadline, "day": 1, "status": "open",
		"role": "combat", "danger": 0.3, "delivered": delivered, "accepted_day": -1}


func _first_scout_day(edu: RefCounted) -> int:
	edu.set_player({"home_sid": 0, "sid": 0, "age": 9, "gold": 100})
	edu.tick_day(100, CTX)
	for d in range(100, 140):
		edu.tick_day(d, CTX)
		if not edu.scouts_present(d).is_empty():
			return d
	return -1


func test_nothing_to_deliver_in_a_quiet_world() -> void:
	var e := _enc()
	assert_bool(e.pick_next({"age": 20, "day": 5, "hour": 10}).is_empty()).is_true()


func test_callups_levy_first_then_soonest_deadline() -> void:
	var e := _enc()
	var cu: RefCounted = e.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9))
	cu.offers_list.append(_offer("cuB", "lost_child", 4))
	var pick: Dictionary = e.pick_next({"age": 20})
	assert_str(String(pick["kind"])).is_equal("callup")
	assert_str(String(pick["offer"]["id"])).is_equal("cuB")
	cu.offers_list.append(_offer("cuC", "militia_levy", 30))
	assert_str(String(e.pick_next({"age": 20})["offer"]["id"])).is_equal("cuC")


func test_no_duplicate_delivery() -> void:
	var e := _enc()
	var cu: RefCounted = e.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9))
	cu.offers_list.append(_offer("cuB", "lost_child", 12))
	var first: Dictionary = e.pick_next({"age": 20})
	assert_str(String(first["offer"]["id"])).is_equal("cuA")
	# Delivered by us (key remembered) and by the module flag: neither comes back.
	e.delivered[String(first["key"])] = 5
	cu.mark_delivered("cuA")
	var second: Dictionary = e.pick_next({"age": 20})
	assert_str(String(second["offer"]["id"])).is_equal("cuB")
	cu.mark_delivered("cuB")
	assert_bool(e.pick_next({"age": 20, "day": 5}).is_empty()).is_true()
	# Deciding an offer takes it out of the queue for good.
	cu.offers_list.append(_offer("cuD", "fire_alarm", 6))
	cu.decline("cuD")
	assert_bool(e.pick_next({"age": 20, "day": 5}).is_empty()).is_true()


func test_accepted_callup_gets_a_report_visit_next_day_once() -> void:
	var e := _enc()
	var cu: RefCounted = e.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9, true))
	cu.accept("cuA")
	for o: Dictionary in cu.offers_list:
		o["accepted_day"] = 5
	assert_bool(e.pick_next({"age": 20, "day": 5}).is_empty()).is_true()
	var rep: Dictionary = e.pick_next({"age": 20, "day": 6})
	assert_str(String(rep["kind"])).is_equal("callup_report")
	e.delivered[String(rep["key"])] = 6
	assert_bool(e.pick_next({"age": 20, "day": 6}).is_empty()).is_true()
	assert_str(String(e.pick_next({"age": 20, "day": 7})["kind"])).is_equal("callup_report")   # a new day, a new visit


func test_scout_news_then_noon_test_only_at_nine_near_the_square() -> void:
	var e := _enc()
	var edu: RefCounted = e.hub_override.mod("education")
	var day := _first_scout_day(edu)
	assert_int(day).is_greater(0)
	# Too old, or already at school: nobody comes.
	assert_bool(e.pick_next({"age": 16, "day": day, "hour": 13, "near_square": true}).is_empty()).is_true()
	# Morning: the news; before seven nothing.
	assert_bool(e.pick_next({"age": 9, "day": day, "hour": 5, "near_square": true}).is_empty()).is_true()
	var news: Dictionary = e.pick_next({"age": 9, "day": day, "hour": 9, "near_square": false})
	assert_str(String(news["kind"])).is_equal("scout_news")
	e.delivered[String(news["key"])] = day
	assert_bool(e.pick_next({"age": 9, "day": day, "hour": 10, "near_square": true}).is_empty()).is_true()
	# Noon away from the square: no test; at the square: the scout walks up.
	assert_bool(e.pick_next({"age": 9, "day": day, "hour": 13, "near_square": false}).is_empty()).is_true()
	var test: Dictionary = e.pick_next({"age": 9, "day": day, "hour": 13, "near_square": true})
	assert_str(String(test["kind"])).is_equal("scout_test")
	e.delivered[String(test["key"])] = day
	assert_bool(e.pick_next({"age": 9, "day": day, "hour": 14, "near_square": true}).is_empty()).is_true()
	# Sitting the test through the module API takes the scout out for good.
	var res: Dictionary = edu.attend(String(test["scout"]["id"]))
	assert_bool(bool(res["ok"])).is_true()


func test_graduation_offer_is_delivered_once_and_priority_beats_callups() -> void:
	var e := _enc()
	var edu: RefCounted = e.hub_override.mod("education")
	edu.set_player({"home_sid": 0, "sid": 0, "age": 12, "gold": 300, "class": 3})
	edu._ensure()
	var iid := ""
	for i: Dictionary in edu.institutions():
		if String(i["kind"]) == "knight_academy" and not bool(i["minor"]):
			iid = String(i["id"])
	edu.tick_day(1, CTX)
	edu.set_player({"axes": {"potential": 95.0, "discipline": 95.0, "intelligence": 95.0, "condition": 95.0, "reflexes": 95.0, "courage": 95.0,
		"memory": 95.0, "leadership": 95.0, "constitution": 95.0, "magic_sensitivity": 95.0, "resonance": 95.0}})
	edu.apply(iid, "exam", CTX)
	edu.student["perf"]["combat"] = 70.0
	edu.graduate(true)
	var cu: RefCounted = e.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9))
	var pick: Dictionary = e.pick_next({"age": 18, "day": 3, "hour": 10})
	if edu.graduation_offers().is_empty():
		assert_str(String(pick["kind"])).is_equal("callup")
		return
	# Every open offer is visited exactly once, then the call-up gets its turn.
	var seen := {}
	for i in 12:
		if String(pick["kind"]) != "grad":
			break
		assert_bool(seen.has(pick["key"])).is_false()
		seen[pick["key"]] = true
		e.delivered[String(pick["key"])] = 3
		pick = e.pick_next({"age": 18, "day": 3, "hour": 10})
	assert_int(seen.size()).is_equal(edu.graduation_offers().size())
	assert_str(String(pick["kind"])).is_equal("callup")


func test_family_trouble_comes_first_and_only_once() -> void:
	var e := _enc()
	var hh: RefCounted = e.hub_override.mod("household")
	hh.set_player({"home_sid": 3, "sid": 3, "age": 10, "gold": 100})
	var cu: RefCounted = e.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9))
	hh.encounter = {"kind": "bandits", "text": "Armed men block the road.", "day": 4, "hour": 7, "leg": 0, "danger": 0.4,
		"choices": ["fight", "flee", "bargain", "hide", "surrender"]}
	var pick: Dictionary = e.pick_next({"age": 10, "day": 4, "hour": 7})
	assert_str(String(pick["kind"])).is_equal("encounter")
	e.delivered[String(pick["key"])] = 4
	assert_str(String(e.pick_next({"age": 10, "day": 4, "hour": 7})["kind"])).is_equal("callup")


func test_state_survives_save_and_load_and_rejects_garbage() -> void:
	var e := _enc()
	e.delivered["cu:cuA"] = 5
	e.delivered["scoutnews:100"] = 101
	e.hints_seen["first_callup"] = true
	var snap: Dictionary = JSON.parse_string(JSON.stringify(e.snapshot()))
	var f := _enc()
	f.restore(snap)
	assert_str(_norm(f.snapshot())).is_equal(_norm(e.snapshot()))
	assert_bool(f.is_delivered("cu:cuA")).is_true()
	# Restored state still refuses a duplicate.
	var cu: RefCounted = f.hub_override.mod("callups")
	cu.offers_list.append(_offer("cuA", "wolves_at_farm", 9))
	assert_bool(f.pick_next({"age": 20}).is_empty()).is_true()
	# Old or broken saves reset to defaults instead of crashing.
	f.restore({})
	assert_bool(f.delivered.is_empty()).is_true()
	f.restore({"delivered": 7, "hints": "x"})
	assert_bool(f.delivered.is_empty() and f.hints_seen.is_empty()).is_true()
	f.restore({"delivered": {"a": "3"}, "hints": {"first_job": 1}})
	assert_int(int(f.delivered["a"])).is_equal(3)


func test_hints_show_once_only() -> void:
	var e := _enc()
	e.hint("first_callup")
	e.hint("first_callup")
	e.hint("no_such_hint")
	assert_int(e._hint_queue.size()).is_equal(1)
	assert_bool(e.hints_seen.has("no_such_hint")).is_false()


func test_drill_yard_finds_free_ground_off_the_streets() -> void:
	WorldGen.setup(2024)
	var s: Dictionary = WorldGen.settlements[0]
	var found: Dictionary = Yard.find_spot(s)
	assert_bool(found.is_empty()).is_false()
	var q: Vector2 = found["pos"]
	assert_bool(WorldGen.is_water(q.x, q.y)).is_false()
	assert_float(CityPlanner.street_distance(s["plan"], q)).is_greater(7.5)
	for lot: Dictionary in s["plan"]["lots"]:
		assert_float(q.distance_to(lot["pos"])).is_greater(14.0)
	assert_float(q.distance_to(s["pos"])).is_less(float(s["radius"]) * 1.4)
	# Deterministic: the same world gives the same yard.
	assert_str(str(Yard.find_spot(s)["pos"])).is_equal(str(q))


func test_academy_campus_is_a_named_site_150_to_400_m_from_kingsreach() -> void:
	for seed_value in [2024, 1066]:
		WorldGen.setup(seed_value)
		var cap := {}
		for s in WorldGen.settlements:
			if s["kind"] == "castle":
				cap = s
		var acad := {}
		for site in WorldGen.sites:
			if site["kind"] == "academy":
				acad = site
		assert_bool(acad.is_empty()).is_false()
		assert_str(String(acad["name"])).is_equal("Kingsreach Academy of Arms and Arts")
		var p: Vector2 = acad["pos"]
		assert_float(p.distance_to(cap["pos"])).is_between(150.0, 400.0)
		assert_float(WorldGen.road_distance(p.x, p.y)).is_greater(40.0)
		assert_bool(WorldGen.is_water(p.x, p.y)).is_false()
		assert_int((acad["parts"] as Array).size()).is_greater(20)
		# Its id is its index (appended last by the planner, so no earlier id moved).
		assert_str(String(WorldGen.sites[int(acad["id"])]["name"])).is_equal(String(acad["name"]))
		# The world map's place list picks it up like any other site.
		var d := preload("res://scripts/sim/discovery.gd").new()
		d.build_from_world([])
		var found := false
		for pl: Dictionary in d.places:
			if String(pl["name"]) == "Kingsreach Academy of Arms and Arts":
				found = true
		assert_bool(found).is_true()
