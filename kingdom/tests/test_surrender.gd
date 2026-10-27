extends GdUnitTestSuite
## WP-04: bandit morale break -> flee or surrender, soldier holds formation, veteran counters repeats,
## surrendered humans are bound, delivered to a guard or ransomed (sim/arrest.gd).

const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const Arrest := preload("res://scripts/sim/arrest.gd")


func _ctx(extra := {}) -> Dictionary:
	var c := {"dist": 2.0, "target_state": "idle", "has_token": true, "own_hp_frac": 1.0}
	c.merge(extra, true)
	return c


## Runs thinks until a FLEE/SURRENDER intent appears or `n` thinks pass; returns the first such intent or -1.
func _until_break(f: RefCounted, ctx: Dictionary, n := 40) -> int:
	for i in n:
		var d: Dictionary = f.think(0.25, ctx)
		if d["intent"] == Fighter.Intent.FLEE or d["intent"] == Fighter.Intent.SURRENDER:
			return d["intent"]
	return -1


func test_profiles_are_opt_in() -> void:
	var f: RefCounted = Fighter.make("bandit", 1)
	for i in 40:
		var d: Dictionary = f.think(0.25, _ctx({"own_hp_frac": 0.05}))
		assert_bool(d["intent"] == Fighter.Intent.FLEE or d["intent"] == Fighter.Intent.SURRENDER).is_false()
	assert_bool(f.surrendered).is_false()


func test_stat_archetypes_map_to_profiles() -> void:
	var want := {"bandit": "bandit", "guard": "soldier", "captain": "veteran", "wolf": "beast", "bandit_chief": "veteran"}
	for a: String in want:
		var f: RefCounted = Fighter.make(a, 1)
		f.set_profile()
		assert_str(f.profile).is_equal(want[a])


func test_healthy_bandit_fights_on() -> void:
	var f: RefCounted = Fighter.make("bandit", 3)
	f.set_profile()
	assert_int(_until_break(f, _ctx())).is_equal(-1)


func test_wounded_bandit_breaks_and_either_flees_or_surrenders() -> void:
	var flee := 0
	var surr := 0
	for s in 40:
		var f: RefCounted = Fighter.make("bandit", s)
		f.set_profile()
		var r := _until_break(f, _ctx({"own_hp_frac": 0.2}))
		assert_int(r).is_not_equal(-1)
		if r == Fighter.Intent.FLEE:
			flee += 1
		else:
			surr += 1
	assert_int(flee).is_greater(0)
	assert_int(surr).is_greater(0)


func test_cornered_bandit_always_surrenders() -> void:
	for s in 20:
		var f: RefCounted = Fighter.make("bandit", s)
		f.set_profile()
		assert_int(_until_break(f, _ctx({"own_hp_frac": 0.2, "cornered": true}))).is_equal(Fighter.Intent.SURRENDER)
		assert_bool(f.surrendered).is_true()


func test_fleeing_bandit_surrenders_when_cornered() -> void:
	for s in 60:
		var f: RefCounted = Fighter.make("bandit", s)
		f.set_profile()
		if _until_break(f, _ctx({"own_hp_frac": 0.2})) != Fighter.Intent.FLEE:
			continue
		var d: Dictionary = f.think(0.25, _ctx({"own_hp_frac": 0.2, "cornered": true}))
		assert_int(d["intent"]).is_equal(Fighter.Intent.SURRENDER)
		return
	fail("no seed fled")


func test_surrender_is_final() -> void:
	var f: RefCounted = Fighter.make("bandit", 1)
	f.set_profile()
	_until_break(f, _ctx({"own_hp_frac": 0.2, "cornered": true}))
	for i in 10:
		assert_int(f.think(0.25, _ctx())["intent"]).is_equal(Fighter.Intent.SURRENDER)


func test_beast_flees_but_never_surrenders() -> void:
	for s in 20:
		var f: RefCounted = Fighter.make("wolf", s)
		f.set_profile()
		assert_int(_until_break(f, _ctx({"own_hp_frac": 0.1, "cornered": true}))).is_equal(Fighter.Intent.FLEE)


func test_soldier_and_veteran_do_not_break_at_a_third_hp() -> void:
	for a in ["guard", "captain"]:
		var f: RefCounted = Fighter.make(a, 2)
		f.set_profile()
		assert_int(_until_break(f, _ctx({"own_hp_frac": 0.35}))).is_equal(-1)


func test_soldier_holds_formation_until_the_target_closes() -> void:
	var f: RefCounted = Fighter.make("guard", 4)
	f.set_profile()
	for i in 10:
		assert_int(f.think(0.25, _ctx({"dist": 12.0, "in_formation": true}))["intent"]).is_equal(Fighter.Intent.HOLD)
	assert_int(f.think(0.25, _ctx({"dist": 12.0, "in_formation": false}))["intent"]).is_equal(Fighter.Intent.APPROACH)


func test_veteran_remembers_five_attacks_and_counters_a_repeat() -> void:
	var f: RefCounted = Fighter.make("captain", 7, 0)    # rank 0: no base reaction, only the repeat bonus
	f.set_profile()
	for id in ["a", "b", "c", "d", "e", "f"]:
		f.observe_attack(id)
	assert_array(f.last_attacks).has_size(5)
	assert_array(f.last_attacks).contains_exactly(["b", "c", "d", "e", "f"])
	assert_bool(f.observe_attack("a")).is_false()        # "a" fell out of the buffer
	assert_bool(f.observe_attack("f")).is_true()
	var counters := 0
	var fresh := 0
	var v: RefCounted = Fighter.make("captain", 9, 0)
	v.set_profile()
	for i in 300:
		v.last_attacks.clear()
		v.last_attacks.append("slash")
		if v.consider_reaction(float(i) * 2.0, -1.0, "slash").get("kind", "") == "counter":
			counters += 1
		v.last_attacks.clear()
		if not v.consider_reaction(float(i) * 2.0 + 1.0, -1.0, "slash").is_empty():
			fresh += 1
	assert_int(counters).is_between(70, 140)             # 0.35 of 300
	assert_int(fresh).is_equal(0)                        # rank 0, first sighting: never


func test_non_veterans_do_not_remember() -> void:
	var f: RefCounted = Fighter.make("bandit", 1)
	f.set_profile()
	f.observe_attack("x")
	assert_bool(f.observe_attack("x")).is_false()
	assert_array(f.last_attacks).is_empty()


func test_captive_record_only_after_surrender() -> void:
	var f: RefCounted = Fighter.make("bandit", 1)
	f.set_profile()
	assert_dict(f.captive_record()).is_empty()
	_until_break(f, _ctx({"own_hp_frac": 0.2, "cornered": true}))
	assert_bool(f.captive_record()["surrendered"]).is_true()


func test_bind_then_guard_pays_bounty() -> void:
	var f: RefCounted = Fighter.make("bandit", 1)
	f.set_profile()
	_until_break(f, _ctx({"own_hp_frac": 0.2, "cornered": true}))
	var c: Dictionary = f.captive_record()
	assert_bool(Arrest.take_to_guard(c)["ok"]).is_false()      # not bound yet
	assert_bool(Arrest.bind(c)["ok"]).is_true()
	var paid := [0]
	var r := Arrest.take_to_guard(c, func(g: int) -> void: paid[0] += g)
	assert_bool(r["ok"]).is_true()
	assert_int(paid[0]).is_equal(Arrest.captive_bounty(c))
	assert_str(c["state"]).is_equal("delivered")
	assert_bool(Arrest.ransom(c, RandomNumberGenerator.new())["ok"]).is_false()   # already gone


func test_bind_needs_a_surrender() -> void:
	assert_bool(Arrest.bind({"surrendered": false})["ok"]).is_false()


func test_ransom_pays_or_cuts_loose_and_chiefs_cost_more() -> void:
	var ok := 0
	var loose := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var gold := [0]
	for i in 200:
		var c := {"surrendered": true, "rank": 3, "chief": false, "state": "free"}
		Arrest.bind(c)
		var r := Arrest.ransom(c, rng, func(g: int) -> void: gold[0] += g)
		if r["ok"]:
			ok += 1
			assert_str(c["state"]).is_equal("ransomed")
		else:
			loose += 1
			assert_str(c["state"]).is_equal("escaped")
	assert_int(ok).is_between(100, 160)
	assert_int(loose).is_greater(0)
	assert_int(gold[0]).is_equal(ok * Arrest.ransom_value({"rank": 3}))
	assert_int(Arrest.ransom_value({"rank": 3, "chief": true})).is_equal(Arrest.ransom_value({"rank": 3}) * 3)
