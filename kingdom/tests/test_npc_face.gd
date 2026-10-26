extends GdUnitTestSuite
## Face logic (docs/art/FACES.md): blink, mouth flap, mood targets, mood_for table, card gate, dialogue mood tags.

const FaceState := preload("res://scripts/living_world/face_state.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const HeroFaceDriver := preload("res://scripts/actors/hero_face_driver.gd")


func test_hero_face_setup_reads_quality_while_model_is_off_tree() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Head")
	var driver := HeroFaceDriver.new()
	driver.setup(skeleton, {}, null)
	var quality: Node = get_tree().root.get_node("Quality")
	assert_bool(driver.lids_allowed == (int(quality.get("tier")) >= 1)).is_true()
	driver.free()
	skeleton.free()


func test_blink_happens_and_lids_return() -> void:
	var f := FaceState.new()
	var blinked := false
	var last := {}
	for i in 480:
		last = f.step(1.0 / 60.0)
		if float(last["lids"]) >= 0.99:
			blinked = true
	assert_bool(blinked).is_true()
	# settle: keep stepping until no blink is running, then lids == mood value
	f.set_mood("happy")
	for i in 60:
		last = f.step(1.0 / 60.0)
	var seen_rest := false
	for i in 120:
		last = f.step(1.0 / 60.0)
		if absf(float(last["lids"]) - 0.15) < 0.001:
			seen_rest = true
	assert_bool(seen_rest).is_true()


func test_say_flaps_then_rests() -> void:
	var f := FaceState.new()
	f.say(1.0)
	var mx := 0.0
	for i in 60:
		mx = maxf(mx, float(f.step(1.0 / 60.0)["mouth_open"]))
	assert_float(mx).is_greater(0.3)
	for i in 8:
		f.step(1.0 / 60.0)
	assert_float(float(f.step(1.0 / 60.0)["mouth_open"])).is_equal(0.0)


func test_moods_reach_table() -> void:
	for m in FaceState.MOODS:
		var f := FaceState.new()
		f.set_mood(m)
		var r := {}
		for i in 30:
			r = f.step(1.0 / 60.0)
		var t: Array = FaceState.TABLE[m]
		assert_float(float(r["brow"])).is_equal_approx(float(t[0]), 0.001)
		assert_float(f.lids).is_equal_approx(float(t[1]), 0.001)
		assert_float(float(r["mouth_curve"])).is_equal_approx(float(t[2]), 0.001)
	var u := FaceState.new()
	u.set_mood("bogus")
	assert_str(u.mood).is_equal("neutral")


func test_mood_for_table() -> void:
	var A := UtilityBrain.Act
	assert_str(FaceState.mood_for(A.WORK, {}, 0, "sad")).is_equal("sad")
	assert_str(FaceState.mood_for(A.WORK, {}, 0, "nonsense")).is_equal("neutral")
	assert_str(FaceState.mood_for(A.FLEE, {}, 50, "")).is_equal("fear")
	assert_str(FaceState.mood_for(A.ALARM, {}, 0, "")).is_equal("fear")
	assert_str(FaceState.mood_for(A.MOURN, {}, 0, "")).is_equal("sad")
	assert_str(FaceState.mood_for(A.PROTEST, {}, 0, "")).is_equal("angry")
	assert_str(FaceState.mood_for(A.FESTIVE, {}, 0, "")).is_equal("happy")
	assert_str(FaceState.mood_for(A.INN, {}, 0, "")).is_equal("happy")
	assert_str(FaceState.mood_for(A.WORK, {"mourning": 0.5}, 0, "")).is_equal("sad")
	assert_str(FaceState.mood_for(A.WORK, {"war": 0.6}, 0, "")).is_equal("fear")
	assert_str(FaceState.mood_for(A.WORK, {"monster": 0.5}, 0, "")).is_equal("fear")
	assert_str(FaceState.mood_for(A.WORK, {"curfew": true}, 0, "")).is_equal("fear")
	assert_str(FaceState.mood_for(A.WORK, {"scarcity": 0.6}, 0, "")).is_equal("sad")
	assert_str(FaceState.mood_for(A.WORK, {"festival": "harvest"}, 0, "")).is_equal("happy")
	assert_str(FaceState.mood_for(A.WORK, {}, -10, "")).is_equal("angry")
	assert_str(FaceState.mood_for(A.WORK, {}, 25, "")).is_equal("happy")
	assert_str(FaceState.mood_for(A.WORK, {}, 5, "")).is_equal("neutral")


func test_act_constants_match_utility_brain() -> void:
	var A := UtilityBrain.Act
	assert_int(FaceState.A_INN).is_equal(A.INN)
	assert_int(FaceState.A_FLEE).is_equal(A.FLEE)
	assert_int(FaceState.A_PROTEST).is_equal(A.PROTEST)
	assert_int(FaceState.A_ALARM).is_equal(A.ALARM)
	assert_int(FaceState.A_MOURN).is_equal(A.MOURN)
	assert_int(FaceState.A_FESTIVE).is_equal(A.FESTIVE)


func test_dialogue_mood_tags() -> void:
	var good := {"start": "a", "nodes": {"a": {"lines": [{"text": "hi", "mood": "sad", "hero_mood": "happy"}]}}}
	assert_int(DialogueRunner.validate(good).size()).is_equal(0)
	var line := DialogueRunner.pick_line(good, "a", {}, null)
	assert_str(String(line["mood"])).is_equal("sad")
	assert_str(String(line["hero_mood"])).is_equal("happy")
	var bad := {"start": "a", "nodes": {"a": {"lines": [{"text": "hi", "mood": "x"}]}}}
	assert_int(DialogueRunner.validate(bad).size()).is_equal(1)
	assert_str(DialogueRunner.validate(bad)[0]).contains("bad mood 'x'")


func test_say_seconds_clamped() -> void:
	assert_float(FaceState.say_seconds("")).is_equal(1.2)
	assert_float(FaceState.say_seconds("x".repeat(1000))).is_equal(6.0)


func test_cards_gate() -> void:
	assert_bool(FaceState.cards_enabled(0, "mobile")).is_false()
	assert_bool(FaceState.cards_enabled(1, "gl_compatibility")).is_false()
	assert_bool(FaceState.cards_enabled(1, "mobile")).is_true()
