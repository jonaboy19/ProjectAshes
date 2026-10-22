extends GdUnitTestSuite
## Region 1 main quest "The Stones Are Dimming" (L14): the data passes the story lint
## (tools_qa/region1/lint_quests.gd, which also autoplays every choice combination it
## samples), the runtime (scripts/region1/story_quest.gd) plays Act I step by step, keeps
## objectives in order, and saves/restores mid-quest.

const Lint := preload("res://tools_qa/region1/lint_quests.gd")
const StoryQuest := preload("res://scripts/region1/story_quest.gd")
const Runner := preload("res://scripts/sim/dialogue_runner.gd")
const State := preload("res://scripts/region1/region1_state.gd")
const MAIN := "res://data/region1/quests/r1_main.json"


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


func _quest() -> Region1StoryQuest:
	var q := StoryQuest.new()
	q.setup(1)
	assert_bool(q.load_quest(MAIN)).is_true()
	return q


func test_lint_passes_with_autoplay() -> void:
	var r := Lint.lint(MAIN)
	assert_array(Array(r["errors"])).is_empty()
	assert_int(int(r["stats"]["steps"])).is_greater_equal(25)
	assert_int(int(r["stats"]["autoplay_failures"])).is_equal(0)
	assert_int(int(r["stats"]["lines_never_shown"])).is_equal(0)


func test_lint_catches_broken_references() -> void:
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAIN))
	var s: Dictionary = q["steps"][1]
	s["giver"] = "nobody"
	s["objectives"].append({"id": "bad", "type": "teleport"})
	s["objectives"].append({"id": "bad2", "type": "carve", "glyph": "smile", "stone": "miller_stone"})
	s["objectives"].append({"id": "bad3", "type": "flag", "flag": "r1.never_set"})
	s["dialogue"].append({"node": "no_such_node"})
	s["tutorial"] = ["juggle"]
	var path := "user://lint_broken_quest.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(q))
	f.close()
	var errs := "\n".join(Lint.lint(path, false, false)["errors"])
	assert_str(errs).contains("unknown giver 'nobody'")
	assert_str(errs).contains("unknown trigger type 'teleport'")
	assert_str(errs).contains("unknown glyph 'smile'")
	assert_str(errs).contains("flag 'r1.never_set' is read")
	assert_str(errs).contains("no_such_node missing")
	assert_str(errs).contains("unknown tutorial prompt 'juggle'")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_every_dialogue_file_is_valid_for_the_runner() -> void:
	for f: String in DirAccess.get_files_at("res://data/region1/dialogue"):
		var d := Runner.load_file(f.get_basename(), "res://data/region1/dialogue")
		assert_bool(d.is_empty()).is_false()
		assert_array(Array(Runner.validate(d))).is_empty()


func test_act_one_plays_in_order() -> void:
	var q := _quest()
	var ctx := {"age": 7, "flags": {}}
	q.refresh(ctx)
	assert_array(Array(q.active_steps())).is_empty()   # nothing before age 8
	ctx["age"] = 8
	q.refresh(ctx)
	assert_array(Array(q.active_steps())).contains_exactly(["a1_dark_stone"])
	assert_str(q.dialogue_entries("a1_dark_stone")[0]["speaker"]).is_equal("mother")
	var ev := q.set_flag("r1.a1.heard", ctx)
	assert_bool(ev.any(func(e: Dictionary) -> bool: return e["type"] == "step_completed")).is_true()
	assert_bool(ev.any(func(e: Dictionary) -> bool:
		return e["type"] == "action" and e["action"] == ["marker", "miller_stone"])).is_true()
	assert_array(Array(q.active_steps())).contains_exactly(["a1_first_glyph"])
	# Idra's conversation only opens once you reach the stone.
	assert_array(q.dialogue_entries("a1_first_glyph")).is_empty()
	q.notify(&"enter_area", {"place": "miller_stone"}, ctx)
	assert_str(q.dialogue_entries("a1_first_glyph")[0]["node"]).is_equal("idra_dark_stone")


func test_objectives_complete_in_order() -> void:
	var q := _quest()
	var ctx := {"age": 8}
	q.refresh(ctx)
	q.set_flag("r1.a1.heard", ctx)
	# Carving before Idra teaches you does not count.
	q.notify(&"enter_area", {"place": "miller_stone"}, ctx)
	q.notify(&"carve", {"glyph": "ward", "stone": "miller_stone"}, ctx)
	assert_bool(q.is_done("a1_first_glyph")).is_false()
	q.set_flag("r1.a1.taught", ctx)
	q.notify(&"carve", {"glyph": "lure", "stone": "miller_stone"}, ctx)   # wrong glyph
	assert_bool(q.is_done("a1_first_glyph")).is_false()
	q.notify(&"carve", {"glyph": "ward", "stone": "miller_stone"}, ctx)
	assert_bool(q.is_done("a1_first_glyph")).is_true()
	assert_bool(q.has_flag("r1.a1.first_glyph")).is_true()


func test_counted_objectives_and_any_branches() -> void:
	var q := _quest()
	var ctx := {"age": 16}
	# Jump to the Scar front by marking earlier steps done.
	for s: Dictionary in q.steps:
		if String(s["id"]) == "a3_scar_front":
			break
		q.status[String(s["id"])] = "done"
	q.refresh(ctx)
	assert_bool(q.is_active("a3_scar_front")).is_true()
	q.set_flag("r1.a3.scar_news", ctx)
	q.notify(&"enter_area", {"place": "greenhollow_south_fields"}, ctx)
	q.set_flag("r1.a3.scar_seen", ctx)
	q.notify(&"scar_harvest", {"place": "greenhollow_south_fields", "amount": 3}, ctx)
	assert_bool(q.has_flag("r1.scar.harvested")).is_false()
	q.notify(&"scar_harvest", {"place": "greenhollow_south_fields", "amount": 2}, ctx)
	assert_bool(q.has_flag("r1.scar.harvested")).is_true()
	assert_bool(q.has_flag("r1.scar.contained")).is_false()


func test_save_and_restore_mid_quest() -> void:
	var q := _quest()
	var ctx := {"age": 8}
	q.refresh(ctx)
	q.set_flag("r1.a1.heard", ctx)
	q.notify(&"enter_area", {"place": "miller_stone"}, ctx)
	State.register_sim(q)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(State.snapshot()))
	var before := q.digest()
	State.clear()
	var r := _quest()
	State.register_sim(r)
	State.restore(snap)
	assert_str(r.digest()).is_equal(before)
	assert_bool(r.is_active("a1_first_glyph")).is_true()
	assert_bool(r.objective_done("a1_first_glyph", "reach")).is_true()
	r.set_flag("r1.a1.taught", ctx)
	r.notify(&"carve", {"glyph": "ward", "stone": "miller_stone"}, ctx)
	assert_bool(r.is_done("a1_first_glyph")).is_true()


func test_ember_choice_sets_the_ember_flag() -> void:
	var q := _quest()
	for s: Dictionary in q.steps:
		if String(s["id"]) == "a4_highwatch":
			break
		q.status[String(s["id"])] = "done"
	var ctx := {"age": 20}
	q.refresh(ctx)
	assert_bool(q.is_active("a4_highwatch")).is_true()
	q.notify(&"enter_area", {"place": "highwatch_keep"}, ctx)
	q.set_flag("r1.a4.gate", ctx)
	q.notify(&"kill", {"target": "rift_wolf", "place": "highwatch_gate", "amount": 6}, ctx)
	q.set_flag("r1.a4.rowan_ember_asked", ctx)
	var ev := q.notify(&"ember_choice", {"who": "rowan", "choice": "stone"}, ctx)
	assert_bool(q.has_flag("ember.rowan.stone")).is_true()
	assert_bool(ev.any(func(e: Dictionary) -> bool:
		return e["type"] == "action" and e["action"] == ["cutscene", "rowan_ember"])).is_true()


# --- story v2: endings, curve, staging -------------------------------------------------

func _play(overrides: Dictionary, run := 0) -> Dictionary:
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAIN))
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(q["registry"])))
	var dialogues := {}
	for f: String in DirAccess.get_files_at("res://data/region1/dialogue"):
		if f.ends_with(".json"):
			dialogues[f.get_basename()] = Runner.load_file(f.get_basename(), "res://data/region1/dialogue")
	var pick := {}
	for g: String in reg["choice_groups"]:
		if not g.begins_with("_"):
			pick[g] = String(reg["choice_groups"][g]["flags"][0])   # the 'giving' option
	for g: String in overrides:
		pick[g] = overrides[g]
	var visited := {}
	var err: String = Lint._play_once(q, reg, dialogues, pick, "blessing:none", visited, {}, run)
	return {"err": err, "visited": visited}


func test_hidden_kindled_ending_when_you_gave_everything() -> void:
	var r := _play({})
	assert_str(r["err"]).is_empty()
	assert_bool(r["visited"].has("r1_act5:kindled_last")).is_true()
	assert_bool(r["visited"].has("r1_act5:bram_last")).is_false()


func test_who_pays_at_the_mouth_follows_earlier_choices() -> void:
	var heir := {"rowan_ember": "ember.rowan.heir"}   # breaks the Kindled Dawn
	var bram := _play(heir.merged({"bram_fate": "r1.bram.spared"}))
	assert_bool(bram["visited"].has("r1_act5:bram_last")).is_true()
	var tamsin := _play(heir.merged({"bram_fate": "r1.bram.chained", "tamsin_fate": "r1.tamsin.pardoned"}))
	assert_bool(tamsin["visited"].has("r1_act5:tamsin_last")).is_true()
	var idra := _play(heir.merged({"bram_fate": "r1.bram.chained", "tamsin_fate": "r1.tamsin.arrested"}))
	assert_bool(idra["visited"].has("r1_act5:idra_last")).is_true()
	var rest := _play({"the_seal": "r1.seal.idra"})
	assert_bool(rest["visited"].has("r1_act5:seal_idra_2")).is_true()
	assert_bool(rest["visited"].has("r1_act5:idra_retire")).is_false()
	for r: Dictionary in [bram, tamsin, idra, rest]:
		assert_str(r["err"]).is_empty()


func test_emotional_curve_swings_full_range() -> void:
	var r := Lint.lint(MAIN, false, false)
	assert_int(int(r["stats"]["curve_min"])).is_equal(-5)
	assert_int(int(r["stats"]["curve_max"])).is_equal(5)
	assert_int(int(r["stats"]["curve_swings"])).is_greater_equal(8)
	assert_str("\n".join(r["warnings"])).not_contains("flat")


func test_lint_checks_staging() -> void:
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAIN))
	q["steps"][0]["staging"] = {"intensity": 9, "music": "kazoo_solo", "needs": ["magic"], "mood": "?"}
	var path := "user://lint_bad_staging.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(q))
	f.close()
	var errs := "\n".join(Lint.lint(path, false, false)["errors"])
	assert_str(errs).contains("intensity must be an integer from -5 to 5")
	assert_str(errs).contains("'kazoo_solo' is not a registry music cue")
	assert_str(errs).contains("staging.needs 'magic'")
	assert_str(errs).contains("unknown staging key 'mood'")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
