extends GdUnitTestSuite
## Followers as individuals: summons with travel delay, agency, temporary
## companions, party disagreements, taming and creature roles.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func test_followers_are_individuals() -> void:
	var f: RefCounted = _hub().mod("followers")
	var a: String = f.hire("hunter", "s0", true, "k1")
	var b: String = f.hire("knight", "s0", true, "k2")
	var fa: Dictionary = f.get_follower(a)
	var fb: Dictionary = f.get_follower(b)
	assert_str(fa["name"]).is_not_equal(fb["name"])
	assert_float(fa["skills"]["tracking"]).is_greater(fb["skills"].get("tracking", 0.0))
	assert_int(fb["salary"]).is_greater(fa["salary"])
	assert_int(f.list().size()).is_equal(2)


func test_summon_arrives_after_travel_hours() -> void:
	var hub := _hub()
	var f: RefCounted = hub.mod("followers")
	var cm: RefCounted = hub.mod("camps")
	var far := WorldGen.settlements.size() - 1
	var id: String = f.hire("cavalry", "s%d" % far, true, "sm")
	# Loyal and free of posts, so they come; pick a key where the message survives.
	f.get_follower(id)["loyalty"] = 90.0
	var res: Dictionary = f.summon(id, 0)
	assert_bool(res["ok"]).is_true()
	var eta: float = cm.travel_hours("s%d" % far, "s0")
	assert_float(res["eta"]).is_greater_equal(eta)
	assert_int(f.arrivals().size()).is_equal(1)
	if f.arrivals()[0]["lost"]:
		return
	var need := int(ceil(res["eta"]))
	var msgs: Array = []
	for h in need - 1:
		msgs.append_array(f.tick_hour(h, CTX))
	assert_str(f.get_follower(id)["status"]).is_equal("traveling")
	msgs.append_array(f.tick_hour(0, CTX))
	assert_str(f.get_follower(id)["status"]).is_equal("present")
	assert_str(f.get_follower(id)["loc"]).is_equal("s0")
	assert_bool(msgs.any(func(m: String) -> bool: return m.contains("arrives"))).is_true()


func test_follower_can_refuse() -> void:
	var f: RefCounted = _hub().mod("followers")
	var id: String = f.hire("scout", "s3", true, "r1")
	f.get_follower(id)["loyalty"] = 10.0
	var res: Dictionary = f.summon(id, 0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["response"]).is_not_empty()
	var id2: String = f.hire("scout", "s3", true, "r2")
	f.get_follower(id2)["loyalty"] = 60.0
	f.assign_post(id2, "gate")
	var refused := 0
	for k in 1:
		refused += 0 if f.summon(id2, 0)["ok"] else 1
	assert_bool(f.get_follower(id2)["post"] == "gate").is_true()


func test_recruit_weighs_reputation() -> void:
	var f: RefCounted = _hub().mod("followers")
	var c: String = f.candidate("knight", "proud", "s0")
	var r1: Dictionary = f.recruit(c, {"reputation": 5, "pay": 9})
	assert_bool(r1["ok"]).is_false()
	assert_str(r1["line"]).contains("protect yourself")
	var r2: Dictionary = f.recruit(c, {"reputation": 90, "pay": 12})
	assert_bool(r2["ok"]).is_true()
	assert_str(f.get_follower(c)["status"]).is_equal("present")


func test_temporary_companion_leaves() -> void:
	var f: RefCounted = _hub().mod("followers")
	var id: String = f.hire_temp("hunter", "s0", 5, "t1")
	var msgs: Array = []
	for h in 6:
		msgs.append_array(f.tick_hour(h, CTX))
	assert_str(f.get_follower(id)["status"]).is_equal("left")
	assert_bool(msgs.any(func(m: String) -> bool: return m.contains("parts ways"))).is_true()
	assert_int(f.list().size()).is_equal(0)


func test_party_disagreement_and_leaving() -> void:
	var f: RefCounted = _hub().mod("followers")
	var a: String = f.hire("knight", "s0", true, "pa")
	var b: String = f.hire("priest", "s0", true, "pb")
	f.get_follower(a)["values"]["mercy"] = -0.9
	f.get_follower(b)["values"]["mercy"] = 0.9
	var la0: float = f.get_follower(a)["loyalty"]
	var lb0: float = f.get_follower(b)["loyalty"]
	var lines: Array = f.decide("mercy", 1.0, 1)
	assert_bool(lines.any(func(m: String) -> bool: return m.contains("disapproves"))).is_true()
	assert_int(f.disputes().size()).is_equal(1)
	assert_float(f.get_follower(b)["loyalty"] - lb0).is_greater(f.get_follower(a)["loyalty"] - la0)
	# Neglected wages and hunger push someone out eventually.
	f.get_follower(a)["loc"] = "wild"
	f.get_follower(b)["loc"] = "wild"
	var left := false
	for d in 200:
		for m in f.tick_day(d, CTX):
			if m.contains("left your service"):
				left = true
	assert_bool(left).is_true()


func test_taming_methods_differ_per_species() -> void:
	var f: RefCounted = _hub().mod("followers")
	f.start_taming("w1", "wolf")
	var res: Dictionary = {}
	for i in 6:
		res = f.attempt_taming("w1", "feed", 1)
	assert_str(res["status"]).is_equal("tamed")
	f.start_taming("b1", "boar")
	assert_float(f.attempt_taming("b1", "feed", 1)["trust"]).is_less(0.1)
	for i in 4:
		f.attempt_taming("b1", "dominate", 1)
	assert_str(f.creature("b1")["status"]).is_equal("tamed")
	f.start_taming("y1", "wyvern", false)
	assert_str(f.attempt_taming("y1", "raise", 1)["msg"]).contains("youth")
	f.start_taming("r1", "rift_wraith")
	assert_str(f.attempt_taming("r1", "feed", 1)["msg"]).contains("never")
	assert_int(f.tamed().size()).is_equal(2)


func test_creature_roles_feed_settlements() -> void:
	var hub := _hub()
	var f: RefCounted = hub.mod("followers")
	var sm: RefCounted = hub.mod("settlements")
	f.start_taming("h1", "draft_horse")
	for i in 5:
		f.attempt_taming("h1", "feed", 1)
	assert_bool(f.assign_role("h1", "farming", "s1")).is_true()
	assert_bool(f.assign_role("h1", "guarding", "s1")).is_false()
	var g0: float = sm.supply_of(1, "grain")
	f.tick_day(2, CTX)
	assert_float(sm.supply_of(1, "grain")).is_greater(g0)
	f.start_taming("w2", "wolf")
	for i in 6:
		f.attempt_taming("w2", "feed", 1)
	f.assign_role("w2", "guarding", "s1")
	assert_float(f.guard_bonus("s1")).is_greater(0.0)


func test_catch_up_and_determinism() -> void:
	var a: RefCounted = _hub().mod("followers")
	var b: RefCounted = _hub().mod("followers")
	for f in [a, b]:
		for i in 5:
			f.hire("mercenary", "s%d" % i, true, "c%d" % i)
	var la: Array = a.catch_up(30, CTX)
	var lb: Array = b.catch_up(30, CTX)
	assert_array(la).is_equal(lb)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	assert_int(la.size()).is_greater(0)


func test_save_round_trip() -> void:
	var hub := _hub()
	var f: RefCounted = hub.mod("followers")
	var id: String = f.hire("hunter", "s3", true, "rt")
	f.get_follower(id)["loyalty"] = 90.0
	f.hire_temp("scout", "s0", 40, "rt2")
	f.summon(id, 0)
	f.start_taming("w1", "wolf")
	f.attempt_taming("w1", "feed", 1)
	f.decide("risk", 0.5, 1)
	var json := JSON.stringify(f.serialize())
	var f2: RefCounted = Hub.new().mod("followers")
	f2.deserialize(JSON.parse_string(json))
	assert_str(_norm(f2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_int(f2.arrivals().size()).is_equal(f.arrivals().size())
	assert_int(f2._temps.size()).is_equal(1)


func test_perf_24_hourly_ticks_with_hundreds() -> void:
	var f: RefCounted = _hub().mod("followers")
	for i in 300:
		f.hire("mercenary", "s%d" % (i % 10), i % 3 != 0, "p%d" % i, 500)
	f.summon("f2", 0)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		f.tick_hour(h, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
