extends GdUnitTestSuite
## Life from birth: ageing, archetypes, titles, hidden triggers, save roundtrip,
## and the cinematic cutscene player.


func _newborn(day := 1) -> RALifePath:
	var lp := RALifePath.new()
	lp.begin(day, 6.0, "Aren", "Hale", [
		{"id": 4, "name": "Edda Hale", "role": "mother"},
		{"id": 9, "name": "Osric Hale", "role": "father"},
	], 0, Vector2(14, 9))
	return lp


# --- ageing -------------------------------------------------------------------

func test_ageing_and_stages() -> void:
	var lp := _newborn(1)
	var y := RALifePath.DAYS_PER_YEAR
	assert_int(lp.age_years(1, 6.0)).is_equal(0)
	assert_int(lp.stage(1)).is_equal(RALifePath.Stage.INFANT)
	assert_int(lp.age_years(1 + y, 5.0)).is_equal(0)   # an hour short of the first birthday
	assert_int(lp.age_years(1 + y, 6.0)).is_equal(1)
	assert_int(lp.age_years(1 + 8 * y, 6.0)).is_equal(8)
	assert_int(lp.stage(1 + 8 * y, 6.0)).is_equal(RALifePath.Stage.CHILD)
	assert_int(lp.stage(1 + 13 * y, 6.0)).is_equal(RALifePath.Stage.YOUTH)
	assert_int(lp.stage(1 + 16 * y, 6.0)).is_equal(RALifePath.Stage.ADULT)
	assert_str(lp.stage_name(1 + 16 * y, 6.0)).is_equal("Adult")
	assert_int(lp.day_of_age(8)).is_equal(1 + 8 * y)


func test_update_emits_birthdays_and_stage_changes() -> void:
	var lp := _newborn(1)
	var ages: Array[int] = []
	var stages: Array[int] = []
	lp.birthday.connect(func(a: int) -> void: ages.append(a))
	lp.stage_changed.connect(func(s: int) -> void: stages.append(s))
	lp.update(1 + 3 * RALifePath.DAYS_PER_YEAR, 7.0)
	assert_array(ages).is_equal([1, 2, 3])
	assert_array(stages).is_equal([RALifePath.Stage.CHILD])


func test_set_age_and_family_bonds() -> void:
	var lp := _newborn(1)
	lp.set_age(8.0, 200, 12.0)
	assert_int(lp.age_years(200, 12.0)).is_equal(8)
	assert_float(lp.bond("mother")).is_equal(RALifePath.BOND_START)
	lp.adjust_bond("mother", 30.0)
	assert_float(lp.bond("mother")).is_equal(90.0)
	lp.adjust_bond("father", 100.0)
	assert_float(lp.bond("father")).is_equal(100.0)
	assert_float(lp.family_bond()).is_equal(95.0)
	assert_str(lp.parent("father")["name"]).is_equal("Osric Hale")
	assert_str(lp.full_name()).is_equal("Aren Hale")


func test_record_accumulates() -> void:
	var lp := _newborn()
	lp.record("hunted")
	lp.record("hunted", 2.5)
	assert_float(lp.count("hunted")).is_equal(3.5)
	assert_int(lp.history.size()).is_equal(2)
	for i in RALifePath.LOG_LIMIT + 10:
		lp.record("studied")
	assert_int(lp.history.size()).is_equal(RALifePath.LOG_LIMIT)
	assert_float(lp.count("studied")).is_equal(float(RALifePath.LOG_LIMIT + 10))


# --- archetypes ---------------------------------------------------------------

func test_empty_life_is_a_villager() -> void:
	var a := RAArchetypes.new()
	assert_str(a.primary({})).is_equal("villager")
	assert_float(a.affinity({}, "villager")).is_equal(1.0)


func test_archetype_follows_actions() -> void:
	var a := RAArchetypes.new()
	var lp := _newborn()
	for i in 20:
		lp.record("hunted")
		lp.record("explored_forest", 0.5)
	assert_str(a.primary(lp.actions)).is_equal("hunter")
	for i in 40:
		lp.record("sneaked")
		lp.record("stole")
	var top := a.leading(lp.actions, {}, 3)
	assert_int(top.size()).is_equal(3)
	var ids: Array = top.map(func(r: Dictionary) -> String: return r["id"])
	assert_array(ids).contains(["assassin", "thief"])
	assert_float(float(top[0]["affinity"])).is_greater(float(top[1]["affinity"]) - 0.0001)
	var sum := 0.0
	var aff := a.affinities(lp.actions)
	for k: String in aff:
		sum += float(aff[k])
	assert_float(sum).is_equal_approx(1.0, 0.0001)


func test_archetype_titles_and_registration() -> void:
	var a := RAArchetypes.new()
	var acts := {"meditated": 2.0}
	assert_str(a.primary(acts, {"spirit_touched": 1})).is_equal("mystic")
	a.register("pirate", "Pirate", {"sailed": 3.0, "stole": 1.0})
	assert_str(a.primary({"sailed": 5.0})).is_equal("pirate")
	assert_str(a.display_name("pirate")).is_equal("Pirate")


# --- titles -------------------------------------------------------------------

func test_titles_earned_by_conditions() -> void:
	var t := RATitles.new()
	var got: Array[String] = []
	t.earned.connect(func(d: Dictionary) -> void: got.append(String(d["id"])))
	var ctx := {"actions": {"hunted": 5.0}, "age": 10, "flags": {}, "stats": {}, "day": 3}
	var new_titles := t.evaluate(ctx)
	assert_array(got).contains(["young_hunter", "first_steps"])
	assert_int(new_titles.size()).is_equal(got.size())
	assert_bool(t.has("young_hunter")).is_true()
	# Evaluating again earns nothing new.
	assert_array(t.evaluate(ctx)).is_empty()
	# Too old for the child-only title.
	var t2 := RATitles.new()
	t2.evaluate({"actions": {"hunted": 5.0}, "age": 14})
	assert_bool(t2.has("young_hunter")).is_false()


func test_hidden_titles_listed_only_when_earned() -> void:
	var t := RATitles.new()
	var ids := func() -> Array: return t.listed().map(func(r: Dictionary) -> String: return r["id"])
	assert_array(ids.call()).contains(["farmhand"])
	assert_array(ids.call()).not_contains(["sticky_fingers", "spirit_touched"])
	# Caught stealing blocks the hidden title.
	t.evaluate({"actions": {"stole": 5.0}, "age": 9, "flags": {"caught_stealing": true}})
	assert_bool(t.has("sticky_fingers")).is_false()
	t.evaluate({"actions": {"stole": 5.0}, "age": 9, "flags": {}})
	assert_bool(t.has("sticky_fingers")).is_true()
	assert_array(ids.call()).contains(["sticky_fingers"])
	# Grant-only titles never come from evaluate(), only grant().
	t.evaluate({"actions": {}, "age": 8})
	assert_bool(t.has("spirit_touched")).is_false()
	assert_str(String(t.grant("spirit_touched", 97).get("name", ""))).is_equal("Spirit-touched")
	assert_dict(t.grant("spirit_touched")).is_empty()
	assert_array(ids.call()).contains(["spirit_touched"])


func test_title_effects_sum() -> void:
	var t := RATitles.new()
	t.grant("farmhand")
	t.grant("spirit_touched")
	var fx := t.effects()
	assert_float(float(fx["stamina_regen"])).is_equal_approx(0.05, 0.0001)
	assert_float(float(fx["magicule_regen"])).is_equal_approx(0.05, 0.0001)
	# Stats conditions.
	t.evaluate({"stats": {"family_bond": 95.0}, "age": 6})
	assert_bool(t.has("beloved_child")).is_true()


# --- hidden triggers ------------------------------------------------------------

func test_triggers_seeded_outside_village() -> void:
	var h := RAHiddenTriggers.new()
	h.seed_first_region(Vector2.ZERO, 60.0)
	assert_int(h.triggers.size()).is_greater_equal(3)
	for t in h.triggers:
		var p: Vector2 = t["pos"]
		assert_float(p.length()).is_greater(60.0 + float(t["radius"]))


func test_trigger_fires_once_at_right_age_and_spot() -> void:
	var h := RAHiddenTriggers.new()
	h.seed_first_region(Vector2.ZERO, 60.0)
	var shrine := h.get_trigger("fallen_shrine")
	var at: Vector2 = shrine["pos"]
	var fired: Array[String] = []
	h.triggered.connect(func(t: Dictionary) -> void: fired.append(String(t["id"])))
	# Wrong spot.
	assert_array(h.check(Vector2.ZERO, 8, 12.0, {})).is_empty()
	# Right spot, wrong age.
	assert_array(h.check(at, 7, 12.0, {})).is_empty()
	assert_array(h.check(at, 9, 12.0, {})).is_empty()
	# Right spot and age.
	var got := h.check(at + Vector2(2, 0), 8, 12.0, {})
	assert_int(got.size()).is_equal(1)
	var g: Dictionary = got[0]["grants"]
	assert_str(String(g["class"])).is_equal("Spirit-touched")
	assert_str(String(g["title"])).is_equal("spirit_touched")
	assert_str(String(g["quest"])).is_equal("q_fallen_shrine")
	assert_array(g["flags"]).contains(["spirit_seen"])
	# One-shot.
	assert_array(h.check(at, 8, 12.0, {})).is_empty()
	assert_array(fired).is_equal(["fallen_shrine"])
	assert_bool(h.has_fired("fallen_shrine")).is_true()


func test_trigger_time_and_flags() -> void:
	var h := RAHiddenTriggers.new()
	h.seed_first_region()
	var pond: Vector2 = h.get_trigger("moonlit_pond")["pos"]
	assert_array(h.check(pond, 7, 14.0, {})).is_empty()        # daytime
	assert_int(h.check(pond, 7, 1.5, {}).size()).is_equal(1)    # after midnight (wrapping window)
	var blind: Vector2 = h.get_trigger("old_hunters_blind")["pos"]
	assert_array(h.check(blind, 11, 9.0, {})).is_empty()        # needs the flag
	assert_int(h.check(blind, 11, 9.0, {"hunted_with_father": true}).size()).is_equal(1)
	var tower: Vector2 = h.get_trigger("burnt_watchtower")["pos"]
	assert_array(h.check(tower, 13, 9.0, {"caught_stealing": true})).is_empty()
	assert_int(h.check(tower, 13, 9.0, {}).size()).is_equal(1)
	assert_bool(RAHiddenTriggers.in_window(23.0, 22.0, 3.0)).is_true()
	assert_bool(RAHiddenTriggers.in_window(3.0, 22.0, 3.0)).is_false()


# --- save ---------------------------------------------------------------------

func test_serialize_roundtrip() -> void:
	var lp := _newborn(5)
	lp.record("hunted", 3.0, 7)
	lp.set_flag("hunted_with_father")
	lp.adjust_bond("mother", 12.0)
	var t := RATitles.new()
	t.grant("keen_eye", 40)
	var h := RAHiddenTriggers.new()
	h.seed_first_region()
	h.check(h.get_trigger("fallen_shrine")["pos"], 8, 10.0, {})

	var blob: Variant = JSON.parse_string(JSON.stringify({
		"life": lp.serialize(), "titles": t.serialize(), "triggers": h.serialize()}))
	var data: Dictionary = blob

	var lp2 := RALifePath.new()
	lp2.deserialize(data["life"])
	assert_str(lp2.full_name()).is_equal("Aren Hale")
	assert_int(lp2.birth_day).is_equal(5)
	assert_float(lp2.count("hunted")).is_equal(3.0)
	assert_bool(lp2.has_flag("hunted_with_father")).is_true()
	assert_float(lp2.bond("mother")).is_equal(72.0)
	assert_str(lp2.parent("mother")["name"]).is_equal("Edda Hale")
	assert_vector(lp2.home_pos).is_equal(Vector2(14, 9))
	assert_int(lp2.history.size()).is_equal(1)
	assert_int(lp2.age_years(5 + 3 * RALifePath.DAYS_PER_YEAR, 6.0)).is_equal(3)

	var t2 := RATitles.new()
	t2.deserialize(data["titles"])
	assert_bool(t2.has("keen_eye")).is_true()
	assert_array(t2.listed().map(func(r: Dictionary) -> String: return r["id"])).contains(["keen_eye"])

	var h2 := RAHiddenTriggers.new()
	h2.seed_first_region()
	h2.deserialize(data["triggers"])
	assert_bool(h2.has_fired("fallen_shrine")).is_true()
	assert_array(h2.check(h2.get_trigger("fallen_shrine")["pos"], 8, 10.0, {})).is_empty()


# --- cinematics ---------------------------------------------------------------

func _flat(_x: float, _z: float) -> float:
	return 2.0


func test_birth_cutscene_builds() -> void:
	var shots := BirthCutscene.build("Aren", "Hale", "Edda", "Osric", Vector2.ZERO, Vector2(14, 9),
		"Ashford", _flat)
	assert_int(shots.size()).is_greater_equal(5)
	var texts := ""
	for s: Dictionary in shots:
		assert_bool(s.has("from")).is_true()
		assert_float(float(s["duration"])).is_greater(0.0)
		texts += String(s.get("text", "")) + String(s.get("speaker", "")) + "\n"
	assert_str(texts).contains("Aren").contains("Edda").contains("Osric")
	# Opens at night, ends at dawn.
	assert_float(float(shots[0]["time"])).is_greater(20.0)
	assert_float(float(shots[shots.size() - 1]["time"])).is_between(5.0, 8.0)
	# Default height source is WorldGen.height; interior shot sits just above the ground there.
	var real := BirthCutscene.build("Aren", "Hale", "Edda", "Osric")
	var h := WorldGen.height(BirthCutscene.DEFAULT_HOUSE.x, BirthCutscene.DEFAULT_HOUSE.y)
	var interior: Vector3 = real[2]["from"]
	assert_float(interior.y - h).is_between(1.0, 2.5)


func test_cutscene_player_finishes_after_durations() -> void:
	var cs: CutscenePlayer = auto_free(CutscenePlayer.new())
	add_child(cs)
	var shots := [
		{"from": Vector3(0, 10, 10), "to": Vector3(0, 5, 5), "look": Vector3.ZERO, "duration": 1.0,
			"text": "Hello", "speaker": "Edda", "fade_in": 0.5},
		{"from": Vector3(0, 3, 3), "look": Vector3(0, 3, 0), "duration": 0.5, "ease": "linear", "fade_out": 0.2},
		{"from": Vector3(0, 50, 0), "look": Vector3(0, 0, 0), "duration": 0.5},   # straight down: no NaN basis
	]
	var done: Array[int] = []
	var started: Array[int] = []
	cs.finished.connect(func() -> void: done.append(1))
	cs.shot_started.connect(func(i: int, _s: Dictionary) -> void: started.append(i))
	cs.play(shots)
	assert_bool(cs.playing).is_true()
	assert_bool(cs.camera.current).is_true()
	assert_float(CutscenePlayer.total_duration(shots)).is_equal_approx(2.0, 0.001)
	var t := 0.0
	while t < 1.9:
		cs.advance(0.1)
		t += 0.1
		assert_bool(cs.camera.transform.origin.is_finite()).is_true()
	assert_array(done).is_empty()
	cs.advance(0.2)
	assert_array(done).is_equal([1])
	assert_array(started).is_equal([0, 1, 2])
	assert_bool(cs.playing).is_false()
	assert_bool(cs.camera.current).is_false()


func test_cutscene_player_skip_restores_camera() -> void:
	var prev: Camera3D = auto_free(Camera3D.new())
	add_child(prev)
	prev.make_current()
	var cs: CutscenePlayer = auto_free(CutscenePlayer.new())
	add_child(cs)
	var skipped: Array[int] = []
	cs.skipped.connect(func() -> void: skipped.append(1))
	cs.play(BirthCutscene.build("Aren", "Hale", "Edda", "Osric", Vector2.ZERO, Vector2(14, 9), "Ashford", _flat))
	assert_bool(cs.camera.current).is_true()
	cs.advance(1.0)
	cs.press_skip()            # first tap only arms
	assert_bool(cs.playing).is_true()
	cs.press_skip()            # second tap skips
	assert_bool(cs.playing).is_false()
	assert_array(skipped).is_equal([1])
	assert_bool(prev.current).is_true()
