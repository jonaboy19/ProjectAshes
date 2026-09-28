extends GdUnitTestSuite
## Villager utility AI: deterministic scoring from inputs, response curves,
## needs, commitment and chat pairing (scripts/population/utility_brain.gd).

const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const Act := UtilityBrain.Act


func _winner(hour: float, over: Dictionary = {}, traits: Dictionary = {}) -> int:
	return UtilityBrain.best(UtilityBrain.make_context(hour, over, traits))


func _name(act: int) -> String:
	return UtilityBrain.NAMES[act]


func test_curves() -> void:
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.LOGISTIC, 0.5, 10.0, 0.5)).is_equal_approx(0.5, 0.0001)
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.BINARY, 0.49, 0.5, 0.1)).is_equal_approx(0.1, 0.0001)
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.BINARY, 0.5, 0.5, 0.1)).is_equal(1.0)
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.RANGE, 0.5, 1.0, 0.0)).is_equal_approx(0.5, 0.0001)
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.LINEAR, 2.0, 1.0, 0.0)).is_equal(1.0)   # clamped
	assert_float(UtilityBrain.curve(UtilityBrain.Resp.EXP, 0.5, 2.0, 0.0)).is_equal_approx(0.25, 0.0001)


func test_scoring_is_deterministic() -> void:
	var ctx := UtilityBrain.make_context(15.0, {"lonely": 0.7, "thirst": 0.6})
	var a := UtilityBrain.scores(ctx)
	var b := UtilityBrain.scores(ctx.duplicate())
	assert_int(a.size()).is_equal(UtilityBrain.NAMES.size())
	for i in a.size():
		assert_float(a[i]).is_equal(b[i])
	# Personality is seeded per person and stable; different people differ.
	assert_dict(UtilityBrain.personality(17)).is_equal(UtilityBrain.personality(17))
	assert_dict(UtilityBrain.personality(17)).is_not_equal(UtilityBrain.personality(18))
	for t: String in ["sociable", "lazy", "pious", "greedy"]:
		assert_float(float(UtilityBrain.personality(17)[t])).is_between(0.0, 1.0)


func test_a_zero_consideration_vetoes_the_action() -> void:
	# The inn is shut to guards on watch, however sociable.
	var ctx := UtilityBrain.make_context(20.0, {"guard": 1.0}, {"sociable": 1.0})
	assert_float(UtilityBrain.score(Act.INN, ctx)).is_equal(0.0)


func test_rain_makes_shelter_win() -> void:
	var dry := _winner(10.0, {"sched_work": 1.0})
	assert_str(_name(dry)).is_equal("work")
	var wet := _winner(10.0, {"sched_work": 1.0, "rain": 1.0, "rain_exposed": 1.0})
	assert_str(_name(wet)).is_equal("shelter")
	# At night the sleepers stay in bed rather than "sheltering".
	assert_str(_name(_winner(23.5, {"rain": 1.0, "tired": 0.7, "rest": 0.3}))).is_equal("sleep")


func test_evening_inn_for_sociable_home_for_shy() -> void:
	assert_str(_name(_winner(20.0, {}, {"sociable": 0.9}))).is_equal("inn")
	assert_str(_name(_winner(20.0, {}, {"sociable": 0.1}))).is_equal("home")
	# DailyRhythm's inn evening (the baseline) tips a middling person over.
	assert_str(_name(_winner(20.0, {"sched_inn": 1.0}, {"sociable": 0.4}))).is_equal("inn")
	# The inn is an evening thing.
	var noon := UtilityBrain.make_context(12.0, {}, {"sociable": 0.9})
	assert_float(UtilityBrain.score(Act.INN, noon)).is_equal(0.0)


func test_danger_makes_flee_win() -> void:
	for hour: float in [3.0, 10.0, 12.5, 20.0]:
		assert_str(_name(_winner(hour, {"danger": 0.9, "hungry": 0.8, "rain": 1.0}))).is_equal("flee")
	# Far-off trouble doesn't send anyone running.
	assert_str(_name(_winner(10.0, {"danger": 0.1, "sched_work": 1.0}))).is_equal("work")
	# Guards hold their ground.
	assert_str(_name(_winner(10.0, {"danger": 0.9, "guard": 1.0, "sched_work": 1.0}))).is_equal("work")


func test_needs_time_and_traits() -> void:
	assert_str(_name(_winner(12.5, {"hungry": 0.7}))).is_equal("eat")
	assert_str(_name(_winner(2.0, {"tired": 0.6, "rest": 0.4}))).is_equal("sleep")
	assert_str(_name(_winner(10.0, {"spectacle": 1.0, "sched_work": 1.0}))).is_equal("watch")
	assert_str(_name(_winner(9.0, {"sched_work": 0.0, "faithless": 0.8}, {"pious": 0.95}))).is_equal("pray")
	# Piety, not the clock, is what makes the difference.
	var devout := UtilityBrain.score(Act.PRAY, UtilityBrain.make_context(9.0, {"faithless": 0.8}, {"pious": 0.95}))
	var worldly := UtilityBrain.score(Act.PRAY, UtilityBrain.make_context(9.0, {"faithless": 0.8}, {"pious": 0.1}))
	assert_float(devout).is_greater(worldly * 3.0)
	# Lazy people work less hard than diligent ones.
	var lazy := UtilityBrain.score(Act.WORK, UtilityBrain.make_context(10.0, {"sched_work": 1.0}, {"lazy": 1.0}))
	var keen := UtilityBrain.score(Act.WORK, UtilityBrain.make_context(10.0, {"sched_work": 1.0}, {"lazy": 0.0}))
	assert_float(keen).is_greater(lazy)


func test_commitment_holds_but_urgent_acts_break_it() -> void:
	# A lazy worker at 17:00 with an empty water jar: someone already at the well
	# finishes there instead of dithering off to work.
	var ctx := UtilityBrain.make_context(17.0, {"sched_work": 1.0, "thirst": 1.0}, {"lazy": 0.9})
	var water := UtilityBrain.score(Act.WATER, ctx)
	var work := UtilityBrain.score(Act.WORK, ctx)
	var committed := _name(UtilityBrain.best(ctx, Act.WATER, UtilityBrain.COMMIT_BONUS))
	assert_str(committed).is_equal("water" if water * UtilityBrain.COMMIT_BONUS >= work else _name(UtilityBrain.best(ctx)))
	# Danger is urgent: no commitment holds against it.
	ctx["danger"] = 0.9
	assert_str(_name(UtilityBrain.best(ctx, Act.WATER, UtilityBrain.COMMIT_BONUS))).is_equal("flee")


func test_needs_decay_and_restore() -> void:
	var b := UtilityBrain.new(5, 0)
	b.seed_needs(10.0, 1)
	var food := b.food
	var rest := b.rest
	b.tick(24.0 + 10.0)
	b.tick(24.0 + 12.0)
	assert_float(b.food).is_less(food)
	assert_float(b.rest).is_less(rest)
	var hungry := b.food
	b.tick(24.0 + 12.3, Act.EAT)
	assert_float(b.food).is_greater(hungry)
	# Seeding reflects the clock: tired late at night, rested in the morning.
	b.seed_needs(23.0, 1)
	var late := b.rest
	b.seed_needs(7.5, 1)
	assert_float(b.rest).is_greater(late)


func test_context_follows_schedule_and_career_shift() -> void:
	var b := UtilityBrain.new(9, 2)
	var ctx := b.context(10.0, 1, false, 0.0, 0.0, false, 0.5)
	assert_float(float(ctx["sched_work"])).is_equal(1.0)
	# An innkeeper's shift (11-23) overrides the shared work schedule.
	var keeper := UtilityBrain.new(9, 2, Vector2(11, 23), "inn")
	assert_float(float(keeper.context(10.0, 1, false, 0.0, 0.0, false, 0.5)["sched_work"])).is_equal(0.0)
	assert_float(float(keeper.context(21.0, 0, false, 0.0, 0.0, false, 0.5)["sched_work"])).is_equal(1.0)
	# Rain only exposes outdoor trades.
	var farmer := UtilityBrain.new(9, 0)
	assert_float(float(farmer.context(10.0, 1, true, 0.0, 0.0, false, 0.5)["rain_exposed"])).is_equal(1.0)
	assert_float(float(b.context(10.0, 1, true, 0.0, 0.0, false, 0.5)["rain_exposed"])).is_equal(0.0)


func test_chat_pairs_up_two_people() -> void:
	var a := auto_free(Node3D.new()) as Node3D
	var c := auto_free(Node3D.new()) as Node3D
	UtilityBrain.register_body(900001, a)
	UtilityBrain.register_body(900002, c)
	var first := UtilityBrain.chat_join(0, 900001, Vector2(10, 0))
	assert_int(int(first[1])).is_equal(-1)
	assert_bool(UtilityBrain.chat_waiting(0, 900002)).is_true()
	var second := UtilityBrain.chat_join(0, 900002, Vector2(20, 0))
	assert_int(int(second[1])).is_equal(900001)
	assert_int(UtilityBrain.chat_partner(900001)).is_equal(900002)
	# The joiner stands a conversation's width from the one who waited.
	assert_float((second[0] as Vector2).distance_to(Vector2(10, 0))).is_equal_approx(UtilityBrain.CHAT_GAP, 0.01)
	UtilityBrain.unregister_body(900001)
	assert_int(UtilityBrain.chat_partner(900002)).is_equal(-1)
	UtilityBrain.unregister_body(900002)
