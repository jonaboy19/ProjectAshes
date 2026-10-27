extends GdUnitTestSuite
## Frame-spike pass (2026-10-06, docs/qa/CPU_MEMORY_SAVE.md section 8): the async autosave (snapshot over frames, worker-thread
## write, synchronous fallback), Life's snapshot steps (nothing live in what a worker stringifies), the one-body-per-frame
## spawn queues, the background NodePool trim and the spread settlement build.

const SaveManager := preload("res://scripts/sim/save_manager.gd")
const NodePool := preload("res://scripts/core/node_pool.gd")
const TEST_DIR := "user://test_saves_hitch/"

var _mgr: SaveManager
var _state: Dictionary
var _saved: Array = []


func before_test() -> void:
	_clear_dir()
	_saved = []
	_state = {"world": {"day": 1, "time": 8.0}, "game": {"gold": 0}}
	_mgr = SaveManager.new()
	_mgr.root_dir = TEST_DIR
	_mgr.capture_thumbnails = false
	_mgr.async_autosave = true
	_mgr.snapshot_fn = func() -> Dictionary: return _state.duplicate(true)
	_mgr.restore_fn = func(d: Dictionary) -> void: _state = (d as Dictionary).duplicate(true)
	_mgr.saved.connect(func(id: String, ok: bool) -> void: _saved.append([id, ok]))
	add_child(_mgr)
	auto_free(_mgr)
	var actor := Node3D.new()
	add_child(actor)
	auto_free(actor)
	_mgr.player_override = actor


func after_test() -> void:
	if is_instance_valid(_mgr):
		_mgr.flush()
	_clear_dir()


func _clear_dir() -> void:
	var abs := ProjectSettings.globalize_path(TEST_DIR)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			d.remove(f)
		f = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)


func _big_state(day: int) -> Dictionary:
	var rows: Array = []
	for i in 2500:
		rows.append({"id": "row_%d" % i, "n": i, "tags": ["a", "b"], "name": "Resident number %d of the realm" % i})
	return {"world": {"day": day, "time": 9.5}, "game": {"gold": 12}, "realm": {"rows": rows}}


func _pump_until_idle(max_frames := 400) -> int:
	var frames := 0
	while _mgr.busy() and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	return frames


# --- async autosave ----------------------------------------------------------------------------------

func test_an_async_autosave_returns_at_once_and_round_trips_through_the_worker() -> void:
	_state = _big_state(5)
	var id := _mgr.autosave("timer", false, true)
	assert_str(id).is_not_empty()
	assert_bool(_mgr.busy()).is_true()                              # nothing was written inside the call
	assert_bool(FileAccess.file_exists(_mgr.path_of(id))).is_false()
	await _pump_until_idle()
	assert_bool(_mgr.busy()).is_false()
	assert_bool(FileAccess.file_exists(_mgr.path_of(id))).is_true()
	assert_array(_saved).contains([[id, true]])
	assert_str(FileAccess.get_file_as_string(_mgr.path_of(id))).contains('"enc":"zstd"')      # compressed, checksummed, enveloped as ever
	var before := _state.duplicate(true)
	_state = {}
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_str(JSON.stringify(_state)).is_equal(JSON.stringify(JSON.parse_string(JSON.stringify(before))))
	assert_bool(FileAccess.file_exists(_mgr.meta_path(id))).is_true()


func test_the_atomic_write_keeps_the_backup_across_async_autosaves() -> void:
	var last := ""
	for i in 4:                                                     # 3 rotating slots: the 4th overwrites the 1st
		_state = _big_state(i + 1)
		_mgr.reset_autosave_clock()
		last = _mgr.autosave("timer", false, true)
		await _pump_until_idle()
	assert_bool(FileAccess.file_exists(_mgr.path_of(last))).is_true()
	assert_bool(FileAccess.file_exists(_mgr.path_of(last) + ".bak")).is_true()
	assert_bool(FileAccess.file_exists(_mgr.path_of(last) + ".tmp")).is_false()
	var env := _mgr.read_slot(last)
	assert_int(int(env["data"]["world"]["day"])).is_equal(4)


func test_the_snapshot_is_collected_a_few_steps_per_frame() -> void:
	var counter := [0]
	var steps: Array = []
	for i in 40:
		steps.append([("world" if i == 0 else ("game" if i == 1 else "s%d" % i)), func() -> Variant:
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < 700:        # 0.7 ms each: a 2.5 ms budget takes 4 per frame
				pass
			counter[0] += 1
			return {"i": counter[0]}])
	_mgr.steps_fn = func() -> Array: return steps
	_mgr.reset_autosave_clock()
	var id := _mgr.autosave("timer", false, true)
	assert_str(id).is_not_empty()
	var per_frame: Array = []
	var frames := 0
	while _mgr.busy() and frames < 200:
		var before: int = counter[0]
		await get_tree().process_frame
		per_frame.append(counter[0] - before)
		frames += 1
	assert_int(counter[0]).is_equal(40)
	var worst := 0
	for n: int in per_frame:
		worst = maxi(worst, n)
	assert_int(worst).is_less_equal(8)                              # never all 40 in one frame
	assert_int(frames).is_greater(4)
	var env := _mgr.read_slot(id)
	assert_int((env["data"] as Dictionary).size()).is_equal(40)


func test_a_failed_worker_falls_back_to_a_synchronous_write() -> void:
	_state = _big_state(9)
	_mgr.test_fail_worker = true
	var id := _mgr.autosave("timer", false, true)
	await _pump_until_idle()
	assert_bool(FileAccess.file_exists(_mgr.path_of(id))).is_true()    # the main thread wrote the same state itself
	assert_array(_saved).contains([[id, true]])
	assert_int(int(_mgr.read_slot(id)["data"]["world"]["day"])).is_equal(9)


func test_an_unwritable_folder_reports_the_failure_and_leaves_no_job() -> void:
	_mgr.root_dir = "user://test_saves_hitch_blocker.json/inner/"
	var f := FileAccess.open("user://test_saves_hitch_blocker.json", FileAccess.WRITE)
	f.store_string("a file where the folder should be")
	f.close()
	_mgr.reset_autosave_clock()
	var id := _mgr.autosave("timer", false, true)
	assert_str(id).is_equal("")
	assert_bool(_mgr.busy()).is_false()
	assert_str(_mgr.last_error).is_not_empty()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves_hitch_blocker.json"))


func test_quit_pause_and_focus_saves_stay_synchronous_and_finish_a_running_job() -> void:
	_state = _big_state(3)
	var first := _mgr.autosave("timer", false, true)
	assert_bool(_mgr.busy()).is_true()
	_state = _big_state(4)
	var second := _mgr.autosave("quit", false, true)               # the app may die right after: on disk before it returns
	assert_bool(_mgr.busy()).is_false()
	assert_bool(FileAccess.file_exists(_mgr.path_of(first))).is_true()
	assert_bool(FileAccess.file_exists(_mgr.path_of(second))).is_true()
	assert_int(int(_mgr.read_slot(second)["data"]["world"]["day"])).is_equal(4)


func test_a_load_or_manual_save_flushes_the_running_autosave_first() -> void:
	_state = _big_state(6)
	var id := _mgr.autosave("timer", false, true)
	assert_bool(_mgr.busy()).is_true()
	assert_bool(_mgr.load_slot(id)).is_true()                      # read_slot flushes: the autosave is complete, not half written
	assert_bool(_mgr.busy()).is_false()
	assert_int(int(_state["world"]["day"])).is_equal(6)
	_state = _big_state(7)
	_mgr.reset_autosave_clock()
	_mgr.autosave("timer", false, true)
	assert_bool(_mgr.save_slot(SaveManager.manual_id(1))).is_true()
	assert_bool(_mgr.busy()).is_false()


func test_changes_made_while_the_worker_runs_keep_the_game_dirty() -> void:
	_state = _big_state(2)
	_mgr.mark_dirty()
	_mgr.autosave("timer", false, true)
	_mgr.mark_dirty()                                               # after the snapshot began
	await _pump_until_idle()
	assert_bool(_mgr.dirty).is_true()
	_mgr.reset_autosave_clock()
	_mgr.autosave("timer", false, true)
	await _pump_until_idle()
	assert_bool(_mgr.dirty).is_false()


func test_a_second_autosave_while_one_runs_is_skipped() -> void:
	_state = _big_state(2)
	var first := _mgr.autosave("timer", false, true)
	assert_str(first).is_not_empty()
	assert_str(_mgr.autosave("enter:Town", false)).is_equal("")
	await _pump_until_idle()


# --- Life's snapshot steps: nothing in the result is a live container -------------------------------

func test_life_snapshot_steps_equal_snapshot_and_hold_no_live_references() -> void:
	var steps: Array = Life.snapshot_steps()
	assert_int(steps.size()).is_greater(40)
	var plain := Life.snapshot()
	var d := {}
	for st: Array in steps:                                      # what the async autosave collects (small sections deep-copied)
		var v: Variant = (st[1] as Callable).call()
		if v != null:
			SaveManager.put(d, String(st[0]), v)
	assert_int(d.size()).is_equal(plain.size())
	for k: String in plain:
		assert_bool(d.has(k)).is_true()
		if k != "interactives":                                  # holds clock-relative ms values that move between two calls
			assert_str(JSON.stringify(d[k])).is_equal(JSON.stringify(plain[k]))
	assert_bool(d.has("world") and d.has("game") and d.has("economy") and d.has("realm") and d.has("inventory")).is_true()
	# What a worker thread stringifies later must not change when the game moves on.
	var text_before := JSON.stringify(d)
	Life.give("bread", 3)
	Game.add_gold(25)
	Life.appearance["route_probe"] = 1
	WorldSim.advance_hours(3.0)
	Life.record("traded", 1.0)
	assert_str(JSON.stringify(d)).is_equal(text_before)
	Life.appearance.erase("route_probe")


# --- spawn queues -------------------------------------------------------------------------------------

func test_the_population_spawns_at_most_one_body_per_frame_nearest_first() -> void:
	var pl := PopulationLOD.new()
	add_child(auto_free(pl))
	pl.setup(ImpostorBaker.new())
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	pl.focus = Vector3(home.x, 0.0, home.y)
	WorldSim.time_of_day = 12.0
	pl.refresh()
	assert_int(pl.full_count).is_equal(0)                       # refresh only queues
	var queued := pl.queued_spawns()
	assert_int(queued).is_greater(2)
	var built: Array = []
	for i in 3:
		var before := pl.full_count
		pl._drain_spawns()
		built.append(pl.full_count - before)
	assert_array(built).is_equal([1, 1, 1])
	assert_int(pl.queued_spawns()).is_less_equal(queued - 3)
	pl.flush_spawns()
	assert_int(pl.queued_spawns()).is_equal(0)
	assert_int(pl.full_count).is_greater(2)


func test_a_queued_body_nobody_wants_any_more_is_dropped() -> void:
	var pl := PopulationLOD.new()
	add_child(auto_free(pl))
	pl.setup(ImpostorBaker.new())
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	pl.focus = Vector3(home.x, 0.0, home.y)
	WorldSim.time_of_day = 12.0
	pl.refresh()
	assert_int(pl.queued_spawns()).is_greater(0)
	pl.focus = Vector3(home.x + 6000.0, 0.0, home.y + 6000.0)   # a teleport away before any body was built
	pl.refresh()
	pl.flush_spawns()
	assert_int(pl.queued_spawns()).is_equal(0)
	assert_int(pl.full_count).is_equal(0)


func test_queue_spawns_false_builds_in_the_refresh_like_before() -> void:
	var pl := PopulationLOD.new()
	add_child(auto_free(pl))
	pl.setup(ImpostorBaker.new())
	pl.queue_spawns = false
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	pl.focus = Vector3(home.x, 0.0, home.y)
	WorldSim.time_of_day = 12.0
	pl.refresh()
	assert_int(pl.full_count).is_greater(2)
	assert_int(pl.queued_spawns()).is_equal(0)


# --- node pool background trim --------------------------------------------------------------------

func test_the_pool_trim_frees_one_long_idle_body_per_step_and_keeps_the_rest() -> void:
	var pool: RefCounted = NodePool.shared("hitch_trim", func() -> Node: return Node3D.new(), 40, false)
	var held: Array = []
	for i in 20:
		held.append(pool.acquire())
	for n: Node in held:
		pool.release(n)
	assert_int(pool.idle_count()).is_equal(20)
	assert_int(NodePool.trim_step()).is_equal(0)                  # freshly idle: nothing is old enough
	assert_int(pool.idle_count()).is_equal(20)
	for n: Node in pool._idle:                                    # pretend they have been idle for two minutes
		n.set_meta(NodePool.IDLE_META, Time.get_ticks_msec() - 120000)
	var freed := 0
	for i in 40:
		freed += NodePool.trim_step()
	assert_int(freed).is_greater_equal(20 - NodePool.BG_KEEP)
	assert_int(pool.idle_count()).is_equal(NodePool.BG_KEEP)
	assert_int(NodePool.trim_step()).is_equal(0)
	pool.clear()


func test_a_requested_trim_ignores_the_idle_age_and_drains_a_body_at_a_time() -> void:
	var pool: RefCounted = NodePool.shared("hitch_trim2", func() -> Node: return Node3D.new(), 40, false)
	var held: Array = []
	for i in 12:
		held.append(pool.acquire())
	for n: Node in held:
		pool.release(n)
	NodePool.request_trim(3)
	assert_bool(NodePool.trim_pending()).is_true()
	assert_int(pool.idle_count()).is_equal(12)
	var steps := 0
	while NodePool.trim_pending() and steps < 100:
		NodePool.trim_step()
		steps += 1
	assert_int(pool.idle_count()).is_equal(3)
	pool.clear()


# --- spread settlement build ----------------------------------------------------------------------

func test_a_spread_settlement_build_finishes_over_frames_and_announces_itself() -> void:
	var sb := SettlementBuilder.new()
	add_child(auto_free(sb))
	var village: Dictionary = {}
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "village":
			village = s
			break
	assert_bool(village.is_empty()).is_false()
	var done: Array = []
	sb.settlement_built.connect(func(st: Dictionary, root: Node3D) -> void: done.append([st["id"], root]))
	sb.focus = Vector3(village["pos"].x, 0.0, village["pos"].y)
	sb.update_now(true)
	assert_int(done.size()).is_equal(0)                            # only the first phase ran in this call
	var first_children := (sb.get_child(0) as Node3D).get_child_count()
	var frames := 0
	while done.is_empty() and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_int(done.size()).is_equal(1)
	assert_int(frames).is_greater(5)                               # several frames, not one
	var root: Node3D = done[0][1]
	assert_int(root.get_child_count()).is_greater(first_children)
	assert_object(sb._spreading_root).is_null()
	sb.finish_prop_jobs()


# --- a step may ask to be run again next frame (Life waits for the realm pump instead of settling hour jobs itself) -------------

func test_a_step_that_answers_retry_is_asked_again_on_the_next_frame() -> void:
	var calls := [0]
	var steps: Array = [["world", func() -> Variant: return {"day": 1}], ["game", func() -> Variant:
		calls[0] += 1
		return SaveManager.RETRY if calls[0] < 4 else {"gold": 3}]]
	_mgr.steps_fn = func() -> Array: return steps
	_mgr.reset_autosave_clock()
	var id := _mgr.autosave("timer", false, true)
	assert_str(id).is_not_empty()
	var frames := await _pump_until_idle()
	assert_int(calls[0]).is_equal(4)
	assert_int(frames).is_greater_equal(3)                       # three retries, a frame each
	assert_int(int(_mgr.read_slot(id)["data"]["game"]["gold"])).is_equal(3)


func test_a_flush_does_not_wait_for_frames_on_a_retrying_step() -> void:
	var calls := [0]
	var steps: Array = [["world", func() -> Variant: return {"day": 1}], ["game", func() -> Variant:
		calls[0] += 1
		return SaveManager.RETRY if calls[0] < 40 else {"gold": 9}]]
	_mgr.steps_fn = func() -> Array: return steps
	_mgr.reset_autosave_clock()
	var id := _mgr.autosave("timer", false, true)
	_mgr.flush()
	assert_bool(_mgr.busy()).is_false()
	assert_int(int(_mgr.read_slot(id)["data"]["game"]["gold"])).is_equal(9)


# --- squads, door, outpost, region bake ---------------------------------------------------------------

func test_a_spread_squad_builds_one_soldier_per_frame() -> void:
	var host := Node3D.new()
	add_child(auto_free(host))
	var sq := Squad.new().setup(1, "raider", "Barbarian", [] as Array[String])
	host.add_child(sq)
	sq.add_soldiers(5, Vector3(0, 0, 0), [], true)
	assert_int(sq.alive()).is_equal(0)                           # nothing yet: queued
	var seen: Array = []
	for i in 7:
		await get_tree().process_frame
		seen.append(sq.alive())
	assert_array(seen.slice(0, 5)).is_equal([1, 2, 3, 4, 5])
	assert_int(sq.alive()).is_equal(5)
	var sq2 := Squad.new().setup(1, "raider", "Barbarian", [] as Array[String])
	host.add_child(sq2)
	sq2.add_soldiers(3, Vector3(20, 0, 0))                       # default: all at once, as before
	assert_int(sq2.alive()).is_equal(3)


func test_a_player_pressed_door_enters_the_room_one_frame_later() -> void:
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	host.add_child(player)
	var door := InteriorDoor.new()
	door.interior_scene = "res://scenes/interiors/chapel_interior.tscn"
	host.add_child(door)
	Assets.scene(door.interior_scene)                            # a room already in memory (the threaded loader queues an uncached one first: test_threaded_region)
	door.enter(player, true)
	assert_object(InteriorDoor.active).is_null()                 # instanced, not yet in the world
	assert_object(door.interior).is_not_null()
	door.enter(player, true)                                     # a second press in the same frame does nothing
	await get_tree().process_frame
	assert_object(InteriorDoor.active).is_equal(door)
	assert_bool(door.interior.is_inside_tree()).is_true()
	door.leave()
	assert_object(InteriorDoor.active).is_null()


func test_the_outpost_builds_in_four_frames_and_sync_builds_at_once() -> void:
	var fort: Node3D = auto_free(load("res://scripts/world/thornfield/outpost.gd").new())
	add_child(fort)
	assert_bool(fort.matches_career()).is_true()
	fort.build(true)
	assert_bool(fort.built).is_true()
	assert_object(fort.palisade).is_not_null()                   # step 0 (palisade and gates) ran in the call
	assert_int(fort.find_children("Watchtower*", "MeshInstance3D", true, false).size()).is_equal(0)     # towers come in step 1
	assert_object(fort.captain).is_null()
	for i in 5:
		await get_tree().process_frame
	assert_int(fort.find_children("Watchtower*", "MeshInstance3D", true, false).size()).is_equal(2)
	assert_object(fort.captain).is_not_null()
	assert_object(fort.barracks_door).is_not_null()
	# the garrison: sync by default (4-6 at once), one per frame when asked
	var sol: Array = fort.spawn_garrison(true)
	assert_int(sol.size()).is_less(4)
	for i in 10:
		await get_tree().process_frame
	assert_int(fort.soldiers().size()).is_between(4, 6)
	fort.despawn_garrison()


func test_the_region_bake_job_gives_the_same_result_in_slices_as_at_once() -> void:
	var results: Array = []
	for budget in [-1.0, 0.2]:
		var rd := RegionDressing.new()
		add_child(auto_free(rd))
		var root := Node3D.new()
		rd.add_child(root)
		root.set_meta("site_id", 9000 + (0 if budget < 0.0 else 1))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		for i in 60:
			var holder := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.set_surface_override_material(0, mat)
			holder.add_child(mi)
			holder.set_meta("bakeable", true)
			root.add_child(holder)
			holder.position = Vector3(i * 2.0, 0, 0)
		var job: Dictionary = rd._bake_begin(root)
		var steps := 0
		while not rd._bake_step(job, budget):
			steps += 1
			assert_int(steps).is_less(2000)
		var baked := 0
		var loose := 0
		for n in root.get_children():
			if String(n.name).begins_with("Baked_"):
				baked += 1
				assert_int((n as MeshInstance3D).mesh.get_surface_count()).is_equal(1)
				assert_int((n as MeshInstance3D).mesh.surface_get_array_len(0)).is_equal(60 * 24)   # 60 boxes of 24 vertices
			elif n.find_children("*", "MeshInstance3D", true, false).size() > 0:
				loose += 1
		results.append([baked, loose, steps > 0])
	assert_array(results[0]).is_equal([1, 0, false])
	assert_int(int(results[1][0])).is_equal(1)
	assert_int(int(results[1][1])).is_equal(0)
	assert_bool(bool(results[1][2])).is_true()                  # the sliced one really took several calls


func test_put_stores_plain_nested_and_merged_values() -> void:
	var d := {}
	SaveManager.put(d, "a", 1)
	SaveManager.put(d, "b/c/d", 2)
	SaveManager.put(d, "b/c/e", 3)
	SaveManager.put(d, "b/*", {"x": 4})
	SaveManager.put(d, "*", {"top": 5})
	SaveManager.put(d, "list", [1, 2])
	assert_dict(d).is_equal({"a": 1, "b": {"c": {"d": 2, "e": 3}, "x": 4}, "top": 5, "list": [1, 2]})


func test_the_economy_and_realm_are_collected_in_pieces_that_add_up_to_their_serialize() -> void:
	var by_step := {}
	var economy_steps := 0
	var realm_steps := 0
	for st: Array in Life.snapshot_steps(false):
		var k := String(st[0])
		if k.begins_with("economy/") or k.begins_with("realm/"):
			SaveManager.put(by_step, k, (st[1] as Callable).call())
			economy_steps += 1 if k.begins_with("economy/") else 0
			realm_steps += 1 if k.begins_with("realm/") else 0
	assert_int(economy_steps).is_greater(20)                     # a market per step, and the loose fields
	assert_int(realm_steps).is_equal(Life.realm.ORDER.size())    # a module per step
	assert_str(JSON.stringify(by_step["economy"]["markets"].keys())).is_equal(JSON.stringify(Life.economy.serialize()["markets"].keys()))
	assert_str(JSON.stringify(by_step["realm"])).is_equal(JSON.stringify(Life.realm.serialize()))
	var whole: Dictionary = Life.economy.serialize()
	var parts: Dictionary = by_step["economy"]
	for key: String in whole:
		assert_bool(parts.has(key)).is_true()
		assert_str(JSON.stringify(parts[key])).is_equal(JSON.stringify(whole[key]))
