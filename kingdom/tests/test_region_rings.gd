extends GdUnitTestSuite
## World rings (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "World structure (rings)"):
## capital -> suburbs/farmland -> villages -> kingdom roads -> frontier towns ->
## forts -> weak frontier roads -> wilderness -> the Rift frontier. With the
## fixed seed the region must have real towns and frontier holds, not just
## villages plus the capital.


func before() -> void:
	WorldGen.setup(1066)


func test_ashford_is_still_the_home_village_at_the_origin() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	assert_str(home["name"]).is_equal("Ashford")
	assert_str(home["kind"]).is_equal("village")
	assert_float((home["pos"] as Vector2).length()).is_equal_approx(0.0, 0.001)


func test_kingsreach_is_still_the_capital_at_its_lore_position() -> void:
	var found := false
	for s in WorldGen.settlements:
		if s["name"] == "Kingsreach":
			found = true
			assert_str(s["kind"]).is_equal("castle")
			assert_float((s["pos"] as Vector2).distance_to(Vector2(560, -420))).is_equal_approx(0.0, 0.001)
	assert_bool(found).is_true()


func test_at_least_two_towns_exist_between_the_capital_and_the_villages() -> void:
	var towns := 0
	for s in WorldGen.settlements:
		if s["kind"] == "town":
			towns += 1
	assert_int(towns).is_greater_equal(2)


func test_at_least_one_frontier_town_exists() -> void:
	var count := 0
	for s in WorldGen.settlements:
		if s["kind"] == "frontier_town":
			count += 1
			# Fortified like a town, not open like a village.
			assert_bool(bool(s["plan"]["walls"])).is_true()
	assert_int(count).is_greater_equal(1)


func test_valley_forts_and_new_land_bastions_and_rift_outposts() -> void:
	# The original valley keeps its two forts (Kingsroad and Farwatch, planned first, so ids 0..core stay put);
	# the 8 km world adds a bastion at the new town and at the far frontier hold, and a second Rift with its outpost.
	var forts := 0
	var rift_outposts := 0
	var names: Array[String] = []
	for s in WorldGen.sites:
		if s["kind"] == "fort":
			forts += 1
			names.append(String(s["name"]))
		elif s["kind"] == "rift_outpost":
			rift_outposts += 1
	# the 12 km world adds a bastion at each new town and frontier hold (as ground allows)
	var new_holds := 0
	for st in WorldGen.settlements:
		if int(st["id"]) >= WorldGen.core_settlement_count and st["kind"] in ["town", "frontier_town"]:
			new_holds += 1
	assert_int(forts).is_between(4, 2 + new_holds)
	assert_array(names).contains(["Kingsroad Bastion", "Farwatch Bastion"])
	assert_int(rift_outposts).is_equal(2)


func test_farms_ring_the_capital_and_every_village_town_and_frontier_town() -> void:
	for s in WorldGen.settlements:
		var pos: Vector2 = s["pos"]
		var want := 2 if s["kind"] == "castle" else (1 if s["kind"] in ["village", "town", "frontier_town"] else 0)
		if want == 0:
			continue
		var near := 0
		for site in WorldGen.sites:
			if site["kind"] == "farm" and (site["pos"] as Vector2).distance_to(pos) < float(s["radius"]) * 3.0:
				near += 1
		assert_int(near).override_failure_message("%s has %d nearby farms, want >= %d" % [s["name"], near, want]).is_greater_equal(want)


func test_every_settlement_is_reachable_by_road() -> void:
	assert_int(WorldGen.roads.size()).is_equal(WorldGen.settlements.size() - 1)
	var linked := {0: true}
	var changed := true
	while changed:
		changed = false
		for r in WorldGen.roads:
			if linked.has(r.x) and not linked.has(r.y):
				linked[r.y] = true
				changed = true
			elif linked.has(r.y) and not linked.has(r.x):
				linked[r.x] = true
				changed = true
	assert_int(linked.size()).is_equal(WorldGen.settlements.size())


func test_new_settlement_kinds_are_dry() -> void:
	for s in WorldGen.settlements:
		if s["kind"] in ["frontier_town", "town"]:
			var p: Vector2 = s["pos"]
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s wet at %s" % [s["name"], p]).is_false()


func test_forts_and_rift_outpost_are_dry_and_clear_of_trees() -> void:
	for s in WorldGen.sites:
		if s["kind"] in ["fort", "rift_outpost"]:
			var p: Vector2 = s["pos"]
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s wet at %s" % [s["name"], p]).is_false()
			assert_float(WorldGen.forest_density(p.x, p.y)).is_equal(0.0)
