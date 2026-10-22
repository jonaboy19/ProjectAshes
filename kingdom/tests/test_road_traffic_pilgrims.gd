extends GdUnitTestSuite
## Region 1 (C10 follow-up): the pilgrim band on the Eastern Gate road (scripts/world/road_traffic.gd). One band at a time,
## daylight only, pooled bodies, the walk runs from the settlement nearest the gate to the gate.

const RoadTraffic := preload("res://scripts/world/road_traffic.gd")


func _sites() -> Array:
	return [{"r1id": "highwatch_keep", "pos": Vector2(0, -900)}, {"r1id": "eastern_gate", "pos": Vector2(1000, 0)}]


func _settlements() -> Array:
	return [{"pos": Vector2(600, 0)}, {"pos": Vector2(-900, 0)}]


func test_the_walk_runs_from_the_nearest_settlement_to_the_gate() -> void:
	var seg := RoadTraffic.pilgrim_segment(_sites(), _settlements())
	assert_vector(seg["a"]).is_equal(Vector2(600, 0))
	assert_vector(seg["b"]).is_equal(Vector2(1000, 0))


func test_no_gate_in_the_world_means_no_pilgrims() -> void:
	assert_dict(RoadTraffic.pilgrim_segment([{"r1id": "x", "pos": Vector2.ZERO}], _settlements())).is_empty()
	assert_dict(RoadTraffic.pilgrim_segment(_sites(), [])).is_empty()


func test_a_band_sets_out_only_in_daylight_near_the_road_and_one_at_a_time() -> void:
	var seg := RoadTraffic.pilgrim_segment(_sites(), _settlements())
	var near := Vector2(800, 40)
	assert_bool(RoadTraffic.pilgrims_may_start(10.0, 0, near, seg)).is_true()
	assert_bool(RoadTraffic.pilgrims_may_start(22.0, 0, near, seg)).override_failure_message("night").is_false()
	assert_bool(RoadTraffic.pilgrims_may_start(5.0, 0, near, seg)).override_failure_message("before dawn").is_false()
	assert_bool(RoadTraffic.pilgrims_may_start(10.0, RoadTraffic.PILGRIM_MAX, near, seg)).override_failure_message("cap").is_false()
	assert_bool(RoadTraffic.pilgrims_may_start(10.0, 0, Vector2(800, 900), seg)).override_failure_message("far from the road").is_false()
	assert_bool(RoadTraffic.pilgrims_may_start(10.0, 0, near, {})).is_false()


func test_the_band_is_capped_and_its_bodies_are_pooled() -> void:
	var rt: Node3D = auto_free(RoadTraffic.new())
	add_child(rt)
	var built := [0]
	rt.pilgrim_builder = func() -> Node3D:
		built[0] += 1
		return Node3D.new()
	WorldSim.time_of_day = 10.0
	var seg := RoadTraffic.pilgrim_segment(_sites(), _settlements())
	var near := Vector2(800, 40)
	assert_bool(rt._maybe_spawn_pilgrims(near, seg, 0.0)).is_true()
	assert_bool(rt._maybe_spawn_pilgrims(near, seg, 0.0)).override_failure_message("a second band went out").is_false()
	assert_int(rt._pilgrims_active()).is_equal(1)
	var first: Node3D = (rt._groups[0] as Dictionary)["node"]
	# the walk ends: the band is parked, not freed
	rt._free_group(rt._groups[0])
	assert_int(rt._pilgrims_active()).is_equal(0)
	assert_bool(is_instance_valid(first) and not first.visible).is_true()
	# the next band is the same bodies
	assert_bool(rt._maybe_spawn_pilgrims(near, seg, 0.0)).is_true()
	assert_int(built[0]).override_failure_message("the pool was not reused").is_equal(1)
	assert_bool((rt._groups[0] as Dictionary)["node"] == first and first.visible).is_true()
