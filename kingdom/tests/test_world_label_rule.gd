extends GdUnitTestSuite
## UI restraint: in-world labels show only near + facing (or targeted), never over a crowd, max 2 at once, fade 0.25 s.

const Rule := preload("res://scripts/core/world_label_rule.gd")


func test_facing_dot_ahead_behind_side_and_degenerate() -> void:
	var fwd := Vector3(0, 0, -1)
	assert_float(Rule.facing_dot(fwd, Vector3.ZERO, Vector3(0, 0, -5))).is_equal_approx(1.0, 0.001)
	assert_float(Rule.facing_dot(fwd, Vector3.ZERO, Vector3(0, 0, 5))).is_equal_approx(-1.0, 0.001)
	assert_float(Rule.facing_dot(fwd, Vector3.ZERO, Vector3(5, 0, 0))).is_equal_approx(0.0, 0.001)
	assert_float(Rule.facing_dot(fwd, Vector3.ZERO, Vector3.ZERO)).is_equal(1.0)     # standing on it: not hidden


func test_contextual_needs_near_and_facing() -> void:
	var m := Rule.MODE_CONTEXTUAL
	assert_float(Rule.target_alpha(m, 2.0, 0.95, false, 0)).is_equal(1.0)
	assert_float(Rule.target_alpha(m, 8.0, 0.95, false, 0)).is_equal(0.0)           # mid distance street: nothing floats
	assert_float(Rule.target_alpha(m, 2.0, 0.2, false, 0)).is_equal(0.0)            # not facing it
	assert_float(Rule.target_alpha(m, Rule.NEAR, 0.95, false, 0)).is_equal(0.0)     # fully faded at the edge


func test_alpha_fades_with_distance() -> void:
	var a1 := Rule.target_alpha(Rule.MODE_CONTEXTUAL, 2.5, 0.9, false, 0)
	var a2 := Rule.target_alpha(Rule.MODE_CONTEXTUAL, 4.2, 0.9, false, 0)
	assert_float(a1).is_equal(1.0)
	assert_float(a2).is_between(0.0, 1.0)
	assert_float(a2).is_less(a1)


func test_focus_target_shows_without_facing_and_a_bit_further() -> void:
	var m := Rule.MODE_CONTEXTUAL
	assert_float(Rule.target_alpha(m, 5.0, -1.0, true, 0)).is_greater(0.0)
	assert_float(Rule.target_alpha(m, 3.0, -1.0, true, 5)).is_equal(1.0)            # even inside a crowd
	assert_float(Rule.target_alpha(m, 7.0, 1.0, true, 0)).is_equal(0.0)


func test_crowd_hides_labels() -> void:
	assert_float(Rule.target_alpha(Rule.MODE_CONTEXTUAL, 2.0, 1.0, false, Rule.CROWD_MAX)).is_equal(0.0)
	assert_float(Rule.target_alpha(Rule.MODE_CONTEXTUAL, 2.0, 1.0, false, Rule.CROWD_MAX - 1)).is_equal(1.0)


func test_crowd_count_excludes_self_and_far_points() -> void:
	var me := Vector3.ZERO
	var pts := [me, Vector3(1, 0, 0), Vector3(0, 0, 2), Vector3(10, 0, 0)]
	assert_int(Rule.crowd_count(me, pts)).is_equal(2)
	assert_int(Rule.crowd_count(me, [me])).is_equal(0)


func test_modes_always_and_off() -> void:
	assert_float(Rule.target_alpha(Rule.MODE_ALWAYS, 50.0, -1.0, false, 9)).is_equal(-1.0)   # not governed: legacy fade applies
	assert_float(Rule.target_alpha(Rule.MODE_OFF, 1.0, 1.0, true, 0)).is_equal(0.0)


func test_pick_visible_max_two_focus_first_then_closest() -> void:
	var rows := [
		{"id": 1, "alpha": 1.0, "dist": 3.0, "focus": false},
		{"id": 2, "alpha": 1.0, "dist": 1.0, "focus": false},
		{"id": 3, "alpha": 1.0, "dist": 4.0, "focus": true},
		{"id": 4, "alpha": 0.0, "dist": 0.5, "focus": false},
	]
	assert_array(Rule.pick_visible(rows)).is_equal([3, 2])
	assert_array(Rule.pick_visible(rows.slice(0, 2))).is_equal([2, 1])
	assert_array(Rule.pick_visible([{"id": 9, "alpha": 0.0, "dist": 1.0, "focus": false}])).is_empty()


func test_fade_takes_a_quarter_second() -> void:
	var a := 0.0
	for i in 15:
		a = Rule.step_alpha(a, 1.0, 1.0 / 60.0)
	assert_float(a).is_equal_approx(1.0, 0.001)
	assert_float(Rule.step_alpha(0.0, 1.0, 1.0 / 60.0)).is_less(0.1)
	assert_float(Rule.step_alpha(1.0, 0.0, 1.0)).is_equal(0.0)
