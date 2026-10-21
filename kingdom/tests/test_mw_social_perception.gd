extends GdUnitTestSuite
## MW-5 social perception: legitimacy per kingdom, disguise exposure, aura misjudgement, bump reactions, determinism, cost.

const SP := preload("res://scripts/realm/social_perception.gd")

func _lord() -> Dictionary:
	return {"id": "lord", "origin": "caldrenn", "title_rank": 4, "insignia": 1.0, "gear_value": 0.9, "protection": 0.5, "companions": 2}

func test_legitimacy_across_kingdoms() -> void:
	assert_float(SP.legitimacy("caldrenn", "caldrenn")).is_equal(1.0)
	assert_float(SP.legitimacy("caldrenn", "solmarch")).is_equal(0.0)
	assert_float(SP.legitimacy("caldrenn", "solmarch", {"allied": ["solmarch"]})).is_equal(1.0)
	assert_float(SP.legitimacy("caldrenn", "veylwood")).is_equal(0.5)
	var sp := SP.new()
	var home: float = sp.read({"id": "o", "kingdom": "caldrenn"}, _lord())["authority"]
	var east: float = sp.read({"id": "o", "kingdom": "solmarch"}, _lord())["authority"]
	assert_float(east).is_equal(0.0)
	assert_bool(home > 0.7).is_true()

func test_disguise_exposure() -> void:
	var sp := SP.new()
	var s := _lord()
	s["disguise"] = {"quality": 0.9, "identity": {"id": "beggar", "title_rank": 0, "gear_value": 0.05, "origin": "caldrenn"}}
	var dull := {"id": "d", "perception": 0.1}
	var sharp := {"id": "s", "perception": 1.0, "knows_true_id": true}
	var a := sp.read(dull, s)
	assert_str(a["perceived_id"]).is_equal("beggar")
	assert_bool(a["wealth"] < 0.2).is_true()
	assert_float(sp.identity(sharp, s)["chance"]).is_greater(sp.identity(dull, s)["chance"])
	s["evidence"] = 1.0
	s["disguise"]["quality"] = 0.3
	sp.clear()
	assert_bool(sp.read(sharp, s)["exposed"]).is_true()
	assert_str(sp.read(sharp, s)["perceived_id"]).is_equal("lord")

func test_aura_misjudgement_and_suppression() -> void:
	var sp := SP.new()
	var mage := {"id": "m", "aura_emit": 0.8}
	var sensitive := {"id": "a", "magic_sense": 0.9, "intelligence": 0.9}
	var dim := {"id": "b", "magic_sense": 0.9, "intelligence": 0.1, "stress": 1.0}
	var blind := {"id": "c", "magic_sense": 0.0}
	assert_float(sp.magic_pressure(blind, mage)).is_equal(0.0)
	assert_float(sp.magic_pressure(sensitive, mage)).is_greater(0.3)
	mage["aura_suppress"] = 0.8
	assert_float(sp.magic_pressure(sensitive, mage)).is_less(0.2)
	mage["aura_suppress"] = 0.0
	mage["aura_emit"] = 0.4
	var diff: int = 0
	for d in 20:
		if absf(sp.magic_pressure(dim, mage, {"day": d}) - sp.magic_pressure(sensitive, mage, {"day": d})) > 0.05:
			diff += 1
	assert_int(diff).is_greater(5)

func test_bump_varies_by_status() -> void:
	var sp := SP.new()
	var o := {"id": "npc", "status": 0.3, "persona": {"courage": 0.6, "pious": 0.2, "greedy": 0.7}}
	assert_str(sp.bump_reaction(o, _lord())).is_equal("apologise")
	assert_str(sp.bump_reaction({"id": "n2", "persona": {"pious": 0.9}}, _lord())).is_equal("bow")
	assert_str(sp.bump_reaction(o, {"id": "rich", "gear_value": 0.9})).is_equal("exploit")
	assert_str(sp.bump_reaction({"id": "meek", "persona": {"courage": 0.2}}, {"id": "brute", "weapons": 1.0, "companions": 4, "strength": 1.0})).is_equal("flee")
	assert_str(sp.bump_reaction({"id": "n3", "persona": {"courage": 0.1}}, {"id": "m", "aura_emit": 1.0}.merged({"x": 0}))).is_not_empty()
	assert_str(sp.bump_reaction({"id": "n4", "magic_sense": 1.0, "intelligence": 1.0, "persona": {"courage": 0.1}}, {"id": "m", "aura_emit": 1.0})).is_equal("flee")
	assert_str(sp.bump_reaction({"id": "n5", "status": 0.9, "persona": {"courage": 0.8}}, {"id": "p", "gear_value": 0.05})).is_equal("demand_apology")
	assert_str(sp.bump_reaction({"id": "n6"}, {"id": "q"})).is_equal("ignore")

func test_determinism_and_cost() -> void:
	var o := {"id": "o", "perception": 0.5, "magic_sense": 0.5}
	var s := _lord()
	s["aura_emit"] = 0.5
	assert_dict(SP.new().read(o, s, {"day": 3})).is_equal(SP.new().read(o, s, {"day": 3}))
	var sp := SP.new()
	var t := Time.get_ticks_usec()
	for i in 1000:
		sp.read(o, s, {"hour": i % 4})
	assert_int(Time.get_ticks_usec() - t).is_less(100000)
	assert_int(sp.hits).is_greater(990)
