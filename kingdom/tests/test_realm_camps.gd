extends GdUnitTestSuite
## Camps on chosen terrain, placed structures with station links, roads.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _camps() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new().mod("camps")


func _good_site(c: RefCounted) -> Vector2:
	var best := Vector2.ZERO
	var bs := -1.0
	for x in range(-1200, 1200, 150):
		for z in range(-1200, 1200, 150):
			var s: float = c.score_site(Vector2(x, z))
			if s > bs:
				bs = s
				best = Vector2(x, z)
	return best


func test_site_score_prefers_good_terrain_and_is_deterministic() -> void:
	var c := _camps()
	var site := _good_site(c)
	assert_float(c.score_site(site)).is_greater(0.3)
	assert_float(c.score_site(site)).is_equal(c.score_site(site))
	assert_float(c.score_site(WorldGen.lake_center)).is_equal(0.0)


func test_found_camp_and_structures_produce() -> void:
	var c := _camps()
	var site := _good_site(c)
	var id: int = c.found_camp(site, "Wolfden", 3)
	assert_int(id).is_greater(0)
	assert_int(c.found_camp(site + Vector2(10, 0), "Too close", 3)).is_equal(-1)
	assert_int(c.camps().size()).is_equal(1)
	var st: Dictionary = c.place_structure(id, "well", site)
	assert_str(st["role"]).is_equal("water")
	var bk: Dictionary = c.place_structure(id, "bakery", site, "s0")
	assert_str(bk["link"]).is_equal("s0")
	for h in 30:
		c.tick_hour(h, CTX)
	assert_bool(c.has_role(id, "water")).is_true()
	var w0: int = c.stock_of(id, "water")
	c.tick_day(4, CTX)
	assert_int(c.stock_of(id, "water")).is_greater(w0)


func test_road_decay_maintenance_and_travel_time() -> void:
	var c := _camps()
	var e: Dictionary = c.edges()[0]
	var a: String = e["a"]
	var b: String = e["b"]
	var f0: float = c.road_factor(a, b)
	var t0: float = c.travel_hours(a, b)
	var v0: float = c.trade_volume(a, b)
	var r0: float = c.raid_risk(a, b)
	for d in 120:
		c.tick_day(d, CTX)
	assert_float(c.road_factor(a, b)).is_greater(f0)
	assert_float(c.travel_hours(a, b)).is_greater(t0)
	assert_float(c.trade_volume(a, b)).is_less(v0)
	assert_float(c.raid_risk(a, b)).is_greater(r0)
	c.maintain_road(a, b, 3.0)
	assert_float(c.road_factor(a, b)).is_less(c.road_factor(a, b) + 0.001)
	assert_str(c.road_state(a, b)).is_equal("built")
	assert_float(c.road_factor("s0", "s0x")).is_equal(2.2)


func test_travel_hours_routes_through_graph() -> void:
	var c := _camps()
	var h: float = c.travel_hours(0, WorldGen.settlements.size() - 1)
	assert_float(h).is_greater(0.0)
	assert_float(c.travel_hours(0, 0)).is_equal(0.0)
	assert_int(c.route(0, WorldGen.settlements.size() - 1).size()).is_greater(1)


func test_camp_gets_a_trail_and_builds_road() -> void:
	var c := _camps()
	var site := _good_site(c)
	var id: int = c.found_camp(site, "X", 0)
	var node := "c%d" % id
	assert_float(c.travel_hours(node, "s0")).is_greater(0.0)
	assert_bool(c.build_road(node, 1, "stone")).is_true()
	assert_float(c.road_factor(node, 1)).is_less(1.0)


func test_save_round_trip() -> void:
	var c := _camps()
	var site := _good_site(c)
	var id: int = c.found_camp(site, "Rt", 0)
	c.place_structure(id, "farm_plot", site)
	for d in 5:
		c.tick_day(d, CTX)
	var json := JSON.stringify(c.serialize())
	var c2: RefCounted = Hub.new().mod("camps")
	c2.deserialize(JSON.parse_string(json))
	assert_str(_norm(c2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_float(c2.travel_hours(0, 1)).is_equal(c.travel_hours(0, 1))
	assert_int(c2.camps().size()).is_equal(1)


func test_perf_24_hourly_ticks() -> void:
	var c := _camps()
	var site := _good_site(c)
	var id: int = c.found_camp(site, "P", 0)
	for k in STRUCT_KINDS():
		c.place_structure(id, k, site)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		c.tick_hour(h, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)


func STRUCT_KINDS() -> Array:
	return ["tent", "well", "farm_plot", "bakery", "smithy", "watchtower"]
