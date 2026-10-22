extends GdUnitTestSuite
## Phase W2 (WORLD_BRIEF.md): water, roads and pads with the Valencious macro on. Rivers sit on the ground (no floating water, shore gap < 0.3 m,
## sampled every 16 m along every polyline); the Westfen marsh pools exist only with the macro; roads are graded by the generator
## (tools/world/gen_valencious.py, ROAD_GRADE) so almost none of the 42 km is steeper than 12 %; the Region 1 landmark pads stay flat.


func after() -> void:
	WorldMacro.override = ""
	WorldGen.setup(1066)


func _macro() -> void:
	WorldMacro.override = "valencious"
	WorldGen.setup(1066)


func test_legacy_has_no_pools() -> void:
	WorldMacro.override = "noise"
	WorldGen.setup(1066)
	assert_array(WorldGen.pools).is_empty()


func test_rivers_sit_on_the_ground_every_16_m() -> void:
	_macro()
	var checked := 0
	var worst := 0.0
	for r: Dictionary in WorldGen.rivers:
		var pts: PackedVector2Array = r["points"]
		var i := 1
		while i < pts.size() - 1:
			var p := pts[i]
			i += 1                                           # polylines are sampled every RIVER_STEP = 16 m
			if absf(p.x) > 6100.0 or absf(p.y) > 6100.0:
				continue
			var lv := WorldGen.water_level_at(p.x, p.y)
			if is_nan(lv):
				continue
			var depth := lv - WorldGen.height(p.x, p.y)
			var in_lake := p.distance_to(WorldGen.lake_center) < WorldGen.lake_radius * 1.5      # the Mere bowl is 6.5 m deep
			assert_float(depth).override_failure_message("river centre dry or floating at %s: depth %.2f" % [p, depth]).is_between(0.05, 7.0 if in_lake else 4.5)
			var nrm := (pts[i] - pts[i - 2]).normalized().orthogonal()
			for side in [-1.0, 1.0]:
				var o := 0.0
				while o < 60.0:
					var q: Vector2 = p + nrm * side * o
					var ql := WorldGen.water_level_at(q.x, q.y)
					if is_nan(ql):
						break
					var gap := WorldGen.height(q.x, q.y) - ql
					if gap >= 0.0:
						worst = maxf(worst, gap)
						break
					o += 0.25
			checked += 1
	assert_int(checked).is_greater(1000)
	assert_float(worst).override_failure_message("shore gap %.3f m" % worst).is_less(0.3)


func test_westfen_pools_are_wet_low_and_clear_of_roads() -> void:
	_macro()
	assert_int(WorldGen.pools.size()).is_greater_equal(5)
	for pl: Dictionary in WorldGen.pools:
		var c: Vector2 = pl["pos"]
		assert_float(c.y).is_between(1000.0, 2300.0)
		assert_bool(WorldGen.is_water(c.x, c.y)).override_failure_message("pool at %s is dry" % c).is_true()
		var depth := WorldGen.water_depth(c.x, c.y)
		assert_float(depth).is_between(0.5, 3.0)
		assert_float(float(pl["level"])).is_between(-1.0, 8.5)         # the fen band is 0-6 m
		assert_float(WorldGen.road_distance(c.x, c.y)).is_greater(float(pl["radius"]) * 1.5)
		for st in WorldGen.settlements:
			assert_float(c.distance_to(st["pos"])).is_greater(float(st["radius"]) * 1.8 + float(pl["radius"]))
		assert_float(WorldGen.shore_distance(c.x, c.y)).is_less(0.0)
		# bank: walking out, the water ends where the ground meets it (no floating edge)
		var dir := Vector2.RIGHT
		var o := 0.0
		while o < float(pl["radius"]) * 2.5:
			var q := c + dir * o
			var lv := WorldGen.water_level_at(q.x, q.y)
			if is_nan(lv):
				break
			var gap := WorldGen.height(q.x, q.y) - lv
			if gap >= 0.0:
				assert_float(gap).is_less(0.3)
				break
			o += 0.25


func test_roads_are_graded_with_the_macro_on() -> void:
	_macro()
	var tot := 0.0
	var steep := 0.0
	for r in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		var len := a.distance_to(b)
		var steps := int(len / 8.0)
		var prev := WorldGen.height(a.x, a.y)
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / steps)
			var h := WorldGen.height(p.x, p.y)
			if absf(h - prev) / (len / steps) > 0.12:
				steep += len / steps
			prev = h
		tot += len
	assert_float(tot).is_greater(40000.0)
	# legacy noise terrain: 46.5 % of the road length is steeper than 12 %; graded macro: measured 7.3 % (Hollin's Reach walls, town pad edges)
	assert_float(steep / tot).override_failure_message("%.1f %% of road length steeper than 12 %%" % [steep / tot * 100.0]).is_less(0.09)


func test_region1_landmark_pads_are_flat_with_the_macro_on() -> void:
	_macro()
	var checked := 0
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) == "" or not bool(s["flatten"]) or float(s["clear"]) <= 0.0:
			continue
		var p: Vector2 = s["pos"]
		var cr: float = s["clear"]
		var base := WorldGen._raw_height(p.x, p.y)
		var m := 0.0
		for k in 8:
			var q := p + Vector2.from_angle(k * TAU / 8.0) * cr * 0.5
			m = maxf(m, absf(WorldGen.height(q.x, q.y) - base))
		assert_float(m).override_failure_message("%s pad off by %.2f m" % [s["name"], m]).is_less(0.6)
		checked += 1
	assert_int(checked).is_greater_equal(25)
