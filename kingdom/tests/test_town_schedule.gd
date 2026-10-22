extends GdUnitTestSuite
## The daily timetable at every simulation level (scripts/population/schedule.gd, town_mood.gd): the original
## three-phase table is intact without flags, rest days / festivals / war / monsters / shortages / mourning / curfew
## bend it, the near AI reads the same table, and other settlements get it as numbers.

const Schedule := preload("res://scripts/population/schedule.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")
const Act := UtilityBrain.Act
const P := Schedule.Phase


func before_test() -> void:
	NpcWorld.reset()
	TownMood.reset()


func after_test() -> void:
	TownMood.reset()


## The original WorldSim._current_phase table.
func _old(job: int, h: float) -> int:
	if h < 6.0 or h >= 21.0:
		return 0
	if job == 3:
		return 1
	if h < 17.0:
		return 2 if (h >= 12.0 and h < 13.0 and job == 4) else 1
	return 2 if h < 19.5 else 0


func _count(job: int, h: float, flags: int, phase: int, n := 60) -> int:
	var c := 0
	for i in n:
		if Schedule.phase(job, h, flags, i, 5) == phase:
			c += 1
	return c


# ---------------------------------------------------------------- tier 1: the rows
func test_without_flags_or_person_the_original_table_is_unchanged() -> void:
	for job in 6:
		for k in 96:
			var h := float(k) * 0.25
			assert_int(Schedule.phase(job, h)).is_equal(_old(job, h))
			assert_int(DailyRhythm.phase_at(job, h)).is_equal(_old(job, h))


func test_every_phase_is_reachable_on_some_day() -> void:
	var seen := {}
	for flags in [0, Schedule.F_REST, Schedule.F_FESTIVAL, Schedule.F_WAR, Schedule.F_SCARCE, Schedule.F_MOURN]:
		for job in 6:
			for k in 48:
				for i in 12:
					seen[Schedule.phase(job, float(k) * 0.5, flags, i, 3)] = true
	for p in 7:
		assert_bool(seen.has(p)).override_failure_message("phase %s never used" % Schedule.NAMES[p]).is_true()


func test_ordinary_evenings_send_some_to_the_inn_and_some_to_temple() -> void:
	assert_int(_count(2, 20.0, 0, P.INN, 100)).is_between(15, 50)
	assert_int(_count(4, 8.8, 0, P.TEMPLE, 100)).is_between(5, 20)
	assert_int(_count(3, 20.0, 0, P.INN, 100)).is_equal(0)          # the watch does not drink on duty


func test_rest_day_empties_the_workplaces_but_not_the_watch() -> void:
	var f := Schedule.F_REST
	assert_int(_count(4, 11.0, f, P.WORK)).is_equal(0)
	assert_int(_count(1, 15.0, f, P.WORK)).is_equal(0)
	assert_int(_count(3, 11.0, f, P.WORK)).is_equal(60)
	assert_int(_count(4, 9.0, f, P.TEMPLE)).is_greater(30)         # the service
	assert_int(_count(4, 11.0, f, P.MARKET)).is_greater(30)        # half-day market
	assert_int(_count(4, 15.0, f, P.SOCIAL)).is_greater(50)
	assert_int(_count(0, 7.0, f, P.WORK)).is_between(20, 40)       # animals still need feeding


func test_festival_fills_the_plaza_and_runs_late() -> void:
	var f := Schedule.F_FESTIVAL
	assert_int(_count(1, 14.0, f, P.SOCIAL)).is_greater(30)
	assert_int(_count(1, 14.0, f, P.WORK)).is_equal(0)
	assert_int(_count(4, 23.0, f, P.SOCIAL) + _count(4, 23.0, f, P.INN)).is_greater(35)
	assert_int(_count(4, 23.0, 0, P.HOME)).is_equal(60)
	assert_int(_count(4, 9.5, f, P.TEMPLE)).is_greater(10)


func test_war_drills_the_guards_and_the_militia() -> void:
	var f := Schedule.F_WAR
	assert_int(_count(3, 15.0, f, P.TRAIN)).is_between(25, 35)
	assert_int(_count(4, 16.0, f, P.TRAIN)).is_between(6, 18)
	assert_int(_count(2, 16.0, f, P.TRAIN)).is_equal(0)             # merchants keep shop
	assert_int(_count(3, 23.0, f, P.WORK)).is_greater(10)           # a night watch
	assert_int(_count(3, 23.0, 0, P.WORK)).is_equal(0)


func test_monsters_empty_fields_and_evening_streets() -> void:
	var f := Schedule.F_MONSTER
	assert_int(_count(0, 16.0, f, P.HOME)).is_equal(60)             # farmers in by mid afternoon
	assert_int(_count(5, 16.0, f, P.HOME)).is_equal(60)
	assert_int(_count(0, 12.0, f, P.WORK)).is_equal(60)             # but a normal morning
	assert_int(_count(4, 18.0, f, P.HOME)).is_equal(60)
	assert_int(_count(4, 20.0, f, P.INN)).is_equal(0)


func test_shortages_form_queues_and_empty_the_inn() -> void:
	var f := Schedule.F_SCARCE
	assert_int(_count(4, 7.5, f, P.MARKET)).is_between(15, 25)      # the bread line
	assert_int(_count(4, 7.5, 0, P.MARKET)).is_equal(0)
	assert_int(_count(4, 18.0, f, P.HOME)).is_greater(25)
	assert_int(_count(2, 20.0, f, P.INN, 200)).is_less(_count(2, 20.0, 0, P.INN, 200))


func test_mourning_sends_half_the_town_to_the_funeral() -> void:
	var f := Schedule.F_MOURN
	assert_int(_count(1, 10.5, f, P.TEMPLE)).is_between(25, 35)
	assert_int(_count(1, 10.5, 0, P.TEMPLE)).is_equal(0)
	assert_int(_count(1, 20.0, f, P.INN, 200)).is_less(_count(1, 20.0, 0, P.INN, 200))


func test_curfew_clears_the_streets_except_the_watch() -> void:
	var f := Schedule.F_CURFEW
	assert_int(_count(4, 20.5, f, P.HOME)).is_equal(60)
	assert_int(_count(4, 20.5, 0, P.HOME)).is_less(60)
	assert_int(_count(4, 20.5, f, P.INN)).is_equal(0)
	assert_int(_count(3, 22.0, f, P.WORK)).is_between(15, 25)


func test_phase_is_deterministic() -> void:
	for i in 40:
		assert_int(Schedule.phase(i % 6, 13.7, 5, i, 9)).is_equal(Schedule.phase(i % 6, 13.7, 5, i, 9))


# ---------------------------------------------------------------- tier 2: other settlements as numbers
func test_other_settlements_get_the_same_table_as_numbers() -> void:
	var m := Schedule.mix("town", 14.0, 0, 3)
	var total := 0.0
	for p in 7:
		total += float(m[p])
	assert_float(total).is_equal_approx(1.0, 0.0001)
	assert_float(float(m[P.WORK])).is_greater(0.5)
	# a rest-day afternoon is on the street, a curfew night is not
	assert_float(Schedule.street_activity("town", 15.0, Schedule.F_REST)).is_greater(Schedule.street_activity("town", 15.0, 0) + 0.2)
	assert_float(Schedule.street_activity("town", 21.0, Schedule.F_CURFEW)).is_less(0.15)
	assert_float(Schedule.street_activity("town", 21.5, Schedule.F_FESTIVAL)).is_greater(Schedule.street_activity("town", 21.5, 0))
	assert_float(Schedule.share("town", 20.0, P.INN, 0, 3)).is_greater(0.05)
	assert_float(Schedule.share("town", 20.0, P.INN, Schedule.F_SCARCE, 3)).is_less(Schedule.share("town", 20.0, P.INN, 0, 3))
	assert_float(Schedule.share("town", 15.0, P.TRAIN, Schedule.F_WAR, 3)).is_greater(Schedule.share("town", 15.0, P.TRAIN, 0, 3))


# ---------------------------------------------------------------- the town's mood
func test_mood_flags_follow_the_numbers() -> void:
	var f := TownMood.flags_from({"rest_day": true, "festival": "harvest", "war": 0.7, "monster": 0.2, "scarcity": 0.5, "mourning": 0.9, "curfew": true})
	assert_int(f & Schedule.F_REST).is_not_equal(0)
	assert_int(f & Schedule.F_FESTIVAL).is_not_equal(0)
	assert_int(f & Schedule.F_WAR).is_not_equal(0)
	assert_int(f & Schedule.F_MONSTER).is_equal(0)
	assert_int(f & Schedule.F_SCARCE).is_not_equal(0)
	assert_int(f & Schedule.F_MOURN).is_not_equal(0)
	assert_int(f & Schedule.F_CURFEW).is_not_equal(0)
	assert_int(TownMood.flags_from({})).is_equal(0)


func test_mood_reads_overrides_and_the_calendar() -> void:
	TownMood.override = {-1: {"war": 1.0, "scarcity": 0.8}}
	var m := TownMood.read(0)
	assert_int(int(m["flags"]) & Schedule.F_WAR).is_not_equal(0)
	assert_int(int(m["flags"]) & Schedule.F_SCARCE).is_not_equal(0)
	TownMood.reset()
	var calm := TownMood.read(0)
	assert_bool(bool(calm["rest_day"])).is_equal(WorldSim.day % 7 == 0)


func test_shortage_meals_get_poorer_and_queues_form_in_the_morning() -> void:
	assert_float(TownMood.meal_quality(0.0)).is_equal(1.0)
	assert_float(TownMood.meal_quality(1.0)).is_less(0.5)
	assert_float(TownMood.meal_quality(0.5)).is_between(TownMood.meal_quality(1.0), 1.0)
	assert_float(TownMood.queue_level(0.8, 7.5)).is_greater(TownMood.queue_level(0.8, 15.0))
	assert_float(TownMood.queue_level(0.0, 7.5)).is_equal(0.0)
	assert_str(TownMood.grumble_category({"scarcity": 0.8})).is_equal("shortage")
	assert_str(TownMood.grumble_category({"war": 0.9})).is_equal("war_talk")
	assert_str(TownMood.grumble_category({"monster": 0.9, "scarcity": 0.9})).is_equal("monster_talk")
	assert_str(TownMood.grumble_category({})).is_equal("")
	for cat in ["shortage", "war_talk", "monster_talk", "mourning", "curfew_talk", "festival_talk", "rest_talk", "queue", "meal_poor"]:
		assert_str(NpcWorld.line(cat, 3)).is_not_empty()


# ---------------------------------------------------------------- tier 0: the near AI reads the same table
func _winner(hour: float, over: Dictionary = {}, traits: Dictionary = {}) -> String:
	return UtilityBrain.NAMES[UtilityBrain.best(UtilityBrain.make_context(hour, over, traits))]


func test_scheduled_drill_makes_guards_train() -> void:
	var over := {"sched_train": 1.0, "sched_work": 0.0, "train": 1.0, "guard": 1.0}
	assert_str(_winner(15.0, over)).is_equal("train")
	assert_str(_winner(15.0, {"sched_train": 1.0, "sched_work": 0.0, "train": 0.0})).is_not_equal("train")   # no yard, no drill
	assert_str(_winner(15.0, {"sched_train": 1.0, "sched_work": 0.0, "train": 1.0, "rain": 1.0})).is_not_equal("train")
	assert_float(UtilityBrain.score(Act.TRAIN, UtilityBrain.make_context(15.0, {"train": 0.0}))).is_equal(0.0)


func test_funeral_pulls_the_devout_and_ignores_the_far() -> void:
	assert_str(_winner(11.0, {"mourn": 0.9, "sched_work": 1.0}, {"pious": 0.8})).is_equal("mourn")
	assert_str(_winner(11.0, {"mourn": 0.0, "sched_work": 1.0})).is_equal("work")
	assert_str(_winner(11.0, {"mourn": 0.9, "danger": 0.9})).is_equal("flee")
	assert_float(UtilityBrain.score(Act.MOURN, UtilityBrain.make_context(11.0, {"mourn": 0.9}, {"pious": 0.9}))).is_greater(
		UtilityBrain.score(Act.MOURN, UtilityBrain.make_context(11.0, {"mourn": 0.9}, {"pious": 0.1})))


func test_festival_day_the_town_celebrates() -> void:
	var over := {"festive": 1.0, "sched_social": 1.0, "sched_work": 0.0, "holiday": 1.0, "lonely": 0.3}
	assert_str(_winner(15.0, over, {"sociable": 0.7})).is_equal("festive")
	assert_str(_winner(15.0, {"festive": 0.0, "sched_work": 0.0})).is_not_equal("festive")
	assert_float(UtilityBrain.score(Act.FESTIVE, UtilityBrain.make_context(15.0, {"festive": 1.0, "sched_social": 1.0}, {"sociable": 0.9}))).is_greater(
		UtilityBrain.score(Act.FESTIVE, UtilityBrain.make_context(15.0, {"festive": 1.0, "sched_social": 0.0}, {"sociable": 0.2})))


func test_shortage_sends_people_to_the_bread_line() -> void:
	var over := {"queue": 1.0, "scarce": 0.8, "sched_work": 0.0, "sched_market": 1.0, "hungry": 0.5}
	assert_str(_winner(7.6, over)).is_equal("queue")
	assert_str(_winner(7.6, {"queue": 0.0, "scarce": 0.8, "sched_work": 0.0})).is_not_equal("queue")
	assert_str(_winner(7.6, {"queue": 1.0, "scarce": 0.0, "sched_work": 0.0})).is_not_equal("queue")


func test_curfew_ends_the_evening_at_the_inn() -> void:
	var over := {"sched_inn": 1.0, "sociable": 0.8, "money": 0.9, "lonely": 0.8}
	assert_str(_winner(20.5, over, {"sociable": 0.8})).is_equal("inn")
	over["curfew"] = 1.0
	assert_str(_winner(20.5, over, {"sociable": 0.8})).is_not_equal("inn")


func test_scheduled_temple_visit_makes_the_faithless_pray() -> void:
	var over := {"sched_temple": 1.0, "sched_work": 0.0, "faithless": 0.6}
	assert_str(_winner(10.0, over, {"pious": 0.1})).is_equal("pray")


func test_rest_day_keeps_a_career_shift_off_the_clock() -> void:
	var b := UtilityBrain.new(1, 1, Vector2(8, 16), "smithy")
	b.inp["holiday"] = 1.0
	var ctx := b.context(11.0, DailyRhythm.State.HOME, false, 0.0, 0.0, false, 0.5, 7)
	assert_float(float(ctx["sched_work"])).is_equal(0.0)
	b.inp["holiday"] = 0.0
	ctx = b.context(11.0, DailyRhythm.State.WORK, false, 0.0, 0.0, false, 0.5, 6)
	assert_float(float(ctx["sched_work"])).is_equal(1.0)
	# the inn's own staff and the watch keep their hours on a holiday
	var keeper := UtilityBrain.new(2, 2, Vector2(10, 23), "inn")
	keeper.inp["holiday"] = 1.0
	assert_float(float(keeper.context(12.0, DailyRhythm.State.WORK, false, 0.0, 0.0, false, 0.5, 7)["sched_work"])).is_equal(1.0)


func test_poorer_meals_restore_less() -> void:
	var full := UtilityBrain.new(5)
	var thin := UtilityBrain.new(6)
	full.food = 0.2
	thin.food = 0.2
	thin.meal_q = TownMood.meal_quality(1.0)
	full.tick(100.0)
	thin.tick(100.0)
	full.tick(100.5, Act.EAT)
	thin.tick(100.5, Act.EAT)
	assert_float(thin.food).is_less(full.food)
	assert_float(thin.food).is_greater(0.2 - 0.001)


func test_new_acts_stay_quiet_without_their_triggers() -> void:
	for hour: float in [3.0, 7.5, 10.0, 12.5, 17.5, 20.0, 23.0]:
		assert_bool(_winner(hour) in ["train", "mourn", "festive", "queue"]).is_false()
