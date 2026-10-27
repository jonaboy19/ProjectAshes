extends GdUnitTestSuite
## MotionRules (M1 core of docs/plans/NPC_MOTION_RULES.md): rule registry from motion_rules.json, channel arbitration
## BODY > LOCO > UPPER > HEAD, priority, min_hold_s hysteresis, tier degrade, stubs, archetype numbers and cost.

const MR := preload("res://scripts/living_world/motion_rules.gd")
const MI := preload("res://scripts/living_world/motion_intent.gd")
const BODY := MI.Channel.BODY
const LOCO := MI.Channel.LOCO
const UPPER := MI.Channel.UPPER
const HEAD := MI.Channel.HEAD
const SECTION3_IDS := ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "A1", "A2", "A3", "A4", "A5", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
	"O1", "O2", "O3", "O4", "O5", "L1", "L2", "L3", "L4", "L5", "L6", "G1", "G2", "G3", "G4", "C1", "C2", "C3", "B1", "B2", "B3"]
const ARCHETYPES := ["villager", "child", "elder", "guard", "bandit", "follower", "merchant", "noble"]

var _real: Dictionary


func before() -> void:
	_real = JSON.parse_string(FileAccess.get_file_as_string(MR.DATA))


# --- fixture: test rules driven by ctx["fire"][id] = {candidate field: value} -------------------------------------------------

## Test rule: counts the call, then fires with the fields the context asks for.
func _t(ctx: Dictionary, _arch: Dictionary, _persona: Dictionary, _row: Dictionary, cand: Dictionary, id: String) -> bool:
	ctx["calls"] = int(ctx.get("calls", 0)) + 1
	var fire: Dictionary = ctx.get("fire", {})
	if not fire.has(id):
		return false
	var f: Dictionary = fire[id]
	for k: String in f:
		cand[k] = f[k]
	return true


func _row(channels: Array, prio: int, hold := 0.0, tier := "NEAR", extra := {}) -> Dictionary:
	var r := {"enabled": true, "stub": false, "channels": channels, "priority": prio, "min_hold_s": hold, "tier": tier}
	r.merge(extra, true)
	return r


func _reg(rows: Dictionary) -> MotionRules.Registry:
	var fns := {}
	for id: String in rows:
		fns[id] = Callable(self, "_t").bind(id)
	return MR.registry_from({"archetypes": _real["archetypes"], "rules": rows}, fns)


func _eval(reg: MotionRules.Registry, fire: Dictionary, tier := MR.TIER_NEAR, extra := {}, persona := {"archetype": "villager"}) -> Dictionary:
	var ctx := {"fire": fire, "speed": 1.2}
	ctx.merge(extra)
	var out := MI.make()
	MR.evaluate_into(out, ctx, persona, tier, reg)
	return out


# --- stubs, data, archetypes ----------------------------------------------------------------------------------------------

func test_every_section3_id_has_a_row_and_a_noop_stub() -> void:
	var rules: Dictionary = _real["rules"]
	assert_int(rules.size()).is_equal(SECTION3_IDS.size())
	for id: String in SECTION3_IDS:
		assert_bool(rules.has(id)).is_true()
		var row: Dictionary = rules[id]
		assert_bool(row["stub"]).is_true()
		assert_bool(Callable(MR, "rule_" + id.to_lower()).is_valid()).is_true()
		var cand := MI.make()
		MI.reset_cand(cand)
		var before_state := cand.duplicate(true)
		var fired: bool = Callable(MR, "rule_" + id.to_lower()).call({}, {}, {}, row, cand)
		assert_bool(fired).is_false()
		assert_dict(cand).is_equal(before_state)


func test_rows_are_well_formed() -> void:
	var rules: Dictionary = _real["rules"]
	for id: String in rules:
		var row: Dictionary = rules[id]
		for c: String in row["channels"]:
			assert_bool(MI.CHANNEL_NAMES.has(c)).is_true()
		assert_bool(MR.TIER_NAMES.has(String(row["tier"]))).is_true()
		assert_bool(int(row["priority"]) >= 0 and int(row["priority"]) <= 8).is_true()
		assert_bool(float(row["min_hold_s"]) >= 0.0).is_true()
		assert_bool(row["params"] is Dictionary).is_true()


func test_stub_rules_are_not_registered_so_default_evaluation_is_noop() -> void:
	assert_int(MR.default_registry().count).is_equal(0)
	var out := MR.evaluate({"speed": 1.0}, {"archetype": "villager"}, MR.TIER_NEAR)
	assert_bool(MI.is_noop(out)).is_true()
	assert_str(out["gait_clip"]).is_equal("Walk")


func test_archetype_table_has_the_section3_numbers() -> void:
	var a: Dictionary = _real["archetypes"]
	for n: String in ARCHETYPES:
		assert_bool(a.has(n)).is_true()
		for k: String in ["space_radius_m", "rvo_radius_m", "rvo_priority", "yield_rank", "curiosity", "gesture_amp", "head_turn_deg", "walk_speed_mps", "patience_s", "gait", "vat_set"]:
			assert_bool((a[n] as Dictionary).has(k)).is_true()
	assert_float(a["guard"]["rvo_radius_m"]).is_equal(0.9)
	assert_float(a["noble"]["rvo_radius_m"]).is_equal(0.8)
	assert_float(a["villager"]["rvo_radius_m"]).is_equal(0.5)
	assert_float(a["child"]["rvo_radius_m"]).is_equal(0.3)
	# elders and the loaded give way: rank above a villager, a child ranks lowest, nobles highest
	assert_bool(a["elder"]["yield_rank"] > a["villager"]["yield_rank"]).is_true()
	assert_bool(a["child"]["yield_rank"] < a["villager"]["yield_rank"]).is_true()
	assert_bool(a["noble"]["yield_rank"] > a["guard"]["yield_rank"]).is_true()


func test_unknown_archetype_falls_back_to_villager_and_persona_overrides() -> void:
	var reg := _reg({})
	var out := MI.make()
	MR.evaluate_into(out, {"speed": 1.0}, {"archetype": "dragon"}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Walk")
	MR.evaluate_into(out, {"speed": 1.0}, {"archetype": "elder"}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Elder")
	MR.evaluate_into(out, {"speed": 1.0}, {"archetype": "elder", "gait": {"walk": "Life_Walk_Happy", "idle": "Idle"}}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Happy")
	var arch: Dictionary = _real["archetypes"]["guard"]
	assert_float(MR.param(arch, {}, "rvo_radius_m")).is_equal(0.9)
	assert_float(MR.param(arch, {"rvo_radius_m": 0.7}, "rvo_radius_m")).is_equal(0.7)


func test_base_gait_follows_speed_velocity_and_stop() -> void:
	var reg := _reg({})
	var out := MI.make()
	MR.evaluate_into(out, {"speed": 0.0}, {"archetype": "guard"}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Life_Guard_Attention")
	MR.evaluate_into(out, {"velocity": Vector3(0, 0, 1.4)}, {"archetype": "guard"}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Walk")
	MR.evaluate_into(out, {}, {"archetype": "villager"}, MR.TIER_NEAR, reg)
	assert_str(out["gait_clip"]).is_equal("Idle")


# --- arbitration truth table ----------------------------------------------------------------------------------------------

func test_priority_wins_within_a_channel_and_ties_go_to_the_earlier_row() -> void:
	var reg := _reg({
		"LA": _row(["LOCO"], 2), "LB": _row(["LOCO"], 3), "LC": _row(["LOCO"], 3),
		"HA": _row(["HEAD"], 1), "HB": _row(["HEAD"], 4),
		"UA": _row(["UPPER"], 2), "UB": _row(["UPPER"], 1)})
	var out := _eval(reg, {
		"LA": {"steer_x": 1.0}, "LB": {"steer_x": 2.0}, "LC": {"steer_x": 3.0},
		"HA": {"look_prio": 1, "look_x": 1.0}, "HB": {"look_prio": 4, "look_x": 2.0},
		"UA": {"upper_clip": "ua"}, "UB": {"upper_clip": "ub"}})
	assert_float(out["steer_x"]).is_equal(2.0)
	assert_str(out["loco_rule"]).is_equal("LB")
	assert_float(out["look_x"]).is_equal(2.0)
	assert_str(out["head_rule"]).is_equal("HB")
	assert_str(out["upper_clip"]).is_equal("ua")
	assert_str(out["upper_rule"]).is_equal("UA")
	assert_str(out["body_rule"]).is_equal("")


func test_channels_are_independent_when_no_body_rule_fires() -> void:
	var reg := _reg({"L": _row(["LOCO"], 1), "U": _row(["UPPER"], 1), "H": _row(["HEAD"], 1)})
	var out := _eval(reg, {"L": {"gait_clip": "Life_Walk_Happy"}, "U": {"upper_clip": "Life_Carry_Sack_Upper"}, "H": {"look_prio": 3, "look_z": 5.0}})
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Happy")
	assert_str(out["upper_clip"]).is_equal("Life_Carry_Sack_Upper")
	assert_int(out["look_prio"]).is_equal(3)


func test_body_winner_suppresses_loco_and_upper_but_not_head() -> void:
	var reg := _reg({"B": _row(["BODY"], 1), "L": _row(["LOCO"], 8), "U": _row(["UPPER"], 8), "H": _row(["HEAD"], 1)})
	var out := _eval(reg, {
		"B": {"reaction": 13, "oneshot_clip": "Kneel", "b_stop": true},
		"L": {"steer_x": 1.0, "gait_clip": "Life_Walk_Happy", "lean": 0.05},
		"U": {"upper_clip": "Talk", "ik": [{"limb": "hand_r"}]},
		"H": {"look_prio": 2}})
	assert_int(out["reaction"]).is_equal(13)
	assert_str(out["oneshot_clip"]).is_equal("Kneel")
	assert_int(out["oneshot_channel"]).is_equal(BODY)
	assert_str(out["body_rule"]).is_equal("B")
	assert_str(out["loco_rule"]).is_equal("")
	assert_str(out["upper_rule"]).is_equal("")
	assert_float(out["steer_x"]).is_equal(0.0)
	assert_float(out["lean"]).is_equal(0.0)
	assert_str(out["upper_clip"]).is_equal("")
	assert_array(out["ik"]).is_empty()
	assert_bool(out["stop"]).is_true()
	assert_str(out["gait_clip"]).is_equal("Idle")
	assert_int(out["look_prio"]).is_equal(2)


func test_body_priority_does_not_matter_for_suppression() -> void:
	# a BODY rule at priority 1 still beats LOCO/UPPER rules at priority 8: precedence is by channel first
	var reg := _reg({"B": _row(["BODY"], 1), "L": _row(["LOCO"], 8)})
	var out := _eval(reg, {"B": {"reaction": 3}, "L": {"steer_x": 4.0}})
	assert_float(out["steer_x"]).is_equal(0.0)
	assert_int(out["reaction"]).is_equal(3)


func test_body_row_can_narrow_what_it_suppresses() -> void:
	var reg := _reg({"B": _row(["BODY"], 5, 0.0, "NEAR", {"suppresses": ["UPPER"]}), "L": _row(["LOCO"], 1), "U": _row(["UPPER"], 1)})
	var out := _eval(reg, {"B": {"reaction": 14}, "L": {"steer_x": 1.0}, "U": {"upper_clip": "x"}})
	assert_float(out["steer_x"]).is_equal(1.0)
	assert_str(out["upper_clip"]).is_equal("")


func test_body_steer_replaces_the_loco_steer() -> void:
	var reg := _reg({"B": _row(["BODY"], 7), "L": _row(["LOCO"], 3)})
	var out := _eval(reg, {"B": {"reaction": 11, "b_steer_x": 0.0, "b_steer_z": -1.0, "b_speed_mul": 1.6}, "L": {"steer_x": 1.0}})
	assert_float(out["speed_mul"]).is_equal(1.6)
	assert_float(out["steer_z"]).is_equal(-1.0)
	assert_float(out["steer_x"]).is_equal(0.0)


func test_oneshot_channel_body_beats_upper() -> void:
	var reg := _reg({"B": _row(["BODY"], 1), "U": _row(["UPPER"], 1)})
	var out := _eval(reg, {"U": {"u_oneshot": "Flinch"}})
	assert_str(out["oneshot_clip"]).is_equal("Flinch")
	assert_int(out["oneshot_channel"]).is_equal(UPPER)
	out = _eval(reg, {"B": {"oneshot_clip": "Faint"}, "U": {"u_oneshot": "Flinch"}})
	assert_str(out["oneshot_clip"]).is_equal("Faint")
	assert_int(out["oneshot_channel"]).is_equal(BODY)


func test_multi_channel_rule_arbitrates_in_each_channel() -> void:
	var reg := _reg({"M": _row(["LOCO", "UPPER"], 2), "L": _row(["LOCO"], 3)})
	var out := _eval(reg, {"M": {"steer_x": 1.0, "upper_clip": "Shoulder"}, "L": {"steer_x": 5.0}})
	assert_str(out["loco_rule"]).is_equal("L")
	assert_str(out["upper_rule"]).is_equal("M")
	assert_str(out["upper_clip"]).is_equal("Shoulder")
	assert_float(out["steer_x"]).is_equal(5.0)


func test_disabled_stub_and_channelless_rows_never_run() -> void:
	var reg := _reg({"X": _row(["LOCO"], 5, 0.0, "NEAR", {"enabled": false}), "Y": _row(["LOCO"], 5, 0.0, "NEAR", {"stub": true}), "Z": _row([], 5)})
	assert_int(reg.count).is_equal(0)
	var ctx := {"fire": {"X": {"steer_x": 1.0}, "Y": {"steer_x": 1.0}, "Z": {"steer_x": 1.0}}}
	var out := MI.make()
	MR.evaluate_into(out, ctx, {}, MR.TIER_NEAR, reg)
	assert_int(int(ctx.get("calls", 0))).is_equal(0)
	assert_bool(MI.is_noop(out)).is_true()


func test_intent_refills_in_place_without_residue() -> void:
	var reg := _reg({"U": _row(["UPPER"], 1), "H": _row(["HEAD"], 1)})
	var out := MI.make()
	var ctx := {"fire": {"U": {"upper_clip": "a", "ik": [{"limb": "hand_l", "target": "x", "weight": 1.0}]}, "H": {"look_prio": 2, "look_x": 3.0}}}
	MR.evaluate_into(out, ctx, {}, MR.TIER_NEAR, reg)
	assert_int((out["ik"] as Array).size()).is_equal(1)
	assert_int(out["look_prio"]).is_equal(2)
	MR.evaluate_into(out, {"fire": {}}, {}, MR.TIER_NEAR, reg)
	assert_bool(MI.is_noop(out)).is_true()
	assert_float(out["look_x"]).is_equal(0.0)
	# the rule's own ik constant is never cleared
	assert_int((ctx["fire"]["U"]["ik"] as Array).size()).is_equal(1)


func test_evaluate_is_deterministic() -> void:
	var reg := _reg({"L": _row(["LOCO"], 2), "H": _row(["HEAD"], 2)})
	var fire := {"L": {"steer_z": 0.5, "lean": 0.02}, "H": {"look_prio": 3}}
	assert_dict(_eval(reg, fire)).is_equal(_eval(reg, fire))


# --- hysteresis (min_hold_s) -----------------------------------------------------------------------------------------------

func _hold_reg() -> MotionRules.Registry:
	# B is registered before A: on a plain tie B wins, so only the hold lets A keep the channel
	return _reg({"B": _row(["LOCO"], 2), "A": _row(["LOCO"], 2, 1.0), "C": _row(["LOCO"], 5), "D": _row(["LOCO"], 1)})


func _at(reg: MotionRules.Registry, st: Dictionary, t: float, fire: Dictionary, tier := MR.TIER_NEAR) -> Dictionary:
	return _eval(reg, fire, tier, {"now": t, "motion_state": st})


func test_hold_keeps_the_incumbent_against_an_equal_priority_challenger() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	assert_str(_at(reg, st, 0.0, {"A": {"steer_x": 1.0}})["loco_rule"]).is_equal("A")
	var out := _at(reg, st, 0.5, {"A": {"steer_x": 1.0}, "B": {"steer_x": 2.0}})
	assert_str(out["loco_rule"]).is_equal("A")
	assert_float(out["steer_x"]).is_equal(1.0)
	# A's own trigger gone: the latch still beats the equal priority B
	out = _at(reg, st, 0.7, {"B": {"steer_x": 2.0}})
	assert_str(out["loco_rule"]).is_equal("A")
	assert_float(out["steer_x"]).is_equal(1.0)


func test_hold_keeps_the_incumbent_when_a_lower_priority_rule_is_the_only_other_firer() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"A": {"steer_x": 1.0}})
	var out := _at(reg, st, 0.4, {"A": {"steer_x": 1.0}, "D": {"steer_x": 9.0}})
	assert_str(out["loco_rule"]).is_equal("A")


func test_higher_priority_preempts_inside_the_hold() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"A": {"steer_x": 1.0}})
	var out := _at(reg, st, 0.3, {"A": {"steer_x": 1.0}, "C": {"steer_x": 7.0}})
	assert_str(out["loco_rule"]).is_equal("C")
	assert_float(out["steer_x"]).is_equal(7.0)


func test_challenger_wins_after_the_hold_expires() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"A": {"steer_x": 1.0}})
	assert_str(_at(reg, st, 0.99, {"A": {"steer_x": 1.0}, "B": {"steer_x": 2.0}})["loco_rule"]).is_equal("A")
	# once the hold has run out the challenger takes over
	assert_str(_at(reg, st, 1.01, {"B": {"steer_x": 2.0}})["loco_rule"]).is_equal("B")


func test_latch_keeps_the_last_output_when_the_trigger_vanishes_inside_the_hold() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"A": {"steer_x": 1.5, "gait_clip": "Life_Walk_Happy"}})
	var out := _at(reg, st, 0.6, {})
	assert_float(out["steer_x"]).is_equal(1.5)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Happy")
	assert_str(out["loco_rule"]).is_equal("A")
	out = _at(reg, st, 1.2, {})
	assert_float(out["steer_x"]).is_equal(0.0)
	assert_str(out["loco_rule"]).is_equal("")


func test_latch_yields_to_a_lower_priority_firer_only_after_the_hold() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"A": {"steer_x": 1.5}})
	var out := _at(reg, st, 0.5, {"D": {"steer_x": 0.2}})
	assert_float(out["steer_x"]).is_equal(1.5)
	out = _at(reg, st, 1.5, {"D": {"steer_x": 0.2}})
	assert_float(out["steer_x"]).is_equal(0.2)


func test_without_a_state_there_is_no_hysteresis() -> void:
	var reg := _hold_reg()
	assert_str(_eval(reg, {"A": {"steer_x": 1.0}}, MR.TIER_NEAR, {"now": 0.0})["loco_rule"]).is_equal("A")
	assert_str(_eval(reg, {"B": {"steer_x": 2.0}}, MR.TIER_NEAR, {"now": 0.1})["loco_rule"]).is_equal("B")


func test_zero_hold_rules_never_latch() -> void:
	var reg := _hold_reg()
	var st := MR.new_state()
	_at(reg, st, 0.0, {"B": {"steer_x": 2.0}})
	assert_float(_at(reg, st, 0.1, {})["steer_x"]).is_equal(0.0)


func test_hold_is_per_body_state_and_per_channel() -> void:
	var reg := _reg({"LA": _row(["LOCO"], 2, 1.0), "LB": _row(["LOCO"], 2), "HA": _row(["HEAD"], 1, 1.0), "HB": _row(["HEAD"], 1)})
	var s1 := MR.new_state()
	var s2 := MR.new_state()
	_at(reg, s1, 0.0, {"LA": {"steer_x": 1.0}, "HA": {"look_prio": 1, "look_x": 1.0}})
	var o1 := _at(reg, s1, 0.5, {"LB": {"steer_x": 2.0}, "HB": {"look_prio": 1, "look_x": 2.0}})
	var o2 := _at(reg, s2, 0.5, {"LB": {"steer_x": 2.0}, "HB": {"look_prio": 1, "look_x": 2.0}})
	assert_float(o1["steer_x"]).is_equal(1.0)
	assert_float(o1["look_x"]).is_equal(1.0)
	assert_float(o2["steer_x"]).is_equal(2.0)
	assert_float(o2["look_x"]).is_equal(2.0)


func test_hold_is_dropped_when_the_incumbent_cannot_run_at_the_new_tier() -> void:
	var reg := _reg({"N": _row(["UPPER"], 3, 5.0, "NEAR"), "M": _row(["UPPER"], 1, 0.0, "MID")})
	var st := MR.new_state()
	_at(reg, st, 0.0, {"N": {"upper_clip": "near_only"}, "M": {"upper_clip": "mid_ok"}}, MR.TIER_NEAR)
	var out := _at(reg, st, 1.0, {"M": {"upper_clip": "mid_ok"}}, MR.TIER_MID)
	assert_str(out["upper_clip"]).is_equal("mid_ok")


# --- tier degrade ----------------------------------------------------------------------------------------------------------

func _full_reg() -> MotionRules.Registry:
	return _reg({
		"N_look": _row(["HEAD"], 2, 0.0, "NEAR"), "N_ik": _row(["UPPER"], 2, 0.0, "NEAR"),
		"M_upper": _row(["UPPER"], 1, 0.0, "MID"), "M_loco": _row(["LOCO"], 2, 0.0, "MID"),
		"F_steer": _row(["LOCO"], 1, 0.0, "FAR"), "M_body": _row(["BODY"], 1, 0.0, "MID")})


func _all_fire() -> Dictionary:
	return {
		"N_look": {"look_prio": 3, "look_x": 1.0},
		"N_ik": {"ik": [{"limb": "hand_r", "target": "crank", "weight": 1.0}], "upper_clip": "Craft"},
		"M_upper": {"upper_clip": "Talk"},
		"M_loco": {"steer_x": 0.5, "speed_mul": 0.4, "gait_clip": "Life_Walk_Drunk", "lean": 0.04},
		"F_steer": {"steer_z": 1.0},
		"M_body": {"oneshot_clip": "Hit", "reaction": 6, "b_speed_mul": 1.0}}


func test_near_keeps_everything() -> void:
	var out := _eval(_full_reg(), _all_fire(), MR.TIER_NEAR, {"speed": 1.0})
	assert_int(out["look_prio"]).is_equal(3)
	assert_float(out["look_limit"]).is_equal(70.0)
	assert_int((out["ik"] as Array).size()).is_equal(0) # BODY winner suppressed UPPER (and its IK)


func test_near_keeps_look_ik_upper_lean_and_gait_without_a_body_rule() -> void:
	var fire := _all_fire()
	fire.erase("M_body")
	var out := _eval(_full_reg(), fire, MR.TIER_NEAR, {"speed": 1.0})
	assert_int(out["look_prio"]).is_equal(3)
	assert_int((out["ik"] as Array).size()).is_equal(1)
	assert_str(out["upper_clip"]).is_equal("Craft")
	assert_float(out["lean"]).is_equal(0.04)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Drunk")


func test_mid_drops_look_and_ik_but_keeps_the_rest() -> void:
	var fire := _all_fire()
	fire.erase("M_body")
	var reg := _full_reg()
	var ctx_calls := {"fire": fire, "speed": 1.0}
	var out := MI.make()
	MR.evaluate_into(out, ctx_calls, {"archetype": "villager"}, MR.TIER_MID, reg)
	assert_int(out["look_prio"]).is_equal(0)
	assert_float(out["look_limit"]).is_equal(0.0)
	assert_array(out["ik"]).is_empty()
	assert_str(out["upper_clip"]).is_equal("Talk") # the NEAR-only rule was not even called
	assert_float(out["lean"]).is_equal(0.04)
	assert_float(out["steer_x"]).is_equal(0.5)
	assert_str(out["gait_clip"]).is_equal("Life_Walk_Drunk")
	assert_int(int(ctx_calls["calls"])).is_equal(4) # M_upper, M_loco, F_steer, M_body; N_look and N_ik skipped


func test_mid_keeps_body_oneshot_and_reaction() -> void:
	var out := _eval(_full_reg(), _all_fire(), MR.TIER_MID)
	assert_str(out["oneshot_clip"]).is_equal("Hit")
	assert_int(out["reaction"]).is_equal(6)


func test_far_keeps_steer_and_the_base_clip_only() -> void:
	var fire := _all_fire()
	var out := _eval(_full_reg(), fire, MR.TIER_FAR, {"speed": 1.0})
	assert_str(out["oneshot_clip"]).is_equal("")
	assert_int(out["oneshot_channel"]).is_equal(-1)
	assert_int(out["reaction"]).is_equal(0)
	assert_str(out["upper_clip"]).is_equal("")
	assert_float(out["lean"]).is_equal(0.0)
	assert_int(out["look_prio"]).is_equal(0)
	assert_array(out["ik"]).is_empty()
	fire.erase("M_body")
	out = _eval(_full_reg(), fire, MR.TIER_FAR, {"speed": 1.0})
	# only FAR-tier rules run at FAR: F_steer fires, the MID-tier M_loco (and its steer, gait and lean) is never called
	assert_float(out["steer_z"]).is_equal(1.0)
	assert_float(out["steer_x"]).is_equal(0.0)
	assert_float(out["speed_mul"]).is_equal(1.0)


func test_far_resolves_a_clip_without_vat_to_walk_or_idle() -> void:
	var reg := _reg({"L": _row(["LOCO"], 1, 0.0, "FAR")})
	# not baked: Life_Walk_Drunk -> Walk, Life_Rest_Nap -> Idle
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Walk_Drunk"}}, MR.TIER_FAR)["gait_clip"]).is_equal("Walk")
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Rest_Nap"}}, MR.TIER_FAR)["gait_clip"]).is_equal("Idle")
	# baked in the villager (adult) set: kept
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Walk_Happy"}}, MR.TIER_FAR)["gait_clip"]).is_equal("Life_Walk_Happy")
	assert_str(_eval(reg, {"L": {"gait_clip": "Walk+Life_Carry_Sack_Upper"}}, MR.TIER_FAR)["gait_clip"]).is_equal("Walk+Life_Carry_Sack_Upper")
	# the child set has no Life_Walk_Happy
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Walk_Happy"}}, MR.TIER_FAR, {}, {"archetype": "child"})["gait_clip"]).is_equal("Walk")
	# the guard set has the patrol walk
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Guard_Patrol_Walk"}}, MR.TIER_FAR, {}, {"archetype": "guard"})["gait_clip"]).is_equal("Life_Guard_Patrol_Walk")
	# NEAR leaves an unbaked clip alone
	assert_str(_eval(reg, {"L": {"gait_clip": "Life_Walk_Drunk"}}, MR.TIER_NEAR)["gait_clip"]).is_equal("Life_Walk_Drunk")


func test_far_base_clips_of_every_archetype_are_baked() -> void:
	var reg := _reg({})
	for n: String in ARCHETYPES:
		for speed in [0.0, 1.3]:
			var out := MI.make()
			MR.evaluate_into(out, {"speed": speed}, {"archetype": n}, MR.TIER_FAR, reg)
			var set_name: String = _real["archetypes"][n]["vat_set"]
			assert_bool(MR.vat_has(set_name, out["gait_clip"])).override_failure_message("%s speed %s clip %s" % [n, speed, out["gait_clip"]]).is_true()
			assert_str(out["gait_clip"]).is_not_empty()


func test_out_tier_returns_nothing() -> void:
	var out := _eval(_full_reg(), _all_fire(), MR.TIER_OUT)
	assert_bool(MI.is_noop(out)).is_true()
	assert_str(out["gait_clip"]).is_equal("")
	assert_int(out["tier"]).is_equal(MR.TIER_OUT)


# --- cost ------------------------------------------------------------------------------------------------------------------

func _cost_contexts(n: int) -> Array:
	var list: Array = []
	for i in n:
		var fire := {}
		if i % 2 == 0:
			fire["N_look"] = {"look_prio": 1 + i % 5, "look_x": float(i)}
		if i % 3 == 0:
			fire["M_loco"] = {"steer_x": 0.1 * i, "gait_clip": "Life_Walk_Happy"}
		if i % 4 == 0:
			fire["M_upper"] = {"upper_clip": "Talk"}
		if i % 5 == 0:
			fire["M_body"] = {"reaction": 6, "oneshot_clip": "Hit"}
		list.append({"fire": fire, "speed": 0.5 + 0.1 * (i % 7), "now": 0.0, "motion_state": MR.new_state()})
	return list


func test_cost_24_contexts_x_1000_evaluations() -> void:
	var reg := _full_reg()
	var ctxs := _cost_contexts(24)
	var personas := []
	for i in 24:
		personas.append({"archetype": ARCHETYPES[i % ARCHETYPES.size()]})
	var intents: Array = []
	for i in 24:
		intents.append(MI.make())
	var report := []
	for tier in [MR.TIER_NEAR, MR.TIER_MID, MR.TIER_FAR]:
		var t0 := Time.get_ticks_usec()
		for rep in 1000:
			for i in 24:
				(ctxs[i] as Dictionary)["now"] = rep * 0.1
				MR.evaluate_into(intents[i], ctxs[i], personas[i], tier, reg)
		var per_eval := float(Time.get_ticks_usec() - t0) / 24000.0
		report.append("%s %.1f us" % [MR.TIER_NAMES[tier], per_eval])
		# Loose limit (CI runners are slow): the design budget is 6 us per body at NEAR (0.15 ms / 24) and 20 us at MID.
		assert_float(per_eval).override_failure_message("tier %d took %.1f us per evaluation" % [tier, per_eval]).is_less(250.0)
	print("MotionRules cost (6 test rules, 24 contexts x 1000, hysteresis on): ", ", ".join(report))
	# the default registry (all rules still stubs) is free
	var t1 := Time.get_ticks_usec()
	for rep in 1000:
		for i in 24:
			MR.evaluate_into(intents[i], ctxs[i], personas[i], MR.TIER_NEAR)
	var stub_per_eval := float(Time.get_ticks_usec() - t1) / 24000.0
	print("MotionRules cost (default registry, all stubs): %.1f us per evaluation" % stub_per_eval)
	assert_float(stub_per_eval).is_less(250.0)


func test_evaluate_matches_evaluate_into() -> void:
	var a := MR.evaluate({"speed": 1.0}, {"archetype": "noble"}, MR.TIER_MID)
	var b := MI.make()
	MR.evaluate_into(b, {"speed": 1.0}, {"archetype": "noble"}, MR.TIER_MID)
	assert_dict(a).is_equal(b)
