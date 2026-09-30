extends GdUnitTestSuite
## C7 acceptance: the story runtime plays Act I to its end through the real director, dialogue runner
## and quest machine with stub world nodes: age gates, talk, area entry, the carve, the safe wolf,
## Kindling Night, the Blessing and the hand-off into Act II. Freedom checks: nothing spawns at a place
## the player has not come near, the tracker can be hidden, and big-creature steps have a parley route.

const Director := preload("res://scripts/region1/r1_story_director.gd")
const Places := preload("res://scripts/region1/region1_places.gd")

var dir: Node
var player: Node3D
var world: Node3D
var spawned: Array = []


class StubGlue extends Node:
	var tutorial = null
	func npc_extra_options(_id: String) -> Array:
		return []


func before_test() -> void:
	Region1State.clear()
	Places.clear()
	spawned = []
	world = auto_free(Node3D.new())
	player = auto_free(Node3D.new())
	player.add_to_group("player")
	add_child(world)
	add_child(player)
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	for k in Life.life_path.flags.keys():
		if String(k).begins_with("r1."):
			Life.life_path.flags.erase(k)
	dir = auto_free(Director.new())
	var glue: Node = auto_free(StubGlue.new())
	add_child(glue)
	add_child(dir)
	dir.setup(glue, null, player, world)
	dir.spawn_override = func(target: String, at: Vector2, n: int, place: String) -> void: spawned.append([target, place])
	# Everything the quest names sits in a line east of the origin, well apart.
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


func _talk_until_quiet(npc: String) -> void:
	dir.talk_through(npc, Callable(self, "_pick_useful"))


## The choice that sets a flag the story still wants, else one that goes somewhere unseen, else the first.
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


func _step_done(id: String) -> bool:
	return dir.story.is_done(id)


func test_the_quest_starts_at_eight_not_before() -> void:
	Life.life_path.set_age(6, WorldSim.day, WorldSim.time_of_day)
	dir._on_tick()
	assert_bool(dir.story.is_active("a1_dark_stone")).is_false()
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	dir._on_tick()
	assert_bool(dir.story.is_active("a1_dark_stone")).is_true()


## A scripted player: does whatever the active step's open objective asks, the way the game's own systems
## would report it (area entry, a carve through the stone menu, a kill, the festival, growing up), and talks to
## whoever offers a conversation. Returns the step ids in the order they finished.
func _autoplay(until_step: String, max_rounds := 80) -> Array[String]:
	var order: Array[String] = []
	for round in max_rounds:
		dir._on_tick()
		for s: Dictionary in dir.story.steps:
			var sid := String(s["id"])
			if dir.story.is_done(sid) and not order.has(sid):
				order.append(sid)
		if dir.story.is_done(until_step):
			break
		var acted := false
		for sid: String in dir.story.active_steps():
			var st: Dictionary = dir.story.step(sid)
			var o: Dictionary = dir.story.current_objective(sid)
			var t := String(o.get("type", ""))
			match t:
				"enter_area":
					_goto(String(o["place"]))
					acted = true
				"carve":
					dir.notify(&"carve", {"glyph": o["glyph"], "stone": o["stone"], "amount": 1})
					acted = true
				"kill":
					var p: Vector2 = Places.position_of(String(o.get("place", st["place"])))
					Life.region1_kill.emit(String(o["target"]), Vector3(p.x, 0.0, p.y))
					acted = true
				"festival":
					dir.notify(&"festival", {"festival": o["festival"]})
					acted = true
				"age":
					Life.life_path.set_age(int(o["min"]), WorldSim.day, 8.0)
					WorldSim.time_of_day = 8.0
					acted = true
				"cutscene_done":
					dir.notify(&"cutscene_done", {"cutscene": o["cutscene"]})
					acted = true
		# Whoever has something to say, at their place, gets a visit.
		for h: Dictionary in dir.hosts_with_talk():
			_goto(String(h["place"]))
			_talk_until_quiet(String(h["npc"]))
			acted = true
		if not acted:
			break
	return order


func test_act_one_plays_to_the_end() -> void:
	WorldSim.time_of_day = 8.0
	Life.life_path.set_age(8, WorldSim.day, WorldSim.time_of_day)
	var order := _autoplay("a1_after_blessing")
	for id in ["a1_dark_stone", "a1_first_glyph", "a1_hesks_ember", "a1_wolf_at_dusk", "a1_thistle", "a1_staff_yard",
			"a1_kindling", "a1_blessing_eve", "a1_blessing", "a1_after_blessing"]:
		assert_bool(order.has(id)).override_failure_message("step %s never finished (done: %s, active: %s)" % [id, order, dir.story.active_steps()]).is_true()
	# Order is the story's order.
	assert_int(order.find("a1_first_glyph")).is_less(order.find("a1_hesks_ember"))
	assert_int(order.find("a1_wolf_at_dusk")).is_less(order.find("a1_blessing"))
	# The wolf and the fawn came out at the ring, and only once the player was there.
	var targets: Array = spawned.map(func(sp: Array) -> String: return String(sp[0]))
	assert_bool(targets.has("wolf")).is_true()
	assert_bool(targets.has("stagborn_fawn")).is_true()
	# Act II has begun; the journal tells Act I, the tracker shows the next step.
	assert_bool(dir.story.is_active("a2_three_letters")).is_true()
	assert_int((dir.journal_page()["entries"] as Array).size()).is_greater(8)
	assert_bool(dir.tracked_quest().is_empty()).is_false()


func test_nothing_is_spawned_for_a_player_who_stays_away() -> void:
	dir._on_tick()
	_talk_until_quiet("mother")
	dir.story.status["a1_hesks_ember"] = "done"
	dir._handle([{"type": "action", "step": "a1_hesks_ember", "action": ["spawn", "wolf", "ashford_ring", 1]}])
	player.global_position = Vector3(-3000, 0, 0)
	dir._on_tick()
	assert_int(spawned.size()).is_equal(0)   # the wolf waits for the player; nothing is forced on a far traveller


func test_tracker_is_text_and_can_be_hidden() -> void:
	dir._on_tick()
	var t: Dictionary = dir.tracked_quest()
	assert_bool(t.is_empty()).is_false()
	var rows: Array = t["objectives"]
	assert_int(rows.size()).is_greater(0)
	dir.set_tracker_hidden(true)
	assert_bool(dir.tracked_quest().is_empty()).is_true()
	assert_object(dir.compass_target()).is_null()
	dir.set_tracker_hidden(false)


func test_story_state_survives_a_save() -> void:
	dir._on_tick()
	_talk_until_quiet("mother")
	assert_bool(_step_done("a1_dark_stone")).is_true()
	var snap := JSON.parse_string(JSON.stringify(Region1State.snapshot())) as Dictionary
	dir.story.status.clear()
	Region1State.restore(snap)
	assert_bool(dir.story.is_done("a1_dark_stone")).is_true()
	assert_bool(dir.story.is_active("a1_first_glyph")).is_true()


func test_big_creature_steps_offer_a_parley_route() -> void:
	# Jump to the Warden's trial in a scratch quest state: the defeat objective must be reachable without a fight.
	dir.story.status["a4_glade_trial"] = "active"
	dir.story.progress["a4_glade_trial"] = {"_done_wren": true, "_done_told": true}
	assert_int(dir.parley_targets().size()).is_equal(1)
	assert_str(String(dir.parley_targets()[0]["target"])).is_equal("antlered_warden")
	assert_bool(dir.parley("antlered_warden")).is_true()
	assert_bool(dir.story.objective_done("a4_glade_trial", "trial")).is_true()


func test_kill_events_reach_the_quest_with_their_place() -> void:
	dir.story.status["a1_wolf_at_dusk"] = "active"
	dir.story.progress["a1_wolf_at_dusk"] = {}
	var ring: Vector2 = Places.position_of("ashford_ring")
	Life.region1_kill.emit("wolf", Vector3(ring.x + 10.0, 0, ring.y))
	assert_bool(dir.story.objective_done("a1_wolf_at_dusk", "wolf")).is_true()
