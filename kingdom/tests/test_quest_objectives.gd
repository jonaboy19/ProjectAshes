extends GdUnitTestSuite
## F7: the generic quest objective library (scripts/quests): every objective type, stage composition,
## Choose branches, saving mid-quest, the Thornfield quest line, and the adapters for radiant and story quests.

const Objectives := preload("res://scripts/quests/quest_objectives.gd")
const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")
const RadiantAdapter := preload("res://scripts/quests/radiant_adapter.gd")
const QuestRewards := preload("res://scripts/quests/quest_rewards.gd")
const Journal := preload("res://scripts/quests/quest_journal.gd")
const Talk := preload("res://scripts/quests/quest_talk.gd")
const Observe := preload("res://scripts/quests/objectives/observe.gd")
const StoryQuest := preload("res://scripts/region1/story_quest.gd")
const THORNFIELD := "res://data/quests/thornfield"

var paid: Array = []


func _obj(d: Dictionary) -> RefCounted:
	return Objectives.create(d)


func _feed(o: RefCounted, t: String, ev: Dictionary = {}) -> void:
	o.on_event(StringName(t), ev)


static func _json_round(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _runner(defs: Array) -> QuestRunner:
	var r := QuestRunner.new(QuestBus.new())
	r.reward_fn = func(rw: Dictionary) -> String:
		paid.append(rw)
		return "paid"
	for d: Dictionary in defs:
		r.add_def(QuestDef.from_dict(d))
	return r


func before_test() -> void:
	paid.clear()


# --- every objective type ---------------------------------------------------------------

func test_library_has_all_eleven_types() -> void:
	for t: String in ["goto", "talk_to", "kill", "collect", "deliver", "escort", "protect", "investigate", "wait", "observe", "choose"]:
		assert_bool(Objectives.has_type(t)).override_failure_message(t).is_true()
	assert_int(Objectives.type_names().size()).is_equal(11)
	assert_object(_obj({"type": "nonsense"})).is_null()


func test_goto_by_place_and_by_position() -> void:
	var o := _obj({"id": "g", "type": "goto", "place": "thornfield_mill"})
	_feed(o, "enter_area", {"place": "somewhere_else"})
	assert_bool(o.is_done()).is_false()
	_feed(o, "enter_area", {"place": "Thornfield_Mill"})
	assert_bool(o.is_done()).is_true()
	assert_float(o.progress()).is_equal(1.0)
	var p := _obj({"id": "p", "type": "goto", "pos": [100, 50], "radius": 10})
	_feed(p, "position", {"x": 130.0, "y": 50.0})
	assert_bool(p.is_done()).is_false()
	_feed(p, "position", {"x": 104.0, "y": 52.0})
	assert_bool(p.is_done()).is_true()
	assert_str(o.describe()).contains("thornfield mill").contains("done")


func test_talk_to() -> void:
	var o := _obj({"id": "t", "type": "talk_to", "npc": "hesta_thorne"})
	_feed(o, "talk", {"npc": "wilm_garrow"})
	assert_bool(o.is_done()).is_false()
	_feed(o, "talk", {"npc": "hesta_thorne", "node": "x"})
	assert_bool(o.is_done()).is_true()
	var n := _obj({"id": "n", "type": "talk_to", "node": "a1_first_glyph"})   # a story talk event
	_feed(n, "talk", {"node": "a1_first_glyph"})
	assert_bool(n.is_done()).is_true()


func test_kill_counts_and_filters() -> void:
	var o := _obj({"id": "k", "type": "kill", "target": "wolf", "count": 3})
	_feed(o, "kill", {"target": "boar"})
	assert_float(o.progress()).is_equal(0.0)
	_feed(o, "kill", {"target": "wolf", "amount": 1})
	assert_float(o.progress()).is_equal_approx(1.0 / 3.0, 0.001)
	assert_str(o.describe()).contains("1/3")
	_feed(o, "kill", {"target": "wolf", "amount": 2})
	assert_bool(o.is_done()).is_true()
	assert_bool(o.is_failed()).is_false()


func test_collect_by_events_and_by_inventory() -> void:
	var o := _obj({"id": "c", "type": "collect", "item": "barley", "count": 4})
	_feed(o, "item", {"item": "barley", "amount": 3})
	_feed(o, "item", {"item": "wheat", "amount": 9})
	assert_float(o.progress()).is_equal(0.75)
	_feed(o, "item", {"item": "barley", "amount": 1})
	assert_bool(o.is_done()).is_true()
	var inv := _obj({"id": "c2", "type": "collect", "item": "healing_herb", "count": 3})
	_feed(inv, "inventory", {"counts": {"healing_herb": 2}})
	assert_bool(inv.is_done()).is_false()
	_feed(inv, "inventory", {"counts": {"healing_herb": 3}})
	assert_bool(inv.is_done()).is_true()


func test_deliver() -> void:
	var o := _obj({"id": "d", "type": "deliver", "item": "barley", "count": 2, "to": "thornfield_miller"})
	_feed(o, "deliver", {"item": "barley", "to": "someone_else", "amount": 2})
	assert_bool(o.is_done()).is_false()
	_feed(o, "deliver", {"item": "barley", "to": "thornfield_miller", "amount": 1})
	assert_bool(o.is_done()).is_false()
	_feed(o, "deliver", {"item": "barley", "to": "thornfield_miller", "amount": 1})
	assert_bool(o.is_done()).is_true()


func test_escort_arrives_or_fails_when_the_target_dies() -> void:
	var ok := _obj({"id": "e", "type": "escort", "actor": "cart", "place": "mill"})
	_feed(ok, "arrive", {"actor": "other_cart", "place": "mill"})
	assert_bool(ok.is_done()).is_false()
	_feed(ok, "arrive", {"actor": "cart", "place": "mill"})
	assert_bool(ok.is_done()).is_true()
	var bad := _obj({"id": "e2", "type": "escort", "actor": "cart", "place": "mill"})
	_feed(bad, "died", {"actor": "cart"})
	assert_bool(bad.is_failed()).is_true()
	assert_bool(bad.is_done()).is_false()
	_feed(bad, "arrive", {"actor": "cart", "place": "mill"})     # too late
	assert_bool(bad.is_done()).is_false()
	var by_pos := _obj({"id": "e3", "type": "escort", "actor": "cart", "pos": [10, 10], "radius": 5})
	_feed(by_pos, "actor_pos", {"actor": "cart", "x": 12.0, "y": 11.0})
	assert_bool(by_pos.is_done()).is_true()


func test_protect_by_hours_until_event_and_failure() -> void:
	var o := _obj({"id": "p", "type": "protect", "actor": "cart", "hours": 2})
	_feed(o, "hours", {"amount": 1.0})
	assert_float(o.progress()).is_equal(0.5)
	_feed(o, "hours", {"amount": 1.0})
	assert_bool(o.is_done()).is_true()
	var u := _obj({"id": "p2", "type": "protect", "actor": "cart", "until": {"type": "clear", "place": "fields"}})
	_feed(u, "hours", {"amount": 5.0})
	assert_bool(u.is_done()).is_false()
	_feed(u, "clear", {"place": "elsewhere"})
	assert_bool(u.is_done()).is_false()
	_feed(u, "clear", {"place": "fields"})
	assert_bool(u.is_done()).is_true()
	var f := _obj({"id": "p3", "type": "protect", "actor": "cart", "hours": 2})
	_feed(f, "hours", {"amount": 1.0})
	_feed(f, "died", {"actor": "cart"})
	assert_bool(f.is_failed()).is_true()
	_feed(f, "hours", {"amount": 5.0})
	assert_bool(f.is_done()).is_false()


func test_investigate_counts_distinct_clues() -> void:
	var o := _obj({"id": "i", "type": "investigate", "clues": ["a/1", "a/2", "a/3", "a/4"], "count": 3})
	_feed(o, "interact", {"id": "a/1"})
	_feed(o, "interact", {"id": "a/1"})          # the same clue twice is still one
	_feed(o, "interact", {"id": "not/a/clue"})
	assert_float(o.have).is_equal(1.0)
	_feed(o, "interact", {"id": "a/3"})
	assert_bool(o.is_done()).is_false()
	assert_str(o.describe()).contains("2/3")
	_feed(o, "interact", {"id": "a/4"})
	assert_bool(o.is_done()).is_true()
	var pre := _obj({"id": "i2", "type": "investigate", "clues": ["x/*"], "count": 1})
	_feed(pre, "interact", {"id": "x/anything"})
	assert_bool(pre.is_done()).is_true()


func test_wait_uses_world_hours_and_window() -> void:
	var o := _obj({"id": "w", "type": "wait", "hours": 3})
	for i in 3:
		_feed(o, "hours", {"amount": 1.0, "hour": 10.0 + i})
	assert_bool(o.is_done()).is_true()
	var night := _obj({"id": "w2", "type": "wait", "hours": 2, "window": [21, 5]})
	_feed(night, "hours", {"amount": 1.0, "hour": 14.0})     # daytime hours do not count
	assert_float(night.have).is_equal(0.0)
	_feed(night, "hours", {"amount": 1.0, "hour": 23.0})
	_feed(night, "hours", {"amount": 1.0, "hour": 2.0})      # the window wraps midnight
	assert_bool(night.is_done()).is_true()


func test_observe_needs_range_and_being_unseen() -> void:
	var o := _obj({"id": "o", "type": "observe", "target": "figure", "range": 15, "seconds": 10})
	_feed(o, "observe", {"target": "figure", "dist": 30.0, "unseen": true, "dt": 5.0})      # too far
	assert_float(o.have).is_equal(0.0)
	_feed(o, "observe", {"target": "figure", "dist": 10.0, "unseen": true, "dt": 6.0})
	assert_float(o.progress()).is_equal_approx(0.6, 0.001)
	_feed(o, "observe", {"target": "figure", "dist": 10.0, "unseen": false, "dt": 0.5})     # spotted: starts over
	assert_float(o.have).is_equal(0.0)
	_feed(o, "observe", {"target": "figure", "dist": 10.0, "unseen": true, "dt": 10.0})
	assert_bool(o.is_done()).is_true()
	var forgiving := _obj({"id": "o2", "type": "observe", "target": "figure", "seconds": 4, "reset_on_seen": false})
	_feed(forgiving, "observe", {"target": "figure", "dist": 5.0, "unseen": true, "dt": 2.0})
	_feed(forgiving, "observe", {"target": "figure", "dist": 5.0, "unseen": false, "dt": 0.5})
	assert_float(forgiving.have).is_equal(2.0)
	var night := _obj({"id": "o3", "type": "observe", "target": "figure", "seconds": 2, "window": [21, 5]})
	_feed(night, "observe", {"target": "figure", "dist": 5.0, "unseen": true, "dt": 5.0, "hour": 13.0})
	assert_bool(night.is_done()).is_false()
	_feed(night, "observe", {"target": "figure", "dist": 5.0, "unseen": true, "dt": 5.0, "hour": 23.0})
	assert_bool(night.is_done()).is_true()


func test_observe_unseen_uses_perception() -> void:
	# Behind the watcher, or far away in the dark, the player is unseen; in front and close in daylight, seen.
	assert_bool(Observe.is_unseen(Vector2.ZERO, Vector2(1, 0), Vector2(-8, 0), 1.0)).is_true()
	assert_bool(Observe.is_unseen(Vector2.ZERO, Vector2(1, 0), Vector2(6, 0), 1.0)).is_false()
	assert_bool(Observe.is_unseen(Vector2.ZERO, Vector2(1, 0), Vector2(300, 0), 0.0)).is_true()


func test_choose_records_the_option() -> void:
	var o := _obj({"id": "ch", "type": "choose", "options": [{"id": "a", "text": "Do A"}, {"id": "b", "text": "Do B"}]})
	_feed(o, "choose", {"choice": "other", "option": "a"})
	assert_bool(o.is_done()).is_false()
	_feed(o, "choose", {"choice": "ch", "option": "zzz"})
	assert_bool(o.is_done()).is_false()
	_feed(o, "choose", {"choice": "ch", "option": "b"})
	assert_bool(o.is_done()).is_true()
	assert_str(o.chosen).is_equal("b")
	assert_str(o.describe()).contains("Do A").contains("Do B")


func test_every_type_saves_and_restores_through_json() -> void:
	var samples := [
		{"id": "a", "type": "goto", "place": "x"}, {"id": "b", "type": "talk_to", "npc": "n"},
		{"id": "c", "type": "kill", "target": "wolf", "count": 3}, {"id": "d", "type": "collect", "item": "barley", "count": 4},
		{"id": "e", "type": "deliver", "item": "barley", "to": "m"}, {"id": "f", "type": "escort", "actor": "cart", "place": "mill"},
		{"id": "g", "type": "protect", "actor": "cart", "hours": 3}, {"id": "h", "type": "investigate", "clues": ["a", "b", "c"], "count": 3},
		{"id": "i", "type": "wait", "hours": 4}, {"id": "j", "type": "observe", "target": "f", "seconds": 8},
		{"id": "k", "type": "choose", "options": [{"id": "a", "text": "A"}]}]
	for d: Dictionary in samples:
		var o := _obj(d)
		_feed(o, "kill", {"target": "wolf"})
		_feed(o, "item", {"item": "barley", "amount": 2})
		_feed(o, "hours", {"amount": 1.0, "hour": 12.0})
		_feed(o, "interact", {"id": "a"})
		_feed(o, "observe", {"target": "f", "dist": 1.0, "unseen": true, "dt": 3.0})
		var back := Objectives.from_save(_json_round(o.save()))
		assert_object(back).is_not_null()
		assert_str(back.type).is_equal(o.type)
		assert_float(back.have).is_equal(o.have)
		assert_float(back.progress()).is_equal_approx(o.progress(), 0.0001)
		assert_str(back.describe()).is_equal(o.describe())
		assert_str(o.describe()).is_not_empty()


# --- composition ---------------------------------------------------------------------------

func _stage_quest(mode: String) -> Dictionary:
	return {"id": "q_" + mode, "title": "T", "stages": [{"id": "s1", "mode": mode, "objectives": [
		{"id": "a", "type": "kill", "target": "wolf", "count": 1},
		{"id": "b", "type": "talk_to", "npc": "hesta"},
		{"id": "c", "type": "goto", "place": "mill"}]}], "rewards": {"gold": 5}}


func test_all_needs_every_objective_in_any_order() -> void:
	var r := _runner([_stage_quest("all")])
	assert_str(r.start("q_all")).is_empty()
	r.notify(&"talk", {"npc": "hesta"})
	r.notify(&"enter_area", {"place": "mill"})
	assert_bool(r.is_active("q_all")).is_true()
	r.notify(&"kill", {"target": "wolf"})
	assert_bool(r.is_done("q_all")).is_true()
	assert_int(paid.size()).is_equal(1)


func test_any_needs_one() -> void:
	var r := _runner([_stage_quest("any")])
	r.start("q_any")
	r.notify(&"enter_area", {"place": "mill"})
	assert_bool(r.is_done("q_any")).is_true()


func test_any_fails_only_when_every_objective_failed() -> void:
	var r := _runner([{"id": "q", "title": "T", "stages": [{"id": "s", "mode": "any", "objectives": [
		{"id": "a", "type": "escort", "actor": "c1", "place": "m"}, {"id": "b", "type": "escort", "actor": "c2", "place": "m"}]}]}])
	r.start("q")
	r.notify(&"died", {"actor": "c1"})
	assert_bool(r.is_active("q")).is_true()
	r.notify(&"died", {"actor": "c2"})
	assert_bool(r.is_failed("q")).is_true()


func test_sequence_only_listens_to_the_first_open_objective() -> void:
	var r := _runner([_stage_quest("sequence")])
	r.start("q_sequence")
	r.notify(&"enter_area", {"place": "mill"})        # third objective: ignored for now
	r.notify(&"talk", {"npc": "hesta"})               # second: ignored
	r.notify(&"kill", {"target": "wolf"})             # first: done
	assert_bool(r.is_active("q_sequence")).is_true()
	assert_bool(r.objectives_of("q_sequence")[1].is_done()).is_false()
	r.notify(&"talk", {"npc": "hesta"})
	r.notify(&"enter_area", {"place": "mill"})
	assert_bool(r.is_done("q_sequence")).is_true()


func test_a_failed_objective_fails_the_quest_and_pays_the_penalty() -> void:
	var r := _runner([{"id": "q", "title": "T", "on_fail": {"rep": {"thornfield": -3}}, "stages": [{"id": "s", "mode": "all", "objectives": [
		{"id": "a", "type": "protect", "actor": "cart", "hours": 2}]}]}])
	r.start("q")
	r.notify(&"died", {"actor": "cart"})
	assert_bool(r.is_failed("q")).is_true()
	assert_int(paid.size()).is_equal(1)
	assert_str(r.start("q")).is_empty()      # a failed quest can be taken up again
	assert_bool(r.is_active("q")).is_true()


func test_optional_objectives_do_not_block_a_stage() -> void:
	var r := _runner([{"id": "q", "title": "T", "stages": [{"id": "s", "mode": "all", "objectives": [
		{"id": "a", "type": "goto", "place": "x"}, {"id": "b", "type": "kill", "target": "wolf", "optional": true}]}]}])
	r.start("q")
	r.notify(&"enter_area", {"place": "x"})
	assert_bool(r.is_done("q")).is_true()


func test_requires_gates_a_quest() -> void:
	var r := _runner([{"id": "first", "title": "F", "stages": [{"id": "s", "objectives": [{"id": "a", "type": "goto", "place": "x"}]}]},
		{"id": "second", "title": "S", "requires": ["first"], "stages": [{"id": "s", "objectives": [{"id": "a", "type": "goto", "place": "y"}]}]}])
	assert_str(r.can_start("second")).is_not_empty()
	r.start("first")
	r.notify(&"enter_area", {"place": "x"})
	assert_str(r.can_start("second")).is_empty()


# --- Choose branches --------------------------------------------------------------------------

func _branch_quest() -> Dictionary:
	return {"id": "bq", "title": "Branches", "stages": [
		{"id": "pick", "title": "Pick", "objectives": [{"id": "which", "type": "choose",
			"options": [{"id": "left", "text": "Left"}, {"id": "right", "text": "Right"}]}], "branches": {"left": "go_left", "right": "go_right"}},
		{"id": "go_left", "title": "Left road", "end": true, "objectives": [{"id": "l", "type": "goto", "place": "left_place"}], "rewards": {"gold": 1}},
		{"id": "go_right", "title": "Right road", "end": true, "objectives": [{"id": "rr", "type": "goto", "place": "right_place"}], "rewards": {"gold": 2}}]}


func test_choose_branches_into_different_stages() -> void:
	for side: String in ["left", "right"]:
		var r := _runner([_branch_quest()])
		paid.clear()
		r.start("bq")
		assert_str(r.stage_of("bq")).is_equal("pick")
		assert_int(r.pending_choices("bq").size()).is_equal(1)
		r.notify(&"choose", {"choice": "which", "option": side})
		assert_str(r.stage_of("bq")).is_equal("go_" + side)
		r.notify(&"enter_area", {"place": ("left_place" if side == "right" else "right_place")})   # the wrong road does nothing
		assert_bool(r.is_active("bq")).is_true()
		r.notify(&"enter_area", {"place": side + "_place"})
		assert_bool(r.is_done("bq")).is_true()
		assert_int(int((paid[paid.size() - 1] as Dictionary)["gold"])).is_equal(1 if side == "left" else 2)


func test_definitions_validate() -> void:
	assert_array(QuestDef.from_dict(_branch_quest()).validate()).is_empty()
	var bad := QuestDef.from_dict({"id": "x", "stages": [{"id": "s", "objectives": [{"id": "a", "type": "teleport"}], "branches": {"zz": "nowhere"}}]})
	assert_int(bad.validate().size()).is_greater_equal(2)


# --- saving ----------------------------------------------------------------------------------

func test_save_round_trip_mid_quest() -> void:
	var defs := [_branch_quest(), _stage_quest("sequence")]
	var a := _runner(defs)
	a.start("bq")
	a.start("q_sequence")
	a.notify(&"choose", {"choice": "which", "option": "right"})
	a.notify(&"kill", {"target": "wolf"})
	a.pin("bq")
	var saved := _json_round(a.serialize())
	var b := _runner(defs)
	b.deserialize(saved)
	assert_str(b.stage_of("bq")).is_equal("go_right")
	assert_str(b.stage_of("q_sequence")).is_equal("s1")
	assert_bool(b.objectives_of("q_sequence")[0].is_done()).is_true()
	assert_bool(b.is_pinned("bq")).is_true()
	assert_str(JSON.stringify(_json_round(b.serialize()))).is_equal(JSON.stringify(_json_round(a.serialize())))
	# The restored runner carries on.
	b.notify(&"enter_area", {"place": "right_place"})
	assert_bool(b.is_done("bq")).is_true()
	b.notify(&"talk", {"npc": "hesta"})
	b.notify(&"enter_area", {"place": "mill"})
	assert_bool(b.is_done("q_sequence")).is_true()
	# Finished quests stay finished across a save.
	var c := _runner(defs)
	c.deserialize(_json_round(b.serialize()))
	assert_bool(c.is_done("bq")).is_true()


func test_hub_saves_through_region1_state() -> void:
	QuestHub.reset()
	var r := QuestHub.runner()
	assert_bool(Region1State.has(QuestHub.MODULE)).is_true()
	assert_bool(r.defs.has("thornfield_spoiled_barley")).is_true()
	r.start("thornfield_spoiled_barley")
	r.notify(&"interact", {"id": "thornfield/clue/sack"})
	var snap := _json_round(Region1State.snapshot())
	r.abandon("thornfield_spoiled_barley")
	assert_bool(r.is_active("thornfield_spoiled_barley")).is_false()
	Region1State.restore(snap)
	assert_bool(r.is_active("thornfield_spoiled_barley")).is_true()
	assert_float(r.objectives_of("thornfield_spoiled_barley")[0].have).is_equal(1.0)
	QuestHub.reset()


# --- the Thornfield line -----------------------------------------------------------------------

func _thornfield() -> QuestRunner:
	var r := QuestRunner.new(QuestBus.new())
	r.reward_fn = func(rw: Dictionary) -> String:
		paid.append(rw)
		return "paid"
	assert_int(r.load_dir(THORNFIELD)).is_equal(3)
	return r


func _barley(r: QuestRunner) -> void:
	assert_str(r.start("thornfield_spoiled_barley")).is_empty()
	for c: String in ["sack", "prints", "lock"]:
		r.notify(&"interact", {"id": "thornfield/clue/" + c})
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("stakeout")
	r.notify(&"hours", {"amount": 1.0, "hour": 19.0})
	r.notify(&"hours", {"amount": 1.0, "hour": 20.0})
	# Spotted while watching once: the watch starts over.
	r.notify(&"observe", {"target": "barn_figure", "dist": 10.0, "unseen": true, "dt": 12.0, "hour": 23.0})
	r.notify(&"observe", {"target": "barn_figure", "dist": 10.0, "unseen": false, "dt": 0.5, "hour": 23.0})
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("stakeout")
	for i in 5:
		r.notify(&"observe", {"target": "barn_figure", "dist": 10.0, "unseen": true, "dt": 5.0, "hour": 23.0})
	assert_str(r.stage_of("thornfield_spoiled_barley")).is_equal("report")
	r.notify(&"talk", {"npc": "hesta_thorne"})
	assert_bool(r.is_done("thornfield_spoiled_barley")).is_true()


func test_thornfield_definitions_are_sound_and_use_every_type() -> void:
	var r := _thornfield()
	var types := {}
	for id: String in r.defs:
		var d: QuestDef = r.defs[id]
		assert_array(d.validate()).override_failure_message(id).is_empty()
		assert_str(d.giver_npc()).is_equal("hesta_thorne")
		for t: String in d.objective_types():
			types[t] = true
	assert_int(types.size()).is_equal(11)


func test_thornfield_quests_are_offered_by_hesta_through_the_talk_menu() -> void:
	var r := _thornfield()
	var offers := r.offers_for("Hesta_Thorne")
	assert_int(offers.size()).is_equal(1)             # the others need the barley quest first
	assert_str(offers[0].id).is_equal("thornfield_spoiled_barley")
	var opts := Talk.options_for(r, "hesta_thorne")
	assert_int(opts.size()).is_equal(1)
	assert_str(String(opts[0][0])).contains("Spoiled Barley")
	(opts[0][1] as Callable).call()
	assert_bool(r.is_active("thornfield_spoiled_barley")).is_true()
	assert_array(Talk.options_for(r, "hesta_thorne")).is_empty()     # nothing to say until the stage is done
	assert_array(r.pinned_markers()).is_empty()                        # and no marker unless pinned


func test_thornfield_end_to_end_turn_in() -> void:
	var r := _thornfield()
	_barley(r)
	assert_int(r.offers_for("hesta_thorne").size()).is_equal(2)
	# Wolves at the grain carts.
	assert_str(r.start("thornfield_grain_carts")).is_empty()
	r.notify(&"item", {"item": "barley", "amount": 4})
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("guard")
	r.notify(&"kill", {"target": "wolf", "place": "thornfield_fields"})
	r.notify(&"kill", {"target": "wolf", "place": "thornfield_fields", "amount": 2})
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("guard")      # still guarding the cart
	r.notify(&"hours", {"amount": 1.0, "hour": 17.0})
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("road")
	r.notify(&"arrive", {"actor": "grain_cart_1", "place": "thornfield_mill"})
	assert_str(r.stage_of("thornfield_grain_carts")).is_equal("mill")
	r.notify(&"deliver", {"item": "barley", "to": "thornfield_miller", "amount": 4})
	assert_bool(r.is_done("thornfield_grain_carts")).is_true()
	# The culprit: turn him in.
	assert_str(r.start("thornfield_the_culprit")).is_empty()
	r.notify(&"talk", {"npc": "wilm_garrow", "node": "confession"})                 # too early: he is not found yet
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("confront")
	r.notify(&"enter_area", {"place": "thornfield_barn"})
	r.notify(&"talk", {"npc": "wilm_garrow", "node": "confession"})
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("verdict")
	var opts := Talk.options_for(r, "wilm_garrow")
	assert_int(opts.size()).is_equal(2)
	paid.clear()
	for o: Array in opts:
		if String(o[0]).contains("turning him in"):
			(o[1] as Callable).call()
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("turned_in")
	r.notify(&"talk", {"npc": "hesta_thorne"})
	assert_bool(r.is_done("thornfield_the_culprit")).is_true()
	var rw := paid[paid.size() - 1] as Dictionary
	assert_int(int(rw["rep"]["thornfield"])).is_greater(0)
	assert_int(int(rw["gold"])).is_equal(20)


func test_thornfield_bribe_ending_has_reputation_consequences() -> void:
	var r := _thornfield()
	_barley(r)
	r.start("thornfield_the_culprit")
	r.notify(&"enter_area", {"place": "thornfield_barn"})
	r.notify(&"talk", {"npc": "wilm_garrow", "node": "confession"})
	r.notify(&"choose", {"choice": "verdict", "option": "bribe"})
	assert_str(r.stage_of("thornfield_the_culprit")).is_equal("bribed")
	paid.clear()
	r.notify(&"talk", {"npc": "wilm_garrow", "node": "bribe_paid"})
	assert_bool(r.is_done("thornfield_the_culprit")).is_true()
	var rw := paid[paid.size() - 1] as Dictionary
	assert_int(int(rw["rep"]["thornfield"])).is_less(0)
	assert_int(int(rw["gold"])).is_equal(60)
	assert_int(int((rw["relationship"] as Array)[0]["value"])).is_less(0)


func test_thornfield_cart_dying_fails_the_wolf_quest() -> void:
	var r := _thornfield()
	_barley(r)
	r.start("thornfield_grain_carts")
	r.notify(&"item", {"item": "barley", "amount": 4})
	paid.clear()
	r.notify(&"died", {"actor": "grain_cart_1"})
	assert_bool(r.is_failed("thornfield_grain_carts")).is_true()
	assert_int(int((paid[0] as Dictionary)["rep"]["thornfield"])).is_less(0)


func test_thornfield_survives_a_save_mid_stakeout() -> void:
	var r := _thornfield()
	assert_str(r.start("thornfield_spoiled_barley")).is_empty()
	for c: String in ["sack", "prints", "ledger"]:
		r.notify(&"interact", {"id": "thornfield/clue/" + c})
	r.notify(&"hours", {"amount": 2.0, "hour": 20.0})
	r.notify(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 12.0, "hour": 22.0})
	var r2 := _thornfield()
	r2.deserialize(_json_round(r.serialize()))
	r2.notify(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 9.0, "hour": 22.0})
	assert_str(r2.stage_of("thornfield_spoiled_barley")).is_equal("report")


func test_journal_lists_library_quests_with_describe_text() -> void:
	var r := _thornfield()
	r.start("thornfield_spoiled_barley")
	r.notify(&"interact", {"id": "thornfield/clue/sack"})
	var j := Journal.entries(r)
	assert_int((j["active"] as Array).size()).is_equal(1)
	var e: Dictionary = j["active"][0]
	assert_str(e["title"]).is_equal("The Spoiled Barley")
	assert_str(e["objectives"][0]["text"]).contains("1/3 found")
	assert_str(e["source"]).is_equal("quest_lib")
	assert_that(e["pos"]).is_null()                   # no marker for an investigation
	var lines := r.journal_lines()
	assert_str(lines[0]).contains("Search the barn").contains("1/3")
	# Finish the stage: the next stage's objective text shows up.
	r.notify(&"interact", {"id": "thornfield/clue/prints"})
	r.notify(&"interact", {"id": "thornfield/clue/lock"})
	var e2: Dictionary = Journal.entries(r)["active"][0]
	assert_str(e2["objectives"][0]["text"]).contains("Wait for night to fall").contains("0/2 hours")
	assert_bool(e2["objectives"][0]["done"]).is_false()
	# Pinned quests expose a marker only after the player pins them.
	r.notify(&"hours", {"amount": 2.0, "hour": 20.0})
	assert_array(r.pinned_markers()).is_empty()
	r.pin("thornfield_spoiled_barley")
	assert_int(r.pinned_markers().size()).is_equal(1)
	assert_that(Journal.entries(r)["active"][0]["pos"]).is_not_null()


func test_menu_data_merges_library_quests() -> void:
	QuestHub.reset()
	var r := QuestHub.runner()
	r.start("thornfield_spoiled_barley")
	var found := false
	for q: Dictionary in preload("res://scripts/ui/gamemenu/menu_data.gd").quests()["active"]:
		if String(q["id"]) == "lib_thornfield_spoiled_barley":
			found = true
	assert_bool(found).is_true()
	QuestHub.reset()


# --- adapters --------------------------------------------------------------------------------------

func test_radiant_quests_convert_to_library_definitions() -> void:
	var world := {"home": Vector2.ZERO,
		"dens": [{"id": 0, "species": "wolf", "pos": Vector2(420, 310), "population": 6, "alive": true}],
		"sites": [{"name": "Cinderpost Waystation", "kind": "waystation", "pos": Vector2(300, -210)}],
		"places": {"whisper_hollow": {"name": "Whisper Hollow", "kind": "hidden_place", "pos": Vector2(-560, 520), "radius": 12}}}
	var kinds := {}
	for q: Dictionary in RadiantQuests.generate(world, 5, 1):
		kinds[q["kind"]] = true
		q["giver"] = "herbalist"
		var d := RadiantAdapter.to_def(q)
		assert_array(d.validate()).override_failure_message(String(q["kind"])).is_empty()
		var r := _runner([])
		r.add_def(d)
		assert_str(r.start(d.id)).is_empty()
		# Walk the quest with the same facts the radiant poller uses.
		for st: Dictionary in q["stages"]:
			match String(st["type"]):
				"reach":
					r.notify(&"position", {"x": (st["pos"] as Vector2).x, "y": (st["pos"] as Vector2).y})
					if String(q["kind"]) == "escort":
						r.notify(&"actor_pos", {"actor": String(q["data"]["trader"]).to_lower().replace(" ", "_"), "x": (st["pos"] as Vector2).x, "y": (st["pos"] as Vector2).y})
				"gather":
					r.notify(&"item", {"item": st["item"], "amount": int(st["amount"])})
				"kill_den":
					r.notify(&"kill", {"target": "wolf", "amount": int(st["kills"])})
				"return":
					r.notify(&"talk", {"npc": "herbalist"})
		assert_bool(r.is_done(d.id)).override_failure_message("%s did not finish" % q["kind"]).is_true()
	for k: String in RadiantQuests.KINDS:
		assert_bool(kinds.has(k)).is_true()


func test_story_steps_can_use_library_objectives() -> void:
	var story := StoryQuest.new()
	story.setup(1)
	story.use_quest({"id": "t", "complete_flag": "done", "steps": [{"id": "s1", "act": 1, "objectives": [
		{"id": "wolves", "type": "lib", "objective": {"type": "kill", "target": "wolf", "count": 2}},
		{"id": "clues", "type": "lib", "objective": {"type": "investigate", "clues": ["a", "b"]}}],
		"on_complete": [["flag", "done"]]}]})
	story.refresh({})
	story.notify(&"kill", {"target": "wolf", "amount": 1})
	assert_bool(story.objective_done("s1", "wolves")).is_false()
	story.notify(&"kill", {"target": "wolf", "amount": 1})
	assert_bool(story.objective_done("s1", "wolves")).is_true()
	story.notify(&"interact", {"id": "a"})
	# Save and restore mid-step: the clue count carries over.
	var saved := _json_round(story.serialize())
	var back := StoryQuest.new()
	back.setup(1)
	back.use_quest(story.quest)
	back.deserialize(saved)
	back.notify(&"interact", {"id": "a"})      # the same clue again does not count twice
	assert_bool(back.is_complete()).is_false()
	back.notify(&"interact", {"id": "b"})
	assert_bool(back.is_complete()).is_true()


func test_story_events_reach_library_quests_on_the_shared_bus() -> void:
	QuestBus.reset_shared()
	var r := QuestRunner.new()           # listens to the shared bus
	r.add_def(QuestDef.from_dict({"id": "q", "title": "T", "stages": [{"id": "s", "objectives": [{"id": "a", "type": "goto", "place": "ashford_ring"}]}]}))
	r.start("q")
	var story := StoryQuest.new()
	story.setup(1)
	story.use_quest({"id": "t", "steps": []})
	story.notify(&"enter_area", {"place": "ashford_ring"})
	assert_bool(r.is_done("q")).is_true()
	r.unbind()
	QuestBus.reset_shared()


func test_live_rewards_pay_through_the_game_apis() -> void:
	var gold0: int = Game.gold
	var rep0: float = Life.relationships.rep("thornfield")
	var text := QuestRewards.apply({"gold": 7, "rep": {"thornfield": 3}})
	assert_int(Game.gold).is_equal(gold0 + 7)
	assert_float(Life.relationships.rep("thornfield")).is_equal(rep0 + 3.0)
	assert_str(text).contains("+7g")
	Game.add_gold(-7)
	Life.relationships.change_rep("thornfield", -3.0)


func test_a_talk_objective_with_a_node_is_not_a_report_button() -> void:
	# "Hear what Wilm has to say" is met inside the conversation (node "confession"); a plain Report would do nothing
	var r := _runner([{"id": "q_node", "title": "T", "stages": [{"id": "s1", "mode": "all", "objectives": [
		{"id": "a", "type": "talk_to", "npc": "wilm", "node": "confession"},
		{"id": "b", "type": "talk_to", "npc": "hesta"}]}]}])
	assert_str(r.start("q_node")).is_empty()
	assert_int(r.quests_awaiting_talk("wilm").size()).is_equal(0)
	assert_int(r.quests_awaiting_talk("hesta").size()).is_equal(1)

