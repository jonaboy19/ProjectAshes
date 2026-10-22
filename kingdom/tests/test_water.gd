extends GdUnitTestSuite
## Lake and rivers: placement keeps the village dry, the lake is deep, rivers connect.


func before() -> void:
	WorldGen.setup(1066)


func test_village_and_runestones_are_dry() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var r: float = home["radius"]
	for i in 36:
		var ang := TAU * i / 36.0
		for dist: float in [0.0, r * 0.5, r, r + 18.0, r * 1.8]:
			var p := c + Vector2(cos(ang), sin(ang)) * dist
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("wet at %s" % p).is_false()
	# The actual runestone ring used by the frontier.
	for i in 6:
		var ang := TAU * i / 6.0 + 0.3
		var p := c + Vector2(cos(ang), sin(ang)) * (r + 18.0)
		assert_float(WorldGen.water_depth(p.x, p.y)).is_equal(0.0)


func test_kings_ember_road_is_dry_and_ashrun_bridge_is_a_ford() -> void:
	var road := [Vector2(0, 0), Vector2(288, -199), Vector2(560, -420)]
	for k in road.size() - 1:
		for i in 41:
			var p: Vector2 = (road[k] as Vector2).lerp(road[k + 1], i / 40.0)
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("road wet at %s" % p).is_false()
	# Where the Oakvale road crosses the Ashrun the water stays wadeable.
	var bridge := Vector2(-318, -214)
	var nearest := INF
	var pts: PackedVector2Array = WorldGen.rivers[0]["points"]
	for p in pts:
		nearest = minf(nearest, p.distance_to(bridge))
	assert_float(nearest).is_less(20.0)
	assert_float(WorldGen.water_depth(bridge.x, bridge.y)).is_less(1.0)


func test_settlements_are_dry() -> void:
	for s in WorldGen.settlements:
		var c: Vector2 = s["pos"]
		var r: float = s["radius"]
		for i in 16:
			var ang := TAU * i / 16.0
			var p := c + Vector2(cos(ang), sin(ang)) * r
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s wet at %s" % [s["name"], p]).is_false()
		assert_bool(WorldGen.is_water(c.x, c.y)).is_false()


func test_lake_is_deep_water_away_from_roads() -> void:
	var lc := WorldGen.lake_center
	assert_float(lc.length()).is_between(350.0, 650.0)
	assert_bool(WorldGen.is_water(lc.x, lc.y)).is_true()
	assert_float(WorldGen.water_depth(lc.x, lc.y)).is_greater(2.0)
	assert_float(WorldGen.water_level_at(lc.x, lc.y)).is_equal_approx(WorldGen.lake_level, 0.001)
	assert_float(WorldGen.road_distance(lc.x, lc.y)).is_greater(WorldGen.lake_radius * 1.3)
	# Far from any water there is no level at all.
	assert_bool(is_nan(WorldGen.water_level_at(0.0, 0.0))).is_true()


func test_rivers_are_continuous() -> void:
	assert_int(WorldGen.rivers.size()).is_equal(3)     # the Ashrun's two arms, then the Silverrun through the new land
	for river in WorldGen.rivers:
		var pts: PackedVector2Array = river["points"]
		var lv: PackedFloat32Array = river["level"]
		assert_int(pts.size()).is_greater(20)
		for i in pts.size():
			var p := pts[i]
			if absf(p.x) > WorldGen.WORLD_HALF - 20.0 or absf(p.y) > WorldGen.WORLD_HALF - 20.0:
				continue
			# Sample the centreline densely, including between polyline points.
			for k in 4:
				var q := p if i == pts.size() - 1 else p.lerp(pts[i + 1], k / 4.0)
				assert_bool(WorldGen.is_water(q.x, q.y)).override_failure_message("dry river at %s" % q).is_true()
			if i > 0:
				assert_float(lv[i]).is_less_equal(lv[i - 1] + 0.001)   # water only runs downhill
	# Upstream arm ends in the lake, downstream arm starts there and reaches the edge.
	var up: PackedVector2Array = WorldGen.rivers[0]["points"]
	var down: PackedVector2Array = WorldGen.rivers[1]["points"]
	assert_float(up[up.size() - 1].distance_to(WorldGen.lake_center)).is_less(1.0)
	assert_float(down[0].distance_to(WorldGen.lake_center)).is_less(1.0)
	var end := down[down.size() - 1]
	assert_float(maxf(absf(end.x), absf(end.y))).is_greater(WorldGen.WORLD_HALF)
	# The Silverrun is independent of the lake and runs out through the eastern side of the 8 km map.
	var silver: PackedVector2Array = WorldGen.rivers[2]["points"]
	assert_float(maxf(absf(silver[silver.size() - 1].x), absf(silver[silver.size() - 1].y))).is_greater(WorldGen.WORLD_HALF)
	assert_float(silver[0].distance_to(WorldGen.lake_center)).is_greater(2000.0)


func test_no_forest_or_dens_in_water() -> void:
	var lc := WorldGen.lake_center
	assert_float(WorldGen.forest_density(lc.x, lc.y)).is_equal(0.0)
	for river in WorldGen.rivers:
		var pts: PackedVector2Array = river["points"]
		for i in range(0, pts.size(), 5):
			assert_float(WorldGen.forest_density(pts[i].x, pts[i].y)).is_equal(0.0)
	# Wolf dens only go where forest_density >= 0.45 (see autoload/frontier.gd): never wet.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lake_dir := lc.normalized()
	for i in 400:
		var p := lc + Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400))
		if i % 2 == 0:
			p = lake_dir * rng.randf_range(320.0, 1100.0)
		if WorldGen.forest_density(p.x, p.y) >= 0.45:
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("den site wet at %s" % p).is_false()
