extends GdUnitTestSuite
## AR-6/7/8/11: dread/awe, recognition, economy, escalation ladder + options, culture, legends, hub registration, save.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Fallout := preload("res://scripts/realm/aura_fallout.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100, "life": null}
const ME := "i:player"

var hub: RefCounted
var fo: RefCounted
var sid := 0


func before_test() -> void:
	WorldGen.setup(2024)
	hub = Hub.new()
	fo = hub.mod("aura_fallout")
	hub.mod("districts")._ensure()
	WorldSim.day = 10


func _days(n: int) -> void:
	for i in n:
		WorldSim.day += 1
		fo.tick_day(WorldSim.day, CTX)


func test_registered_in_hub() -> void:
	assert_object(fo).is_not_null()
	assert_bool(Hub.ORDER.has("aura_fallout")).is_true()
	assert_bool(fo.has_method("take_pending_gold")).is_true()


func test_deeds_set_dread_and_awe_and_travel_by_reputation() -> void:
	var rep: RefCounted = hub.mod("reputation")
	var c0 := float(rep.truth(ME).get("cruelty", 0.0)) if not rep.truth(ME).is_empty() else 0.0
	fo.on_deed(ME, "siege_broken", sid)
	assert_float(fo.dread(ME, sid)).is_greater(30.0)
	assert_float(fo.awe(ME, sid)).is_greater(5.0)
	assert_float(float(rep.truth(ME)["cruelty"])).is_greater(c0)          # mirrored onto the frozen reputation axes
	fo.on_deed(ME, "monster_defeated", sid)
	assert_float(fo.awe(ME, sid)).is_greater(30.0)
	assert_float(fo.on_deed(ME, "no_such_deed", sid)).is_equal(0.0)


func test_documented_half_lives() -> void:
	fo.add(ME, sid, 80.0, 80.0)
	WorldSim.day += 90
	assert_float(fo.dread(ME, sid)).is_equal_approx(40.0, 1.0)            # 90 days
	assert_float(fo.awe(ME, sid)).is_greater(fo.dread(ME, sid))           # awe fades slower (150)
	assert_float(fo.awe(ME, sid)).is_equal_approx(80.0 * 0.8 * pow(0.5, 90.0 / 150.0), 1.0)   # valencios awe_mult 0.8
	# a legend slows dread decay to 240 days
	var other := "i:legend"
	fo.add(other, sid, 80.0, 0.0)
	fo._make_legend(other, "siege_broken", sid)
	WorldSim.day += 90
	assert_float(fo.dread(other, sid)).is_greater(fo.dread(ME, sid))


func test_recognition_obeys_disguise_and_axis() -> void:
	fo.add(ME, sid, 80.0, 0.0)
	var obs := {"id": "n1", "perception": 0.2, "face_seen": true}
	var open: float = fo.recognise(obs, {"id": ME, "gear_signature": 0.5}, sid)
	assert_float(open).is_greater(0.6)
	var hooded: float = fo.recognise({"id": "n1", "perception": 0.0}, {"id": ME, "gear_signature": 0.0, "disguise": {"quality": 1.0, "identity": {"id": "i:x"}}}, sid)
	assert_float(hooded).is_less(0.1)
	var unknown: float = fo.recognise({"id": "n1", "face_seen": true}, {"id": "i:nobody"}, sid)
	assert_float(unknown).is_less(0.25)                                   # face alone is not fame


func test_cascade_and_world_hook() -> void:
	assert_int(fo.cascade_level(ME, sid)).is_equal(0)
	fo.add(ME, sid, 55.0, 0.0)
	var st: Dictionary = fo.fear_state(sid)
	assert_bool(bool(st["shutters"])).is_true()
	assert_bool(bool(st["market_empty"])).is_false()
	fo.add(ME, sid, 20.0, 0.0)
	assert_bool(bool(fo.fear_state(sid)["market_empty"])).is_true()
	fo.add(ME, sid, 20.0, 0.0)
	assert_bool(bool(fo.fear_state(sid)["curfew"])).is_true()
	# awe 20 above dread flips the cascade: people come out
	var kind := "i:kind"
	fo.add(kind, sid, 20.0, 60.0)
	assert_bool(bool(fo.fear_state(sid, kind)["people_out"])).is_true()


func test_price_bounded_and_vendor_fallback() -> void:
	assert_float(fo.price_mult(sid)).is_equal(1.0)
	fo.add(ME, sid, 100.0, 0.0)
	assert_float(fo.price_mult(sid)).is_less_equal(1.4001)
	assert_float(fo.price_mult(sid)).is_greater(1.2)
	assert_bool(fo.vendor_refuses(sid, {})).is_true()
	assert_bool(fo.vendor_refuses(sid, {"devotee": true})).is_false()
	assert_bool(fo.vendor_refuses(sid, {"fence": true})).is_false()
	assert_bool(fo.fallback_shop(sid)).is_true()


func test_spread_cap_to_neighbours() -> void:
	fo.add(ME, 1, 100.0, 0.0)
	assert_float(fo.dread_felt(ME, 2)).is_less_equal(30.0)                # one town adds at most 30
	fo.add(ME, 1, 0.0, 0.0, {"kingdom_scale": true})
	assert_float(fo.dread_felt(ME, 2)).is_greater(30.0)                   # unless the deed was kingdom-scale
	assert_float(fo.dread(ME, 2)).is_equal(0.0)


func test_bill_paid_once_cuts_dread() -> void:
	fo.add(ME, sid, 40.0, 0.0)
	assert_int(fo.bill(ME, sid, 120)).is_equal(120)
	var r: Dictionary = fo.pay_bill(ME, sid)
	assert_bool(bool(r["ok"])).is_true()
	assert_float(fo.dread(ME, sid)).is_equal_approx(25.0, 0.5)            # a paid bill cuts dread by 15
	assert_bool(bool(fo.pay_bill(ME, sid)["ok"])).is_false()
	assert_int(fo.take_pending_gold()).is_equal(-120)
	assert_int(fo.take_pending_gold()).is_equal(0)


func test_severity_monotonic_and_steps_only_under_triggers() -> void:
	var last := -1.0
	for peak in [0.0, 0.2, 0.5, 0.8, 1.0]:
		var s := Fallout.severity(peak, 2, 0.0)
		assert_float(s).is_greater_equal(last)
		last = s
	assert_float(Fallout.severity(0.5, 4, 0.0)).is_greater(Fallout.severity(0.5, 0, 0.0))
	assert_int(Fallout.step_for({}, 0.0)).is_equal(-1)
	assert_int(Fallout.step_for({"t1": 1}, 0.0)).is_equal(0)
	assert_int(Fallout.step_for({"t2": 3}, 0.0)).is_equal(1)
	assert_int(Fallout.step_for({"t3": 1}, 0.0)).is_equal(1)
	assert_int(Fallout.step_for({"t2": 1, "sustained_s": 12.0}, 0.0)).is_equal(2)
	assert_int(Fallout.step_for({"t4": 1}, 0.0)).is_equal(2)
	assert_int(Fallout.step_for({"t2": 1}, 55.0)).is_equal(2)
	assert_int(Fallout.step_for({"t3": 1, "damage": true}, 0.0)).is_equal(3)
	assert_int(Fallout.step_for({"t3": 1}, 72.0)).is_equal(4)
	assert_int(Fallout.step_for({"t3": 1, "death": true}, 0.0)).is_equal(4)
	assert_int(Fallout.step_for({"t3": 1, "demonic_church": true}, 0.0)).is_equal(4)
	assert_int(Fallout.step_for({"t3": 1}, 90.0)).is_equal(5)
	assert_int(Fallout.step_for({"t3": 1, "noble_killed": true}, 0.0)).is_equal(5)
	assert_int(Fallout.step_for({"t3": 1}, 10.0, 2)).is_equal(5)          # repeated step 4


func test_incident_builds_ladder_with_timers_and_effects() -> void:
	var dm: RefCounted = hub.mod("districts")
	var q := "merchant" if dm.has_quarter(sid, "merchant") else String(dm.quarters_of(sid)[0])
	var safe0: float = dm.values(sid, q)["safety"]
	var step: int = fo.on_incident(ME, sid, q, 0.6, 0.0, 6, {"t2": 4, "t3": 1, "duration_s": 5.0, "no_case": true})
	assert_int(step).is_equal(1)
	var l: Dictionary = fo.ladder(ME, sid)
	assert_str(String(l["id"])).is_equal("patrol")
	assert_bool(bool(l["arrived"])).is_false()
	var eta0 := float(l["eta_s"])
	assert_float(eta0).is_between(20.0, 45.0)                            # documented arrival window
	fo.advance(ME, sid, 50.0)
	assert_bool(bool(fo.ladder(ME, sid)["arrived"])).is_true()
	assert_float(dm.values(sid, q)["safety"]).is_less(safe0)
	assert_float(fo.dread(ME, sid)).is_greater(0.0)
	# the same incident again is deterministic
	var fo2: RefCounted = Hub.new().mod("aura_fallout")
	fo2.on_incident(ME, sid, q, 0.6, 0.0, 6, {"t2": 4, "t3": 1, "duration_s": 5.0, "no_case": true})
	assert_float(float(fo2.ladder(ME, sid)["eta_s"])).is_equal(eta0)


func test_court_case_and_news_at_officer_parley() -> void:
	var cm: RefCounted = hub.mod("courts")
	var before: int = cm.cases().size()
	var step: int = fo.on_incident(ME, sid, "other", 0.8, 0.0, 8, {"t3": 2, "t4": 1, "duration_s": 12.0})
	assert_int(step).is_greater_equal(2)
	assert_int(cm.cases().size()).is_equal(before + 1)
	assert_str(String(cm.case_of(String((cm.cases()[-1] as Dictionary)["id"]))["crime"])).is_equal("public_terror")


func test_options_resolve_deterministically() -> void:
	fo.on_incident(ME, sid, "", 0.7, 0.0, 6, {"t2": 3, "t3": 2, "duration_s": 12.0, "no_case": true})
	assert_int(int(fo.ladder(ME, sid)["step"])).is_equal(2)
	# suppress: step 2 -> 1
	var r: Dictionary = fo.resolve(ME, sid, "suppress", {})
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(r["after"])).is_equal(1)
	# unknown option / no ladder
	assert_bool(bool(fo.resolve(ME, sid, "dance", {})["ok"])).is_false()
	assert_bool(bool(fo.resolve("i:nobody", sid, "talk", {})["ok"])).is_false()


func _ladder_at(f: RefCounted, step: int, subject := ME) -> void:
	f._set_step(subject, sid, step, "test")


func test_option_talk_bribe_intimidate_surrender_flee_fight() -> void:
	# talk: a persuasive, respected player is dismissed; a hated one escalates
	fo.add(ME, sid, 0.0, 70.0)
	_ladder_at(fo, 2)
	var t: Dictionary = fo.resolve(ME, sid, "talk", {"persuasion": 0.9, "rank": 4})
	assert_str(String(t["outcome"])).is_equal("dismissed")
	assert_int(int(t["after"])).is_equal(0)
	var bad := "i:bad"
	fo.add(bad, sid, 60.0, 0.0)
	_ladder_at(fo, 2, bad)
	var tb: Dictionary = fo.resolve(bad, sid, "talk", {"persuasion": 0.0, "rank": 0})
	assert_int(int(tb["after"])).is_greater_equal(2)
	# intimidate works once at low step with enough power, fails without
	var a := "i:a"
	_ladder_at(fo, 2, a)
	assert_int(int(fo.resolve(a, sid, "intimidate", {"power": 0.7})["after"])).is_equal(1)
	var b := "i:b"
	_ladder_at(fo, 2, b)
	assert_int(int(fo.resolve(b, sid, "intimidate", {"power": 0.1})["after"])).is_equal(3)
	# bribe: honest officer refuses (and it is recorded), corrupt one takes it and costs gold, scaling with dread
	var c := "i:c"
	_ladder_at(fo, 2, c)
	var refused: Dictionary = fo.resolve(c, sid, "bribe", {"honest": 0.95})
	assert_str(String(refused["outcome"])).is_equal("refused_and_recorded")
	assert_int(int(refused["after"])).is_equal(3)
	var d := "i:d"
	_ladder_at(fo, 2, d)
	var cheap: Dictionary = fo.resolve(d, sid, "bribe", {"honest": 0.1})
	assert_str(String(cheap["outcome"])).is_equal("taken")
	assert_int(int(cheap["gold"])).is_less(0)
	var e := "i:e"
	fo.add(e, sid, 60.0, 0.0)
	_ladder_at(fo, 2, e)
	var dear: Dictionary = fo.resolve(e, sid, "bribe", {"honest": 0.1})
	assert_int(int(dear["gold"])).is_less(int(cheap["gold"]))             # costs more with dread
	# surrender yields a hearing and ends the ladder
	var g := "i:g"
	_ladder_at(fo, 3, g)
	var sur: Dictionary = fo.resolve(g, sid, "surrender", {})
	assert_str(String(sur["outcome"])).is_equal("hearing")
	assert_int(int(sur["after"])).is_equal(0)
	var cm: RefCounted = hub.mod("courts")
	assert_int(cm.cases().size()).is_greater(0)
	# a lethal fight jumps straight to step 4
	var h := "i:h"
	_ladder_at(fo, 1, h)
	var lethal: Dictionary = fo.resolve(h, sid, "fight_lethal", {})
	assert_int(int(lethal["after"])).is_equal(4)
	assert_float(fo.dread(h, sid)).is_greater_equal(29.0)
	# non-lethal fight keeps reputation clean (small dread) but raises step to 3
	var n := "i:n"
	_ladder_at(fo, 2, n)
	assert_int(int(fo.resolve(n, sid, "fight", {})["after"])).is_equal(3)
	assert_float(fo.dread(n, sid)).is_less(10.0)
	# appeal needs awe and costs a favour
	var p := "i:p"
	fo.add(p, sid, 0.0, 60.0)
	_ladder_at(fo, 3, p)
	assert_int(int(fo.resolve(p, sid, "appeal", {})["after"])).is_equal(2)
	assert_int(fo.favours(p, sid)).is_equal(1)
	# flee: deterministic for a given ladder
	var fl := "i:fl"
	_ladder_at(fo, 2, fl)
	var f1: Dictionary = fo.resolve(fl, sid, "flee", {"power": 0.8})
	var fo2: RefCounted = Hub.new().mod("aura_fallout")
	fo2._set_step(fl, sid, 2, "test")
	var f2: Dictionary = fo2.resolve(fl, sid, "flee", {"power": 0.8})
	assert_str(String(f1["outcome"])).is_equal(String(f2["outcome"]))


func test_step_five_sends_a_royal_response() -> void:
	var wi: RefCounted = hub.mod("war_intel")
	var before: int = wi.envoys("waiting").size()
	fo.add(ME, sid, 90.0, 0.0)
	var step: int = fo.on_incident(ME, sid, "", 0.9, 0.0, 10, {"t3": 3, "t4": 2, "no_case": true})
	assert_int(step).is_equal(5)
	assert_int(String(fo.ladder(ME, sid)["id"]).length()).is_greater(0)
	assert_str(String(fo.ladder(ME, sid)["id"])).is_equal("royal_response")
	assert_int(wi.envoys("waiting").size()).is_greater(before)            # an envoy with terms
	assert_float(float(fo.ladder(ME, sid)["eta_s"])).is_greater(3000.0)   # hours to days


func test_culture_difference_in_fallout() -> void:
	# Valencios: a visible release is a crime waiting; monster town: a greeting
	var step_v: int = fo.on_incident(ME, sid, "", 0.7, 0.0, 6, {"t2": 3, "t3": 1, "no_case": true, "kingdom": "caldrenn"})
	assert_int(step_v).is_greater_equal(1)
	var mon := "i:mon"
	var step_m: int = fo.on_incident(mon, sid, "", 0.7, 0.0, 6, {"t2": 3, "t3": 1, "kingdom": "monster_town"})
	assert_int(step_m).is_equal(-1)
	assert_float(fo.dread(mon, sid)).is_equal(0.0)
	assert_float(fo.awe(mon, sid)).is_greater(0.0)
	# church kingdom: more dread from the same deed, and a demonic read reaches the inquisitors at once
	var a := "i:ca"
	var b := "i:cb"
	fo.on_deed(a, "street_slaughter", sid, 1.0, {"kingdom": "caldrenn"})
	fo.on_deed(b, "street_slaughter", sid, 1.0, {"kingdom": "solmarch"})
	assert_float(fo.dread(b, sid)).is_greater(fo.dread(a, sid))
	var c := "i:cc"
	var s_church: int = fo.on_incident(c, sid, "", 0.6, 0.0, 5, {"t3": 2, "demonic": true, "kingdom": "solmarch", "no_case": true})
	var d := "i:cd"
	var s_sec: int = fo.on_incident(d, sid, "", 0.6, 0.0, 5, {"t3": 2, "demonic": true, "kingdom": "caldrenn", "no_case": true})
	assert_int(s_church).is_equal(4)
	assert_int(s_sec).is_less(4)
	# bribery is harder in the church kingdom data
	assert_float(float(Fallout.culture_row("solmarch")["bribe_base"])).is_less(float(Fallout.culture_row("caldrenn")["bribe_base"]))


func test_legends_threshold_dedupe_cap() -> void:
	fo.on_deed(ME, "riot_ended", sid)
	assert_int(fo.legends(ME).size()).is_equal(0)
	fo.on_deed(ME, "riot_ended", sid)
	fo.on_deed(ME, "riot_ended", sid)
	assert_int(fo.legends(ME).size()).is_equal(1)
	fo.on_deed(ME, "riot_ended", sid)
	assert_int(fo.legends(ME).size()).is_equal(1)                         # deduped
	fo.on_deed(ME, "siege_broken", sid)                                   # a siege alone is a story
	assert_int(fo.legends(ME).size()).is_equal(2)
	for i in 30:
		fo._make_legend("i:x%d" % i, "siege_broken", sid)
	assert_int(fo.legends().size()).is_equal(20)


func test_daily_tick_shocks_districts_and_decays() -> void:
	var dm: RefCounted = hub.mod("districts")
	var q := String(dm.quarters_of(sid)[0])
	var p0: float = dm.values(sid, q)["prosperity"]
	var t0: float = dm.values(sid, q)["tension"]
	fo.add(ME, sid, 90.0, 0.0)
	_days(1)
	for c in fo.tick_day_chunks(WorldSim.day, CTX):
		c.call()
	assert_float(dm.values(sid, q)["prosperity"]).is_less(p0)
	assert_float(dm.values(sid, q)["tension"]).is_greater(t0)
	_days(400)
	assert_float(fo.dread(ME, sid)).is_less(5.0)                          # recoverable
	assert_float(dm.values(sid, q)["prosperity"]).is_greater(0.0)


func test_chunked_matches_direct_and_catch_up_is_cheap() -> void:
	var a: RefCounted = Hub.new().mod("aura_fallout")
	var b: RefCounted = Hub.new().mod("aura_fallout")
	for f in [a, b]:
		f.add(ME, 1, 50.0, 20.0)
	a.tick_day(WorldSim.day + 1, CTX)
	for c in b.tick_day_chunks(WorldSim.day + 1, CTX):
		c.call()
	assert_dict(a.serialize()).is_equal(b.serialize())
	var t0 := Time.get_ticks_usec()
	a.catch_up(500, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(50000)


func test_save_round_trip_and_size() -> void:
	fo.add(ME, 1, 61.0, 20.0, {"kingdom_scale": true})
	fo.on_incident(ME, 1, "", 0.7, 0.0, 6, {"t2": 3, "t3": 1, "damage_gold": 80, "no_case": true})
	fo.on_deed(ME, "siege_broken", 2)
	fo.on_deed(ME, "riot_ended", 2)
	fo.on_deed(ME, "riot_ended", 2)
	fo.on_deed(ME, "riot_ended", 2)
	fo.pay_bill(ME, 1)
	var d: Dictionary = JSON.parse_string(JSON.stringify(fo.serialize()))
	assert_int(JSON.stringify(d).length()).is_less(6000)                  # under 6 KB
	var fo2: RefCounted = Hub.new().mod("aura_fallout")
	fo2.deserialize(d)
	assert_float(fo2.dread(ME, 1)).is_equal_approx(fo.dread(ME, 1), 0.1)
	assert_float(fo2.awe(ME, 2)).is_equal_approx(fo.awe(ME, 2), 0.1)
	assert_int(int(fo2.ladder(ME, 1)["step"])).is_equal(int(fo.ladder(ME, 1)["step"]))
	assert_int(fo2.legends(ME).size()).is_equal(fo.legends(ME).size())
	assert_int(fo2.bill_due(ME, 1)).is_equal(fo.bill_due(ME, 1))
	assert_int(fo2.take_pending_gold()).is_equal(fo.take_pending_gold())
	assert_float(fo2.dread_felt(ME, 3)).is_equal_approx(fo.dread_felt(ME, 3), 0.1)
	# whole-hub round trip keeps the module
	var h2: RefCounted = Hub.new()
	h2.deserialize(JSON.parse_string(JSON.stringify(hub.serialize())))
	assert_float(h2.mod("aura_fallout").dread(ME, 1)).is_equal_approx(fo.dread(ME, 1), 0.1)


func test_no_mind_control_in_fallout() -> void:
	# nothing in the fallout API writes follower will, minds or bonds
	var src := FileAccess.get_file_as_string("res://scripts/realm/aura_fallout.gd")
	for banned in ["mod(\"will\")", "mod(\"minds\")", "mod(\"bonds\")", "mod(\"psyche\")"]:
		assert_bool(src.contains(banned)).is_false()
