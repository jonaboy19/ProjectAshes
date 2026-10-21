extends GdUnitTestSuite
## MW-12/13/14: follower motives, roles, order responses (the Theron scenario), requests, delegation quality, player actions, save, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Brain := preload("res://scripts/actors/follower_brain.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 1000, "player_pos": Vector3.ZERO, "life": null}
## "Attack the neighbour": a wrong war, and Theron's kin live there.
const ATTACK := {"kind": "attack_neighbour", "moral": 0.7, "danger": 0.7, "tie": 0.8}
const CALM := {"kind": "attack_neighbour", "moral": 0.1, "danger": 0.5, "tie": 0.0}


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func _theron(hub: RefCounted, m: Dictionary, extra := {}) -> String:
	var fid: String = hub.mod("followers").hire("knight", "s0", true, "theron")
	var st := {"m": m, "agenda": "", "life": false, "rank": 2}
	st.merge(extra, true)
	hub.mod("will").set_state(fid, st)
	return fid


func test_motives_start_from_traits_and_drift_with_events() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("hunter", "s0", true, "a")
	var m0: Dictionary = w.motives(fid)
	assert_int(m0.size()).is_equal(7)
	w.on_event(fid, "saved_by_player", 1.0)
	assert_float(w.motives(fid)["aff"]).is_greater(float(m0["aff"]))
	w.on_event(fid, "punished_unjust", 2.0)
	assert_float(w.state_of(fid)["g"]).is_greater(0.3)
	assert_int((w.state_of(fid)["mem"] as Array).size()).is_equal(2)
	assert_float(w.memory_bias(fid)).is_less(0.0)


func test_theron_outcome_varies_by_state() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var seen := {}
	var base_m := {"aff": 0.9, "res": 0.85, "fear": 0.1, "ide": 0.4, "gre": 0.2, "pro": 0.3, "hid": 0.0}
	# 1 loyal, no kin at stake: complies
	var a := _theron(hub, base_m)
	seen["loyal"] = w.respond(a, CALM, {"day": 5})["action"]
	assert_str(seen["loyal"]).is_equal("comply")
	# 2 family in the target and a protective man: stays behind or refuses
	var b := _theron(hub, {"aff": 0.8, "res": 0.7, "fear": 0.1, "ide": 0.6, "gre": 0.2, "pro": 0.9, "hid": 0.0})
	seen["family"] = w.respond(b, ATTACK, {"day": 5, "family_risk": 0.8})["action"]
	assert_bool(seen["family"] in ["stay_behind", "refuse_moral"]).is_true()
	# 3 principled, harsh order: refuses on moral grounds
	var c := _theron(hub, {"aff": 0.7, "res": 0.8, "fear": 0.05, "ide": 0.95, "gre": 0.1, "pro": 0.4, "hid": 0.0})
	seen["moral"] = w.respond(c, {"kind": "burn", "moral": 0.95, "danger": 0.4, "tie": 0.0}, {"day": 5})["action"]
	assert_str(seen["moral"]).is_equal("refuse_moral")
	# 4 unpaid, resentful, lord weak: leaves
	var d := _theron(hub, {"aff": 0.2, "res": 0.4, "fear": 0.05, "ide": 0.3, "gre": 0.7, "pro": 0.2, "hid": 0.0}, {"g": 0.7})
	seen["unpaid"] = w.respond(d, CALM, {"day": 5, "owed_days": 12, "lord_strength": 0.2})["action"]
	assert_str(seen["unpaid"]).is_equal("consider_leaving")
	# 5 lord absent, holds the garrison, ambitious, allies: attempts takeover
	var e := _theron(hub, {"aff": 0.2, "res": 0.3, "fear": 0.0, "ide": 0.1, "gre": 0.9, "pro": 0.1, "hid": 0.6}, {"g": 0.6, "agenda": "power", "rank": 3})
	w.set_state(e, {"al": ["f90", "f91", "f92"]})
	seen["coup"] = w.respond(e, CALM, {"day": 5, "garrison": true, "lord_present": false, "lord_strength": 0.3, "allies": 3})["action"]
	assert_str(seen["coup"]).is_equal("attempt_takeover")
	# 6 same man with the lord watching and strong: hides it
	seen["hide"] = w.respond(e, CALM, {"day": 5, "garrison": false, "lord_present": true, "lord_strength": 0.9, "allies": 0})["action"]
	assert_bool(seen["hide"] in ["conceal_resentment", "comply"]).is_true()
	# 7 enemy agent with a contact: leaks
	var f := _theron(hub, {"aff": 0.15, "res": 0.3, "fear": 0.0, "ide": 0.05, "gre": 0.4, "pro": 0.4, "hid": 0.8}, {"g": 0.5, "agenda": "enemy_agent"})
	seen["leak"] = w.respond(f, ATTACK, {"day": 5, "enemy_contact": 1.0, "lord_strength": 0.3})["action"]
	assert_str(seen["leak"]).is_equal("leak_to_enemy")
	# 8 grumbling with allies in a weak lord's camp: organises resistance
	var g := _theron(hub, {"aff": 0.4, "res": 0.6, "fear": 0.0, "ide": 0.7, "gre": 0.3, "pro": 0.5, "hid": 0.0}, {"g": 0.6, "rank": 3})
	seen["resist"] = w.respond(g, ATTACK, {"day": 5, "allies": 3, "lord_strength": 0.1})["action"]
	assert_bool(seen["resist"] in ["organise_resistance", "refuse_moral"]).is_true()
	var kinds := {}
	for k: String in seen:
		kinds[seen[k]] = true
	assert_int(kinds.size()).is_greater_equal(6)


func test_response_is_deterministic() -> void:
	var h1 := _hub()
	var h2 := _hub()
	var m := {"aff": 0.5, "res": 0.5, "fear": 0.2, "ide": 0.5, "gre": 0.4, "pro": 0.5, "hid": 0.0}
	var a := _theron(h1, m, {"g": 0.4})
	var b := _theron(h2, m, {"g": 0.4})
	for day in 20:
		var ra: Dictionary = h1.mod("will").respond(a, ATTACK, {"day": day}, false)
		var rb: Dictionary = h2.mod("will").respond(b, ATTACK, {"day": day}, false)
		assert_str(ra["action"]).is_equal(rb["action"])


func test_betrayal_possible_never_inevitable_and_lifelong_loyal_holds() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var sit := {"garrison": false, "lord_present": true, "lord_strength": 0.5, "enemy_contact": 0.0, "allies": 0, "owed_days": 0}
	var shaky := {"aff": 0.5, "res": 0.5, "fear": 0.05, "ide": 0.4, "gre": 0.4, "pro": 0.4, "hid": 0.0}
	var man := _theron(hub, shaky, {"g": 0.62, "rank": 3})
	var loyal := _theron(hub, shaky, {"g": 0.62, "rank": 3, "life": true})
	var betray := 0
	var betray_loyal := 0
	var bad := ["leak_to_enemy", "organise_resistance", "attempt_takeover", "consider_leaving"]
	for day in 200:
		sit["day"] = day
		if w.respond(man, ATTACK, sit, false)["action"] in bad:
			betray += 1
		if w.respond(loyal, ATTACK, sit, false)["action"] in bad:
			betray_loyal += 1
	assert_int(betray).is_greater(0)
	assert_int(betray).is_less(200)
	assert_int(betray_loyal).is_equal(0)


func test_lifelong_loyalty_earned_then_lost_by_injustice() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("knight", "s0", true, "old")
	var f: Dictionary = hub.mod("followers").get_follower(fid)
	f["traits"] = ["loyal", "honorable", "brave"]
	f["loyalty"] = 95.0
	f["joined_day"] = -200
	w.set_state(fid, {"m": {"aff": 0.9, "res": 0.8}, "agenda": ""})
	for d in 5:
		w.tick_day(d + 1, CTX)
	assert_bool(w.state_of(fid)["life"]).is_true()
	for i in 3:
		w.on_event(fid, "punished_unjust", 1.0)
	assert_bool(w.state_of(fid)["life"]).is_false()


func test_roles_check_skill_authority_motivation() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var knight: String = hub.mod("followers").hire("knight", "s0", true, "k")
	var healer: String = hub.mod("followers").hire("healer", "s0", true, "h")
	w.set_state(knight, {"m": {"res": 0.8, "ide": 0.7, "aff": 0.6}})
	w.set_state(healer, {"m": {"res": 0.8, "ide": 0.7, "aff": 0.6, "pro": 0.6}})
	assert_bool(w.role_fit(knight, "military")["ok"]).is_true()
	var bad: Dictionary = w.role_fit(healer, "military")
	assert_bool(bad["ok"]).is_false()
	assert_str(bad["why"]).is_equal("lacks the skill")
	assert_bool(w.role_fit(healer, "social")["ok"]).is_true()
	w.set_state(knight, {"m": {"res": 0.0, "ide": 0.0}})
	assert_bool(w.assign_role(knight, "military")["ok"]).is_false()


func test_requests_come_from_needs_and_answers_change_motives() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("mercenary", "s0", true, "poor")
	hub.mod("followers").get_follower(fid)["needs"]["pay"] = 0.2
	hub.mod("followers").get_follower(fid)["owed"] = 0
	var msgs: Array = w.tick_day(30, CTX)
	assert_str(w.pending_request(fid)).is_not_equal("")
	assert_int(msgs.size()).is_greater(0)
	var aff0: float = w.motives(fid)["aff"]
	w.answer(fid, "deny")
	assert_float(w.motives(fid)["aff"]).is_less(aff0)
	assert_str(w.pending_request(fid)).is_equal("")
	assert_str(w.wanted_request(fid, 31)).is_equal("")      # cooldown


func test_delegation_quality_reaches_the_settlement_hook() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var able: String = hub.mod("followers").hire("builder", "s0", true, "able")
	var crook: String = hub.mod("followers").hire("builder", "s0", true, "crook")
	var fa: Dictionary = hub.mod("followers").get_follower(able)
	var fc: Dictionary = hub.mod("followers").get_follower(crook)
	fa["skills"] = {"command": 0.9, "speech": 0.8, "building": 0.8}
	fc["skills"] = {"command": 0.9, "speech": 0.8, "building": 0.8}
	fa["traits"] = ["honorable", "loyal", "brave"]
	fc["traits"] = ["greedy", "ruthless", "curious"]
	w.set_state(able, {"role": "settlement", "m": {"pro": 0.8, "ide": 0.9, "aff": 0.8, "res": 0.8, "gre": 0.1}})
	w.set_state(crook, {"role": "settlement", "agenda": "profit", "m": {"pro": 0.8, "ide": 0.2, "aff": 0.3, "res": 0.8, "gre": 0.9}})
	assert_bool(w.appoint_governor(1, able)["ok"]).is_true()
	assert_bool(w.appoint_governor(2, crook)["ok"]).is_true()
	var m1: Dictionary = w.settlement_modifier(1)
	var m2: Dictionary = w.settlement_modifier(2)
	assert_float(m1["leak"]).is_less(m2["leak"])
	assert_float(m2["leak"]).is_greater(0.2)
	assert_float(w.settlement_modifier(99)["output"]).is_equal(1.0)
	# the skim accrues, an audit finds it, oversight then cuts it
	for d in 10:
		w.tick_day(d + 1, CTX)
	assert_float(w.skimmed(crook)).is_greater(1.0)
	var res: Dictionary = w.audit(crook)
	assert_float(res["found"]).is_greater(1.0)
	assert_float(w.skimmed(crook)).is_equal(0.0)
	assert_float(w.settlement_modifier(2)["leak"]).is_less(m2["leak"])


func test_player_actions() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("knight", "s0", true, "p")
	var buddy: String = hub.mod("followers").hire("scout", "s0", true, "q")
	w.add_ally(fid, buddy)
	w.set_state(fid, {"agenda": "power", "m": {"hid": 0.1, "res": 0.8, "ide": 0.6, "aff": 0.7}})
	var inv: Dictionary = w.investigate(fid, 0.95, 3)
	assert_bool(inv["found"]).is_true()
	assert_str(inv["agenda"]).is_equal("power")
	var rw: Dictionary = w.reward(fid, 100)
	assert_int(rw["cost"]).is_equal(100)
	var pr: Dictionary = w.promote(fid, "military")
	assert_bool(pr["ok"]).is_true()
	assert_int(w.rank_of(fid)).is_equal(1)
	w.on_event(fid, "punished_unjust", 1.5)
	var g0: float = w.state_of(fid)["g"]
	w.forgive(fid)
	assert_float(w.state_of(fid)["g"]).is_less(g0)
	var b0: float = w.motives(buddy)["aff"]
	var res: Dictionary = w.dismiss(fid, 0)
	assert_bool(res.has("ok")).is_true()
	assert_float(b0).is_greater(-1.0)


func test_imprison_respects_regional_law() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var mild: String = hub.mod("followers").hire("knight", "s0", true, "m")
	var harsh: String = hub.mod("followers").hire("knight", "s0", true, "n")
	var friend: String = hub.mod("followers").hire("scout", "s0", true, "o")
	w.add_ally(harsh, friend)
	var no: Dictionary = w.imprison(mild, "veylwood")
	assert_bool(no["ok"]).is_false()
	assert_bool(no["lawful"]).is_false()
	assert_bool(w.is_held(mild)).is_false()
	var yes: Dictionary = w.imprison(harsh, "solkar_dominion")
	assert_bool(yes["ok"]).is_true()
	assert_bool(yes["lawful"]).is_false()
	assert_bool(w.is_held(harsh)).is_true()
	assert_float(w.state_of(harsh)["g"]).is_greater(0.2)
	assert_int((w.state_of(friend)["mem"] as Array).size()).is_greater(0)
	# a proven crime goes through the court of that kingdom
	var tried: Dictionary = w.imprison(mild, "solkar_dominion", "robbery", 0, 1.0, 10)
	assert_bool(tried.has("case")).is_true()


func test_brain_holds_followers_who_asked_to_stay() -> void:
	assert_int(Brain.decide("follow", {"dist": 3.0, "will": "stay_behind"})).is_equal(Brain.Mode.WAIT)
	assert_int(Brain.decide("follow", {"dist": 3.0, "will": "comply"})).is_equal(Brain.Mode.FOLLOW)


func test_chunked_day_save_roundtrip_and_cost() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var ids: Array = []
	for i in 40:
		ids.append(hub.mod("followers").hire(["knight", "hunter", "healer", "builder"][i % 4], "s0", true, "bulk%d" % i))
	var chunks: Array = w.tick_day_chunks(8, CTX)
	assert_int(chunks.size()).is_equal(3)
	w.on_event(ids[0], "punished_unjust", 1.0)
	w.set_state(ids[1], {"plot": "resist", "held": 12})
	var t0 := Time.get_ticks_usec()
	for d in 30:
		w.tick_day(d + 9, CTX)
	var per_day := float(Time.get_ticks_usec() - t0) / 30.0
	assert_float(per_day).is_less(20000.0)
	var blob: String = JSON.stringify(w.serialize())
	var back: RefCounted = Hub.new().mod("will")
	back.deserialize(JSON.parse_string(blob))
	assert_str(JSON.stringify(back.serialize())).is_equal(blob)
	assert_float(back.state_of(ids[0])["g"]).is_equal_approx(w.state_of(ids[0])["g"], 0.011)
	assert_int(blob.length()).is_less(40 * 220)


func test_catch_up_is_closed_form() -> void:
	var hub := _hub()
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("knight", "s0", true, "c")
	w.ensure(fid)
	var t0 := Time.get_ticks_usec()
	w.catch_up(400, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(50000)
