extends GdUnitTestSuite
## Region 1 tutorial director (L16, scripts/region1/tutorial_director.gd): context triggers,
## dismissal only by the real action, priority and pre-emption, skip, replay, save round trip,
## locale rows (en + nl) and the prompt view.

const Director := preload("res://scripts/region1/tutorial_director.gd")
const View := preload("res://scripts/region1/tutorial_prompt_view.gd")
const State := preload("res://scripts/region1/region1_state.gd")


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


## A context in which prompt `id` is relevant (built from its own rule).
func _ctx_for(id: String) -> Dictionary:
	var ctx := {"touch": true}
	var rule: Dictionary = Director.PROMPTS[id]["when"]
	for k: String in rule:
		if k.ends_with("_lt"):
			ctx[k.trim_suffix("_lt")] = float(rule[k]) - 10.0
		elif k.ends_with("_gt"):
			ctx[k.trim_suffix("_gt")] = float(rule[k]) + 10.0
		else:
			ctx[k] = rule[k]
	return ctx


## Settle everything `id` depends on, so it may show.
func _unlock(d: Director, id: String) -> void:
	for dep: Variant in Director.PROMPTS[id].get("after", []):
		_unlock(d, String(dep))
		d.skip(StringName(dep))


func _pump(d: Director, ctx: Dictionary, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		d.update(ctx, 0.1)
		t += 0.1


func test_there_are_twelve_prompts_covering_the_brief() -> void:
	assert_array(Array(Director.ids())).contains_exactly_in_any_order(
		["move", "look", "talk", "interact", "eat", "sleep", "fight", "block", "dodge", "carve", "map", "ashsight"])


func test_every_prompt_shows_in_context_and_only_its_real_action_dismisses_it() -> void:
	for id: String in Director.PROMPTS:
		var d := Director.new()
		_unlock(d, id)
		var ctx := _ctx_for(id)
		_pump(d, ctx, 2.0)
		assert_str(String(d.current)).override_failure_message("%s did not show" % id).is_equal(id)
		d.notify(&"not_the_action", 99.0)
		assert_str(String(d.current)).override_failure_message("%s dismissed by a wrong action" % id).is_equal(id)
		var p: Dictionary = Director.PROMPTS[id]
		d.notify(StringName(p["action"]), float(p["amount"]))
		assert_bool(d.is_done(StringName(id))).override_failure_message("%s not done" % id).is_true()
		assert_str(String(d.current)).is_equal("")


func test_nothing_shows_without_context() -> void:
	var d := Director.new()
	_pump(d, {}, 5.0)
	assert_str(String(d.current)).is_equal("")


func test_prompt_hidden_signal_says_done_after_the_action() -> void:
	var d := Director.new()
	var got: Array = []
	d.prompt_hidden.connect(func(id: StringName, why: StringName) -> void: got.append([String(id), String(why)]))
	_pump(d, {"can_control": true}, 1.0)
	assert_str(String(d.current)).is_equal("move")
	d.notify(&"move", 0.5)
	assert_str(String(d.current)).is_equal("move")   # needs a full second of walking
	d.notify(&"move", 0.6)
	assert_array(got).contains([["move", "done"]])


func test_doing_the_action_before_the_prompt_counts() -> void:
	var d := Director.new()
	d.notify(&"move", 2.0)
	assert_bool(d.is_done(&"move")).is_true()
	_pump(d, {"can_control": true}, 3.0)
	assert_str(String(d.current)).is_equal("look")   # move is skipped straight to the next lesson


func test_later_lessons_wait_for_their_prerequisite() -> void:
	var d := Director.new()
	d.notify(&"block")   # blocking before learning to strike does not count yet
	assert_bool(d.is_done(&"block")).is_false()
	_pump(d, {"enemy_near": true, "enemy_winding_up": true}, 2.0)
	assert_str(String(d.current)).is_equal("fight")


func test_combat_prompt_preempts_a_calm_one() -> void:
	var d := Director.new()
	d.notify(&"move", 2.0)
	d.notify(&"look", 2.0)
	var ctx := {"can_control": true, "near_npc": true}
	_pump(d, ctx, 2.0)
	assert_str(String(d.current)).is_equal("talk")
	ctx["enemy_near"] = true
	_pump(d, ctx, 1.0)
	assert_str(String(d.current)).is_equal("fight")
	assert_bool(d.is_done(&"talk")).is_false()   # still pending: it comes back later


func test_lost_context_hides_the_prompt_and_it_returns() -> void:
	var d := Director.new()
	var ctx := {"enemy_near": true}
	_pump(d, ctx, 1.0)
	assert_str(String(d.current)).is_equal("fight")
	_pump(d, {}, 2.0)
	assert_str(String(d.current)).is_equal("")
	_pump(d, ctx, 2.0)
	assert_str(String(d.current)).is_equal("fight")


func test_menus_and_cutscenes_block_prompts() -> void:
	var d := Director.new()
	_pump(d, {"can_control": true, "blocked": true}, 3.0)
	assert_str(String(d.current)).is_equal("")
	_pump(d, {"can_control": true}, 1.0)
	assert_str(String(d.current)).is_equal("move")
	d.update({"can_control": true, "blocked": true}, 0.1)
	assert_str(String(d.current)).is_equal("")


func test_skip_current_and_hide_all() -> void:
	var d := Director.new()
	_pump(d, {"can_control": true}, 1.0)
	d.skip_current()
	assert_int(d.status(&"move")).is_equal(Director.State.SKIPPED)
	_pump(d, {"can_control": true}, 3.0)
	assert_str(String(d.current)).is_equal("look")   # skipping still unlocks the next lesson
	d.set_enabled(false)
	assert_str(String(d.current)).is_equal("")
	_pump(d, {"can_control": true, "enemy_near": true}, 3.0)
	assert_str(String(d.current)).is_equal("")


func test_replay_shows_out_of_context_and_still_needs_the_action() -> void:
	var d := Director.new()
	d.notify(&"move", 2.0)
	d.notify(&"look", 2.0)
	d.notify(&"carve")   # carve counted (no prerequisite) and done
	assert_bool(d.is_done(&"carve")).is_true()
	d.replay(&"carve")
	_pump(d, {}, 0.5)
	assert_str(String(d.current)).is_equal("carve")
	_pump(d, {}, 3.0)
	assert_str(String(d.current)).is_equal("carve")   # forced prompts do not time out
	d.notify(&"carve")
	assert_bool(d.is_done(&"carve")).is_true()
	d.set_enabled(false)
	d.replay_all()
	assert_bool(d.enabled).is_true()
	assert_int(d.pending().size()).is_equal(Director.PROMPTS.size())


func test_touch_and_keyboard_captions() -> void:
	var d := Director.new()
	var touch := d.describe(&"fight", true)
	var kb := d.describe(&"fight", false)
	assert_str(touch["text_key"]).is_equal("TUT_FIGHT")
	assert_str(kb["text_key"]).is_equal("TUT_FIGHT_KB")
	assert_str(touch["anchor"]).is_equal("btn_attack")
	for id: String in Director.PROMPTS:
		assert_int(String(Director.PROMPTS[id]["en"]).length()).is_less_equal(28)   # minimal text


func test_snapshot_round_trips_through_json_and_the_region1_registry() -> void:
	var d := Director.new()
	d.notify(&"move", 2.0)
	d.skip(&"look")
	d.set_enabled(false)
	d.register_save()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(State.snapshot()))
	var e := Director.new()
	State.clear()
	e.register_save()
	State.restore(snap)
	assert_bool(e.is_done(&"move")).is_true()
	assert_int(e.status(&"look")).is_equal(Director.State.SKIPPED)
	assert_bool(e.enabled).is_false()
	assert_int(e.pending().size()).is_equal(Director.PROMPTS.size() - 2)


func test_every_prompt_string_has_english_and_dutch_rows() -> void:
	var rows := {}
	var f := FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	assert_object(f).is_not_null()
	var header := f.get_csv_line()
	assert_array(Array(header)).is_equal(["keys", "en", "nl"])
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() >= 3:
			rows[r[0]] = r
	var keys := ["TUT_SKIP", "TUT_TIPS", "TUT_TIPS_OFF", "TUT_REPLAY", "TUT_REPLAY_ALL"]
	for id: String in Director.PROMPTS:
		keys.append(Director.PROMPTS[id]["text"])
		keys.append(Director.PROMPTS[id]["text_kb"])
	for k: String in keys:
		assert_bool(rows.has(k)).override_failure_message("locale row %s missing" % k).is_true()
		if rows.has(k):
			assert_str(rows[k][1]).is_not_empty()
			assert_str(rows[k][2]).is_not_empty()
	assert_str(rows["TUT_MOVE"][1]).is_equal(Director.PROMPTS["move"]["en"])


func test_view_shows_the_prompt_and_its_skip_button_skips() -> void:
	var d := Director.new()
	var v: Region1TutorialPromptView = auto_free(View.new())
	add_child(v)
	v.size = Vector2(1200, 540)
	v.bind(d)
	_pump(d, {"can_control": true}, 1.0)
	assert_str(String(d.current)).is_equal("move")
	assert_bool(v._pill.visible).is_true()
	assert_bool(v._label.text.length() > 0).is_true()
	assert_str(v.prompt["anchor"]).is_equal("left_stick")
	v.skip_pressed.emit()
	assert_int(d.status(&"move")).is_equal(Director.State.SKIPPED)
	v.set_hud_anchor(&"btn_attack", Vector2(10, 20))
	assert_vector(v.anchor_pos("btn_attack")).is_equal(Vector2(10, 20))


func test_tell_reaches_the_main_director_only_when_set() -> void:
	Director.main = null
	Director.tell(&"carve")   # no director: harmless
	var d := Director.new().make_main()
	Director.tell(&"carve")
	assert_bool(d.is_done(&"carve")).is_true()
	Director.main = null


class FakePlayer extends Node3D:
	var velocity := Vector3.ZERO
	var dead := false
	var camera: Node3D
	var near: Node = null
	func nearest_interactable() -> Node:
		return near


func test_bridge_builds_context_and_detects_walking() -> void:
	var p := FakePlayer.new()
	var hud := CanvasLayer.new()
	add_child(p)
	add_child(hud)
	var b := Region1TutorialBridge.new()
	add_child(b)
	b.setup(p, hud)
	assert_object(Region1TutorialDirector.main).is_same(b.director)
	var ctx := b.context()
	assert_bool(ctx["can_control"]).is_true()
	assert_bool(ctx["near_npc"]).is_false()
	var npc := Node3D.new()
	npc.add_to_group("villager")
	add_child(npc)
	p.near = npc
	assert_bool(b.context()["near_npc"]).is_true()
	p.velocity = Vector3(3, 0, 0)
	for i in 12:
		b._process(0.1)
	assert_bool(b.director.is_done(&"move")).is_true()
	b.queue_free()
	p.queue_free()
	hud.queue_free()
	npc.queue_free()
	await get_tree().process_frame
	assert_object(Region1TutorialDirector.main).is_null()
