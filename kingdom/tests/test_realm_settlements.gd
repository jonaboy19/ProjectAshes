extends GdUnitTestSuite
## Settlement identity drift, supply chains, emergencies and the absence digest.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new().mod("settlements")


func test_seeded_from_worldgen() -> void:
	var s := _mk()
	assert_int(s.settlement_ids().size()).is_equal(WorldGen.settlements.size())
	assert_float(s.supply_of(0, "bread")).is_greater(0.0)
	assert_dict(s.identity(0)).has_size(7)
	# The castle reads as a fortress, not just a big town.
	var castle := -1
	for st in WorldGen.settlements:
		if st["kind"] == "castle":
			castle = st["id"]
	assert_str(s.dominant(castle)).is_equal("fortress")


func test_identity_drifts_toward_what_is_built() -> void:
	var s := _mk()
	var before: float = s.identity(0)["religious"]
	s.add_structure(0, "temple", 4)
	s.add_residents(0, "priest", 30)
	for d in 60:
		s.tick_day(d, CTX)
	assert_float(s.identity(0)["religious"]).is_greater(before + 0.1)
	assert_str(s.dominant(0)).is_equal("religious")


func test_supply_chain_shortage_and_emergency_window() -> void:
	var s := _mk()
	for k in s.stock(0):
		s.stock(0)[k] = 0.0
	s.stock(0)["wood"] = 0.0
	s._s[0]["chains"] = {}
	var got_famine := false
	for d in 8:
		s.tick_day(d, CTX)
		for e in s.emergencies(0):
			if e["kind"] == "famine":
				got_famine = true
	assert_bool(got_famine).is_true()
	assert_int(s.shortages(0).get("food", 0)).is_greater(2)


func test_emergency_response_and_ignored_consequences() -> void:
	var s := _mk()
	s.raid_aftermath(1, 1.0)
	var e: Dictionary = s.emergencies(1)[0]
	var pop0: int = s.population(1)
	var msg: String = s.respond(e["id"], 10)
	assert_str(msg).contains("more gold")
	assert_str(s.respond(e["id"], 1000)).contains("saved")
	assert_int(s.emergencies(1).size()).is_equal(0)
	# Ignored: window passes and the town pays.
	s.raid_aftermath(1, 1.0)
	var lines: Array = []
	for h in 60:
		lines.append_array(s.tick_hour(h, CTX))
	assert_int(s.emergencies(1).size()).is_equal(0)
	assert_int(lines.size()).is_greater(0)
	assert_int(s.population(1)).is_less(pop0)


func test_catch_up_digest_and_determinism() -> void:
	var a := _mk()
	var b := _mk()
	var la: Array = a.catch_up(20, CTX)
	var lb: Array = b.catch_up(20, CTX)
	assert_array(la).is_equal(lb)
	assert_array(a.digest()).is_equal(la)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_tick_day_deterministic() -> void:
	var a := _mk()
	var b := _mk()
	for d in 40:
		a.tick_day(d, CTX)
		b.tick_day(d, CTX)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_save_round_trip() -> void:
	var s := _mk()
	s.raid_aftermath(2, 0.6)
	for d in 15:
		s.tick_day(d, CTX)
	var json := JSON.stringify(s.serialize())
	var s2: RefCounted = Hub.new().mod("settlements")
	s2.deserialize(JSON.parse_string(json))
	assert_str(_norm(s2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_float(s2.supply_of(0, "grain")).is_equal_approx(s.supply_of(0, "grain"), 0.001)
	assert_int(s2.emergencies().size()).is_equal(s.emergencies().size())


func test_perf_24_hourly_ticks() -> void:
	var s := _mk()
	for i in 6:
		s.raid_aftermath(i, 0.5)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		s.tick_hour(h, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
