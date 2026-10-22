extends GdUnitTestSuite
## Sieges (scripts/realm/siege.gd, docs/design/WAR_COMMAND_RULEBOOK.md §41-47), advisors (§18-19), war goals and claims
## (§55-59): engine build times, approaches, breaches with inner defence lines, street layers, surrender with reputation.

const Siege := preload("res://scripts/realm/siege.gd")
const Tactical := preload("res://scripts/realm/tactical.gd")
const WarAdvisors := preload("res://scripts/realm/war_advisors.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const Campaign := preload("res://scripts/realm/campaign.gd")


func before_test() -> void:
	WorldGen.setup(2024)


func _mk(over := {}) -> RefCounted:
	var p: Vector2 = WorldGen.settlements[2]["pos"]
	var spec := {"key": "t1", "name": "Greyford Keep", "pos": [p.x, p.y], "kind": "town", "defender": "caldrenn", "attacker": "player", "seed": 5, "garrison": 300, "food_days": 30.0,
		"water_days": 20.0, "civilians": 600, "wall_age": 0.4, "wall_radius": 110.0, "gates": [0.0, PI], "commander": {"name": "Castellan Holt", "personality": "loyal"},
		"camp": {"men": 1200, "engineers": 20, "guards": 200, "medical": 30}, "tech": 2, "timber": 0.8}
	for k: String in over:
		spec[k] = over[k]
	return Siege.create(spec)


func _days(sg: RefCounted, n: int) -> void:
	for i in n:
		sg.tick_day()


# --- engines (R§44) ---------------------------------------------------------------------------------------

func test_engines_take_days_to_build_and_engineers_shorten_it() -> void:
	var sg := _mk()
	var r: Dictionary = sg.build_engine("ram")
	assert_bool(bool(r["ok"])).is_true()
	var days := int(r["days"])
	assert_int(days).is_between(2, 4)
	for i in days - 1:
		sg.tick_day()
	assert_int(sg.engine_count("ram")).is_equal(0)
	assert_str(String(sg.view()["engines"][0]["state"])).is_equal("building")
	sg.tick_day()
	assert_int(sg.engine_count("ram")).is_equal(1)
	# a tower needs much longer than a ram; a trebuchet longer still
	var sg2 := _mk()
	assert_bool(sg2.build_days("tower") > sg2.build_days("ram")).is_true()
	assert_bool(sg2.build_days("trebuchet") > sg2.build_days("tower")).is_true()
	# more engineers, faster
	var many := _mk({"camp": {"men": 1200, "engineers": 120, "guards": 200, "medical": 30}})
	var few := _mk({"camp": {"men": 1200, "engineers": 12, "guards": 200, "medical": 30}})
	assert_bool(many.build_days("tower") < few.build_days("tower")).is_true()
	# technology and timber matter
	var low_tech := _mk({"tech": 1})
	var res: Dictionary = low_tech.build_engine("trebuchet")
	assert_bool(bool(res["ok"])).is_false()
	var bare := _mk({"timber": 0.15})
	assert_bool(bare.build_days("ram") >= sg2.build_days("ram")).is_true()
	# parallel builds share the engineers
	var par := _mk()
	par.build_engine("catapult")
	var second: Dictionary = par.build_engine("ballista")
	assert_bool(float(second["days"]) >= par.build_days("ballista", 1)).is_true()


# --- approaches and supplies (R§42) ----------------------------------------------------------------------------

func test_starving_and_cutting_water_wear_the_garrison_down() -> void:
	var sg := _mk({"food_days": 12.0, "water_days": 8.0, "well": false})
	var m0: float = sg.s["morale"]
	sg.approach("starve", true)
	sg.approach("cut_water", true)
	_days(sg, 7)
	assert_float(float(sg.s["food_days"])).is_less(6.0)
	assert_float(float(sg.s["water_days"])).is_less(2.0)
	assert_float(float(sg.s["morale"])).is_less(m0 - 0.05)
	# a fortress with a deep well shrugs off a cut stream
	var wellsg := _mk({"water_days": 8.0, "well": true})
	wellsg.approach("cut_water", true)
	_days(wellsg, 7)
	assert_float(float(wellsg.s["water_days"])).is_greater(5.0)
	# when the granaries are empty the garrison dwindles
	var dry := _mk({"food_days": 1.0})
	_days(dry, 6)
	assert_int(int(dry.s["garrison"])).is_less(300)


func test_bombardment_breaches_the_older_wall_first() -> void:
	var sg := _mk({"wall_age": 0.5})
	sg.s["walls"][0]["age"] = 0.95
	sg.s["walls"][1]["age"] = 0.0
	sg.s["walls"][2]["age"] = 0.0
	sg.s["walls"][3]["age"] = 0.0
	sg.build_engine("catapult")
	sg.build_engine("catapult")
	sg.approach("bombard", true)
	var first := -1
	for i in 40:
		sg.tick_day()
		var br: Array = sg.breaches()
		if not br.is_empty():
			first = int(br[0])
			break
	assert_int(first).is_equal(0)
	assert_bool(sg.wall_label() != "High").is_true()


func test_ram_smashes_the_gate_and_a_tunnel_brings_down_a_wall() -> void:
	var sg := _mk()
	sg.build_engine("ram")
	_days(sg, 4)
	sg.approach("gate_assault", true)
	_days(sg, 8)
	assert_float(float(sg.s["gates"][0]["hp"])).is_equal(0.0)
	assert_bool(sg.breaches().size() > 0).is_true()
	var t := _mk({"camp": {"men": 1200, "engineers": 60, "guards": 200, "medical": 30}})
	var r: Dictionary = t.approach("undermine", true, {"wall": 2})
	assert_bool(bool(r["ok"])).is_true()
	var broke := false
	for i in 40:
		t.tick_day()
		if bool(t.s["walls"][2]["breach"]):
			broke = true
			break
	assert_bool(broke).is_true()


# --- breaches and inner lines (R§45) --------------------------------------------------------------------------------

func test_a_breach_makes_the_defenders_raise_an_inner_line_and_the_map_shows_it() -> void:
	var sg := _mk()
	assert_int(int(sg.s["inner_lines"])).is_equal(0)
	sg.s["walls"][1]["hp"] = 0.0
	sg.s["walls"][1]["breach"] = true
	sg.tick_day()
	assert_int(int(sg.s["inner_lines"])).is_greater_equal(1)
	assert_bool(sg.plan().size() > 3).is_true()
	# the assault battlefield has the breach, the gate, and a barricade line behind the breach
	var spec: Dictionary = sg.assault_spec()
	spec["deploy"] = false
	var tt: RefCounted = Tactical.create(spec)
	var cnt: Array = []
	for code in Tactical.CHARS.length():
		cnt.append(0)
	for k in tt.tc.size():
		cnt[int(tt.tc[k])] += 1
	assert_int(int(cnt[Tactical.T_BREACH])).is_greater(0)
	assert_int(int(cnt[Tactical.T_BARR])).is_greater(0)
	assert_int(int(cnt[Tactical.T_WALL])).is_greater(10)
	assert_int(tt.side_units(0).size()).is_greater(2)
	assert_int(tt.side_units(1).size()).is_greater(2)
	# destroying a wall does not automatically win: a stronger garrison repels a weak assault
	var weak := _mk({"camp": {"men": 120, "engineers": 10, "guards": 20, "medical": 5}, "garrison": 500})
	weak.s["walls"][0]["breach"] = true
	weak.s["walls"][0]["hp"] = 0.0
	weak.tick_day()
	var res: Dictionary = weak.auto_assault()
	assert_bool(bool(res["won"])).is_false()
	assert_str(String(weak.s["status"])).is_equal("active")
	assert_int(int(weak.s["camp"]["men"])).is_less(120)


func test_street_fighting_moves_through_layers_before_the_place_falls() -> void:
	var sg := _mk({"kind": "castle"})
	assert_int((sg.s["layers"] as Array).size()).is_equal(4)
	assert_str(String(sg.view()["layer"])).is_equal("Outer wall")
	sg.s["walls"][0]["breach"] = true
	sg.s["walls"][0]["hp"] = 0.0
	var won_res := {"winner": "a", "units": [{"side": 0, "men0": 100, "men": 80, "state": "holding"}, {"side": 1, "men0": 100, "men": 10, "state": "holding"}]}
	var r1: Dictionary = sg.apply_assault(won_res)
	assert_bool(bool(r1["won"])).is_true()
	assert_bool(bool(r1["fell"])).is_false()
	assert_int(int(sg.s["layer"])).is_equal(1)
	assert_str(String(sg.view()["layer"])).is_equal("Courtyard")
	# the next layer is a street fight on a houses-and-lanes map
	var spec: Dictionary = sg.assault_spec()
	spec["deploy"] = false
	var tt: RefCounted = Tactical.create(spec)
	var bl := 0
	for k in tt.tc.size():
		if int(tt.tc[k]) == Tactical.T_BLDG:
			bl += 1
	assert_int(bl).is_greater(200)
	for i in 2:
		sg.s["garrison"] = 300
		sg.apply_assault(won_res)
	sg.s["garrison"] = 300
	var last: Dictionary = sg.apply_assault(won_res)
	assert_bool(bool(last["fell"])).is_true()
	assert_str(String(sg.s["status"])).is_equal("fallen")


func test_the_garrison_sorties_against_a_weak_camp() -> void:
	var sg := _mk({"camp": {"men": 300, "engineers": 40, "guards": 15, "medical": 10}, "garrison": 400})
	sg.build_engine("ram")
	var fired := false
	for i in 40:
		sg.tick_day()
		if bool(sg.s["sortie_due"]):
			fired = true
			break
	assert_bool(fired).is_true()
	var spec: Dictionary = sg.sortie_spec()
	spec["deploy"] = false
	var tt: RefCounted = Tactical.create(spec)
	assert_str(String(spec["surprise"])).is_equal("b")
	assert_int(tt.side_units(1).size()).is_greater(1)
	var res: Dictionary = sg.auto_sortie()
	assert_int((res["lines"] as Array).size()).is_equal(1)
	assert_int(int(sg.s["sorties"])).is_equal(1)


# --- surrender (R§47) -----------------------------------------------------------------------------------------------------

func test_a_reputation_for_massacre_makes_defeat_certain_but_surrender_impossible() -> void:
	var sg := _mk({"food_days": 1.0, "water_days": 1.0, "morale": 0.05, "hope": 0.0, "civilians": 900})
	sg.s["walls"][0]["breach"] = true
	var honourable := {"honour": 20.0, "ruthless": 0.0, "cowardly": 0.0, "label": "honourable", "acts": 5}
	var butcher := {"honour": -10.0, "ruthless": 45.0, "cowardly": 0.0, "label": "ruthless", "acts": 5}
	var unknown := {"honour": 0.0, "ruthless": 0.0, "cowardly": 0.0, "label": "unknown", "acts": 0}
	var a: Dictionary = sg.surrender_eval(honourable)
	var b: Dictionary = sg.surrender_eval(butcher)
	var c: Dictionary = sg.surrender_eval(unknown)
	assert_bool(bool(a["accept"])).is_true()
	assert_bool(bool(c["accept"])).is_true()
	assert_bool(bool(b["accept"])).is_false()
	assert_str(String(b["refusal"])).is_equal("massacre")
	assert_bool(float(b["score"]) >= float(b["threshold"])).is_true()     # the defeat is certain, the refusal is about trust
	assert_bool(String(" ".join(PackedStringArray(b["reasons"]))).contains("massacre")).is_true()
	var refused: Dictionary = sg.negotiate(butcher)
	assert_bool(bool(refused["surrendered"])).is_false()
	assert_str(String(sg.s["status"])).is_equal("active")
	var taken: Dictionary = sg.negotiate(honourable)
	assert_bool(bool(taken["surrendered"])).is_true()
	assert_str(String(sg.s["status"])).is_equal("fallen")


func test_commander_personality_and_hope_change_the_answer() -> void:
	var stubborn := _mk({"commander": {"name": "A", "personality": "stubborn"}, "food_days": 8.0, "morale": 0.3, "hope": 0.2})
	var cautious := _mk({"commander": {"name": "B", "personality": "cautious"}, "food_days": 8.0, "morale": 0.3, "hope": 0.2})
	var none := {"honour": 0.0, "ruthless": 0.0, "label": "unknown"}
	assert_float(float(cautious.surrender_eval(none)["threshold"])).is_less(float(stubborn.surrender_eval(none)["threshold"]))
	assert_float(float(stubborn.surrender_eval(none)["score"])).is_equal_approx(float(cautious.surrender_eval(none)["score"]), 0.0001)
	# fresh and fed, with a relief army coming: no surrender
	var fresh := _mk({"food_days": 40.0, "morale": 0.9, "hope": 0.9})
	assert_bool(bool(fresh.surrender_eval(none)["accept"])).is_false()
	assert_str(String(fresh.surrender_eval(none)["refusal"])).is_equal("hope")
	# terms sweeten it
	var borderline := _mk({"food_days": 6.0, "morale": 0.25, "hope": 0.1})
	var plain: Dictionary = borderline.surrender_eval(none)
	var kind: Dictionary = borderline.surrender_eval(none, {"spare_civilians": true, "free_passage": true})
	assert_float(float(kind["threshold"])).is_less(float(plain["threshold"]))
	# the victor's conduct is recorded as war acts
	assert_str(String(_mk().conduct("massacre"))).is_equal("massacre")
	assert_str(String(_mk().conduct("spare"))).is_equal("spare_civilians")


func test_bribery_can_open_a_gate_for_enough_gold() -> void:
	var opened := 0
	for sd in 30:
		var sg := _mk({"seed": sd + 1, "morale": 0.3, "commander": {"name": "x", "personality": "cautious"}})
		if bool((sg.bribe(1500) as Dictionary)["ok"]):
			opened += 1
	assert_bool(opened > 3 and opened < 30).is_true()
	var cheap := 0
	for sd2 in 30:
		var sg2 := _mk({"seed": sd2 + 1, "morale": 0.9, "commander": {"name": "x", "personality": "stubborn"}})
		if bool((sg2.bribe(50) as Dictionary)["ok"]):
			cheap += 1
	assert_int(cheap).is_less(opened)


# --- persistence --------------------------------------------------------------------------------------------------------------

func test_json_round_trip_continues_identically() -> void:
	var sg := _mk()
	sg.build_engine("catapult")
	sg.build_engine("ram")
	sg.approach("bombard", true)
	sg.approach("starve", true)
	_days(sg, 6)
	var js := JSON.stringify(sg.serialize())
	var back: RefCounted = Siege.restore(JSON.parse_string(js))
	_days(sg, 8)
	_days(back, 8)
	assert_str(JSON.stringify(back.serialize())).is_equal(JSON.stringify(sg.serialize()))
	assert_bool(js.contains("Vector2")).is_false()


# --- advisors (R§18-19) -------------------------------------------------------------------------------------------------------------

func test_advisors_give_situation_based_advice_and_can_be_wrong() -> void:
	var staff: Array = WarAdvisors.roster(77)
	assert_int(staff.size()).is_equal(4)
	var sg := _mk()
	sg.s["walls"][3]["age"] = 0.95
	sg.s["walls"][3]["hp"] = 60.0
	var right := 0
	var wrong := 0
	var picked_old := 0
	for tick in 60:
		for line: Dictionary in WarAdvisors.siege_advice(sg.view(), staff, 9, tick, sg.s["walls"]):
			if String(line["role"]) == "siege_engineer":
				if bool(line["correct"]):
					right += 1
					if int(line["wall"]) == 3:
						picked_old += 1
					assert_str(String(line["text"])).contains("older")
				else:
					wrong += 1
					assert_int(int(line["wall"])).is_not_equal(3)
	assert_bool(right > 5 and wrong > 0).is_true()
	assert_int(picked_old).is_equal(right)
	# a skilled, experienced advisor errs less than a green one
	var good := {"role": "siege_engineer", "skill": 0.95, "experience": 0.95, "bias": "none", "flaw": "misread"}
	var green := {"role": "siege_engineer", "skill": 0.3, "experience": 0.2, "bias": "cautious", "flaw": "lie"}
	assert_float(WarAdvisors.error_chance(good)).is_less(WarAdvisors.error_chance(green))
	# battlefield lines come from the actual situation
	var tt: RefCounted = Tactical.create({"seed": 3, "name": "T", "center": [-1274.0, -2318.0], "deploy": false, "attacker": "a", "sides": {
		"a": {"faction": "caldrenn", "player": true, "name": "a", "units": [{"cid": 0, "name": "I", "kind": "infantry", "men": 300, "quality": 0.6, "morale": 0.7, "fatigue": 0.0}], "cmd": {"name": "G", "personality": "loyal", "skill": 2}, "supply": 4.0},
		"b": {"faction": "caldrenn", "player": false, "name": "b", "units": [{"cid": 0, "name": "I", "kind": "infantry", "men": 300, "quality": 0.6, "morale": 0.7, "fatigue": 0.0}], "cmd": {"name": "G", "personality": "loyal", "skill": 2}, "supply": 4.0}}})
	var adv: Array = WarAdvisors.battle_advice(tt, 0, staff, 1)
	var kinds := {}
	for l: Dictionary in adv:
		kinds[String(l["role"])] = true
	assert_bool(kinds.has("strategist") and kinds.has("logistics") and kinds.has("scout_master")).is_true()


# --- campaign: sieges, goals, claims, independence -------------------------------------------------------------------------------

func test_campaign_siege_capture_goal_claim_and_political_cost() -> void:
	var h: RefCounted = Hub.new()
	var cm: RefCounted = h.mod("campaign")
	cm.call("set_hq", 0)
	cm.call("tick_day", 0, {})
	var sh: RefCounted = h.mod("strongholds")
	var st: Dictionary = {}
	for s: Dictionary in sh.call("strongholds"):
		if String(s["owner"]) != "player":
			st = s
			break
	assert_bool(st.is_empty()).is_false()
	var sid := int(st["id"])
	var node: int = cm.call("nearest_node", st["pos"])
	var army: int = cm.call("spawn_army", "player", node, 1500, "aggressive", "Siege Host")
	var gid: int = cm.call("add_war_goal", "capture_fortress", sid, String(st["owner"]))
	assert_int(gid).is_greater(0)
	var sg: RefCounted = cm.call("siege_begin", sid, "player", [army])
	assert_object(sg).is_not_null()
	assert_int(int(cm.call("sieges").size())).is_equal(1)
	assert_bool(int(sg.s["camp"]["engineers"]) >= 10).is_true()
	# weaken and take it
	sg.s["walls"][0]["breach"] = true
	sg.s["walls"][0]["hp"] = 0.0
	sg.s["garrison"] = 20
	sg.s["morale"] = 0.05
	sg.s["food_days"] = 0.0
	var ev: Dictionary = cm.call("siege_negotiate", String(sg.s["key"]))
	assert_bool(bool(ev["surrendered"])).is_true()
	assert_str(String((sh.call("stronghold", sid) as Dictionary)["owner"])).is_equal("player")
	cm.call("tick_day", 1, {})
	var goals: Array = cm.call("war_goals")
	assert_bool(bool((goals[0] as Dictionary)["done"])).is_true()
	var cost: Dictionary = cm.call("war_cost")
	assert_bool(bool(cost["achieved"])).is_true()
	assert_float(float(cost["cost_per_day"])).is_greater(1.0)
	# the old holder keeps a claim on land taken (R§59)
	var land: RefCounted = h.mod("land")
	var region := str(int(cm.call("nearest_node", st["pos"])))
	land.call("conquer", region, "player", 5)
	var cl: Array = land.call("claimants", region)
	assert_bool(cl.size() > 0).is_true()
	# independence is hard with 300 people (R§57)
	var weak: Dictionary = cm.call("independence_readiness", region, {"population": 0.05, "food": 0.4, "army": 0.05, "defences": 0.1}, 1.0)
	assert_str(String(weak["verdict"])).is_equal("destroyed")
	var strong: Dictionary = cm.call("independence_readiness", region, {"population": 0.9, "food": 0.9, "money": 0.8, "army": 0.8, "defences": 0.9, "officers": 0.8, "recognition": 0.7, "legitimacy": 0.8, "trade": 0.8, "administration": 0.8}, 0.8)
	assert_str(String(strong["verdict"])).is_equal("viable")
	# a saved campaign keeps sieges, goals and staff
	var d: Dictionary = cm.call("serialize")
	var c2 := Campaign.new()
	c2.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_int(int(c2.sieges(false).size())).is_equal(1)
	assert_int(int(c2.war_goals().size())).is_equal(1)
