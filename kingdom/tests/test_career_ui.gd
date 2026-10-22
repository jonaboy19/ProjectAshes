extends GdUnitTestSuite
## Smoke test of the career work and ladder screen (scripts/ui/career_tasks.gd): every scribe task screen
## renders from the module's view, a full copy task can be played by pressing its buttons, and the
## ladder tab lists every rank with its requirement ticks. No answers leak into the screens.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const CareerTasks := preload("res://scripts/ui/career_tasks.gd")

static var _world_ready := false
var _hub: RefCounted
var _sc: RefCounted
var _tr: RefCounted


func before_test() -> void:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true
	_hub = Hub.new()
	_sc = _hub.mod("scribe")
	_tr = _hub.mod("trades")
	var m := Mastery.new()
	var b := Biography.new()
	for d in 40:
		m.gain("scholarship", 2.0, d)
		m.gain("smithing", 1.0, d)
	for mod: RefCounted in [_sc, _tr]:
		mod.mastery_ref = m
		mod.bio_ref = b
		mod.gold_ref = 300
		mod.sync_life = false
	_tr.homestead_ref = preload("res://scripts/sim/homestead.gd").new()
	_sc.apply(0, 1, 0.9)
	_sc.rank = 2
	CareerTasks.modules = {"scribe": _sc, "trades": _tr, "land": _hub.mod("land")}
	CareerTasks.day_override = 50


func after_test() -> void:
	CareerTasks.modules = {}
	CareerTasks.day_override = -1


func _screen(trade := "scribe") -> Control:
	var s: Control = auto_free(CareerTasks.new())
	add_child(s)
	s.open(trade)
	return s


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text and not (n as Button).disabled:
		return n as Button
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func _press(s: Control, text: String) -> void:
	var b := _find_button(s.get("_content"), text)
	assert_object(b).override_failure_message("no button '%s'" % text).is_not_null()
	if b != null:
		b.pressed.emit()


func test_menu_lists_the_offers_for_the_rank_and_the_ladder_lists_every_rank() -> void:
	var s := _screen()
	var all: String = "\n".join(_texts(s.get("_content")))
	assert_str(all).contains("Copy a document")
	assert_str(all).contains("Examine a seal")
	assert_str(all).contains("Open the sealed archive")
	s.call("_set_tab", "ladder")
	var ladder: String = "\n".join(_texts(s.get("_content")))
	for title in ["Copyist", "Clerk", "Registrar", "Steward's Secretary", "Steward", "Envoy"]:
		assert_str(ladder).contains(title)
	assert_str(ladder).contains("[ok]")
	assert_str(ladder).contains("[  ]")
	s.call("close_screen")


func test_a_whole_copy_task_can_be_played_with_the_buttons() -> void:
	var s := _screen()
	_press(s, "Copy a document  (2 h)")
	assert_str(String(_sc.task["kind"])).is_equal("copy")
	# Steady the pen: the widget needs a real tap, so skip that step the way the screen does when it ends.
	var lines: Array = _sc.task["doc"]["lines"]
	s.get("_scratch")["copy"] = {"i": 0, "picks": [], "steady": 0.95}
	for i in lines.size():
		s.call("_render_task")
		var l: Dictionary = lines[i]
		_press(s, String(l["options"][int(l["correct"])]))
	var done: String = "\n".join(_texts(s.get("_content")))
	assert_str(done.to_lower()).contains("done")
	assert_str(done).contains("faithful")
	assert_int(_sc.stats["copies"]).is_equal(1)
	s.set("_pending_hours", 0.0)
	s.call("close_screen")


func test_forgery_screen_shows_findings_without_leaking_the_flaws() -> void:
	var s := _screen()
	var guard := 0
	while guard < 50:
		guard += 1
		_sc.hours_used.clear()
		_sc.begin("forgery", 60 + guard)
		if not (_sc.task["doc"]["flaws"] as Dictionary).is_empty():
			break
		_sc.abandon_task()
	s.call("_render_task")
	var before: String = "\n".join(_texts(s.get("_content")))
	assert_str(before).contains("Examine the seal")
	assert_str(before).not_contains("specimen shows")
	_press(s, "Examine the seal")
	s.call("_render_task")
	var after: String = "\n".join(_texts(s.get("_content")))
	assert_str(after).contains("Seal")
	assert_str(after).contains("Suspicious")
	_press(s, "Genuine: pass it")
	assert_str("\n".join(_texts(s.get("_content"))).to_lower()).contains("done")
	s.set("_pending_hours", 0.0)
	s.call("close_screen")


func test_tax_translate_exam_and_secret_screens_render() -> void:
	var s := _screen()
	var bt: Dictionary = _sc.begin("tax", 51)
	assert_bool(bt["ok"]).override_failure_message(String(bt.get("reason", ""))).is_true()
	s.call("_render_task")
	var tax: String = "\n".join(_texts(s.get("_content")))
	assert_str(tax).contains("Report the errors")
	assert_str(tax).contains("declared")
	_sc.abandon_task()
	_sc.hours_used.clear()
	_sc.begin("translate", 52)
	s.set("_scratch", {})
	s.call("_render_task")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Read it")
	_sc.abandon_task()
	_sc.hours_used.clear()
	_sc.rank = 3     # a secretary sits the steward's accounts next
	var be: Dictionary = _sc.begin("exam", 53)
	assert_bool(be["ok"]).override_failure_message(String(be.get("reason", ""))).is_true()
	s.set("_scratch", {})
	s.call("_render_task")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Question 1 of")
	_sc.abandon_task()
	var sec: Dictionary = _sc._new_secret("debt", 54, 0, false)
	s.call("_render_secret", sec)
	var secret: String = "\n".join(_texts(s.get("_content")))
	assert_str(secret).contains("Blackmail")
	assert_str(secret).contains("Report it")
	s.call("close_screen")


func test_steward_estate_and_envoy_screens_render() -> void:
	_sc.rank = 4
	_sc.assign_estate(40)
	var s := _screen()
	s.call("_render_estate")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Tenants")
	_sc.rank = 5
	_sc.hours_used.clear()
	s.call("_render_embassy")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Go")
	s.call("close_screen")


func test_trade_screens_walk_the_steps_of_a_task() -> void:
	_tr.join("blacksmith", 1)
	var s := _screen("blacksmith")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Forge a piece")
	_press(s, "Forge a piece  (2 h)")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Step 1 of 2")
	s.call("_trade_submit", _tr.submit(0.9))
	assert_str("\n".join(_texts(s.get("_content")))).contains("Step 2 of 2")
	s.call("_trade_submit", _tr.submit(0.9))
	assert_str("\n".join(_texts(s.get("_content"))).to_lower()).contains("done")
	s.set("_pending_hours", 0.0)
	s.call("_set_tab", "ladder")
	assert_str("\n".join(_texts(s.get("_content")))).contains("Journeyman")
	s.call("close_screen")


func test_embedded_mode_reports_the_quality_back() -> void:
	var holder: Control = auto_free(Control.new())
	add_child(holder)
	var s: Control = CareerTasks.open_rich(holder, "copy")
	assert_object(s).is_not_null()
	var got := [-1.0]
	s.task_done.connect(func(q: float, _r: Dictionary) -> void: got[0] = q)
	var lines: Array = _sc.task["doc"]["lines"]
	s.get("_scratch")["copy"] = {"i": 0, "picks": [], "steady": 1.0}
	for i in lines.size():
		s.call("_render_task")
		var l: Dictionary = lines[i]
		_press(s, String(l["options"][int(l["correct"])]))
	_press(s, "Continue")
	assert_float(got[0]).is_greater(0.9)
	# A forgery task is refused to someone with no post (the work shift falls back to its plain widget).
	var free_sc: RefCounted = _hub.mod("scribe")
	free_sc.active = false
	free_sc.task = {}
	assert_object(CareerTasks.open_rich(holder, "forgery")).is_null()
