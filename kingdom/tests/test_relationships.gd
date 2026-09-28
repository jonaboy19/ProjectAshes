extends GdUnitTestSuite
## Opinion modifiers fade, tiers follow opinion and familiarity, parents never
## become enemies, gifts follow career and culture, and it all survives a save.

const Relationships := preload("res://scripts/sim/relationships.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")


func _rel() -> Relationships:
	var r := Relationships.new()
	r.ensure("p1", {"name": "Edda Brook", "role": "farmer", "culture": "caldric"})
	return r


func test_modifier_fades_linearly_and_expires() -> void:
	var r := _rel()
	r.add_modifier("p1", "chores", "Helped with chores", 10.0, 1.0, 30.0)
	assert_int(r.opinion("p1", 1.0)).is_equal(10)
	assert_int(r.opinion("p1", 16.0)).is_equal(5)
	assert_int(r.opinion("p1", 31.0)).is_equal(0)
	assert_bool(r.has_modifier("p1", "chores", 31.0)).is_false()
	r.prune(31.0)
	assert_array(r.npcs["p1"]["mods"]).is_empty()


func test_permanent_modifier_and_replacement() -> void:
	var r := _rel()
	r.add_modifier("p1", "insult", "Insulted", -15.0, 1.0)
	assert_int(r.opinion("p1", 500.0)).is_equal(-15)
	# Same id replaces rather than stacks...
	r.add_modifier("p1", "insult", "Insulted", -15.0, 2.0)
	assert_int(r.opinion("p1", 3.0)).is_equal(-15)
	# ...unless stacking is allowed.
	r.add_modifier("p1", "gift", "Gifts", 5.0, 2.0, 0.0, 3)
	r.add_modifier("p1", "gift", "Gifts", 5.0, 2.0, 0.0, 3)
	assert_int(r.opinion("p1", 3.0)).is_equal(-5)
	r.remove_modifier("p1", "insult")
	assert_int(r.opinion("p1", 3.0)).is_equal(10)


func test_opinion_is_clamped() -> void:
	var r := _rel()
	for i in 5:
		r.add_modifier("p1", "hero%d" % i, "Hero", 40.0, 1.0)
	assert_int(r.opinion("p1", 1.0)).is_equal(100)


func test_tiers() -> void:
	assert_str(Relationships.tier_for(0.0, 0)).is_equal("stranger")
	assert_str(Relationships.tier_for(0.0, 1)).is_equal("acquaintance")
	assert_str(Relationships.tier_for(35.0, 1)).is_equal("friend")
	assert_str(Relationships.tier_for(70.0, 0)).is_equal("close_friend")
	assert_str(Relationships.tier_for(-30.0, 3)).is_equal("rival")
	assert_str(Relationships.tier_for(-80.0, 3)).is_equal("enemy")
	var r := _rel()
	assert_str(r.tier("p1", 1.0)).is_equal("stranger")
	assert_bool(r.note_talk("p1", 1.2)).is_true()
	assert_bool(r.note_talk("p1", 1.5)).is_false()     # second talk the same day
	assert_str(r.tier("p1", 1.5)).is_equal("acquaintance")
	r.add_modifier("p1", "saved", "Saved my life", 70.0, 1.5)
	assert_str(r.tier("p1", 1.5)).is_equal("close_friend")
	assert_int(Relationships.tier_rank("close_friend")).is_greater(Relationships.tier_rank("acquaintance"))


func test_parents_never_become_enemies() -> void:
	var r := Relationships.new()
	r.set_bond("mum", "mother", 60.0)
	assert_str(r.bond("mum")).is_equal("mother")
	assert_int(r.opinion("mum", 1.0)).is_equal(60)
	r.add_modifier("mum", "awful", "Burnt the house down", -200.0, 1.0)
	assert_int(r.opinion("mum", 1.0)).is_equal(Relationships.PARENT_FLOOR)
	assert_str(r.tier("mum", 1.0)).is_not_equal("enemy")
	assert_str(r.tier_label("mum", 1.0)).contains("Mother")


func test_faction_standing_colours_opinion() -> void:
	var r := _rel()
	r.ensure("p1", {"faction": "ashford"})
	var before := r.opinion("p1", 1.0)
	r.change_rep("ashford", 50.0)
	assert_int(r.opinion("p1", 1.0)).is_equal(before + 10)
	assert_str(r.standing("mossfang")).is_equal("Hostile")
	r.add_sects({"royal_ember_academy": {"name": "Royal Ember Academy"}})
	assert_str(r.faction_name("royal_ember_academy")).is_equal("Royal Ember Academy")
	assert_float(r.change_rep("royal_ember_academy", 500.0)).is_equal(100.0)


func test_gifts_follow_career_and_culture() -> void:
	var farmer := Relationships.gift_prefs("farmer", "caldric")
	assert_array(farmer["loves"]).contains(["cheese"])
	assert_array(farmer["dislikes"]).contains(["wolf_meat"])
	var orc_healer := Relationships.gift_prefs("healer", "urrokai")
	assert_array(orc_healer["loves"]).contains(["healing_herb", "pork"])
	var r := _rel()
	var g := r.give_gift("p1", "cheese", 2.0)
	assert_bool(g["ok"]).is_true()
	assert_str(g["reaction"]).is_equal("loves")
	assert_bool(r.give_gift("p1", "apple", 2.5)["ok"]).is_false()   # one gift a day
	assert_str(r.known_reaction("p1", "cheese")).is_equal("loves")
	var repeat := r.give_gift("p1", "cheese", 3.0)
	assert_int(repeat["delta"]).is_less(int(g["delta"]))              # same item within a week counts half
	assert_int(r.give_gift("p1", "wolf_meat", 4.0)["delta"]).is_less(0)


func test_serialise_roundtrip_through_json() -> void:
	var r := _rel()
	r.set_bond("mum", "mother", 72.0)
	r.add_modifier("p1", "chores", "Helped with chores", 10.0, 1.0, 30.0)
	r.note_talk("p1", 1.0)
	r.give_gift("p1", "bread", 1.0)
	r.change_rep("tuskridge", 12.0)
	var copy := Relationships.new()
	copy.deserialize(JSON.parse_string(JSON.stringify(r.serialize())))
	for t: float in [1.0, 5.5, 20.0, 40.0]:
		assert_int(copy.opinion("p1", t)).is_equal(r.opinion("p1", t))
		assert_str(copy.tier("p1", t)).is_equal(r.tier("p1", t))
	assert_int(copy.opinion("mum", 1.0)).is_equal(72)
	assert_float(copy.rep("tuskridge")).is_equal(r.rep("tuskridge"))
	assert_str(copy.known_reaction("p1", "bread")).is_equal(r.known_reaction("p1", "bread"))
	assert_bool(copy.gifted_today("p1", 1.4)).is_true()


func test_dialogue_files_are_sound() -> void:
	DialogueRunner.clear_cache()
	for f: String in ["villager", "parents", "guild", "innkeeper"]:
		var d := DialogueRunner.load_file(f)
		assert_bool(d.is_empty()).override_failure_message("%s.json missing or invalid" % f).is_false()
		assert_array(DialogueRunner.validate(d)).override_failure_message(f).is_empty()
	var gossip := DialogueRunner.load_file("gossip")
	assert_bool((gossip.get("hints", {}) as Dictionary).has("fallen_shrine")).is_true()


func test_greeting_varies_by_tier_time_and_age() -> void:
	var d := DialogueRunner.load_file("villager")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var base := {"first": "Edda", "player": "Ren", "kid": "friend", "greeting": "Hearth keep you.", "reply": "And stone guard you."}
	var enemy := base.merged({"tier": "enemy", "time": "morning", "child": false})
	assert_str(DialogueRunner.pick_line(d, "greet", enemy, rng)["text"]).contains("says nothing")
	var night_child := base.merged({"tier": "acquaintance", "time": "night", "child": true, "kid": "little one"})
	assert_str(DialogueRunner.pick_line(d, "greet", night_child, rng)["text"]).contains("bedtime")
	var helped := base.merged({"tier": "friend", "time": "afternoon", "child": false, "events": ["helped_recently"]})
	assert_str(DialogueRunner.pick_line(d, "greet", helped, rng)["text"]).contains("helper")
	var opts := DialogueRunner.choices(d, "greet", base.merged({"tier": "enemy"}))
	for o: Dictionary in opts:
		assert_str(o["goto"]).is_not_equal("gossip")
