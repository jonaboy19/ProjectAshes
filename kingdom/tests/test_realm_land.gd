extends GdUnitTestSuite
## Deeds, conquest vs ownership, territory memory, rebellion, generations.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new().mod("land")


func test_deeds_seeded_and_legal_claim_vs_occupation() -> void:
	var l := _mk()
	assert_str(l.deed(1)["holder"]).is_not_empty()
	var old: String = l.deed(1)["holder"]
	assert_bool(l.in_conflict(1)).is_false()
	l.seize(1, "player", 5)
	assert_str(l.deed(1)["holder"]).is_equal(old)
	assert_str(l.deed(1)["occupier"]).is_equal("player")
	assert_bool(l.in_conflict(1)).is_true()
	assert_int(l.conflicts().size()).is_equal(1)
	l.legitimise(1, 6)
	assert_str(l.deed(1)["holder"]).is_equal("player")
	assert_bool(l.in_conflict(1)).is_false()
	assert_str(l.strongest_claim(1)["who"]).is_equal(old)


func test_purchase_grant_inheritance() -> void:
	var l := _mk()
	assert_bool(l.purchase(2, "player", 500, 1)).is_true()
	assert_str(l.deed(2)["acquired_by"]).is_equal("purchase")
	assert_bool(l.grant(3, "player", "nobody")).is_false()
	assert_bool(l.inherit(2, "heir_of_player", 9)).is_true()
	assert_str(l.deed(2)["holder"]).is_equal("heir_of_player")
	assert_int(l.deed(2)["history"].size()).is_equal(2)


func test_conquest_is_not_ownership_loyalty_and_rebellion() -> void:
	var l := _mk()
	l.conquer(1, "player", 0)
	l.remember(1, "massacre", 1.0, 0)
	assert_float(l.loyalty(1)).is_less(25.0)
	var msgs: Array = []
	for d in range(1, 60):
		msgs.append_array(l.tick_day(d, CTX))
	assert_int(l.rebellions().size()).is_greater(0)
	var rb: Dictionary = l.rebellions()[0]
	assert_str(rb["leader"]["name"]).is_not_empty()
	assert_bool(msgs.size() > 0).is_true()


func test_crush_and_appease() -> void:
	var l := _mk()
	l.conquer(1, "player", 0)
	l.remember(1, "massacre", 1.0, 0)
	for d in range(1, 30):
		l.tick_day(d, CTX)
	if l.rebellion_at(1).is_empty():
		l._rebels.append({"id": 99, "region": "1", "leader": l._new_leader("1", 1), "strength": 0.3, "start_day": 1, "status": "open", "against": "player"})
	assert_str(l.crush(1, 5.0)).contains("crushed")
	assert_bool(l.rebellion_at(1).is_empty()).is_true()


func test_memory_biases_loyalty_and_decays() -> void:
	var a := _mk()
	var b := _mk()
	a.remember(4, "fair_rule", 1.0, 0)
	b.remember(4, "massacre", 1.0, 0)
	for d in range(1, 30):
		a.tick_day(d, CTX)
		b.tick_day(d, CTX)
	assert_float(a.loyalty(4)).is_greater(b.loyalty(4) + 30.0)
	var w0: float = b.memories(4)[0]["weight"]
	for d in range(30, 200):
		b.tick_day(d, CTX)
	assert_float(b.memories(4)[0]["weight"]).is_less(w0)


func test_generations_pass_memory_at_reduced_weight() -> void:
	var l := _mk()
	l.remember(5, "massacre", 1.0, 0)
	l.catch_up(400, CTX)
	var m: Dictionary = l.memories(5)[0]
	assert_int(m["gen"]).is_equal(1)
	assert_float(m["weight"]).is_less(0.5)
	assert_bool(String(m["who"]).begins_with("descendants of")).is_true()


func test_catch_up_rebels_and_determinism() -> void:
	var a := _mk()
	var b := _mk()
	for l in [a, b]:
		l.conquer(1, "player", 0)
		l.remember(1, "massacre", 1.5, 0)
	var la: Array = a.catch_up(25, CTX)
	var lb: Array = b.catch_up(25, CTX)
	assert_array(la).is_equal(lb)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_save_round_trip() -> void:
	var l := _mk()
	l.conquer(1, "player", 0)
	l.remember(1, "massacre", 1.0, 0)
	for d in range(1, 40):
		l.tick_day(d, CTX)
	var json := JSON.stringify(l.serialize())
	var l2: RefCounted = Hub.new().mod("land")
	l2.deserialize(JSON.parse_string(json))
	assert_str(_norm(l2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_float(l2.loyalty(1)).is_equal_approx(l.loyalty(1), 0.001)
	assert_int(l2.rebellions().size()).is_equal(l.rebellions().size())


func test_perf_24_hourly_ticks() -> void:
	var l := _mk()
	l.deed(0)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		l.tick_hour(h, CTX)
	l.tick_day(1, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
