extends GdUnitTestSuite
## C§32-38: five power paths, their limits, cross-training, prodigy gate.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "abs_hours": 0, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk(paths: Array = []) -> RefCounted:
	var pp: RefCounted = Hub.new().mod("power_paths")
	for p: String in paths:
		pp.learn(p, "academy")
	return pp


func test_learn_and_sources() -> void:
	var pp := _mk()
	assert_bool(pp.learn("magic", "academy")).is_true()
	assert_bool(pp.learn("magic", "academy")).is_false()
	assert_bool(pp.learn("sorcery", "academy")).is_false()
	assert_bool(pp.learn("knight", "cheat")).is_false()
	assert_array(pp.paths()).is_equal(["magic"])
	assert_int(pp.level("magic")).is_equal(1)
	assert_int(pp.level("beast")).is_equal(0)
	assert_bool(pp.can_use("beast", 1.0, CTX)["ok"]).is_false()
	var s := _mk()
	s.learn("knight", "self")
	assert_float(s.xp_multiplier("knight")).is_less(pp.xp_multiplier("magic"))


func test_magic_exhausted_casting_is_risky() -> void:
	var pp := _mk(["magic"])
	var fresh: Dictionary = pp.can_use("magic", 5.0, CTX)
	assert_bool(fresh["ok"]).is_true()
	# drain into overdraw
	pp.use("magic", pp.resource("magic")["cur"] + 5.0, CTX)
	assert_float(pp.resource("magic")["cur"]).is_less(0.0)
	var risky: Dictionary = pp.can_use("magic", 2.0, CTX)
	assert_bool(risky["ok"]).is_true()
	assert_float(risky["risk"]).is_greater(fresh["risk"] + 0.2)
	var bad := 0
	for i in 40:
		pp.rest(20.0, CTX)
		pp.use("magic", pp.resource("magic")["cur"] + 4.0, CTX)
		var r: Dictionary = pp.use("magic", 1.0, CTX)
		if r["ok"] and not r["effects"].is_empty():
			bad += 1
	assert_int(bad).is_greater(0)


func test_magic_wraps_life_magicules() -> void:
	var holder := _FakeLife.new()
	var ctx := {"life": holder, "abs_hours": 0}
	var pp := _mk(["magic"])
	assert_float(pp.resource("magic", ctx)["cur"]).is_equal(holder.magicules.current)
	var before: float = holder.magicules.current
	var r: Dictionary = pp.use("magic", 10.0, ctx)
	assert_bool(r["ok"]).is_true()
	assert_float(holder.magicules.current).is_equal(before - 10.0)
	# no duplicate regen from the module tick
	pp.tick_hour(1, ctx)
	assert_float(holder.magicules.current).is_equal(before - 10.0)
	# instability injures through life.injuries
	holder.magicules.current = -5.0
	holder.magicules.exhaustion = 1.0
	for i in 60:
		holder.magicules.current = -5.0
		pp.use("magic", 0.1, ctx)
	assert_bool(holder.injuries.has("magicule_burn")).is_true()


func test_bending_desert_weaker_than_river() -> void:
	var pp := _mk(["bending"])
	var river := {"near_water": true, "biome": "plains", "element": "water"}
	var desert := {"near_water": false, "biome": "desert", "element": "water"}
	assert_float(pp.environment_factor("bending", desert)).is_less(pp.environment_factor("bending", river))
	var a: Dictionary = pp.use("bending", 10.0, river)
	var pp2 := _mk(["bending"])
	var b: Dictionary = pp2.use("bending", 10.0, desert)
	assert_float(b["power"]).is_less(a["power"])
	assert_float(pp2.resource("bending")["cur"]).is_less(pp.resource("bending")["cur"])
	# a fire bender is not hurt by the desert
	assert_float(pp.environment_factor("bending", {"biome": "desert", "element": "fire"})).is_greater(1.0)


func test_bending_injuries_change_forms() -> void:
	var pp := _mk(["bending"])
	var ctx := {"element": "water", "near_water": true, "injuries": ["broken_arm"]}
	assert_float(pp.environment_factor("bending", ctx)).is_less(1.0)
	var r: Dictionary = pp.use("bending", 5.0, ctx)
	var forms: Array = r["effects"].filter(func(e: Dictionary) -> bool: return e["type"] == "form_change")
	assert_int(forms.size()).is_equal(1)
	var earth := {"element": "earth", "injuries": ["broken_leg"]}
	assert_float(pp.environment_factor("bending", earth)).is_less(0.6)
	assert_float(pp.environment_factor("bending", {"element": "earth"})).is_equal(1.0)


func test_sect_overuse_causes_injury_and_mastery_helps() -> void:
	var pp := _mk(["sect"])
	var ctx := {"abs_hours": 48}
	var hurt := false
	for i in 200:
		if pp.use("sect", 2.0, ctx)["ok"]:
			pass
		pp.tick_hour(i, ctx) if i % 4 == 0 else null
		if not pp.active_injuries(ctx).is_empty():
			hurt = true
			break
	assert_bool(hurt).is_true()
	assert_float(pp.strain("sect")).is_greater(0.0)
	# mastery lowers risk at equal strain
	var lo := _mk(["sect"])
	var hi := _mk(["sect"])
	hi.gain_xp("sect", 2000.0)
	lo._p["sect"]["strain"] = 0.8
	hi._p["sect"]["strain"] = 0.8
	assert_float(hi.can_use("sect", 1.0)["risk"]).is_less(lo.can_use("sect", 1.0)["risk"])
	# self-injury heals by day
	pp.tick_day(200, ctx)
	assert_array(pp.active_injuries(ctx)).is_empty()


func test_sect_injury_lands_in_life() -> void:
	var holder := _FakeLife.new()
	var pp := _mk(["sect"])
	pp._p["sect"]["strain"] = 1.0
	for i in 60:
		pp._p["sect"]["cur"] = 30.0
		pp._p["sect"]["strain"] = 1.0
		pp.use("sect", 1.0, {"life": holder})
	assert_int(holder.injuries.active.size()).is_greater(0)


func test_knight_usable_at_zero_energy() -> void:
	var pp := _mk(["knight"])
	pp._p["knight"]["cur"] = 0.0
	var c: Dictionary = pp.can_use("knight", 5.0, CTX)
	assert_bool(c["ok"]).is_true()
	var r: Dictionary = pp.use("knight", 5.0, CTX)
	assert_bool(r["ok"]).is_true()
	assert_float(r["power"]).is_greater(0.3)
	assert_float(pp.resource("knight")["cur"]).is_equal(0.0)
	var fresh := _mk(["knight"])
	assert_float(fresh.use("knight", 5.0, CTX)["power"]).is_greater(r["power"])
	# armour load costs more; conditioning offsets it
	var heavy := {"armour_load": 1.0}
	assert_float(_mk(["knight"]).can_use("knight", 5.0, heavy)["risk"]).is_greater_equal(0.0)
	var a := _mk(["knight"])
	a.use("knight", 10.0, heavy)
	var b := _mk(["knight"])
	b.use("knight", 10.0, CTX)
	assert_float(a.resource("knight")["cur"]).is_less(b.resource("knight")["cur"])


func test_beast_bond_trust_and_burden() -> void:
	var pp := _mk(["beast"])
	var ctx := {"creature": "wolf_1"}
	pp.add_trust("wolf_1", -0.5)
	var c: Dictionary = pp.can_use("beast", 3.0, ctx)
	assert_bool(c["ok"]).is_false()
	assert_str(c["reason"]).contains("trust")
	pp.add_trust("wolf_1", 0.6)
	assert_bool(pp.can_use("beast", 3.0, ctx)["ok"]).is_true()
	var t0: float = pp.trust("wolf_1")
	var p_low: float = pp.use("beast", 3.0, ctx)["power"]
	assert_float(pp.trust("wolf_1")).is_greater(t0)
	pp.add_trust("wolf_1", 1.0)
	assert_float(pp.can_use("beast", 3.0, ctx)["risk"]).is_less(0.2)
	# mental burden raises risk
	pp._p["beast"]["burden"] = 0.9
	assert_float(pp.can_use("beast", 3.0, ctx)["risk"]).is_greater(0.3)
	assert_float(pp.burden()).is_greater(0.8)
	assert_float(p_low).is_greater(0.0)
	pp.rest(30.0)
	assert_float(pp.burden()).is_less(0.9)


func test_cross_training_slows() -> void:
	var pp := _mk(["knight"])
	var one: float = pp.xp_multiplier("knight")
	pp.learn("magic", "academy")
	var two: float = pp.xp_multiplier("knight")
	pp.learn("bending", "academy")
	var three: float = pp.xp_multiplier("knight")
	assert_float(two).is_less(one)
	assert_float(three).is_less(two)
	assert_float(pp.gain_xp("knight", 10.0)).is_equal_approx(10.0 * three, 0.0001)
	for p: String in ["sect", "beast"]:
		pp.learn(p, "academy")
	assert_float(pp.xp_multiplier("knight")).is_greater_equal(0.15)


func test_prodigy_gate() -> void:
	var pp := _mk(["knight", "magic", "bending"])
	assert_bool(pp.unlock_prodigy("rift_exposure", {"region": "valencios_first"})).is_false()
	assert_bool(pp.unlock_prodigy("rift_exposure", {})).is_false()
	assert_bool(pp.unlock_prodigy("because_i_said_so", {"region": "east"})).is_false()
	assert_bool(pp.is_prodigy()).is_false()
	var before: float = pp.xp_multiplier("knight")
	assert_bool(pp.unlock_prodigy("rift_exposure", {"region": "second_realm"})).is_true()
	assert_bool(pp.unlock_prodigy("rift_exposure", {"region": "second_realm"})).is_false()
	assert_bool(pp.is_prodigy()).is_true()
	assert_float(pp.xp_multiplier("knight")).is_greater(before)


func test_recovery_and_rest() -> void:
	var pp := _mk(["sect", "knight"])
	pp.use("sect", 30.0, CTX)
	var lo: float = pp.resource("sect")["cur"]
	pp.tick_hour(1, CTX)
	assert_float(pp.resource("sect")["cur"]).is_greater(lo)
	pp.rest(100.0)
	assert_float(pp.resource("sect")["cur"]).is_equal(pp.resource("sect")["max"])
	assert_float(pp.strain("sect")).is_equal(0.0)


func test_determinism_and_round_trip() -> void:
	var a := _mk(["magic", "sect", "beast"])
	var b := _mk(["magic", "sect", "beast"])
	for i in 50:
		a.use("magic", 9.0, CTX)
		b.use("magic", 9.0, CTX)
		a.use("sect", 3.0, CTX)
		b.use("sect", 3.0, CTX)
		if i % 5 == 0:
			a.rest(2.0)
			b.rest(2.0)
	assert_str(_norm(a.serialize())).is_equal(_norm(b.serialize()))
	var s: Dictionary = a.serialize()
	var c := _mk()
	c.deserialize(JSON.parse_string(JSON.stringify(s)))
	assert_str(_norm(c.serialize())).is_equal(_norm(s))
	# continues identically after load
	var r1: Dictionary = a.use("magic", 9.0, CTX)
	var r2: Dictionary = c.use("magic", 9.0, CTX)
	assert_str(_norm(r1)).is_equal(_norm(r2))


func test_hub_registration_and_hub_round_trip() -> void:
	var hub := Hub.new()
	assert_object(hub.mod("power_paths")).is_not_null()
	hub.mod("power_paths").learn("knight", "teacher")
	var d: Dictionary = hub.serialize()
	var h2 := Hub.new()
	h2.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_array(h2.mod("power_paths").paths()).is_equal(["knight"])


func test_perf() -> void:
	var pp := _mk(["magic", "bending", "sect", "knight", "beast"])
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		for p: String in pp.paths():
			pp.can_use(p, 3.0, {"creature": "x"})
			pp.use(p, 1.0, {"creature": "x"})
		pp.tick_hour(i, CTX)
	var per := float(Time.get_ticks_usec() - t0) / 2000.0
	assert_float(per).is_less(2000.0)


class _FakeLife extends RefCounted:
	var magicules := RAMagicules.new(40.0, 1.5)
	var injuries := RAInjuries.new()
