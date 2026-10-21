extends GdUnitTestSuite
## MW-10/11: district values move from causes, winners and losers, no stereotype crime, save/load, catch_up.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100, "life": null}


func _dv() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("districts")
	m._ensure()
	return m


func _town(m: RefCounted) -> int:
	for sid in WorldGen.settlements.size():
		if m.has_quarter(sid, "poor") and m.has_quarter(sid, "merchant"):
			return sid
	return 0


func _days(m: RefCounted, n: int) -> void:
	for d in n:
		m.tick_day(d + 1, CTX)


func test_causes_move_values() -> void:
	var m := _dv()
	var s := _town(m)
	var before: Dictionary = m.values(s, "merchant")
	m.invest(s, "merchant", 1000)
	for i in 3:
		m.on_business(s, "merchant", true)
	_days(m, 40)
	var after: Dictionary = m.values(s, "merchant")
	assert_float(after["prosperity"]).is_greater(before["prosperity"])
	assert_float(after["unemployment"]).is_less(before["unemployment"])
	var pb: Dictionary = m.values(s, "poor")
	for i in 4:
		m.on_crime(s, "poor", 1.0)
	m.on_payment(s, "poor", "rent", -400)
	_days(m, 20)
	var pa: Dictionary = m.values(s, "poor")
	assert_float(pa["safety"]).is_less(pb["safety"])
	var tb: float = pa["tension"]
	m.garrison(s, "poor", 1.0)
	_days(m, 40)
	assert_float(m.values(s, "poor")["safety"]).is_greater(pa["safety"])
	assert_float(m.guard_density(s, "poor")).is_greater(0.3)
	assert_float(tb).is_greater(pb["tension"] - 0.01)


func test_winners_and_losers() -> void:
	var m := _dv()
	var s := _town(m)
	var ctl := _dv()
	_days(ctl, 40)
	var p0: float = ctl.values(s, "other")["prosperity"]
	var u0: float = ctl.values(s, "other")["unemployment"]
	var fx: Array = m.act("workshop_opened", s, "other", "player", 1.0, ["npc:rival"])
	var groups := {}
	for e: Dictionary in fx:
		groups[e["group"]] = float(e["delta"])
	assert_float(groups["owner"]).is_greater(0.0)
	assert_float(groups["rival"]).is_less(0.0)
	assert_float(groups["residents"]).is_less(0.0)   # unemployment falls
	_days(m, 40)
	assert_float(m.values(s, "other")["prosperity"]).is_greater(p0)
	assert_float(m.values(s, "other")["unemployment"]).is_less(u0)
	assert_float(m.opposition("npc:rival", "player")).is_greater(0.1)
	assert_array(m.opponents_of("player")).contains(["npc:rival"])


func test_no_stereotype_crime() -> void:
	var m := _dv()
	var s := _town(m)
	# Same circumstances in a poor and a merchant quarter give the same opportunity: the quarter name is never read.
	var a: Array = m._v[m._key(s, "poor")]
	var b: Array = m._v[m._key(s, "merchant")]
	for i in a.size():
		b[i] = a[i]
	m._d[m._key(s, "merchant")] = (m._d[m._key(s, "poor")] as Array).duplicate()
	var who := {"need": 0.5, "greed": 0.4, "honesty": 0.5}
	assert_float(m.crime_opportunity(s, "poor", who)).is_equal_approx(m.crime_opportunity(s, "merchant", who), 0.0001)
	# Individuals differ: a desperate dishonest person versus a content honest one in the same street.
	var bad: float = m.crime_opportunity(s, "poor", {"need": 0.9, "greed": 0.8, "honesty": 0.1})
	var good: float = m.crime_opportunity(s, "poor", {"need": 0.1, "greed": 0.1, "honesty": 0.95})
	assert_float(bad).is_greater(good * 3.0)
	# Circumstances matter: a hungry, jobless, unguarded poor quarter versus a fed, employed, guarded one.
	var k: String = m._key(s, "poor")
	(m._v[k] as Array)[m.F_UNEMP] = 0.9
	(m._v[k] as Array)[m.F_FOOD] = 0.1
	var hard: float = m.crime_opportunity(s, "poor", who)
	(m._v[k] as Array)[m.F_UNEMP] = 0.05
	(m._v[k] as Array)[m.F_FOOD] = 0.95
	assert_float(m.crime_opportunity(s, "poor", who)).is_less(hard)


func test_feedback_reads() -> void:
	var m := _dv()
	var s := _town(m)
	assert_float(m.etiquette(s, "merchant")).is_between(0.0, 1.0)
	assert_float(m.mood(s, "merchant")).is_between(-1.0, 1.0)
	var hi: float = m.price_mult(s, "poor")
	(m._v[m._key(s, "poor")] as Array)[m.F_FOOD] = 0.05
	assert_float(m.price_mult(s, "poor")).is_greater(hi)


func test_save_load_roundtrip() -> void:
	var m := _dv()
	var s := _town(m)
	m.act("workshop_opened", s, "other", "player", 1.0, ["npc:rival"])
	m.on_crime(s, "poor", 2.0)
	_days(m, 10)
	var d: Dictionary = JSON.parse_string(JSON.stringify(m.serialize()))
	var m2 := _dv()
	m2.deserialize(d)
	for f: String in m.FIELDS:
		assert_float(m2.values(s, "poor")[f]).is_equal_approx(m.values(s, "poor")[f], 0.01)
	assert_float(m2.opposition("npc:rival", "player")).is_equal_approx(m.opposition("npc:rival", "player"), 0.001)
	assert_int(JSON.stringify(m.serialize()).length()).is_less(60000)


func test_catch_up_matches_daily() -> void:
	var a := _dv()
	var b := _dv()
	var s := _town(a)
	a.invest(s, "poor", 800)
	b.invest(s, "poor", 800)
	_days(a, 60)
	b.catch_up(60, CTX)
	for f: String in a.FIELDS:
		assert_float(b.values(s, "poor")[f]).is_equal_approx(a.values(s, "poor")[f], 0.05)


func test_deterministic_and_cheap() -> void:
	var a := _dv()
	var b := _dv()
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	var t := Time.get_ticks_usec()
	_days(a, 1)
	assert_int(Time.get_ticks_usec() - t).is_less(20000)
