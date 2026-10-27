extends GdUnitTestSuite
## Steering rules S1-S8 (scripts/living_world/steer_rules.gd, hazard_field.gd, street_lanes.gd): pure rule maths plus a
## headless NavigationServer3D avoidance test (2 and 6 agents cross without overlapping).

const DT := 1.0 / 60.0

var _map := RID()
var _agents: Array[RID] = []
var _obstacles: Array[RID] = []
var _safe: Array[Vector3] = []
var _got := 0


func before_test() -> void:
	HazardField.clear()


func after_test() -> void:
	for a in _agents:
		SteerRules.destroy_agent(a)
	for o in _obstacles:
		SteerRules.destroy_obstacle(o)
	_agents.clear()
	_obstacles.clear()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()
	HazardField.clear()


# -- helpers -----------------------------------------------------------------------------------------------------------

## A street stub: a straight corridor along Z of the given width centred on x = 0 (footprints beyond +-width/2).
class Corridor extends RefCounted:
	var half := 0.8

	func _init(width: float) -> void:
		half = width * 0.5

	func inside(p: Vector2, _r := 0.0) -> bool:
		return absf(p.x) > half


func _res() -> SteerRules.Result:
	return SteerRules.Result.new()


# -- HazardField (S5 storage) --------------------------------------------------------------------------------------------

func test_hazard_register_query_unregister() -> void:
	var h := HazardField.register(Vector2(5, 5), HazardField.Kind.PUDDLE)
	assert_bool(h >= 0).is_true()
	assert_int(HazardField.count()).is_equal(1)
	var n := HazardField.query(Vector2(5.5, 5), 0.0, HazardField.scratch)
	assert_int(n).is_equal(1)
	assert_float(HazardField.slot_radius(HazardField.scratch[0])).is_equal_approx(0.8, 0.001)
	assert_int(HazardField.query(Vector2(20, 20), 0.0, HazardField.scratch)).is_equal(0)
	assert_bool(HazardField.unregister(h)).is_true()
	assert_bool(HazardField.unregister(h)).is_false()     # stale handle
	assert_int(HazardField.count()).is_equal(0)
	assert_int(HazardField.query(Vector2(5.5, 5), 0.0, HazardField.scratch)).is_equal(0)


func test_hazard_stale_handle_never_frees_the_next_occupant() -> void:
	var h1 := HazardField.register(Vector2.ZERO, HazardField.Kind.MUD)
	HazardField.unregister(h1)
	var h2 := HazardField.register(Vector2(1, 1), HazardField.Kind.FIRE)
	assert_bool(HazardField.unregister(h1)).is_false()
	assert_int(HazardField.count()).is_equal(1)
	assert_bool(HazardField.unregister(h2)).is_true()


func test_hazard_kind_radii_and_capacity_and_expiry() -> void:
	var fire := HazardField.register(Vector2.ZERO, HazardField.Kind.FIRE)
	HazardField.query(Vector2.ZERO, 0.0, HazardField.scratch)
	assert_float(HazardField.slot_radius(HazardField.scratch[0])).is_equal_approx(2.0, 0.001)
	HazardField.unregister(fire)
	for i in HazardField.MAX:
		assert_bool(HazardField.register(Vector2(i, 0), HazardField.Kind.DUNG, -1.0, 10.0) >= 0).is_true()
	assert_int(HazardField.register(Vector2.ZERO)).is_equal(-1)    # full
	assert_int(HazardField.prune(9.0)).is_equal(0)
	assert_int(HazardField.prune(10.0)).is_equal(HazardField.MAX)
	assert_int(HazardField.count()).is_equal(0)


func test_hazard_inside() -> void:
	HazardField.register(Vector2(0, 0), HazardField.Kind.MUD, 1.0)
	assert_bool(HazardField.inside(Vector2(0.9, 0))).is_true()
	assert_bool(HazardField.inside(Vector2(1.1, 0))).is_false()


# -- StreetLanes (corridor_width / lane_offset) --------------------------------------------------------------------------

func test_corridor_width_measures_the_street() -> void:
	for w: float in [1.2, 1.6, 2.4, 3.0]:
		var got := StreetLanes.corridor_width(Corridor.new(w), Vector2.ZERO, Vector2(0, 1))
		assert_float(got).is_equal_approx(w, 0.45)
	# in the open the probe tops out at 2 * max_half
	assert_float(StreetLanes.corridor_width(Corridor.new(40.0), Vector2.ZERO, Vector2(0, 1))).is_equal_approx(StreetLanes.PROBE_MAX, 0.25)
	# inside a footprint there is no corridor
	assert_float(StreetLanes.corridor_width(Corridor.new(1.0), Vector2(3, 0), Vector2(0, 1))).is_equal(0.0)


func test_right_of_convention() -> void:
	# facing -Z (the walker's forward) the right hand is +X; facing +Z it is -X
	assert_vector(Vector3(StreetLanes.right_of(Vector2(0, -1)).x, 0, 0)).is_equal_approx(Vector3(1, 0, 0), Vector3(0.001, 0.001, 0.001))
	assert_float(StreetLanes.right_of(Vector2(0, 1)).x).is_equal_approx(-1.0, 0.001)


func test_lane_offset_distribution_is_not_centred() -> void:
	var sum := 0.0
	var lo := INF
	var hi := -INF
	for k in 1000:
		var o := StreetLanes.lane_offset(5.0, k)
		sum += o
		lo = minf(lo, o)
		hi = maxf(hi, o)
	assert_float(sum / 1000.0).is_greater(1.0)                  # mean toward the right edge, not 0
	assert_float(lo).is_greater_equal(0.3 * 5.0 - 0.001)
	assert_float(hi).is_less_equal(0.45 * 5.0 + 0.001)
	assert_float(hi - lo).is_greater(0.4)                       # spread by hash, not one line
	# deterministic
	assert_float(StreetLanes.lane_offset(5.0, 17)).is_equal(StreetLanes.lane_offset(5.0, 17))


func test_lane_offset_narrow_street_and_body_clamp() -> void:
	assert_float(StreetLanes.lane_offset(2.9, 5)).is_equal(0.0)
	for k in 200:
		assert_float(StreetLanes.lane_offset(3.0, k)).is_less_equal(3.0 * 0.5 - 0.35 - StreetLanes.LANE_EDGE_MARGIN + 0.0001)


func test_lane_steer_converges_to_the_lane() -> void:
	var r := _res()
	var lat := 0.0
	var route := Vector2(0, -1.3)
	var key := 11
	for i in 600:
		r.reset()
		SteerRules.lane_steer(r, route, 5.0, lat, key)
		lat += r.steer.dot(StreetLanes.right_of(Vector2(0, -1))) * DT
	assert_float(lat).is_equal_approx(StreetLanes.lane_offset(5.0, key), 0.08)
	# a narrow street: nothing to do
	r.reset()
	assert_bool(SteerRules.lane_steer(r, route, 2.5, 0.0, key)).is_false()


# -- S1: RVO parameters and the NavigationServer3D agent ----------------------------------------------------------------------

func test_rvo_params_table() -> void:
	assert_float(SteerRules.rvo_params("child")["radius"]).is_equal_approx(0.3, 0.001)
	assert_float(SteerRules.rvo_params("villager")["radius"]).is_equal_approx(0.5, 0.001)
	assert_float(SteerRules.rvo_params("guard")["radius"]).is_equal_approx(0.9, 0.001)
	assert_float(SteerRules.rvo_params("noble")["radius"]).is_equal_approx(0.8, 0.001)
	var layers := 0
	for a: String in SteerRules.ARCH_LAYER:
		var p := SteerRules.rvo_params(a)
		assert_float(p["time_horizon_agents"]).is_equal(1.5)
		assert_int(p["max_neighbors"]).is_equal(6)
		assert_int(layers & int(p["layers"])).is_equal(0)       # one distinct bit per archetype
		layers |= int(p["layers"])
		assert_bool(float(p["priority"]) >= 0.0 and float(p["priority"]) <= 1.0).is_true()
	# unknown archetypes fall back to the villager row
	assert_float(SteerRules.rvo_params("dragon")["radius"]).is_equal_approx(0.5, 0.001)
	# the same Dictionary every call (no allocation)
	assert_bool(SteerRules.rvo_params("guard") == SteerRules.rvo_params("guard")).is_true()


func test_rvo_priority_ranks_a_loaded_carrier_higher() -> void:
	assert_float(SteerRules.rvo_priority("villager", true)).is_greater(SteerRules.rvo_priority("villager", false))
	assert_float(SteerRules.rvo_priority("noble", true)).is_less_equal(1.0)
	assert_float(SteerRules.rvo_priority("child", false)).is_less(SteerRules.rvo_priority("guard", false))


func test_create_agent_configures_the_server() -> void:
	# the server queues commands until its next sync, so give it a physics frame before reading anything back
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	var a := SteerRules.create_agent(_map, "guard", Vector3(1, 0, 2))
	_agents.append(a)
	assert_bool(a.is_valid()).is_true()
	var ob := SteerRules.create_vehicle_obstacle(_map, "cart", Vector3(0, 0, 0), Vector3(3, 0, 0))
	_obstacles.append(ob)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(ob.is_valid()).is_true()
	assert_bool(NavigationServer3D.agent_get_map(a) == _map).is_true()
	assert_bool(NavigationServer3D.agent_get_avoidance_enabled(a)).is_true()
	var p := SteerRules.rvo_params("guard")
	assert_float(NavigationServer3D.agent_get_radius(a)).is_equal_approx(p["radius"], 0.001)
	assert_float(NavigationServer3D.agent_get_avoidance_priority(a)).is_equal_approx(p["priority"], 0.001)
	assert_int(NavigationServer3D.agent_get_avoidance_layers(a)).is_equal(p["layers"])
	assert_float(NavigationServer3D.agent_get_time_horizon_agents(a)).is_equal_approx(1.5, 0.001)
	assert_int(NavigationServer3D.agent_get_max_neighbors(a)).is_equal(6)
	assert_bool(NavigationServer3D.obstacle_get_avoidance_enabled(ob)).is_true()
	assert_float(NavigationServer3D.obstacle_get_radius(ob)).is_equal_approx(SteerRules.VEHICLE_RADIUS["cart"], 0.001)


func _on_safe(v: Vector3, i: int) -> void:
	_safe[i] = v
	_got += 1


## Drives agents[i] from starts[i] to goals[i] through the server's avoidance; returns the minimum centre distance between any
## two bodies over the run and writes the final positions into `ends`. Steps physics frames and waits for every callback.
func _cross(archetypes: Array, starts: Array, goals: Array, seconds: float, speed: float, ends: Array, obstacles: Array = []) -> float:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	var n := archetypes.size()
	_safe.clear()
	var pos: Array[Vector3] = []
	for i in n:
		_safe.append(Vector3.ZERO)
		pos.append(starts[i])
		_agents.append(SteerRules.create_agent(_map, archetypes[i], starts[i], Callable(self, "_on_safe").bind(i)))
	var vehicles: Array = []
	for o: Dictionary in obstacles:
		var ob := SteerRules.create_vehicle_obstacle(_map, o["kind"], o["pos"], o["vel"])
		_obstacles.append(ob)
		vehicles.append({"rid": ob, "pos": o["pos"], "vel": o["vel"], "radius": float(SteerRules.VEHICLE_RADIUS[o["kind"]])})
	var min_dist := INF
	var min_vehicle := INF
	for step in int(seconds / DT):
		_got = 0
		for i in n:
			var to: Vector3 = goals[i] - pos[i]
			to.y = 0.0
			var pref := to.normalized() * minf(speed, to.length() / DT)
			SteerRules.agent_update(_agents[i], pos[i], Vector2(pref.x, pref.z))
		for v: Dictionary in vehicles:
			v["pos"] += v["vel"] * DT
			SteerRules.update_vehicle_obstacle(v["rid"], v["pos"], v["vel"])
		var waited := 0
		while _got < n and waited < 6:
			await get_tree().physics_frame
			waited += 1
		for i in n:
			pos[i] += _safe[i] * DT
		for i in n:
			for j in range(i + 1, n):
				min_dist = minf(min_dist, pos[i].distance_to(pos[j]))
			for v: Dictionary in vehicles:
				min_vehicle = minf(min_vehicle, pos[i].distance_to(v["pos"]) - float(v["radius"]))
	ends.clear()
	ends.append_array(pos)
	if not vehicles.is_empty():
		return min_vehicle
	return min_dist


func test_two_agents_cross_head_on_without_overlap() -> void:
	var ends: Array = []
	var d: float = await _cross(["villager", "villager"], [Vector3(-4, 0, 0), Vector3(4, 0, 0.03)],
		[Vector3(4, 0, 0), Vector3(-4, 0, 0)], 9.0, 1.4, ends)
	print("2-agent head-on min centre distance: %.2f m" % d)
	assert_float(d).is_greater_equal(0.45)
	assert_float(ends[0].x).is_greater(3.0)       # both got through
	assert_float(ends[1].x).is_less(-3.0)


func test_six_agents_cross_without_overlap() -> void:
	var archs := ["villager", "child", "elder", "guard", "merchant", "villager"]
	var starts: Array = []
	var goals: Array = []
	for k in 6:
		var a := TAU * k / 6.0 + 0.05 * k
		starts.append(Vector3(cos(a), 0, sin(a)) * 4.5)
		goals.append(Vector3(cos(a + PI), 0, sin(a + PI)) * 4.5)
	var ends: Array = []
	var d: float = await _cross(archs, starts, goals, 14.0, 1.4, ends)
	print("6-agent crossing min centre distance: %.2f m" % d)
	assert_float(d).is_greater_equal(0.45)
	for k in 6:
		assert_float((ends[k] as Vector3).distance_to(goals[k])).is_less(1.5)      # everybody arrives


func test_agent_routes_around_a_moving_cart_obstacle() -> void:
	var ends: Array = []
	var d: float = await _cross(["villager"], [Vector3(0, 0, -5)], [Vector3(0, 0, 5)], 7.0, 1.4, ends,
		[{"kind": "cart", "pos": Vector3(-8, 0, 0.0), "vel": Vector3(3, 0, 0)}])
	print("agent clearance to the cart edge: %.2f m" % d)
	assert_float(d).is_greater(0.0)                # never inside the cart radius


# -- S2: yield (rank x load x age) ---------------------------------------------------------------------------------------

func test_effective_rank_truth_table() -> void:
	assert_float(SteerRules.effective_rank(2.0, false, 30.0)).is_equal(2.0)
	assert_float(SteerRules.effective_rank(2.0, true, 30.0)).is_equal(3.0)      # a load
	assert_float(SteerRules.effective_rank(2.0, false, 70.0)).is_equal(3.0)     # age
	assert_float(SteerRules.effective_rank(2.0, true, 70.0)).is_equal(4.0)      # both
	assert_float(SteerRules.effective_rank(1.0, false, 8.0)).is_equal(1.0)      # a child


func test_yield_role_truth_table() -> void:
	assert_int(SteerRules.yield_role(2.0, 4.0, 1, 2)).is_equal(1)      # lower rank yields
	assert_int(SteerRules.yield_role(4.0, 2.0, 1, 2)).is_equal(-1)     # higher holds
	assert_int(SteerRules.yield_role(3.0, 3.0, 1, 2)).is_equal(1)      # tie: lower key yields
	assert_int(SteerRules.yield_role(3.0, 3.0, 2, 1)).is_equal(-1)
	assert_int(SteerRules.yield_role(3.0, 3.0, 7, 7)).is_equal(0)
	# villager (2) vs loaded villager (3), vs aged loaded villager (4) vs elder archetype (4)
	var plain := SteerRules.effective_rank(2.0, false)
	var loaded := SteerRules.effective_rank(2.0, true)
	var old_loaded := SteerRules.effective_rank(2.0, true, 75.0)
	assert_int(SteerRules.yield_role(plain, loaded, 5, 6)).is_equal(1)
	assert_int(SteerRules.yield_role(loaded, old_loaded, 5, 6)).is_equal(1)
	assert_int(SteerRules.yield_role(old_loaded, 4.0, 9, 3)).is_equal(-1)     # same rank 4, higher key holds


func test_yield_step_lower_rank_slows_and_steps_right() -> void:
	var r := _res()
	# me walking +Z at 1.3, the other coming -Z, 4 m apart: contact in ~1.4 s
	var fired := SteerRules.yield_step(r, Vector2.ZERO, Vector2(0, 1.3), 2.0, 1, 0.5, Vector2(0, 4), Vector2(0, -1.3), 4.0, 2, 0.5)
	assert_bool(fired).is_true()
	assert_float(r.speed_mul).is_equal_approx(0.4, 0.001)
	assert_float(r.steer.length()).is_equal_approx(0.6, 0.001)
	assert_float(r.steer.dot(StreetLanes.right_of(Vector2(0, 1)))).is_greater(0.5)       # to my right
	# the higher rank barely deviates and keeps its speed
	r.reset()
	assert_bool(SteerRules.yield_step(r, Vector2(0, 4), Vector2(0, -1.3), 4.0, 2, 0.5, Vector2.ZERO, Vector2(0, 1.3), 2.0, 1, 0.5)).is_true()
	assert_float(r.speed_mul).is_equal(1.0)
	assert_float(r.steer.length()).is_less(0.15)
	assert_float(r.steer.length()).is_greater(0.0)


func test_yield_step_needs_a_collision_course_within_the_horizon() -> void:
	var r := _res()
	# far away: contact in more than 2.5 s
	assert_bool(SteerRules.yield_step(r, Vector2.ZERO, Vector2(0, 1.3), 2.0, 1, 0.5, Vector2(0, 12), Vector2(0, -1.3), 4.0, 2, 0.5)).is_false()
	# passing 3 m to the side
	assert_bool(SteerRules.yield_step(r, Vector2.ZERO, Vector2(0, 1.3), 2.0, 1, 0.5, Vector2(3, 4), Vector2(0, -1.3), 4.0, 2, 0.5)).is_false()
	# diverging
	assert_bool(SteerRules.yield_step(r, Vector2.ZERO, Vector2(0, -1.3), 2.0, 1, 0.5, Vector2(0, 2), Vector2(0, 1.3), 4.0, 2, 0.5)).is_false()
	assert_float(r.speed_mul).is_equal(1.0)


func test_yield_head_on_pair_passes_with_clearance() -> void:
	# lower rank (A) and higher rank (B) head-on, both with the S2 rule only, 60 Hz
	var a := Vector2(0, 0)
	var b := Vector2(0, 8)
	var min_d := INF
	var r := _res()
	for i in 480:
		var va := Vector2(0, 1.3)
		var vb := Vector2(0, -1.3)
		r.reset()
		SteerRules.yield_step(r, a, va, 2.0, 1, 0.5, b, vb, 4.0, 2, 0.5)
		var na := r.velocity(va)
		r.reset()
		SteerRules.yield_step(r, b, vb, 4.0, 2, 0.5, a, va, 2.0, 1, 0.5)
		var nb := r.velocity(vb)
		a += na * DT
		b += nb * DT
		min_d = minf(min_d, a.distance_to(b))
	print("S2 head-on min centre distance: %.2f m" % min_d)
	assert_float(min_d).is_greater_equal(0.45)
	assert_float(a.y).is_greater(b.y)        # they got past each other
	assert_float(a.x).is_less(b.x)           # A on its right (-X facing +Z), B on its right (+X facing -Z)


# -- S3: pass on the right + shoulder turn ----------------------------------------------------------------------------------

func test_pass_trigger_window() -> void:
	var r := _res()
	var me := Vector2.ZERO
	var v := Vector2(0, 1.3)
	var oncoming := Vector2(0, -1.3)
	assert_bool(SteerRules.pass_applies(1.4, me, v, Vector2(0, 2.9), oncoming)).is_true()
	assert_bool(SteerRules.pass_applies(1.4, me, v, Vector2(0, 3.1), oncoming)).is_false()    # beyond 3 m
	assert_bool(SteerRules.pass_applies(1.4, me, v, Vector2(0, -2.0), -oncoming)).is_false()  # behind me
	assert_bool(SteerRules.pass_applies(1.4, me, v, Vector2(0, 2.0), Vector2(0, 1.3))).is_false()  # same direction
	assert_bool(SteerRules.pass_right(r, 1.4, me, v, Vector2(0, 2.9), oncoming, 3, 0)).is_true()


func test_no_pass_rule_in_a_wide_street() -> void:
	var r := _res()
	for w: float in [1.6, 1.8, 2.0, 3.0]:
		r.reset()
		assert_bool(SteerRules.pass_right(r, w, Vector2.ZERO, Vector2(0, 1.3), Vector2(0, 2.0), Vector2(0, -1.3), 3, 0)).is_false()
		assert_bool(r.turn).is_false()
		assert_vector(Vector3(r.steer.x, 0, r.steer.y)).is_equal(Vector3.ZERO)


func test_pass_keeps_right_and_turns_only_when_close_at_near() -> void:
	var r := _res()
	var right := StreetLanes.right_of(Vector2(0, 1))
	assert_bool(SteerRules.pass_right(r, 1.3, Vector2.ZERO, Vector2(0, 1.3), Vector2(0, 2.8), Vector2(0, -1.3), 3, SteerRules.TIER_NEAR)).is_true()
	assert_float(r.steer.dot(right)).is_greater(0.0)          # bias to my right
	assert_bool(r.turn).is_false()                           # still 2.8 m away
	r.reset()
	assert_bool(SteerRules.pass_right(r, 1.3, Vector2.ZERO, Vector2(0, 1.3), Vector2(0, 1.4), Vector2(0, -1.3), 3, SteerRules.TIER_NEAR)).is_true()
	assert_bool(r.turn).is_true()
	assert_float(r.turn_deg).is_between(30.0, 40.0)
	r.reset()    # MID: side bias only
	assert_bool(SteerRules.pass_right(r, 1.3, Vector2.ZERO, Vector2(0, 1.3), Vector2(0, 1.4), Vector2(0, -1.3), 3, 1)).is_true()
	assert_bool(r.turn).is_false()
	assert_float(r.steer.length()).is_greater(0.0)


func test_pass_in_a_narrow_alley_ends_on_opposite_sides() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(0, 8)
	var r := _res()
	var lat_a := 0.0
	var lat_b := 0.0
	for i in 300:
		var va := Vector2(0, 1.3)
		var vb := Vector2(0, -1.3)
		r.reset()
		SteerRules.pass_right(r, 1.4, a, va, b, vb, 1, 0)
		var na := r.velocity(va)
		r.reset()
		SteerRules.pass_right(r, 1.4, b, vb, a, va, 2, 0)
		var nb := r.velocity(vb)
		a += na * DT
		b += nb * DT
		if absf(a.y - b.y) < 0.3:
			lat_a = a.x
			lat_b = b.x
	assert_float(lat_a).is_less(lat_b - 0.2)     # A passed on -X (its right facing +Z), B on +X (its right facing -Z)


# -- S4: stop for carts and horses -------------------------------------------------------------------------------------------

func test_mover_stop_triggers_and_releases() -> void:
	var r := _res()
	var cart := Vector2(-6, 0)
	var vel := Vector2(3, 0)
	# beside the lane, cart coming: stop at the kerb
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 2.0), cart, vel, 4)).is_true()
	assert_bool(r.stop).is_true()
	# far outside the stop distance: walk on
	r.reset()
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 5.0), cart, vel, 4)).is_false()
	# the cart has just reached the walker: still stopped; two metres past: resume
	r.reset()
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 2.0), Vector2(0.5, 0), vel, 4)).is_true()
	r.reset()
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 2.0), Vector2(2.0, 0), vel, 4)).is_false()
	# standing in the lane: step out sideways instead of just stopping
	r.reset()
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 0.4), cart, vel, 4)).is_true()
	assert_bool(r.stop).is_true()
	assert_float(absf(r.steer.y)).is_greater(1.0)
	assert_float(r.steer.y).is_greater(0.0)               # out toward the side it was already on
	# a standing cart is no threat
	r.reset()
	assert_bool(SteerRules.mover_stop(r, Vector2(0, 0.4), cart, Vector2(0.2, 0), 4)).is_false()


func test_fifty_seeded_cart_passes_never_clip() -> void:
	var worst := INF
	for seed in 50:
		var start_side := 1.0 if StreetLanes.hash01(seed, 1) >= 0.5 else -1.0
		var lateral := lerpf(2.2, 7.0, StreetLanes.hash01(seed, 2))
		var ax := lerpf(-3.0, 3.0, StreetLanes.hash01(seed, 3))
		var walker := Vector2(ax, start_side * lateral)
		var goal_z := -start_side * 8.0            # crosses the lane
		var cart_speed := lerpf(2.0, 4.0, StreetLanes.hash01(seed, 4))
		var cart := Vector2(-lerpf(8.0, 16.0, StreetLanes.hash01(seed, 5)), 0.0)
		var r := _res()
		var cart_radius := 1.0
		for i in int(14.0 / DT):
			var to_goal := Vector2(ax, goal_z) - walker
			var route := to_goal.normalized() * 1.35 if to_goal.length() > 0.2 else Vector2.ZERO
			r.reset()
			SteerRules.mover_stop(r, walker, cart, Vector2(cart_speed, 0), seed)
			walker += r.velocity(route) * DT
			cart.x += cart_speed * DT
			worst = minf(worst, walker.distance_to(cart) - cart_radius)
	print("S4 worst clearance to the cart edge over 50 passes: %.2f m" % worst)
	assert_float(worst).is_greater(0.0)


# -- S5: hazards --------------------------------------------------------------------------------------------------------------

func test_walker_steers_around_a_puddle() -> void:
	HazardField.register(Vector2(0, 6), HazardField.Kind.PUDDLE)
	var worst := INF
	for key in 10:
		var pos := Vector2(0, 0)
		var r := _res()
		for i in int(8.0 / DT):
			var route := Vector2(0, 1.35)
			r.reset()
			SteerRules.avoid_hazards(r, pos, route, key)
			pos += r.velocity(route) * DT
			worst = minf(worst, pos.distance_to(Vector2(0, 6)))
		assert_float(pos.y).is_greater(8.0)         # still got to the far side
	print("S5 closest approach to the puddle centre: %.2f m (radius 0.8)" % worst)
	assert_float(worst).is_greater(0.8)


func test_runner_splashes_through_a_puddle() -> void:
	HazardField.register(Vector2(0, 6), HazardField.Kind.PUDDLE)
	var r := _res()
	assert_bool(SteerRules.avoid_hazards(r, Vector2(0, 4.5), Vector2(0, 4.5), 1)).is_false()      # 4.5 m/s
	assert_bool(SteerRules.avoid_hazards(r, Vector2(0, 4.5), Vector2(0, 1.35), 1, true)).is_false()
	assert_bool(SteerRules.avoid_hazards(r, Vector2(0, 4.5), Vector2(0, 1.35), 1)).is_true()


func test_hazard_off_the_path_changes_nothing() -> void:
	HazardField.register(Vector2(6, 6), HazardField.Kind.MUD)
	var r := _res()
	assert_bool(SteerRules.avoid_hazards(r, Vector2(0, 5), Vector2(0, 1.35), 1)).is_false()
	assert_bool(SteerRules.avoid_hazards(r, Vector2(0, 9), Vector2(0, 1.35), 1)).is_false()    # already past it
	assert_float(r.steer.length()).is_equal(0.0)


# -- S6: pair offset --------------------------------------------------------------------------------------------------------

func test_pair_slot_and_speed() -> void:
	var slot := SteerRules.pair_slot(Vector2(10, 10), Vector2(0, -1), 1.0)       # leader walking -Z, partner on its right (+X)
	assert_vector(Vector3(slot.x, 0, slot.y)).is_equal_approx(Vector3(10.7, 0, 10.0), Vector3(0.001, 0.001, 0.001))
	slot = SteerRules.pair_slot(Vector2(10, 10), Vector2(0, -1), -1.0)
	assert_float(slot.x).is_equal_approx(9.3, 0.001)
	assert_float(SteerRules.pair_speed(1.4, 0.95)).is_equal(0.95)


func test_pair_partner_stays_within_half_a_metre_through_a_corner() -> void:
	var leader := Vector2.ZERO
	var heading := 0.0                                  # radians, 0 = +Z
	var partner := SteerRules.pair_slot(leader, Vector2(0, 1), 1.0)
	var r := _res()
	var worst := 0.0
	var turn_started := false
	for i in int(14.0 / DT):
		var t := i * DT
		# straight 5 s, then a 90 degree rounded corner (radius 1.5 m at 1.35 m/s: ~1.7 s), then straight
		var rate := 0.0
		if t >= 5.0 and heading < PI * 0.5:
			rate = 1.35 / 1.5
			turn_started = true
		heading = minf(heading + rate * DT, PI * 0.5)
		var dir := Vector2(sin(heading), cos(heading))
		var lv := dir * 1.35
		leader += lv * DT
		var slot := SteerRules.pair_slot(leader, dir, 1.0)
		r.reset()
		SteerRules.pair_steer(r, partner, slot)
		partner += (lv + r.steer) * DT
		if t > 1.0:
			worst = maxf(worst, partner.distance_to(slot))
	assert_bool(turn_started).is_true()
	print("S6 worst slot error through the corner: %.2f m" % worst)
	assert_float(worst).is_less(0.5)
	assert_float(partner.distance_to(SteerRules.pair_slot(leader, Vector2(1, 0), 1.0))).is_less(0.1)


# -- composition and MotionRules bindings -----------------------------------------------------------------------------------

func _ctx(pos: Vector3, vel: Vector3) -> Dictionary:
	return {"position": pos, "velocity": vel, "now": 0.0, "speed": Vector2(vel.x, vel.z).length()}


func test_desired_velocity_without_neighbours_is_the_route_velocity() -> void:
	var arch: Dictionary = MotionRules.default_registry().archetypes["villager"]
	var r := _res()
	var v := SteerRules.desired_velocity(r, _ctx(Vector3(3, 0, 4), Vector3(0, 0, 1.3)), arch, {"id": 4}, 0)
	assert_vector(Vector3(v.x, 0, v.y)).is_equal_approx(Vector3(0, 0, 1.3), Vector3(0.001, 0.001, 0.001))
	assert_int(r.fired).is_equal(0)


func test_desired_velocity_composes_rules() -> void:
	var arch: Dictionary = MotionRules.default_registry().archetypes["villager"]
	var ctx := _ctx(Vector3(0, 0, 0), Vector3(0, 0, 1.3))
	ctx["oncoming_pos"] = Vector3(0, 0, 2.8)
	ctx["oncoming_vel"] = Vector3(0, 0, -1.3)
	ctx["oncoming_rank"] = 4.0
	ctx["oncoming_id"] = 99
	ctx["corridor_width"] = 1.3
	ctx["edge_width"] = 5.0
	var r := _res()
	var v := SteerRules.desired_velocity(r, ctx, arch, {"id": 4}, 0)
	assert_int(r.fired & 2).is_equal(2)          # S2
	assert_int(r.fired & 4).is_equal(4)          # S3
	assert_int(r.fired & 128).is_equal(128)      # S8
	assert_float(v.y).is_less(1.3)               # slowed
	assert_float(v.x).is_less(-0.3)              # to its right (-X facing +Z)
	# a carrier of equal archetype outranks: the oncoming (rank 4) now yields, so I keep going nearly straight
	ctx["carrying"] = true
	ctx["age"] = 70.0
	ctx["oncoming_rank"] = 2.0
	r.reset()
	var v2 := SteerRules.desired_velocity(r, ctx, arch, {"id": 4}, 0)
	assert_float(v2.y).is_greater(v.y)


func test_desired_velocity_runner_skips_polite_rules() -> void:
	var arch: Dictionary = MotionRules.default_registry().archetypes["villager"]
	var ctx := _ctx(Vector3(0, 0, 0), Vector3(0, 0, 4.5))
	ctx["oncoming_pos"] = Vector3(0, 0, 4.0)
	ctx["oncoming_vel"] = Vector3(0, 0, -1.3)
	var r := _res()
	SteerRules.desired_velocity(r, ctx, arch, {"id": 4}, 0)
	assert_int(r.fired & 2).is_equal(0)


func test_motion_rules_bindings_fire_and_arbitrate() -> void:
	var ctx := _ctx(Vector3(0, 0, 2.0), Vector3(1.3, 0, 0))
	ctx["mover_pos"] = Vector3(-6, 0, 0)
	ctx["mover_vel"] = Vector3(3, 0, 0)
	var intent := MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_NEAR)
	assert_str(intent["loco_rule"]).is_equal("S4")
	assert_bool(intent["stop"]).is_true()
	# an oncoming walker too: S4 (priority 4) outranks S2 (3)
	ctx["oncoming_pos"] = Vector3(4, 0, 2.0)
	ctx["oncoming_vel"] = Vector3(-1.3, 0, 0)
	ctx["oncoming_rank"] = 5.0
	intent = MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_NEAR)
	assert_str(intent["loco_rule"]).is_equal("S4")
	# without the mover the yield wins the LOCO channel
	ctx.erase("mover_pos")
	intent = MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_NEAR)
	assert_str(intent["loco_rule"]).is_equal("S2")
	assert_float(intent["speed_mul"]).is_equal_approx(0.4, 0.001)


func test_motion_rules_s3_plays_the_turn_clip_only_at_near() -> void:
	var ctx := _ctx(Vector3(0, 0, 0), Vector3(0, 0, 1.3))
	ctx["oncoming_pos"] = Vector3(0, 0, 1.4)
	ctx["oncoming_vel"] = Vector3(0, 0, -1.3)
	ctx["oncoming_rank"] = 2.0
	ctx["oncoming_id"] = 4          # equal rank, equal key: no yield, so the pass rule owns the channels
	ctx["corridor_width"] = 1.2
	var near := MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_NEAR)
	assert_str(near["upper_clip"]).is_equal("Life_Pass_Shoulder_Turn_Upper")
	assert_str(near["loco_rule"]).is_equal("S3")
	var mid := MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_MID)
	assert_str(mid["upper_clip"]).is_equal("")
	assert_str(mid["loco_rule"]).is_equal("S3")


func test_motion_rules_s5_and_s8_bind() -> void:
	HazardField.register(Vector2(0, 3), HazardField.Kind.PUDDLE)
	var ctx := _ctx(Vector3(0, 0, 0.5), Vector3(0, 0, 1.3))
	var intent := MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_MID)
	assert_str(intent["loco_rule"]).is_equal("S5")
	assert_float(Vector2(intent["steer_x"], intent["steer_z"]).length()).is_greater(0.3)
	HazardField.clear()
	ctx["edge_width"] = 5.0
	ctx["edge_lateral"] = 0.0
	intent = MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_FAR)
	assert_str(intent["loco_rule"]).is_equal("S8")
	assert_float(intent["steer_x"]).is_less(0.0)       # right of +Z is -X


func test_stub_rules_stay_stubs() -> void:
	# S1 (node-side agent) and S6/S7 (M5) must not fire from the rule table
	var ctx := _ctx(Vector3(0, 0, 0), Vector3(0, 0, 1.3))
	ctx["pair_pos"] = Vector3(3, 0, 0)
	ctx["pair_vel"] = Vector3(0, 0, 1.3)
	var intent := MotionRules.evaluate(ctx, {"archetype": "villager", "id": 4}, MotionRules.TIER_NEAR)
	assert_str(intent["loco_rule"]).is_equal("")


# -- cost -----------------------------------------------------------------------------------------------------------------------

func test_desired_velocity_cost_for_24_bodies() -> void:
	HazardField.register(Vector2(0, 3), HazardField.Kind.PUDDLE)
	var arch: Dictionary = MotionRules.default_registry().archetypes["villager"]
	var ctxs: Array = []
	var results: Array = []
	for k in 24:
		var c := _ctx(Vector3(k * 0.3, 0, 0), Vector3(0, 0, 1.3))
		c["oncoming_pos"] = Vector3(k * 0.3, 0, 3.0)
		c["oncoming_vel"] = Vector3(0, 0, -1.3)
		c["corridor_width"] = 1.4
		c["edge_width"] = 4.0
		c["mover_pos"] = Vector3(-8, 0, 0)
		c["mover_vel"] = Vector3(3, 0, 0)
		ctxs.append(c)
		results.append(_res())
	var t0 := Time.get_ticks_usec()
	for it in 1000:
		for k in 24:
			SteerRules.desired_velocity(results[k], ctxs[k], arch, {"id": k}, 0)
	var per_body_us := float(Time.get_ticks_usec() - t0) / 24000.0
	print("SteerRules.desired_velocity: %.2f us per body (all rules active)" % per_body_us)
	assert_float(per_body_us).is_less(150.0)       # loose: CI boxes are slow; the budget is 0.15 ms per frame for 24 bodies at 3.3 Hz
