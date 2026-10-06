extends GdUnitTestSuite
## In-world conversation (FOUNDATION_PLAN F4): the talk session (distance / stick), the villager pause and
## resume, the body turn, the camera framing, the greeting bark limits and the dialogue runner choices.

const TalkSession := preload("res://scripts/ui/talk_session.gd")
const TalkPose := preload("res://scripts/population/talk_pose.gd")
const TalkBark := preload("res://scripts/population/talk_bark.gd")
const ChaseCamera := preload("res://scripts/actors/chase_camera.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const DialogueSheet := preload("res://scripts/ui/dialogue_sheet.gd")
const VillagerScript := preload("res://scripts/population/villager.gd")


class StubPlayer extends Node3D:
	var touch_move := Vector2.ZERO
	var framing := false
	func set_talk_framing(on: bool, _partner: Node3D = null) -> void:
		framing = on


class StubNpc extends Node3D:
	var talking := false
	var begun := 0
	var ended := 0
	func talk_begin(_p: Node3D = null) -> void:
		talking = true
		begun += 1
	func talk_end() -> void:
		talking = false
		ended += 1


var _menu_open := true
var _sheet_open := true


func _is_menu() -> bool:
	return _menu_open


func _is_sheet() -> bool:
	return _sheet_open


func _session(npc_at := Vector3(2, 0, 0)) -> Array:
	var player := StubPlayer.new()
	var npc := StubNpc.new()
	add_child(auto_free(player))
	add_child(auto_free(npc))
	npc.global_position = npc_at
	var s := TalkSession.new()
	add_child(auto_free(s))
	_menu_open = true
	_sheet_open = true
	s.begin(player, npc, _is_menu, _is_sheet, "p1")
	return [s, player, npc]


# --- session ends on distance or stick ---------------------------------------------------

func test_session_starts_the_npc_and_the_camera() -> void:
	var r := _session()
	assert_bool((r[0] as Node).active).is_true()
	assert_bool((r[2] as StubNpc).talking).is_true()
	assert_bool((r[1] as StubPlayer).framing).is_true()


func test_walking_away_ends_the_talk_and_releases_everything() -> void:
	var r := _session()
	var s: Node = r[0]
	assert_str(s.tick(0.1, Vector2.ZERO)).is_equal("")
	(r[1] as Node3D).global_position = Vector3(-(TalkSession.END_DISTANCE + 0.5), 0, 0)   # 6.5 m from the NPC
	assert_str(s.tick(0.1, Vector2.ZERO)).is_equal("distance")
	assert_bool(s.active).is_false()
	assert_bool((r[2] as StubNpc).talking).is_false()
	assert_bool((r[1] as StubPlayer).framing).is_false()


func test_close_enough_keeps_talking() -> void:
	var r := _session(Vector3(3.5, 0, 0))
	for i in 20:
		assert_str((r[0] as Node).tick(0.1, Vector2.ZERO)).is_equal("")
	assert_bool((r[0] as Node).active).is_true()


func test_moving_the_stick_ends_the_talk() -> void:
	var r := _session()
	var s: Node = r[0]
	assert_str(s.tick(0.1, Vector2.ZERO)).is_equal("")
	assert_str(s.tick(0.1, Vector2(0.0, -0.8))).is_equal("moved")
	assert_bool((r[2] as StubNpc).talking).is_false()


func test_a_stick_still_held_from_walking_up_does_not_end_it_at_once() -> void:
	var r := _session()
	var s: Node = r[0]
	assert_str(s.tick(0.1, Vector2(0, -1))).is_equal("")      # not armed yet
	assert_str(s.tick(0.1, Vector2(0, -1))).is_equal("")
	s.tick(0.1, Vector2.ZERO)                                  # let go ...
	assert_str(s.tick(0.1, Vector2(0.5, 0))).is_equal("moved")  # ... and push again


func test_small_stick_noise_is_ignored() -> void:
	var r := _session()
	(r[0] as Node).tick(0.1, Vector2.ZERO)
	assert_str((r[0] as Node).tick(0.1, Vector2(0.1, 0.05))).is_equal("")


func test_closing_the_menu_ends_the_session_and_a_shop_does_not() -> void:
	var r := _session()
	var s: Node = r[0]
	s.tick(0.1, Vector2.ZERO)
	_sheet_open = false                                        # a full-screen shop replaced the sheet
	assert_str(s.tick(0.1, Vector2(0, -1))).is_equal("")       # stick noise does not close a shop
	assert_bool(s.active).is_true()
	_menu_open = false
	assert_str(s.tick(0.1, Vector2.ZERO)).is_equal("closed")
	assert_bool((r[2] as StubNpc).talking).is_false()


func test_fresh_session_waits_for_the_menu_to_open() -> void:
	var r := _session()
	_menu_open = false                                         # the HUD has not shown the sheet yet
	assert_str((r[0] as Node).tick(0.1, Vector2.ZERO)).is_equal("")
	_menu_open = true
	(r[0] as Node).tick(0.1, Vector2.ZERO)
	_menu_open = false
	assert_str((r[0] as Node).tick(0.1, Vector2.ZERO)).is_equal("closed")


func test_ending_twice_resumes_the_npc_once() -> void:
	var r := _session()
	(r[0] as Node).end("closed")
	(r[0] as Node).end("closed")
	assert_int((r[2] as StubNpc).ended).is_equal(1)


# --- villager pause / resume ---------------------------------------------------------

func test_villager_stops_keeps_its_route_and_resumes() -> void:
	var player := Node3D.new()
	add_child(auto_free(player))
	player.global_position = Vector3(5, 0, 0)
	var v = VillagerScript.new()           # not in the tree: only its state is driven here
	auto_free(v)
	v._path = [Vector2(10, 10), Vector2(20, 20)] as Array[Vector2]
	v._path_i = 1
	v._arrived = false
	v._heading = 0.0
	v._move_speed = 1.4
	v.talk_begin(player)
	assert_bool(v.is_talking()).is_true()
	for i in 30:
		assert_vector(v._steer(Vector2.ZERO, 0.05)).is_equal(Vector2.ZERO)    # stands still while talking
	assert_float(v._move_speed).is_equal(0.0)
	assert_int(v._path_i).is_equal(1)                          # the schedule / route is untouched
	assert_int(v._path.size()).is_equal(2)
	assert_bool(v._arrived).is_false()
	v.talk_end()
	assert_bool(v.is_talking()).is_false()
	assert_int(v._path_i).is_equal(1)
	v._steer(Vector2.ZERO, 0.05)                               # resumes route following (heads for waypoint 1)
	assert_float(v._move_speed).is_greater(0.0)


# --- face target ---------------------------------------------------------------------

func test_turn_heading_converges_without_overshoot() -> void:
	var here := Vector2.ZERO
	var target := Vector2(-3, -3)       # behind the NPC (heading 0 faces +z)
	var h := 0.0
	var last := TalkPose.facing_error(h, here, target)
	for i in 120:
		h = TalkPose.turn_heading(h, here, target, 1.0 / 60.0)
		var e := TalkPose.facing_error(h, here, target)
		assert_float(e).is_less_equal(last + 0.0001)           # never turns away or overshoots
		last = e
	assert_float(last).is_less(TalkPose.FACING_EPS)
	assert_float(TalkPose.facing_error(h, here, target)).is_equal_approx(0.0, 0.001)


func test_turn_takes_the_short_way_round() -> void:
	var h := TalkPose.turn_heading(3.0, Vector2.ZERO, Vector2(-0.2, -1.0), 0.05)   # target is near heading PI
	assert_float(absf(wrapf(h - 3.0, -PI, PI))).is_less(0.3)
	assert_float(wrapf(h - 3.0, -PI, PI)).is_greater(0.0)      # increasing through PI, not the long way down


func test_villager_body_faces_the_player_while_talking() -> void:
	var player := Node3D.new()
	add_child(auto_free(player))
	player.global_position = Vector3(4, 0, 0)               # to the villager's +x
	var v = VillagerScript.new()
	auto_free(v)
	v._heading = PI
	v.talk_begin(player)
	for i in 90:
		v._steer(Vector2.ZERO, 1.0 / 60.0)
	assert_float(TalkPose.facing_error(v._heading, Vector2.ZERO, Vector2(4, 0))).is_less(TalkPose.FACING_EPS)


# --- camera --------------------------------------------------------------------------

func _run(c: RefCounted, seconds: float) -> void:
	for i in int(seconds * 60.0):
		c.step(1.0 / 60.0, {})


func test_camera_framing_is_applied_and_restored() -> void:
	var c := ChaseCamera.new()
	_run(c, 0.2)
	assert_float(c.talk_shift()).is_equal(0.0)
	assert_bool(c.begin_talk()).is_true()
	c.step(1.0 / 60.0, {})
	assert_float(c.talk_shift()).is_between(0.0, 0.1)         # eased, never a snap
	_run(c, ChaseCamera.TALK_TIME + 0.1)
	assert_float(c.talk_shift()).is_equal_approx(ChaseCamera.TALK_SHIFT, 0.001)
	assert_float(c.fov_offset()).is_equal_approx(ChaseCamera.TALK_FOV, 0.001)
	assert_float(c.fov_base()).is_equal_approx(ChaseCamera.BASE_FOV + ChaseCamera.TALK_FOV, 0.001)
	assert_float(c.dist_offset()).is_equal_approx(ChaseCamera.TALK_DIST, 0.001)
	c.end_talk()
	_run(c, ChaseCamera.TALK_TIME + 0.1)
	assert_float(c.talk_shift()).is_equal(0.0)
	assert_float(c.fov_offset()).is_equal_approx(0.0, 0.001)
	assert_float(c.dist_offset()).is_equal_approx(0.0, 0.001)


func test_camera_framing_takes_about_four_tenths_of_a_second() -> void:
	var c := ChaseCamera.new()
	c.begin_talk()
	_run(c, 0.2)
	assert_float(c.talk_shift()).is_between(0.05, ChaseCamera.TALK_SHIFT - 0.05)
	_run(c, 0.25)
	assert_float(c.talk_shift()).is_equal_approx(ChaseCamera.TALK_SHIFT, 0.001)


func test_camera_framing_setting_off_disables_it() -> void:
	var c := ChaseCamera.new()
	c.talk_enabled = false
	assert_bool(c.begin_talk()).is_false()
	_run(c, 1.0)
	assert_float(c.talk_shift()).is_equal(0.0)
	var SS := preload("res://scripts/ui/frontend/settings_store.gd")
	assert_bool(SS.DEFAULTS.has("talk_camera")).is_true()
	assert_bool(bool(SS.DEFAULTS["talk_camera"])).is_true()


# --- bark ----------------------------------------------------------------------------

func test_bark_needs_a_good_opinion_and_is_rate_limited() -> void:
	TalkBark.reset()
	var t := 1000000
	assert_bool(TalkBark.eligible(TalkBark.MIN_OPINION - 1, 3.0, t, -1000000, 0)).is_false()
	assert_bool(TalkBark.eligible(TalkBark.MIN_OPINION, 9.0, t, -1000000, 0)).is_false()       # too far
	assert_bool(TalkBark.eligible(TalkBark.MIN_OPINION, 3.0, t, -1000000, 1)).is_false()       # a bubble is already up
	assert_bool(TalkBark.eligible(TalkBark.MIN_OPINION, 3.0, t, t - 1000, 0)).is_false()       # this person just spoke
	assert_bool(TalkBark.eligible(TalkBark.MIN_OPINION, 3.0, t, -1000000, 0)).is_true()
	TalkBark.spoke(t)
	assert_bool(TalkBark.eligible(50, 3.0, t + 1000, -1000000, 0)).is_false()                  # global cooldown
	assert_bool(TalkBark.eligible(50, 3.0, t + TalkBark.GLOBAL_GAP_MS + 1, -1000000, 0)).is_true()
	TalkBark.reset()
	assert_str(TalkBark.line(3, 20)).is_not_empty()
	assert_str(TalkBark.line(3, 60)).is_not_empty()


# --- dialogue runner + sheet ---------------------------------------------------------

func test_dialogue_runner_choices_still_work() -> void:
	DialogueRunner.clear_cache()
	var d := DialogueRunner.load_file("villager")
	var ctx := {"first": "Edda", "player": "Ren", "kid": "friend", "greeting": "Hearth keep you.", "reply": "And stone guard you.",
		"tier": "friend", "time": "morning", "child": false}
	var start := DialogueRunner.start_node(d)
	var opts := DialogueRunner.choices(d, start, ctx)
	assert_bool(opts.is_empty()).is_false()
	for o: Dictionary in opts:
		assert_bool(String(o["text"]) != "").is_true()
		var g := String(o["goto"])
		assert_bool(g == "@end" or DialogueRunner.node_exists(d, g)).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_bool(DialogueRunner.pick_line(d, start, ctx, rng).is_empty()).is_false()


func test_sheet_shows_choices_and_picks_them() -> void:
	var sheet: Control = auto_free(DialogueSheet.new())
	add_child(sheet)
	var picked: Array[int] = []
	sheet.option_picked.connect(func(i: int) -> void: picked.append(i))
	sheet.set_page({"speaker": "Edda", "role": "Baker", "line": "Hearth keep you.", "relationship": "Friendly (+20)",
		"options": [["Chat", Callable()], ["Trade", Callable(), false], ["Leave", Callable()]]})
	assert_int(sheet.choice_count()).is_equal(3)
	assert_bool(sheet.pick(1)).is_false()      # disabled
	assert_bool(sheet.pick(2)).is_true()
	assert_array(picked).is_equal([2])
	for b in sheet._buttons:
		assert_float((b as Button).custom_minimum_size.y).is_greater_equal(48.0)   # big tap targets
	assert_float(DialogueSheet.SHEET_TOP).is_equal_approx(0.72, 0.001)           # the lower ~28% (AAA pass 8)
