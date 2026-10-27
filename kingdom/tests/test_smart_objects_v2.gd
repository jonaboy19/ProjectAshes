extends GdUnitTestSuite
## Smart objects schema v2 (NPC_MOTION_RULES M7): validator, defaults round-trip, O1 need-weighted find,
## O2 arrival arc, O3 side pick, O5 watcher slots.

const SmartObjects := preload("res://scripts/living_world/smart_objects.gd")
const V2_KEYS := ["approach_dir", "approach_arc", "ik", "ik_targets", "occupancy", "needs", "clip_tags", "enter"]


func _real() -> SmartObjects:
	return SmartObjects.new()


func _strip_v2(types: Dictionary) -> Dictionary:
	var out: Dictionary = types.duplicate(true)
	for name in out:
		var t: Dictionary = out[name]
		for k in V2_KEYS:
			t.erase(k)
		t.erase("_ik_unverified")
		for sl: Dictionary in t["slots"]:
			for k in V2_KEYS:
				sl.erase(k)
	return out


func _one_slot_type(extra := {}, slot_extra := {}) -> Dictionary:
	var sl := {"stand": [0.0, 0.0, 0.0], "face": 180}
	sl.merge(slot_extra, true)
	var t := {"slots": [sl], "approach": 1.0, "activity": {"loop": ["Idle"], "duration": [10, 20]}, "acts": ["work"]}
	t.merge(extra, true)
	return t


# ---------------------------------------------------------------- validator

func test_shipped_data_is_valid() -> void:
	var so := _real()
	assert_int(so.types.size()).is_equal(33)
	assert_array(SmartObjects.validate(so.types)).is_empty()


func test_every_type_has_needs_ik_targets_and_unverified_mark() -> void:
	for name in _real().types:
		var t: Dictionary = _real().types[name]
		assert_bool(t.has("needs")).override_failure_message("%s needs" % name).is_true()
		assert_bool((t.get("ik_targets", {}) as Dictionary).size() > 0).override_failure_message("%s ik_targets" % name).is_true()
		assert_bool(bool(t.get("_ik_unverified", false))).override_failure_message("%s _ik_unverified" % name).is_true()


func test_validator_reports_each_kind_of_error() -> void:
	var cases := {
		"slots_missing": [{"approach": 1.0}, "slots must be"],
		"bad_stand": [{"slots": [{"stand": "x", "face": 0}]}, "stand must be"],
		"enter_side": [_one_slot_type({"enter": {"left": "A"}}), "unknown side"],
		"enter_type": [_one_slot_type({"enter": 5}), "enter must be"],
		"arc_zero": [_one_slot_type({}, {"approach_arc": 0.0}), "approach_arc"],
		"arc_big": [_one_slot_type({}, {"approach_arc": 200}), "approach_arc"],
		"dir_vertical": [_one_slot_type({}, {"approach_dir": [0, 1, 0]}), "approach_dir"],
		"dir_short": [_one_slot_type({}, {"approach_dir": [1, 0]}), "approach_dir"],
		"ik_target_missing": [_one_slot_type({}, {"ik": [{"limb": "hand_r", "target": "nope", "weight": 1.0}]}), "not in ik_targets"],
		"ik_limb": [_one_slot_type({"ik_targets": {"a": [0, 1, 0]}}, {"ik": [{"limb": "head", "target": "a"}]}), "limb"],
		"ik_weight": [_one_slot_type({"ik_targets": {"a": [0, 1, 0]}}, {"ik": [{"limb": "hand_r", "target": "a", "weight": 2.0}]}), "weight"],
		"ik_phase": [_one_slot_type({"ik_targets": {"a": [0, 1, 0]}}, {"ik": [{"limb": "hand_r", "target": "a", "phase": [0.8, 0.2]}]}), "phase"],
		"ik_target_vec": [_one_slot_type({"ik_targets": {"a": [0, 1]}}), "ik_targets.a"],
		"occ_max": [_one_slot_type({"occupancy": {"max": 3}}), "occupancy.max"],
		"occ_ring": [_one_slot_type({"occupancy": {"watch_ring": 0.1}}), "watch_ring"],
		"occ_key": [_one_slot_type({"occupancy": {"cap": 1}}), "unknown key"],
		"need_name": [_one_slot_type({"needs": {"mana": 1.0}}), "unknown need"],
		"need_weight": [_one_slot_type({"needs": {"water": 0.0}}), "needs.water"],
		"tags": [_one_slot_type({"clip_tags": {"loop": 3}}), "clip_tags.loop"],
	}
	for key in cases:
		var errs := SmartObjects.validate({"t": cases[key][0]})
		assert_bool(errs.size() > 0).override_failure_message("%s: no error" % key).is_true()
		assert_bool(" ".join(errs).contains(cases[key][1])).override_failure_message("%s: %s" % [key, errs]).is_true()


func test_validator_accepts_a_full_v2_type() -> void:
	var t := _one_slot_type({
		"ik_targets": {"crank": [0.3, 0.9, 0.1]}, "occupancy": {"max": 1, "watchers": 2, "watch_ring": 2.2},
		"needs": {"water": 1.0}, "clip_tags": {"loop": "verb:draw_water"}},
		{"approach_dir": [0, 0, 1], "approach_arc": 70, "enter": {"front": "A", "side": "B", "back": "C"},
		"ik": [{"limb": "hand_r", "target": "crank", "weight": 1.0, "phase": [0.0, 1.0]}, {"limb": "hand_l", "target": "crank"}]})
	assert_array(SmartObjects.validate({"t": t})).is_empty()


# ---------------------------------------------------------------- defaults round-trip

func test_json_round_trip_keeps_data_valid_and_equal() -> void:
	var so := _real()
	var back = JSON.parse_string(JSON.stringify(so.types))
	assert_array(SmartObjects.validate(back)).is_empty()
	assert_int((back as Dictionary).size()).is_equal(so.types.size())
	assert_array(SmartObjects.validate(_strip_v2(so.types))).is_empty()


func test_v1_data_gets_v1_defaults() -> void:
	var so := _real()
	so.types = _strip_v2(so.types)
	for name in so.types:
		var t: Dictionary = so.types[name]
		var n := (t["slots"] as Array).size()
		assert_int(SmartObjects.occupancy_max(t)).is_equal(n)
		assert_int(SmartObjects.watchers_max(t)).is_equal(0)
		assert_float(SmartObjects.watch_ring(t)).is_equal(SmartObjects.DEFAULT_WATCH_RING)
		assert_dict(SmartObjects.needs_of(t)).is_empty()
		assert_dict(SmartObjects.ik_targets_of(t)).is_empty()
		assert_dict(SmartObjects.clip_tags_of(t)).is_empty()
		for i in n:
			assert_array(SmartObjects.ik_of(t, i)).is_empty()
			assert_float(SmartObjects.arc_of(t, i)).is_equal(180.0)


func test_v1_approach_point_and_find_unchanged_by_the_migration() -> void:
	var v1 := _real()
	v1.types = _strip_v2(v1.types)
	var v2 := _real()
	var xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(5, 0, 3))
	for name in v1.types:
		if name == "anvil" or name == "well" or name == "notice_board" or name == "shop_counter" or name == "bar_counter" or name == "market_stall":
			continue  # these declare an approach_dir/approach_arc in the shipped data (same dir, new arc)
		var a := v1.add(name, xf)
		var b := v2.add(name, xf)
		for k in (v1.types[name]["slots"] as Array).size():
			assert_vector(v2.approach_point(b, k)).is_equal_approx(v1.approach_point(a, k), Vector3.ONE * 0.003)
	# declared approach_dir equals the v1 line for the migrated types
	for name in ["anvil", "well", "notice_board", "shop_counter", "bar_counter", "market_stall"]:
		var a := v1.add(name, xf)
		var b := v2.add(name, xf)
		for k in (v1.types[name]["slots"] as Array).size():
			assert_vector(v2.approach_point(b, k)).is_equal_approx(v1.approach_point(a, k), Vector3.ONE * 0.003)
	for f in [{"act": "work", "job": "Blacksmith", "hour": 9.5}, {"act": "water"}, {"act": "rest"}, {"act": "pray"}]:
		var p1 := v1.find(Vector3(5, 0, 3), f, 60.0, 4)
		var p2 := v2.find(Vector3(5, 0, 3), f, 60.0, 4)
		assert_array(p2).is_equal(p1)


func test_default_occupancy_max_does_not_block_claims() -> void:
	var so := _real()
	var s := so.add("field_row", Transform3D.IDENTITY)   # 3 slots, no occupancy key
	for i in 3:
		assert_bool(so.claim(s, i, 10 + i)).is_true()
	assert_bool(so.is_full(s)).is_true()


func test_occupancy_max_limits_concurrent_users() -> void:
	var so := _real()
	so.types["two_slot"] = {"slots": [{"stand": [0, 0, 0], "face": 0}, {"stand": [1, 0, 0], "face": 0}],
		"activity": {"loop": ["Idle"]}, "occupancy": {"max": 1}}
	var s := so.add("two_slot", Transform3D.IDENTITY)
	assert_bool(so.claim(s, 0, 1)).is_true()
	assert_bool(so.claim(s, 1, 2)).is_false()
	assert_bool(so.claim(s, 0, 1)).is_true()   # refresh stays valid


# ---------------------------------------------------------------- O1 need-weighted find

func _table_pick(types: Array, need: Dictionary, person := 3) -> String:
	var so := _real()
	var i := 0
	for name: String in types:
		so.add(name, Transform3D(Basis.IDENTITY, Vector3(10.0 * cos(i * 1.3), 0, 10.0 * sin(i * 1.3))))
		i += 1
	var pick := so.find(Vector3.ZERO, {"needs": need}, 60.0, person)
	return "" if pick.is_empty() else String(so.spots[pick[0]]["type"])


func test_o1_need_to_type_table() -> void:
	assert_str(_table_pick(["bench", "well", "bed"], {"water": 1.0})).is_equal("well")
	assert_str(_table_pick(["bench", "bed", "tavern_table"], {"rest": 1.0})).is_equal("bed")
	assert_str(_table_pick(["bench", "chapel_kneel", "shrine_stand"], {"faith": 0.8})).is_equal("chapel_kneel")
	assert_str(_table_pick(["cook_pot", "tavern_table", "bench"], {"food": 1.0})).is_equal("tavern_table")
	assert_str(_table_pick(["bench", "conversation", "sit_ground"], {"social": 1.0})).is_equal("conversation")
	assert_str(_table_pick(["bed", "sit_ground", "well"], {"breath": 1.0})).is_equal("sit_ground")


func test_o1_skips_types_that_serve_no_wanted_need() -> void:
	assert_str(_table_pick(["anvil", "bellows", "field_row"], {"water": 1.0})).is_equal("")


func test_o1_urgency_changes_the_winner() -> void:
	var so := _real()
	var well := so.add("well", Transform3D(Basis.IDENTITY, Vector3(12, 0, 0)))
	var tavern := so.add("tavern_table", Transform3D(Basis.IDENTITY, Vector3(0, 0, 12)))
	var thirsty := so.find(Vector3.ZERO, {"needs": {"water": 1.0, "social": 0.1}}, 60.0, 1)
	var chatty := so.find(Vector3.ZERO, {"needs": {"water": 0.05, "social": 1.0}}, 60.0, 1)
	assert_int(thirsty[0]).is_equal(well)
	assert_int(chatty[0]).is_equal(tavern)


func test_o1_nearer_and_emptier_spot_wins() -> void:
	var so := _real()
	var near := so.add("well", Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)))
	var far := so.add("well", Transform3D(Basis.IDENTITY, Vector3(30, 0, 0)))
	assert_int(so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 60.0, 1)[0]).is_equal(near)
	# equal distance: the one with fewer users wins
	var so2 := _real()
	var a := so2.add("well", Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	var b := so2.add("well", Transform3D(Basis.IDENTITY, Vector3(-10, 0, 0)))
	so2.claim(a, 0, 99)
	for person in 20:
		assert_int(so2.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 60.0, person)[0]).is_equal(b)
	assert_int(far).is_not_equal(near)


func test_o1_ties_are_deterministic() -> void:
	var so := _real()
	so.add("well", Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	so.add("well", Transform3D(Basis.IDENTITY, Vector3(-10, 0, 0)))
	for person in 12:
		var first := so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 60.0, person)
		for rep in 3:
			assert_array(so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 60.0, person)).is_equal(first)


func test_o1_respects_hours_and_the_old_filter_keys() -> void:
	var so := _real()
	so.add("well", Transform3D.IDENTITY)   # hours 6..20
	assert_array(so.find(Vector3.ZERO, {"needs": {"water": 1.0}, "hour": 3.0}, 60.0, 1)).is_empty()
	assert_bool(so.find(Vector3.ZERO, {"needs": {"water": 1.0}, "hour": 9.0}, 60.0, 1).size() == 2).is_true()
	assert_array(so.find(Vector3.ZERO, {"needs": {"water": 1.0}, "type": "bench"}, 60.0, 1)).is_empty()


# ---------------------------------------------------------------- O2 arrival arc

func _bearing(so: SmartObjects, spot: int, slot: int, body: Vector3) -> float:
	var sx := so.stand_xform(spot, slot)
	return SmartObjects.yaw_between(so.approach_dir_world(spot, slot), Vector3(body.x - sx.origin.x, 0, body.z - sx.origin.z))


func test_o2_arrival_point_lies_inside_the_arc_for_100_seeded_approaches() -> void:
	var centre := Vector3(2, 0, -1)
	var dir := Vector3(0, 0, 1)
	for i in 100:
		var ang := float(absi(hash([i, 1])) % 3600) / 10.0 - 180.0
		var r := 3.0 + float(absi(hash([i, 2])) % 90) / 10.0
		var from := centre + Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(ang)) * r
		var wp := SmartObjects.arrival_point(from, centre, dir, 70.0, 1.0)
		var b := absf(SmartObjects.yaw_between(dir, wp - centre))
		assert_float(b).is_less_equal(70.0 - SmartObjects.ARC_MARGIN + 0.01)
		assert_float(wp.distance_to(centre)).is_equal_approx(1.0, 0.001)


func test_o2_inside_the_arc_arrives_along_the_bearing_without_shuffling() -> void:
	var centre := Vector3.ZERO
	var dir := Vector3(0, 0, 1)
	var from := Vector3(0, 0, 6).rotated(Vector3.UP, deg_to_rad(25.0))
	var wp := SmartObjects.arrival_point(from, centre, dir, 70.0, 1.0)
	assert_float(SmartObjects.yaw_between(dir, wp)).is_equal_approx(SmartObjects.yaw_between(dir, from), 0.01)


func test_o2_sessions_end_the_approach_inside_the_arc() -> void:
	var so := _real()
	var spot := so.add("anvil", Transform3D(Basis(Vector3.UP, 0.4), Vector3(10, 0, 10)))
	var arc := SmartObjects.arc_of(so.types["anvil"], 0)
	assert_float(arc).is_equal(70.0)
	for i in 100:
		var ang := float(absi(hash([i, 7])) % 3600) / 10.0 - 180.0
		var r := 4.0 + float(absi(hash([i, 8])) % 80) / 10.0
		var body := Vector3(10, 0, 10) + Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(ang)) * r
		so.release(i)
		assert_bool(so.claim(spot, 0, i)).is_true()
		var s := so.session(i, spot, 0)
		var steps := 0
		while s.phase == SmartObjects.Session.APPROACH and steps < 2000:
			var out := s.update(1.0 / 30.0, body, false)
			if out["move_to"] != null:
				var to: Vector3 = (out["move_to"] as Vector3) - body
				to.y = 0.0
				body += to.limit_length(1.4 / 30.0 * float(out["speed_scale"]))
			steps += 1
		assert_int(s.phase).is_equal(SmartObjects.Session.ALIGN)
		assert_float(absf(_bearing(so, spot, 0, body))).is_less_equal(arc)
		s.cancel_now()


func test_o2_slows_over_the_last_metre_and_a_bit() -> void:
	assert_float(SmartObjects.arrival_speed(5.0)).is_equal(1.0)
	assert_float(SmartObjects.arrival_speed(SmartObjects.SLOW_DIST)).is_equal(1.0)
	assert_float(SmartObjects.arrival_speed(0.6)).is_equal_approx(0.5, 0.001)
	assert_float(SmartObjects.arrival_speed(0.0)).is_equal(SmartObjects.SLOW_MIN)
	var so := _real()
	var spot := so.add("anvil", Transform3D.IDENTITY)
	so.claim(spot, 0, 1)
	var s := so.session(1, spot, 0)
	assert_float(float(s.update(0.03, Vector3(0, 0, 9), false)["speed_scale"])).is_equal(1.0)
	var near := s.update(0.03, so.approach_point(spot, 0) + Vector3(0, 0, 0.7), false)
	assert_float(float(near["speed_scale"])).is_less(0.7)


func test_o2_v1_slots_still_walk_straight_to_the_approach_point() -> void:
	var so := _real()
	var spot := so.add("bellows", Transform3D.IDENTITY)   # no approach_arc
	so.claim(spot, 0, 1)
	var s := so.session(1, spot, 0)
	var out := s.update(0.03, Vector3(7, 0, -4), false)
	assert_vector(out["move_to"] as Vector3).is_equal_approx(so.approach_point(spot, 0), Vector3.ONE * 0.0001)


# ---------------------------------------------------------------- O3 side pick

func test_o3_side_classification() -> void:
	for c in [[0.0, "front"], [44.0, "front"], [-44.0, "front"], [46.0, "side"], [-90.0, "side"], [135.0, "side"],
			[136.0, "back"], [-170.0, "back"], [180.0, "back"]]:
		assert_str(SmartObjects.classify_side(c[0])).override_failure_message("%s" % [c]).is_equal(c[1])


func test_o3_enter_resolution_and_fallbacks() -> void:
	var spec := {"front": "F", "side": "S", "back": "B"}
	assert_str(SmartObjects.resolve_enter(spec, "side")).is_equal("S")
	assert_str(SmartObjects.resolve_enter(spec, "back")).is_equal("B")
	assert_str(SmartObjects.resolve_enter({"front": "F"}, "side", "single")).is_equal("F")
	assert_str(SmartObjects.resolve_enter({"back": "B"}, "side", "single")).is_equal("single")
	assert_str(SmartObjects.resolve_enter("one", "back")).is_equal("one")
	assert_str(SmartObjects.resolve_enter("", "back", "single")).is_equal("single")
	assert_str(SmartObjects.resolve_enter(null, "front")).is_equal("")


func _run_to_enter(so: SmartObjects, spot: int, body: Vector3) -> SmartObjects.Session:
	assert_bool(so.claim(spot, 0, 5)).is_true()
	var s := so.session(5, spot, 0)
	var steps := 0
	while s.phase != SmartObjects.Session.ENTER and s.phase != SmartObjects.Session.DONE and steps < 3000:
		var out := s.update(1.0 / 30.0, body, false)
		if out["move_to"] != null:
			var to: Vector3 = (out["move_to"] as Vector3) - body
			to.y = 0.0
			body += to.limit_length(1.4 / 30.0)
		steps += 1
	return s


func test_o3_session_picks_the_enter_clip_for_the_arrival_side() -> void:
	var enter := {"front": "Enter_F", "side": "Enter_S", "back": "Enter_B"}
	var cases := {"front": Vector3(0, 0, 8), "side": Vector3(8, 0, 0.2), "back": Vector3(0, 0, -8)}
	for want in cases:
		var so := _real()
		so.types["seat_t"] = _one_slot_type({}, {"stand": [0.0, 0.0, 0.0], "face": 180, "enter": enter, "approach_arc": 175.0})
		var spot := so.add("seat_t", Transform3D.IDENTITY)
		var s := _run_to_enter(so, spot, cases[want])
		assert_str(s.side).is_equal(want)
		assert_int(s.phase).is_equal(SmartObjects.Session.ENTER)
		assert_str(s.clip).is_equal(enter[want])


func test_o3_string_enter_and_activity_enter_still_work() -> void:
	var so := _real()
	var spot := so.add("anvil", Transform3D.IDENTITY)   # activity.enter is a single string
	var s := _run_to_enter(so, spot, Vector3(5, 0, 5))
	assert_str(s.clip).is_equal("Life_Smith_Hammer_Enter")


# ---------------------------------------------------------------- O5 watcher slots

func test_o5_watchers_need_a_full_spot_and_slots_are_unique() -> void:
	var so := _real()
	var anvil := so.add("anvil", Transform3D.IDENTITY)   # 1 slot, 2 watchers, ring 2.2
	assert_bool(so.claim_watch(anvil, 0, 20)).is_false()   # nobody working yet
	so.claim(anvil, 0, 1)
	assert_bool(so.is_full(anvil)).is_true()
	assert_bool(so.claim_watch(anvil, 0, 20)).is_true()
	assert_bool(so.claim_watch(anvil, 0, 21)).is_false()   # taken
	assert_bool(so.claim_watch(anvil, 0, 20)).is_true()    # idempotent for the owner
	assert_bool(so.claim_watch(anvil, 1, 21)).is_true()
	assert_bool(so.claim_watch(anvil, 2, 22)).is_false()   # only 2 watchers
	assert_array(so.watching(21)).is_equal([anvil, 1])
	so.release_watch(20)
	assert_bool(so.claim_watch(anvil, 0, 22)).is_true()


func test_o5_watch_points_are_on_the_ring_distinct_and_face_the_object() -> void:
	var so := _real()
	var anvil := so.add("anvil", Transform3D(Basis(Vector3.UP, 0.9), Vector3(4, 0, 4)))
	var p0 := so.watch_point(anvil, 0)
	var p1 := so.watch_point(anvil, 1)
	for p in [p0, p1]:
		assert_float(Vector2(p.x - 4.0, p.z - 4.0).length()).is_equal_approx(2.2, 0.001)
	assert_float(p0.distance_to(p1)).is_greater(0.8)
	var f := so.watch_face(anvil, 0)
	var to := Vector3(4, 0, 4) - p0
	assert_float(Vector3(sin(f), 0, cos(f)).dot(to.normalized())).is_equal_approx(1.0, 0.001)


func test_o5_find_watch_returns_a_full_spot_with_a_free_slot_and_nothing_otherwise() -> void:
	var so := _real()
	var near := so.add("anvil", Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	var far := so.add("anvil", Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)))
	assert_array(so.find_watch(Vector3.ZERO, {"type": "anvil"}, 40.0, 30)).is_empty()
	so.claim(far, 0, 1)
	assert_array(so.find_watch(Vector3.ZERO, {"type": "anvil"}, 40.0, 30)).is_equal([far, 0])
	so.claim(near, 0, 2)
	assert_array(so.find_watch(Vector3.ZERO, {"type": "anvil"}, 40.0, 30)).is_equal([near, 0])
	so.claim_watch(near, 0, 30)
	so.claim_watch(near, 1, 31)
	assert_array(so.find_watch(Vector3.ZERO, {"type": "anvil"}, 40.0, 32)).is_equal([far, 0])
	assert_array(so.find_watch(Vector3.ZERO, {"type": "anvil"}, 40.0, 30)).is_equal([near, 0])   # keeps its own slot
	assert_array(so.find_watch(Vector3.ZERO, {"type": "bench"}, 40.0, 32)).is_empty()


func test_o5_taking_a_work_slot_releases_the_watch() -> void:
	var so := _real()
	var anvil := so.add("anvil", Transform3D.IDENTITY)
	var other := so.add("well", Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)))
	so.claim(anvil, 0, 1)
	so.claim_watch(anvil, 0, 40)
	so.claim(other, 0, 40)
	assert_array(so.watching(40)).is_empty()
	assert_bool(so.claim_watch(anvil, 0, 41)).is_true()


func test_o5_types_without_watchers_have_none() -> void:
	var so := _real()
	var bell := so.add("bellows", Transform3D.IDENTITY)
	so.claim(bell, 0, 1)
	assert_bool(so.claim_watch(bell, 0, 2)).is_false()
	assert_array(so.find_watch(Vector3.ZERO, {}, 40.0, 2)).is_empty()


# ---------------------------------------------------------------- budgets (printed; loose limits)

func test_budget_find_with_needs_and_session_update() -> void:
	var so := _real()
	var names: Array = so.types.keys()
	for i in 400:
		so.add(names[i % names.size()], Transform3D(Basis.IDENTITY, Vector3(float(i % 20) * 6.0, 0, float(i / 20) * 6.0)))
	var f := {"needs": {"water": 0.8, "social": 0.3}}
	var t0 := Time.get_ticks_usec()
	for i in 200:
		so.find(Vector3(60, 0, 60), f, 60.0, i)
	var per_find := float(Time.get_ticks_usec() - t0) / 200.0
	var t1 := Time.get_ticks_usec()
	for i in 200:
		so.find(Vector3(60, 0, 60), {"act": "work"}, 60.0, i)
	var per_old := float(Time.get_ticks_usec() - t1) / 200.0
	var anvil := so.add("anvil", Transform3D.IDENTITY)
	so.claim(anvil, 0, 9001)
	var s := so.session(9001, anvil, 0)
	var t2 := Time.get_ticks_usec()
	for i in 10000:
		s.update(0.001, Vector3(30, 0, 30), false)
	var per_update := float(Time.get_ticks_usec() - t2) / 10000.0
	print("M7 BUDGET  find(needs, 400 spots) %.1f us   find(old filter) %.1f us   Session.update(APPROACH, arc) %.2f us" % [per_find, per_old, per_update])
	assert_float(per_find).is_less(3000.0)
	assert_float(per_update).is_less(100.0)


func test_yaw_between_matches_vector_rotation() -> void:
	for deg in [-170.0, -90.0, -25.0, 0.0, 30.0, 120.0]:
		var a := Vector3(0.3, 0, 1.0).normalized()
		var b := a.rotated(Vector3.UP, deg_to_rad(deg))
		assert_float(SmartObjects.yaw_between(a, b)).is_equal_approx(deg, 0.01)
