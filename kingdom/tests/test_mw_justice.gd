extends GdUnitTestSuite
## MW-22/24/25 (docs/design/LIVING_WORLD_MASTER_PLAN.md section H): evidence, investigations, false accusation and testimony, trials by local law and
## culture (church vs secular), corruption, appeals; obligations (promises, oaths, favours, debts); social influence (persuade, intimidate,
## blackmail, patronage). All inside courts.gd / society.gd.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const PD := preload("res://scripts/realm/politics_data.gd")

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	for k in ["caldrenn", "solmarch"]:
		h.mod("courts").set_profile(k, "corrupt", 0.0)
		h.mod("courts").set_profile(k, "std", 0.55)
		h.mod("courts").set_profile(k, "wit", 1)
		h.mod("courts").set_profile(k, "harsh", 0.4)
		h.mod("courts").set_profile(k, "priv", 0.2)
	return h


func _sid_in(kingdom: String) -> int:
	for s: Dictionary in WorldGen.settlements:
		if PD.kingdom_of(int(s["id"])) == kingdom and String(s["kind"]) in ["village", "town"]:
			return int(s["id"])
	return int(WorldGen.settlements[0]["id"])


func _run(h: RefCounted, from: int, to: int) -> void:
	for d in range(from, to):
		h.mod("courts").tick_day(d, {})


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _lie_case(ct: RefCounted, sid: int, who: String) -> String:
	return ct.file_case("robbery", sid, {"id": "n1", "name": "Mara"}, {"id": who, "name": who}, {"culprit": "real_thief",
		"evidence": [{"type": "stolen_goods", "s": 0.75, "day": 0}]})


func test_wrong_person_accused_is_cleared_by_evidence_and_the_real_thief_is_charged() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var cid: String = ct.file_case("robbery", sid, {"id": "n1", "name": "Mara"}, {"id": "innocent", "name": "Wren"}, {"culprit": "real_thief", "malicious": true,
		"official": {"id": "ch:good", "name": "Sergeant Hale", "comp": 0.95, "honest": 0.95}, "evidence": [{"type": "stolen_goods", "s": 0.5, "day": 0}]})
	assert_bool(ct.add_evidence(cid, "footprints", 0.9, {"against": "real_thief"})).is_true()
	_run(h, 1, 60)
	var c: Dictionary = ct.case_of(cid)
	assert_str(String(c["cleared"])).is_equal("innocent")
	assert_str(String(c["accused"]["id"])).is_equal("real_thief")
	assert_int(ct.fines_due("innocent")).is_equal(0)
	assert_int(ct.jailed_until("innocent")).is_equal(-1)
	assert_str(String(c["state"])).is_equal("tried")
	# the malicious accuser's word is worth less afterwards
	assert_float(float(h.mod("reputation").truth("i:n1")["reliability"])).is_less(0.0)
	assert_int(int(ct.stats["cleared"])).is_equal(1)


func test_a_bought_officer_does_not_clear_and_a_skilled_one_finds_more_proof() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var a: String = ct.file_case("assault", sid, {"id": "n1", "name": "M"}, {"id": "inn1", "name": "I"}, {"culprit": "real1", "official": {"id": "o1", "name": "Sharp", "comp": 0.98, "honest": 0.9}})
	var b: String = ct.file_case("assault", sid, {"id": "n1", "name": "M"}, {"id": "inn2", "name": "I"}, {"culprit": "real2", "official": {"id": "o2", "name": "Dull", "comp": 0.0, "honest": 0.9}})
	_run(h, 1, 25)
	assert_int((ct.case_of(a)["evidence"] as Array).size()).is_greater((ct.case_of(b)["evidence"] as Array).size())
	# a bribed officer plants proof for the complainant (some officers refuse: try until one takes)
	var taken := false
	var planted := ""
	for i in 12:
		var cc: String = ct.file_case("robbery", sid, {"id": "n%d" % i, "name": "x"}, {"id": "target%d" % i, "name": "t"}, {"culprit": "other", "official": {"id": "crook", "name": "Crook", "comp": 0.5, "honest": 0.05}})
		if bool(ct.bribe_officer(cc, "complainant", 100 + i)["taken"]):
			taken = true
			planted = cc
			break
	assert_bool(taken).is_true()
	var fake := 0
	for e: Dictionary in ct.case_of(planted)["evidence"]:
		if bool(e.get("fake", false)):
			fake += 1
	assert_int(fake).is_equal(1)


func test_a_bribed_witness_convicts_an_innocent_and_an_honest_one_refuses() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var clean := _lie_case(ct, sid, "inn_a")
	ct.bring_to_court(clean)
	assert_str(String(ct.trial(clean)["verdict"])).is_not_equal("guilty")      # evidence alone, no witness: not enough
	var dirty := _lie_case(ct, sid, "inn_b")
	var r: Dictionary = {}
	for i in 10:
		r = ct.suborn_witness(dirty, "wit%d" % i, "accuser", "bribe", 250)
		if bool(r["taken"]):
			break
	assert_bool(bool(r["taken"])).is_true()
	assert_str(String(r["state"])).is_equal("bribed")
	ct.bring_to_court(dirty)
	var res: Dictionary = ct.trial(dirty)
	assert_str(String(res["verdict"])).override_failure_message("total %s" % str(res.get("total"))).is_equal("guilty")
	# threats work on the timid, not on the bold; a failed attempt marks the briber
	var refused := false
	for i in 40:
		var cc := _lie_case(ct, sid, "inn_c%d" % i)
		var rr: Dictionary = ct.suborn_witness(cc, "tiny%d" % i, "accuser", "bribe", 1)
		if not bool(rr["taken"]):
			refused = true
			assert_int(int(ct.case_of(cc)["exposed"])).is_equal(1)
			break
	assert_bool(refused).is_true()
	assert_int(int(ct.stats["suborned"])).is_greater(0)


func test_church_and_secular_courts_reach_different_verdicts_on_the_same_case() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sec := _sid_in("caldrenn")
	var chu := sec
	assert_bool(ct.culture("solmarch")["church"]).is_true()
	assert_bool(ct.culture("caldrenn")["church"]).is_false()
	var opts := {"culprit": "grifter", "witnesses": [{"id": "n1", "name": "Mara", "saw": true, "conf": 0.8}],
		"evidence": [{"type": "letter", "s": 0.2, "day": 0}, {"type": "magic_trace", "s": 0.3, "day": 0}]}
	var a: String = ct.file_case("fraud", sec, {"id": "n1", "name": "Mara"}, {"id": "grifter", "name": "G"}, opts)
	var b: String = ct.file_case("fraud", chu, {"id": "n1", "name": "Mara"}, {"id": "grifter", "name": "G"}, opts.merged({"kingdom": "solmarch"}))
	ct.bring_to_court(a)
	ct.bring_to_court(b)
	var ra: Dictionary = ct.trial(a)
	var rb: Dictionary = ct.trial(b)
	var msg := "secular %s %s church %s %s" % [ra["verdict"], ra["total"], rb["verdict"], rb["total"]]
	assert_str(String(ra["verdict"])).override_failure_message(msg).is_not_equal("guilty")
	assert_str(String(rb["verdict"])).override_failure_message(msg).is_equal("guilty")
	assert_bool(rb["sentence"].has("penance")).is_true()
	assert_bool(ra.get("sentence", {}).has("penance")).is_false()


func test_an_appeal_with_new_proof_reverses_a_wrongful_conviction() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var cid := _lie_case(ct, sid, "inn_d")
	for i in 10:
		if bool(ct.suborn_witness(cid, "liar%d" % i, "accuser", "bribe", 250)["taken"]):
			break
	ct.bring_to_court(cid)
	assert_str(String(ct.trial(cid)["verdict"])).is_equal("guilty")
	assert_int(ct.fines_due("inn_d")).is_greater(0)
	var ap: Dictionary = ct.appeal(cid, {"id": "inn_d", "name": "x", "kind": "npc", "fame": 2.0, "rank": 0, "sponsors": []},
		{"evidence": [{"type": "footprints", "s": 0.9, "against": "real_thief"}]})
	assert_bool(bool(ap["ok"])).is_true()
	assert_bool(bool(ap["overturned"])).is_true()
	assert_int(ct.fines_due("inn_d")).is_equal(0)
	assert_int(int(ct.stats["overturned"])).is_equal(1)


func test_corruption_reads_and_feeds_the_districts_value() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var dv: RefCounted = h.mod("districts")
	var sid := _sid_in("caldrenn")
	for s: Dictionary in WorldGen.settlements:
		if not dv.quarters_of(int(s["id"])).is_empty() and PD.kingdom_of(int(s["id"])) == "caldrenn":
			sid = int(s["id"])
			break
	assert_float(ct.district_corruption(sid)).is_between(0.0, 1.0)
	ct.set_profile("caldrenn", "corrupt", 0.9)
	var before: float = ct.district_corruption(sid)
	var took := 0
	for i in 12:
		var cid: String = ct.file_case("robbery", sid, {"id": "n1", "name": "x"}, {"id": "p%d" % i, "name": "p"}, {})
		if bool(ct.bribe(cid, "accused", 300 + i)["taken"]):
			took += 1
	assert_int(took).is_greater(0)
	if not dv.quarters_of(sid).is_empty():
		assert_float(ct.district_corruption(sid)).is_greater(before)


func test_a_broken_oath_costs_reputation_more_than_a_promise_and_most_in_a_church_realm() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var rep: RefCounted = h.mod("reputation")
	var sec := _sid_in("caldrenn")
	var pr: String = ct.make_obligation("promise", "ch:a", "ch:b", 5, {"sid": sec})
	var oa: String = ct.make_obligation("oath", "ch:c", "ch:b", 5, {"sid": sec})
	var oc: String = ct.make_obligation("oath", "ch:d", "ch:b", 5, {"sid": sec, "kingdom": "solmarch"})
	var kept: String = ct.make_obligation("oath", "ch:e", "ch:b", 5, {"sid": sec})
	assert_str(pr).is_not_empty()
	assert_bool(bool(ct.fulfil(kept)["ok"])).is_true()
	ct.break_obligation(pr)
	ct.break_obligation(oa)
	ct.break_obligation(oc)
	var ra: float = rep.truth("i:ch:a")["reliability"]
	var rc: float = rep.truth("i:ch:c")["reliability"]
	var rd: float = rep.truth("i:ch:d")["reliability"]
	assert_float(ra).is_less(0.0)
	assert_float(rc).is_less(ra)
	assert_float(rd).is_less(rc)
	assert_float(float(rep.truth("i:ch:e")["reliability"])).is_greater(0.0)
	assert_str(String(ct.obligation(oa)["state"])).is_equal("broken")
	assert_int(int(ct.stats["oaths_broken"])).is_equal(3)


func test_debts_fall_due_the_player_gets_a_grace_period_and_the_creditor_sues() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var oid: String = ct.make_obligation("debt", "player", "ch:lender", 10, {"sid": sid, "gold": 80})
	_run(h, 1, 20)
	assert_str(String(ct.obligation(oid)["state"])).is_equal("open")      # inside the grace period
	_run(h, 20, 30)
	assert_str(String(ct.obligation(oid)["state"])).is_equal("broken")
	var found := false
	for c: Dictionary in ct.cases():
		if String(c["crime"]) == "fraud" and String(c["accused"]["id"]) == "player":
			found = true
	assert_bool(found).is_true()
	var pay: String = ct.make_obligation("debt", "player", "lender_npc", 99, {"sid": sid, "gold": 50})
	var f: Dictionary = ct.fulfil(pay)
	assert_bool(bool(f["ok"])).is_true()
	assert_int(int(f["cost"])).is_equal(50)          # the caller deducts it, courts never touches the player's purse


func test_blackmail_needs_a_known_secret_and_a_used_secret_loses_force() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var none: Dictionary = ct.influence("blackmail", "player", "ch:baron", {"sid": sid})
	assert_bool(bool(none["ok"])).is_false()
	assert_str(String(none["reason"])).contains("nothing")
	assert_bool(ct.learn_secret("player", "ch:baron", "hid a body", 0.8)).is_true()
	var first: Dictionary = ct.influence("blackmail", "player", "ch:baron", {"sid": sid})
	assert_bool(bool(first["ok"])).is_true()
	var second: Dictionary = ct.influence("blackmail", "player", "ch:baron", {"sid": sid})
	assert_float(float(second["p"])).is_less(float(first["p"]))
	# a secret about someone else is no use against this one
	assert_bool(bool(ct.influence("blackmail", "player", "ch:other", {"sid": sid})["ok"])).is_false()
	# a case teaches its observer the culprit's guilt
	var cid: String = ct.file_case("murder", sid, {"id": "n1", "name": "x"}, {}, {"culprit": "ch:killer"})
	assert_bool(ct.secret_from_case("ch:clerk", cid)).is_true()
	assert_int(ct.secrets_known("ch:clerk", "ch:killer").size()).is_equal(1)
	if bool(first["success"]):
		assert_str(String(first["obligation"])).is_not_empty()


func test_influence_chances_follow_authority_threat_and_the_targets_nerve() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var low: Dictionary = ct.influence("persuade", "a", "ch:t", {"sid": sid})
	var high: Dictionary = ct.influence("persuade", "b", "ch:t", {"sid": sid, "actor_state": {"title_rank": 5, "insignia": 1.0}})
	assert_float(float(high["p"])).is_greater(float(low["p"]))
	var meek: Dictionary = ct.influence("intimidate", "c", "ch:t", {"sid": sid})
	var armed: Dictionary = ct.influence("intimidate", "d", "ch:t", {"sid": sid, "actor_state": {"weapons": 1.0, "companions": 3}})
	assert_float(float(armed["p"])).is_greater(float(meek["p"]))
	var hard: Dictionary = ct.influence("persuade", "e", "ch:t", {"sid": sid, "ask": 1.0})
	assert_float(float(hard["p"])).is_less(float(low["p"]))
	var small: Dictionary = ct.influence("patronage", "f", "ch:t", {"sid": sid, "gold": 20})
	var big: Dictionary = ct.influence("patronage", "g", "ch:t", {"sid": sid, "gold": 150})
	assert_float(float(big["p"])).is_greater(float(small["p"]))
	assert_int(int(big["cost"])).is_equal(150)
	assert_bool(bool(ct.influence("patronage", "g", "ch:t", {"sid": sid})["ok"])).is_false()


func _play(h: RefCounted) -> void:
	var ct: RefCounted = h.mod("courts")
	var sid := _sid_in("caldrenn")
	var cid := _lie_case(ct, sid, "inn_z")
	ct.suborn_witness(cid, "liar", "accuser", "bribe", 250)
	ct.add_evidence(cid, "footprints", 0.8, {"against": "real_thief"})
	ct.make_obligation("oath", "ch:x", "ch:y", 8, {"sid": sid})
	ct.make_obligation("debt", "player", "ch:y", 9, {"sid": sid, "gold": 30})
	ct.learn_secret("player", "ch:baron", "s", 0.7)
	ct.influence("blackmail", "player", "ch:baron", {"sid": sid})
	ct.influence("persuade", "player", "ch:baron", {"sid": sid})
	_run(h, 1, 40)


func test_same_play_gives_the_same_world() -> void:
	var h1 := _hub()
	var h2 := _hub()
	_play(h1)
	_play(h2)
	assert_str(_norm(h1.mod("courts").serialize())).is_equal(_norm(h2.mod("courts").serialize()))


func test_save_and_load_keeps_obligations_secrets_cases_and_continues_identically() -> void:
	var h := _hub()
	_play(h)
	var ct: RefCounted = h.mod("courts")
	ct.make_obligation("favour", "ch:p", "ch:q", 80, {"sid": 3})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ct.serialize()))
	var h2 := _hub()
	h2.mod("courts").deserialize(saved)
	assert_str(_norm(h2.mod("courts").serialize())).is_equal(_norm(ct.serialize()))
	assert_int(h2.mod("courts").secrets_known("player").size()).is_equal(1)
	assert_int(h2.mod("courts").obligations_of("ch:p").size()).is_equal(1)
	_run(h, 40, 70)
	_run(h2, 40, 70)
	assert_str(_norm(h2.mod("courts").serialize())).is_equal(_norm(ct.serialize()))
