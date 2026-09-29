extends GdUnitTestSuite
## The 8 x 8 km world: the original valley is untouched, the new land is filled (settlements,
## roads, forts, bridges, rifts, camps, a second river) and danger climbs with distance from
## Kingsreach. Also guards the spatial index (exact answers) and the population budget.


func before() -> void:
	WorldGen.setup(1066)


func _capital() -> Vector2:
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			return s["pos"]
	return Vector2.ZERO


func test_world_is_8_km_wide() -> void:
	assert_float(WorldGen.WORLD_HALF).is_equal(4096.0)


func test_new_land_has_about_twenty_settlements_with_unique_names() -> void:
	var n := WorldGen.settlements.size()
	assert_int(n).is_between(18, 24)
	assert_int(WorldGen.core_settlement_count).is_equal(12)
	var names := {}
	var outer := 0
	var outer_town := false
	var outer_frontier := false
	var hamlets := 0
	for s in WorldGen.settlements:
		assert_bool(names.has(s["name"])).override_failure_message("duplicate name %s" % s["name"]).is_false()
		names[s["name"]] = true
		if int(s["id"]) >= WorldGen.core_settlement_count:
			outer += 1
			var p: Vector2 = s["pos"]
			assert_float(maxf(absf(p.x), absf(p.y))).is_less(WorldGen.WORLD_HALF - 400.0)
			outer_town = outer_town or s["kind"] == "town"
			outer_frontier = outer_frontier or s["kind"] == "frontier_town"
			hamlets += 1 if bool(s.get("hamlet", false)) else 0
	assert_int(outer).is_greater_equal(6)
	assert_bool(outer_town).is_true()
	assert_bool(outer_frontier).is_true()
	assert_int(hamlets).is_greater_equal(1)


func test_valley_keeps_ashford_kingsreach_and_their_roads() -> void:
	assert_vector(WorldGen.settlements[0]["pos"]).is_equal(Vector2.ZERO)
	assert_vector(WorldGen.settlements[1]["pos"]).is_equal(Vector2(560, -420))
	# The new land hangs off the valley's other towns, never off Ashford or the capital,
	# so their gates (and the gate market) are exactly as before.
	for r in WorldGen.roads:
		if maxi(r.x, r.y) >= WorldGen.core_settlement_count:
			assert_bool(mini(r.x, r.y) >= 2 or maxi(r.x, r.y) < WorldGen.core_settlement_count).is_true()
	assert_int(WorldGen.gate_angles(WorldGen.settlements[0]).size()).is_equal(2)
	assert_int(WorldGen.gate_angles(WorldGen.settlements[1]).size()).is_equal(3)


func test_population_stays_within_the_mobile_budget() -> void:
	var total := 0
	for s in WorldGen.settlements:
		total += int(s["population"])
	assert_int(total).is_less_equal(25000)
	assert_int(WorldSim.population()).is_less_equal(25000)


func test_new_land_sites_are_filled_and_inside_the_world() -> void:
	var kinds := {}
	for s in WorldGen.sites:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
		var p: Vector2 = s["pos"]
		assert_bool(absf(p.x) < WorldGen.WORLD_HALF and absf(p.y) < WorldGen.WORLD_HALF).override_failure_message("%s outside" % s["name"]).is_true()
	assert_int(int(kinds.get("fort", 0))).is_greater_equal(4)
	assert_int(int(kinds.get("watchfort", 0))).is_greater_equal(4)
	assert_int(int(kinds.get("bridge", 0))).is_greater_equal(2)
	assert_int(int(kinds.get("rift", 0))).is_equal(2)
	assert_int(int(kinds.get("rift_outpost", 0))).is_equal(2)
	assert_int(int(kinds.get("mine", 0))).is_greater_equal(2)
	assert_int(int(kinds.get("bandit_camp", 0))).is_greater_equal(3)
	assert_int(int(kinds.get("tower_ruin", 0))).is_greater_equal(3)
	assert_int(int(kinds.get("waystation", 0))).is_greater_equal(2)
	# The academy stays the very last site (nothing else's id moved).
	assert_str(String(WorldGen.sites[WorldGen.sites.size() - 1]["kind"])).is_equal("academy")


func test_bandit_camps_and_rifts_thicken_with_distance() -> void:
	var cap := _capital()
	var far_camps := 0
	for s in WorldGen.sites:
		if s["kind"] == "bandit_camp" and (s["pos"] as Vector2).distance_to(cap) > 1600.0:
			far_camps += 1
	assert_int(far_camps).is_greater_equal(3)
	var scar := Vector2.ZERO
	var rift := Vector2.ZERO
	for s in WorldGen.sites:
		if s["kind"] == "rift":
			if s["name"] == "The Ashen Scar":
				scar = s["pos"]
			else:
				rift = s["pos"]
	assert_float(scar.distance_to(cap)).is_greater(rift.distance_to(cap) + 1000.0)


func test_lore_camps_get_more_dangerous_the_further_from_kingsreach() -> void:
	var lore := Life.lore
	var cap := _capital()
	var tiered: Array = []
	for pl: Dictionary in lore.places_in_region():
		if String(pl.get("kind", "")) in ["goblin_warren", "orc_village"] and pl.has("danger_tier"):
			tiered.append(pl)
	assert_int(tiered.size()).is_greater_equal(3)
	tiered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).distance_to(cap) < (b["pos"] as Vector2).distance_to(cap))
	var last := 0
	for pl: Dictionary in tiered:
		assert_int(int(pl["danger_tier"])).override_failure_message("%s tier drops" % pl["name"]).is_greater_equal(last)
		last = int(pl["danger_tier"])
	assert_int(last).is_equal(3)
	# Every camp ground is dry ground away from settlements and roads.
	assert_int(WorldGen.camp_grounds.size()).is_greater_equal(6)
	for g in WorldGen.camp_grounds:
		var p: Vector2 = g["pos"]
		assert_bool(WorldGen.is_water(p.x, p.y)).is_false()
		if p.distance_to(cap) > 1500.0:      # the new land's camps (the valley's two are lore-fixed)
			assert_float(WorldGen.road_distance(p.x, p.y)).is_greater(float(g["radius"]))
			assert_float(WorldGen.nearest_settlement(p)["pos"].distance_to(p)).is_greater(250.0)


func test_far_dens_are_deadlier_than_near_ones() -> void:
	var cap := _capital()
	var far_wolves := 0
	var corrupted := 0
	for d: Dictionary in Frontier.ecology.dens:
		var dist: float = (d["pos"] as Vector2).distance_to(cap)
		if d["species"] == "corrupted_wolf" and not bool(d.get("apex", false)) and dist > 3000.0:
			corrupted += 1
		elif d["species"] == "wolf" and dist > 1400.0:
			far_wolves += 1
	assert_int(far_wolves).is_greater_equal(8)
	assert_int(corrupted).is_greater_equal(3)


func test_second_river_runs_through_the_east_and_needs_bridges() -> void:
	assert_int(WorldGen.rivers.size()).is_equal(3)
	var pts: PackedVector2Array = WorldGen.rivers[2]["points"]
	var mid := pts[pts.size() / 2]
	assert_float(mid.x).is_greater(1500.0)
	# Every road that crosses the Silverrun gets a bridge (or a shallow ford).
	var bridges := 0
	for s in WorldGen.sites:
		if s["kind"] == "bridge" and (s["pos"] as Vector2).x > 1500.0:
			bridges += 1
	assert_int(bridges).is_greater_equal(1)


func test_spatial_index_answers_exactly_like_a_full_scan() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 400:
		var p := Vector2(rng.randf_range(-4300, 4300), rng.randf_range(-4300, 4300))
		if i % 3 == 0:
			p = (WorldGen.settlements[rng.randi() % WorldGen.settlements.size()]["pos"] as Vector2) + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		var best := INF
		for r in WorldGen.roads:
			var a: Vector2 = WorldGen.settlements[r.x]["pos"]
			var b: Vector2 = WorldGen.settlements[r.y]["pos"]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
		assert_float(WorldGen.road_distance(p.x, p.y)).is_equal_approx(best, 0.001)
		assert_float(float(WorldGen.road_info(p.x, p.y)["dist"])).is_equal_approx(best, 0.001)
		var near := INF
		var near_id := -1
		for s in WorldGen.settlements:
			var d := p.distance_squared_to(s["pos"])
			if d < near:
				near = d
				near_id = int(s["id"])
		assert_int(int(WorldGen.nearest_settlement(p)["id"])).is_equal(near_id)


func test_streaming_radius_does_not_depend_on_world_size() -> void:
	# Terrain and water stream a fixed ring of 64 m chunks around the player, whatever the map size.
	var t := TerrainStreamer.new()
	assert_int(t.view_radius).is_equal(4)
	assert_int(t.collision_radius).is_equal(1)
	assert_int(t.grass_radius).is_equal(1)
	assert_float(TerrainStreamer.CHUNK).is_equal(64.0)
	t.free()
