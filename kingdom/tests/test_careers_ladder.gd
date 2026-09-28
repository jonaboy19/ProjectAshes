extends GdUnitTestSuite
## Careers as ladders that accumulate: mastery only grows by doing (and never on
## a career switch), overlaps feed related disciplines, promotion needs real
## requirements, soldier rank caps company size, the biography summarises a
## life, everything round-trips through JSON, and career-born work generates
## deterministically for a seed.

const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


# --- mastery ------------------------------------------------------------------------

func test_mastery_starts_at_one_and_only_grows_by_doing() -> void:
	var m := Mastery.new()
	assert_int(m.level("farming")).is_equal(1)
	assert_int(m.level("soldiering")).is_equal(1)
	m.gain("farming", 1.0, 1)
	assert_int(m.level("soldiering")).is_equal(1)   # untouched disciplines never move


func test_curve_reaches_about_level_fifty_after_ten_years_of_steady_practice() -> void:
	var m := Mastery.new()
	var years := 10
	var days := years * 12   # RALifePath.DAYS_PER_YEAR
	for d in days:
		m.gain("farming", 1.0, d)
	assert_int(m.level("farming")).is_between(40, 55)
	assert_int(m.years_practised("farming")).is_equal(years)


func test_levels_never_exceed_the_cap() -> void:
	var m := Mastery.new()
	for d in 20000:
		m.gain("smithing", 5.0, d)
	assert_int(m.level("smithing")).is_equal(Mastery.MAX_LEVEL)
	assert_str(m.rank_word_for("smithing")).is_equal("Grandmaster")


func test_no_free_experience_on_a_career_switch() -> void:
	# Mastery has no notion of "switching careers" at all: gain() is the only
	# way xp moves, so starting a new biography chapter can't touch it.
	var m := Mastery.new()
	var b := Biography.new()
	m.gain("smithing", 50.0, 1)
	var before := m.level("smithing")
	b.start_chapter("soldier", "guard", "recruit", "Ashford", 2)
	b.start_chapter("farmer", "", "field_hand", "Ashford", 3)
	assert_int(m.level("smithing")).is_equal(before)
	assert_int(m.level("soldiering")).is_equal(1)
	assert_int(m.level("farming")).is_equal(1)


func test_overlaps_feed_related_disciplines() -> void:
	var m := Mastery.new()
	m.gain("hunting", 10.0, 1)
	assert_float(float(m.xp.get("beast_lore", 0.0))).is_equal_approx(3.0, 0.01)     # 30%
	m.gain("soldiering", 10.0, 1)
	assert_float(float(m.xp.get("leadership", 0.0))).is_equal_approx(2.5, 0.01)     # 25%
	m.gain("trading", 10.0, 1)
	assert_float(float(m.xp.get("scholarship", 0.0))).is_equal_approx(1.0, 0.01)    # 10%
	# Overlap credit doesn't count as a day practised in the fed discipline.
	assert_int(m.years_practised("beast_lore")).is_equal(0)


func test_mastery_round_trips() -> void:
	var m := Mastery.new()
	for d in 40:
		m.gain("hunting", 2.0, d)
	var copy := Mastery.new()
	copy.deserialize(_roundtrip(m.serialize()))
	assert_int(copy.level("hunting")).is_equal(m.level("hunting"))
	assert_int(copy.level("beast_lore")).is_equal(m.level("beast_lore"))
	assert_int(copy.years_practised("hunting")).is_equal(m.years_practised("hunting"))


# --- biography ------------------------------------------------------------------------

func test_biography_tracks_chapters_and_reputation_across_switches() -> void:
	var b := Biography.new()
	b.start_chapter("blacksmith", "smithy", "apprentice", "Ashford", 0)
	b.add_highlight("Forged a masterwork sword", 10)
	b.change_rep("craft", 20.0)
	b.start_chapter("soldier", "guard", "recruit", "Ashford", 50)
	assert_float(b.rep("craft")).is_equal(20.0)     # kept across the switch
	assert_int(b.chapters.size()).is_equal(2)
	assert_int(int(b.chapters[0]["end_day"])).is_equal(50)


func test_promote_writes_a_biography_entry() -> void:
	var b := Biography.new()
	b.start_chapter("soldier", "guard", "recruit", "Ashford", 0)
	b.promote("soldier", "soldier", "Sworn Soldier", 30, "guard", "Ashford")
	assert_str(String(b.current_chapter()["rank"])).is_equal("soldier")
	var found := false
	for h: Dictionary in b.current_chapter()["highlights"]:
		if String(h["text"]).contains("Sworn Soldier"):
			found = true
	assert_bool(found).is_true()


func test_biography_summary_has_three_to_six_lines() -> void:
	var b := Biography.new()
	b.start_chapter("farmer", "", "field_hand", "Ashford", 0)
	b.add_highlight("Bought a homestead plot", 20)
	b.change_rep("farming", 25.0)
	b.start_chapter("soldier", "guard", "recruit", "Ashford", 120)
	b.add_highlight("Slew the wolf Ravenmaw", 140)
	var lines := b.summary(200)
	assert_int(lines.size()).is_between(3, 6)
	assert_bool(lines[0].length() > 0).is_true()


func test_biography_round_trips() -> void:
	var b := Biography.new()
	b.start_chapter("merchant", "", "peddler", "Ashford", 0)
	b.add_highlight("Sold a fox pelt", 5)
	b.change_rep("trade", 15.0)
	var copy := Biography.new()
	copy.deserialize(_roundtrip(b.serialize()))
	assert_int(copy.chapters.size()).is_equal(b.chapters.size())
	assert_float(copy.rep("trade")).is_equal(15.0)
	assert_str(String(copy.current_chapter()["role"])).is_equal("merchant")


# --- career ladders ------------------------------------------------------------------

func test_troops_for_rank_grows_with_soldier_rank() -> void:
	assert_int(CareerLadders.troops_for_rank("militia")).is_equal(0)
	assert_int(CareerLadders.troops_for_rank("soldier")).is_equal(5)
	assert_int(CareerLadders.troops_for_rank("squad_leader")).is_equal(20)
	assert_int(CareerLadders.troops_for_rank("captain")).is_equal(60)
	assert_int(CareerLadders.troops_for_rank("general")).is_equal(200)
	assert_int(CareerLadders.troops_for_rank("no_such_rank")).is_equal(0)


func test_ladders_load_and_chain() -> void:
	for career: String in ["farmer", "soldier", "merchant", "blacksmith", "hunter", "healer", "innkeeper", "guard"]:
		var l := CareerLadders.ladder(career)
		assert_array(l).override_failure_message(career).is_not_empty()
	assert_str(CareerLadders.title_for("soldier", "captain")).is_equal("Captain")
	assert_dict(CareerLadders.next_rank_def("soldier", "general")).is_empty()


func test_promotion_reports_missing_requirements() -> void:
	var m := Mastery.new()
	var b := Biography.new()
	var c := RACareers.new()
	c.add_org("guard", "the Ashford Guard", 0, "Captain", Vector3.ZERO, Vector2(7, 19), 3,
		[{"title": "Guard", "wage": 9, "count": 1, "merit": 0}])
	var ctx := {"career": "soldier", "rank": "recruit", "since_day": 0, "day": 5, "mastery": m,
		"biography": b, "careers": c, "gold": 0, "at_war": false, "sponsor_tier": 0}
	var check := CareerLadders.check_promotion(ctx)
	assert_bool(check["eligible"]).is_false()
	assert_bool(Array(check["missing"] as PackedStringArray).any(func(s: String) -> bool: return s.contains("Soldiering"))).is_true()
	assert_bool(Array(check["missing"] as PackedStringArray).any(func(s: String) -> bool: return s.contains("days"))).is_true()
	# Meet every requirement: enough mastery, enough time in rank, an open seat.
	for d in 30:
		m.gain("soldiering", 1.0, d)
	ctx["day"] = 30
	check = CareerLadders.check_promotion(ctx)
	assert_array(Array(check["missing"])).is_empty()
	assert_bool(check["eligible"]).is_true()
	var r := CareerLadders.promote(ctx)
	assert_bool(r["ok"]).is_true()
	assert_str(r["rank"]).is_equal("soldier")
	assert_str(String(b.current_chapter()["rank"])).is_equal("soldier")


func test_promotion_needs_a_sponsor_at_officer_rank() -> void:
	var m := Mastery.new()
	for d in 200:
		m.gain("soldiering", 2.0, d)
		m.gain("leadership", 2.0, d)
		m.gain("command", 2.0, d)
	var b := Biography.new()
	b.change_rep("military", 75.0)
	var ctx := {"career": "soldier", "rank": "commander", "since_day": 0, "day": 200,
		"mastery": m, "biography": b, "gold": 0, "at_war": false, "sponsor_tier": 0}
	var check := CareerLadders.check_promotion(ctx)
	assert_bool(Array(check["missing"] as PackedStringArray).any(func(s: String) -> bool: return s.contains("sponsor"))).is_true()
	ctx["sponsor_tier"] = 4
	check = CareerLadders.check_promotion(ctx)
	assert_array(Array(check["missing"])).is_empty()


func test_wartime_speeds_time_in_rank() -> void:
	var m := Mastery.new()
	for d in 40:
		m.gain("soldiering", 2.0, d)
		m.gain("swordsmanship", 2.0, d)
	var b := Biography.new()
	var ctx := {"career": "soldier", "rank": "soldier", "since_day": 0, "day": 20, "mastery": m,
		"biography": b, "gold": 0, "at_war": false, "sponsor_tier": 0}
	var peacetime := CareerLadders.check_promotion(ctx)
	assert_bool(Array(peacetime["missing"] as PackedStringArray).any(func(s: String) -> bool: return s.contains("days"))).is_true()
	ctx["at_war"] = true
	var wartime := CareerLadders.check_promotion(ctx)
	assert_bool(Array(wartime["missing"] as PackedStringArray).any(func(s: String) -> bool: return s.contains("days"))).is_false()


# --- career-born quests ---------------------------------------------------------------

func _world_for_career(career: String, rank: String) -> Dictionary:
	return {
		"home": Vector2.ZERO,
		"dens": [{"id": 0, "species": "wolf", "pos": Vector2(420, 310), "population": 6, "alive": true}],
		"sites": [{"name": "Cinderpost Waystation", "kind": "waystation", "pos": Vector2(300, -210)}],
		"places": {},
		"career_rank": {"career": career, "rank": rank},
		"days_left_in_season": 15,
	}


func test_career_kinds_only_appear_for_the_matching_career() -> void:
	var soldier_kinds := RadiantQuests.available_kinds(_world_for_career("soldier", "soldier"))
	assert_array(soldier_kinds).contains(["soldier_patrol", "soldier_escort_caravan", "soldier_clear_den", "soldier_night_guard"])
	var farmer_kinds := RadiantQuests.available_kinds(_world_for_career("farmer", "field_hand"))
	assert_array(farmer_kinds).contains(["farmer_deliver_grain"])
	assert_bool(farmer_kinds.has("soldier_patrol")).is_false()
	var no_career := RadiantQuests.available_kinds({"home": Vector2.ZERO, "dens": [], "sites": [], "places": {}})
	for k: String in RadiantQuests.CAREER_KINDS:
		assert_bool(no_career.has(k)).override_failure_message(k).is_false()


func test_career_quest_generation_is_deterministic() -> void:
	var world := _world_for_career("soldier", "soldier")
	var a := RadiantQuests.generate(world, 42, 3, RadiantQuests.available_kinds(world).size())
	var b := RadiantQuests.generate(world, 42, 3, RadiantQuests.available_kinds(world).size())
	assert_str(JSON.stringify(RadiantQuests._enc(a))).is_equal(JSON.stringify(RadiantQuests._enc(b)))
	var kinds := {}
	for q: Dictionary in a:
		kinds[q["kind"]] = true
	assert_bool(kinds.has("soldier_patrol") or kinds.has("soldier_night_guard") or
		kinds.has("soldier_clear_den") or kinds.has("soldier_escort_caravan")).is_true()
