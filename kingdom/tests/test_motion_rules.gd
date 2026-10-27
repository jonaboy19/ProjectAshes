extends GdUnitTestSuite
## M1 core of docs/plans/NPC_MOTION_RULES.md: channel arbitration, hysteresis, tier degrade, archetypes, stubs, cost.
## (scripts/living_world/motion_rules.gd, motion_intent.gd, data/living_world/motion_rules.json)

const MR := preload("res://scripts/living_world/motion_rules.gd")
const MI := preload("res://scripts/living_world/motion_intent.gd")
const NEAR := 0
const MID := 1
const FAR := 2
const OUT := 3

const SECTION3_IDS := [
	"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8",
	"A1", "A2", "A3", "A4", "A5",
	"R1", "R2", "R3", "R4", "R5", "R6", "R7",
	"O1", "O2", "O3", "O4", "O5",
	"L1", "L2", "L3", "L4", "L5", "L6",
	"G1", "G2", "G3", "G4",
	"C1", "C2", "C3",
	"B1", "B2", "B3",
]


func after_test() -> void:
	MR.reload()


func _row(id: String, channel: String, prio: int, hold := 0.0, tier := "far") -> Dictionary:
	return {"id": id, "channel": channel, "priority": prio, "min_hold_s": hold, "tier": tier}


func _pay(payload: Dictionary) -> Callable:
	return func(_c: Dictionary, _p: Dictionary, _prm: Dictionary) -> Dictionary: return payload


func _setup(rows: Array, payloads: Dictionary) -> void:
	var funcs := {}
	for id: String in payloads:
		funcs[id] = _pay(payloads[id])
	MR.load_rows(rows, funcs)


func _eval(tier := NEAR, ctx := {}) -> Dictionary:
	return MR.evaluate(ctx, {}, tier)


# ---------------------------------------------------------------- arbitration

func test_idle_registry_gives_the_neutral_intent() -> void:
	var i := _eval(NEAR, {"clip": "Walk", "rate": 1.2})
	assert_str(i["gait"]["clip"]).is_equal("Walk")
	assert_float(i["gait"]["rate"]).is_equal(1.2)
	assert_float(i["steer"]["speed_mul"]).is_equal(1.0)
	assert_bool(i["steer"]["stop"]).is_false()
	assert_object(i["look"]["target"]).is_null()
	assert_str(i["upper"]).is_equal("")
	assert_int(i["reaction"]).is_equal(0)
	assert_array(i["ik"]).is_empty()
	assert_array(i["winners"]).is_equal(["", "", "", ""])


func test_truth_table_independent_channels_all_apply() -> void:
	_setup([_row("H", "head", 1), _row("U", "upper", 1), _row("L", "loco", 1)], {
		"H": {"look": {"target": Vector3(1, 2, 3)}},
		"U": {"upper": "Carry"},
		"L": {"steer": {"speed_mul": 0.5}},
	})
	var i := _eval()
	assert_vector(i["look"]["target"]).is_equal(Vector3(1, 2, 3))
	assert_str(i["upper"]).is_equal("Carry")
	assert_float(i["steer"]["speed_mul"]).is_equal(0.5)
	assert_array(i["winners"]).is_equal(["H", "U", "L", ""])


func test_truth_table_body_suppresses_loco_and_upper_but_not_head() -> void:
	_setup([_row("H", "head", 1), _row("U", "upper", 1), _row("L", "loco", 9), _row("B", "body", 1)], {
		"H": {"look": {"target": Vector3.ONE}},
		"U": {"upper": "Carry"},
		"L": {"steer": {"speed_mul": 0.5}},
		"B": {"reaction": 11, "oneshot": {"clip": "Flee_Start"}},
	})
	var i := _eval()
	assert_array(i["winners"]).is_equal(["H", "", "", "B"])
	assert_str(i["upper"]).is_equal("")
	assert_float(i["steer"]["speed_mul"]).is_equal(1.0)
	assert_int(i["reaction"]).is_equal(11)
	assert_vector(i["look"]["target"]).is_equal(Vector3.ONE)
	assert_str(i["oneshot"]["clip"]).is_equal("Flee_Start")
	assert_int(i["oneshot"]["channel"]).is_equal(MI.Channel.BODY)   # filled in from the winning row


func test_truth_table_priority_within_channel() -> void:
	_setup([_row("LO", "loco", 2), _row("HI", "loco", 5), _row("MID", "loco", 3)], {
		"LO": {"gait": {"clip": "Lo"}}, "HI": {"gait": {"clip": "Hi"}}, "MID": {"gait": {"clip": "Mid"}},
	})
	var i := _eval()
	assert_str(i["gait"]["clip"]).is_equal("Hi")
	assert_array(i["winners"]).is_equal(["", "", "HI", ""])


func test_truth_table_tie_goes_to_the_first_row() -> void:
	_setup([_row("A", "loco", 3), _row("B", "loco", 3)], {"A": {"gait": {"clip": "A"}}, "B": {"gait": {"clip": "B"}}})
	assert_str(_eval()["gait"]["clip"]).is_equal("A")


func test_look_priority_defaults_to_the_row_priority() -> void:
	_setup([_row("H", "head", 4)], {"H": {"look": {"target": Vector3.ONE, "hold_s": 2.0}}})
	var i := _eval()
	assert_int(i["look"]["priority"]).is_equal(4)
	assert_float(i["look"]["hold_s"]).is_equal(2.0)


func test_disabled_and_noop_rules_do_not_win() -> void:
	var rows := [_row("A", "loco", 9), _row("B", "loco", 1)]
	rows[0]["enabled"] = false
	_setup(rows, {"A": {"gait": {"clip": "A"}}, "B": {}})
	assert_array(_eval()["winners"]).is_equal(["", "", "", ""])


# ---------------------------------------------------------------- hysteresis

func test_hysteresis_holds_the_winner_for_min_hold() -> void:
	var fire := {"a": true}
	var funcs := {
		"X": func(_c, _p, _prm) -> Dictionary: return {"gait": {"clip": "X"}} if fire["a"] else MR.NOOP,
		"Y": _pay({"gait": {"clip": "Y"}}),
	}
	MR.load_rows([_row("X", "loco", 1, 1.0), _row("Y", "loco", 1, 0.0)], funcs)
	var st := MI.new_state()
	var ctx := {"state": st, "time": 0.0}
	assert_str(MR.evaluate(ctx, {}, NEAR)["gait"]["clip"]).is_equal("X")   # first row wins the tie, held 1 s
	fire["a"] = false
	ctx["time"] = 0.5
	assert_str(MR.evaluate(ctx, {}, NEAR)["gait"]["clip"]).is_equal("X")   # X silent, Y equal priority: still X
	ctx["time"] = 1.01
	var i := MR.evaluate(ctx, {}, NEAR)
	assert_str(i["gait"]["clip"]).is_equal("Y")                            # hold over, Y takes it
	assert_array(i["winners"]).is_equal(["", "", "Y", ""])


func test_hysteresis_is_preempted_only_by_strictly_higher_priority() -> void:
	var on := {"hi": false, "same": false}
	var funcs := {
		"X": _pay({"gait": {"clip": "X"}}),
		"Y": func(_c, _p, _prm) -> Dictionary: return {"gait": {"clip": "Y"}} if on["same"] else MR.NOOP,
		"Z": func(_c, _p, _prm) -> Dictionary: return {"gait": {"clip": "Z"}} if on["hi"] else MR.NOOP,
	}
	MR.load_rows([_row("X", "loco", 2, 2.0), _row("Y", "loco", 2, 0.0), _row("Z", "loco", 3, 0.0)], funcs)
	var ctx := {"state": MI.new_state(), "time": 0.0}
	assert_str(MR.evaluate(ctx, {}, NEAR)["gait"]["clip"]).is_equal("X")
	on["same"] = true
	ctx["time"] = 0.5
	assert_str(MR.evaluate(ctx, {}, NEAR)["gait"]["clip"]).is_equal("X")   # equal priority does not preempt
	on["hi"] = true
	ctx["time"] = 0.6
	assert_str(MR.evaluate(ctx, {}, NEAR)["gait"]["clip"]).is_equal("Z")   # higher priority preempts mid-hold


func test_hysteresis_refreshes_payload_of_the_held_rule() -> void:
	var v := {"n": 0.5}
	MR.load_rows([_row("X", "loco", 1, 5.0)], {"X": func(_c, _p, _prm) -> Dictionary: return {"steer": {"speed_mul": v["n"]}}})
	var ctx := {"state": MI.new_state(), "time": 0.0}
	assert_float(MR.evaluate(ctx, {}, NEAR)["steer"]["speed_mul"]).is_equal(0.5)
	v["n"] = 0.8
	ctx["time"] = 1.0
	assert_float(MR.evaluate(ctx, {}, NEAR)["steer"]["speed_mul"]).is_equal(0.8)


func test_no_state_means_no_hold() -> void:
	var fire := {"a": true}
	MR.load_rows([_row("X", "loco", 1, 9.0)], {"X": func(_c, _p, _prm) -> Dictionary: return {"gait": {"clip": "X"}} if fire["a"] else MR.NOOP})
	assert_str(MR.evaluate({}, {}, NEAR)["gait"]["clip"]).is_equal("X")
	fire["a"] = false
	assert_str(MR.evaluate({}, {}, NEAR)["gait"]["clip"]).is_equal("")


func test_hold_is_per_channel_and_per_body() -> void:
	_setup([_row("X", "loco", 1, 3.0)], {"X": {"gait": {"clip": "X"}}})
	var a := {"state": MI.new_state(), "time": 0.0}
	var b := {"state": MI.new_state(), "time": 0.0}
	MR.evaluate(a, {}, NEAR)
	assert_int(a["state"]["rule"][MI.Channel.LOCO]).is_equal(0)
	assert_int(b["state"]["rule"][MI.Channel.LOCO]).is_equal(-1)
	assert_int(a["state"]["rule"][MI.Channel.HEAD]).is_equal(-1)


# ---------------------------------------------------------------- tiers

func _all_keys_rows() -> void:
	_setup([_row("H", "head", 1), _row("U", "upper", 1), _row("L", "loco", 1), _row("B", "body", 1)], {
		"H": {"look": {"target": Vector3.ONE}, "ik": [{"limb": "hand_r", "target": Vector3.UP, "weight": 1.0}]},
		"U": {"upper": "Carry", "lean": 0.05},
		"L": {"steer": {"speed_mul": 0.4, "offset": Vector3(0.5, 0, 0)}, "gait": {"clip": "Life_Walk_Tired", "rate": 1.1}},
		"B": {"oneshot": {"clip": "Flinch"}, "reaction": 6},
	})


func test_degrade_near_keeps_everything() -> void:
	_all_keys_rows()
	var i := _eval(NEAR, {"speed": 1.0})
	assert_object(i["look"]["target"]).is_not_null()
	assert_array(i["ik"]).has_size(1)
	assert_int(i["reaction"]).is_equal(6)
	assert_str(i["oneshot"]["clip"]).is_equal("Flinch")


func test_degrade_mid_drops_look_and_ik() -> void:
	_all_keys_rows()
	var i := _eval(MID, {"speed": 1.0})
	assert_object(i["look"]["target"]).is_null()
	assert_int(i["look"]["priority"]).is_equal(0)
	assert_array(i["ik"]).is_empty()
	assert_int(i["reaction"]).is_equal(6)
	assert_str(i["oneshot"]["clip"]).is_equal("Flinch")


func test_degrade_far_keeps_steer_and_base_clip_only() -> void:
	_setup([_row("H", "head", 1), _row("U", "upper", 1), _row("L", "loco", 1)], {
		"H": {"look": {"target": Vector3.ONE}, "ik": [{"limb": "hand_r", "target": Vector3.UP, "weight": 1.0}]},
		"U": {"upper": "Carry", "lean": 0.05, "oneshot": {"clip": "Flinch"}, "reaction": 6},
		"L": {"steer": {"speed_mul": 0.4, "offset": Vector3(0.5, 0, 0)}, "gait": {"clip": "Life_Walk_Elder", "rate": 1.1}},
	})
	var i := _eval(FAR, {"speed": 1.0})
	assert_object(i["look"]["target"]).is_null()
	assert_array(i["ik"]).is_empty()
	assert_str(i["upper"]).is_equal("")
	assert_str(i["oneshot"]["clip"]).is_equal("")
	assert_float(i["lean"]).is_equal(0.0)
	assert_int(i["reaction"]).is_equal(0)
	assert_float(i["steer"]["speed_mul"]).is_equal(0.4)
	assert_vector(i["steer"]["offset"]).is_equal(Vector3(0.5, 0, 0))
	assert_str(i["gait"]["clip"]).is_equal("Life_Walk_Elder")   # baked in the VAT set
	assert_float(i["gait"]["rate"]).is_equal(1.1)


func test_far_clip_without_vat_resolves_to_walk_or_idle() -> void:
	_all_keys_rows()   # Life_Walk_Tired is in vat_bake, so use an unbaked clip through ctx instead
	MR.load_rows([], {})
	assert_str(MR.evaluate({"clip": "Life_Mocap_Cold", "speed": 1.2}, {}, FAR)["gait"]["clip"]).is_equal("Walk")
	assert_str(MR.evaluate({"clip": "Life_Mocap_Cold", "speed": 0.0}, {}, FAR)["gait"]["clip"]).is_equal("Idle")
	assert_str(MR.evaluate({"clip": "Life_Mocap_Cold", "moving": true}, {}, FAR)["gait"]["clip"]).is_equal("Walk")
	assert_str(MR.evaluate({"clip": "", "speed": 2.0}, {}, FAR)["gait"]["clip"]).is_equal("Walk")
	assert_str(MR.evaluate({"clip": "Life_Walk_Happy", "speed": 1.0}, {}, FAR)["gait"]["clip"]).is_equal("Life_Walk_Happy")
	# the same unbaked clip is untouched at NEAR and MID
	assert_str(MR.evaluate({"clip": "Life_Mocap_Cold"}, {}, NEAR)["gait"]["clip"]).is_equal("Life_Mocap_Cold")
	assert_str(MR.evaluate({"clip": "Life_Mocap_Cold"}, {}, MID)["gait"]["clip"]).is_equal("Life_Mocap_Cold")


func test_far_stopped_body_resolves_to_idle_even_if_speed_is_set() -> void:
	_setup([_row("L", "loco", 1)], {"L": {"steer": {"stop": true}, "gait": {"clip": "Unbaked"}}})
	assert_str(MR.evaluate({"speed": 1.0}, {}, FAR)["gait"]["clip"]).is_equal("Idle")


func test_out_tier_is_empty() -> void:
	_all_keys_rows()
	var i := _eval(OUT, {"clip": "Walk"})
	assert_str(i["gait"]["clip"]).is_equal("")
	assert_array(i["winners"]).is_equal(["", "", "", ""])
	assert_int(i["tier"]).is_equal(OUT)


func test_rule_tier_gates_which_rules_run() -> void:
	_setup([_row("N", "head", 1, 0.0, "near"), _row("M", "loco", 1, 0.0, "mid"), _row("F", "upper", 1, 0.0, "far")], {
		"N": {"look": {"target": Vector3.ONE}}, "M": {"steer": {"speed_mul": 0.3}}, "F": {"upper": "Carry"},
	})
	assert_array(_eval(NEAR)["winners"]).is_equal(["N", "F", "M", ""])
	assert_array(_eval(MID)["winners"]).is_equal(["", "F", "M", ""])
	assert_array(_eval(FAR)["winners"]).is_equal(["", "F", "", ""])
	assert_str(_eval(FAR)["upper"]).is_equal("")   # far-tier rule ran, but the degrade table still strips upper


func test_held_rule_below_the_current_tier_is_dropped() -> void:
	_setup([_row("M", "loco", 1, 9.0, "mid")], {"M": {"steer": {"speed_mul": 0.3}}})
	var ctx := {"state": MI.new_state(), "time": 0.0}
	MR.evaluate(ctx, {}, NEAR)
	ctx["time"] = 1.0
	var i := MR.evaluate(ctx, {}, FAR)   # a mid rule must not keep steering a far body through the hold
	assert_float(i["steer"]["speed_mul"]).is_equal(1.0)


# ---------------------------------------------------------------- data, archetypes, stubs

func test_archetypes_carry_the_design_numbers() -> void:
	var names := MR.archetype_names()
	for n: String in ["villager", "child", "elder", "guard", "bandit", "follower", "merchant", "noble"]:
		assert_bool(names.has(n)).is_true()
		var a := MR.archetype({"archetype": n})
		for k: String in ["space_radius", "rvo_radius", "rvo_priority", "yield_rank", "curiosity", "gesture_amp", "head_limit_deg", "gaits"]:
			assert_bool(a.has(k)).is_true()
	assert_float(MR.archetype({"archetype": "guard"})["rvo_radius"]).is_equal(0.9)
	assert_float(MR.archetype({"archetype": "noble"})["rvo_radius"]).is_equal(0.8)
	assert_float(MR.archetype({"archetype": "villager"})["rvo_radius"]).is_equal(0.5)
	assert_float(MR.archetype({"archetype": "child"})["rvo_radius"]).is_equal(0.3)
	assert_float(MR.archetype({})["rvo_radius"]).is_equal(0.5)                 # default villager
	assert_float(MR.archetype({"archetype": "dragon"})["rvo_radius"]).is_equal(0.5)   # unknown falls back
	# children give way, elders and nobles are given way to
	assert_int(int(MR.archetype({"archetype": "child"})["yield_rank"])).is_less(MR.archetype({"archetype": "villager"})["yield_rank"])
	assert_int(int(MR.archetype({"archetype": "elder"})["yield_rank"])).is_greater(MR.archetype({"archetype": "villager"})["yield_rank"])


func test_every_section3_id_is_registered_as_a_noop_stub() -> void:
	var ids := MR.rule_ids()
	assert_int(ids.size()).is_equal(SECTION3_IDS.size())
	for id: String in SECTION3_IDS:
		assert_bool(ids.has(id)).is_true()
		assert_bool(MR.is_stub(id)).is_true()
		var fn := Callable(MR, "rule_" + id.to_lower())
		assert_bool(fn.is_valid()).is_true()
		assert_bool((fn.call({}, {}, {}) as Dictionary).is_empty()).is_true()


func test_json_rows_are_well_formed() -> void:
	var seen := {}
	for id: String in MR.rule_ids():
		assert_bool(seen.has(id)).is_false()
		seen[id] = true
		var i := MR.index_of(id)
		assert_int(MR._chan[i]).is_between(0, 3)
		assert_int(MR._tier[i]).is_between(0, 2)
		assert_float(MR._hold[i]).is_between(0.0, 10.0)
		assert_int(MR._prio[i]).is_between(0, 9)


func test_json_params_hold_the_design_thresholds() -> void:
	assert_float(MR.params_of("S3")["max_corridor_m"]).is_equal(1.6)
	assert_float(MR.params_of("S4")["stop_dist_m"]).is_equal(2.6)
	assert_float(MR.params_of("A1")["look_slots_high"]).is_equal(6.0)
	assert_float(MR.params_of("R3")["wave_mps"]).is_equal(6.0)
	assert_float(MR.params_of("L2")["max_roll_deg"]).is_equal(5.0)
	assert_float(MR.params_of("L3")["rate_min"]).is_equal(0.75)
	assert_float(MR.params_of("G1")["radius_per_person_m"]).is_equal(0.25)


func test_full_stub_registry_evaluates_to_the_neutral_intent_at_every_tier() -> void:
	for t in 4:
		var i := MR.evaluate({"clip": "Walk"}, {"archetype": "guard"}, t)
		assert_array(i["winners"]).is_equal(["", "", "", ""])
		assert_float(i["steer"]["speed_mul"]).is_equal(1.0)
		assert_int(i["reaction"]).is_equal(0)


func test_register_replaces_a_stub_and_participates() -> void:
	assert_bool(MR.register("S2", _pay({"steer": {"speed_mul": 0.4}}))).is_true()
	assert_bool(MR.is_stub("S2")).is_false()
	var i := _eval(NEAR)
	assert_float(i["steer"]["speed_mul"]).is_equal(0.4)
	assert_array(i["winners"]).is_equal(["", "", "S2", ""])
	assert_bool(MR.register("nope", _pay({}))).is_false()


func test_rules_receive_ctx_persona_and_their_params() -> void:
	var seen := {}
	MR.register("S3", func(c: Dictionary, p: Dictionary, prm: Dictionary) -> Dictionary:
		seen["c"] = c.get("marker")
		seen["p"] = MR.archetype(p)["rvo_radius"]
		seen["prm"] = prm["max_corridor_m"]
		return MR.NOOP)
	MR.evaluate({"marker": 7}, {"archetype": "guard"}, NEAR)
	assert_int(seen["c"]).is_equal(7)
	assert_float(seen["p"]).is_equal(0.9)
	assert_float(seen["prm"]).is_equal(1.6)


func test_deterministic() -> void:
	MR.register("S2", func(c: Dictionary, p: Dictionary, _prm: Dictionary) -> Dictionary:
		return {"steer": {"speed_mul": 0.3 + MR.h01(int(p.get("person", 0)), 3) * 0.2}})
	var a := MR.evaluate({"clip": "Walk"}, {"person": 41}, NEAR)
	var b := MR.evaluate({"clip": "Walk"}, {"person": 41}, NEAR)
	assert_dict(a).is_equal(b)
	assert_float(MR.h01(41, 3)).is_equal(MR.h01(41, 3))
	assert_float(MR.h01(41, 3)).is_not_equal(MR.h01(42, 3))
	for s in 50:
		assert_float(MR.h01(s, 9)).is_between(0.0, 1.0)


func test_evaluate_into_reuses_the_intent_without_leaking_state() -> void:
	_setup([_row("L", "loco", 1), _row("H", "head", 1)], {"L": {"steer": {"speed_mul": 0.4}, "gait": {"clip": "X"}}, "H": {"look": {"target": Vector3.ONE}}})
	var out := MI.make()
	MR.evaluate_into({}, {}, NEAR, out)
	assert_object(out["look"]["target"]).is_not_null()
	MR.load_rows([], {})
	MR.evaluate_into({}, {}, NEAR, out)
	assert_object(out["look"]["target"]).is_null()
	assert_float(out["steer"]["speed_mul"]).is_equal(1.0)
	assert_str(out["gait"]["clip"]).is_equal("")
	assert_array(out["winners"]).is_equal(["", "", "", ""])


# ---------------------------------------------------------------- cost

func _busy_registry() -> void:
	# Ten live rules across all channels, each doing a little real arithmetic like a real rule would.
	var rows := []
	var funcs := {}
	for k in 10:
		var id := "T%d" % k
		rows.append(_row(id, MI.CHANNEL_NAMES[k % 4], 1 + k % 5, 0.3, "far"))
		funcs[id] = func(c: Dictionary, p: Dictionary, _prm: Dictionary) -> Dictionary:
			var d: float = (c["pos"] as Vector3).distance_to(c["player"])
			if d > 6.0 + k:
				return MR.NOOP
			return {"steer": {"speed_mul": clampf(d * 0.2, 0.4, 1.0)}} if k % 4 == 2 else MR.NOOP
	MR.load_rows(rows, funcs)


func _bench(tier: int, bodies: int, evals: int) -> float:
	var ctxs := []
	var states := []
	for b in bodies:
		ctxs.append({"pos": Vector3(b * 1.3, 0, b * 0.7), "player": Vector3(4, 0, 4), "clip": "Walk", "speed": 1.2, "time": 0.0, "state": MI.new_state()})
	var out := MI.make()
	var persona := {"archetype": "villager", "person": 1}
	var t0 := Time.get_ticks_usec()
	for e in evals:
		for b in bodies:
			var c: Dictionary = ctxs[b]
			c["time"] = e * 0.3
			MR.evaluate_into(c, persona, tier, out)
	return float(Time.get_ticks_usec() - t0)


func test_cost_24_contexts_x_1000_evaluations() -> void:
	_busy_registry()
	var near_us := _bench(NEAR, 24, 1000)
	var mid_us := _bench(MID, 24, 1000)
	var far_us := _bench(FAR, 24, 1000)
	var near_per := near_us / 24000.0
	var mid_per := mid_us / 24000.0
	var far_per := far_us / 24000.0
	print("MotionRules cost per evaluation (10 live rules): NEAR %.1f us  MID %.1f us  FAR %.1f us  | 24 bodies NEAR = %.3f ms per pass" % [near_per, mid_per, far_per, near_per * 24.0 / 1000.0])
	# Loose CI limit (design budget is 0.15 ms for 24 NEAR bodies per frame, 0.02 ms per MID body).
	assert_float(near_us / 1000.0).is_less(4000.0)
	assert_float(mid_us / 1000.0).is_less(4000.0)
	assert_float(far_us / 1000.0).is_less(4000.0)


func test_cost_shipped_registry_is_nearly_free() -> void:
	var t := _bench(NEAR, 24, 1000)
	print("MotionRules cost per evaluation (shipped stub registry): %.2f us | 24 bodies = %.4f ms per pass" % [t / 24000.0, t / 24000.0 * 24.0 / 1000.0])
	assert_float(t / 1000.0).is_less(2000.0)
