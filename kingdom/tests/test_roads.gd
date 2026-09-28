extends GdUnitTestSuite
## Road tiers, widths, runestone spacing/condition and the roads pillar's
## danger-by-time-of-day and rumours (docs/RISING_ASHES_LIFE_SIM_DESIGN.md).


func before() -> void:
	WorldGen.setup(1066)


func test_road_tier_by_settlement_kind() -> void:
	for r in WorldGen.roads:
		var a: Dictionary = WorldGen.settlements[r.x]
		var b: Dictionary = WorldGen.settlements[r.y]
		var tier := WorldGen.road_tier(r.x, r.y)
		if a["kind"] == "castle" or b["kind"] == "castle":
			assert_str(tier).is_equal("kingdom")
		elif a["kind"] == "town" or b["kind"] == "town":
			assert_str(tier).is_equal("rural")
		else:
			assert_str(tier).is_equal("frontier")


## Finds an actual MST road edge of the given tier, as {a, b}.
func _find_road(tier: String) -> Dictionary:
	for r in WorldGen.roads:
		if WorldGen.road_tier(r.x, r.y) == tier:
			return {"a": WorldGen.settlements[r.x]["pos"], "b": WorldGen.settlements[r.y]["pos"]}
	return {}


func test_road_info_widths_match_tier() -> void:
	var road := _find_road("kingdom")
	assert_bool(road.is_empty()).is_false()
	var mid: Vector2 = (road["a"] as Vector2).lerp(road["b"], 0.5)
	var info := WorldGen.road_info(mid.x, mid.y)
	assert_str(info["tier"]).is_equal("kingdom")
	assert_float(info["width"]).is_equal_approx(7.0, 0.001)
	assert_float(info["dist"]).is_less(1.0)
	# Off the road entirely: distance grows, tier of the *nearest* road still reported.
	var far := mid + Vector2(0, 500)
	var far_info := WorldGen.road_info(far.x, far.y)
	assert_float(far_info["dist"]).is_greater(300.0)
	assert_float(far_info["dist"]).is_greater(info["dist"])


func test_road_bed_is_wider_under_a_kingdom_road() -> void:
	# A point 3 m off a kingdom road centreline should still be inside its cut
	# bed (half width 3.5 m); a frontier road's half width is only 1.25 m.
	var road := _find_road("kingdom")
	assert_bool(road.is_empty()).is_false()
	var a: Vector2 = road["a"]
	var b: Vector2 = road["b"]
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x)
	var p := a.lerp(b, 0.5) + side * 3.0
	var info := WorldGen.road_info(p.x, p.y)
	assert_str(info["tier"]).is_equal("kingdom")
	assert_float(info["dist"]).is_less(info["width"] * 0.5 + 6.0)


func test_road_stones_overlap_along_a_kingdom_road() -> void:
	var net := RARunestoneNetwork.new()
	net.seed_road_stones()
	var road_stones: Array = net.stones.filter(func(s: Dictionary) -> bool: return bool(s.get("road", false)))
	assert_int(road_stones.size()).is_greater(0)
	# Between any two consecutive stones on the same kingdom/rural road, the
	# midpoint should still have coverage: they were spaced to just overlap.
	var checked := 0
	for r in WorldGen.roads:
		var tier := WorldGen.road_tier(r.x, r.y)
		if tier == "frontier":
			continue
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		var on_this_road: Array = road_stones.filter(func(s: Dictionary) -> bool:
			return Geometry2D.get_closest_point_to_segment(s["pos"], a, b).distance_to(s["pos"]) < 0.5)
		if on_this_road.size() < 2:
			continue
		on_this_road.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return a.distance_to(x["pos"]) < a.distance_to(y["pos"]))
		for i in on_this_road.size() - 1:
			var pa: Vector2 = on_this_road[i]["pos"]
			var pb: Vector2 = on_this_road[i + 1]["pos"]
			var mid: Vector2 = pa.lerp(pb, 0.5)
			assert_float(net.coverage(mid)).override_failure_message(
				"gap between road stones at %s" % mid).is_greater(0.0)
			checked += 1
	assert_int(checked).is_greater(0)


func test_frontier_road_stones_are_sparser_than_kingdom() -> void:
	assert_float(RARunestoneNetwork.ROAD_SPACING["frontier"]).is_greater(RARunestoneNetwork.ROAD_SPACING["kingdom"])
	assert_float(RARunestoneNetwork.ROAD_SPACING["frontier"]).is_greater(RARunestoneNetwork.ROAD_SPACING["rural"])


func test_condition_scales_coverage_strength() -> void:
	var net := RARunestoneNetwork.new()
	var s := net.add_stone(Vector2.ZERO, 100.0)
	var full := net.coverage(Vector2.ZERO)
	s["condition"] = 0.2
	var weak := net.coverage(Vector2.ZERO)
	assert_float(weak).is_less(full)
	assert_str(net.condition_name(s)).is_equal("cracked")
	s["condition"] = 0.05
	assert_str(net.condition_name(s)).is_equal("dark")
	s["condition"] = 1.0
	assert_str(net.condition_name(s)).is_equal("glowing")


func test_road_stone_condition_drifts_and_can_fail_or_repair() -> void:
	var net := RARunestoneNetwork.new()
	net.seed_road_stones()
	assert_bool(net.stones.is_empty()).is_false()
	for day in range(1, 60):
		net.tick_day(day)
	# Over many days of seeded drift, conditions should have spread out rather
	# than all staying pinned at 1.0 (decay) or 0.0 (repair floor).
	var distinct := {}
	for s in net.stones:
		distinct[snappedf(float(s["condition"]), 0.01)] = true
	assert_int(distinct.size()).is_greater(1)


func test_rumours_name_roads_with_failing_stones() -> void:
	var net := RARunestoneNetwork.new()
	net.seed_road_stones()
	assert_array(net.rumours()).is_empty()
	var road_stone: Dictionary = net.stones.filter(func(s: Dictionary) -> bool: return bool(s.get("road", false)))[0]
	road_stone["condition"] = 0.1
	net.stone_changed.emit(road_stone)
	var rumours := net.rumours()
	assert_int(rumours.size()).is_equal(1)
	assert_str(rumours[0]).contains(String(road_stone["road_to"]))
	assert_str(rumours[0]).contains("stopped glowing")


func test_danger_multiplier_rises_toward_deep_night() -> void:
	assert_float(Frontier.danger_mult(12.0)).is_equal_approx(1.0, 0.001)
	assert_float(Frontier.danger_mult(18.0)).is_equal_approx(1.5, 0.001)
	assert_float(Frontier.danger_mult(21.0)).is_equal_approx(2.5, 0.001)
	assert_float(Frontier.danger_mult(3.0)).is_equal_approx(3.0, 0.001)
	assert_float(Frontier.danger_mult(3.0)).is_greater(Frontier.danger_mult(21.0))
	assert_float(Frontier.danger_mult(21.0)).is_greater(Frontier.danger_mult(18.0))
	assert_float(Frontier.danger_mult(18.0)).is_greater(Frontier.danger_mult(12.0))
