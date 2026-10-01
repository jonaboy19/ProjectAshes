extends GdUnitTestSuite
## NpcFighter decision model: determinism, rank scaling, token/perception gates, reaction rules, move tables.

const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")


func _ctx(extra := {}) -> Dictionary:
	var c := {"dist": 1.5, "target_state": "idle", "has_token": true, "own_hp_frac": 1.0}
	c.merge(extra, true)
	return c


func test_every_archetype_builds_with_moves() -> void:
	for name: String in Fighter.ARCHETYPES:
		var f: RefCounted = Fighter.make(name, 1)
		assert_bool(f.moves.size() >= 2).is_true()
		assert_bool(f.rank >= 0 and f.rank <= 10).is_true()
		assert_float(f.cooldown()).is_greater(0.5)


func test_same_seed_same_decisions() -> void:
	var a: RefCounted = Fighter.make("bandit", 99)
	var b: RefCounted = Fighter.make("bandit", 99)
	for i in 30:
		var da: Dictionary = a.think(0.25, _ctx({"dist": 1.0 + (i % 3)}))
		var db: Dictionary = b.think(0.25, _ctx({"dist": 1.0 + (i % 3)}))
		assert_int(da["intent"]).is_equal(db["intent"])
		assert_object(da["move"]).is_same(db["move"])


func test_reaction_numbers_follow_rank() -> void:
	var low: RefCounted = Fighter.make("goblin", 1, 0)
	var high: RefCounted = Fighter.make("goblin", 1, 10)
	assert_float(low.react_chance()).is_equal_approx(0.0, 0.0001)
	assert_float(high.react_chance()).is_equal_approx(0.7, 0.0001)
	assert_float(low.react_delay()).is_equal_approx(0.25, 0.0001)
	assert_float(high.react_delay()).is_equal_approx(0.10, 0.0001)


func test_never_reacts_twice_inside_the_gap() -> void:
	var f: RefCounted = Fighter.make("guard", 5, 10)
	var reacted := 0
	for i in 8:
		if not f.consider_reaction(float(i) * 0.1).is_empty():
			reacted += 1
	assert_int(reacted).is_less_equal(1)         # 8 tries inside 0.8 s: at most one reaction
	var gap_ok := false
	for i in 40:
		if not f.consider_reaction(10.0 + i * (Fighter.REACT_GAP + 0.01)).is_empty():
			gap_ok = true
	assert_bool(gap_ok).is_true()


func test_high_rank_reacts_more_often() -> void:
	var counts := []
	for rank in [1, 9]:
		var f: RefCounted = Fighter.make("bandit", 11, rank)
		var n := 0
		for i in 400:
			if not f.consider_reaction(float(i) * 2.0).is_empty():
				n += 1
		counts.append(n)
	assert_int(counts[1]).is_greater(counts[0] * 2)


func test_no_token_means_circle_not_strike() -> void:
	var f: RefCounted = Fighter.make("wolf", 3)
	for i in 20:
		var d: Dictionary = f.think(0.25, _ctx({"has_token": false}))
		assert_int(d["intent"]).is_equal(Fighter.Intent.CIRCLE)
		assert_object(d["move"]).is_null()


func test_unseen_target_holds() -> void:
	# guards: sees_target comes from Perception; without it the fighter never swings
	var f: RefCounted = Fighter.make("guard", 3)
	for i in 10:
		var d: Dictionary = f.think(0.25, _ctx({"sees_target": false}))
		assert_int(d["intent"]).is_equal(Fighter.Intent.HOLD)


func test_out_of_reach_approaches() -> void:
	var f: RefCounted = Fighter.make("orc", 3)
	var d: Dictionary = f.think(0.25, _ctx({"dist": 9.0}))
	assert_int(d["intent"]).is_equal(Fighter.Intent.APPROACH)


func test_moves_come_from_the_table_and_respect_range() -> void:
	var f: RefCounted = Fighter.make("wolf", 8)
	var seen := {}
	for i in 200:
		var m: Resource = f.choose_move(1.5)
		assert_object(m).is_not_null()
		assert_float(1.5).is_less_equal(maxf(m.max_range, m.reach))
		seen[m.id] = true
	assert_bool(seen.size() >= 2).is_true()      # a wolf has more than one move
	for id: String in seen:
		assert_object(Moves.find("wolf", id)).is_not_null()
	assert_object(f.choose_move(150.0)).is_null()


func test_only_high_rank_feints() -> void:
	var low: RefCounted = Fighter.make("bandit", 4, 3)
	var high: RefCounted = Fighter.make("bandit", 4, 9)
	var low_feints := 0
	var high_feints := 0
	for i in 400:
		var c := _ctx({"target_state": "blocking"})
		if low.think(0.25, c)["intent"] == Fighter.Intent.FEINT:
			low_feints += 1
		if high.think(0.25, c)["intent"] == Fighter.Intent.FEINT:
			high_feints += 1
	assert_int(low_feints).is_equal(0)
	assert_int(high_feints).is_greater(0)


func test_aggression_rises_against_a_tired_target_and_falls_when_hurt() -> void:
	var f: RefCounted = Fighter.make("bandit", 2)
	f.think(10.0, _ctx({"target_tired": true}))
	var up: float = f.aggression
	f.think(10.0, _ctx({"own_hp_frac": 0.1}))
	var down: float = f.aggression
	assert_float(up).is_greater(f.base_aggression)
	assert_float(down).is_less(f.base_aggression)


func test_press_after_win_chance_scales_with_rank() -> void:
	var low: RefCounted = Fighter.make("goblin", 6, 0)
	var high: RefCounted = Fighter.make("goblin", 6, 10)
	var l := 0
	var h := 0
	for i in 600:
		l += 1 if low.press_after_win() else 0
		h += 1 if high.press_after_win() else 0
	assert_int(l).is_equal(0)
	assert_int(h).is_between(150, 250)           # rank/30 = 0.33
