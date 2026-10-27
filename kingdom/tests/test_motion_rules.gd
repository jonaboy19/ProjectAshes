extends GdUnitTestSuite
## M1 core of docs/plans/NPC_MOTION_RULES.md: channel arbitration, min_hold_s hysteresis, tier degrade, archetype params, stub rows,
## determinism and cost. (scripts/living_world/motion_rules.gd, motion_intent.gd, data/living_world/motion_rules.json)
## Test rules are plain Callables handed to MotionRules.registry_from(data, fns); they fire when ctx[id] is true and write `payload`.

const NEAR := MotionRules.TIER_NEAR
const MID := MotionRules.TIER_MID
const FAR := MotionRules.TIER_FAR
const OUT := MotionRules.TIER_OUT
const CHANNELS := ["HEAD", "UPPER", "LOCO", "BODY"]


func _fire(payload: Dictionary) -> Callable:
	return func(ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, row: Dictionary, cand: Dictionary) -> bool:
		if not ctx.get(row["name"], false):
			return false
		for k: String in payload:
			cand[k] = payload[k]
		return true


## rules: Array of [id, channels, priority, hold, tier, payload, (suppresses)] in registration order.
func _reg(rules: Array, archetypes := {"villager": {"head_turn_deg": 70, "gait": {"idle": "Idle", "walk": "Walk"}, "vat_set": "adult"}}) -> MotionRules.Registry:
	var rows := {}
	var fns := {}
	for r: Array in rules:
		var row := {"name": r[0], "channels": r[1], "priority": r[2], "min_hold_s": r[3], "tier": r[4]}
		if r.size() > 6:
			row["suppresses"] = r[6]
		rows[r[0]] = row
		fns[r[0]] = _fire(r[5])
	return MotionRules.registry_from({"archetypes": archetypes, "rules": rows}, fns)


func _eval(reg: MotionRules.Registry, ctx := {}, tier := NEAR, persona := {}) -> Dictionary:
	var out := MotionIntent.make()
	MotionRules.evaluate_into(out, ctx, persona, tier, reg)
	return out


func _on(ids: Array, extra := {}) -> Dictionary:
	var c := extra.duplicate()
	for id: String in ids:
		c[id] = true
	return c


# ---------------------------------------------------------------- neutral / base gait

func test_no_rules_gives_the_neutral_intent_with_a_base_gait() -> void:
	var reg := _reg([])
	var idle := _eval(reg)
	assert_str(idle["gait_clip"]).is_equal("Idle")
	assert_bool(MotionIntent.is_noop(idle)).is_true()
	for k in ["body_rule", "loco_rule", "upper_rule", "head_rule"]:
		assert_str(idle[k]).is_equal("")
	assert_str(_eval(reg, {"speed": 1.2})["gait_clip"]).is_equal("Walk")
	assert_str(_eval(reg, {"velocity": Vector3(0, 0, 1.0)})["gait_clip"]).is_equal("Walk")
	assert_str(_eval(reg, {"speed": MotionRules.MOVING_SPEED})["gait_clip"]).is_equal("Idle")


func test_out_tier_returns_nothing() -> void:
	var reg := _reg([["a", ["LOCO"], 5, 0.0, "FAR", {"gait_clip": "Run", "speed_mul": 2.0}]])
	var o := _eval(reg, _on(["a"], {"speed": 2.0}), OUT)
	assert_str(o["gait_clip"]).is_equal("")
	assert_str(o["loco_rule"]).is_equal("")
	assert_int(o["tier"]).is_equal(OUT)
	assert_float(o["speed_mul"]).is_equal(1.0)


# ---------------------------------------------------------------- arbitration truth table

func test_independent_channels_all_apply() -> void:
	var reg := _reg([
		["h", ["HEAD"], 1, 0.0, "FAR", {"look_prio": 2, "look_x": 1.0, "look_y": 2.0, "look_z": 3.0}],
		["u", ["UPPER"], 1, 0.0, "FAR", {"upper_clip": "Carry"}],
		["l", ["LOCO"], 1, 0.0, "FAR", {"speed_mul": 0.5, "gait_clip": "Walk_Tired"}],
	])
	var o := _eval(reg, _on(["h", "u", "l"]))
	assert_str(o["head_rule"]).is_equal("h")
	assert_str(o["upper_rule"]).is_equal("u")
	assert_str(o["loco_rule"]).is_equal("l")
	assert_str(o["body_rule"]).is_equal("")
	assert_float(o["look_y"]).is_equal(2.0)
	assert_str(o["upper_clip"]).is_equal("Carry")
	assert_float(o["speed_mul"]).is_equal(0.5)
	assert_str(o["gait_clip"]).is_equal("Walk_Tired")


func test_body_suppresses_loco_and_upper_but_not_head() -> void:
	var reg := _reg([
		["h", ["HEAD"], 1, 0.0, "FAR", {"look_prio": 1}],
		["u", ["UPPER"], 9, 0.0, "FAR", {"upper_clip": "Carry"}],
		["l", ["LOCO"], 9, 0.0, "FAR", {"speed_mul": 0.5, "gait_clip": "Walk_Tired"}],
		["b", ["BODY"], 1, 0.0, "FAR", {"reaction": 11, "oneshot_clip": "Flee_Start", "b_speed_mul": 2.0, "b_steer_x": 3.0}],
	])
	var o := _eval(reg, _on(["h", "u", "l", "b"], {"speed": 1.0}))
	assert_str(o["body_rule"]).is_equal("b")
	assert_str(o["loco_rule"]).is_equal("")
	assert_str(o["upper_rule"]).is_equal("")
	assert_str(o["head_rule"]).is_equal("h")
	assert_str(o["upper_clip"]).is_equal("")
	assert_str(o["gait_clip"]).is_equal("Walk")       # the LOCO rule's clip is gone, base gait fills in
	# the BODY steer is what the body uses
	assert_float(o["speed_mul"]).is_equal(2.0)
	assert_float(o["steer_x"]).is_equal(3.0)
	assert_int(o["reaction"]).is_equal(11)
	assert_str(o["oneshot_clip"]).is_equal("Flee_Start")
	assert_int(o["oneshot_channel"]).is_equal(MotionIntent.Channel.BODY)


func test_body_suppresses_regardless_of_priority_numbers() -> void:
	var reg := _reg([
		["l", ["LOCO"], 99, 0.0, "FAR", {"speed_mul": 0.1}],
		["b", ["BODY"], 1, 0.0, "FAR", {"reaction": 3}],
	])
	var o := _eval(reg, _on(["l", "b"]))
	assert_str(o["body_rule"]).is_equal("b")
	assert_str(o["loco_rule"]).is_equal("")
	assert_float(o["speed_mul"]).is_equal(1.0)


func test_body_row_suppresses_list_overrides_the_default() -> void:
	var reg := _reg([
		["u", ["UPPER"], 1, 0.0, "FAR", {"upper_clip": "Carry"}],
		["l", ["LOCO"], 1, 0.0, "FAR", {"speed_mul": 0.5}],
		["b", ["BODY"], 1, 0.0, "FAR", {"reaction": 3}, ["UPPER"]],
	])
	var o := _eval(reg, _on(["u", "l", "b"]))
	assert_str(o["upper_rule"]).is_equal("")
	assert_str(o["loco_rule"]).is_equal("l")
	assert_float(o["speed_mul"]).is_equal(0.5)


func test_higher_priority_wins_within_a_channel_and_ties_go_to_the_earlier_row() -> void:
	var reg := _reg([
		["a", ["LOCO"], 2, 0.0, "FAR", {"speed_mul": 0.2}],
		["b", ["LOCO"], 3, 0.0, "FAR", {"speed_mul": 0.3}],
		["c", ["LOCO"], 3, 0.0, "FAR", {"speed_mul": 0.4}],
	])
	assert_str(_eval(reg, _on(["a", "b", "c"]))["loco_rule"]).is_equal("b")
	assert_float(_eval(reg, _on(["a", "b", "c"]))["speed_mul"]).is_equal(0.3)
	assert_str(_eval(reg, _on(["a", "c"]))["loco_rule"]).is_equal("c")
	assert_str(_eval(reg, _on(["a"]))["loco_rule"]).is_equal("a")
	assert_str(_eval(reg, {})["loco_rule"]).is_equal("")


func test_a_multi_channel_rule_competes_in_each_channel() -> void:
	var reg := _reg([
		["both", ["LOCO", "UPPER"], 2, 0.0, "FAR", {"speed_mul": 0.6, "upper_clip": "Talk"}],
		["u_hi", ["UPPER"], 5, 0.0, "FAR", {"upper_clip": "Wave"}],
	])
	var o := _eval(reg, _on(["both", "u_hi"]))
	assert_str(o["loco_rule"]).is_equal("both")
	assert_float(o["speed_mul"]).is_equal(0.6)
	assert_str(o["upper_rule"]).is_equal("u_hi")
	assert_str(o["upper_clip"]).is_equal("Wave")


func test_oneshot_composition_body_beats_upper() -> void:
	var upper_only := _reg([["u", ["UPPER"], 1, 0.0, "FAR", {"u_oneshot": "Wave_Once"}]])
	var o := _eval(upper_only, _on(["u"]))
	assert_str(o["oneshot_clip"]).is_equal("Wave_Once")
	assert_int(o["oneshot_channel"]).is_equal(MotionIntent.Channel.UPPER)
	var body := _reg([["b", ["BODY"], 1, 0.0, "FAR", {"oneshot_clip": "Flinch"}], ["u", ["UPPER"], 1, 0.0, "FAR", {"u_oneshot": "Wave_Once"}]], {"villager": {}})
	o = _eval(body, _on(["b", "u"]))
	assert_str(o["oneshot_clip"]).is_equal("Flinch")
	assert_int(o["oneshot_channel"]).is_equal(MotionIntent.Channel.BODY)


func test_disabled_stub_and_channelless_rows_are_never_registered_or_called() -> void:
	var calls := [0]
	var spy := func(_c: Dictionary, _a: Dictionary, _p: Dictionary, _r: Dictionary, cand: Dictionary) -> bool:
		calls[0] += 1
		cand["speed_mul"] = 0.1
		return true
	var rows := {
		"off": {"enabled": false, "channels": ["LOCO"], "priority": 5, "tier": "FAR"},
		"stub": {"stub": true, "channels": ["LOCO"], "priority": 5, "tier": "FAR"},
		"none": {"channels": [], "priority": 5, "tier": "FAR"},
		"bad": {"channels": ["NOPE"], "priority": 5, "tier": "FAR"},
	}
	var reg := MotionRules.registry_from({"rules": rows}, {"off": spy, "stub": spy, "none": spy, "bad": spy})
	assert_int(reg.count).is_equal(0)
	_eval(reg, {})
	assert_int(calls[0]).is_equal(0)


func test_rule_tier_gates_when_it_runs() -> void:
	var reg := _reg([
		["near", ["LOCO"], 1, 0.0, "NEAR", {"speed_mul": 0.1}],
		["mid", ["LOCO"], 2, 0.0, "MID", {"speed_mul": 0.2}],
		["far", ["LOCO"], 3, 0.0, "FAR", {"speed_mul": 0.3}],
	])
	var all := _on(["near", "mid", "far"])
	assert_str(_eval(reg, all, NEAR)["loco_rule"]).is_equal("far")
	assert_str(_eval(reg, _on(["near", "mid"]), NEAR)["loco_rule"]).is_equal("mid")
	assert_str(_eval(reg, _on(["near", "mid"]), MID)["loco_rule"]).is_equal("mid")
	assert_str(_eval(reg, _on(["near", "mid"]), FAR)["loco_rule"]).is_equal("")
	assert_str(_eval(reg, _on(["near"]), MID)["loco_rule"]).is_equal("")
	assert_str(_eval(reg, all, FAR)["loco_rule"]).is_equal("far")


# ---------------------------------------------------------------- min_hold_s hysteresis

func test_hold_keeps_the_incumbent_against_an_equal_priority_challenger() -> void:
	var reg := _reg([
		["a", ["LOCO"], 2, 0.0, "FAR", {"speed_mul": 0.2}],           # earlier row: would win a tie
		["b", ["LOCO"], 2, 1.0, "FAR", {"speed_mul": 0.3}],
	])
	var st := MotionRules.new_state()
	var o := _eval(reg, _on(["b"], {"now": 0.0, "motion_state": st}))
	assert_str(o["loco_rule"]).is_equal("b")
	o = _eval(reg, _on(["a", "b"], {"now": 0.5, "motion_state": st}))
	assert_str(o["loco_rule"]).is_equal("b")               # held
	assert_float(o["speed_mul"]).is_equal(0.3)
	o = _eval(reg, _on(["a", "b"], {"now": 1.01, "motion_state": st}))
	assert_str(o["loco_rule"]).is_equal("a")               # hold over, the tie goes to the earlier row again


func test_without_motion_state_there_is_no_hysteresis() -> void:
	var reg := _reg([
		["a", ["LOCO"], 2, 0.0, "FAR", {"speed_mul": 0.2}],
		["b", ["LOCO"], 2, 5.0, "FAR", {"speed_mul": 0.3}],
	])
	assert_str(_eval(reg, _on(["b"], {"now": 0.0}))["loco_rule"]).is_equal("b")
	assert_str(_eval(reg, _on(["a", "b"], {"now": 0.1}))["loco_rule"]).is_equal("a")


func test_a_higher_priority_challenger_preempts_a_hold() -> void:
	var reg := _reg([
		["low", ["LOCO"], 2, 5.0, "FAR", {"speed_mul": 0.5}],
		["high", ["LOCO"], 4, 0.0, "FAR", {"speed_mul": 0.1}],
	])
	var st := MotionRules.new_state()
	assert_str(_eval(reg, _on(["low"], {"now": 0.0, "motion_state": st}))["loco_rule"]).is_equal("low")
	var o := _eval(reg, _on(["low", "high"], {"now": 0.2, "motion_state": st}))
	assert_str(o["loco_rule"]).is_equal("high")
	# and the preempted rule does not come back by itself inside its old hold
	o = _eval(reg, _on(["low"], {"now": 0.4, "motion_state": st}))
	assert_str(o["loco_rule"]).is_equal("low")             # high is gone (no hold) so low wins again, nothing latched
	assert_float(o["speed_mul"]).is_equal(0.5)


func test_vanished_trigger_is_latched_until_the_hold_ends() -> void:
	var reg := _reg([["a", ["LOCO", "UPPER"], 2, 1.0, "FAR", {"speed_mul": 0.4, "steer_x": 2.0, "upper_clip": "Talk"}]])
	var st := MotionRules.new_state()
	_eval(reg, _on(["a"], {"now": 0.0, "motion_state": st}))
	var o := _eval(reg, {"now": 0.6, "motion_state": st})      # trigger gone
	assert_str(o["loco_rule"]).is_equal("a")
	assert_float(o["speed_mul"]).is_equal(0.4)
	assert_float(o["steer_x"]).is_equal(2.0)
	assert_str(o["upper_clip"]).is_equal("Talk")
	o = _eval(reg, {"now": 1.2, "motion_state": st})            # hold over
	assert_str(o["loco_rule"]).is_equal("")
	assert_float(o["speed_mul"]).is_equal(1.0)
	assert_str(o["upper_clip"]).is_equal("")
	assert_str(o["upper_rule"]).is_equal("")


func test_latch_is_dropped_when_the_incumbent_cannot_run_at_the_new_tier() -> void:
	var reg := _reg([["a", ["LOCO"], 2, 5.0, "NEAR", {"speed_mul": 0.4}]])
	var st := MotionRules.new_state()
	_eval(reg, _on(["a"], {"now": 0.0, "motion_state": st}), NEAR)
	var o := _eval(reg, {"now": 0.5, "motion_state": st}, MID)
	assert_str(o["loco_rule"]).is_equal("")
	assert_float(o["speed_mul"]).is_equal(1.0)


func test_hold_is_per_channel() -> void:
	var reg := _reg([
		["l", ["LOCO"], 1, 2.0, "FAR", {"speed_mul": 0.5}],
		["u", ["UPPER"], 1, 0.0, "FAR", {"upper_clip": "Carry"}],
	])
	var st := MotionRules.new_state()
	_eval(reg, _on(["l", "u"], {"now": 0.0, "motion_state": st}))
	var o := _eval(reg, {"now": 0.5, "motion_state": st})
	assert_str(o["loco_rule"]).is_equal("l")
	assert_str(o["upper_rule"]).is_equal("")


func test_a_body_state_is_independent_of_another_body() -> void:
	var reg := _reg([["a", ["LOCO"], 2, 1.0, "FAR", {"speed_mul": 0.4}]])
	var s1 := MotionRules.new_state()
	var s2 := MotionRules.new_state()
	_eval(reg, _on(["a"], {"now": 0.0, "motion_state": s1}))
	assert_str(_eval(reg, {"now": 0.5, "motion_state": s1})["loco_rule"]).is_equal("a")
	assert_str(_eval(reg, {"now": 0.5, "motion_state": s2})["loco_rule"]).is_equal("")


# ---------------------------------------------------------------- tier degrade

func _full_reg() -> MotionRules.Registry:
	return _reg([
		["h", ["HEAD"], 1, 0.0, "FAR", {"look_prio": 3, "look_x": 1.0, "look_hold": 2.0}],
		["u", ["UPPER"], 1, 0.0, "FAR", {"upper_clip": "Life_Carry_Sack_Upper", "u_oneshot": "Wave_Once", "ik": [{"limb": "hand_r", "weight": 1.0}]}],
		["l", ["LOCO"], 1, 0.0, "FAR", {"gait_clip": "Walk", "steer_x": 1.5, "speed_mul": 0.7, "lean": 0.1}],
	], {"villager": {"head_turn_deg": 70, "gait": {"idle": "Idle", "walk": "Walk"}, "vat_set": "adult"}})


func test_near_keeps_everything() -> void:
	var o := _eval(_full_reg(), _on(["h", "u", "l"]), NEAR)
	assert_int(o["look_prio"]).is_equal(3)
	assert_float(o["look_limit"]).is_equal(70.0)
	assert_str(o["upper_clip"]).is_equal("Life_Carry_Sack_Upper")
	assert_str(o["oneshot_clip"]).is_equal("Wave_Once")
	assert_array(o["ik"]).has_size(1)
	assert_float(o["lean"]).is_equal(0.1)


func test_mid_drops_look_and_ik_only() -> void:
	var o := _eval(_full_reg(), _on(["h", "u", "l"]), MID)
	assert_int(o["look_prio"]).is_equal(0)
	assert_float(o["look_limit"]).is_equal(0.0)
	assert_float(o["look_hold"]).is_equal(0.0)
	assert_str(o["head_rule"]).is_equal("")
	assert_array(o["ik"]).is_empty()
	assert_str(o["upper_clip"]).is_equal("Life_Carry_Sack_Upper")
	assert_str(o["oneshot_clip"]).is_equal("Wave_Once")
	assert_float(o["lean"]).is_equal(0.1)
	assert_float(o["steer_x"]).is_equal(1.5)
	assert_float(o["speed_mul"]).is_equal(0.7)


func test_far_keeps_steer_and_the_base_clip_only() -> void:
	var reg := _reg([
		["h", ["HEAD"], 1, 0.0, "FAR", {"look_prio": 3}],
		["u", ["UPPER"], 1, 0.0, "FAR", {"upper_clip": "Talk", "u_oneshot": "Wave_Once", "ik": [{"limb": "hand_r"}]}],
		["l", ["LOCO"], 1, 0.0, "FAR", {"gait_clip": "Walk", "steer_x": 1.5, "speed_mul": 0.7, "lean": 0.1}],
		["b", ["BODY"], 1, 0.0, "FAR", {"reaction": 4, "oneshot_clip": "Flinch"}, []],
	])
	var o := _eval(reg, _on(["h", "u", "l", "b"], {"speed": 1.0}), FAR)
	assert_int(o["look_prio"]).is_equal(0)
	assert_str(o["upper_clip"]).is_equal("")
	assert_str(o["oneshot_clip"]).is_equal("")
	assert_int(o["oneshot_channel"]).is_equal(MotionIntent.NO_CHANNEL)
	assert_int(o["reaction"]).is_equal(0)
	assert_float(o["lean"]).is_equal(0.0)
	assert_array(o["ik"]).is_empty()
	assert_float(o["steer_x"]).is_equal(1.5)
	assert_float(o["speed_mul"]).is_equal(0.7)
	assert_str(o["gait_clip"]).is_equal("Walk")
	assert_str(o["loco_rule"]).is_equal("l")
	assert_str(o["head_rule"]).is_equal("")
	assert_str(o["upper_rule"]).is_equal("")


func test_far_resolves_a_clip_without_a_vat_bake_to_walk_or_idle() -> void:
	var reg := _reg([["l", ["LOCO"], 1, 0.0, "FAR", {"gait_clip": "Life_Walk_Tired"}]], {"child": {"vat_set": "child", "gait": {"idle": "Idle", "walk": "Walk"}}, "villager": {"vat_set": "adult"}})
	# Life_Walk_Tired is baked for the adult set, not the child set
	assert_str(_eval(reg, _on(["l"]), FAR, {"archetype": "villager"})["gait_clip"]).is_equal("Life_Walk_Tired")
	assert_str(_eval(reg, _on(["l"]), FAR, {"archetype": "child"})["gait_clip"]).is_equal("Walk")
	assert_str(_eval(reg, _on(["l"]), NEAR, {"archetype": "child"})["gait_clip"]).is_equal("Life_Walk_Tired")
	# an unbaked clip that is not a walk/run falls back to Idle
	var idle_reg := _reg([["l", ["LOCO"], 1, 0.0, "FAR", {"gait_clip": "Life_Mocap_Cold"}]])
	assert_str(_eval(idle_reg, _on(["l"]), FAR)["gait_clip"]).is_equal("Idle")
	assert_str(_eval(idle_reg, _on(["l"]), MID)["gait_clip"]).is_equal("Life_Mocap_Cold")
	var run_reg := _reg([["l", ["LOCO"], 1, 0.0, "FAR", {"gait_clip": "Run_Natural"}]])
	assert_str(_eval(run_reg, _on(["l"]), FAR)["gait_clip"]).is_equal("Walk")
	# a per-person vat_set override
	assert_str(_eval(reg, _on(["l"]), FAR, {"archetype": "child", "vat_set": "adult"})["gait_clip"]).is_equal("Life_Walk_Tired")


func test_vat_has_reads_the_bake_clip_sets() -> void:
	assert_bool(MotionRules.vat_has("adult", "Walk")).is_true()
	assert_bool(MotionRules.vat_has("nope", "Idle")).is_true()
	assert_bool(MotionRules.vat_has("adult", "Life_Farm_Hoe")).is_true()
	assert_bool(MotionRules.vat_has("guard", "Life_Guard_Attention")).is_true()
	assert_bool(MotionRules.vat_has("child", "Life_Farm_Hoe")).is_false()
	assert_bool(MotionRules.vat_has("nope", "Life_Farm_Hoe")).is_false()


func test_base_gait_per_archetype_from_the_json() -> void:
	var reg := MotionRules.default_registry()
	assert_str(_eval(reg, {"speed": 1.0}, NEAR, {"archetype": "elder"})["gait_clip"]).is_equal("Life_Walk_Elder")
	assert_str(_eval(reg, {"speed": 0.0}, NEAR, {"archetype": "guard"})["gait_clip"]).is_equal("Life_Guard_Attention")
	# both are baked, so FAR keeps them
	assert_str(_eval(reg, {"speed": 1.0}, FAR, {"archetype": "elder"})["gait_clip"]).is_equal("Life_Walk_Elder")
	assert_str(_eval(reg, {"speed": 0.0}, FAR, {"archetype": "guard"})["gait_clip"]).is_equal("Life_Guard_Attention")
	# a persona gait wins over the archetype
	var p := {"archetype": "elder", "gait": {"idle": "Sitting_Idle", "walk": "Life_Walk_Happy"}}
	assert_str(_eval(reg, {"speed": 1.0}, NEAR, p)["gait_clip"]).is_equal("Life_Walk_Happy")
	assert_str(_eval(reg, {"speed": 0.0}, NEAR, p)["gait_clip"]).is_equal("Sitting_Idle")
	# a stop request is not moving
	var stopper := _reg([["l", ["LOCO"], 1, 0.0, "FAR", {"stop": true}]])
	assert_str(_eval(stopper, _on(["l"], {"speed": 2.0}))["gait_clip"]).is_equal("Idle")


# ---------------------------------------------------------------- archetype params from motion_rules.json

func test_json_has_every_archetype_with_the_expected_params() -> void:
	var reg := MotionRules.default_registry()
	for a in ["villager", "child", "elder", "guard", "bandit", "follower", "merchant", "noble"]:
		assert_bool(reg.archetypes.has(a)).is_true()
		var row: Dictionary = reg.archetypes[a]
		for k in ["space_radius_m", "rvo_radius_m", "rvo_priority", "yield_rank", "curiosity", "gesture_amp", "head_turn_deg", "walk_speed_mps", "patience_s", "gait", "vat_set"]:
			assert_bool(row.has(k)).is_true()
		assert_float(float(row["head_turn_deg"])).is_between(30.0, 120.0)
		assert_bool(row["gait"].has("idle") and row["gait"].has("walk")).is_true()
	assert_float(float(reg.archetypes["guard"]["head_turn_deg"])).is_equal(90.0)
	assert_float(reg.archetypes["child"]["walk_speed_mps"]).is_equal(1.5)
	assert_str(reg.archetypes["elder"]["gait"]["walk"]).is_equal("Life_Walk_Elder")


func test_param_persona_overrides_archetype_and_unknown_archetype_falls_back() -> void:
	var reg := MotionRules.default_registry()
	var guard: Dictionary = reg.archetype_of({"archetype": "guard"})
	assert_float(float(MotionRules.param(guard, {}, "head_turn_deg"))).is_equal(90.0)
	assert_float(float(MotionRules.param(guard, {"head_turn_deg": 40}, "head_turn_deg"))).is_equal(40.0)
	assert_float(float(MotionRules.param(guard, {}, "no_such_key", 7.0))).is_equal(7.0)
	assert_float(float(reg.archetype_of({"archetype": "dragon"})["head_turn_deg"])).is_equal(70.0)    # villager row
	assert_float(float(reg.archetype_of({})["head_turn_deg"])).is_equal(70.0)


func test_look_limit_follows_the_archetype_and_persona_head_turn() -> void:
	var arch := {"guard": {"head_turn_deg": 90, "gait": {}, "vat_set": "guard"}, "villager": {"head_turn_deg": 70}}
	var reg := _reg([["h", ["HEAD"], 1, 0.0, "FAR", {"look_prio": 2}]], arch)
	assert_float(_eval(reg, _on(["h"]), NEAR, {"archetype": "guard"})["look_limit"]).is_equal(90.0)
	assert_float(_eval(reg, _on(["h"]), NEAR, {"archetype": "guard", "head_turn_deg": 45})["look_limit"]).is_equal(45.0)
	assert_float(_eval(reg, _on(["h"]), NEAR, {})["look_limit"]).is_equal(70.0)
	assert_float(_eval(reg, {}, NEAR, {"archetype": "guard"})["look_limit"]).is_equal(0.0)     # no look, no limit


func test_rule_functions_see_the_archetype_and_persona() -> void:
	var seen := []
	var probe := func(_c: Dictionary, arch: Dictionary, persona: Dictionary, _r: Dictionary, cand: Dictionary) -> bool:
		cand["speed_mul"] = float(MotionRules.param(arch, persona, "walk_speed_mps")) / 1.35
		seen.append(persona.get("archetype"))
		return true
	var data := {"archetypes": {"villager": {"walk_speed_mps": 1.35}, "elder": {"walk_speed_mps": 0.95}}, "rules": {"p": {"channels": ["LOCO"], "priority": 1, "tier": "FAR"}}}
	var reg := MotionRules.registry_from(data, {"p": probe})
	assert_float(_eval(reg, {}, NEAR, {"archetype": "elder"})["speed_mul"]).is_equal_approx(0.95 / 1.35, 0.0001)
	assert_float(_eval(reg, {}, NEAR, {"archetype": "elder", "walk_speed_mps": 2.7})["speed_mul"]).is_equal_approx(2.0, 0.0001)
	assert_float(_eval(reg, {}, NEAR, {})["speed_mul"]).is_equal_approx(1.0, 0.0001)
	assert_array(seen).has_size(3)


# ---------------------------------------------------------------- the JSON rule table and its stubs

func test_every_json_row_has_a_registered_noop_stub_function() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MotionRules.DATA))
	var rules: Dictionary = d["rules"]
	assert_int(rules.size()).is_equal(41)
	for id: String in rules:
		var row: Dictionary = rules[id]
		var fn := Callable(MotionRules, "rule_" + id.to_lower())
		assert_bool(fn.is_valid()).override_failure_message("rule_%s missing" % id.to_lower()).is_true()
		assert_bool(bool(row.get("stub", false))).override_failure_message("%s is not a stub" % id).is_true()
		assert_bool(MotionRules.TIER_NAMES.has(String(row["tier"]))).is_true()
		for c in row["channels"]:
			assert_bool(MotionIntent.CHANNEL_NAMES.has(String(c))).is_true()
		var cand := MotionIntent.make()
		MotionIntent.reset_cand(cand)
		var before := cand.duplicate(true)
		var ctx := {"speed": 1.0, "act": "work", "carrying": true, "hour": 12.0}
		assert_bool(fn.call(ctx, {}, {}, row, cand)).override_failure_message("%s fired" % id).is_false()
		assert_dict(cand).is_equal(before)
		assert_dict(ctx).has_size(4)


func test_all_stub_registry_is_empty_and_the_real_json_evaluates_to_noop() -> void:
	var reg := MotionRules.default_registry()
	assert_int(reg.count).is_equal(0)
	for tier in [NEAR, MID, FAR]:
		var o := _eval(reg, {"speed": 1.4, "act": "work", "carrying": true, "weather": "rain"}, tier, {"archetype": "villager"})
		assert_bool(MotionIntent.is_noop(o)).is_true()
		assert_str(o["gait_clip"]).is_equal("Walk")
		for k in ["body_rule", "loco_rule", "upper_rule", "head_rule"]:
			assert_str(o[k]).is_equal("")


func test_flipping_a_row_off_stub_registers_it_and_the_bound_function_runs() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MotionRules.DATA))
	var live: Dictionary = d["rules"]["S2"]
	live["stub"] = false
	var reg := MotionRules.registry_from(d)
	assert_int(reg.count).is_equal(1)
	assert_str(reg.ids[0]).is_equal("S2")
	assert_int(reg.max_tier[0]).is_equal(MID)
	assert_float(reg.hold[0]).is_equal(0.6)
	assert_bool(MotionIntent.is_noop(_eval(reg, {"speed": 1.0}))).is_true()      # rule_s2 is still the stub body


func test_registry_from_a_missing_or_broken_file_is_empty_and_safe() -> void:
	var reg := MotionRules.registry_from_file("res://data/living_world/does_not_exist.json")
	assert_int(reg.count).is_equal(0)
	var o := _eval(reg, {"speed": 1.0})
	assert_str(o["gait_clip"]).is_equal("Walk")


# ---------------------------------------------------------------- determinism and in-place reuse

func _busy_reg() -> MotionRules.Registry:
	return _reg([
		["h", ["HEAD"], 2, 1.0, "NEAR", {"look_prio": 2, "look_x": 4.0}],
		["u", ["UPPER"], 2, 0.5, "MID", {"upper_clip": "Talk", "ik": [{"limb": "hand_l", "weight": 0.5}]}],
		["l1", ["LOCO"], 2, 1.0, "FAR", {"speed_mul": 0.7, "gait_clip": "Life_Walk_Tired"}],
		["l2", ["LOCO"], 3, 0.0, "FAR", {"speed_mul": 0.4, "steer_z": 1.0}],
		["b", ["BODY"], 5, 2.0, "MID", {"reaction": 2, "oneshot_clip": "Flinch", "b_speed_mul": 0.0, "b_stop": true}],
	])


func _drive(reg: MotionRules.Registry, steps: int, tier: int) -> Array:
	var st := MotionRules.new_state()
	var out := MotionIntent.make()
	var log := []
	for i in steps:
		var ctx := {"now": float(i) * 0.1, "motion_state": st, "speed": 1.0 if i % 7 else 0.0}
		for id in ["h", "u", "l1", "l2", "b"]:
			ctx[id] = hash([id, i]) % 3 == 0
		MotionRules.evaluate_into(out, ctx, {"archetype": "villager"}, tier, reg)
		log.append(out.duplicate(true))
	return log


func test_evaluation_is_deterministic_per_tier() -> void:
	for tier in [NEAR, MID, FAR]:
		assert_array(_drive(_busy_reg(), 300, tier)).is_equal(_drive(_busy_reg(), 300, tier))


func test_evaluate_and_evaluate_into_agree_and_reuse_leaves_no_residue() -> void:
	var reg := _busy_reg()
	var ctx := {"now": 1.0, "speed": 1.0, "h": true, "u": true, "l2": true, "b": true}
	var fresh := _eval(reg, ctx)
	var dirty := MotionIntent.make()
	MotionRules.evaluate_into(dirty, _on(["h", "u", "l1", "l2", "b"], {"now": 5.0, "speed": 3.0}), {"archetype": "guard"}, NEAR, reg)
	MotionRules.evaluate_into(dirty, ctx, {}, NEAR, reg)
	assert_dict(dirty).is_equal(fresh)
	# the allocating helper uses the default registry (all stubs): neutral
	assert_bool(MotionIntent.is_noop(MotionRules.evaluate({"speed": 1.0}, {}, NEAR))).is_true()
	# the ik list of the intent is owned: mutating one result never leaks into the rule or the next evaluation
	var o1 := _eval(reg, _on(["u"]))
	(o1["ik"] as Array).append("junk")
	assert_array(_eval(reg, _on(["u"]))["ik"]).has_size(1)


func test_intent_keys_are_a_fixed_set() -> void:
	var reg := _busy_reg()
	var keys := MotionIntent.make().keys()
	for tier in [NEAR, MID, FAR, OUT]:
		assert_array(_eval(reg, _on(["h", "u", "l1", "l2", "b"]), tier).keys()).is_equal(keys)


# ---------------------------------------------------------------- cost (printed; loose limit)

func test_cost_24_contexts_x_1000_evaluations() -> void:
	var reg := _busy_reg()
	var intents: Array = []
	var ctxs: Array = []
	var states: Array = []
	for i in 24:
		intents.append(MotionIntent.make())
		states.append(MotionRules.new_state())
		var c := {"now": 0.0, "speed": 1.0, "motion_state": states[i], "heading": float(i), "carrying": i % 2 == 0, "act": "work"}
		for id in ["h", "u", "l1", "l2", "b"]:
			c[id] = (i + id.length()) % 2 == 0
		ctxs.append(c)
	var persona := {"archetype": "villager"}
	var results := []
	for tier in [NEAR, MID, FAR]:
		var t0 := Time.get_ticks_usec()
		for n in 1000:
			for i in 24:
				var c: Dictionary = ctxs[i]
				c["now"] = float(n) * 0.1
				MotionRules.evaluate_into(intents[i], c, persona, tier, reg)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		results.append(ms)
	var t1 := Time.get_ticks_usec()
	for n in 1000:
		for i in 24:
			MotionRules.evaluate_into(intents[i], ctxs[i], persona, NEAR)       # the shipped (all-stub) registry
	var ms_default := float(Time.get_ticks_usec() - t1) / 1000.0
	print("M1 BUDGET  24 ctx x 1000 evaluate_into, 5 live test rules: NEAR %.1f ms  MID %.1f ms  FAR %.1f ms  (%.2f us/call NEAR)   shipped registry NEAR %.1f ms (%.2f us/call)" % [
		results[0], results[1], results[2], results[0] * 1000.0 / 24000.0, ms_default, ms_default * 1000.0 / 24000.0])
	assert_float(results[0]).is_less(3000.0)
	assert_float(ms_default).is_less(1500.0)
