extends GdUnitTestSuite
## AbilityDef / EffectSet / AbilityRunner (scripts/abilities): the one lifecycle shared by the player's technique
## caster and NPC casters. Parity with the legacy skills.gd numbers, lifecycle order, pay-on-release, cooldown,
## lockout, interrupt/refund, effect families and stacking rules, burn parity with the old caster's _burns.

const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const Skills := preload("res://scripts/sim/skills.gd")


func _skills() -> Skills:
	return Skills.new()


func _def(id: String, extra := {}) -> Dictionary:
	var row := {"id": id, "name": id, "path": "sect", "cost_dummy": 0, "cooldown": 4.0, "windup": 0.5, "damage": 20,
		"costs": {"qi": 10}, "targeting": {"kind": "melee", "range": 3.0}}
	row.merge(extra, true)
	return AbilityDef.normalise(row)


func _runner(defs: Array, pools := {"qi": 100.0}) -> Dictionary:
	var by_id := {}
	for d: Dictionary in defs:
		by_id[d["id"]] = d
	var log := {"paid": [], "executed": [], "refunded": [], "pools": pools.duplicate()}
	var r := Runner.new()
	r.hooks = {
		"lookup": func(id: String) -> Dictionary: return by_id.get(id, {}),
		"pools": func() -> Dictionary: return log["pools"],
		"pay": func(res: String, amt: float) -> void:
			log["paid"].append([res, amt])
			log["pools"][res] = float(log["pools"].get(res, 0.0)) - amt,
		"refund": func(res: String, amt: float) -> void: log["refunded"].append([res, amt]),
		"execute": func(_d: Dictionary, cast: Dictionary) -> void: log["executed"].append(cast),
	}
	return {"runner": r, "log": log}


# --- AbilityDef: legacy port ------------------------------------------------------

func test_every_legacy_technique_converts_and_validates() -> void:
	var s := _skills()
	assert_array(AbilityLib.validate_all()).is_empty()
	var n := 0
	for id: String in s.techniques:
		var t: Dictionary = s.techniques[id]
		var ab := AbilityDef.from_technique(t)
		n += 1
		assert_str(ab["id"]).is_equal(id)
		# The flat dictionary the caster executes is the original, untouched.
		assert_dict(AbilityDef.flat(ab)).is_equal(t)
		if t["kind"] != "active":
			continue
		var pc := AbilityDef.primary_cost(ab)
		assert_str(pc["resource"]).is_equal(t["resource"])
		assert_float(pc["amount"]).is_equal_approx(float(t["cost"]), 0.0001)
		assert_float(ab["windup"]).is_equal_approx(float(t["hit_time"]), 0.0001)
		assert_str(ab["targeting"]["kind"]).is_equal(t["shape"])
	assert_int(n).is_greater(50)


func test_runner_default_numbers_match_skills_at_rank_one() -> void:
	var s := _skills()
	var r := Runner.new()
	for id: String in s.techniques:
		var t: Dictionary = s.techniques[id]
		if t["kind"] != "active":
			continue
		s.ranks[id] = 1
		var ev: Dictionary = r.evaluate(id)
		assert_bool(ev["ok"]).is_true()
		var nums: Dictionary = ev["numbers"]
		assert_float(float(nums["costs"][t["resource"]])).is_equal_approx(s.cost_of(id), 0.0001)
		assert_float(float(nums["cooldown"])).is_equal_approx(s.cooldown_of(id), 0.0001)
		assert_int(int(nums["damage"])).is_equal(s.damage_of(id))


func test_legacy_effects_become_effect_rows() -> void:
	var fb := AbilityLib.get_def("fire_ember_orb")
	var burn: Dictionary = fb["effects"][0]
	assert_str(burn["type"]).is_equal("dot")
	assert_str(burn["family"]).is_equal("burn")
	assert_str(burn["rule"]).is_equal("stack")
	assert_float(burn["duration"]).is_equal_approx(3.0, 0.0001)
	var ws := AbilityLib.get_def("command_war_cry")
	var types: Array = []
	for e: Dictionary in ws["effects"]:
		types.append(e["type"])
	assert_array(types).is_equal(["slow", "fear"])           # same order the old _hit used
	var stone := AbilityLib.get_def("earth_stone_skin")
	assert_str(stone["effects"][0]["family"]).is_equal("buff:earth_stone_skin")


func test_validate_catches_bad_rows() -> void:
	var bad := _def("bad", {"cast": {"kind": "chant"}, "costs": {"gold": 5}, "cooldown": 0.2, "windup": 0.5,
		"effects": [{"type": "dot", "rule": "forever"}, {"type": "explode"}]})
	var errs := AbilityDef.validate(bad)
	var joined := " ".join(PackedStringArray(errs))
	assert_str(joined).contains("chant without seals")
	assert_str(joined).contains("unknown resource gold")
	assert_str(joined).contains("cooldown is shorter")
	assert_str(joined).contains("unknown stacking rule")
	assert_str(joined).contains("unknown effect type")


# --- lifecycle ---------------------------------------------------------------------

func test_instant_ability_pays_cools_down_and_executes_after_windup() -> void:
	var h := _runner([_def("palm")])
	var r: Runner = h["runner"]
	var log: Dictionary = h["log"]
	var res: Dictionary = r.begin("palm", {"target": "dummy"})
	assert_bool(res["ok"]).is_true()
	assert_array(log["paid"]).is_equal([["qi", 10.0]])          # paid at commit
	assert_float(r.cooldown_left("palm")).is_equal_approx(4.0, 0.0001)
	assert_int(res["damage"]).is_equal(20)
	assert_int(r.phase).is_equal(Runner.Phase.WINDUP)
	assert_array(log["executed"]).is_empty()
	r.update(0.3)
	assert_array(log["executed"]).is_empty()
	r.update(0.25)
	assert_int((log["executed"] as Array).size()).is_equal(1)
	assert_str(log["executed"][0]["target"]).is_equal("dummy")
	assert_int(r.phase).is_equal(Runner.Phase.IDLE)


func test_rejections_have_the_legacy_reasons() -> void:
	var h := _runner([_def("palm"), _def("passive_x", {"kind": "passive"})], {"qi": 5.0})
	var r: Runner = h["runner"]
	assert_str(r.begin("nothing")["reason"]).is_equal("Unknown ability.")
	assert_str(r.begin("palm")["reason"]).is_equal("Not enough qi.")
	h["log"]["pools"]["qi"] = 100.0
	assert_str(r.begin("passive_x")["reason"]).is_equal("Passive.")
	assert_bool(r.begin("palm")["ok"]).is_true()
	r.update(1.0)
	assert_str(r.begin("palm")["reason"]).is_equal("3.0s")
	r.hooks["known"] = func(_id: String) -> bool: return false
	r.update(5.0)
	assert_str(r.begin("palm")["reason"]).is_equal("Not learned.")
	r.hooks.erase("known")
	r.hooks["blocked"] = func() -> String: return "Swimming."
	assert_str(r.begin("palm")["reason"]).is_equal("Swimming.")


func test_global_lockout_blocks_a_second_cast_for_a_moment() -> void:
	var h := _runner([_def("a"), _def("b")])
	var r: Runner = h["runner"]
	r.overlap_windups = true
	assert_bool(r.begin("a")["ok"]).is_true()
	assert_str(r.begin("b")["reason"]).is_equal("Busy.")
	r.update(Runner.CAST_LOCK + 0.01)
	assert_bool(r.begin("b")["ok"]).is_true()      # windups may overlap for the player
	var n := _runner([_def("a"), _def("b")])
	var npc: Runner = n["runner"]
	assert_bool(npc.begin("a")["ok"]).is_true()
	npc.update(Runner.CAST_LOCK + 0.01)
	assert_str(npc.begin("b")["reason"]).is_equal("Busy.")   # NPCs do one thing at a time


func test_costs_off_means_cooldown_only() -> void:
	var h := _runner([_def("palm")], {})
	var r: Runner = h["runner"]
	r.costs_enabled = false
	assert_bool(r.begin("palm")["ok"]).is_true()
	assert_array(h["log"]["paid"]).is_empty()
	assert_float(r.cooldown_left("palm")).is_greater(0.0)


func test_chant_pays_on_release_not_while_chanting() -> void:
	var chant := _def("bolt", {"path": "magic", "costs": {"magicules": 6}, "cast": {"kind": "chant", "seals": ["tiger", "rat"], "chant_time": 1.0}})
	var h := _runner([chant], {"magicules": 50.0})
	var r: Runner = h["runner"]
	var res: Dictionary = r.begin("bolt", {})
	assert_str(res["phase"]).is_equal("chant")
	assert_array(res["seals"]).is_equal(["tiger", "rat"])
	assert_array(h["log"]["paid"]).is_empty()
	assert_float(r.cooldown_left("bolt")).is_equal(0.0)
	r.update(5.0)                                   # a player chant waits for the seal pad: it never times itself
	assert_int(r.phase).is_equal(Runner.Phase.CHANT)
	var done: Dictionary = r.chant_complete(true, true)
	assert_bool(done["ok"]).is_true()
	assert_array(h["log"]["paid"]).is_equal([["magicules", 6.0]])
	assert_int(done["damage"]).is_equal(int(round(20 * 1.15)))   # seal pad bonus, exactly the legacy +15 percent


func test_broken_chant_fizzles_with_a_short_cooldown_and_costs_nothing() -> void:
	var chant := _def("bolt", {"path": "magic", "costs": {"magicules": 6}, "cast": {"kind": "chant", "seals": ["tiger"], "chant_time": 1.0}})
	var h := _runner([chant], {"magicules": 50.0})
	var r: Runner = h["runner"]
	r.begin("bolt", {})
	var res: Dictionary = r.chant_complete(false)
	assert_str(res["reason"]).is_equal("fizzle")
	assert_array(h["log"]["paid"]).is_empty()
	assert_float(r.cooldown_left("bolt")).is_equal_approx(Runner.FIZZLE_COOLDOWN, 0.0001)
	assert_int(r.phase).is_equal(Runner.Phase.IDLE)


func test_auto_chant_times_itself_for_npcs() -> void:
	var chant := _def("bolt", {"path": "magic", "costs": {}, "cast": {"kind": "chant", "seals": ["tiger"], "chant_time": 1.0}})
	var h := _runner([chant], {})
	var r: Runner = h["runner"]
	r.costs_enabled = false
	r.begin("bolt", {"auto_chant": true})
	r.update(0.9)
	assert_int(r.phase).is_equal(Runner.Phase.CHANT)
	r.update(0.2)
	assert_int(r.phase).is_equal(Runner.Phase.WINDUP)          # chant over, committed, windup running
	r.update(0.6)
	assert_int((h["log"]["executed"] as Array).size()).is_equal(1)


func test_interrupt_chant_fizzles_interrupt_windup_refunds_half() -> void:
	var chant := _def("bolt", {"path": "magic", "costs": {"magicules": 6}, "cast": {"kind": "chant", "seals": ["tiger"], "chant_time": 1.0}})
	var h := _runner([chant, _def("palm")], {"magicules": 50.0, "qi": 50.0})
	var r: Runner = h["runner"]
	r.begin("bolt", {})
	assert_bool(r.interrupt("hit")).is_true()
	assert_float(r.cooldown_left("bolt")).is_equal_approx(Runner.FIZZLE_COOLDOWN, 0.0001)
	r.update(1.0)
	r.begin("palm", {})
	assert_bool(r.interrupt("staggered")).is_true()
	assert_array(h["log"]["refunded"]).is_equal([["qi", 5.0]])
	r.update(2.0)
	assert_array(h["log"]["executed"]).is_empty()               # the dropped windup never resolves
	assert_bool(r.interrupt("nothing to break")).is_false()


func test_recover_phase_and_cancel() -> void:
	var h := _runner([_def("slam", {"recover": 0.4, "windup": 0.2})])
	var r: Runner = h["runner"]
	r.begin("slam")
	r.update(0.25)
	assert_int(r.phase).is_equal(Runner.Phase.RECOVER)
	assert_str(r.begin("slam")["reason"]).is_not_equal("")
	r.update(0.5)
	assert_int(r.phase).is_equal(Runner.Phase.IDLE)
	var chant := _def("bolt", {"path": "magic", "costs": {}, "cast": {"kind": "chant", "seals": ["rat"], "chant_time": 1.0}})
	var h2 := _runner([chant], {})
	var r2: Runner = h2["runner"]
	r2.begin("bolt", {})
	assert_bool(r2.cancel()).is_true()
	assert_float(r2.cooldown_left("bolt")).is_equal(0.0)       # walking away from the seal pad costs nothing


func test_commit_hook_replaces_pay_and_cooldown() -> void:
	var h := _runner([_def("palm")])
	var r: Runner = h["runner"]
	r.hooks["commit"] = func(id: String, _d: Dictionary, sealed: bool, _n: Dictionary, _o: Dictionary) -> Dictionary:
		return {"ok": true, "reason": "", "resource": "qi", "cost": 3.0, "cooldown": 1.0, "damage": 77 if sealed else 55}
	var res: Dictionary = r.begin("palm")
	assert_int(res["damage"]).is_equal(55)
	assert_array(h["log"]["paid"]).is_empty()                   # the hook owns payment
	r.hooks["commit"] = func(_i: String, _d: Dictionary, _s: bool, _n: Dictionary, _o: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "no"}
	r.update(5.0)
	assert_str(r.begin("palm")["reason"]).is_equal("no")


# --- EffectSet ------------------------------------------------------------------------

func test_refresh_rule_keeps_one_entry_and_never_shortens() -> void:
	var es := EffectSet.new()
	assert_str(es.apply({"type": "stun", "duration": 2.0, "rule": "refresh"})["action"]).is_equal("added")
	es.tick(1.5)
	assert_str(es.apply({"type": "stun", "duration": 1.0, "rule": "refresh"})["action"]).is_equal("refreshed")
	assert_int(es.count("stun")).is_equal(1)
	assert_float(float(es.active[0]["left"])).is_equal_approx(1.0, 0.0001)   # 0.5 left vs new 1.0: the longer wins
	es.apply({"type": "stun", "duration": 0.2, "rule": "refresh"})
	assert_float(float(es.active[0]["left"])).is_equal_approx(1.0, 0.0001)


func test_replace_if_stronger_rule() -> void:
	var es := EffectSet.new()
	es.apply({"type": "ward", "magnitude": 30.0, "duration": 10.0, "rule": "replace_if_stronger"})
	assert_str(es.apply({"type": "ward", "magnitude": 20.0, "duration": 10.0, "rule": "replace_if_stronger"})["action"]).is_equal("rejected")
	assert_str(es.apply({"type": "ward", "magnitude": 30.0, "duration": 12.0, "rule": "replace_if_stronger"})["action"]).is_equal("refreshed")
	assert_str(es.apply({"type": "ward", "magnitude": 80.0, "duration": 5.0, "rule": "replace_if_stronger"})["action"]).is_equal("replaced")
	assert_int(es.count("ward")).is_equal(1)
	assert_float(float(es.active[0]["magnitude"])).is_equal(80.0)


func test_stack_rule_caps_and_refreshes_the_oldest() -> void:
	var es := EffectSet.new()
	var row := {"type": "dot", "family": "burn", "magnitude": 3.0, "duration": 3.0, "rule": "stack", "max_stacks": 3}
	for i in 3:
		es.apply(row)
		es.tick(0.1)
	assert_int(es.count("burn")).is_equal(3)
	var r := es.apply(row)
	assert_str(r["action"]).is_equal("refreshed")
	assert_int(es.count("burn")).is_equal(3)               # capped
	es.apply({"type": "dot", "family": "bleed", "magnitude": 2.0, "duration": 3.0, "rule": "stack", "max_stacks": 3})
	assert_int(es.count("bleed")).is_equal(1)              # a different family is independent
	assert_array(es.families()).is_equal(["burn", "bleed"])


func test_burn_matches_the_old_caster_burn_exactly() -> void:
	# Old _update_burns: left and tick run down by delta; at left <= 0 the burn is removed (no last tick),
	# otherwise every BURN_TICK a hit of dps = max(1, round(amount * 0.08)).
	for dur in [2.0, 3.0, 4.0, 5.0]:
		for step in [0.016, 0.02, 0.033]:
			var amount := 22
			var dps := maxi(1, int(round(amount * 0.08)))
			var old_total := 0
			var left: float = dur
			var tick := 0.5
			var t := 0.0
			while left > 0.0 and t < 20.0:
				left -= step
				tick -= step
				t += step
				if left <= 0.0:
					break
				if tick <= 0.0:
					tick = 0.5
					old_total += dps
			var es := EffectSet.new()
			var r := Runner.new()
			var ab := AbilityDef.from_technique({"id": "x", "name": "x", "tree": "fire", "resource": "magicules", "cost": 1.0,
				"effect": {"burn": dur}, "shape": "projectile"})
			r.apply_effects(ab, amount, es, "enemy")
			var new_total := 0
			var steps := int(t / step) + 2
			for i in steps:
				for ev: Dictionary in es.tick(step):
					if ev["kind"] == "dot":
						new_total += int(ev["amount"])
			assert_int(new_total).override_failure_message("dur %s step %s" % [dur, step]).is_equal(old_total)


func test_tick_chunks_large_steps_and_expires() -> void:
	var es := EffectSet.new()
	es.apply({"type": "dot", "family": "poison", "magnitude": 4.0, "duration": 2.0, "rule": "refresh"})
	var events := es.tick(3.0)
	var ticks := 0
	var expired := 0
	for e: Dictionary in events:
		if e["kind"] == "dot":
			ticks += 1
		elif e["kind"] == "expire":
			expired += 1
	assert_int(ticks).is_equal(3)                        # 0.5, 1.0, 1.5 (2.0 expires before ticking)
	assert_int(expired).is_equal(1)
	assert_bool(es.has("poison")).is_false()


func test_ward_and_absorb_counter_damage_before_it_lands() -> void:
	var es := EffectSet.new()
	es.apply({"type": "ward", "family": "ward", "magnitude": 30.0, "duration": 10.0})
	var r := es.mitigate(20.0)
	assert_int(r["amount"]).is_equal(0)
	assert_int(r["absorbed"]).is_equal(20)
	r = es.mitigate(25.0)
	assert_int(r["absorbed"]).is_equal(10)
	assert_int(r["amount"]).is_equal(15)
	assert_bool(es.has("ward")).is_false()               # a spent ward is gone
	es.apply({"type": "buff", "family": "skin", "stats": {"damage_taken": -0.5}, "duration": 5.0})
	assert_int(es.mitigate(40.0)["amount"]).is_equal(20)
	es.apply({"type": "ward", "family": "ember_ward", "magnitude": 99.0, "duration": 5.0, "tags": ["fire"]})
	assert_int(es.mitigate(10.0, "water")["amount"]).is_equal(5)   # an element ward ignores other elements


func test_slow_speed_factor_and_stat_sums() -> void:
	var es := EffectSet.new()
	assert_float(es.speed_factor()).is_equal_approx(1.0, 0.0001)
	es.apply({"type": "slow", "duration": 3.0, "magnitude": 0.4})
	es.apply({"type": "slow", "family": "frost", "duration": 3.0, "magnitude": 0.6})
	assert_float(es.speed_factor()).is_equal_approx(0.4, 0.0001)
	es.apply({"type": "buff", "family": "a", "stats": {"sword_damage": 0.1}, "duration": 5.0})
	es.apply({"type": "buff", "family": "b", "stats": {"sword_damage": 0.2}, "duration": 5.0})
	assert_float(es.stat("sword_damage")).is_equal_approx(0.3, 0.0001)
	assert_bool(es.is_stunned()).is_false()
	es.apply({"type": "stun", "duration": 1.0})
	assert_bool(es.is_stunned()).is_true()


func test_effect_set_serialises_as_json() -> void:
	var es := EffectSet.new()
	es.apply({"type": "dot", "family": "burn", "magnitude": 2.0, "duration": 3.0, "rule": "stack", "max_stacks": 4})
	es.apply({"type": "ward", "magnitude": 40.0, "duration": 9.0, "tags": ["fire"]})
	es.tick(0.7)
	var rows: Array = JSON.parse_string(JSON.stringify(es.serialize()))
	var back := EffectSet.new()
	back.deserialize(rows)
	assert_str(JSON.stringify(back.serialize())).is_equal(JSON.stringify(es.serialize()))
	assert_int(back.count("burn")).is_equal(1)
	assert_float(float(back.active[0]["left"])).is_equal_approx(float(es.active[0]["left"]), 0.0001)


func test_apply_effects_sorts_riders_by_target() -> void:
	var ab := _def("mix", {"effects": [
		{"type": "dot", "family": "burn", "dps_ratio": 0.1, "duration": 3.0},
		{"type": "stun", "duration": 0.5},
		{"type": "ward", "magnitude": 20.0, "duration": 5.0},
		{"type": "heal", "magnitude": 12.0},
		{"type": "restore", "resource": "qi", "magnitude": 7.0}]})
	var r := Runner.new()
	var foe := EffectSet.new()
	var res: Dictionary = r.apply_effects(ab, 50, foe, "enemy")
	assert_array(foe.families()).is_equal(["burn", "stun"])
	assert_float(float(foe.active[0]["magnitude"])).is_equal_approx(5.0, 0.0001)
	assert_array(res["statuses"]).is_equal([{"status": "stun", "duration": 0.5}])
	var me := EffectSet.new()
	var own: Dictionary = r.apply_effects(ab, 50, me, "self", 1.5)
	assert_array(me.families()).is_equal(["ward"])
	assert_float(float(me.active[0]["magnitude"])).is_equal_approx(30.0, 0.0001)    # power scales the ward
	assert_int(own["heal"]).is_equal(18)
	assert_float(own["restore"]["qi"]).is_equal_approx(10.5, 0.0001)
	# A burn needs a hit to scale from: no damage, no burn.
	var cold := EffectSet.new()
	r.apply_effects(ab, 0, cold, "enemy")
	assert_bool(cold.has("burn")).is_false()


func test_runner_serialises_cooldowns_and_effects() -> void:
	var h := _runner([_def("palm")])
	var r: Runner = h["runner"]
	r.begin("palm")
	r.effects.apply({"type": "buff", "family": "x", "stats": {"a": 1.0}, "duration": 5.0})
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.serialize()))
	var r2 := Runner.new()
	r2.deserialize(d)
	assert_float(r2.cooldown_left("palm")).is_equal_approx(4.0, 0.0001)
	assert_bool(r2.effects.has("x")).is_true()
