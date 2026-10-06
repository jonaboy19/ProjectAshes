extends GdUnitTestSuite
## The town kit at scale (S2): 30 hubs are attached, and while the player is far from all of them they must cost nothing per frame
## (cell streamer "settlement" tier: no _process, no polls, props hidden and out of the interaction scan), wake once the player is in
## range and sleep again when he leaves. Roster binding of all towns is a few milliseconds, activation is lazy, and everything the kit
## adds to the save stays small. Numbers are printed as `TOWNPERF` lines (tools_qa/perf/town_kit_perf.gd measures the same on a bigger run).

const TownHub := preload("res://scripts/world/town_kit/town_hub.gd")
const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
## Budget for 30 idle hubs far from the player: average microseconds of hub script per frame, and the worst single frame.
const IDLE_US_PER_FRAME := 40.0
const IDLE_WORST_FRAME_US := 3000


func before() -> void:
	WorldGen.setup(WorldSim.SEED)
	WorldSim.reset()


func before_test() -> void:
	CellStreamer.reset_shared()
	QuestHub.reset()
	QuestBus.reset_shared()
	TownHub.prof = false


func after_test() -> void:
	TownHub.prof = false
	CellStreamer.reset_shared()
	QuestHub.reset()
	QuestBus.reset_shared()
	preload("res://scripts/core/node_pool.gd").clear_all()


## The dry point furthest from every settlement (a coarse grid over the world).
func _far_spot() -> Vector2:
	var far := Vector2.ZERO
	var best := -1.0
	for gx in range(-3000, 3001, 250):
		for gz in range(-3000, 3001, 250):
			var p := Vector2(gx, gz)
			var m := INF
			for s in WorldGen.settlements:
				m = minf(m, p.distance_to(s["pos"]))
			if m > best:
				best = m
				far = p
	return far


func _player_at(p: Vector2) -> Node3D:
	var n := Node3D.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node3D\nvar crouching := false\nvar dead := false\n"
	sc.reload()
	n.set_script(sc)
	n.add_to_group("player")
	add_child(n)
	n.global_position = Vector3(p.x, 0.0, p.y)
	return auto_free(n)


func _focus(cs: RefCounted, p: Vector2) -> void:
	cs.call("update", Vector3(p.x, 0.0, p.y))


func test_thirty_hubs_idle_far_away_cost_under_a_small_budget_per_frame() -> void:
	var cs := CellStreamer.shared()
	var far := _far_spot()
	_player_at(far)
	_focus(cs, far)
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var t0 := Time.get_ticks_usec()
	var hubs := TownHub.attach_all(holder, true)
	var attach_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_int(hubs.size()).is_equal(30)
	var awake := 0
	for h: Node in hubs:
		if h.call("is_awake"):
			awake += 1
			assert_str(String(h.name)).is_equal("ThornfieldHub")        # the hand-made town keeps its own always-on hub
		else:
			assert_bool(h.call("is_active")).override_failure_message(String(h.name) + " was built although nobody came near").is_false()
			assert_bool(h.is_processing()).is_false()
			assert_int(h.get_child_count()).is_equal(0)
	assert_int(awake).is_equal(1)
	TownHub.prof = true
	TownHub.prof_usec = 0
	TownHub.prof_calls = 0
	var frames := 150
	var worst := 0
	for i in frames:
		_focus(cs, far)
		var before := TownHub.prof_usec
		await get_tree().process_frame
		worst = maxi(worst, TownHub.prof_usec - before)
	var avg := float(TownHub.prof_usec) / float(frames)
	print("TOWNPERF idle_30_hubs attach_ms=%.1f nearest_town_m=%.0f hub_us_per_frame=%.2f hub_calls_per_frame=%.2f worst_frame_us=%d" % [
		attach_ms, TownPlaces.settlement("millbrook")["pos"].distance_to(far), avg, float(TownHub.prof_calls) / float(frames), worst])
	assert_float(avg).override_failure_message("30 idle hubs cost %.1f us per frame" % avg).is_less(IDLE_US_PER_FRAME)
	assert_int(worst).override_failure_message("worst idle frame %d us" % worst).is_less(IDLE_WORST_FRAME_US)
	assert_float(float(TownHub.prof_calls) / float(frames)).is_less(1.6)       # only Thornfield's hub runs _process


func test_a_hub_wakes_in_the_settlement_tier_builds_itself_once_and_sleeps_again() -> void:
	var cs := CellStreamer.shared()
	var far := _far_spot()
	var player := _player_at(far)
	_focus(cs, far)
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var hubs := TownHub.attach_all(holder, true)
	var mill: Node = null
	for h: Node in hubs:
		if String(h.get("tid")) == "millbrook":
			mill = h
	assert_bool(mill.call("is_awake")).is_false()
	var c: Vector2 = TownPlaces.settlement("millbrook")["pos"]
	player.global_position = Vector3(c.x, 0.0, c.y)
	_focus(cs, c)
	assert_bool(mill.call("is_awake")).is_true()
	assert_bool(mill.call("is_active")).is_true()
	assert_bool(mill.is_processing()).is_true()
	var clues: Array = mill.get("clues")
	assert_int(clues.size()).is_greater(0)
	var stash: Node = (mill.get("stashes") as Array)[0]
	assert_bool((clues[0] as Node3D).visible).is_true()
	assert_bool(clues[0].is_in_group(&"interactable")).is_true()
	await get_tree().process_frame           # the den search (the threat node) takes the frame after the wake
	assert_bool(mill.get("threat") != null).is_true()
	var asleep := 0
	for h: Node in hubs:
		if not h.call("is_awake"):
			asleep += 1
	assert_int(asleep).is_greater_equal(20)        # a town wakes alone (plus any neighbour within range), not the region
	# The wake poll reports the place the player stands in.
	var events: Array = []
	var cb := func(t: StringName, d: Dictionary) -> void: events.append([String(t), d])
	QuestBus.shared().fired.connect(cb)
	mill.call("poll", 0.5)
	QuestBus.shared().fired.disconnect(cb)
	assert_bool(events.any(func(e: Array) -> bool: return e[0] == "enter_area" and String(e[1]["place"]) == "millbrook")).is_true()
	# The player leaves: asleep again, props hidden and out of the interaction scan, nothing rebuilt on the way back.
	_focus(cs, far)
	assert_bool(mill.call("is_awake")).is_false()
	assert_bool(mill.is_processing()).is_false()
	assert_bool((clues[0] as Node3D).visible).is_false()
	assert_bool(clues[0].is_in_group(&"interactable")).is_false()
	assert_bool(stash.is_in_group(&"interactable")).is_false()
	_focus(cs, c)
	assert_bool(mill.call("is_awake")).is_true()
	assert_bool((mill.get("clues") as Array)[0] == clues[0]).is_true()
	assert_bool(clues[0].is_in_group(&"interactable")).is_true()


func test_kit_towns_do_not_run_when_the_streamer_is_not_asked() -> void:
	# Ungated hubs (tests, tools) are always awake and built at once, as before.
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var h: Node = TownHub.attach(holder, "millbrook")
	assert_bool(h.call("is_awake") and h.call("is_active")).is_true()
	assert_bool(h.is_processing()).is_true()


func test_binding_every_roster_is_a_few_milliseconds() -> void:
	var t0 := Time.get_ticks_usec()
	TownRoster.bind_all(true)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("TOWNPERF bind_all_ms=%.1f towns=%d" % [ms, TownData.ids().size()])
	assert_float(ms).override_failure_message("binding 30 rosters took %.1f ms" % ms).is_less(120.0)
	for id: String in TownData.ids():
		var want := 0
		for e: Dictionary in TownData.residents(id):
			if bool(e.get("bind", true)):
				want += 1
		assert_int(TownRoster.rows_of(id).size()).override_failure_message(id).is_equal(want)


func test_what_the_kit_adds_to_the_save_stays_small() -> void:
	(Life.npc_social_graph.get("edges") as Dictionary).clear()          # earlier tests may have seeded the warm ties already
	var before := JSON.stringify(Life.snapshot()).length()
	var dens_before: int = Frontier.ecology.alive_count()
	var holder := Node3D.new()
	add_child(auto_free(holder))
	TownHub.attach_all(holder)         # every hub activated: ties seeded into the social graph, dens placed
	var after := JSON.stringify(Life.snapshot()).length()
	var graph := JSON.stringify(Life.npc_social_graph.serialize()).length()
	print("TOWNPERF save_bytes_before=%d after=%d kit_delta=%d social_graph=%d" % [before, after, after - before, graph])
	assert_int(after - before).override_failure_message("the kit grew the save by %d bytes" % (after - before)).is_less(100000)
	assert_int(graph).is_less(120000)
	# every town keeps a den (reusing one in reach): at most 30 new ones, and the ceiling leaves room for migration on a fresh world
	var alive: int = Frontier.ecology.alive_count()
	print("TOWNPERF dens_alive=%d (+%d) ceiling=%d" % [alive, alive - dens_before, preload("res://scripts/sim/monster_ecology.gd").MAX_ALIVE_DENS])
	assert_int(alive - dens_before).is_less_equal(30)
