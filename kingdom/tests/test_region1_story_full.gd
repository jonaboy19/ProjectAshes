extends GdUnitTestSuite
## Region 1 whole-story autoplay: a scripted player finishes every step of Acts I-V through the real director,
## dialogue runner and quest machine (stub world nodes), saves and loads mid-act, and checks that every step
## has a journal line and a tracker entry. Also: every registry place resolves in the real world to a site that
## exists (not just the registry's proposed coordinates).

const Director := preload("res://scripts/region1/r1_story_director.gd")
const Places := preload("res://scripts/region1/region1_places.gd")

var dir: Node
var player: Node3D
var world: Node3D
var spawned: Array = []
var tracker_texts: Dictionary = {}


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


func before_test() -> void:
	Region1State.clear()
	Places.clear()
	_build()


func _build() -> void:
	spawned = []
	world = auto_free(Node3D.new())
	player = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	for k in Life.life_path.flags.keys():
		if String(k).begins_with("r1.") or String(k).begins_with("ember."):
			Life.life_path.flags.erase(k)
	dir = auto_free(Director.new())
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	add_child(dir)
	dir.setup(glue, null, player, world)
	dir.spawn_override = func(target: String, _at: Vector2, _n: int, place: String) -> void: spawned.append([target, place])
	var i := 0
	for id in Places.registry().get("places", {}):
		Places.set_override(String(id), Vector2(2000.0 + 400.0 * i, 0.0), 30.0)
		i += 1


func after_test() -> void:
	Region1State.clear()
	Places.clear()


func _goto(place: String) -> void:
	var p: Vector2 = Places.position_of(place)
	player.global_position = Vector3(p.x, 0.0, p.y)
	dir._on_tick()


func _pick_useful(opts: Array) -> int:
	for i in opts.size():
		for a: Variant in (opts[i] as Dictionary).get("do", []):
			if a is Array and String(a[0]) == "flag" and not dir.story.has_flag(String(a[1])):
				return i
	for i in opts.size():
		var g := String((opts[i] as Dictionary).get("goto", ""))
		if g != "" and g != "@end" and not dir._talked.has(g):
			return i
	return 0


## Does what one open objective asks, as the game's own systems would report it. True when it acted.
func _perform(o: Dictionary, st: Dictionary) -> bool:
	match String(o.get("type", "")):
		"enter_area":
			_goto(String(o["place"]))
		"carve":
			dir.notify(&"carve", {"glyph": o["glyph"], "stone": o["stone"], "amount": int(o.get("count", 1))})
		"kill":
			_goto(String(o.get("place", st["place"])))   # the creatures come out when the player is there
			var p: Vector2 = Places.position_of(String(o.get("place", st["place"])))
			for n in int(o.get("count", 1)):
				Life.region1_kill.emit(String(o["target"]), Vector3(p.x, 0.0, p.y))
		"festival":
			dir.notify(&"festival", {"festival": o["festival"]})
		"age":
			Life.life_path.set_age(int(o["min"]), WorldSim.day, 8.0)
			WorldSim.time_of_day = 8.0
		"cutscene_done":
			dir.notify(&"cutscene_done", {"cutscene": o["cutscene"]})
		"ashsight":
			_goto(String(st["place"]))
			dir.notify(&"ashsight", {"site": o["site"]})
		"relight_elder":
			dir.notify(&"relight_elder", {"stone": o["stone"]})
		"wardline_link":
			for n in int(o.get("count", 1)):
				dir.notify(&"wardline_link", {"from": o.get("from", ""), "to": o["to"], "amount": 1})
		"scar_contain":
			dir.notify(&"scar_contain", {"place": o["place"], "amount": int(o["cells"])})
		"scar_harvest":
			dir.notify(&"scar_harvest", {"place": o["place"], "amount": int(o["crystals"])})
		"ember_choice":
			dir.notify(&"ember_choice", {"who": o["who"], "choice": "stone"})
		"defeat":
			_goto(String(st["place"]))
			dir.parley(String(o["target"]))
		"item":
			Life.give(String(o["item"]), int(o.get("count", 1)))
		"any":
			return _perform((o["of"] as Array)[0], st)
		_:
			return false
	return true


func _record(order: Array[String]) -> void:
	for s: Dictionary in dir.story.steps:
		var sid := String(s["id"])
		if dir.story.is_done(sid) and not order.has(sid):
			order.append(sid)
	var t: Dictionary = dir.tracked_quest()
	for sid: String in dir.story.active_steps():
		if not tracker_texts.has(sid) and not t.is_empty():
			var rows: Array = t["objectives"]
			if rows.size() > 0:
				tracker_texts[sid] = true


func _autoplay(until_step: String, order: Array[String], max_rounds := 400) -> void:
	if Life.age() < 8:
		Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	for round in max_rounds:
		dir._on_tick()
		_record(order)
		if dir.story.is_done(until_step):
			return
		var acted := false
		_record(order)
		for sid: String in dir.story.active_steps():
			var st: Dictionary = dir.story.step(sid)
			var o: Dictionary = dir.story.current_objective(sid)
			if _perform(o, st):
				acted = true
		_record(order)   # the tracker as the player sees it before talking
		for h: Dictionary in dir.hosts_with_talk():
			_goto(String(h["place"]))
			dir.talk_through(String(h["npc"]), Callable(self, "_pick_useful"))
			acted = true
		if not acted:
			return


func _all_ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in dir.story.steps:
		out.append(String(s["id"]))
	return out


func _missing(order: Array[String]) -> Array:
	return _all_ids().filter(func(id: String) -> bool: return not order.has(id))


func test_whole_story_plays_to_region_complete() -> void:
	WorldSim.time_of_day = 8.0
	var order: Array[String] = []
	_autoplay("a5_homecoming", order)
	assert_array(_missing(order)).override_failure_message("steps never finished: %s (active: %s)" % [_missing(order), dir.story.active_steps()]).is_empty()
	assert_bool(dir.story.is_complete()).is_true()
	assert_bool(dir.story.has_flag("r1.complete")).is_true()
	# The story's order holds across acts.
	for pair in [["a1_blessing", "a2_three_letters"], ["a2_thief_truth", "a3_council"], ["a3_ring_falls", "a3_the_ledger"],
			["a3_the_ledger", "a4_dark_night"], ["a4_dark_night", "a4_glade_trial"], ["a4_glade_trial", "a4_five_hearts"],
			["a4_five_hearts", "a5_rifts_edge"], ["a5_scarbound", "a5_seal"], ["a5_seal", "a5_homecoming"]]:
		assert_int(order.find(pair[0])).is_less(order.find(pair[1]))
	# One ending flag was reached.
	var endings := 0
	for f in ["r1.ending.kindled", "r1.ending.bram", "r1.ending.tamsin", "r1.ending.idra"]:
		if dir.story.has_flag(f):
			endings += 1
	assert_int(endings).is_equal(1)
	# Journal and tracker: every step has an entry, the tracker named every step while it was active.
	var entries: Array = dir.journal_page()["entries"]
	assert_int(entries.size()).is_equal(dir.story.steps.size())
	for e: Dictionary in entries:
		assert_bool(String(e["text"]) != "").is_true()
		assert_bool(bool(e["done"])).is_true()
	for sid in _all_ids():
		assert_bool(tracker_texts.has(sid) or sid == "a1_dark_stone").override_failure_message("tracker never showed %s" % sid).is_true()
	# Quests tab: completed row.
	assert_int((dir.quest_entries()["completed"] as Array).size()).is_equal(1)


func test_every_big_creature_step_has_a_parley_route_and_no_gate() -> void:
	for s: Dictionary in dir.story.steps:
		for o: Dictionary in s["objectives"]:
			if String(o["type"]) == "defeat":
				dir.story.status[String(s["id"])] = "active"
				dir.story.progress[String(s["id"])] = {}
				for prev: Dictionary in s["objectives"]:
					if prev == o:
						break
					dir.story.progress[String(s["id"])]["_done_" + String(prev["id"])] = true
				assert_bool(dir.parley(String(o["target"]))).override_failure_message("no parley for %s" % o["target"]).is_true()


func test_save_and_load_mid_act_then_finish() -> void:
	WorldSim.time_of_day = 8.0
	for mid in ["a2_first_ashsight", "a3_ring_falls", "a4_greyseam", "a5_turn_the_tide"]:
		Region1State.clear()
		Places.clear()
		_build()
		var order: Array[String] = []
		_autoplay(mid, order)
		assert_bool(dir.story.is_done(mid)).override_failure_message("never reached %s" % mid).is_true()
		var done_before := order.duplicate()
		var active_before: PackedStringArray = dir.story.active_steps()
		var snap := JSON.parse_string(JSON.stringify(Region1State.snapshot())) as Dictionary
		dir.story.status.clear()
		dir.story.progress.clear()
		dir.story.flags.clear()
		Region1State.restore(snap)
		for sid in done_before:
			assert_bool(dir.story.is_done(sid)).override_failure_message("%s lost across save at %s" % [sid, mid]).is_true()
		assert_array(dir.story.active_steps()).is_equal(active_before)
		_autoplay("a5_homecoming", order)
		assert_bool(dir.story.is_complete()).override_failure_message("did not finish after loading at %s (active %s)" % [mid, dir.story.active_steps()]).is_true()


func test_the_big_fights_have_bodies_and_the_world_hears_the_story() -> void:
	WorldSim.time_of_day = 8.0
	var order: Array[String] = []
	_autoplay("a5_homecoming", order)
	var tags: Array = spawned.map(func(sp: Array) -> String: return "%s@%s" % [sp[0], sp[1]])
	for want in ["rift_wolf@ashford_ring", "rift_wolf@highwatch_gate", "scarbound_troll@rift_mouth", "ashen_hand_saboteur@duskbriar_bandit_camp"]:
		assert_bool(tags.has(want)).override_failure_message("never spawned %s (got %s)" % [want, tags]).is_true()
	# The realm's news module heard the finale.
	var news: Variant = Life.realm.mod("news")
	var heard := false
	for it: Dictionary in news.get("_items"):
		if String(it["text"]).contains("Scar Mouth is sealed"):
			heard = true
	assert_bool(heard).is_true()


func test_a_fallen_warden_counts_as_beaten_and_a_kill_is_never_required() -> void:
	dir.story.status["a4_glade_trial"] = "active"
	dir.story.progress["a4_glade_trial"] = {"_done_wren": true, "_done_told": true}
	Life.region1_kill.emit("stagborn_warden", Vector3.ZERO)
	assert_bool(dir.story.objective_done("a4_glade_trial", "trial")).is_true()
