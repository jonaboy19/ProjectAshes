extends GdUnitTestSuite
## AR-2/3/4/5: observer tiers vs sensitivity, no mind control, crowd reaction mix, culture, contract, presence integration.

const AuraField := preload("res://scripts/population/aura_field.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const Presence := preload("res://scripts/population/presence.gd")
const Adapter := preload("res://scripts/population/reaction_adapter.gd")

var f: RefCounted


func before_test() -> void:
	f = AuraField.new()


func _subject(emit := 0.6, sig := "warm_gold") -> Dictionary:
	return {"id": "i:player", "aura_emit": emit, "aura_suppress": 0.0, "reach_m": 6.0 + 70.0 * pow(emit, 1.3), "signature": sig}


func _villager(extra := {}) -> Dictionary:
	var o := {"id": "v1", "magic_sense": 0.1, "persona": {"courage": 0.5, "pious": 0.2}, "kingdom": "caldrenn"}
	o.merge(extra, true)
	return o


func test_felt_falls_with_distance_and_zero_beyond_reach() -> void:
	var s := _subject(0.7)
	var near: float = f.felt(_villager(), s, 2.0)
	var mid: float = f.felt(_villager(), s, 15.0)
	assert_float(near).is_greater(mid)
	assert_float(f.felt(_villager(), s, float(s["reach_m"]) + 1.0)).is_equal(0.0)
	assert_float(f.felt(_villager(), _subject(0.0), 1.0)).is_equal(0.0)


func test_walls_muffle() -> void:
	var s := _subject(0.7)
	assert_float(f.felt(_villager(), s, 5.0, 0.45)).is_less(f.felt(_villager(), s, 5.0, 1.0))


func test_same_emit_gives_ordered_felt_across_observers() -> void:
	var s := _subject(0.4)
	var d := 12.0
	var villager: float = f.felt(_villager(), s, d)
	var mage: float = f.felt(_villager({"magic_sense": 1.0}), s, d)
	var soldier: float = f.felt(_villager({"training": "soldier"}), s, d)
	var monk: float = f.felt(_villager({"training": "monk"}), s, d)
	var dog: float = f.felt(_villager({"species": "dog"}), s, d)
	var horse: float = f.felt(_villager({"species": "horse"}), s, d)
	var undead: float = f.felt(_villager({"species": "undead"}), s, d)
	assert_float(mage).is_greater_equal(villager)
	assert_float(soldier).is_less(villager)
	assert_float(monk).is_less(soldier)
	assert_float(dog).is_greater(villager)                        # animals exceed humans at equal emit
	assert_float(horse).is_greater_equal(dog)
	assert_float(undead).is_equal(0.0)
	assert_float(f.felt(_villager({"state": "asleep"}), s, d)).is_less(villager)
	assert_float(f.felt(_villager({"age_group": "elder"}), s, d)).is_greater_equal(villager)


func test_courage_changes_fear_and_tier() -> void:
	var s := _subject(0.7)
	var fv: float = f.felt(_villager(), s, 4.0)
	var timid := AuraField.fear_of(_villager({"persona": {"courage": 0.1}}), fv)
	var brave := AuraField.fear_of(_villager({"persona": {"courage": 0.9}}), fv)
	assert_float(timid).is_greater(brave)
	assert_int(AuraField.tier_of(timid)).is_greater_equal(AuraField.tier_of(brave))
	var child := AuraField.fear_of(_villager({"age_group": "child", "persona": {"courage": 0.1}}), fv)
	assert_float(child).is_less(timid)                            # children behave as courage 0.9


func test_tier_thresholds_and_hysteresis() -> void:
	assert_int(AuraField.tier_of(0.05)).is_equal(0)
	assert_int(AuraField.tier_of(0.12)).is_equal(1)
	assert_int(AuraField.tier_of(0.3)).is_equal(2)
	assert_int(AuraField.tier_of(0.55)).is_equal(3)
	assert_int(AuraField.tier_of(0.8)).is_equal(4)
	assert_int(AuraField.tier_of(1.0)).is_equal(5)
	assert_int(AuraField.tier_of(0.29, 2)).is_equal(2)            # inside the band: no flicker
	assert_int(AuraField.tier_of(0.2, 2)).is_equal(1)


func test_low_power_cannot_grief() -> void:
	# tier-3 cultivator (P 0.12 for the table) releases fully: ordinary adults at 10 m stay below panic
	var s := _subject(0.12)
	var fv: float = f.felt(_villager(), s, 10.0)
	assert_int(AuraField.tier_of(AuraField.fear_of(_villager(), fv))).is_less(3)
	var big := _subject(0.95)
	var fb: float = f.felt(_villager({"persona": {"courage": 0.2}}), big, 4.0)
	assert_int(AuraField.tier_of(AuraField.fear_of(_villager({"persona": {"courage": 0.2}}), fb))).is_greater_equal(4)


func test_no_mind_control_only_fear_reactions() -> void:
	var seen := {}
	for tier in range(0, 6):
		for pious in [0.1, 0.9]:
			for sig in ["warm_gold", "dark_swirl", "cold_white"]:
				for kingdom in ["caldrenn", "solmarch"]:
					for child in [false, true]:
						for guard in [false, true]:
							var o := _villager({"kingdom": kingdom, "persona": {"courage": 0.3, "pious": pious}, "has_child": child, "guard": guard, "guard_near": true, "id_n": tier * 7 + 1})
							var k := AuraField.reaction_for(tier, o, sig)
							seen[k] = true
							if tier == 0:
								assert_int(k).is_equal(0)
	for k: int in seen:
		if k != 0:
			assert_bool(k in AuraField.ALLOWED).is_true()
	# aura never produces obedience-shaped kinds
	for bad in [RR.Kind.CONFRONT, RR.Kind.WAVE, RR.Kind.RETURN_TO_WORK, RR.Kind.STEP_ASIDE]:
		assert_bool(bad in AuraField.ALLOWED).is_false()


func test_crowd_reaction_mix_by_tier() -> void:
	var K := RR.Kind
	var parent := _villager({"has_child": true, "id_n": 5})
	assert_int(AuraField.reaction_for(3, parent)).is_equal(K.FLEE_WITH_CHILD)
	assert_int(AuraField.reaction_for(2, parent)).is_equal(K.HIDE)
	assert_int(AuraField.reaction_for(3, _villager({"id_n": 6}))).is_equal(K.FLEE)
	assert_int(AuraField.reaction_for(3, _villager({"can_hide": true, "persona": {"courage": 0.3}}))).is_equal(K.HIDE)
	assert_int(AuraField.reaction_for(3, _villager({"age_group": "elder"}))).is_equal(K.KNEEL)
	assert_int(AuraField.reaction_for(4, _villager({"age_group": "elder"}))).is_equal(K.FAINT)
	assert_int(AuraField.reaction_for(4, _villager({"id_n": 2}))).is_equal(K.KNEEL)
	assert_int(AuraField.reaction_for(5, _villager({"id_n": 2}))).is_equal(K.FAINT)
	var guard := _villager({"guard": true, "guard_near": true})
	assert_int(AuraField.reaction_for(2, guard)).is_equal(K.STEP_BACK)       # veterans hold the ring at T2
	assert_int(AuraField.reaction_for(3, guard)).is_equal(K.CALL_GUARD)
	var low := [AuraField.reaction_for(1, _villager({"id_n": 2})), AuraField.reaction_for(1, _villager({"id_n": 3}))]
	for k: int in low:
		assert_bool(k in [K.GLANCE, K.LOOK_AWAY]).is_true()
	# a mixed crowd at one tier is not uniform
	var kinds := {}
	for n in 30:
		kinds[AuraField.reaction_for(2, _villager({"id_n": n}))] = true
	assert_int(kinds.size()).is_greater_equal(2)


func test_roles() -> void:
	assert_str(AuraField.role_of(_villager({"has_child": true}), 2)).is_equal("parent")
	assert_str(AuraField.role_of(_villager({"age_group": "elder"}), 2)).is_equal("elder")
	assert_str(AuraField.role_of(_villager({"age_group": "child"}), 2)).is_equal("child")
	assert_str(AuraField.role_of(_villager({"guard": true}), 2)).is_equal("guard")
	assert_str(AuraField.role_of(_villager({"stall_owner": true}), 2)).is_equal("merchant")
	assert_str(AuraField.role_of(_villager({"persona": {"pious": 0.9}, "kingdom": "solmarch"}), 2, "holy")).is_equal("devotee")
	assert_str(AuraField.role_of(_villager({"persona": {"pious": 0.9}}), 2, "demonic")).is_equal("fanatic")
	assert_str(AuraField.role_of(_villager({"drunk": true}), 1)).is_equal("drunk")
	# looters only at high chaos
	var greedy := {"persona": {"greedy": 0.9, "courage": 0.9}, "chaos": 0.2}
	assert_str(AuraField.role_of(_villager(greedy), 2)).is_not_equal("looter")
	greedy["chaos"] = 0.8
	assert_str(AuraField.role_of(_villager(greedy), 2)).is_equal("looter")
	assert_float(AuraField.chaos_index(4, true, 2, 0)).is_equal_approx(0.8, 0.001)
	assert_float(AuraField.chaos_index(4, true, 2, 3)).is_equal(0.0)          # guards arriving lower it


func test_culture_difference() -> void:
	var K := RR.Kind
	# church kingdom, pious, warm gold: kneel; same release in Valencios: nobody kneels, the watch is called
	var church := _villager({"kingdom": "solmarch", "persona": {"courage": 0.5, "pious": 0.9}, "guard_near": true, "id_n": 3})
	var secular := _villager({"kingdom": "caldrenn", "persona": {"courage": 0.5, "pious": 0.9}, "guard_near": true, "id_n": 3})
	assert_int(AuraField.reaction_for(2, church, "warm_gold")).is_equal(K.KNEEL)
	assert_int(AuraField.reaction_for(2, secular, "warm_gold")).is_equal(K.CALL_GUARD)
	# dark signature in the church kingdom: denounce, not kneel
	assert_int(AuraField.reaction_for(2, church, "dark_swirl")).is_equal(K.CALL_GUARD)
	assert_int(AuraField.reaction_for(2, _villager({"kingdom": "solmarch", "persona": {"pious": 0.9}}), "dark_swirl")).is_equal(K.WARN)
	# monster town: release is a greeting, nobody calls the guard, fear is halved
	var monster := _villager({"culture": "monster_town", "guard": true, "guard_near": true})
	assert_int(AuraField.reaction_for(3, monster)).is_equal(K.STEP_BACK)
	var fv := 0.8
	assert_float(AuraField.fear_of(_villager({"culture": "monster_town"}), fv)).is_less(AuraField.fear_of(_villager(), fv))
	# holy read raises sensitivity of the pious
	var holy: float = f.felt(church, _subject(0.5, "warm_gold"), 6.0)
	var plain: float = f.felt(_villager({"kingdom": "caldrenn", "persona": {"courage": 0.5, "pious": 0.9}}), _subject(0.5, "warm_gold"), 6.0)
	assert_float(holy).is_not_equal(plain)


func test_repulsion_field_flows_not_teleports() -> void:
	var c1 := AuraField.repulsion_cost(Vector2(2, 0), Vector2.ZERO, 40.0, 0.8)
	var c2 := AuraField.repulsion_cost(Vector2(15, 0), Vector2.ZERO, 40.0, 0.8)
	assert_float(c1).is_greater(c2)
	assert_float(AuraField.repulsion_cost(Vector2(30, 0), Vector2.ZERO, 40.0, 0.8)).is_equal(0.0)
	assert_float(c1).is_less_equal(6.0)                           # bounded cost: a soft field


# --------------------------------------------------------------- reaction contract (AR-5)

func test_new_kinds_extend_contract_without_moving_old() -> void:
	assert_int(RR.Kind.RETURN_TO_WORK).is_equal(12)
	assert_int(RR.Kind.KNEEL).is_equal(13)
	assert_int(RR.Kind.FLEE_WITH_CHILD).is_equal(16)
	assert_int(RR.NAMES.size()).is_equal(17)
	for arr in [RR.PRIORITY, RR.DURATION_MS, RR.LAYER_OF, RR.KEEPS_ACTIVITY]:
		assert_int(arr.size()).is_equal(RR.NAMES.size())
	for k in range(0, RR.NAMES.size()):
		assert_int(RR.kind_from_name(RR.name_of(k))).is_equal(k)        # name round trip
	assert_str(RR.name_of(RR.Kind.FLEE_WITH_CHILD)).is_equal("flee_with_child")
	for k in RR.AURA_KINDS:
		assert_int(Adapter.describe(k)["fallback_kind"]).is_not_equal(k)  # no-op adapter fallback exists
		assert_bool(Adapter.describe(k).has("clip_hint")).is_true()


func test_flee_exclusivity_preserved_and_extended() -> void:
	var q := RR.new()
	assert_bool(q.request(1, RR.Kind.FLEE, 9, 0)).is_true()
	assert_bool(q.request(1, RR.Kind.CONFRONT, 9, 100)).is_false()
	assert_bool(q.request(1, RR.Kind.KNEEL, 9, 100)).is_false()            # prio 4: blocked by the exclusive flee
	assert_bool(q.request(1, RR.Kind.FAINT, 9, 200)).is_true()             # legs give way: outranks flee
	var q2 := RR.new()
	assert_bool(q2.request(2, RR.Kind.FLEE_WITH_CHILD, 5, 0)).is_true()
	assert_bool(q2.request(2, RR.Kind.WARN, 5, 100)).is_false()
	assert_bool(q2.request(2, RR.Kind.GLANCE, 5, 100)).is_false()
	assert_int(q2.current(2, RR.Layer.LOCO, 100)).is_equal(RR.Kind.FLEE_WITH_CHILD)
	var r: Array = q2.pop(2)
	assert_int(r[0]).is_equal(RR.Kind.FLEE_WITH_CHILD)
	assert_int(r[1]).is_equal(5)


func test_fallback_delivers_through_adapter() -> void:
	var q := RR.new()
	q.request(3, RR.Kind.HIDE, 7, 0)
	var got := []
	var ad := Adapter.new()
	ad.consume(q, 3, func(_slot: int, kind: int, _t: int, info: Dictionary) -> void: got.append([kind, info["fallback_kind"]]))
	assert_int(got.size()).is_equal(1)
	assert_int(got[0][0]).is_equal(RR.Kind.HIDE)
	assert_int(got[0][1]).is_equal(RR.Kind.STEP_BACK)


# --------------------------------------------------------------- presence integration (AR-3)

func _presence_run(p: Presence, secs: float) -> void:
	var now := 0
	while now < int(secs * 1000.0):
		now += 250
		p.tick(now)


func _kinds(p: Presence, id: int) -> Array:
	var out: Array = []
	var slot := p.slot_of(id)
	for i in 20:
		var r: Array = p.requests.pop(slot)
		if r.is_empty():
			break
		out.append(r[0])
	return out


func test_presence_aura_stimulus_makes_crowd_react() -> void:
	var p := Presence.new()
	p.stagger = 1
	p.set_body(0, Vector2(0, 0), Vector2(0, 1))
	p.describe_subject(0, {"aura_emit": 0.9, "aura_suppress": 0.0, "reach_m": 70.0, "signature": "warm_gold"})
	# a timid villager at 30 m (beyond the normal 20 m presence range, inside the aura reach), one behind a stone wall, one far out
	p.set_body(1, Vector2(0, 30), Vector2(0, -1))
	p.make_observer(1, {"tolerance": 0.0, "persona": {"courage": 0.1, "pious": 0.1}, "kingdom": "caldrenn"})
	p.set_body(2, Vector2(0, 8), Vector2(0, -1))
	p.make_observer(2, {"tolerance": 0.0, "persona": {"courage": 0.1, "pious": 0.1}, "wall": 0.25})
	p.set_body(3, Vector2(0, 90), Vector2(0, -1))
	p.make_observer(3, {"tolerance": 0.0, "persona": {"courage": 0.1}})
	_presence_run(p, 20.0)
	assert_int(p.requests.pending_count(p.slot_of(3))).is_equal(0)         # outside reach: nothing
	var k1 := _kinds(p, 1)
	assert_int(k1.size()).is_greater(0)
	for k: int in k1:
		assert_bool(k in AuraField.ALLOWED or k == RR.Kind.RETURN_TO_WORK).is_true()
	var k2 := _kinds(p, 2)
	assert_int(k2.size()).is_greater(0)


func test_presence_no_aura_no_change_and_deterministic() -> void:
	var run := func() -> Array:
		var p := Presence.new()
		p.stagger = 1
		p.set_body(0, Vector2(0, 0), Vector2(0, 1))
		p.describe_subject(0, {"aura_emit": 0.8, "reach_m": 60.0})
		p.set_body(1, Vector2(0, 5), Vector2(0, -1))
		p.make_observer(1, {"tolerance": 0.0, "persona": {"courage": 0.2}})
		_presence_run(p, 12.0)
		return _kinds(p, 1)
	assert_array(run.call()).is_equal(run.call())
	var q := Presence.new()
	q.stagger = 1
	q.set_body(0, Vector2(0, 0), Vector2(0, -1), Vector2.ZERO, Vector2(0, -1))     # head turned away: no stare
	q.set_body(1, Vector2(0, 5), Vector2(0, -1))
	q.make_observer(1, {"tolerance": 0.0})
	_presence_run(q, 12.0)
	assert_int(q.requests.pending_count(q.slot_of(1))).is_equal(0)


func test_presence_tick_cost_with_48_bodies() -> void:
	var p := Presence.new()
	p.stagger = 3
	p.set_body(0, Vector2(0, 0), Vector2(0, 1))
	p.describe_subject(0, {"aura_emit": 0.8, "reach_m": 60.0})
	for i in range(1, 48):
		p.set_body(i, Vector2(float(i % 8) * 4.0 - 14.0, float(i / 8) * 4.0 + 3.0), Vector2(0, -1))
		p.make_observer(i, {"persona": {"courage": 0.3}})
	var t0 := Time.get_ticks_usec()
	for n in 40:
		p.tick(n * 250)
	var per_tick := float(Time.get_ticks_usec() - t0) / 40.0
	assert_float(per_tick).is_less(8000.0)                         # loose: CI runners are slow (target 0.3 ms)
