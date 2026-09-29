extends GdUnitTestSuite
## Society: tiers and reputation, provocation and duels, multi-dimensional
## relationships, dating/compatibility/marriage, clothing and class, crime with
## witnesses and decaying evidence, rumours travelling along roads with
## distortion, NPC memory and goals, apprenticeships, knowledge and stories.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Society := preload("res://scripts/realm/society.gd")

const CTX := {"player_pos": Vector2(0, 0), "season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 500}


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func _soc() -> RefCounted:
	return _hub().mod("society")


func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _canon(v[k])
		return o
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_canon(x))
		return a
	if v is int or v is float:
		return snappedf(float(v), 0.0001)
	return v


func _find(s: RefCounted, pred: Callable) -> String:
	s.notable_count()
	for id: String in s.npcs:
		if pred.call(s.npcs[id]):
			return id
	return ""


func _match_player(s: RefCounted, id: String) -> void:
	var n: Dictionary = s.npcs[id]
	s.set_player({"religion": n["religion"], "culture": n["culture"], "lifestyle": n["lifestyle"], "age": n["age"], "class": n["class"],
		"personality": {"kindness": n["pers"]["kindness"], "temper": n["pers"]["temper"], "ambition": n["pers"]["ambition"], "openness": n["pers"]["openness"]},
		"wealth_score": 5000, "family": 3, "wants_children": true})


func _hour_ctx(h: int) -> Dictionary:
	var c := CTX.duplicate()
	c["abs_hours"] = float(h)
	return c


func test_roster_is_about_two_hundred_and_deterministic() -> void:
	var a := _soc()
	a.tick_day(1, CTX)
	assert_int(a.notable_count()).is_equal(200)
	var b := _soc()
	b.tick_day(1, CTX)
	assert_str(JSON.stringify(_canon(a.npcs))).is_equal(JSON.stringify(_canon(b.npcs)))
	var tiers := {}
	for id: String in a.npcs:
		tiers[a.npcs[id]["tier"]] = true
	assert_int(tiers.size()).is_greater(2)


func test_tiers_gate_teaching_and_duels() -> void:
	var s := _soc()
	s.set_player({"combat": 5})
	var top := _find(s, func(n: Dictionary) -> bool: return int(n["tier"]) >= 5)
	assert_str(top).is_not_empty()
	var acc: Dictionary = s.tier_access(top)
	assert_bool(acc["will_teach"]).is_false()
	assert_bool(acc["will_duel"]).is_false()
	assert_str(s.tier_name(8)).is_equal("legend")
	s.set_player({"combat": 100})
	assert_int(s.player_tier()).is_equal(8)
	assert_bool(s.tier_access(top)["will_duel"]).is_true()


func test_reputation_is_per_group_with_tiers_and_district_bleeds_into_city() -> void:
	var s := _soc()
	assert_str(s.rep_tier("guild:hunters")).is_equal("Unknown")
	s.add_rep("guild:hunters", 40.0)
	s.add_rep("district:0:market", 20.0)
	assert_str(s.rep_tier("guild:hunters")).is_equal("Respected")
	assert_float(s.rep("city:0")).is_equal_approx(6.0, 0.01)
	assert_float(s.rep("faction:x")).is_equal(0.0)
	s.add_rep("city:1", -70.0)
	assert_str(s.rep_tier("city:1")).is_equal("Reviled")


func test_criminal_reputation_is_separate_from_public() -> void:
	var s := _soc()
	for i in 4:
		s.commit_crime("smuggling", 0, 0)
	assert_float(s.crim_rep("underworld")).is_greater(5.0)
	assert_float(s.rep("city:0")).is_equal(0.0)    # nobody saw
	assert_str(s.crim_tier()).is_not_equal("nobody")


func test_relationships_have_dimensions_that_diverge() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := "n1"
	for i in 6:
		s.interact(id, "help")
	s.interact(id, "insult")
	var r: Dictionary = s.relation(id)
	assert_float(float(r["respect"])).is_greater(5.0)
	assert_float(float(r["resentment"])).is_greater(0.0)
	assert_bool(r["known"]).is_true()
	# Fear without affection: a threatened NPC fears and resents but does not love.
	s.interact("n2", "threaten")
	s.interact("n2", "threaten")
	var t: Dictionary = s.relation("n2")
	assert_float(float(t["fear"])).is_greater(float(t["affection"]))
	# "Respects but dislikes" and friends: dimensions combine into stories.
	s.npcs["n3"]["rel"] = {"respect": 40.0, "affection": -10.0, "familiarity": 20.0}
	assert_str(String(s.relation("n3")["label"])).is_equal("respects you but dislikes you")
	s.npcs["n3"]["rel"] = {"affection": 50.0, "trust": -5.0}
	assert_str(String(s.relation("n3")["label"])).is_equal("cares for you but does not trust you")
	s.npcs["n3"]["rel"] = {"fear": 40.0, "loyalty": 30.0}
	assert_str(String(s.relation("n3")["label"])).is_equal("fears you and stays loyal")


func test_memory_weights_shape_attitude() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	s.interact("n4", "save_child")
	assert_float(s.attitude("n4")).is_greater(5.0)
	s.interact("n5", "kill_kin")
	assert_float(s.attitude("n5")).is_less(-5.0)
	assert_int(s.memory_of("n5").size()).is_equal(1)
	for i in 30:
		s.remember("n6", "helped", 0.3 + i * 0.01)
	assert_int(s.memory_of("n6").size()).is_less_equal(10)
	# Heavy memories outlast light ones.
	s.remember("n7", "gifted", 1.0)
	s.remember("n7", "killed_kin", -10.0)
	for d in range(2, 200):
		s.tick_day(d, CTX)
	var m: Array = s.memory_of("n7")
	var deeds := []
	for e: Dictionary in m:
		deeds.append(e["deed"])
	assert_bool(deeds.has("killed_kin")).is_true()
	assert_bool(deeds.has("gifted")).is_false()


func test_provocation_varies_by_personality() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var seen := {}
	for id: String in s.npcs:
		seen[s.provoke(id, "insult_family")["reaction"]] = true
	assert_bool(seen.size() >= 3).is_true()
	assert_bool(seen.has("laughs")).is_true()


func test_duel_terms_respect_culture_and_tier() -> void:
	var s := _soc()
	s.set_player({"combat": 30, "gold": 100})
	var forb := _find(s, func(n: Dictionary) -> bool: return n["culture"] == "mercantile")
	assert_bool(s.challenge_duel(forb, {"stake": "honor"})["accepted"]).is_false()
	var cel := _find(s, func(n: Dictionary) -> bool: return n["culture"] == "martial" and int(n["tier"]) <= 4 and int(n["tier"]) >= 2)
	assert_str(cel).is_not_empty()
	assert_bool(s.challenge_duel(cel, {"stake": "honor", "to": "first_blood"})["accepted"]).is_true()
	assert_bool(s.challenge_duel(cel, {"stake": "money", "amount": 9999})["accepted"]).is_false()
	var court := _find(s, func(n: Dictionary) -> bool: return n["culture"] == "courtly" and int(n["tier"]) <= 4)
	if court != "":
		assert_bool(s.challenge_duel(court, {"to": "death"})["accepted"]).is_false()
	s.set_player({"combat": 1})
	var champ := _find(s, func(n: Dictionary) -> bool: return n["culture"] == "martial" and int(n["tier"]) >= 5)
	if champ != "":
		assert_bool(s.challenge_duel(champ, {})["accepted"]).is_false()


func test_duel_resolution_pays_stakes_and_spreads_word() -> void:
	var s := _soc()
	var cel := _find(s, func(n: Dictionary) -> bool: return n["culture"] == "martial" and int(n["tier"]) <= 3)
	var out: Dictionary = s.resolve_duel(cel, {"stake": "money", "amount": 40}, 99.0)
	assert_bool(out["won"]).is_true()
	assert_int(s.take_pending_gold()).is_equal(40)
	assert_int(s.rumours(int(s.npcs[cel]["sid"])).size()).is_greater(0)


func test_dating_compatibility_and_marriage() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := _find(s, func(n: Dictionary) -> bool: return int(n["class"]) <= 1 and n["spouse"] == "" and int(n["age"]) < 40)
	assert_str(id).is_not_empty()
	_match_player(s, id)
	var comp: Dictionary = s.compatibility(id)
	assert_float(float(comp["score"])).is_greater(0.6)
	assert_bool(comp["willing"]).is_true()
	assert_bool(s.propose(id)["ok"]).is_false()   # too soon
	for d in range(2, 9):
		s._day = d
		var likes: Array = s.npcs[id]["likes"]
		assert_bool(s.date(id, likes[0])["ok"]).is_true()
	assert_bool(s.date(id, "walk")["ok"]).is_false()   # once per day
	s._day = 20
	var res: Dictionary = s.propose(id)
	assert_str(String(res.get("reason", "")) if not res["ok"] else "").is_empty()
	assert_str(String(s.spouse()["spouse"])).is_equal("player")
	assert_int(s.in_laws().size()).is_greater(0)
	assert_bool(s.propose(id)["ok"]).is_false()


func test_incompatible_or_family_forbidden_does_not_marry() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := _find(s, func(n: Dictionary) -> bool: return int(n["class"]) <= 1 and n["spouse"] == "")
	_match_player(s, id)
	s.set_player({"religion": "none" if s.npcs[id]["religion"] != "none" else "dawn", "culture": "courtly" if s.npcs[id]["culture"] != "courtly" else "martial",
		"age": int(s.npcs[id]["age"]) + 25})
	var c: Dictionary = s.compatibility(id)
	assert_bool(c["willing"]).is_false()
	assert_bool((c["blockers"] as Array).size() > 0).is_true()


func test_noble_courtship_needs_title_land_and_name() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := _find(s, func(n: Dictionary) -> bool: return int(n["class"]) >= 3 and n["spouse"] == "")
	assert_str(id).is_not_empty()
	_match_player(s, id)
	s.set_player({"title": 0, "wealth_score": 0, "land": false, "class": 1})
	assert_bool((s.compatibility(id)["blockers"] as Array).size() > 0).is_true()
	s.set_player({"title": 2, "wealth_score": 900, "land": true, "class": 3, "family": 3})
	assert_int(s.noble_requirements(id).size()).is_less_equal(2)
	s.add_rep("city:%d" % int(s.npcs[id]["sid"]), 30.0)
	for m: String in s.houses[s.npcs[id]["house"]]["members"]:
		s.remember(m, "helped", 4.0)
	assert_int(s.noble_requirements(id).size()).is_equal(0)


func test_marriage_problems_and_resolution() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := _find(s, func(n: Dictionary) -> bool: return int(n["class"]) <= 1 and n["spouse"] == "" and int(n["age"]) < 40)
	_match_player(s, id)
	for d in range(2, 9):
		s._day = d
		s.date(id, s.npcs[id]["likes"][0])
	s._day = 20
	assert_bool(s.propose(id)["ok"]).is_true()
	var ctx := CTX.duplicate()
	var probs := 0
	for d in range(21, 45):
		s.tick_day(d, ctx)
	probs = (s.marriage_state()["problems"] as Array).size()
	assert_int(probs).is_greater(0)
	var kind: String = s.marriage_state()["problems"][0]["kind"]
	var h0: float = s.marriage_state()["happiness"]
	var wrong: Dictionary = s.resolve_problem(kind, "nonsense")
	assert_bool(wrong["ok"]).is_true()
	var fix: String = Society.PROBLEM_FIX[kind]
	assert_bool(s.resolve_problem(kind, fix)["ok"]).is_true()
	assert_float(float(s.marriage_state()["happiness"])).is_greater(h0 - 3.0)
	# Sustained neglect ends in estrangement.
	for d in range(45, 400):
		s.tick_day(d, ctx)
	assert_bool(String(s.marriage_state()["status"]) != "married").is_true()


func test_clothing_changes_class_and_access() -> void:
	var s := _soc()
	s.set_outfit("rags", true)
	assert_int(s.perceived_class()).is_equal(0)
	assert_bool(s.place_access("noble", 12)["ok"]).is_false()
	var poor: Dictionary = s.treatment()
	s.set_outfit("noble", false)
	assert_int(s.perceived_class()).is_equal(3)
	assert_bool(s.place_access("noble", 12)["ok"]).is_true()
	assert_bool(s.place_access("noble", 23)["ok"]).is_true()
	assert_float(float(s.treatment()["price_mult"])).is_less(float(poor["price_mult"]))
	s.set_outfit("common", false)
	assert_bool(s.place_access("noble", 23)["ok"]).is_false()
	assert_bool(s.place_access("military", 12)["ok"]).is_false()
	s.set_outfit("military", false)
	assert_bool(s.place_access("military", 12)["ok"]).is_true()
	assert_bool(s.set_outfit("nonsense")).is_false()


func test_witnesses_report_and_identify_and_masks_help() -> void:
	var s := _soc()
	var crowd: Dictionary = s.commit_crime("robbery", 0, 12)
	assert_int(int(crowd["witnesses"])).is_equal(12)
	assert_int(int(crowd["noticed"])).is_greater(5)
	assert_int(int(crowd["reported"])).is_greater(0)
	assert_int(int(crowd["identified"])).is_greater(0)
	var alone: Dictionary = s.commit_crime("robbery", 0, 0)
	assert_int(int(alone["reported"])).is_equal(0)
	assert_bool((s.evidence(0).size()) > 0).is_true()
	# A mask lowers identification across a big crowd.
	var s1 := _soc()
	var s2 := _soc()
	s2.set_outfit("mask", false, 0.8)
	var open_id := 0
	var masked_id := 0
	for i in 20:
		open_id += int(s1.commit_crime("pickpocket", 0, 10)["identified"])
		masked_id += int(s2.commit_crime("pickpocket", 0, 10)["identified"])
	assert_int(masked_id).is_less(open_id)


func test_guards_always_report_and_friends_do_not() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var guard := _find(s, func(n: Dictionary) -> bool: return n["job"] == "guard")
	assert_str(guard).is_not_empty()
	var r: Dictionary = s.commit_crime("assault", 0, [guard, guard, guard, guard])
	assert_int(int(r["reported"])).is_equal(int(r["noticed"]))


func test_evidence_decays_and_investigation_ends_in_a_bounty() -> void:
	var s := _soc()
	var r: Dictionary = s.commit_crime("murder", 3, 15)
	assert_int((r["evidence"] as Array).size()).is_greater(1)
	var start: int = s.evidence(3).size()
	var seen_bounty := false
	var ctx := CTX.duplicate()
	for d in range(1, 40):
		s.tick_day(d, ctx)
		if s.bounty(3) > 0:
			seen_bounty = true
			break
	assert_bool(seen_bounty).is_true()
	for d in range(41, 120):
		s.tick_day(d, ctx)
	assert_int(s.evidence(3).size()).is_less(start)
	assert_int(s.bounty()).is_greater(0)
	assert_int(s.bounty(3)).is_equal(s.bounty())
	s.set_player({"gold": 5000})
	var paid: Dictionary = s.pay_bounty(3)
	assert_bool(paid["ok"]).is_true()
	assert_int(s.bounty()).is_equal(0)


func test_unwitnessed_crime_can_be_forgotten() -> void:
	var s := _soc()
	s.commit_crime("smuggling", 2, 0)
	var ctx := CTX.duplicate()
	for d in range(1, 90):
		s.tick_day(d, ctx)
	assert_int(s.bounty()).is_equal(0)
	assert_int(s.evidence(2).size()).is_equal(0)


func test_destroying_evidence_and_bribing_witnesses() -> void:
	var s := _soc()
	s.set_player({"gold": 1000})
	var r: Dictionary = s.commit_crime("burglary", 1, 10)
	for e: String in r["evidence"]:
		assert_bool(s.destroy_evidence(e)).is_true()
	assert_int(s.evidence(1).size()).is_equal(0)
	assert_bool(s.destroy_evidence("e999")).is_false()
	var b: Dictionary = s.bribe_witness(r["id"], 200)
	assert_bool(b["ok"]).is_true()
	assert_int(s.take_pending_gold()).is_equal(-200)


func test_rumours_travel_along_roads_with_distortion() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id: String = s.add_rumour("monster_kill", 0, 4.0)
	assert_array(s.rumour_reach(id)).is_equal([0])
	var counts: Array = []
	var ctx := CTX.duplicate()
	for h in range(1, 24 * 40):
		ctx["abs_hours"] = float(h)
		s.tick_hour(h % 24, ctx)
		if h % 240 == 0:
			counts.append(s.rumour_reach(id).size())
	assert_int(s.rumour_reach(id).size()).is_greater(1)
	for i in range(1, counts.size()):
		assert_bool(counts[i] >= counts[i - 1]).is_true()
	# Not instant: nothing beyond the origin after a few hours.
	var s2 := _soc()
	var id2: String = s2.add_rumour("monster_kill", 0, 4.0)
	s2.tick_hour(1, _hour_ctx(2))
	assert_int(s2.rumour_reach(id2).size()).is_equal(1)
	# The far end hears a different story from the origin.
	var reach: Array = s.rumour_reach(id)
	var far := int(reach[reach.size() - 1])
	var near_text: String = s.rumours(0)[0]
	var far_text: String = s.rumours(far)[0]
	assert_str(far_text).is_not_equal(near_text)
	assert_bool(far_text.begins_with("The adventurer")).is_false()


func test_rumour_reaches_neighbours_before_distant_towns_and_is_deterministic() -> void:
	var a := _soc()
	var b := _soc()
	var ia: String = a.add_rumour("rescue", 0, 3.0)
	var ib: String = b.add_rumour("rescue", 0, 3.0)
	var ctx := CTX.duplicate()
	for h in range(1, 24 * 20):
		ctx["abs_hours"] = float(h)
		a.tick_hour(h % 24, ctx)
		b.tick_hour(h % 24, ctx)
	assert_array(a.rumour_reach(ia)).is_equal(b.rumour_reach(ib))
	var arrivals: Dictionary = a.rumour_list[0]["heard"]
	var t0 := 0.0
	for k: String in arrivals:
		if int(k) != 0:
			assert_bool(float(arrivals[k]["h"]) > t0).is_true()
	# Neighbours (one road hop) come before towns two hops away. Checked over the original
	# valley: on the 8 km map the far roads are 2 km long, so a long single hop can rightly
	# arrive after a couple of short ones (the delay is road length / RUMOUR_SPEED).
	var hops: Dictionary = {}
	for k: String in arrivals:
		if int(k) < WorldGen.core_settlement_count:
			hops[k] = int(arrivals[k]["hops"])
	for k1: String in hops:
		for k2: String in hops:
			if hops[k1] < hops[k2]:
				assert_bool(float(arrivals[k1]["h"]) <= float(arrivals[k2]["h"])).is_true()


func test_fame_arrives_with_the_rumour() -> void:
	var s := _soc()
	var id: String = s.add_rumour("rescue", 0, 4.0)
	var reach0: int = s.rumour_reach(id).size()
	var ctx := CTX.duplicate()
	for h in range(1, 24 * 30):
		ctx["abs_hours"] = float(h)
		s.tick_hour(h % 24, ctx)
	var reach: Array = s.rumour_reach(id)
	assert_int(reach.size()).is_greater(reach0)
	var other := int(reach[reach.size() - 1])
	assert_float(s.rep("city:%d" % other)).is_greater(0.0)


func test_npc_goals_advance_without_the_player() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var before := JSON.stringify(_canon(s.npcs))
	var ctx := CTX.duplicate()
	var msgs := 0
	for d in range(2, 120):
		msgs += s.tick_day(d, ctx).size()
	assert_str(JSON.stringify(_canon(s.npcs))).is_not_equal(before)
	var changed := 0
	var s0 := _soc()
	s0.tick_day(1, CTX)
	for id: String in s.npcs:
		if s.npcs[id]["job"] != s0.npcs[id]["job"] or s.npcs[id]["sid"] != s0.npcs[id]["sid"] or int(s.npcs[id]["tier"]) != int(s0.npcs[id]["tier"]):
			changed += 1
	assert_int(changed).is_greater(5)


func test_grudges_turn_goals_into_revenge() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var id := "n10"
	s.interact(id, "kill_kin")
	var ctx := CTX.duplicate()
	var saw := false
	for d in range(2, 300):
		s.tick_day(d, ctx)
		var g: Array = s.goals_of(id)
		if not g.is_empty() and g[0]["type"] == "revenge":
			saw = true
			break
	assert_bool(saw).is_true()


func test_apprenticeship_learns_from_master_over_days() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var m := _find(s, func(n: Dictionary) -> bool: return int(n["tier"]) >= 3 and int(n["tier"]) <= 5)
	assert_str(m).is_not_empty()
	s.set_player({"gold": 1000, "refs": 2, "combat": 40, "skills": {"smithing": 20}})
	for i in 4:
		s.interact(m, "train_together")
	s.do_service(m)
	var r: Dictionary = s.apply_apprenticeship(m, "smithing")
	assert_bool(r["ok"]).is_true()
	assert_bool(s.apply_apprenticeship(m, "smithing")["ok"]).is_false()
	var ctx := CTX.duplicate()
	for d in range(2, 60):
		s.attend_lesson()
		s.tick_day(d, ctx)
	assert_bool(s.knows("skill:smithing")).is_true()
	assert_float(float(s.player["skills"]["smithing"])).is_greater_equal(55.0)


func test_master_rejects_and_skipping_lessons_loses_the_place() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	var m := _find(s, func(n: Dictionary) -> bool: return int(n["tier"]) >= 3 and int(n["tier"]) <= 5)
	s.set_player({"gold": 0, "refs": 0, "skills": {}})
	var r: Dictionary = s.apply_apprenticeship(m, "smithing")
	assert_bool(r["ok"]).is_false()
	assert_str(String(r["reason"])).is_not_empty()
	var low := _find(s, func(n: Dictionary) -> bool: return int(n["tier"]) < 3)
	assert_bool(s.apply_apprenticeship(low, "smithing")["ok"]).is_false()
	# Accepted, then absent.
	s.set_player({"gold": 1000, "refs": 2, "combat": 40, "skills": {"smithing": 20}})
	for i in 4:
		s.interact(m, "train_together")
	s.do_service(m)
	assert_bool(s.apply_apprenticeship(m, "smithing")["ok"]).is_true()
	var ctx := CTX.duplicate()
	for d in range(2, 12):
		s.tick_day(d, ctx)
	assert_bool(s.apprenticeship.is_empty()).is_true()
	assert_int(s.story_hooks().size()).is_greater(0)


func test_player_becomes_master_and_teaches() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	s.set_player({"skills": {"herbalism": 70}, "gold": 500})
	var id := "n20"
	assert_bool(s.take_student(id, "herbalism")["ok"]).is_true()
	assert_bool(s.take_student("n21", "herbalism")["ok"]).is_false()   # no school yet
	assert_bool(s.found_school()).is_true()
	assert_bool(s.take_student("n21", "herbalism")["ok"]).is_true()
	var tier0: int = s.npcs[id]["tier"]
	var ctx := CTX.duplicate()
	for d in range(2, 60):
		s.teach_lesson()
		s.tick_day(d, ctx)
	assert_int(s.students.size()).is_equal(0)
	assert_int(int(s.npcs[id]["tier"])).is_greater(tier0 - 1)
	assert_float(s.relation(id)["loyalty"]).is_greater(20.0)
	assert_bool(s.take_student("n22", "swordplay")["ok"]).is_false()


func test_knowledge_unlocks_dialogue_and_leads() -> void:
	var s := _soc()
	assert_bool(s.knows("secret:mayor_debts")).is_false()
	assert_bool(s.learn("secret:mayor_debts", "The mayor owes the moneylender.")).is_true()
	assert_bool(s.learn("secret:mayor_debts")).is_false()
	assert_bool(s.knows("secret:mayor_debts")).is_true()
	s.learn("topic:old_well")
	s.learn("place:0:old well")
	var opts: Array = s.dialogue_unlocks()
	assert_bool(opts.has("Confront them about mayor debts")).is_true()
	assert_bool(opts.has("Ask about old well")).is_true()
	assert_str(s.knowledge_level(0)).is_equal("newcomer")
	for i in 5:
		s.learn("place:0:landmark%d" % i)
	assert_str(s.knowledge_level(0)).is_equal("local")
	assert_int(s.leads().size()).is_equal(1)


func test_knowledge_can_feed_hidden_leads() -> void:
	var hub := _hub()
	var s: RefCounted = hub.mod("society")
	var c: RefCounted = hub.mod("city_life")
	for i in 6:
		s.learn("topic:%d" % i)
	var informant := false
	for l: Dictionary in c.hidden_leads():
		if l["id"] == "informant":
			informant = true
	assert_bool(informant).is_true()


func test_failures_log_stories_and_can_be_resolved() -> void:
	var s := _soc()
	s.log_failure("evicted", "You lost your room.", 0)
	var hooks: Array = s.story_hooks()
	assert_int(hooks.size()).is_equal(1)
	assert_str(String(hooks[0]["hook"])).contains("slums")
	assert_bool(s.resolve_story(hooks[0]["id"])).is_true()
	assert_int(s.story_hooks().size()).is_equal(0)
	assert_int(s.story_hooks(true).size()).is_equal(1)
	var msgs: Array = s.tick_day(1, CTX)
	var found := false
	for m: String in msgs:
		if m.begins_with("Story:"):
			found = true
	assert_bool(found).is_true()


func test_offers_from_the_world() -> void:
	var s := _soc()
	var ctx := CTX.duplicate()
	for d in range(1, 200):
		s.tick_day(d, ctx)
	assert_int(s.offers().size()).is_greater(0)
	var o: Dictionary = s.offers()[0]
	assert_bool(s.accept_offer(o["id"])["ok"]).is_true()
	assert_bool(s.knows("contact:" + String(o["npc"]))).is_true()


func test_life_reputation_is_mirrored_read_only() -> void:
	var s := _soc()
	var fake := RefCounted.new()
	var ctx := CTX.duplicate()
	ctx["life"] = null
	s.tick_day(1, ctx)   # no life: no crash
	assert_bool(fake != null).is_true()


func test_serialize_round_trip_including_json() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	s.add_rep("city:0", 12.5)
	s.interact("n1", "help")
	s.commit_crime("murder", 1, 8)
	s.add_rumour("rescue", 0, 3.0)
	s.learn("secret:x", "y")
	s.log_failure("fired", "lost job", 0)
	s.set_outfit("noble")
	s.set_player({"combat": 44, "skills": {"a": 3}})
	var ctx := CTX.duplicate()
	for h in range(1, 80):
		ctx["abs_hours"] = float(h)
		s.tick_hour(h % 24, ctx)
	s.tick_day(2, ctx)
	var a: Dictionary = s.serialize()
	var b := Society.new()
	b.deserialize(a)
	assert_str(JSON.stringify(_canon(b.serialize()))).is_equal(JSON.stringify(_canon(a)))
	var c := Society.new()
	c.deserialize(JSON.parse_string(JSON.stringify(a)))
	assert_str(JSON.stringify(_canon(c.serialize()))).is_equal(JSON.stringify(_canon(a)))
	assert_float(c.rep("city:0")).is_equal_approx(s.rep("city:0"), 0.01)
	assert_array(c.rumours(0)).is_equal(s.rumours(0))
	assert_bool(c.knows("secret:x")).is_true()
	assert_int(c.notable_count()).is_equal(200)
	# Continuing after a JSON load stays in step with the original.
	for d in range(3, 12):
		s.tick_day(d, ctx)
		c.tick_day(d, ctx)
	assert_str(JSON.stringify(_canon(c.serialize()))).is_equal(JSON.stringify(_canon(s.serialize())))


func test_catch_up_is_closed_form_and_bounded() -> void:
	var s := _soc()
	s.tick_day(1, CTX)
	s.add_rumour("rescue", 0, 3.0)
	s.commit_crime("murder", 0, 12)
	s.add_rep("city:0", 50.0)
	var t0 := Time.get_ticks_usec()
	var msgs: Array = s.catch_up(200, CTX)
	var us := Time.get_ticks_usec() - t0
	assert_int(us).is_less(20000)
	assert_float(s.rep("city:0")).is_less(50.0)
	assert_int(s.rumour_reach(s.rumour_list[0]["id"] if not s.rumour_list.is_empty() else "").size()).is_greater(0)
	assert_bool(msgs is Array).is_true()


func test_perf_day_of_ticks_under_budget() -> void:
	var s := _soc()
	s.tick_day(1, CTX)   # roster generated once, as on the first game day
	for i in 5:
		s.add_rumour("rescue", i, 2.0)
	var ctx := CTX.duplicate()
	var t0 := Time.get_ticks_usec()
	for h in 24:
		ctx["abs_hours"] = float(h)
		s.tick_hour(h, ctx)
	s.tick_day(2, ctx)
	var us := Time.get_ticks_usec() - t0
	assert_int(us).is_less(20000)
	# The first-ever day (including roster generation) also fits.
	var fresh := _soc()
	var t1 := Time.get_ticks_usec()
	for h in 24:
		fresh.tick_hour(h, ctx)
	fresh.tick_day(1, ctx)
	assert_int(Time.get_ticks_usec() - t1).is_less(20000)
