extends GdUnitTestSuite
## LW-6.1 to 6.4 (docs/design/LIVING_WORLD_SANDBOX.md sections 7, 8, 13): authority chain per location, petitions and audiences in 8 steps (access gated by
## fame, rank and sponsors; rejections with reasons; documents; disputes; reviews), multi-axis reputation with travel delay, marriage and inheritance
## (marriage never grants a throne), running a territory (neglect loses office), territory layers (capture is not lordship), diplomacy with memory of
## broken pacts and reactions to independent factions, justice (laws per kingdom, cases, courts, appeals, corruption), NPC parity, save, tick cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const PD := preload("res://scripts/realm/politics_data.gd")
const Soc := preload("res://scripts/realm/society.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const HV := preload("res://scripts/world/hidden_valley.gd")
const MODS := ["reputation", "stewardship", "audiences", "territory", "diplomacy", "courts", "succession"]

static var _world := false


func _hub() -> RefCounted:
	if not _world or WorldGen._hills.seed != 2024:   # other suites in the same process may re-seed the world
		WorldGen.setup(2024)
		_world = true
	WorldSim.day = 0   # the politics modules read max(hub day, WorldSim.day); earlier suites leave it far ahead
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	return h


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _pass(h: RefCounted, from: int, to: int) -> void:
	h.set_meta("day", maxi(to, _cur(h)))
	for d in range(from, to + 1):
		for k: String in MODS:
			h.mod(k).tick_day(d, {})
		if d % 7 == 0:
			for k: String in MODS:
				h.mod(k).tick_week(d / 7, {})


func _sid(kind: String, nth := 0) -> int:
	var n := 0
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == kind:
			if n == nth:
				return int(s["id"])
			n += 1
	return int(WorldGen.settlements[0]["id"])


func _who(id: String, fame := 12.0, rank := 0, kind := "player") -> Dictionary:
	return {"id": id, "name": id, "kind": kind, "fame": fame, "rank": rank, "sponsors": []}


func _good_name(h: RefCounted, id: String, sid: int) -> void:
	var rep: RefCounted = h.mod("reputation")
	for ax: String in ["trust", "reliability", "legitimacy"]:
		rep.record("i:" + id, ax, 45.0, sid, "none")


func _ev(kinds: Array, s := 0.9) -> Array:
	var out: Array = []
	for k: String in kinds:
		out.append({"kind": k, "s": s})
	return out


## Files and presents a petition with strong evidence and a good name; returns the pid.
func _strong(h: RefCounted, ptype: String, sid: int, who: Dictionary, subject: Dictionary = {}) -> String:
	var aud: RefCounted = h.mod("audiences")
	_good_name(h, String(who["id"]), sid)
	var spec: Dictionary = PD.PETITIONS[ptype]
	var fr: Dictionary = aud.file(ptype, sid, who, subject)
	assert_bool(bool(fr["ok"])).override_failure_message("%s: %s" % [ptype, fr.get("reason", "")]).is_true()
	aud.present(String(fr["pid"]), _ev((spec["need"] as Array) + (spec["help"] as Array), 0.95))
	return String(fr["pid"])


func _cur(h: RefCounted) -> int:
	return int(h.get_meta("day", 0))


func _hear(h: RefCounted, pid: String, _from_day := 1) -> Dictionary:
	var aud: RefCounted = h.mod("audiences")
	for d in range(_cur(h) + 1, _cur(h) + 60):
		_pass(h, d, d)
		if String(aud.petition(pid)["state"]) == "audience":
			break
	return aud.attend(pid)


# --- 1. authority chain -------------------------------------------------------------------------

func test_authority_chain_has_four_offices_with_real_holders() -> void:
	var h := _hub()
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var c: Array = st.chain(sid)
	assert_int(c.size()).is_equal(4)
	var roles := ["headman", "district magistrate", "governor", "crown"]
	for i in 4:
		assert_int(int(c[i]["level"])).is_equal(i)
		assert_str(String(c[i]["role"])).is_equal(roles[i])
		assert_str(String(c[i]["holder"])).is_not_equal("vacant")
		assert_str(String(c[i]["name"])).is_not_empty()
		assert_bool((c[i]["limits"] as Dictionary).has("tax")).is_true()
		assert_str(String(c[i]["gatekeeper"])).is_not_empty()
	assert_str(String(c[3]["holder"])).starts_with("ruler:")
	# limits grow with rank; permissions follow the petition table
	assert_float(st.limit(0, "tax")).is_less(st.limit(3, "tax"))
	assert_bool(st.permits(0, "land")).is_false()
	assert_bool(st.permits(2, "land")).is_true()
	assert_bool(st.permits(3, "title")).is_true()
	# jurisdiction: the district office covers this village
	assert_bool((st.jurisdiction(String(c[1]["key"])) as Array).has(sid)).is_true()
	# deterministic: a second hub names the same holders
	var c2: Array = _hub().mod("stewardship").chain(sid)
	for i in 4:
		assert_str(String(c2[i]["holder"])).is_equal(String(c[i]["holder"]))


# --- 2. the 8 steps ----------------------------------------------------------------------------------

func test_a_petition_goes_through_eight_steps_with_a_record() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var who := _who("player")
	_good_name(h, "player", sid)
	var idf: Dictionary = aud.identify("tax_relief", sid)
	assert_bool(bool(idf["ok"])).is_true()
	assert_int(int(idf["level"])).is_equal(1)
	assert_str(String(idf["office"]["role"])).is_equal("district magistrate")
	var fr: Dictionary = aud.file("tax_relief", sid, who)
	assert_bool(bool(fr["ok"])).is_true()
	var pid := String(fr["pid"])
	var pr: Dictionary = aud.present(pid, _ev(["witness", "survey", "recommendation"]))
	assert_bool(bool(pr["ok"])).is_true()
	assert_int(int(pr["wait"])).is_greater(0)
	assert_str(String(aud.petition(pid)["state"])).is_equal("waiting")
	assert_dict(aud.attend(pid)).contains_keys(["ok"])                    # too early: no hearing yet
	assert_bool(bool(aud.attend(pid)["ok"])).is_false()
	var sheet := _hear(h, pid)
	assert_bool(bool(sheet["ok"])).is_true()
	assert_bool(bool(sheet["refused"])).is_false()
	assert_array(sheet["lines"]).is_not_empty()
	var ids: Array = []
	for c: Dictionary in sheet["choices"]:
		ids.append(c["id"])
	assert_bool(ids.has("accept") and ids.has("haggle") and ids.has("withdraw")).is_true()
	var tax_before: float = st.tax_rate(sid)
	var nr: Dictionary = aud.negotiate(pid, {"accept": true})
	assert_str(String(nr["state"])).is_equal("agreed")
	var d: Dictionary = aud.issue(pid)
	assert_str(String(d["kind"])).is_equal("grant")
	assert_str(String(d["state"])).is_equal("valid")
	assert_bool(float(d["terms"]["relief"]) > 0.0).is_true()
	assert_float(st.tax_rate(sid)).is_less(tax_before + 0.0001)
	var steps: Array = []
	for s: Array in aud.petition(pid)["steps"]:
		steps.append(int(s[0]))
	for n in range(1, 9):
		assert_bool(steps.has(n)).override_failure_message("step %d missing in %s" % [n, steps]).is_true()
	assert_str(String(aud.petition(pid)["state"])).is_equal("granted")
	assert_bool(aud.has_right("player", "tax_relief", sid)).is_true()


func test_rejections_give_reasons_and_a_cooldown() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var sid := _sid("village")
	var fr: Dictionary = aud.file("tax_relief", sid, _who("poor"))
	aud.present(String(fr["pid"]), [])                                    # nothing to show
	var sheet := _hear(h, String(fr["pid"]))
	assert_bool(bool(sheet["refused"])).is_true()
	var p: Dictionary = aud.petition(String(fr["pid"]))
	assert_str(String(p["state"])).is_equal("rejected")
	assert_bool((p["reasons"] as Array).has("no_evidence:witness")).is_true()
	assert_array(aud.reason_words(p["reasons"])).is_not_empty()
	var again: Dictionary = aud.file("tax_relief", sid, _who("poor"))
	assert_bool(bool(again["ok"])).is_false()
	assert_bool((again["missing"] as Array).has("cooldown")).is_true()
	# a bad name alone is not enough, a good one is not forced: unreliable people are refused with that reason
	var h2 := _hub()
	var a2: RefCounted = h2.mod("audiences")
	h2.mod("reputation").record("i:liar", "reliability", -60.0, sid, "none")
	var f2: Dictionary = a2.file("tax_relief", sid, _who("liar"))
	a2.present(String(f2["pid"]), _ev(["witness", "survey", "recommendation"]))
	var s2 := _hear(h2, String(f2["pid"]))
	assert_bool(bool(s2["refused"])).is_true()
	assert_bool((a2.petition(String(f2["pid"]))["reasons"] as Array).has("unreliable")).is_true()
	# a hearing nobody attends lapses
	var f3: Dictionary = a2.file("trade_rights", sid, _who("absent"))
	a2.present(String(f3["pid"]), _ev(["witness"]))
	_pass(h2, 1, 40)
	assert_str(String(a2.petition(String(f3["pid"]))["state"])).is_equal("lapsed")


func test_access_is_gated_by_fame_rank_and_sponsors_and_the_king_is_rare() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var sid := _sid("village")
	assert_bool(bool(aud.access(_who("a", 0.0, 0), 0, sid)["ok"])).is_true()          # the village clerk lets anyone in
	var low: Dictionary = aud.access(_who("a", 2.0, 0), 1, sid)
	assert_bool(bool(low["ok"])).is_false()
	assert_bool((low["missing"] as Array).has("fame")).is_true()
	var sp := _who("b", 2.0, 0)
	sp["sponsors"] = [{"id": "x", "name": "Sir X", "rank": 2}]
	assert_bool(bool(aud.access(sp, 1, sid)["ok"])).is_true()                          # a sponsor opens the district door
	assert_bool(bool(aud.access(_who("c", 30.0, 0), 2, sid)["ok"])).is_false()         # a governor wants rank or a sponsor as well as a name
	assert_bool(bool(aud.access(_who("c", 55.0, 0), 2, sid)["ok"])).is_true()          # unless the name is very great
	assert_bool(bool(aud.access(_who("c", 30.0, 2), 2, sid)["ok"])).is_true()
	var king: Dictionary = aud.access(_who("d", 30.0, 1), 3, sid)
	assert_bool(bool(king["ok"])).is_false()
	for m: String in ["rank", "fame", "sponsor"]:
		assert_bool((king["missing"] as Array).has(m)).override_failure_message(m).is_true()
	var fr: Dictionary = aud.file("title", sid, _who("d", 30.0, 1), {"rank": 3})
	assert_bool(bool(fr["ok"])).is_false()
	assert_str(String(fr["reason"])).contains("chamberlain")
	var earned := _who("e", 90.0, 4)
	earned["sponsors"] = [{"id": "y", "name": "Duke Y", "rank": 3}]
	assert_bool(bool(aud.access(earned, 3, sid)["ok"])).is_true()
	assert_bool(bool(aud.access(_who("f", 90.0, 4), 3, sid)["ok"])).is_false()          # no sponsor, no king
	assert_int(int(aud.stats["turned_away"])).is_greater(0)


func test_negotiation_haggles_counters_and_can_collapse() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var sid := _sid("village")
	var pid := _strong(h, "trade_rights", sid, _who("trader"))
	var sheet := _hear(h, pid)
	assert_bool(bool(sheet["refused"])).is_false()
	var tm: Dictionary = sheet["terms"]
	assert_float(float(tm["tax"])).is_greater(0.0)
	# an offer within what the good name buys is agreed
	var ok: Dictionary = aud.negotiate(pid, {"tax": float(tm["tax"]) * 0.85, "levy": int(tm["levy"]), "build": int(tm["build"])})
	assert_str(String(ok["state"])).is_equal("agreed")
	# an absurd offer gets counters and then the talks fail with a reason
	var h2 := _hub()
	var a2: RefCounted = h2.mod("audiences")
	var p2 := _strong(h2, "trade_rights", sid, _who("greedy"))
	_hear(h2, p2)
	var r1: Dictionary = a2.negotiate(p2, {"tax": 0.0, "levy": 0, "build": 9999})
	assert_str(String(r1["state"])).is_equal("counter")
	assert_bool((r1["failed"] as Array).has("tax")).is_true()
	a2.negotiate(p2, {"tax": 0.0, "levy": 0})
	var r3: Dictionary = a2.negotiate(p2, {"tax": 0.0, "levy": 0})
	assert_str(String(r3["state"])).is_equal("refused")
	assert_str(String(a2.petition(p2)["state"])).is_equal("rejected")
	assert_bool((a2.petition(p2)["reasons"] as Array).has("talks_failed")).is_true()
	# a higher office demands loyalty, and swearing it buys a better price
	var h3 := _hub()
	var a3: RefCounted = h3.mod("audiences")
	var rich := _who("rich", 40.0, 2)
	var p3 := _strong(h3, "mining_rights", sid, rich)
	var s3 := _hear(h3, p3)
	assert_bool(bool(s3["terms"]["loyalty"])).is_true()
	var no_oath: Dictionary = a3.negotiate(p3, {"tax": float(s3["terms"]["tax"]), "levy": int(s3["terms"]["levy"])})
	assert_bool((no_oath["failed"] as Array).has("loyalty")).is_true()
	var oath: Dictionary = a3.negotiate(p3, {"swear": true, "tax": float(s3["terms"]["tax"]) * 0.8})
	assert_str(String(oath["state"])).is_equal("agreed")


func test_every_petition_type_issues_its_document() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var gv: RefCounted = h.mod("governance")
	gv.leader_of_settlement(sid)
	for s2: Dictionary in WorldGen.settlements:
		gv.set_law(int(s2["id"]), "land_ownership", 0, "test")
		gv.set_law(int(s2["id"]), "guild_licensing", 0, "test")
	var seen := {}
	var day := 1
	for ptype: String in PD.PETITIONS:
		var who := _who("p_" + ptype, 90.0, 4)
		h.mod("audiences").sponsor(String(who["id"]), "lord1", "Lord One", 3)
		who["sponsors"] = h.mod("audiences").sponsors_of(String(who["id"]))
		var sub: Dictionary = {}
		match ptype:
			"settlement_recognition": sub = {"scale": "village", "pos": [100.0, 100.0], "cells": 2}
			"title": sub = {"rank": 2, "title": "knight"}
			"office": sub = {"office": st.office_key(sid, 0)}
		var pid := _strong(h, ptype, sid, who, sub)
		var sheet := _hear(h, pid, day)
		day += 1
		assert_bool(bool(sheet["refused"])).override_failure_message("%s refused: %s" % [ptype, aud.petition(pid)["reasons"]]).is_false()
		assert_str(String(aud.negotiate(pid, {"accept": true})["state"])).is_equal("agreed")
		var d: Dictionary = aud.issue(pid)
		assert_str(String(d["kind"])).override_failure_message(ptype).is_equal(String((PD.PETITIONS[ptype] as Dictionary)["doc"]))
		seen[String(d["kind"])] = true
	for k: String in PD.DOC_KINDS:
		assert_bool(seen.has(k)).override_failure_message("no " + k).is_true()
	# consequences are real
	assert_int(st.rank_of("p_title")).is_greater_equal(2)
	assert_str(String(st.office(st.office_key(sid, 0))["holder"])).is_equal("p_office")
	assert_str(String(h.mod("land").deed(sid).get("holder", ""))).is_equal("p_land")
	assert_bool(aud.has_right("p_mining_rights", "mining_rights", sid)).is_true()


func test_documents_are_disputed_breached_and_lapse_on_unpaid_dues() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var sid := _sid("village")
	var pid := _strong(h, "trade_rights", sid, _who("player"))
	_hear(h, pid)
	aud.negotiate(pid, {"accept": true})
	var d: Dictionary = aud.issue(pid)
	var did := String(d["id"])
	# a rival disputes it; the issuing office rules
	var rival := _who("rival", 20.0, 1, "npc")
	assert_bool(bool(aud.dispute(did, _who("player"), "mine")["ok"]) ).is_false()           # you cannot dispute your own
	var x: Dictionary = aud.dispute(did, rival, "it was my stall first", [{"kind": "witness", "s": 0.9}])
	assert_bool(bool(x["ok"])).is_true()
	var ruling: Dictionary = aud.rule_dispute(String(x["xid"]), "upheld")
	assert_bool(bool(ruling["upheld"])).is_true()
	assert_str(String(aud.doc(did)["state"])).is_equal("revoked")
	assert_bool(aud.has_right("player", "trade_rights", sid)).is_false()
	# a second licence: three breaches revoke it
	var p2 := _strong(h, "mining_rights", sid, _who("p2", 40.0, 2))
	_hear(h, p2, 10)
	aud.negotiate(p2, {"swear": true, "accept": false, "tax": 1.0})
	var d2: Dictionary = aud.issue(p2)
	if d2.is_empty():
		aud.negotiate(p2, {"accept": true})
		d2 = aud.issue(p2)
	var id2 := String(d2["id"])
	assert_int(aud.breach(id2, "built too much")).is_equal(1)
	assert_int(aud.breach(id2, "built too much")).is_equal(2)
	aud.breach(id2, "built too much")
	assert_str(String(aud.doc(id2)["state"])).is_equal("revoked")
	# a third: the player's dues fall into arrears and the licence is lost
	var p3 := _strong(h, "trade_rights", sid, _who("player2"))
	_hear(h, p3, 20)
	aud.negotiate(p3, {"accept": true})
	var d3: Dictionary = aud.issue(p3)
	assert_float(float(d3["terms"]["tax"])).is_greater(0.0)
	for w in 9:
		aud.tick_week(w, {})
	assert_str(String(aud.doc(String(d3["id"]))["state"])).is_equal("revoked")
	assert_int(int(aud.stats["revoked"])).is_greater_equal(3)


func test_a_new_ruler_reviews_what_the_old_one_granted() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var pid := _strong(h, "trade_rights", sid, _who("player"))
	_hear(h, pid)
	aud.negotiate(pid, {"accept": true})
	var d: Dictionary = aud.issue(pid)
	var key := String(d["key"])
	assert_bool(st.assume(key, "new_magistrate", "Magistrate New")).is_true()
	assert_str(String(aud.doc(String(d["id"]))["state"])).is_equal("review")
	assert_bool(aud.has_right("player", "trade_rights", sid)).is_true()                 # still honoured while in review
	_pass(h, 1, 40)
	var after := String(aud.doc(String(d["id"]))["state"])
	assert_bool(after in ["valid", "revoked"]).override_failure_message(after).is_true()
	assert_int(int(aud.stats["reviewed"])).is_equal(1)
	assert_str(String(aud.doc(String(d["id"]))["issuer"])).is_equal("new_magistrate")


func _org_char(h: RefCounted, cash: int, rep: float) -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": 0, "prof": "smith", "rep": rep, "sk": {"combat": 0.7, "crafting": 0.7, "trading": 0.7, "farming": 0.7, "faith": 0.7, "lore": 0.7, "stealth": 0.7}})
	return ch


func test_org_and_settlement_stubs_are_resolved_by_audiences() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var aud: RefCounted = h.mod("audiences")
	var lead: String = h.mod("registry").mint("ch")
	om.ensure_char(lead, {"cash": 2000, "sid": 0, "prof": "smith", "rep": 10.0, "sk": {"combat": 0.7, "crafting": 0.7, "trading": 0.7, "farming": 0.7, "faith": 0.7, "lore": 0.7, "stealth": 0.7}})
	var res: Dictionary = om.start_founding(lead, "craft_guild", "Audience Guild", 0)
	var oid: String = res["org"]
	var m2: String = h.mod("registry").mint("ch")
	om.ensure_char(m2, {"cash": 300, "sid": 0, "prof": "smith", "rep": 10.0, "sk": {"combat": 0.7, "crafting": 0.7, "trading": 0.7, "farming": 0.7, "faith": 0.7, "lore": 0.7, "stealth": 0.7}})
	om.add_founder(oid, lead, m2)
	om.add_founder(oid, lead, _org_char(h, 300, 10.0))
	assert_bool(bool(om.draft_charter(oid, lead, "We make fair steel.")["ok"])).is_true()
	for m: String in om.members_of(oid):
		om.record_activity(oid, m, 6.0)
	om._settle(oid, 5)
	var pet: Dictionary = om.petition_recognition(oid, lead)
	assert_bool(bool(pet["ok"])).override_failure_message(str(pet)).is_true()
	assert_str(String(om.org(oid)["legal"])).is_equal("petitioned")
	_pass(h, 1, 6)                                                           # before the old stub would decide (7 days)
	assert_str(String(om.org(oid)["legal"])).is_equal("recognised")
	var rec: Array = aud.petitions("granted")
	assert_bool(rec.any(func(p: Dictionary) -> bool: return p["type"] == "org_recognition")).is_true()
	assert_bool(aud.documents("", "valid").any(func(d: Dictionary) -> bool: return d["type"] == "org_recognition" and d["kind"] == "charter")).is_true()
	# an unknown body with no name is refused, with a reason in the org's own record
	var l2: String = h.mod("registry").mint("ch")
	om.ensure_char(l2, {"cash": 2000, "sid": 0, "prof": "smith", "rep": 0.0, "sk": {"combat": 0.7, "crafting": 0.7, "trading": 0.7, "farming": 0.7, "faith": 0.7, "lore": 0.7, "stealth": 0.7}})
	var o2: String = om.start_founding(l2, "craft_guild", "Nobody Guild", 0)["org"]
	var m3: String = h.mod("registry").mint("ch")
	om.ensure_char(m3, {"cash": 300, "sid": 0, "prof": "smith", "rep": 0.0, "sk": {"combat": 0.7, "crafting": 0.7, "trading": 0.7, "farming": 0.7, "faith": 0.7, "lore": 0.7, "stealth": 0.7}})
	om.add_founder(o2, l2, m3)
	om.add_founder(o2, l2, _org_char(h, 300, 0.0))
	assert_bool(bool(om.draft_charter(o2, l2, "x")["ok"])).is_true()
	om.petition_recognition(o2, l2)
	_pass(h, 7, 14)
	assert_str(String(om.org(o2)["legal"])).is_not_equal("recognised")
	var refused: Array = aud.petitions("rejected", o2)
	assert_int(refused.size()).is_equal(1)
	assert_array(aud.reason_words(refused[0]["reasons"])).is_not_empty()


func _founding_at_recognition(h: RefCounted) -> Array:
	var fd: RefCounted = h.mod("founding")
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	h.mod("civilization").runestones = rs
	h.mod("civilization")._ensure()
	h.mod("land")._ensure()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var pos := Vector2.ZERO
	var found := false
	for _i in 4000:
		var s: Dictionary = WorldGen.settlements[rng.randi() % WorldGen.settlements.size()]
		var p: Vector2 = (s["pos"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(400.0, 1500.0)
		if absf(p.x) > 5500.0 or absf(p.y) > 5500.0 or LandClaim.block_reason(p) != "" or HV.in_valley(p) or HV.protected_ground(p):
			continue
		var ev: Dictionary = fd.evaluate_site(p)
		if float(ev["overall"]) >= 0.3 and float(ev["camp"]) >= 0.26:
			pos = p
			found = true
			break
	assert_bool(found).is_true()
	var r: Dictionary = fd.begin(pos, "Fernrest", "player")
	assert_bool(bool(r["ok"])).is_true()
	var f: Dictionary = fd.get_founding(int(r["fid"]))
	f["st"] = 7                                                              # the recognition stage (the founding flow itself is test_founding's)
	(f["off"] as Dictionary)["reeve"] = {"n": "Bram", "c": 0.6, "h": 0.7, "age": 40, "since": 0}
	return [int(r["fid"]), f]


func test_the_settlement_recognition_stub_goes_through_a_hearing() -> void:
	var h := _hub()
	var fd: RefCounted = h.mod("founding")
	var fx := _founding_at_recognition(h)
	var fid: int = fx[0]
	var f: Dictionary = fx[1]
	assert_bool(bool(fd.file_petition(fid)["ok"])).is_true()
	assert_bool(bool(f["rights"]["govern"])).is_false()
	(f["pet"] as Dictionary)["pop"] = 60                                    # settlers who can vouch for the place
	_pass(h, 1, 1)
	var pid := String(f["pet"].get("pid", ""))
	assert_str(pid).override_failure_message(str(f["pet"])).is_not_empty()   # audiences took the stub
	assert_str(String(f["pet"]["stage6"])).is_equal("audiences")
	_pass(h, 2, 40)
	assert_str(String(h.mod("audiences").petition(pid)["state"])).is_equal("granted")
	assert_bool(bool(f["rights"]["govern"])).is_true()
	assert_bool(h.mod("audiences").has_right("fo:%d" % fid, "settlement_recognition", -1)).is_true()
	# an empty place with no one to vouch for it is refused, and the refusal reaches the founding record
	var h2 := _hub()
	var fx2 := _founding_at_recognition(h2)
	var f2: Dictionary = fx2[1]
	h2.mod("founding").file_petition(int(fx2[0]))
	_pass(h2, 1, 40)
	assert_str(String(f2["pet"]["state"])).is_equal("refused")
	assert_bool(bool(f2["rights"]["govern"])).is_false()
	var rej: Array = h2.mod("audiences").petitions("rejected", "fo:%d" % int(fx2[0]))
	assert_int(rej.size()).is_equal(1)
	assert_array(h2.mod("audiences").reason_words(rej[0]["reasons"])).is_not_empty()


func test_npcs_use_the_same_petition_pipeline() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	_pass(h, 1, 90)
	assert_int(int(aud.stats["npc"])).is_greater(5)
	assert_int(int(aud.stats["granted"])).is_greater(0)
	var any_npc := false
	for p: Dictionary in aud.petitions():
		if String(p["by"]["kind"]) == "npc":
			any_npc = true
			assert_bool(bool(p["proxy"])).is_true()
			assert_array(p["steps"]).is_not_empty()
	assert_bool(any_npc).is_true()
	var granted_npc: Array = aud.documents().filter(func(d: Dictionary) -> bool: return d["hkind"] == "npc")
	assert_array(granted_npc).is_not_empty()
	assert_bool(h.mod("audiences").petitions("rejected").size() > 0 or aud.petitions("granted").size() > 3).is_true()


# --- 3. reputation -------------------------------------------------------------------------------------

func _far_pair() -> Array:
	var best := [0, 0]
	var bd := 0.0
	for a: Dictionary in WorldGen.settlements:
		for b: Dictionary in WorldGen.settlements:
			var d := (a["pos"] as Vector2).distance_to(b["pos"])
			if d > bd:
				bd = d
				best = [int(a["id"]), int(b["id"])]
	return best


func test_reputation_has_nine_axes_that_move_independently() -> void:
	var h := _hub()
	var rep: RefCounted = h.mod("reputation")
	assert_int(PD.AXES.size()).is_equal(9)
	rep.record("i:ann", "generosity", 20.0, 0, "none")
	rep.record("i:ann", "cruelty", 30.0, 0, "none")
	var v: Dictionary = rep.view("i:ann", "t:0")
	assert_float(float(v["generosity"])).is_equal(20.0)
	assert_float(float(v["cruelty"])).is_equal(30.0)
	for ax: String in ["competence", "reliability", "legitimacy", "wealth", "strength", "influence", "trust"]:
		assert_float(float(v[ax])).is_equal(0.0)
	rep.on_deed("i:ann", "treaty_broken", 0)
	assert_float(rep.axis_of("i:ann", "reliability", "t:0")).is_less(-5.0)
	assert_float(rep.axis_of("i:ann", "generosity", "t:0")).is_equal(20.0)
	# every scope works as a subject and as an observer
	for scope in ["i", "h", "t", "f", "r", "a", "k"]:
		var key: String = rep.key(scope, "x")
		rep.record(key, "strength", 5.0, 0, "none", {"groups": ["k:caldrenn"]})
		assert_float(rep.axis_of(key, "strength", "t:0")).is_equal(5.0)
	assert_str(rep.words("i:ann", 0)).contains("feared as cruel")
	assert_str(rep.words("i:nobody", 0)).contains("nobody")


func test_news_travels_with_delay_and_hearsay_can_be_wrong() -> void:
	var h := _hub()
	var rep: RefCounted = h.mod("reputation")
	var a: int = int(WorldGen.settlements[0]["id"])
	var near: Array = []
	for t: Dictionary in WorldGen.settlements:
		if int(t["id"]) != a:
			near.append([(t["pos"] as Vector2).distance_to(WorldGen.settlements[0]["pos"]), int(t["id"])])
	near.sort()
	var b: int = int(near[2][1])                                           # the third nearest town: inside every channel's reach
	rep.record("i:fast", "strength", 20.0, a, "witness", {"channels": ["messenger"]})
	rep.record("i:slow", "strength", 20.0, a, "witness", {"channels": ["rumour"]})
	assert_bool(rep.knows("i:fast", "t:%d" % a)).is_true()                   # seen at once where it happened
	assert_bool(rep.knows("i:fast", "t:%d" % b)).is_false()                  # not yet anywhere else
	var first_fast := -1
	var first_slow := -1
	for d in range(1, 400):
		rep.tick_day(d, {})
		if first_fast < 0 and rep.knows("i:fast", "t:%d" % b):
			first_fast = d
		if first_slow < 0 and rep.knows("i:slow", "t:%d" % b):
			first_slow = d
	assert_int(first_fast).is_greater(0)
	assert_int(first_slow).is_greater(first_fast)                            # messengers beat rumours
	# many rumours: some arrive garbled
	var garbled := 0
	for i in 60:
		rep.record("i:r%d" % i, "generosity", 10.0, a, "witness", {"channels": ["rumour"]})
	rep.catch_up(400, {})
	for i in 60:
		for t: Dictionary in WorldGen.settlements:
			var v: Dictionary = rep.view("i:r%d" % i, "t:%d" % int(t["id"]))
			if not v.is_empty() and absf(float(v["generosity"]) - 10.0) > 0.5 and int(t["id"]) != a:
				garbled += 1
	assert_int(garbled).is_greater(0)
	assert_int(int(rep.stats["garbled"])).is_greater(0)
	assert_int(rep.pending()).is_equal(0)
	# the truth is untouched by the garbling (it only fades slowly with time)
	assert_float(float(rep.truth("i:r0")["generosity"])).is_between(6.0, 10.0)


# --- 4. marriage and inheritance ------------------------------------------------------------------------

func test_marriage_never_grants_a_throne() -> void:
	var h := _hub()
	var su: RefCounted = h.mod("succession")
	var crown := "crown:caldrenn"
	var king: String = su.holder(crown)
	assert_str(String(su.person(king)["name"])).contains("Aldric")
	var hs: Array = su.heirs(crown)
	var heir: String = hs[0]["pid"]
	assert_str(String(su.person(heir)["name"])).contains("Isolde")
	assert_int(int(su.person(heir)["age"])).is_equal(24)
	var me: String = su.new_person("The Wanderer", 27, "m", "wanderer", "", "", "player")
	var m: Dictionary = su.marry(me, heir)
	assert_bool(bool(m["ok"])).is_true()
	assert_bool(bool(m["throne"])).is_false()
	assert_str(String(su.holder(crown))).is_equal(king)
	for e: Dictionary in su.heirs(crown):
		assert_str(String(e["pid"])).is_not_equal(me)                         # a consort is never an heir
	var cl: Array = su.claims_of(me)
	assert_bool(cl.all(func(c: Dictionary) -> bool: return c["basis"] == "consort" and float(c["strength"]) == 0.0)).is_true()
	# the old king dies: the heir (your wife) rules, you are her consort and not the king
	var res: Dictionary = su.die(king)
	assert_str(String(res["titles"][0]["new"])).is_equal(heir)
	assert_str(String(su.holder(crown))).is_equal(heir)
	assert_str(String(su.holder(crown))).is_not_equal(me)
	# she dies childless: you still do not inherit
	su.die(heir)
	assert_str(String(su.holder(crown))).is_not_equal(me)
	# the stewardship crown office follows the throne (a new holder means a review of grants)
	var st: RefCounted = h.mod("stewardship")
	assert_str(String(st.office("%d:3" % PD.capital_sid())["holder"])).is_equal(String(su.holder(crown)))
	# your children carry both lines' claims
	var q: String = su.new_person("Queen", 25, "f", "wanderer")
	var me2: String = su.new_person("Prince", 30, "m", "wanderer")
	assert_bool(bool(su.marry(me2, q)["ok"])).is_true()
	var kid: String = su.beget(me2, q)
	assert_str(kid).is_not_empty()
	assert_bool(bool(su.marry(me2, heir)["ok"])).is_false()                    # already married / dead


func test_a_minor_heir_gets_a_regent_who_is_never_the_holder() -> void:
	var h := _hub()
	var su: RefCounted = h.mod("succession")
	var key := "house:harrow"
	var hp: String = su.holder(key)
	var sp: String = String(su.person(hp)["spouse"])
	for k: String in su.person(hp)["kids"]:
		su.die(k)
	var kid: String = su.new_person("Little Heir", 6, "m", "harrow", hp if String(su.person(hp)["sex"]) == "m" else sp, sp if String(su.person(hp)["sex"]) == "m" else hp)
	var res: Dictionary = su.die(hp)
	assert_str(String(res["titles"][0]["new"])).is_equal(kid)
	assert_str(su.regent_of(key)).is_equal(sp)
	assert_str(su.holder(key)).is_equal(kid)
	assert_str(su.regent_of(key)).is_not_equal(su.holder(key))
	for e: Dictionary in su.heirs(key):
		assert_str(String(e["pid"])).is_not_equal(sp)
	# ten years on the heir comes of age and the regency ends
	var kp: Dictionary = su._ppl[kid]
	kp["born"] = int(kp["born"]) - 10 * 360
	su.catch_up(30, {})
	assert_str(su.regent_of(key)).is_equal("")
	assert_str(su.holder(key)).is_equal(kid)


func test_local_rules_decide_the_heir_and_close_claims_open_a_dispute() -> void:
	var h := _hub()
	var su: RefCounted = h.mod("succession")
	var key := "crown:caldrenn"
	var kids: Array = []
	for e: Dictionary in su.heirs(key):
		kids.append(e["pid"])
	assert_int(kids.size()).is_greater_equal(2)
	var eldest: String = su.heirs(key)[0]["pid"]
	su._titles[key]["rule"] = "ultimogeniture"
	var youngest: String = su.heirs(key)[0]["pid"]
	assert_str(youngest).is_not_equal(eldest)
	su._titles[key]["rule"] = "designation"
	assert_bool(su.designate(key, youngest)).is_true()
	assert_str(String(su.heirs(key)[0]["pid"])).is_equal(youngest)
	su._titles[key]["rule"] = "primogeniture"
	assert_str(String(su.heirs(key)[0]["pid"])).is_equal(eldest)
	# local rule by place
	var sid := _sid("castle")
	assert_str(su.rule_of("lord:%d" % sid)).is_equal(String(PD.SUCCESSION_RULE["caldrenn"]))
	assert_bool(su.set_local_rule(sid, "elective")).is_true()
	assert_str(su.rule_of("lord:%d" % sid)).is_equal("elective")
	assert_bool(su.set_local_rule(sid, "nonsense")).is_false()
	# a conqueror's claim close behind the eldest opens a dispute and an interregnum
	var rival: String = su.new_person("Pretender", 40, "m", "pretender")
	assert_bool(su.add_claim(key, rival, "conquest", 0.95)).is_true()
	var res: Dictionary = su.die(su.holder(key))
	var disp: String = String(res["titles"][0]["dispute"])
	assert_str(disp).is_not_empty()
	assert_str(su.holder(key)).is_equal("")
	assert_int(su.disputes().size()).is_equal(1)
	assert_int((su.support(disp) as Dictionary).size()).is_equal(2)
	var winner: String = su.resolve_dispute(disp, "council")
	assert_str(winner).is_not_empty()
	assert_str(su.holder(key)).is_equal(winner)
	assert_int(su.disputes().size()).is_equal(0)
	assert_str(String(su.title(key)["dispute"])).is_equal("")


# --- 5. running a territory -----------------------------------------------------------------------------

func test_neglect_loses_office_and_diligence_keeps_it() -> void:
	var h := _hub()
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var key: String = st.office_key(sid, 0)
	assert_bool(st.assume(key, "player", "You", true)).is_true()
	assert_int((st.obligations(key) as Array).size()).is_equal(5)
	# a diligent steward performs every duty and keeps the seat
	for d in range(1, 120):
		st.tick_day(d, {})
		if d % 7 == 0:
			for duty: String in st.DUTIES:
				st.perform(key, duty)
			st.tick_week(d / 7, {})
	assert_str(String(st.office(key)["holder"])).is_equal("player")
	assert_float(st.neglect(key)).is_less(2.0)
	# the same steward, idle, is dismissed and a real NPC is seated
	var h2 := _hub()
	var s2: RefCounted = h2.mod("stewardship")
	s2.assume(key, "player", "You", true)
	var gone := -1
	for d in range(1, 300):
		s2.tick_day(d, {})
		if d % 7 == 0:
			s2.tick_week(d / 7, {})
		if String(s2.office(key)["holder"]) != "player":
			gone = d
			break
	assert_int(gone).is_greater(0)
	assert_int(int(s2.stats["dismissed"])).is_equal(1)
	assert_str(String(s2.office(key)["holder"])).is_not_equal("player")
	assert_float(float(h2.mod("reputation").truth("i:player")["competence"])).is_less(0.0)   # the neglect is charged to the person
	# unheard petitions at the office count as neglect too
	assert_int(s2.log_lines().size()).is_greater(0)


# --- 6. territory layers ---------------------------------------------------------------------------------

func test_ten_layers_and_visible_growth() -> void:
	var h := _hub()
	var tr: RefCounted = h.mod("territory")
	var sid := _sid("castle")
	var pos: Vector2 = PD.settlement(sid)["pos"]
	var ls: Dictionary = tr.layers_at(pos)
	assert_int(ls.size()).is_equal(10)
	for l: String in tr.LAYERS:
		assert_bool(ls.has(l)).is_true()
	assert_str(String(ls["sovereignty"])).is_equal("caldrenn")
	assert_float(float(ls["patrol"])).is_greater(0.0)
	assert_str(String(tr.at("sovereignty", Vector2(90000.0, 90000.0)))).is_equal("")
	# a growing settlement widens its claim; the map shows the stage
	var spot := pos + Vector2(1800.0, 0.0)
	var c1: int = tr.grow("player", spot, 10)
	var g1: Dictionary = tr.visible_growth("player")
	var c2: int = tr.grow("player", spot, 220)
	var g2: Dictionary = tr.visible_growth("player")
	assert_int(c2).is_greater(c1)
	assert_int(int(g2["cells"])).is_greater(int(g1["cells"]))
	assert_int(int(g2["stage_n"])).is_greater_equal(int(g1["stage_n"]))
	assert_str(String(tr.at("claims", spot))).contains("player")
	assert_array(tr.map_layer("claims", Rect2(spot - Vector2(900, 900), Vector2(1800, 1800)))).is_not_empty()
	# the save stays within 9 KB even when the cap is hit
	for i in 500:
		tr.set_layer("claims", Vector2(float(i) * 300.0, float(i % 7) * 300.0), "player|caldrenn")
	assert_int(JSON.stringify(tr.serialize()).length()).is_less(9000)
	assert_int(tr._ov.size()).is_less_equal(tr.CELL_CAP)


func test_capturing_a_castle_does_not_make_the_captor_the_lawful_lord() -> void:
	var h := _hub()
	var tr: RefCounted = h.mod("territory")
	var ld: RefCounted = h.mod("land")
	var sid := _sid("castle")
	var pos: Vector2 = PD.settlement(sid)["pos"]
	var holder_before: String = tr.lawful_holder(sid)
	var deed_before: String = String(ld.deed(sid).get("holder", ""))
	var res: Dictionary = tr.capture(sid, "warlord")
	assert_bool(bool(res["ok"])).is_true()
	assert_bool(bool(res["lawful"])).is_false()
	assert_str(String(tr.at("occupation", pos))).is_equal("warlord")
	assert_str(String(tr.at("sovereignty", pos))).is_equal("caldrenn")          # the kingdom is unchanged
	assert_str(tr.lawful_holder(sid)).is_equal(holder_before)
	assert_str(String(ld.deed(sid).get("holder", ""))).is_equal(deed_before)    # the deed is untouched (land.gd)
	assert_str(String(ld.deed(sid).get("occupier", ""))).is_equal("warlord")
	assert_bool(tr.is_lawful_lord(sid, "warlord")).is_false()
	assert_bool(bool(tr.confirm_sid(sid, "warlord", "dc999")["ok"])).is_false()      # no such charter
	assert_bool(bool(tr.confirm_sid(sid, "stranger", "treaty:ag1")["ok"])).is_false()
	var loyalty0: float = ld.loyalty(sid)
	for w in 6:
		tr.tick_week(w, {})
	assert_float(ld.loyalty(sid)).is_less(loyalty0)                              # the unlawful occupier breeds unrest
	assert_bool(tr.occupation_days(sid) >= 0).is_true()
	# a valid grant from the right office makes it lawful
	var aud: RefCounted = h.mod("audiences")
	var gv: RefCounted = h.mod("governance")
	gv.leader_of_settlement(sid)
	gv.set_law(sid, "land_ownership", 0, "test")
	var who := _who("warlord", 90.0, 4)
	aud.sponsor("warlord", "k", "King's man", 3)
	who["sponsors"] = aud.sponsors_of("warlord")
	var pid := _strong(h, "land", sid, who)
	_hear(h, pid)
	aud.negotiate(pid, {"accept": true})
	var d: Dictionary = aud.issue(pid)
	var ok: Dictionary = tr.confirm_sid(sid, "warlord", String(d["id"]))
	assert_bool(bool(ok["ok"])).override_failure_message(String(ok.get("reason", ""))).is_true()
	assert_bool(tr.is_lawful_lord(sid, "warlord")).is_true()
	assert_str(String(tr.at("ownership", pos))).is_equal("warlord")
	assert_str(String(tr.at("occupation", pos))).is_equal("")


# --- 7. diplomacy ----------------------------------------------------------------------------------------

func test_pacts_have_terms_duration_enforcement_and_memory() -> void:
	var h := _hub()
	var dp: RefCounted = h.mod("diplomacy")
	var fc: RefCounted = h.mod("factions")
	fc.change_relation("caldrenn", "player", "trust", 50.0)
	fc.change_relation("caldrenn", "player", "grievance", -50.0)
	var made := {}
	for t: String in dp.TYPES:
		var r: Dictionary = dp.propose("player", "caldrenn", t, {"amount": 5, "payer": "player", "lord": "caldrenn", "dowry": 20})
		assert_bool(bool(r["accepted"])).override_failure_message("%s: %s" % [t, r]).is_true()
		made[t] = String(r["id"])
	assert_int(dp.agreements("player").size()).is_equal(7)
	var al: Dictionary = dp.agreement(made["alliance"])
	assert_int(int(al["end"]) - int(al["start"])).is_equal(dp.TYPES["alliance"]["dur"])
	assert_int(int(dp.agreement(made["vassalage"])["end"])).is_equal(-1)
	assert_bool(bool(dp.propose("player", "caldrenn", "trade")["ok"])).is_false()          # one of each at a time
	assert_bool(bool(dp.allowed("player", "caldrenn", "attack")["allowed"])).is_false()
	assert_bool(bool(dp.allowed("player", "caldrenn", "trade")["allowed"])).is_true()
	# a weak party cannot take a weaker lord
	assert_bool(bool(dp.propose("caldrenn", "player", "vassalage")["accepted"])).is_false()
	# breach: the pact breaks, trust falls, reliability falls, and the next proposal is weighed against it
	var before_trust: float = fc.relation("caldrenn", "player")["trust"]
	var br: Dictionary = dp.report_act("player", "caldrenn", "attack", 0)
	assert_bool(bool(br["breach"])).is_true()
	assert_str(String(dp.agreement(String(br["agreement"]))["state"])).is_equal("broken")
	assert_float(fc.relation("caldrenn", "player")["trust"]).is_less(before_trust)
	assert_int(dp.breaches_by("player")).is_equal(1)
	h.mod("reputation").tick_day(2, {})
	assert_float(h.mod("reputation").axis_of("f:player", "reliability", "k:caldrenn")).is_less(0.0)
	var h2 := _hub()
	var d2: RefCounted = h2.mod("diplomacy")
	h2.mod("factions").change_relation("caldrenn", "player", "trust", 50.0)
	h2.mod("factions").change_relation("caldrenn", "player", "grievance", -50.0)
	var clean: Dictionary = d2.propose("player", "caldrenn", "trade")
	d2.propose("player", "caldrenn", "non_aggression")
	d2.report_act("player", "caldrenn", "attack")
	h2.mod("factions").change_relation("caldrenn", "player", "trust", 100.0)
	var dirty: Dictionary = d2.propose("player", "caldrenn", "passage")
	var dirty_trade: Dictionary = d2.propose("player", "veylwood", "trade")
	assert_float(float(dirty["score"])).is_less(float(clean["score"]) + 100.0 - 0.1)
	assert_bool(float(dirty["score"]) < 100.0).is_true()
	assert_bool(dirty_trade.has("score")).is_true()
	# tribute accrues; a player three weeks in arrears is in default and it counts as a breach
	var t: Dictionary = dp.propose("player", "veylwood", "tribute", {"amount": 8, "payer": "player"})
	if bool(t["accepted"]):
		for w in 3:
			dp.tick_week(w, {})
		assert_str(String(dp.agreement(String(t["id"]))["state"])).is_equal("broken")
	# pacts end on time
	dp.catch_up(800, {})
	assert_int(dp.agreements("player", "active").filter(func(a: Dictionary) -> bool: return a["type"] in ["alliance", "trade", "passage"]).size()).is_equal(0)


func test_kingdoms_react_to_independent_factions_by_visibility_and_conduct() -> void:
	var h := _hub()
	var dp: RefCounted = h.mod("diplomacy")
	var fc: RefCounted = h.mod("factions")
	assert_str(dp.react_for(0.05, 0.9)).is_equal("ignore")
	assert_str(dp.react_for(0.20, 0.10)).is_equal("tax")
	assert_str(dp.react_for(0.40, 0.60)).is_equal("recognize")
	assert_str(dp.react_for(0.40, -0.50)).is_equal("suppress")
	assert_str(dp.react_for(0.85, 0.20)).is_equal("suppress")
	assert_str(dp.react_for(0.85, 0.60)).is_equal("recognize")
	# a growing faction walks up the table as its visibility rises
	var rising := ""
	for fa: Dictionary in fc.factions():
		if String(fa["kind"]) == "house":
			rising = String(fa["id"])
			break
	var seen: Array = []
	for step in [[0.05, 0.5], [0.2, 0.4], [0.5, 0.6], [0.9, 0.1]]:
		dp.set_profile(rising, float(step[0]), float(step[1]))
		var a: Dictionary = dp.react("caldrenn", rising)
		seen.append(String(a["reaction"]))
	assert_array(seen).is_equal(["ignore", "tax", "recognize", "suppress"])
	assert_str(dp.reaction("caldrenn", rising)).is_equal("suppress")
	# each reaction has its effect
	var tax_ag: Array = dp.agreements(rising, "").filter(func(a: Dictionary) -> bool: return a["type"] == "tribute")
	assert_int(tax_ag.size()).is_equal(1)
	assert_str(String(tax_ag[0]["state"])).is_equal("demanded")
	var offer: Array = dp.agreements(rising, "").filter(func(a: Dictionary) -> bool: return a["type"] == "vassalage")
	assert_str(String(offer[0]["state"])).is_equal("offered")
	assert_bool(dp.answer(String(offer[0]["id"]), true)).is_true()
	assert_str(String(dp.agreement(String(offer[0]["id"]))["state"])).is_equal("active")
	assert_float(fc.relation("caldrenn", rising)["grievance"]).is_greater(0.0)
	# far kingdoms see less of the same faction
	dp.set_profile("distant", 0.2, 0.4)
	assert_str(String(dp.assess("caldrenn", "distant")["reaction"])).is_equal("tax")
	assert_str(String(dp.assess("seirune_isles", "distant")["reaction"])).is_equal("ignore")
	# conduct: a broken pact lowers it
	fc.change_relation("caldrenn", "player", "trust", 60.0)
	dp.propose("player", "caldrenn", "non_aggression")
	var c0: float = dp.conduct_of("player", "caldrenn")
	dp.report_act("player", "caldrenn", "attack")
	assert_float(dp.conduct_of("player", "caldrenn")).is_less(c0)
	# independent sects are judged by the same table every week
	dp.tick_week(1, {})
	assert_int(int(dp.stats["reactions"])).is_greater(4)


# --- 8. justice ------------------------------------------------------------------------------------------

func test_thirteen_kingdoms_have_their_own_laws() -> void:
	var ks := PD.kingdoms()
	assert_int(ks.size()).is_equal(13)
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var pens := {}
	for k: String in ks:
		var lw: Dictionary = ct.laws(k)
		assert_int(lw.size()).is_equal(Soc.CRIMES.size())
		for c: String in lw:
			assert_bool(ct.LADDER.has(String(lw[c]["penalty"]))).is_true()
		for c2: String in lw:
			pens[String(lw[c2]["penalty"])] = true
		assert_str(PD.kingdom_name(k)).is_not_empty()
		assert_str(String(PD.SUCCESSION_RULE[k])).is_not_empty()
	assert_bool(pens.size() >= 3).override_failure_message(str(pens)).is_true()          # the same crimes are punished differently across realms
	assert_str(String(ct.law("solkar_dominion", "murder")["penalty"])).is_not_equal(String(ct.law("veylwood", "murder")["penalty"]))
	assert_str(String(ct.law("veylwood", "robbery")["penalty"])).is_not_equal(String(ct.law("solkar_dominion", "robbery")["penalty"]))
	assert_int(int(ct.law("solkar_dominion", "robbery")["fine"])).is_greater(int(ct.law("veylwood", "robbery")["fine"]))


func _strong_case(h: RefCounted, sid: int, ev_s := 0.9, accused_id := "thief1", rank := 0) -> String:
	var ct: RefCounted = h.mod("courts")
	h.mod("courts").set_profile("caldrenn", "corrupt", 0.0)
	return ct.file_case("robbery", sid, {"id": "n1", "name": "Mara the baker"}, {"id": accused_id, "name": "Rook", "rank": rank},
		{"evidence": [{"type": "stolen_goods", "s": ev_s, "day": 0}, {"type": "footprints", "s": ev_s * 0.8, "day": 0}], "witnesses": [{"id": "n1", "name": "Mara", "saw": true, "conf": 0.9}]})


func test_a_case_runs_from_investigation_to_verdict_and_sentence() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid("village")
	var cid := _strong_case(h, sid)
	assert_str(String(ct.case_of(cid)["state"])).is_equal("open")
	assert_str(String(ct.case_of(cid)["officer"]["name"])).is_not_empty()
	var days := 0
	for d in range(1, 40):
		ct.tick_day(d, {})
		days = d
		if String(ct.case_of(cid)["state"]) in ["tried", "closed"]:
			break
	var c: Dictionary = ct.case_of(cid)
	assert_str(String(c["state"])).is_equal("tried")
	assert_str(String(c["verdict"])).is_equal("guilty")
	assert_str(String(c["sentence"]["penalty"])).is_equal(String(ct.law("caldrenn", "robbery")["penalty"]))
	assert_int(ct.jailed_until("thief1")).is_greater(0)
	assert_int(ct.fines_due("thief1")).is_greater(0)
	assert_int(ct.pay_fine("thief1", 9999)).is_greater(0)
	assert_int(ct.fines_due("thief1")).is_equal(0)
	assert_int(days).is_greater(2)                                          # investigation takes days
	# weak evidence and no witnesses: not convicted
	var weak: String = ct.file_case("robbery", sid, {"id": "n2", "name": "A"}, {"id": "thief2", "name": "Wren"}, {"evidence": [{"type": "footprints", "s": 0.15, "day": 0}]})
	for d in range(41, 90):
		ct.tick_day(d, {})
	assert_str(String(ct.case_of(weak)["verdict"])).is_not_equal("guilty")
	# an unknown culprit is found by the officers when the trail is good, or the case goes cold
	var cold: String = ct.file_case("burglary", sid, {"id": "n3", "name": "B"}, {}, {})
	for d in range(90, 170):
		ct.tick_day(d, {})
	assert_str(String(ct.case_of(cold)["state"])).is_equal("cold")
	var solved: String = ct.file_case("burglary", sid, {"id": "n3", "name": "B"}, {}, {"culprit": "thief3", "evidence": [{"type": "stolen_goods", "s": 0.9, "day": 170}],
		"witnesses": [{"id": "n9", "name": "W", "saw": true, "conf": 0.9}]})
	for d in range(170, 215):
		ct.tick_day(d, {})
	assert_str(String(ct.case_of(solved)["accused"]["id"])).is_equal("thief3")
	assert_str(String(ct.case_of(solved)["state"])).is_equal("tried")


func test_cases_can_be_built_from_society_crimes_and_evidence() -> void:
	var h := _hub()
	var soc: RefCounted = h.mod("society")
	var ct: RefCounted = h.mod("courts")
	soc._ensure_npcs()
	var sid := _sid("village")
	var ids: Array = soc.npcs_in(sid)
	var res: Dictionary = soc.commit_crime("robbery", sid, ids.slice(0, 3), {})
	assert_bool(bool(res["ok"])).is_true()
	var cid: String = ct.from_society(String(res["id"]))
	assert_str(cid).is_not_empty()
	var c: Dictionary = ct.case_of(cid)
	assert_str(String(c["crime"])).is_equal("robbery")
	assert_str(String(c["soc"])).is_equal(String(res["id"]))
	assert_int((c["evidence"] as Array).size()).is_equal((res["evidence"] as Array).size())
	assert_str(ct.from_society("c-none")).is_equal("")


func test_laws_per_kingdom_change_the_verdict_and_the_sentence() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid("village")
	var base := _strong_case(h, sid, 0.7, "t_a")
	ct.bring_to_court(base)
	assert_str(String(ct.trial(base)["verdict"])).is_equal("guilty")
	var pen0 := String(ct.case_of(base)["sentence"]["penalty"])
	# stricter proof: the same evidence no longer convicts
	ct.set_law("caldrenn", "robbery", "std", 0.95)
	var b2 := _strong_case(h, sid, 0.7, "t_b")
	ct.bring_to_court(b2)
	assert_str(String(ct.trial(b2)["verdict"])).is_not_equal("guilty")
	ct.set_law("caldrenn", "robbery", "std", 0.55)
	# more witnesses required
	ct.set_law("caldrenn", "robbery", "witnesses", 3)
	var b3 := _strong_case(h, sid, 0.5, "t_c")
	ct.bring_to_court(b3)
	assert_str(String(ct.trial(b3)["verdict"])).is_not_equal("guilty")
	ct.set_law("caldrenn", "robbery", "witnesses", 1)
	# a harsher penalty for the same crime
	ct.set_law("caldrenn", "robbery", "penalty", "execution")
	var b4 := _strong_case(h, sid, 0.7, "t_d")
	ct.bring_to_court(b4)
	assert_str(String(ct.trial(b4)["sentence"]["penalty"])).is_equal("execution")
	assert_str(pen0).is_not_equal("execution")
	assert_int(int(ct.stats["executed"])).is_equal(1)
	# the profile moves the ladder for every crime at once
	ct.set_profile("caldrenn", "harsh", 0.95)
	assert_str(String(ct.law("caldrenn", "assault")["penalty"])).is_not_equal("fine")


func test_appeals_climb_courts_and_the_crown_court_is_gated() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var sid := _sid("village")
	var cid := _strong_case(h, sid, 0.4, "t_e")
	ct.bring_to_court(cid)
	assert_str(String(ct.trial(cid)["verdict"])).is_equal("guilty")
	var by := {"id": "t_e", "name": "Rook", "kind": "npc", "fame": 3.0, "rank": 0, "sponsors": []}
	var ap: Dictionary = ct.appeal(cid, by, {"flaw": true})
	assert_bool(bool(ap["ok"])).is_true()
	assert_bool(bool(ap["overturned"])).is_true()                           # a flawed first trial is undone
	assert_int(int(ct.case_of(cid)["level"])).is_equal(2)
	assert_int(int(ct.stats["overturned"])).is_equal(1)
	assert_int(ct.fines_due("t_e")).is_equal(0)
	# a conviction that stands cannot climb to the crown unless the chamberlain would admit you
	var c2 := _strong_case(h, sid, 1.0, "t_f")
	ct.bring_to_court(c2)
	ct.trial(c2)
	assert_bool(bool(ct.appeal(c2, by)["ok"])).is_true()
	if String(ct.case_of(c2)["verdict"]) == "guilty":
		var gate: Dictionary = ct.appeal(c2, by)
		assert_bool(bool(gate["ok"])).is_false()
		assert_str(String(gate["reason"])).contains("chamberlain")
	# the realm's own limit
	var c3 := _strong_case(h, sid, 1.0, "t_g")
	ct.set_profile("caldrenn", "appeal", 1)
	ct.bring_to_court(c3)
	ct.trial(c3)
	assert_bool(bool(ct.appeal(c3, by)["ok"])).is_false()


func test_a_corrupt_bench_takes_bribes_and_an_honest_one_does_not() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var st: RefCounted = h.mod("stewardship")
	var sid := _sid("village")
	var cid := _strong_case(h, sid, 0.9, "t_h")
	ct.set_profile("caldrenn", "corrupt", 0.95)
	st.office(st.office_key(sid, 1))["honest"] = 0.0
	var taken := false
	for g in range(100, 140):
		if bool(ct.bribe(cid, "accused", g)["taken"]):
			taken = true
			break
	assert_bool(taken).is_true()
	ct.bring_to_court(cid)
	assert_str(String(ct.trial(cid)["verdict"])).is_not_equal("guilty")
	assert_int(int(ct.stats["corrupt"])).is_greater(0)
	# the same crime before an honest judge: the bribe is refused and the briber marked
	var h2 := _hub()
	var c2: RefCounted = h2.mod("courts")
	var s2: RefCounted = h2.mod("stewardship")
	var cid2 := _strong_case(h2, sid, 0.9, "t_i")
	c2.set_profile("caldrenn", "corrupt", 0.0)
	s2.office(s2.office_key(sid, 1))["honest"] = 1.0
	h2.mod("founding").force_corruption(sid, 0.0)
	var r: Dictionary = c2.bribe(cid2, "accused", 200)
	assert_bool(bool(r["taken"])).is_false()
	c2.bring_to_court(cid2)
	assert_str(String(c2.trial(cid2)["verdict"])).is_equal("guilty")


func test_bonded_people_are_easier_to_convict_cannot_appeal_and_can_be_freed() -> void:
	var h := _hub()
	var ct: RefCounted = h.mod("courts")
	var soc: RefCounted = h.mod("society")
	soc._ensure_npcs()
	var low := ""
	for id: String in soc.npcs:
		if int(soc.npcs[id]["class"]) == 0:
			low = id
			break
	assert_str(low).is_not_empty()
	assert_float(ct.bonded_share("hollowdeep")).is_greater(ct.bonded_share("veylwood"))
	ct.set_bond_share("caldrenn", 0.5)
	assert_str(ct.status_of(low, "caldrenn")).is_equal("bonded")
	var sid := _sid("village")
	var cid := _strong_case(h, sid, 0.7, low)
	ct.bring_to_court(cid)
	assert_str(String(ct.trial(cid)["verdict"])).is_equal("guilty")
	var ap: Dictionary = ct.appeal(cid, {"id": low, "name": "x", "kind": "npc", "fame": 1.0, "rank": 0, "sponsors": []}, {"flaw": true})
	assert_bool(bool(ap["ok"])).is_false()
	assert_str(String(ap["reason"])).contains("bonded")
	# liberation by decree, purchase or revolt lowers the share
	var s1: float = ct.liberate("caldrenn", "player", "decree", 0.3)
	assert_float(s1).is_less(0.5)
	var s2: float = ct.liberate("caldrenn", "player", "revolt", 0.3)
	assert_float(s2).is_equal(0.0)
	assert_str(ct.status_of(low, "caldrenn")).is_equal("free")
	var cid2 := _strong_case(h, sid, 0.7, low)
	ct.bring_to_court(cid2)
	ct.trial(cid2)
	assert_bool(bool(ct.appeal(cid2, {"id": low, "name": "x", "kind": "npc", "fame": 1.0, "rank": 0, "sponsors": []}, {"flaw": true})["ok"])).is_true()


func test_amnesty_pardons_a_sentence() -> void:
	var h := _hub()
	var aud: RefCounted = h.mod("audiences")
	var ct: RefCounted = h.mod("courts")
	var sid := _sid("village")
	var cid := _strong_case(h, sid, 0.9, "t_j")
	ct.bring_to_court(cid)
	ct.trial(cid)
	assert_int(ct.fines_due("t_j")).is_greater(0)
	var who := _who("t_j", 60.0, 3, "npc")
	aud.sponsor("t_j", "lordx", "Lord X", 3)
	who["sponsors"] = aud.sponsors_of("t_j")
	var pid := _strong(h, "amnesty", sid, who)
	_hear(h, pid)
	aud.negotiate(pid, {"accept": true})
	aud.issue(pid)
	assert_int(ct.fines_due("t_j")).is_equal(0)
	assert_int(ct.jailed_until("t_j")).is_equal(-1)


# --- performance, parity, save -------------------------------------------------------------------------------

func _busy(h: RefCounted) -> void:
	var aud: RefCounted = h.mod("audiences")
	var sid := _sid("village")
	for i in 3:
		var who := _who("busy%d" % i, 90.0, 4)
		aud.sponsor(String(who["id"]), "lordy", "Lord Y", 3)
		who["sponsors"] = aud.sponsors_of(String(who["id"]))
		var pid := _strong(h, ["tax_relief", "trade_rights", "dispute"][i], sid, who)
		_hear(h, pid, 1 + i)
		aud.negotiate(pid, {"accept": true})
		aud.issue(pid)
	var cid := _strong_case(h, sid, 0.9, "busy_t")
	h.mod("courts").bring_to_court(cid)
	h.mod("courts").trial(cid)
	h.mod("courts").appeal(cid, {"id": "busy_t", "name": "x", "kind": "npc", "fame": 2.0, "rank": 0, "sponsors": []}, {"flaw": true})
	h.mod("diplomacy").propose("player", "caldrenn", "passage")
	h.mod("diplomacy").report_act("player", "caldrenn", "raid")
	h.mod("diplomacy").set_profile("rising", 0.5, 0.6)
	h.mod("diplomacy").react("caldrenn", "rising")
	h.mod("territory").capture(_sid("castle"), "warlord", 3)
	h.mod("territory").grow("player", Vector2(2000, 2000), 90)
	h.mod("reputation").record("i:player", "generosity", 12.0, sid, "witness", {"groups": ["k:caldrenn"]})
	h.mod("succession").die(h.mod("succession").holder("crown:caldrenn"))
	h.mod("stewardship").assume(h.mod("stewardship").office_key(sid, 0), "player", "You", true)
	_pass(h, 5, 60)


func test_save_round_trip() -> void:
	var h := _hub()
	_busy(h)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(h.serialize()))
	var h2 := _hub()
	h2.deserialize(saved)
	for k: String in MODS:
		assert_str(_norm(h2.mod(k).serialize())).override_failure_message(k).is_equal(_norm(h.mod(k).serialize()))
	# and the behaviour continues identically
	_pass(h, 61, 75)
	_pass(h2, 61, 75)
	for k: String in MODS:
		var sa := _norm(h2.mod(k).serialize())
		var sb := _norm(h.mod(k).serialize())
		var at := 0
		while at < mini(sa.length(), sb.length()) and sa[at] == sb[at]:
			at += 1
		assert_str(sa).override_failure_message("after play: %s differs at %d: ...%s | ...%s" % [k, at, sa.substr(maxi(0, at - 60), 140), sb.substr(maxi(0, at - 60), 140)]).is_equal(sb)
	assert_str(String(h2.mod("audiences").documents()[0]["state"])).is_not_empty()


func test_save_size_is_small() -> void:
	var h := _hub()
	_busy(h)
	var total := 0
	for k: String in MODS:
		var n := JSON.stringify(h.mod(k).serialize()).length()
		total += n
		prints("stage 6 save", k, n)
	assert_int(total).is_less(120000)
	assert_int(JSON.stringify(h.mod("territory").serialize()).length()).is_less(9000)


func test_tick_cost_stays_inside_the_realm_budget() -> void:
	var h := _hub()
	_busy(h)
	var aud: RefCounted = h.mod("audiences")
	# fill the queues: 100 petitions, 100 cases, a rumour storm
	var sid := _sid("village")
	var n := 0
	for i in 140:
		var who := _who("load%d" % i, 90.0, 4)
		var fr: Dictionary = aud.file(["tax_relief", "trade_rights", "dispute"][i % 3], sid, who)
		if bool(fr["ok"]):
			aud.present(String(fr["pid"]), _ev(["witness", "survey"]))
			n += 1
	assert_int(n).is_greater(60)
	for i in 100:
		h.mod("courts").file_case("assault", sid, {"id": "c%d" % i, "name": "c"}, {"id": "a%d" % i, "name": "a"}, {"evidence": [{"type": "blood", "s": 0.6, "day": 0}]})
	for i in 120:
		h.mod("reputation").record("i:m%d" % (i % 30), PD.AXES[i % 9], 6.0, sid, "witness", {"groups": ["k:caldrenn"]})
	var worst := {}
	for d in range(100, 140):
		for k: String in MODS:
			var chunks: Array = h.mod(k).tick_day_chunks(d, {})
			if chunks.is_empty():
				chunks = [func() -> Array: return h.mod(k).tick_day(d, {})]
			if d % 7 == 0:
				chunks.append(func() -> Array: return h.mod(k).tick_week(d / 7, {}))
			for cb: Callable in chunks:                                         # the hub runs each chunk as its own pump job
				var t0 := Time.get_ticks_usec()
				cb.call()
				worst[k] = maxi(int(worst.get(k, 0)), Time.get_ticks_usec() - t0)
	var total := 0
	for k: String in worst:
		total += int(worst[k])
		prints("stage 6 tick (us, worst)", k, worst[k])
		assert_int(int(worst[k])).override_failure_message("%s took %d us" % [k, int(worst[k])]).is_less(1500)
	assert_int(total).is_less(6000)
	assert_int(aud.petitions().size()).is_less_equal(aud.PET_MAX)
	assert_int(h.mod("courts").cases().size()).is_less_equal(h.mod("courts").CASE_MAX)
	assert_int(h.mod("reputation").pending()).is_less_equal(h.mod("reputation").PENDING_MAX)
