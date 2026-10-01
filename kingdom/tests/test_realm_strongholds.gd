extends GdUnitTestSuite
## Realm strongholds: chokepoints from WorldGen, routes, raids, difficulty text.

const Strongholds := preload("res://scripts/realm/strongholds.gd")


func _mk() -> Strongholds:
	WorldGen.setup(2024)
	return Strongholds.new()


func test_strongholds_at_chokepoints_deterministic() -> void:
	var a := _mk()
	var b := _mk()
	assert_int(a.strongholds().size()).is_between(3, 64)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	for s: Dictionary in a.strongholds():
		assert_bool(s["owner"] != "").is_true()
		assert_bool(s["garrison"] > 0).is_true()


func test_controls_route() -> void:
	var m := _mk()
	var found := false
	for e: Vector2i in WorldGen.roads:
		var c := m.controls_route(e.x, e.y)
		if not c.is_empty():
			found = true
			assert_bool(m.controls_route(e.y, e.x) == c).is_true()
			assert_bool(c.has("owner") and c.has("toll")).is_true()
	assert_bool(found).is_true()
	assert_bool(m.controls_route(0, 0).is_empty()).is_true()


func test_raids_spawn_travel_and_strike() -> void:
	var m := _mk()
	var struck := false
	for d in 30:
		m.tick_day(d, {"player_pos": Vector2.ZERO})
		for h in 24:
			m.tick_hour(h, {})
		if not m.recent_raid_results().is_empty():
			struck = true
			break
	assert_bool(struck).is_true()
	var r: Dictionary = m.recent_raid_results()[0]
	assert_bool(r.has("loot") and r.has("target") and r.has("success")).is_true()


func test_raid_results_feed_land_memory() -> void:
	var m := _mk()
	var Land := GDScript.new()
	Land.source_code = "extends RefCounted\nvar calls := 0\nfunc remember(_p, _k, _w, _d):\n\tcalls += 1\n"
	Land.reload()
	var stub: RefCounted = Land.new()
	var hub := RefCounted.new()
	var hub_script := GDScript.new()
	hub_script.source_code = "extends RefCounted\nvar land\nfunc mod(_n):\n\treturn land\n"
	hub_script.reload()
	var h: RefCounted = hub_script.new()
	h.land = stub
	m.hub = h
	for d in 30:
		m.tick_day(d, {})
		for hr in 24:
			m.tick_hour(hr, {})
	assert_int(stub.calls).is_greater(0)


func test_recommended_preparation() -> void:
	var m := _mk()
	var p := m.recommended_preparation(0, {"season": "winter"})
	assert_bool(p["lines"].size() > 0).is_true()
	assert_bool("Cold weather" in p["text"]).is_true()
	assert_float(p["danger"]).is_between(0.0, 1.0)
	var far := m.recommended_preparation(Vector2(1500, 1500))
	assert_float(far["danger"]).is_greater_equal(0.0)


func test_round_trip_and_perf() -> void:
	var m := _mk()
	for d in 12:
		m.tick_day(d, {})
		m.tick_hour(d, {})
	var s := JSON.stringify(m.serialize())
	var b := Strongholds.new()
	b.deserialize(JSON.parse_string(s))
	assert_str(JSON.stringify(b.serialize())).is_equal(s)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		m.tick_hour(h, {})
	m.tick_day(99, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
	t0 = Time.get_ticks_usec()
	m.catch_up(60, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
