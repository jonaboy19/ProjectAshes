extends GdUnitTestSuite
## Realm factions: relation matrix, ties, marriages, kingship paths, church,
## sects, war reputation, determinism, round trip, perf.

const Factions := preload("res://scripts/realm/factions.gd")


func _run(days: int) -> Factions:
	WorldGen.setup(2024)
	var f := Factions.new()
	for d in days:
		f.tick_day(d, {})
	return f


func test_seeded_from_nations_and_houses() -> void:
	WorldGen.setup(2024)
	var f := Factions.new()
	var ids: Array = f.factions().map(func(x: Dictionary) -> String: return x["id"])
	assert_bool("caldrenn" in ids).is_true()
	assert_bool("ongur_khanate" in ids).is_true()
	assert_bool("church" in ids).is_true()
	assert_int(f.factions().filter(func(x: Dictionary) -> bool: return x["kind"] == "house").size()).is_greater(3)
	# nations.json: caldrenn/veylwood allied, caldrenn/urrokai hostile
	assert_float(f.relation("caldrenn", "veylwood")["trust"]).is_greater(f.relation("caldrenn", "urrokai_clanlands")["trust"])
	var r := f.relation("caldrenn", "ongur_khanate")
	for k in ["trust", "fear", "grievance", "trade", "stance"]:
		assert_bool(r.has(k)).is_true()
	assert_float(f.relation("caldrenn", "ongur_khanate")["trust"]).is_equal(f.relation("ongur_khanate", "caldrenn")["trust"])


func test_deterministic() -> void:
	var a := _run(40)
	var b := _run(40)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_round_trip_json() -> void:
	var a := _run(60)
	a.record_war_act("player", "spare_civilians")
	a.add_kingship_progress("uprising", 5.0, "test")
	var s := JSON.stringify(a.serialize())
	var b := Factions.new()
	b.deserialize(JSON.parse_string(s))
	assert_str(JSON.stringify(b.serialize())).is_equal(s)
	assert_str(str(b.war_rep("player")["label"])).is_equal(str(a.war_rep("player")["label"]))


func test_marriages_form_alliances_and_claims() -> void:
	var f := _run(120)
	assert_int(f.marriages().size()).is_greater(0)
	var kinds := {}
	for t: Dictionary in f.ties(true):
		kinds[t["kind"]] = true
	assert_bool(kinds.has("marriage")).is_true()
	assert_bool(kinds.has("rivalry") or kinds.has("kin")).is_true()
	# player marriage adds an inheritance claim, never automatic kingship
	var houses := f.factions().filter(func(x: Dictionary) -> bool: return x["kind"] == "house")
	f.change_relation("player", houses[0]["id"], "trust", 60.0)
	var before: float = f.kingship_paths()["inheritance"]["progress"]
	var wed := false
	for i in 20:
		f.tick_day(200 + i, {})
		if f.propose_marriage("player", houses[0]["id"]).get("accepted", false):
			wed = true
			break
	assert_bool(wed).is_true()
	f.tick_day(300, {})
	assert_float(f.kingship_paths()["inheritance"]["progress"]).is_greater(before)
	assert_float(f.kingship_paths()["inheritance"]["progress"]).is_less(100.0)


func test_kingship_paths_and_war_rep() -> void:
	var f := _run(5)
	var p := f.kingship_paths()
	for k in ["inheritance", "election", "conquest", "coronation", "uprising"]:
		assert_bool(p.has(k)).is_true()
	f.record_war_act("warlord", "massacre")
	f.record_war_act("warlord", "massacre")
	assert_str(f.war_rep("warlord")["label"]).is_equal("ruthless")
	f.record_war_act("knight", "honour_surrender")
	f.record_war_act("knight", "keep_treaty")
	assert_str(f.war_rep("knight")["label"]).is_equal("honourable")
	f.record_war_act("runner", "flee_battle")
	f.record_war_act("runner", "abandon_allies")
	assert_str(f.war_rep("runner")["label"]).is_equal("cowardly")


func test_church_and_sects() -> void:
	var f := _run(3)
	var c := f.church_influence("caldrenn")
	assert_bool(c["known"]).is_true()
	assert_bool(f.church_influence("ongur_khanate")["known"]).is_false()
	f.discover_church("ongur_khanate")
	assert_bool(f.church_influence("ongur_khanate")["known"]).is_true()
	assert_int(f.sects().size()).is_greater(0)
	for w in 60:
		f.tick_week(w, {})
	assert_int(f.sects().size()).is_greater(2)


func test_catch_up_is_bounded_and_perf() -> void:
	var f := _run(3)
	var t0 := Time.get_ticks_usec()
	f.catch_up(200, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
	t0 = Time.get_ticks_usec()
	for h in 24:
		f.tick_hour(h, {})
	f.tick_day(500, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
