extends GdUnitTestSuite
## Tendencies, the childhood event pool and the age-12 Blessing (awakening.gd).

const Tendencies := preload("res://scripts/sim/tendencies.gd")
const ChildhoodEvents := preload("res://scripts/sim/childhood_events.gd")
const Awakening := preload("res://scripts/sim/awakening.gd")


# --- tendencies -----------------------------------------------------------------

func test_tendencies_move_with_record() -> void:
	var t := Tendencies.new()
	var before := t.value("martial")
	t.record("hunted", 1.0)
	assert_float(t.value("martial")).is_greater(before)
	assert_float(t.value("wilderness")).is_greater(0.35)


func test_tendencies_ignore_unmapped_tags() -> void:
	var t := Tendencies.new()
	var snapshot := t.serialize()
	t.record("some_unknown_tag_xyz", 5.0)
	assert_that(t.serialize()).is_equal(snapshot)


func test_tendencies_describe_is_never_numeric() -> void:
	var t := Tendencies.new()
	for i in 30:
		t.record("stole", 1.0)
	var text := t.describe()
	assert_str(text).not_contains("0.")
	assert_str(text).contains("Trouble")


func test_tendencies_roundtrip() -> void:
	var t := Tendencies.new()
	t.record("studied", 4.0)
	t.record("trained_sword", 2.0)
	var data: Variant = JSON.parse_string(JSON.stringify(t.serialize()))
	var t2 := Tendencies.new()
	t2.deserialize(data)
	assert_float(t2.value("scholarship")).is_equal_approx(t.value("scholarship"), 0.001)
	assert_float(t2.value("martial")).is_equal_approx(t.value("martial"), 0.001)


# --- childhood events -------------------------------------------------------------

func _events() -> ChildhoodEvents:
	var e := ChildhoodEvents.new()
	e.load_pool()
	return e


func test_events_pool_has_at_least_forty_split_by_age() -> void:
	var e := _events()
	assert_int(e.pool.size()).is_greater_equal(40)
	var young := 0
	var mid := 0
	for ev: Dictionary in e.pool:
		if int(ev["age_max"]) <= 7:
			young += 1
		elif int(ev["age_min"]) >= 8 and int(ev["age_max"]) <= 11:
			mid += 1
	assert_int(young).is_greater_equal(20)
	assert_int(mid).is_greater_equal(20)


func test_events_are_eligible_only_in_their_age_range() -> void:
	var e := _events()
	var ev := {"id": "t1", "age_min": 8, "age_max": 11, "place": ["any"], "season": ["any"]}
	assert_bool(e.eligible(ev, 7, "settlement", "spring", {})).is_false()
	assert_bool(e.eligible(ev, 8, "settlement", "spring", {})).is_true()
	assert_bool(e.eligible(ev, 11, "settlement", "spring", {})).is_true()
	assert_bool(e.eligible(ev, 12, "settlement", "spring", {})).is_false()


func test_events_respect_place_season_and_flags() -> void:
	var e := _events()
	var ev := {"id": "t2", "age_min": 4, "age_max": 15, "place": ["forest_edge"], "season": ["winter"],
		"flags": ["needed"], "not_flags": ["blocked"]}
	assert_bool(e.eligible(ev, 6, "settlement", "winter", {"needed": true})).is_false()   # wrong place
	assert_bool(e.eligible(ev, 6, "forest_edge", "summer", {"needed": true})).is_false()  # wrong season
	assert_bool(e.eligible(ev, 6, "forest_edge", "winter", {})).is_false()                # missing flag
	assert_bool(e.eligible(ev, 6, "forest_edge", "winter", {"needed": true, "blocked": true})).is_false()
	assert_bool(e.eligible(ev, 6, "forest_edge", "winter", {"needed": true})).is_true()


func test_events_are_one_shot() -> void:
	var e := _events()
	e.seen["fallen_shrine_test"] = true
	var ev := {"id": "fallen_shrine_test", "age_min": 4, "age_max": 15, "place": ["any"], "season": ["any"]}
	assert_bool(e.eligible(ev, 6, "settlement", "spring", {})).is_false()


func test_weighted_pick_is_deterministic_per_seed() -> void:
	var a := _events()
	a.seed_from(1234, "Aren Hale")
	var b := _events()
	b.seed_from(1234, "Aren Hale")
	var seq_a: Array = []
	var seq_b: Array = []
	var day := 0.0
	for i in 8:
		var ev_a := a.roll(6, "home", "spring", {}, day)
		var ev_b := b.roll(6, "home", "spring", {}, day)
		seq_a.append(String(ev_a.get("id", "")))
		seq_b.append(String(ev_b.get("id", "")))
		if not ev_a.is_empty():
			a.mark_seen(String(ev_a["id"]), day)
		if not ev_b.is_empty():
			b.mark_seen(String(ev_b["id"]), day)
		day += 2.5
	assert_array(seq_a).is_equal(seq_b)
	# A different character seed should (almost certainly) diverge somewhere.
	var c := _events()
	c.seed_from(1234, "Ailsa Hale")
	var seq_c: Array = []
	day = 0.0
	for i in 8:
		var ev_c := c.roll(6, "home", "spring", {}, day)
		seq_c.append(String(ev_c.get("id", "")))
		if not ev_c.is_empty():
			c.mark_seen(String(ev_c["id"]), day)
		day += 2.5
	assert_bool(seq_a == seq_c).is_false()


func test_events_gap_rate_is_gentle() -> void:
	var e := _events()
	e.seed_from(1, "Test Child")
	assert_bool(e.due(0.0)).is_true()
	var ev := e.roll(6, "home", "spring", {}, 0.0)
	assert_bool(ev.is_empty()).is_false()
	e.mark_seen(String(ev["id"]), 0.0)
	assert_bool(e.due(0.5)).is_false()
	assert_bool(e.due(3.0)).is_true()


func test_childhood_events_roundtrip() -> void:
	var e := _events()
	e.seed_from(1, "Roundtrip Kid")
	e.mark_seen("some_event", 3.0)
	var data: Variant = JSON.parse_string(JSON.stringify(e.serialize()))
	var e2 := _events()
	e2.deserialize(data)
	assert_bool(e2.has_fired("some_event")).is_true()


# --- awakening / the Blessing ------------------------------------------------------

func test_awakening_result_is_stable_once_rolled() -> void:
	var a := Awakening.new()
	var t := Tendencies.new()
	var r1 := a.roll(t, "caldric", 42, "Rowan Ashdown", 200)
	var r2 := a.roll(t, "caldric", 999, "Someone Else", 999)   # ignored: already rolled
	assert_that(r1).is_equal(r2)
	assert_bool(a.has_happened()).is_true()


func test_awakening_flags_shape() -> void:
	var a := Awakening.new()
	var t := Tendencies.new()
	a.roll(t, "caldric", 7, "Flag Test", 100)
	var f := a.flags()
	if a.none:
		assert_array(f).is_equal(["blessing:none"])
	else:
		assert_bool(f.has("blessing:" + a.element)).is_true()
		assert_bool(f.has("blessing_tier:" + a.tier)).is_true()
		if a.dual != "":
			assert_bool(f.has("blessing_dual")).is_true()


func test_awakening_outcome_distribution() -> void:
	var none_count := 0
	var dual_count := 0
	var n := 1000
	for i in n:
		var a := Awakening.new()
		var t := Tendencies.new()
		a.roll(t, "caldric", 5000 + i, "Child_%d" % i, 100 + i)
		if a.none:
			none_count += 1
		elif a.dual != "":
			dual_count += 1
	var none_rate := float(none_count) / n
	var dual_rate := float(dual_count) / n
	# Design: "none about 6%, dual about 4%" — generous tolerance for 1000 seeded rolls.
	assert_float(none_rate).is_between(0.02, 0.11)
	assert_float(dual_rate).is_between(0.01, 0.09)


func test_awakening_roundtrip() -> void:
	var a := Awakening.new()
	var t := Tendencies.new()
	a.roll(t, "caldric", 11, "Save Test", 50)
	var data: Variant = JSON.parse_string(JSON.stringify(a.serialize()))
	var a2 := Awakening.new()
	a2.deserialize(data)
	assert_bool(a2.has_happened()).is_equal(a.has_happened())
	assert_str(a2.element).is_equal(a.element)
	assert_str(a2.tier).is_equal(a.tier)
	assert_bool(a2.none).is_equal(a.none)


func test_awakening_culture_leans_the_element() -> void:
	# Over many rolls, a Caldric (earth) child should awaken earth more than
	# a Seirune (water) child playing the same tendencies.
	var earth_hits := 0
	var trials := 300
	for i in trials:
		var a := Awakening.new()
		var t := Tendencies.new()
		a.roll(t, "caldric", 9000 + i, "Earth_%d" % i, 100)
		if a.element == "earth":
			earth_hits += 1
	var baseline := float(trials) / Awakening.ELEMENTS.size()
	assert_float(float(earth_hits)).is_greater(baseline)
