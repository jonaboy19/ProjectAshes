extends GdUnitTestSuite
## AR-1: hold-to-leak curve, echo, suppression, focus/strain, slips, power table, input action, save.

const AuraState := preload("res://scripts/sim/aura_state.gd")
const AuraInput := preload("res://scripts/sim/aura_input.gd")


func _st(power := 1.0) -> RefCounted:
	var s: RefCounted = AuraState.new()
	s.power = power
	return s


func _hold(s: RefCounted, secs: float, dt := 0.1) -> void:
	var n := int(round(secs / dt))
	for i in n:
		s.update(dt, true, {"day": 3})


func test_curve_values_at_1_4_8_12_seconds() -> void:
	var want := {1.0: 0.2992, 4.0: 0.6930, 8.0: 0.8902, 12.0: 0.9600}
	for h: float in want:
		var s := _st()
		s.emotion["stress"] = 0.5         # no calm bonus: S = 0 with zero skill
		assert_float(s.suppression()).is_equal_approx(0.0, 0.001)
		s.focus = 1000.0
		_hold(s, h)
		assert_float(AuraState.leak_of(h) ** 0.8).is_equal_approx(float(want[h]), 0.002)
		assert_float(s.current_emit()).is_equal_approx(float(want[h]), 0.01)
	assert_float(_st().current_emit()).is_equal(0.0)      # h = 0: nothing


func test_reach_grows_with_emit_and_is_bounded() -> void:
	var s := _st()
	s.emotion["stress"] = 0.5
	s.focus = 1000.0
	_hold(s, 0.5)
	var r1: float = s.reach_m()
	_hold(s, 10.0)
	var r2: float = s.reach_m()
	assert_float(r1).is_greater_equal(6.0)
	assert_float(r2).is_greater(r1)
	assert_float(r2).is_less_equal(76.5)


func test_echo_half_life_and_passive_floor() -> void:
	var s := _st(0.8)
	s.emotion["stress"] = 0.5
	_hold(s, 6.0)
	s.update(0.1, false, {})
	var e0: float = s.emit_at_release
	assert_float(e0).is_greater(0.3)
	for i in 60:                                  # 6 s of echo
		s.update(0.1, false, {})
	var passive: float = s.passive()
	assert_float(s.current_emit()).is_equal_approx(maxf(e0 * exp(-1.0), passive), 0.03)
	for i in 600:
		s.update(0.1, false, {})
	assert_float(s.current_emit()).is_equal_approx(s.passive(), 0.02)


func test_suppression_sources_and_subtraction() -> void:
	var s := _st(0.8)
	s.emotion["stress"] = 0.5
	assert_float(s.suppression()).is_equal(0.0)                   # stress 0.5 costs more than it has
	s.control = 100.0
	assert_float(s.suppression()).is_equal_approx(0.55 - 0.0525, 0.001)
	s.discipline = 1.0
	s.mantle = 0.25
	s.warded = true
	assert_float(s.suppression()).is_equal(1.0)    # clamped
	var a := _st(0.8)
	a.emotion["stress"] = 0.5
	var b := _st(0.8)
	b.emotion["stress"] = 0.5
	b.control = 80.0
	_hold(a, 2.0)
	_hold(b, 2.0)
	assert_float(b.current_emit()).is_less(a.current_emit())      # a trained hand leaks less at the same hold time
	var v: Dictionary = b.subject_view()
	assert_float(float(v["aura_suppress"])).is_equal_approx(b.suppression(), 0.001)   # what magic_pressure subtracts
	# emotion costs suppression
	var c := _st()
	c.control = 50.0
	var calm: float = c.suppression()
	c.emotion["anger"] = 1.0
	assert_float(c.suppression()).is_less(calm - 0.3)


func test_rein_in_raises_suppression_costs_focus() -> void:
	var s := _st(0.8)
	s.emotion["stress"] = 0.5
	s.control = 60.0
	var f0: float = s.focus
	var s0: float = s.suppression()
	assert_bool(s.rein_in()).is_true()
	assert_float(s.suppression()).is_equal_approx(s0 + 0.25, 0.001)
	assert_float(s.focus).is_less(f0)
	for i in 110:
		s.update(0.1, false, {})
	assert_float(s.suppression()).is_equal_approx(s0, 0.001)      # 10 s later it wears off


func test_focus_drain_strain_and_regen() -> void:
	var s := _st(1.0)
	s.emotion["stress"] = 0.5
	_hold(s, 3.0)
	assert_float(s.focus).is_less(100.0)
	s.focus = 2.0
	_hold(s, 1.0)
	assert_bool(s.strained).is_true()
	assert_int(s.state()).is_equal(AuraState.St.STRAINED)
	assert_float(s.focus).is_equal(0.0)
	var f: float = s.focus
	s.update(60.0, false, {})
	assert_float(s.focus).is_equal_approx(f + 1.2, 0.05)          # 1.2 per minute out of combat
	s.update(60.0, false, {"meditating": true})
	assert_float(s.focus).is_greater(f + 1.2 + 2.5)
	var s2 := _st(1.0)
	s2.update(60.0, false, {"in_combat": true})
	assert_float(s2.focus).is_equal(100.0)


func test_settling_and_afterglow() -> void:
	var s := _st(0.8)
	s.emotion["stress"] = 0.5
	_hold(s, 7.0)
	s.update(0.1, false, {})
	assert_float(s.settle_t).is_greater(0.0)
	assert_int(s.after_n).is_equal(1)
	for i in 3:
		_hold(s, 1.0)
		s.update(0.1, false, {})
	assert_int(s.after_n).is_greater(1)
	assert_int(s.after_n).is_less_equal(5)


func test_slip_is_deterministic_and_needs_stress() -> void:
	var a := _st(0.8)
	var b := _st(0.8)
	a.emotion["anger"] = 1.0
	b.emotion["anger"] = 1.0
	var ta := -1.0
	var tb := -1.0
	for i in 1200:
		a.update(0.1, false, {"day": 4})
		b.update(0.1, false, {"day": 4})
		if ta < 0.0 and a.state() == AuraState.St.SLIPPED:
			ta = a.clock
		if tb < 0.0 and b.state() == AuraState.St.SLIPPED:
			tb = b.clock
	assert_float(ta).is_greater(0.0)
	assert_float(ta).is_equal(tb)                                  # same seed, same moment
	var calm := _st(0.8)
	for i in 1200:
		calm.update(0.1, false, {"day": 4})
		assert_int(calm.state()).is_not_equal(AuraState.St.SLIPPED)
	# a slip leaks 0.4 P and a rein cuts it short
	var r := _st(1.0)
	r.slip_t = 3.0
	r.update(0.1, false, {})
	assert_float(r.current_emit()).is_greater_equal(0.39)
	assert_bool(r.rein_in()).is_true()
	assert_float(r.slip_t).is_equal(0.0)


func test_breakthrough_is_unavoidable_and_wide() -> void:
	var s := _st(0.9)
	s.control = 100.0
	s.breakthrough()
	s.update(0.1, false, {})
	assert_float(s.current_emit()).is_greater_equal(0.85)
	assert_float(s.reach_m()).is_greater_equal(150.0)
	assert_bool(s.rein_in()).is_false()                            # no rein for the surge


func test_power_table_is_flat_below_tier_three() -> void:
	assert_float(AuraState.power_from_tier(0)).is_equal(0.0)
	assert_float(AuraState.power_from_tier(1)).is_equal(0.0)
	assert_float(AuraState.power_from_tier(2)).is_greater(0.0)
	assert_float(AuraState.power_from_tier(2)).is_less(0.1)
	assert_float(AuraState.power_from_tier(11)).is_equal_approx(1.0, 0.001)
	var p0 := _st(0.0)
	_hold(p0, 10.0)
	assert_float(p0.current_emit()).is_equal(0.0)                 # early play is never penalised
	var last := -1.0
	for t in 12:
		var v := AuraState.power_from_tier(t)
		assert_float(v).is_greater_equal(last)
		last = v


func test_flare_and_surge() -> void:
	var s := _st(0.8)
	s.flare(1.0)
	assert_float(s.current_emit()).is_greater_equal(0.79)
	var h := _st(0.6)
	h.emotion["stress"] = 0.5
	_hold(h, 2.0)
	var before: float = h.current_emit()
	assert_bool(h.surge()).is_true()
	h.update(0.1, true, {})
	assert_float(h.current_emit()).is_greater(before)


func test_input_action_default_and_rebind() -> void:
	AuraInput.ensure_actions()
	assert_bool(InputMap.has_action("aura_release")).is_true()
	var evs := InputMap.action_get_events("aura_release")
	assert_int(evs.size()).is_equal(1)
	assert_int((evs[0] as InputEventKey).physical_keycode).is_equal(KEY_Q)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	AuraInput.rebind("aura_release", ev)
	assert_int((InputMap.action_get_events("aura_release")[0] as InputEventKey).physical_keycode).is_equal(KEY_G)
	var back := InputEventKey.new()
	back.physical_keycode = KEY_Q
	AuraInput.rebind("aura_release", back)


func test_save_round_trip_is_compact() -> void:
	var s := _st(0.7)
	s.control = 42.5
	s.focus = 61.3
	s.after_n = 3
	s.signature = "dark_swirl"
	var d: Dictionary = s.serialize()
	assert_int(JSON.stringify(d).length()).is_less(120)
	var t := _st(0.7)
	t.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_float(t.control).is_equal_approx(42.5, 0.06)
	assert_float(t.focus).is_equal_approx(61.3, 0.06)
	assert_int(t.after_n).is_equal(3)
	assert_str(t.signature).is_equal("dark_swirl")
	assert_int(t.state()).is_equal(AuraState.St.SEALED)
