extends GdUnitTestSuite
## Life courses (scripts/sim/life_courses.gd): the notable population ages,
## marries, has children, rises and dies deterministically per seed; war
## raises soldier deaths; a dead seat holder's post reopens; news only
## surfaces for people the player knows; and it all round-trips and stays
## fast for a realistic notable population.

const LifeCourses := preload("res://scripts/sim/life_courses.gd")
const YEAR := 12   # RALifePath.DAYS_PER_YEAR


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _lc(seed_value := 1234) -> LifeCourses:
	var lc := LifeCourses.new()
	lc.seed_from(seed_value)
	return lc


# --- determinism ---------------------------------------------------------------

func test_deterministic_yearly_simulation_per_seed() -> void:
	var a := _lc(42)
	a.populate_region(60, 0)
	var b := _lc(42)
	b.populate_region(60, 0)
	var ctx := {"at_war": false, "frontier_threat": 5.0}
	for day in range(0, YEAR * 15, YEAR):
		a.tick_day(day, ctx)
		b.tick_day(day, ctx)
	assert_str(JSON.stringify(_roundtrip(a.serialize()))).is_equal(JSON.stringify(_roundtrip(b.serialize())))
	# A different seed should (almost certainly) diverge somewhere.
	var c := _lc(43)
	c.populate_region(60, 0)
	for day in range(0, YEAR * 15, YEAR):
		c.tick_day(day, ctx)
	assert_bool(JSON.stringify(_roundtrip(a.serialize())) == JSON.stringify(_roundtrip(c.serialize()))).is_false()


# --- aging & death ---------------------------------------------------------------

func test_aging_and_death_by_old_age() -> void:
	var lc := _lc(7)
	var id := lc._new_person("Old Tomas", -60 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	var ctx := {"at_war": false, "frontier_threat": 0.0}
	var died := false
	var death_age := -1
	for years in 60:
		var day := years * YEAR
		lc.tick_day(day, ctx)
		var p := lc.person(id)
		if not bool(p["alive"]):
			died = true
			death_age = lc.age_years(id, day)
			assert_bool(String(p["cause_of_death"]) in ["old_age", "illness"]).is_true()
			break
	assert_bool(died).override_failure_message("expected the person to die of old age within 60 more years").is_true()
	assert_int(death_age).is_greater_equal(60)


# --- marriage --------------------------------------------------------------------

func test_marriage_pairs_only_eligible_adults() -> void:
	var lc := _lc(9)
	var groom := lc._new_person("Groom Adult", -20 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	var child := lc._new_person("Too Young", -10 * YEAR, "female", 0, "caldric", "child", "seeded")
	var bride := lc._new_person("Eligible Bride", -25 * YEAR, "female", 0, "caldric", "farmer", "seeded")
	var day := 20 * YEAR
	var chosen := lc.try_marry(groom, day)
	assert_int(chosen).is_equal(bride)
	assert_int(lc.person(groom)["spouse"]).is_equal(bride)
	assert_int(lc.person(bride)["spouse"]).is_equal(groom)
	assert_int(lc.person(child)["spouse"]).is_equal(-1)


func test_marriage_requires_same_or_nearby_settlement() -> void:
	var lc := _lc(11)
	var far_settlement := WorldGen.settlements.size() - 1
	if far_settlement <= 0:
		return   # a tiny test world with one settlement can't test distance
	var groom := lc._new_person("Local Groom", -20 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	var far_bride := lc._new_person("Far Bride", -22 * YEAR, "female", far_settlement, "caldric", "farmer", "seeded")
	if lc._settlement_near(0, far_settlement):
		return   # world layout happens to put them close; nothing to assert
	var chosen := lc.try_marry(groom, 20 * YEAR)
	assert_int(chosen).is_equal(-1)
	assert_int(lc.person(far_bride)["spouse"]).is_equal(-1)


# --- children ---------------------------------------------------------------------

func test_children_linked_to_parents() -> void:
	var lc := _lc(13)
	var mother := lc._new_person("Mother Hale", -25 * YEAR, "female", 0, "caldric", "farmer", "seeded")
	var father := lc._new_person("Father Hale", -27 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	lc.person(mother)["spouse"] = father
	lc.person(father)["spouse"] = mother
	var day := 25 * YEAR
	var child := lc.have_child(mother, day)
	assert_int(child).is_greater(0)
	var c := lc.person(child)
	assert_array(Array(c["parents"])).contains([mother, father])
	assert_array(Array(lc.person(mother)["children"])).contains([child])
	assert_array(Array(lc.person(father)["children"])).contains([child])
	assert_int(int(c["birth_day"])).is_equal(day)


# --- war -----------------------------------------------------------------------

func test_war_raises_soldier_deaths() -> void:
	var years := 10
	var n := 150
	var peace := _lc(21)
	var war := _lc(21)
	var peace_ids: Array[int] = []
	var war_ids: Array[int] = []
	for i in n:
		var pid := peace._new_person("Soldier P%d" % i, -30 * YEAR, "male", 0, "caldric", "soldier", "seeded")
		peace.person(pid)["rank"] = "soldier"
		peace.person(pid)["_last_age"] = 30
		peace_ids.append(pid)
		var wid := war._new_person("Soldier W%d" % i, -30 * YEAR, "male", 0, "caldric", "soldier", "seeded")
		war.person(wid)["rank"] = "soldier"
		war.person(wid)["_last_age"] = 30
		war_ids.append(wid)
	for y in years:
		var day := (30 + y + 1) * YEAR
		peace.tick_day(day, {"at_war": false, "frontier_threat": 0.0})
		war.tick_day(day, {"at_war": true, "frontier_threat": 0.0})
	var peace_deaths := 0
	for id in peace_ids:
		if not bool(peace.person(id)["alive"]):
			peace_deaths += 1
	var war_deaths := 0
	for id in war_ids:
		if not bool(war.person(id)["alive"]):
			war_deaths += 1
	assert_int(war_deaths).override_failure_message(
		"war deaths %d should exceed peacetime deaths %d" % [war_deaths, peace_deaths]).is_greater(peace_deaths)


# --- careers integration -----------------------------------------------------------

func test_careers_seat_reopens_and_is_refilled_on_death() -> void:
	var lc := _lc(17)
	var careers := RACareers.new()
	careers.add_org("guard", "the Ashford Guard", 0, "Captain", Vector3.ZERO, Vector2(7, 19), 3,
		[{"title": "Guard", "wage": 9, "count": 1, "merit": 0}])
	var pid := lc.ensure_person("Captain Rowe", "guard", 0)
	assert_bool(lc.assign_to_seat(pid, careers, "guard", "Guard")).is_true()
	assert_int(careers.open_count(careers.seat("guard", "Guard"))).is_equal(0)
	lc.kill(pid, 100, "illness", {}, careers, null)
	assert_int(careers.open_count(careers.seat("guard", "Guard"))).is_equal(1)
	assert_dict(careers.holder_of(LifeCourses.careers_holder_id(pid))).is_empty()
	# A vacancy signal hands the seat straight back to a notable.
	lc.on_vacancy(careers.org("guard"), careers.seat("guard", "Guard"), careers)
	assert_int(careers.open_count(careers.seat("guard", "Guard"))).is_equal(0)


# --- news / rumours ---------------------------------------------------------------

func test_news_since_only_surfaces_known_people() -> void:
	var lc := _lc(23)
	lc.populate_region(5, 0)
	var stranger := lc._new_person("A Stranger", -30 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	lc.kill(stranger, 50, "illness", {}, null, null)
	assert_array(lc.news_since(0)).is_empty()
	lc.on_player_met(stranger)
	var news := lc.news_since(0)
	assert_bool(news.size() > 0).is_true()
	assert_bool(news[0].contains("A Stranger")).is_true()
	assert_array(lc.news_since(50)).is_empty()   # exclusive of the cutoff day


func test_ensure_person_and_find_by_name() -> void:
	var lc := _lc(29)
	var id := lc.ensure_person("Tomas Reed", "guard", 0)
	assert_dict(lc.find_by_name("Tomas Reed")).is_not_empty()
	var again := lc.ensure_person("Tomas Reed", "guard", 0)
	assert_int(again).is_equal(id)   # meeting the same name twice doesn't duplicate them
	assert_int(lc.people.size()).is_equal(1)


# --- save / load -------------------------------------------------------------------

func test_life_courses_round_trips() -> void:
	var lc := _lc(31)
	lc.populate_region(20, 0)
	var mother := lc._new_person("Round Mother", -25 * YEAR, "female", 0, "caldric", "farmer", "seeded")
	var father := lc._new_person("Round Father", -27 * YEAR, "male", 0, "caldric", "farmer", "seeded")
	lc.person(mother)["spouse"] = father
	lc.person(father)["spouse"] = mother
	lc.have_child(mother, 25 * YEAR)
	lc.kill(father, 26 * YEAR, "illness", {}, null, null)
	var copy := LifeCourses.new()
	copy.deserialize(_roundtrip(lc.serialize()))
	assert_int(copy.people.size()).is_equal(lc.people.size())
	assert_dict(copy.find_by_name("Round Mother")).is_not_empty()
	assert_bool(bool(copy.find_by_name("Round Father")["alive"])).is_false()
	assert_int(int(copy.find_by_name("Round Mother")["children"].size())).is_equal(1)


# --- performance ---------------------------------------------------------------

func test_simulating_twenty_years_for_three_hundred_people_is_fast() -> void:
	var lc := _lc(99)
	lc.populate_region(300, 0)
	var ctx := {"at_war": false, "frontier_threat": 10.0}
	var start := Time.get_ticks_msec()
	for day in range(0, YEAR * 20, YEAR):
		lc.tick_day(day, ctx)
	var elapsed := Time.get_ticks_msec() - start
	assert_int(elapsed).override_failure_message(
		"20 years for 300 people took %d ms" % elapsed).is_less(500)
