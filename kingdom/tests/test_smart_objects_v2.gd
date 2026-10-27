extends GdUnitTestSuite
## Smart objects schema v2 (docs/plans/NPC_MOTION_RULES.md 3.4): validator, defaults round-trip,
## O1 need-weighted find, O2 arrival arc, O3 side pick, O5 watcher slots.

const SmartObjects := preload("res://scripts/living_world/smart_objects.gd")

## Legacy-shaped type: no v2 key anywhere.
const LEGACY := {
	"slots": [{"stand": [0.0, 0.0, 0.5], "face": 180}, {"stand": [1.0, 0.0, 0.5], "face": 180}],
	"approach": 1.0,
	"activity": {"enter": "Enter_A", "loop": ["Loop_A"], "exit": "Exit_A", "duration": [10, 20]},
	"acts": ["work"], "hours": [6, 20], "tags": ["t"],
}


func _so() -> SmartObjects:
	return SmartObjects.new()


func _type(extra := {}, slots := []) -> Dictionary:
	var t: Dictionary = LEGACY.duplicate(true)
	if not slots.is_empty():
		t["slots"] = slots
	t.merge(extra, true)
	return t


func _strip_v2(types: Dictionary) -> Dictionary:
	var out: Dictionary = types.duplicate(true)
	for k: String in out:
		for key in ["needs", "ik_targets", "ik", "occupancy", "approach_arc", "approach_dir", "clip_tags", "_ik_unverified"]:
			(out[k] as Dictionary).erase(key)
	return out


# ---------------------------------------------------------------- validator

func test_shipped_data_validates_clean() -> void:
	var so := _so()
	assert_array(SmartObjects.validate(so.types)).is_empty()
	assert_int(so.types.size()).is_equal(33)


func test_every_shipped_type_has_needs_ik_targets_and_the_unverified_flag() -> void:
	var so := _so()
	for name: String in so.types:
		var t: Dictionary = so.types[name]
		assert_bool((t.get("needs", {}) as Dictionary).is_empty()).override_failure_message(name + " needs").is_false()
		assert_bool((t.get("ik_targets", {}) as Dictionary).is_empty()).override_failure_message(name + " ik_targets").is_false()
		assert_bool(bool(t.get("_ik_unverified", false))).override_failure_message(name + " _ik_unverified").is_true()


func test_validator_flags_each_bad_value() -> void:
	var bad := {
		"arc_hi": _type({"approach_arc": 200}),
		"arc_zero": _type({"approach_arc": 0}),
		"dir_zero": _type({"approach_dir": [0, 0, 0]}),
		"dir_len": _type({"approach_dir": [1, 0]}),
		"enter_key": _type({"enter": {"left": "X"}}),
		"enter_empty": _type({"enter": {}}),
		"enter_type": _type({"enter": 5}),
		"ik_unknown_target": _type({"ik": [{"limb": "hand_r", "target": "nope", "weight": 1.0}], "ik_targets": {"a": [0, 0, 0]}}),
		"ik_limb": _type({"ik": [{"limb": "elbow", "target": "a", "weight": 1.0}], "ik_targets": {"a": [0, 0, 0]}}),
		"ik_weight": _type({"ik": [{"limb": "hand_r", "target": "a", "weight": 2.0}], "ik_targets": {"a": [0, 0, 0]}}),
		"ik_phase": _type({"ik": [{"limb": "hand_r", "target": "a", "weight": 1.0, "phase": [0.8, 0.2]}], "ik_targets": {"a": [0, 0, 0]}}),
		"ik_target_vec": _type({"ik_targets": {"a": [0, 0]}}),
		"occ_max": _type({"occupancy": {"max": 0}}),
		"occ_watchers": _type({"occupancy": {"watchers": -1}}),
		"occ_ring": _type({"occupancy": {"watch_ring": -2.0}}),
		"occ_key": _type({"occupancy": {"watchres": 2}}),
		"needs_neg": _type({"needs": {"water": -1.0}}),
		"needs_str": _type({"needs": {"water": "lots"}}),
		"tags_type": _type({"clip_tags": {"loop": 3}}),
		"no_slots": {"slots": []},
		"bad_stand": _type({}, [{"stand": "somewhere", "face": 0}]),
		"slot_arc": _type({}, [{"stand": [0, 0, 0], "face": 0, "approach_arc": 999}]),
	}
	var errs := SmartObjects.validate(bad)
	for name: String in bad:
		var hit := false
		for e in errs:
			if e.begins_with(name + ":") or e.begins_with(name + "/"):
				hit = true
				break
		assert_bool(hit).override_failure_message("validator missed " + name).is_true()


func test_validator_accepts_full_v2_block() -> void:
	var ok := {"good": _type({
		"approach_arc": 70, "approach_dir": [0, 0, 1],
		"enter": {"front": "A", "side": "B", "back": "C"}, "exit": "D",
		"ik_targets": {"a": [0.1, 0.9, 0.2]},
		"ik": [{"limb": "hand_r", "target": "a", "weight": 0.8, "phase": [0.0, 1.0]}, {"limb": "hand_l", "target": "a", "weight": 1.0, "phase": "loop"}],
		"occupancy": {"max": 2, "watchers": 3, "watch_ring": 2.2},
		"needs": {"water": 1.0}, "clip_tags": {"loop": "verb:draw_water"}})}
	assert_array(SmartObjects.validate(ok)).is_empty()


# ---------------------------------------------------------------- defaults round trip

func test_defaults_for_a_legacy_type_behave_like_the_old_code() -> void:
	var so := _so()
	so.types["legacy"] = _type()
	var id := so.add("legacy", Transform3D(Basis(Vector3.UP, 0.7), Vector3(10, 0, 4)))
	assert_float(so.approach_arc(id, 0)).is_equal(180.0)
	assert_bool(so.declares_arc(id, 0)).is_false()
	assert_vector(so.arrival_point(id, 0, Vector3(40, 0, -30))).is_equal_approx(so.approach_point(id, 0), Vector3.ONE * 0.0001)
	assert_int(so.max_users(id)).is_equal(2)
	assert_int(so.watch_capacity(id)).is_equal(0)
	assert_float(so.watch_ring(id)).is_equal(SmartObjects.DEFAULT_WATCH_RING)
	assert_array(so.ik_list(id, 0)).is_empty()
	assert_dict(so.needs_of("legacy")).is_empty()
	assert_str(so.clip_tag(id, 0, "loop")).is_equal("")
	for side in SmartObjects.SIDES:
		assert_str(so.enter_clip(id, 0, side)).is_equal("Enter_A")
		assert_str(so.exit_clip(id, 0, side)).is_equal("Exit_A")
	# default approach axis = straight back out of the stand point = the old approach_point direction
	var sx := so.stand_xform(id, 0)
	var back := -sx.basis.z
	assert_vector(so.approach_axis(id, 0)).is_equal_approx(back.normalized(), Vector3.ONE * 0.0001)


func test_stripping_v2_keys_does_not_change_old_filter_results() -> void:
	var full := _so()
	var old := _so()
	old.types = _strip_v2(full.types)
	var names := ["well", "bench", "anvil", "cook_pot", "bar_counter", "chapel_kneel", "market_stall", "notice_board", "hopscotch", "bed"]
	for i in names.size():
		var xf := Transform3D(Basis(Vector3.UP, float(i) * 0.6), Vector3(float(i) * 7.0, 0, float(i * 3 % 11)))
		full.add(names[i], xf)
		old.add(names[i], xf)
	for fi in 6:
		var f := {"act": ["work", "rest", "water", "pray", "social", "shop"][fi], "hour": 10.0 + float(fi)}
		for person in [3, 17, 901]:
			assert_array(full.find(Vector3(20, 0, 5), f, 80.0, person)).is_equal(old.find(Vector3(20, 0, 5), f, 80.0, person))
	# the stand / approach geometry of every slot is identical when no arc is declared
	for k in full.spots.size():
		if full.declares_arc(k, 0):
			continue
		assert_vector(full.approach_point(k, 0)).is_equal(old.approach_point(k, 0))


func test_types_json_round_trips() -> void:
	var so := _so()
	var text := JSON.stringify(so.types)
	var back = JSON.parse_string(text)
	assert_array(SmartObjects.validate(back)).is_empty()
	assert_dict(back).is_equal(so.types)


# ---------------------------------------------------------------- O1 need-weighted find

func test_types_for_need_table_is_sorted_and_deterministic() -> void:
	var so := _so()
	var water := so.types_for_need("water")
	assert_str(water[0]).is_equal("well")
	assert_array(water).contains(["well", "bar_counter"])
	assert_array(so.types_for_need("water")).is_equal(water)
	assert_array(so.types_for_need("nonexistent")).is_empty()
	assert_str(so.types_for_need("sleep")[0]).is_equal("bed")
	assert_str(so.types_for_need("pray")[0]).is_equal("chapel_kneel")


func test_need_find_prefers_the_matching_type_over_the_nearest_one() -> void:
	var so := _so()
	so.add("bench", Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	so.add("anvil", Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)))
	var well := so.add("well", Transform3D(Basis.IDENTITY, Vector3(25, 0, 0)))
	var pick := so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 60.0, 5)
	assert_int(pick[0]).is_equal(well)
	assert_array(so.find(Vector3.ZERO, {"needs": {"sleep": 1.0}}, 60.0, 5)).is_empty()


func test_need_find_weights_distance_occupancy_and_urgency() -> void:
	var so := _so()
	var near := so.add("well", Transform3D(Basis.IDENTITY, Vector3(8, 0, 0)))
	var far := so.add("well", Transform3D(Basis.IDENTITY, Vector3(40, 0, 0)))
	assert_int(so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 80.0, 1)[0]).is_equal(near)
	# the near well is full (max 2): the far one wins
	assert_bool(so.claim(near, 0, 100)).is_true()
	assert_bool(so.claim(near, 1, 101)).is_true()
	assert_int(so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 80.0, 1)[0]).is_equal(far)
	so.release(100)
	so.release(101)
	# half occupied is a penalty but near still wins
	so.claim(near, 0, 100)
	assert_int(so.find(Vector3.ZERO, {"needs": {"water": 1.0}}, 80.0, 1)[0]).is_equal(near)
	# urgency scales the utility, not the choice, for a single need
	var u_low := so.need_utility(near, 1, {"water": 0.2}, Vector3.ZERO, -1.0)
	var u_high := so.need_utility(near, 1, {"water": 1.0}, Vector3.ZERO, -1.0)
	assert_float(u_high).is_greater(u_low)
	# a second need blends in: bar_counter satisfies water 0.4 and fun 0.8
	var bar := so.add("bar_counter", Transform3D(Basis.IDENTITY, Vector3(8, 0, 2)))
	var both := {"fun": 1.0, "water": 0.3}
	assert_float(so.need_utility(bar, 0, both, Vector3.ZERO, -1.0)).is_greater(so.need_utility(near, 0, both, Vector3.ZERO, -1.0))


func test_need_find_honours_hours_and_skips_disabled_types() -> void:
	var so := _so()
	so.add("wash_tub", Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	assert_array(so.find(Vector3.ZERO, {"needs": {"hygiene": 1.0}}, 60.0, 1)).is_empty()
	assert_array(so.find(Vector3.ZERO, {"needs": {"hygiene": 1.0}, "hour": 10.0}, 60.0, 1)).is_empty()
	var well := so.add("well", Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)))
	assert_int(so.find(Vector3.ZERO, {"needs": {"water": 1.0}, "hour": 12.0}, 60.0, 1)[0]).is_equal(well)
	assert_array(so.find(Vector3.ZERO, {"needs": {"water": 1.0}, "hour": 23.0}, 60.0, 1)).is_empty()
	# fading near the edge of the opening hours
	assert_float(so.need_utility(well, 0, {"water": 1.0}, Vector3.ZERO, 6.1)).is_less(so.need_utility(well, 0, {"water": 1.0}, Vector3.ZERO, 12.0))


func test_need_find_ties_break_deterministically() -> void:
	var a := _so()
	var b := _so()
	for so in [a, b]:
		so.add("bench", Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)))
		so.add("bench", Transform3D(Basis.IDENTITY, Vector3(-6, 0, 0)))
		so.add("bench", Transform3D(Basis.IDENTITY, Vector3(0, 0, 6)))
	for person in range(0, 40):
		var pa := a.find(Vector3.ZERO, {"needs": {"rest": 1.0}}, 30.0, person)
		var pb := b.find(Vector3.ZERO, {"needs": {"rest": 1.0}}, 30.0, person)
		assert_array(pa).is_equal(pb)
		assert_bool(pa.size() == 2).is_true()
	# a person keeps the slot they hold (hysteresis)
	var first := a.find(Vector3.ZERO, {"needs": {"rest": 1.0}}, 30.0, 77)
	a.claim(first[0], first[1], 77)
	assert_array(a.find(Vector3.ZERO, {"needs": {"rest": 1.0}}, 30.0, 77)).is_equal(first)
	# an exact geometric tie (mirror-image shrines) resolves the same way every call and on every instance
	var picks := []
	for k in 2:
		var c := _so()
		c.add("shrine_stand", Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)))
		c.add("shrine_stand", Transform3D(Basis.IDENTITY, Vector3(-4, 0, 0)))
		picks.append(c.find(Vector3.ZERO, {"needs": {"pray": 1.0}}, 30.0))
		picks.append(c.find(Vector3.ZERO, {"needs": {"pray": 1.0}}, 30.0))
	assert_array(picks[0]).is_equal(picks[1])
	assert_array(picks[0]).is_equal(picks[2])
	assert_array(picks[0]).is_equal(picks[3])


func test_old_filter_is_unchanged_by_the_needs_key_being_absent() -> void:
	var so := _so()
	so.add("bench", Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	var well := so.add("well", Transform3D(Basis.IDENTITY, Vector3(25, 0, 0)))
	var rest := so.find(Vector3.ZERO, {"act": "rest"}, 60.0, 5)
	assert_int(rest[0]).is_equal(0)
	assert_int(so.find(Vector3.ZERO, {"act": "water"}, 60.0, 5)[0]).is_equal(well)


# ---------------------------------------------------------------- O2 arrival arc

func _walk_to_align(so: SmartObjects, spot: int, person: int, start: Vector3) -> Dictionary:
	assert_bool(so.claim(spot, 0, person)).is_true()
	var s := so.session(person, spot, 0, person)
	var body := start
	var min_scale := 1.0
	var steps := 0
	var first_move := Vector3.INF
	while s.phase == SmartObjects.Session.APPROACH and steps < 4000:
		var out := s.update(1.0 / 30.0, body, false)
		if out["move_to"] != null:
			var tgt: Vector3 = out["move_to"]
			if first_move == Vector3.INF:
				first_move = tgt
			var scale := float(out.get("speed_scale", 1.0))
			min_scale = minf(min_scale, scale)
			var step := tgt - body
			step.y = 0.0
			var len := minf(step.length(), 1.4 * scale / 30.0)
			if step.length() > 0.0001:
				body += step.normalized() * len
		steps += 1
	return {"body": body, "steps": steps, "session": s, "first": first_move, "min_scale": min_scale}


func _arrival_angle_deg(so: SmartObjects, spot: int, body: Vector3) -> float:
	var sx := so.stand_xform(spot, 0)
	var v := Vector3(body.x - sx.origin.x, 0.0, body.z - sx.origin.z).normalized()
	return rad_to_deg(absf(so.approach_axis(spot, 0).signed_angle_to(v, Vector3.UP)))


func test_arrival_lands_inside_the_declared_arc_for_100_seeded_approaches() -> void:
	var so := _so()
	var cases := [["well", 70.0], ["bellows", 80.0], ["bench", 100.0], ["shrine_stand", 60.0]]
	var worst := 0.0
	var n := 0
	for c in cases:
		for i in 25:
			var yaw := float(absi(hash([c[0], i, "yaw"])) % 628) / 100.0
			var spot := so.add(c[0], Transform3D(Basis(Vector3.UP, yaw), Vector3(float(n) * 30.0, 0, 0)))
			var ang := float(absi(hash([c[0], i, "ang"])) % 628) / 100.0
			var rad := 4.0 + float(absi(hash([c[0], i, "rad"])) % 80) / 10.0
			var o := (so.spots[spot]["xform"] as Transform3D).origin
			var r := _walk_to_align(so, spot, 1000 + n, o + Vector3(sin(ang), 0, cos(ang)) * rad)
			assert_int(int(r["session"].phase)).is_equal(SmartObjects.Session.ALIGN)
			var a := _arrival_angle_deg(so, spot, r["body"])
			worst = maxf(worst, a - float(c[1]))
			assert_float(a).is_less_equal(float(c[1]) + 0.5)
			so.release(1000 + n)
			n += 1
	assert_int(n).is_equal(100)
	print("[M7] worst arrival excess over arc: %.2f deg" % worst)


func test_slow_down_over_the_last_1_2_m_and_no_arc_keeps_the_old_target() -> void:
	var so := _so()
	var well := so.add("well", Transform3D.IDENTITY)
	var r := _walk_to_align(so, well, 1, Vector3(0, 0, 9))
	assert_float(float(r["min_scale"])).is_less(1.0)
	assert_float(float(r["min_scale"])).is_greater_equal(SmartObjects.SLOW_MIN - 0.0001)
	# far from the target the scale is 1.0
	so.release(1)
	so.claim(well, 0, 2)
	var s := so.session(2, well, 0, 2)
	assert_float(float(s.update(0.033, Vector3(0, 0, 12), false).get("speed_scale", 0.0))).is_equal(1.0)
	# a type with no declared arc walks to exactly the old approach point
	so.types["legacy"] = _type()
	var id := so.add("legacy", Transform3D(Basis(Vector3.UP, 1.1), Vector3(20, 0, 20)))
	so.claim(id, 0, 3)
	var s2 := so.session(3, id, 0, 3)
	var out := s2.update(0.033, Vector3(35, 0, 5), false)
	assert_vector(out["move_to"]).is_equal_approx(so.approach_point(id, 0), Vector3.ONE * 0.0001)


# ---------------------------------------------------------------- O3 side pick

func test_side_classification_front_side_back() -> void:
	var so := _so()
	so.types["t"] = _type({"approach_arc": 170})
	var id := so.add("t", Transform3D(Basis(Vector3.UP, 0.4), Vector3(3, 0, 3)))
	var sx := so.stand_xform(id, 0)
	var axis := so.approach_axis(id, 0)
	assert_str(so.classify_side(id, 0, sx.origin + axis * 4.0)).is_equal("front")
	assert_str(so.classify_side(id, 0, sx.origin + axis.rotated(Vector3.UP, deg_to_rad(20)) * 4.0)).is_equal("front")
	assert_str(so.classify_side(id, 0, sx.origin + axis.rotated(Vector3.UP, deg_to_rad(90)) * 4.0)).is_equal("side")
	assert_str(so.classify_side(id, 0, sx.origin + axis.rotated(Vector3.UP, deg_to_rad(-90)) * 4.0)).is_equal("side")
	assert_str(so.classify_side(id, 0, sx.origin - axis * 4.0)).is_equal("back")
	assert_str(so.classify_side(id, 0, sx.origin + axis.rotated(Vector3.UP, deg_to_rad(160)) * 4.0)).is_equal("back")


func test_enter_clip_resolution_and_fallbacks() -> void:
	var so := _so()
	so.types["t"] = _type({"activity": {"enter": {"front": "F", "side": "S"}, "exit": "X", "loop": ["L"]}})
	so.types["t2"] = _type({"activity": {"enter": "Plain", "exit": {"front": "XF", "back": "XB"}, "loop": ["L"]}}, [
		{"stand": [0, 0, 0], "face": 0, "enter": {"front": "SlotF", "side": "SlotS"}},
		{"stand": [1, 0, 0], "face": 0}])
	var a := so.add("t", Transform3D.IDENTITY)
	var b := so.add("t2", Transform3D.IDENTITY)
	assert_str(so.enter_clip(a, 0, "front")).is_equal("F")
	assert_str(so.enter_clip(a, 0, "side")).is_equal("S")
	assert_str(so.enter_clip(a, 0, "back")).is_equal("F")   # missing side -> front
	assert_str(so.exit_clip(a, 0, "side")).is_equal("X")     # string exit serves every side
	assert_str(so.enter_clip(b, 0, "side")).is_equal("SlotS")  # slot overrides the activity
	assert_str(so.enter_clip(b, 0, "back")).is_equal("SlotF")
	assert_str(so.enter_clip(b, 1, "side")).is_equal("Plain")  # slot without enter -> activity string
	assert_str(so.exit_clip(b, 0, "back")).is_equal("XB")
	assert_str(so.exit_clip(b, 0, "side")).is_equal("XF")
	assert_str(SmartObjects.pick_clip(7, "front")).is_equal("")
	assert_str(SmartObjects.pick_clip({"back": "B"}, "front")).is_equal("")


func test_session_plays_the_enter_clip_of_the_side_it_came_from() -> void:
	var so := _so()
	so.types["t"] = _type({
		"approach_arc": 130,
		"activity": {"enter": {"front": "Enter_F", "side": "Enter_S", "back": "Enter_B"}, "exit": {"front": "Exit_F", "side": "Exit_S"},
			"loop": ["Loop_A"], "duration": [10, 20]}})
	var seen := {}
	for ang in [0.0, 90.0, -90.0, 180.0]:
		var id := so.add("t", Transform3D(Basis.IDENTITY, Vector3(float(seen.size()) * 20.0, 0, 0)))
		var axis := so.approach_axis(id, 0)
		var sx := so.stand_xform(id, 0)
		var start := sx.origin + axis.rotated(Vector3.UP, deg_to_rad(ang)) * 7.0
		var person := 50 + seen.size()
		so.claim(id, 0, person)
		var s := so.session(person, id, 0, person)
		var body := start
		var guard := 0
		while s.phase != SmartObjects.Session.ENTER and guard < 4000:
			var out := s.update(1.0 / 30.0, body, false)
			if out["move_to"] != null:
				var step: Vector3 = (out["move_to"] as Vector3) - body
				step.y = 0.0
				body += step.normalized() * minf(step.length(), 0.06) if step.length() > 0.0001 else Vector3.ZERO
			guard += 1
		assert_int(s.phase).is_equal(SmartObjects.Session.ENTER)
		seen[ang] = s.clip
		# the exit reuses the side (and the `act` dictionary the hot files read is already resolved to a string)
		assert_str(String(s.act.get("exit", ""))).is_not_empty()
	assert_str(seen[0.0]).is_equal("Enter_F")
	assert_str(seen[90.0]).is_equal("Enter_S")
	assert_str(seen[-90.0]).is_equal("Enter_S")
	# 180 deg is clamped to the 130 deg arc * 0.9 = 117 deg: still a side entry
	assert_str(seen[180.0]).is_equal("Enter_S")


func test_session_act_exit_is_a_plain_string_for_side_exits() -> void:
	var so := _so()
	so.types["t"] = _type({"approach_arc": 130, "activity": {"enter": "E", "exit": {"front": "Exit_F", "side": "Exit_S"}, "loop": ["L"]}})
	var id := so.add("t", Transform3D.IDENTITY)
	so.claim(id, 0, 9)
	var s := so.session(9, id, 0, 9)
	assert_str(String(s.act.get("exit"))).is_equal("Exit_F")   # before the approach side is known: front
	var sx := so.stand_xform(id, 0)
	s.update(0.033, sx.origin + so.approach_axis(id, 0).rotated(Vector3.UP, deg_to_rad(100)) * 6.0, false)
	assert_str(String(s.act.get("exit"))).is_equal("Exit_S")


# ---------------------------------------------------------------- O5 occupancy / watchers

func test_watcher_slots_are_unique_capped_and_released() -> void:
	var so := _so()
	so.types["t"] = _type({"occupancy": {"max": 1, "watchers": 3, "watch_ring": 2.4}})
	var id := so.add("t", Transform3D(Basis(Vector3.UP, 0.5), Vector3(10, 0, 10)))
	assert_bool(so.claim(id, 0, 1)).is_true()
	assert_bool(so.claim(id, 1, 2)).is_false()   # max 1 user even though the type has 2 slots
	assert_int(so.watch_capacity(id)).is_equal(3)
	var slots := []
	for p in [2, 3, 4]:
		slots.append(so.claim_watch(id, p))
	assert_array(slots).is_equal([0, 1, 2])
	assert_int(so.claim_watch(id, 5)).is_equal(-1)
	assert_int(so.watcher_count(id)).is_equal(3)
	assert_int(so.claim_watch(id, 3)).is_equal(1)   # idempotent
	# positions: on the ring, distinct, facing the object
	var origin := Vector3(10, 0, 10)
	var pts := []
	for i in 3:
		var w := so.watch_xform(id, i)
		assert_float(Vector2(w.origin.x - origin.x, w.origin.z - origin.z).length()).is_equal_approx(2.4, 0.001)
		var to_obj := (origin - w.origin)
		to_obj.y = 0.0
		assert_float(w.basis.z.dot(to_obj.normalized())).is_greater(0.999)
		for q in pts:
			assert_float((q as Vector3).distance_to(w.origin)).is_greater(0.5)
		pts.append(w.origin)
	so.release_watch(3)
	assert_int(so.claim_watch(id, 5)).is_equal(1)
	# releasing the person releases the watch too
	so.release(5)
	assert_int(so.watcher_count(id)).is_equal(2)
	# a user cannot also watch the same spot slot-free: holders keep working
	so.release(1)
	assert_bool(so.claim(id, 0, 6)).is_true()


func test_types_without_watchers_never_hand_out_watch_slots() -> void:
	var so := _so()
	so.types["t"] = _type()
	var id := so.add("t", Transform3D.IDENTITY)
	assert_int(so.claim_watch(id, 1)).is_equal(-1)
	assert_int(so.watcher_count(id)).is_equal(0)


func test_find_skips_full_spots_and_watch_pick_returns_a_free_ring_slot() -> void:
	var so := _so()
	var anvil := so.add("anvil", Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)))
	assert_int(so.find(Vector3.ZERO, {"act": "work", "job": "Blacksmith"}, 60.0, 1)[0]).is_equal(anvil)
	so.claim(anvil, 0, 1)
	assert_array(so.find(Vector3.ZERO, {"act": "work", "job": "Blacksmith"}, 60.0, 2)).is_empty()
	# watchers: the smith's anvil is full, a passer-by gets a ring slot
	var w := so.watch_pick(Vector3.ZERO, {"type": "anvil"}, 60.0, 2)
	assert_array(w).is_equal([anvil, 0])
	assert_int(so.claim_watch(w[0], 2)).is_equal(0)
	assert_array(so.watch_pick(Vector3.ZERO, {"type": "anvil"}, 60.0, 3)).is_equal([anvil, 1])
	# a free spot is used, not watched
	var free := so.add("anvil", Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)))
	assert_array(so.watch_pick(Vector3.ZERO, {"type": "anvil"}, 60.0, 4)).is_empty()
	so.claim(free, 0, 9)
	# both anvils full, the first ring has 1 free slot -> index 1 for the next person
	assert_array(so.watch_pick(Vector3.ZERO, {"type": "anvil"}, 60.0, 4)).is_equal([anvil, 1])


func test_watcher_slots_are_deterministic_across_instances() -> void:
	var out := []
	for k in 2:
		var so := _so()
		var id := so.add("anvil", Transform3D(Basis(Vector3.UP, 1.3), Vector3(4, 0, 4)))
		var pts := []
		for p in [10, 11, 12]:
			var i := so.claim_watch(id, p)
			pts.append(so.watch_xform(id, i).origin)
		out.append(pts)
	assert_array(out[0]).is_equal(out[1])


# ---------------------------------------------------------------- IK data accessors (O4 data only)

func test_ik_accessors_resolve_targets_into_world_space() -> void:
	var so := _so()
	var id := so.add("well", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10, 0, 0)))
	var ik := so.ik_list(id, 0)
	assert_int(ik.size()).is_equal(2)
	assert_str(String(ik[0]["limb"])).is_equal("hand_r")
	var local: Array = so.types["well"]["ik_targets"][ik[0]["target"]]
	var world := so.ik_target_world(id, String(ik[0]["target"]))
	var expect: Vector3 = (so.spots[id]["xform"] as Transform3D) * Vector3(local[0], local[1], local[2])
	assert_vector(world).is_equal_approx(expect, Vector3.ONE * 0.0001)
	assert_bool(bool(so.types["well"]["_ik_unverified"])).is_true()
	assert_vector(so.ik_target_world(id, "missing")).is_equal(Vector3.INF)
	assert_str(so.clip_tag(id, 0, "loop")).is_equal("verb:draw_water")


# ---------------------------------------------------------------- budgets

func test_cost_budgets() -> void:
	var so := _so()
	var names := so.types.keys()
	for i in 200:
		so.add(names[i % names.size()], Transform3D(Basis.IDENTITY, Vector3(float(i % 20) * 9.0, 0, float(i / 20) * 9.0)))
	var needs := {"water": 0.8, "rest": 0.5, "social": 0.3}
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for i in 500:
		hits += so.find(Vector3(90, 0, 45), {"needs": needs, "hour": 12.0}, 70.0, i).size()
	var find_us := float(Time.get_ticks_usec() - t0) / 500.0
	t0 = Time.get_ticks_usec()
	for i in 500:
		hits += so.find(Vector3(90, 0, 45), {"act": "work", "hour": 12.0}, 70.0, i).size()
	var old_us := float(Time.get_ticks_usec() - t0) / 500.0
	var well := so.add("well", Transform3D.IDENTITY)
	so.claim(well, 0, 1)
	var s := so.session(1, well, 0, 1)
	t0 = Time.get_ticks_usec()
	var body := Vector3(0, 0, 8)
	for i in 2000:
		s.update(0.033, body + Vector3(float(i % 7) * 0.01, 0, 0), false)
		if s.phase != SmartObjects.Session.APPROACH:
			break
	var upd_us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("[M7] budgets: need-find %.1f us (old filter %.1f us), Session.update(APPROACH) %.2f us, hits %d" % [find_us, old_us, upd_us, hits])
	assert_float(find_us).is_less(8000.0)   # a think-tick query (3.3 Hz per NPC), not a per-frame one
	assert_float(upd_us).is_less(200.0)
