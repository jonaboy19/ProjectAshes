extends GdUnitTestSuite
## Recruitment core (Living World §2): evaluation, negotiation, notice applicants, wages and desertion, chain
## separation on resign, manager skimming and audit, save round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const RUI := preload("res://scripts/ui/recruitment_ui.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 1000, "player_pos": Vector3.ZERO, "life": null}


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


## A living row of settlement 0 that is not already special; scans for the requested kind of person.
func _row(want_trait := "", skip := 0) -> int:
	var rg: Vector2i = WorldSim.ranges[0]
	var seen := 0
	var rc: RefCounted = Rec.new()     # profile() needs no hub
	for i in range(rg.x, rg.y):
		if WorldSim.health[i] == 0:
			continue
		var p: Dictionary = rc.profile(i)
		if want_trait == "" or want_trait in p["traits"]:
			if seen >= skip:
				return i
			seen += 1
	return rg.x


func _find(has: String, lacks: Array) -> int:
	var rg: Vector2i = WorldSim.ranges[0]
	var rc: RefCounted = Rec.new()
	for i in range(rg.x, rg.y):
		var t: Array = rc.profile(i)["traits"]
		if WorldSim.health[i] != 0 and has in t:
			var ok := true
			for l: String in lacks:
				ok = ok and not (l in t)
			if ok:
				return i
	return rg.x


func _day(hub: RefCounted, day: int, gold := 1000) -> Array:
	var ctx := CTX.duplicate()
	ctx["gold"] = gold
	var out: Array = hub.mod("followers").tick_day(day, ctx)
	out.append_array(hub.mod("recruitment").tick_day(day, ctx))
	return out


func _hire(hub: RefCounted, row: int, wage := 40, chain := "personal", org := "", duty := "labor") -> String:
	var rc: RefCounted = hub.mod("recruitment")
	var res: Dictionary = rc.engage(row, Rec.make_terms(wage, duty, 0, true), chain, org, {"trust": 40.0, "reputation": 60.0})
	assert_bool(res["ok"]).is_true()
	return res["fid"]


func test_evaluation_uses_pay_danger_trust() -> void:
	var rc: RefCounted = _hub().mod("recruitment")
	var row := _row()
	var ask: int = rc.profile(row)["ask"]
	var low: Dictionary = rc.evaluate(row, Rec.make_terms(1, "campaign"), {"trust": -50.0})
	var fair: Dictionary = rc.evaluate(row, Rec.make_terms(ask + 4, "labor", 0, true), {"trust": 30.0, "reputation": 60.0})
	assert_float(fair["score"]).is_greater(low["score"])
	assert_str(low["verdict"]).is_not_equal("accept")
	assert_str(fair["verdict"]).is_equal("accept")
	assert_int(low["reasons"].size()).is_greater(1)
	# More danger lowers the same offer; trust raises it.
	var safe: Dictionary = rc.evaluate(row, Rec.make_terms(ask, "labor"), {})
	var risky: Dictionary = rc.evaluate(row, Rec.make_terms(ask, "campaign"), {})
	assert_float(risky["score"]).is_less(safe["score"])
	var trusted: Dictionary = rc.evaluate(row, Rec.make_terms(ask, "labor"), {"trust": 60.0})
	assert_float(trusted["score"]).is_greater(safe["score"])
	# Deterministic and same-profile.
	assert_float(rc.evaluate(row, Rec.make_terms(ask, "labor"), {})["score"]).is_equal(safe["score"])


func test_negotiation_counter_then_accept() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	# Find someone who counters a slightly low offer.
	var found := -1
	var rg: Vector2i = WorldSim.ranges[0]
	for i in range(rg.x, rg.y):
		var ask: int = rc.profile(i)["ask"]
		var ev: Dictionary = rc.evaluate(i, Rec.make_terms(maxi(1, ask - 1), "labor"), {"reputation": 40.0})
		if ev["verdict"] == "counter":
			found = i
			break
	assert_int(found).is_greater_equal(0)
	var terms := Rec.make_terms(1, "labor")
	var ev1: Dictionary = rc.evaluate(found, Rec.make_terms(int(rc.profile(found)["ask"]) - 1, "labor"), {"reputation": 40.0})
	assert_str(ev1["line"]).contains("gold a day")
	assert_int(ev1["counter"]["w"]).is_greater(int(rc.profile(found)["ask"]) - 1)
	var reject: Dictionary = rc.evaluate(found, Rec.make_terms(1, "campaign"), {"trust": -80.0})
	assert_str(reject["verdict"]).is_equal("reject")
	assert_str(reject["line"]).is_not_empty()
	# Signing needs an acceptable offer; counter terms are accepted.
	assert_bool(rc.engage(found, Rec.make_terms(1, "campaign"), "personal")["ok"]).is_false()
	var res: Dictionary = rc.engage(found, ev1["counter"], "personal", "", {"reputation": 40.0})
	assert_bool(res["ok"]).is_true()
	var c: Dictionary = rc.contract(res["cid"])
	assert_str(c["st"]).is_equal("active")
	assert_bool(String(c["id"]).begins_with("k")).is_true()
	assert_bool(rc.engage(found, ev1["counter"])["ok"]).is_false()    # already yours
	assert_bool(terms.has("w")).is_true()


func test_talk_menu_offer_work_option() -> void:
	var opts: Array = []
	var row := _row()
	RUI.add_options(opts, {"person": row, "name": "X", "id": "p"}, null, Callable())
	# Life's hub is the live one; the option appears for an unrecruited villager.
	assert_int(opts.size()).is_equal(1)
	assert_str(opts[0][0]).is_equal("Offer work")


func test_notice_generates_real_applicants_over_days() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var n: Dictionary = rc.post_notice(0, "inn", Rec.make_terms(14, "labor", 0, true))
	assert_bool(n["ok"]).is_true()
	assert_int(rc.applicants(n["nid"]).size()).is_equal(0)
	for d in range(1, 11):
		_day(hub, d)
	var apps: Array = rc.applicants(n["nid"])
	assert_int(apps.size()).is_greater(0)
	var rg: Vector2i = WorldSim.ranges[0]
	for a: Dictionary in apps:
		assert_bool(int(a["row"]) >= rg.x and int(a["row"]) < rg.y).is_true()     # real people of that settlement
		assert_str(a["name"]).is_equal(WorldSim.person_name(int(a["row"])))
	var first: Dictionary = apps[0]
	var hired: Dictionary = rc.hire_applicant(n["nid"], int(first["row"]), Rec.make_terms(60, "labor", 0, true), {"trust": 30.0, "reputation": 60.0})
	assert_bool(hired["ok"]).is_true()
	assert_bool(rc.is_recruited(int(first["row"]))).is_true()
	assert_int(rc.take_pending_gold()).is_less(0)     # the notice fee left through the ledger


func test_wage_paid_then_unpaid_deserts() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fol: RefCounted = hub.mod("followers")
	var fid := _hire(hub, _row(), 10)
	_day(hub, 1, 500)
	assert_int(rc.take_pending_gold()).is_equal(-10)
	assert_int(fol.get_follower(fid)["owed"]).is_equal(0)
	var line := ""
	for d in range(2, 8):
		for l: String in _day(hub, d, 0):          # empty purse
			if l.contains("deserted"):
				line = l
	assert_str(line).contains("deserted")
	assert_str(fol.get_follower(fid)["status"]).is_equal("left")
	assert_str(rc.contract_of(fid)["st"]).is_equal("broken")
	assert_bool(rc.is_recruited(int(fol.get_follower(fid)["person"]))).is_false()


func test_morale_raise_expiry_and_orders() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fol: RefCounted = hub.mod("followers")
	var row := _row("brave")
	var res: Dictionary = rc.engage(row, Rec.make_terms(60, "guard", 0, true), "personal", "", {"trust": 60.0, "reputation": 60.0})
	assert_bool(res["ok"]).is_true()
	var fid: String = res["fid"]
	for d in range(1, 4):
		_day(hub, d)
	assert_float(rc.get_entry(fid)["m"]).is_greater(0.4)
	# Skills outgrow the pay -> a raise demand; granting it raises morale and the wage.
	fol.get_follower(fid)["salary"] = 1
	rc.contract_of(fid)["t"]["w"] = 1
	for s in fol.get_follower(fid)["skills"]:
		fol.get_follower(fid)["skills"][s] = 0.9
	var said := PackedStringArray()
	for d in range(7, 9):
		said.append_array(_day(hub, d))
	assert_bool("\n".join(said).contains("demands a raise")).is_true()
	assert_bool(rc.grant_raise(fid)).is_true()
	assert_int(rc.contract_of(fid)["t"]["w"]).is_greater(1)
	# Orders: illegal is refused by an honourable/unbent follower, plainly worded.
	var ref: Dictionary = rc.give_order(fid, "illegal")
	if not ref["obeys"]:
		assert_str(ref["line"]).contains("law")
	var sui: Dictionary = rc.give_order(fid, "suicidal")
	assert_bool(sui["obeys"] or sui["line"].contains("death")).is_true()
	assert_bool(rc.give_order(fid, "normal")["obeys"]).is_true()
	# Contract end: a renewal is offered, then they leave if not renewed.
	rc.contract_of(fid)["e"] = 12
	var msgs := PackedStringArray()
	for d in range(9, 14):
		msgs.append_array(_day(hub, d))
	assert_bool("\n".join(msgs).contains("contract ends in")).is_true()
	assert_bool("\n".join(msgs).contains("the contract has ended")).is_true()
	assert_str(rc.contract_of(fid)["st"]).is_equal("expired")


func test_unwise_orders_and_trust_vs_loyalty() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fid := _hire(hub, _row("honorable"), 40, "org", "guard")
	var e: Dictionary = rc.get_entry(fid)
	e["tr"] = 10.0          # distrusts you ...
	e["ol"] = 95.0          # ... but is devoted to the organization
	assert_bool(rc.give_order(fid, "illegal")["obeys"]).is_false()
	assert_bool(rc.give_order(fid, "suicidal")["obeys"]).is_true()   # org loyalty carries it; trust does not
	e["ol"] = 20.0
	assert_bool(rc.give_order(fid, "suicidal")["obeys"]).is_false()


func test_chains_separate_on_resign() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var a := _hire(hub, _row("", 0), 30, "personal")
	var b := _hire(hub, _row("", 1), 30, "org", "guard")
	var c := _hire(hub, _row("", 2), 30, "property")
	var gid: String = rc.create_group("property", "farm1", "Farm")
	rc.assign_to_group(c, gid)
	assert_int(rc.members("personal").size()).is_equal(1)
	assert_int(rc.members("org", "guard").size()).is_equal(1)
	assert_int(rc.members("property").size()).is_equal(1)
	var r: Dictionary = rc.resign("guard")
	assert_int(r["lost_org"]).is_equal(1)
	assert_int(r["kept_personal"]).is_equal(1)
	assert_bool(rc._active(a)).is_true()
	assert_bool(rc._active(b)).is_false()
	assert_bool(rc._active(c)).is_true()
	# Org members are paid by the org, personal by the purse, property by its budget.
	_day(hub, 1, 100)
	var fol: RefCounted = hub.mod("followers")
	assert_int(fol.get_follower(a)["owed"]).is_equal(0)       # the purse paid the personal follower
	assert_int(fol.get_follower(b)["owed"]).is_equal(0)       # (b already left)
	assert_int(rc.take_pending_gold()).is_between(-30, -26)   # only one wage left the purse (output of the farm offsets a little)
	assert_int(hub.mod("followers").get_follower(c)["owed"]).is_equal(30)    # no budget, still owed


func test_manager_skims_and_audit_reveals() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var gid: String = rc.create_group("property", "mill", "Mill", 8.0)
	var crook := _hire(hub, _find("greedy", ["honorable", "loyal"]), 20, "property")
	var honest := _hire(hub, _find("honorable", ["greedy", "ruthless"]), 20, "property")
	var w1 := _hire(hub, _row("", 5), 10, "property")
	for f in [w1, honest]:
		rc.assign_to_group(f, gid)
	assert_float(rc.honesty(crook)).is_less(rc.honesty(honest))
	rc.fund(gid, 2000)
	assert_bool(rc.appoint_manager(crook, gid, "steward", 20.0)["ok"]).is_true()
	for d in range(1, 11):
		_day(hub, d, 0)
	var skimmed: float = rc.group(gid)["sk"]
	assert_float(skimmed).is_greater(5.0)
	var a: Dictionary = rc.audit(gid)
	assert_int(a["found"]).is_greater(0)
	assert_str(a["line"]).contains("skimming")
	assert_float(rc.group(gid)["sk"]).is_equal(0.0)
	# Oversight shrinks later skimming; an honest manager skims nothing.
	for d in range(11, 14):
		_day(hub, d, 0)
	assert_float(rc.group(gid)["sk"]).is_less(skimmed)
	rc.dismiss_manager(gid)
	assert_bool(rc.appoint_manager(honest, gid, "steward", 20.0)["ok"]).is_true()
	rc.audit(gid)
	for d in range(14, 24):
		_day(hub, d, 0)
	assert_float(rc.group(gid)["sk"]).is_less(0.5)


func test_incompetent_manager_loses_output() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fol: RefCounted = hub.mod("followers")
	var gid: String = rc.create_group("property", "farm", "Farm", 8.0)
	var m1 := _hire(hub, _find("honorable", ["greedy"]), 40, "property")
	var w := _hire(hub, _row("", 7), 40, "property")
	rc.assign_to_group(w, gid)
	rc.fund(gid, 500)
	for s in fol.get_follower(m1)["skills"]:
		fol.get_follower(m1)["skills"][s] = 0.9
	rc.appoint_manager(m1, gid, "steward", 10.0)
	rc._group_day(gid, 1.0)
	var good: float = rc.group(gid)["out"]
	for s in fol.get_follower(m1)["skills"]:
		fol.get_follower(m1)["skills"][s] = 0.05
	rc._group_day(gid, 1.0)
	assert_float(rc.group(gid)["out"]).is_less(good)


func _mods_size(hub: RefCounted) -> int:
	return JSON.stringify(hub.mod("followers").serialize()).length() + JSON.stringify(hub.mod("recruitment").serialize()).length()


func test_save_round_trip_and_size() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var rg: Vector2i = WorldSim.ranges[0]
	var gid: String = rc.create_group("property", "p", "P")
	var before := _mods_size(hub)
	var made := 0
	for i in range(rg.x, rg.y):
		if made >= 50:
			break
		if rc.is_recruited(i):
			continue
		var res: Dictionary = rc.engage(i, Rec.make_terms(60, "labor", 30, true), "personal", "", {"trust": 40.0, "reputation": 70.0})
		if res["ok"]:
			made += 1
			if made % 5 == 0:
				rc.assign_to_group(res["fid"], gid)
	assert_int(made).is_equal(50)
	rc.post_notice(0, "market", Rec.make_terms(9, "guard"))
	for d in range(1, 4):
		_day(hub, d, 100000)
	assert_int(rc.members().size()).is_greater(40)
	var grown := _mods_size(hub) - before
	print("SIZES growth for 50 followers: ", grown, " bytes (recruitment ", JSON.stringify(rc.serialize()).length(), ")")
	assert_int(grown).is_less(30 * 1024)
	var data: Dictionary = JSON.parse_string(JSON.stringify(hub.serialize()))
	var hub2 := Hub.new()
	hub2.deserialize(data)
	var rc2: RefCounted = hub2.mod("recruitment")
	var s1 := JSON.stringify(JSON.parse_string(JSON.stringify(rc2.serialize())))
	var s2 := JSON.stringify(JSON.parse_string(JSON.stringify(rc.serialize())))
	assert_bool(s1 == s2).is_true()
	assert_int(rc2.members("personal").size()).is_equal(rc.members("personal").size())
	assert_bool(rc2.is_recruited(rg.x)).is_equal(rc.is_recruited(rg.x))
	var some: String = rc.members()[0]
	assert_str(rc2.contract_of(some)["id"]).is_equal(rc.contract_of(some)["id"])
	assert_str(rc2.contract_of(some)["chain"]).is_equal("personal")
	var f1: Dictionary = hub.mod("followers").get_follower(some)
	var f2: Dictionary = hub2.mod("followers").get_follower(some)
	assert_str(f2["name"]).is_equal(f1["name"])
	assert_float(f2["loyalty"]).is_equal_approx(f1["loyalty"], 0.001)
	assert_int(int(f2["person"])).is_equal(int(f1["person"]))
	assert_float(f2["values"]["honor"]).is_equal(f1["values"]["honor"])     # derived axes are rebuilt from the traits
	# Continues identically after load.
	var o1 := _day(hub, 4, 100000)
	var o2 := _day(hub2, 4, 100000)
	assert_str("\n".join(PackedStringArray(o1))).is_equal("\n".join(PackedStringArray(o2)))


func test_day_chunks_are_cheap_with_fifty_followers() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var rg: Vector2i = WorldSim.ranges[0]
	var made := 0
	for i in range(rg.x, rg.y):
		if made >= 50:
			break
		if rc.engage(i, Rec.make_terms(60, "guard", 30, true), "personal", "", {"trust": 40.0, "reputation": 70.0})["ok"]:
			made += 1
	rc.post_notice(0, "inn", Rec.make_terms(9, "labor"))
	hub.mod("followers").tick_day(1, CTX)
	var worst := 0
	for pass_i in 3:        # the first pass pays the one-off profile cache; judge the steady state
		worst = 0
		for chunk: Callable in rc.tick_day_chunks(1 + pass_i, CTX):
			var t0 := Time.get_ticks_usec()
			chunk.call()
			var dt := Time.get_ticks_usec() - t0
			worst = maxi(worst, dt)
		print("recruitment pass ", pass_i, " worst chunk usec: ", worst)
	print("recruitment worst chunk usec: ", worst)
	assert_int(worst).is_less(3000)      # loose: the budget is 600 us on device, CI is slow
