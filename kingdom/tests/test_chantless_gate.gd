extends GdUnitTestSuite
## Chantless magic is advanced only: a high magic level, spell-theory mastery, several path milestones and Core
## Formation. Beginners must chant. Enforced in data (data/powers/magic.json chantless_gate), in
## power_paths.can_use (ctx.chantless) and in AbilityRunner, never only in the UI.

const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const NpcCaster := preload("res://scripts/combat/npc_caster.gd")

const MS3 := ["first_circle", "theory_exam", "duel_won"]


func _mage(level := 20, theory := 0.7, milestones: Array = MS3, realm := 4, stage := 1) -> Dictionary:
	var p := PowerTrees.empty_profile()
	p["paths"] = ["magic"]
	p["primary"] = "magic"
	p["levels"] = {"magic": level}
	p["theory"] = {"magic": theory}
	p["milestones"] = {"magic": milestones.duplicate()}
	p["realms"] = {"magic": {"realm": realm, "stage": stage}}
	return p


func _runner(profile: Dictionary) -> Runner:
	var r := Runner.new()
	r.costs_enabled = false
	r.hooks = {"profile": func() -> Dictionary: return profile}
	return r


func test_the_gate_is_data_with_four_conditions() -> void:
	var g := PowerTrees.chantless_gate("magic")
	assert_int(int(g["path_level"])).is_greater_equal(15)
	assert_float(float(g["theory"])).is_greater_equal(0.5)
	assert_int(int(g["milestones"])).is_greater_equal(3)
	assert_int(int(g["realm"])).is_greater_equal(4)             # Core Formation, per PROGRESSION_R1
	assert_array(g["milestone_ids"]).contains(["first_circle", "theory_exam"])
	for other: String in ["bending", "sect", "knight", "beast"]:
		assert_bool(PowerTrees.chantless_gate(other).is_empty()).is_true()      # only magic has a chantless art


func test_an_advanced_caster_passes() -> void:
	var c := PowerTrees.chantless_check(_mage())
	assert_bool(c["ok"]).is_true()
	assert_array(c["reasons"]).is_empty()


func test_each_missing_condition_closes_the_gate_on_its_own() -> void:
	var cases := {
		"level": _mage(19), "theory": _mage(20, 0.69), "milestones": _mage(20, 0.7, ["first_circle", "duel_won"]),
		"realm": _mage(20, 0.7, MS3, 3, 9),
	}
	for k: String in cases:
		var c := PowerTrees.chantless_check(cases[k])
		assert_bool(c["ok"]).override_failure_message("passed without " + k).is_false()
		assert_int((c["reasons"] as Array).size()).is_equal(1)
	# Milestones that are not on the path list do not count.
	assert_bool(PowerTrees.chantless_check(_mage(20, 0.7, ["a", "b", "c"]))["ok"]).is_false()
	# A beginner fails on all four and is told why.
	var b := PowerTrees.chantless_check(_mage(1, 0.0, [], 1, 1))
	assert_int((b["reasons"] as Array).size()).is_equal(4)
	var text := " ".join(PackedStringArray(b["reasons"]))
	assert_str(text).contains("Magic level")
	assert_str(text).contains("Spell-theory")
	assert_str(text).contains("milestones")
	assert_str(text).contains("Mana Core")           # realm 4 on the magic ladder (Core Formation)
	# Not on the path at all.
	assert_bool(PowerTrees.chantless_check(PowerTrees.empty_profile())["ok"]).is_false()


func test_chantless_is_out_of_reach_in_region_one() -> void:
	# Region 1 caps cultivation at realm 3 and the gate needs realm 4: nobody casts chantless before Region 2.
	assert_int(int(PowerTrees.chantless_gate("magic")["realm"])).is_greater(int(PowerTrees.region_cap()["realm"]))
	assert_bool(PowerTrees.chantless_check(_mage(30, 1.0, MS3, 3, 9))["ok"]).is_false()
	var t := PowerTrees.technique("mg_chantless")
	assert_int(int(t["region"])).is_equal(2)
	assert_str(PowerTrees.state("mg_chantless", _mage(20, 0.7, MS3, 3, 9))["state"]).is_equal("beyond")


func test_beginners_must_chant_every_magic_spell() -> void:
	for t: Dictionary in PowerTrees.techniques_of("magic"):
		var ab := PowerTrees.ability(String(t["id"]))
		if ab["kind"] != "active":
			continue
		assert_str(ab["cast"]["kind"]).override_failure_message(t["id"] + " is not a chant").is_equal("chant")
		assert_str(ab["cast"]["chantless_req"]).is_equal("magic")
		assert_bool((ab["cast"]["seals"] as Array).size() >= 1).is_true()
	# Legacy elemental techniques with seals chant too; sect/shadow seals stay an optional bonus.
	assert_str(AbilityLib.get_def("fire_dawnflame_nova")["cast"]["kind"]).is_equal("chant")
	assert_str(AbilityLib.get_def("lightning_heaven_strike")["cast"]["kind"]).is_equal("chant")
	assert_str(AbilityLib.get_def("qi_explosion")["cast"]["kind"]).is_equal("instant")
	assert_bool(AbilityLib.get_def("qi_explosion")["cast"]["seal_optional"]).is_true()
	assert_str(AbilityLib.get_def("shadow_clone")["cast"]["kind"]).is_equal("instant")
	# No other path chants.
	for path: String in ["bending", "sect", "knight", "beast"]:
		for t: Dictionary in PowerTrees.techniques_of(path):
			assert_str(PowerTrees.ability(String(t["id"]))["cast"]["kind"]).is_equal("instant")


func test_runner_denies_chantless_to_a_beginner() -> void:
	var r := _runner(_mage(3, 0.1, [], 1, 5))
	var res: Dictionary = r.begin("mg_spark", {"chantless": true})
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).contains("Chantless casting is beyond you")
	assert_float(r.cooldown_left("mg_spark")).is_equal(0.0)
	assert_int(r.phase).is_equal(Runner.Phase.IDLE)


func test_runner_makes_a_beginner_chant_when_chantless_is_not_insisted_on() -> void:
	var r := _runner(_mage(3, 0.1, [], 1, 5))
	var res: Dictionary = r.begin("mg_spark", {})
	assert_bool(res["ok"]).is_true()
	assert_str(res["phase"]).is_equal("chant")
	assert_array(res["seals"]).is_equal(["tiger", "rat"])
	assert_int(r.phase).is_equal(Runner.Phase.CHANT)
	r.cancel()
	var fb: Dictionary = r.begin("mg_spark", {"chantless": true, "fallback_chant": true})
	assert_str(fb["phase"]).is_equal("chant")                  # asked for chantless, fell back to the chant


func test_runner_lets_an_advanced_caster_skip_the_chant() -> void:
	var r := _runner(_mage())
	var res: Dictionary = r.begin("mg_spark", {"chantless": true})
	assert_bool(res["ok"]).is_true()
	assert_bool(res.has("phase") and res["phase"] == "chant").is_false()
	assert_int(r.phase).is_equal(Runner.Phase.WINDUP)
	assert_float(res["cooldown"]).is_greater(0.0)


func test_chant_time_shortens_with_level_but_never_below_the_floor() -> void:
	var novice := _runner(_mage(1, 0.0, [], 1, 1)).evaluate("mg_circle_bolt", {})
	var adept := _runner(_mage(12, 0.2, [], 2, 5)).evaluate("mg_circle_bolt", {})
	var master := _runner(_mage(19, 0.5, [], 3, 9)).evaluate("mg_circle_bolt", {})
	assert_bool(float(novice["chant"]["time"]) > float(adept["chant"]["time"])).is_true()
	assert_bool(float(adept["chant"]["time"]) > float(master["chant"]["time"])).is_true()
	var base := float(PowerTrees.ability("mg_circle_bolt")["cast"]["chant_time"])
	assert_float(float(novice["chant"]["time"])).is_equal_approx(base, 0.0001)
	assert_float(PowerTrees.chant_factor("magic", 99)).is_equal_approx(0.35, 0.0001)
	assert_str(PowerTrees.chant_tier("magic", 1)["id"]).is_equal("novice")
	assert_str(PowerTrees.chant_tier("magic", 20)["id"]).is_equal("master")


func test_power_paths_can_use_enforces_the_gate_not_only_the_ui() -> void:
	var pp: RefCounted = Hub.new().mod("power_paths")
	pp.learn("magic", "academy")
	# No chantless request: fine for anybody who knows the path.
	assert_bool(pp.can_use("magic", 4.0, {})["ok"]).is_true()
	var refused: Dictionary = pp.can_use("magic", 4.0, {"chantless": true})
	assert_bool(refused["ok"]).is_false()
	assert_str(refused["reason"]).contains("Chantless casting is beyond you")
	var used: Dictionary = pp.use("magic", 4.0, {"chantless": true})
	assert_bool(used["ok"]).is_false()
	assert_float(pp.resource("magic")["cur"]).is_equal_approx(pp.max_of("magic"), 0.0001)     # nothing was spent
	# Earn the gate through the real module: theory and milestones...
	pp.study_theory("magic", 0.75)
	for m: String in MS3:
		pp.add_milestone("magic", m)
	pp.gain_xp("magic", 5000.0)
	assert_int(pp.level("magic")).is_greater_equal(20)
	# ...but cultivation still must reach Core Formation: with a stub profile at realm 3 it stays shut.
	var shut: Dictionary = pp.can_use("magic", 4.0, {"chantless": true, "profile": pp.profile({"realms": {"magic": {"realm": 3, "stage": 9}}})})
	assert_bool(shut["ok"]).is_false()
	var open: Dictionary = pp.can_use("magic", 4.0, {"chantless": true, "profile": pp.profile({"realms": {"magic": {"realm": 4, "stage": 1}}})})
	assert_bool(open["ok"]).is_true()
	assert_bool(pp.chantless_ready({"profile": pp.profile({"realms": {"magic": {"realm": 4, "stage": 2}}})})["ok"]).is_true()
	# The gate is for the magic path only.
	var k: RefCounted = Hub.new().mod("power_paths")
	k.learn("knight", "academy")
	assert_bool(k.can_use("knight", 4.0, {"chantless": true})["ok"]).is_true()


func test_a_second_path_mage_does_not_qualify_by_borrowing_the_first() -> void:
	var p := _mage(8, 0.1, [], 2, 3)
	p["paths"] = ["sect", "magic"]
	p["primary"] = "sect"
	p["levels"] = {"sect": 25, "magic": 8}
	p["realms"] = {"sect": {"realm": 5, "stage": 1}, "magic": {"realm": 2, "stage": 3}}
	assert_bool(PowerTrees.chantless_check(p)["ok"]).is_false()
	p["levels"]["sect"] = 99
	assert_bool(PowerTrees.chantless_check(p)["ok"]).is_false()


func test_npc_casters_follow_the_same_gate() -> void:
	assert_bool(NpcCaster.make("bandit_mage", 1).chantless).is_false()
	assert_bool(NpcCaster.make("veteran_mage", 1).chantless).is_true()
	var m: RefCounted = NpcCaster.make("bandit_mage", 1)
	var r: Dictionary = m.cast("mg_spark", null)
	assert_str(r["phase"]).is_equal("chant")                    # the bandit mage must chant
	var v: RefCounted = NpcCaster.make("veteran_mage", 1)
	var rv: Dictionary = v.cast("mg_spark", null)
	assert_bool(rv.has("phase")).is_false()                     # the veteran does not
	assert_int(v.runner.phase).is_equal(Runner.Phase.WINDUP)
