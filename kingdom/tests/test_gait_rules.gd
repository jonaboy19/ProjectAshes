extends GdUnitTestSuite
## NPC motion package M8: GaitRules (scripts/living_world/gait_rules.gd), rules L2-L6 of docs/plans/NPC_MOTION_RULES.md.

const G := preload("res://scripts/living_world/gait_rules.gd")


# --- L6: state -> gait set --------------------------------------------------------------------------

func test_l6_state_table() -> void:
	assert_int(G.state_for(1.0, 1.0, false)).is_equal(G.State.NORMAL)
	assert_int(G.state_for(0.3, 1.0, false)).is_equal(G.State.INJURED)
	assert_int(G.state_for(0.3, 0.0, true)).is_equal(G.State.INJURED)   # injured beats drunk
	assert_int(G.state_for(1.0, 1.0, true)).is_equal(G.State.DRUNK)
	assert_int(G.state_for(0.5, 1.0, false)).is_equal(G.State.LIMP)
	assert_int(G.state_for(1.0, 1.0, false, true)).is_equal(G.State.LIMP)
	assert_int(G.state_for(1.0, 0.1, false)).is_equal(G.State.TIRED)
	assert_int(G.state_for(1.0, 0.2, false)).is_equal(G.State.NORMAL)


func test_l6_every_state_has_clips_and_falls_back() -> void:
	var lib := {"Idle": true, "Walk": true}
	for s in G.STATE_NAMES.size():
		assert_str(G.clip_for(s, 0)).is_not_empty()
		assert_str(G.idle_for(s)).is_not_empty()
		# a library with only the base clips resolves every state to Walk / Idle
		assert_str(G.clip_for(s, 0, lib)).is_equal("Walk")
		assert_str(G.idle_for(s, lib)).is_equal("Idle")
	assert_str(G.clip_for(G.State.DRUNK, 0)).is_equal("Life_Walk_Drunk")
	assert_str(G.clip_for(G.State.LIMP, 0)).is_equal("Life_Walk_Limp")
	assert_str(G.clip_for(G.State.INJURED, 0, {"Mx_Inj_Walk_Loop": true})).is_equal("Mx_Inj_Walk_Loop")


func test_l6_weave_amplitude_bounded_and_deterministic() -> void:
	var peak := 0.0
	for id in 40:
		for i in 400:
			var o := G.weave_offset(id, i * 0.25)
			peak = maxf(peak, absf(o))
			assert_float(o).is_between(-G.WEAVE_AMP_M, G.WEAVE_AMP_M)
	assert_float(peak).is_greater(0.3)
	assert_float(G.weave_offset(7, 12.5)).is_equal(G.weave_offset(7, 12.5))
	assert_float(G.weave_offset(7, 12.5)).is_not_equal(G.weave_offset(8, 12.5))


func test_l6_weave_speed_is_the_derivative() -> void:
	for id in [3, 11, 99]:
		var t := 5.0
		var fd := (G.weave_offset(id, t + 0.001) - G.weave_offset(id, t - 0.001)) / 0.002
		assert_float(G.weave_speed(id, t)).is_equal_approx(fd, 0.001)
		assert_float(absf(G.weave_speed(id, t))).is_less(1.0)


# --- L3: stride band --------------------------------------------------------------------------------

func test_l3_rate_stays_in_band_0_6_to_4_mps() -> void:
	var cur := 0
	var s := 0.6
	while s <= 4.0:
		cur = G.pick_rung(G.State.NORMAL, s, cur)
		var r := G.rate_for(G.State.NORMAL, cur, s)
		# slower than the walk clip's band floor is the clamp's job; everywhere a faster rung exists the rate is in band
		if s >= G.ground_speed(G.State.NORMAL, 0) * G.BAND_LO:
			assert_float(r).is_between(G.BAND_LO - 0.001, G.BAND_HI + 0.001)
		s += 0.05


func test_l3_switches_gait_when_rate_leaves_the_band() -> void:
	assert_int(G.pick_rung(G.State.NORMAL, 1.35, 0)).is_equal(0)
	assert_int(G.pick_rung(G.State.NORMAL, 1.7, 0)).is_equal(0)       # 1.26: still in band
	assert_int(G.pick_rung(G.State.NORMAL, 1.9, 0)).is_equal(1)       # 1.41: brisk
	assert_int(G.pick_rung(G.State.NORMAL, 3.2, 1)).is_equal(2)       # jog
	assert_int(G.pick_rung(G.State.NORMAL, 1.4, 2)).is_equal(0)       # slowing from a jog drops to walk
	# hysteresis: inside the band of the current rung nothing changes
	assert_int(G.pick_rung(G.State.NORMAL, 1.6, 1)).is_equal(1)


func test_l3_rate_clamped_and_gait_into_writes_intent() -> void:
	assert_float(G.rate_for(G.State.LIMP, 0, 0.1)).is_equal(G.RATE_MIN)
	assert_float(G.rate_for(G.State.LIMP, 0, 9.0)).is_equal(G.RATE_MAX)
	var out := MotionIntent.make()
	var rung := G.gait_into(out, G.State.NORMAL, 2.0, 0)
	assert_int(rung).is_equal(1)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Brisk")
	assert_float(out["gait_rate"]).is_equal_approx(2.0 / 1.9, 0.001)
	G.gait_into(out, G.State.DRUNK, 0.0)
	assert_str(out["gait_clip"]).is_equal("Idle")
	# FAR: only the VAT set exists, so a brisk gait resolves to Walk
	G.gait_into(out, G.State.NORMAL, 2.0, 0, {"Walk": true, "Idle": true})
	assert_str(out["gait_clip"]).is_equal("Walk")


# --- L4: start, stop, turn --------------------------------------------------------------------------

func test_l4_decision_table() -> void:
	var N := G.TIER_NEAR
	var M := G.TIER_MID
	assert_str(G.transition(0.0, 1.3, 0.0, N)).is_equal("Loco_WalkStart_F")
	assert_str(G.transition(0.0, 1.3, 0.0, M)).is_equal("Loco_WalkStart_F")
	assert_str(G.transition(1.3, 0.0, 0.0, N)).is_equal("Loco_WalkStop")
	assert_str(G.transition(1.3, 0.0, 0.0, M)).is_equal("Loco_WalkStop")
	assert_str(G.transition(1.3, 1.3, 0.0, N)).is_equal("")           # steady walking
	assert_str(G.transition(0.0, 0.0, 0.0, N)).is_equal("")           # standing
	assert_str(G.transition(0.0, 1.3, 120.0, N)).is_equal("Mx_RunTurn_L")
	assert_str(G.transition(0.0, 1.3, -120.0, N)).is_equal("Mx_RunTurn_R")
	assert_str(G.transition(0.5, 1.3, 170.0, N)).is_equal("Mx_Run_Turn_180")
	assert_str(G.transition(0.5, 1.3, -170.0, N)).is_equal("Mx_Run_Turn_180")
	assert_str(G.transition(0.0, 1.3, 90.0, N)).is_equal("Loco_WalkStart_F")   # under 100 degrees: just start
	assert_str(G.transition(1.5, 1.3, 170.0, N)).is_equal("")          # over 1 m/s: no turn in place


func test_l4_tier_limits() -> void:
	assert_str(G.transition(0.0, 1.3, 170.0, G.TIER_MID)).is_equal("Loco_WalkStart_F")   # MID: no turns, start only
	assert_str(G.transition(0.0, 1.3, 0.0, G.TIER_FAR)).is_equal("")
	assert_str(G.transition(1.3, 0.0, 0.0, 3)).is_equal("")


func test_l4_injured_turns_and_missing_clips() -> void:
	assert_str(G.transition(0.0, 1.0, 120.0, G.TIER_NEAR, G.State.INJURED)).is_equal("Mx_Inj_Turn_Left")
	assert_str(G.transition(0.0, 1.0, -120.0, G.TIER_NEAR, G.State.INJURED)).is_equal("Mx_Inj_Turn_Right")
	assert_str(G.transition(0.0, 1.3, 0.0, G.TIER_NEAR, G.State.NORMAL, {"Walk": true})).is_equal("")
	assert_str(G.transition(0.0, 1.3, 0.0, G.TIER_NEAR, G.State.NORMAL, {"Loco_WalkStart_F": true})).is_equal("Loco_WalkStart_F")


# --- L2: lean spring --------------------------------------------------------------------------------

func _settle(st: PackedFloat32Array, speed: float, yaw: float, secs: float, bias := 0.0) -> void:
	for i in int(secs / 0.016):
		G.lean_step(st, speed, yaw, 0.016, bias)


func test_l2_lean_goal_and_limits() -> void:
	var st := G.lean_new()
	_settle(st, 1.4, 1.0, 2.0)
	assert_float(G.lean_roll(st)).is_equal_approx(-1.4 * 1.0 * G.LEAN_K, 0.002)   # into the turn
	assert_float(G.lean_pitch(st)).is_equal_approx(1.4 * G.LEAN_PITCH_GAIN, 0.002)
	var st2 := G.lean_new()
	_settle(st2, 4.0, 8.0, 2.0)
	assert_float(absf(G.lean_roll(st2))).is_less_equal(G.LEAN_MAX_ROLL + 0.003)
	assert_float(G.lean_pitch(st2)).is_less_equal(G.LEAN_MAX_PITCH + 0.003)
	var st3 := G.lean_new()
	_settle(st3, 4.0, -8.0, 2.0)
	assert_float(G.lean_roll(st3)).is_greater(0.0)     # opposite turn, opposite roll


func test_l2_spring_lags_then_settles_without_overshoot() -> void:
	var st := G.lean_new()
	G.lean_step(st, 1.4, 3.0, 0.016)
	var goal := minf(1.4 * 3.0 * G.LEAN_K, G.LEAN_MAX_ROLL)
	assert_float(absf(G.lean_roll(st))).is_less(goal * 0.2)    # lags like weight
	var peak := 0.0
	for i in 300:
		G.lean_step(st, 1.4, 3.0, 0.016)
		peak = maxf(peak, absf(G.lean_roll(st)))
	assert_float(peak).is_less_equal(goal + 0.002)             # critically damped: no overshoot
	_settle(st, 0.0, 0.0, 2.0)
	assert_float(G.lean_roll(st)).is_equal_approx(0.0, 0.002)
	assert_float(G.lean_pitch(st)).is_equal_approx(0.0, 0.002)


func test_l2_bias_and_dt_guard() -> void:
	var st := G.lean_new()
	_settle(st, 0.0, 0.0, 2.0, -0.05)
	assert_float(G.lean_pitch(st)).is_equal_approx(-0.05, 0.002)
	var before := G.lean_roll(st)
	assert_float(G.lean_step(st, 1.0, 1.0, 0.0)).is_equal(before)     # dt 0 is a no-op
	G.lean_step(st, 1.0, 1.0, 10.0)                                   # a hitch is capped at 50 ms, stays finite
	assert_bool(is_finite(G.lean_roll(st))).is_true()


# --- L5: carry mass pace ---------------------------------------------------------------------------

func test_l5_pace_by_mass() -> void:
	assert_float(G.carry_pace_mul("")).is_equal(1.0)
	assert_float(G.carry_rate_mul("")).is_equal(1.0)
	assert_float(G.carry_pace_mul("crate")).is_equal_approx(0.85, 0.0001)
	assert_float(G.carry_rate_mul("crate")).is_equal_approx(1.05, 0.0001)
	# heavier = slower, never below 0.85
	assert_float(G.carry_pace_mul("basket")).is_greater(G.carry_pace_mul("sack"))
	assert_float(G.carry_pace_mul("sack")).is_greater(G.carry_pace_mul("crate"))
	for k in G.LOADS:
		assert_float(G.carry_pace_mul(k)).is_between(0.85, 1.0)
		assert_float(G.carry_rate_mul(k)).is_between(1.0, 1.05)


func test_l5_lean_by_load_type() -> void:
	assert_float(G.carry_lean_bias("sack")).is_greater(0.0)
	assert_float(G.carry_lean_bias("crate")).is_less(0.0)
	assert_float(G.carry_lean_bias("basket")).is_equal(0.0)
	assert_float(G.carry_lean_bias("nothing")).is_equal(0.0)
	var st := G.lean_new()
	_settle(st, 1.0, 0.0, 2.0, G.carry_lean_bias("crate"))
	assert_float(G.lean_pitch(st)).is_less(0.0)   # crate: leans back despite walking forward


# --- cost -------------------------------------------------------------------------------------------

func test_cost_per_tick_is_small() -> void:
	var st := G.lean_new()
	var out := MotionIntent.make()
	var t0 := Time.get_ticks_usec()
	var cur := 0
	for i in 24000:
		cur = G.gait_into(out, G.State.NORMAL, 0.5 + (i % 40) * 0.08, cur)
		G.lean_step(st, 1.4, 0.5, 0.016)
		G.transition(1.0, 1.0, 0.0, G.TIER_NEAR)
		G.weave_offset(i % 24, i * 0.016)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_float(ms).is_less(400.0)   # 24 bodies x 1000 ticks, loose; one tick of 24 bodies is far under 0.15 ms
