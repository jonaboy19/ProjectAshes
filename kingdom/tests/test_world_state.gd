extends GdUnitTestSuite
## WorldState delta store (scripts/world/world_state.gd): deltas keyed by stable ids, defaults dropped, unknown ids
## and garbage ignored, new keys default, bounded, JSON round trip, and the Life snapshot / atomic SaveManager path.

const WorldState := preload("res://scripts/world/world_state.gd")
const SaveManager := preload("res://scripts/sim/save_manager.gd")
const Locks := preload("res://scripts/world/locks.gd")
const DoorModel := preload("res://scripts/world/door_model.gd")
const Evidence := preload("res://scripts/population/evidence.gd")

const DEFAULTS := {"open": false, "locked": true, "loot_taken": 0}


func _json(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d))


func test_only_deltas_from_defaults_are_stored() -> void:
	var ws: RefCounted = WorldState.new()
	ws.set_state("ash/chest/3", {"open": false, "locked": true}, DEFAULTS)
	assert_int(ws.size()).is_equal(0)
	ws.set_state("ash/chest/3", {"locked": false, "loot_taken": 2}, DEFAULTS)
	assert_int(ws.size()).is_equal(1)
	var st: Dictionary = ws.get_state("ash/chest/3", DEFAULTS)
	assert_bool(st["locked"]).is_false()
	assert_int(st["loot_taken"]).is_equal(2)
	assert_bool(st["open"]).is_false()
	# Putting a key back to its default removes it; the last delta removes the id.
	ws.set_state("ash/chest/3", {"locked": true}, DEFAULTS)
	assert_array(ws.objects["ash/chest/3"].keys()).is_equal(["loot_taken"])
	ws.set_state("ash/chest/3", {"loot_taken": 0}, DEFAULTS)
	assert_bool(ws.has_state("ash/chest/3")).is_false()
	# Unknown id reads as defaults; the defaults dictionary is not mutated.
	var fresh: Dictionary = ws.get_state("nowhere/door/0", DEFAULTS)
	fresh["open"] = true
	assert_bool(DEFAULTS["open"]).is_false()


func test_snapshot_round_trip_through_json_keeps_types() -> void:
	var ws: RefCounted = WorldState.new()
	ws.set_state("ash/door/1", {"open": true, "broken": false}, {"open": false, "broken": false})
	ws.set_state("ash/chest/2", {"loot_taken": 3, "who": "player", "pos": [1, 2]}, {})
	ws.set_state("ash/lever/9", {"pulled": true}, {"pulled": false})
	ws.schedule(500, "ash/lever/9", "reset")
	var snap: Dictionary = ws.snapshot()
	assert_int(snap["v"]).is_equal(WorldState.VERSION)
	var other: RefCounted = WorldState.new()
	other.restore(_json(snap))
	assert_dict(other.objects).is_equal(ws.objects)
	assert_array(other.sched).is_equal(ws.sched)
	assert_int(other.get_state("ash/chest/2")["loot_taken"]).is_equal(3)


func test_unknown_ids_keys_and_garbage_are_ignored_and_new_keys_default() -> void:
	var ws: RefCounted = WorldState.new()
	ws.restore({"v": 99, "objects": {"ok/door/1": {"open": true, "future_key": [1, 2]}, 7: {"open": true}, "bad/door/2": "text",
		"empty/door/3": {}}, "sched": ["junk", {"t": 5, "id": "x/lever/1"}], "surprise": 1})
	assert_int(ws.size()).is_equal(1)
	assert_bool(ws.get_state("ok/door/1", {"open": false, "broken": false})["broken"]).is_false()     # new key defaults
	assert_bool(ws.get_state("ok/door/1")["open"]).is_true()
	assert_int(ws.sched.size()).is_equal(1)
	for junk: Variant in [null, 5, "str", [], {"objects": 5}]:
		ws.restore(junk)
		assert_int(ws.size()).is_equal(0)
	# Ids of regions that are not loaded yet stay in the store untouched until their objects ask.
	ws.restore({"objects": {"far_town/door/1": {"open": true}}})
	assert_bool(ws.has_state("far_town/door/1")).is_true()
	assert_int(ws.ids_with_prefix("far_town/").size()).is_equal(1)


func test_store_is_bounded_and_scheduler_holds_plain_data_in_order() -> void:
	var ws: RefCounted = WorldState.new()
	for i in WorldState.MAX_OBJECTS + 50:
		ws.set_state("r/obj/%d" % i, {"x": 1}, {})
	assert_int(ws.size()).is_equal(WorldState.MAX_OBJECTS)
	assert_bool(ws.set_state("r/new", {"x": 1}, {})).is_false()
	assert_bool(ws.set_state("r/obj/0", {"x": 2}, {})).is_true()           # existing ids still update
	ws.schedule(30, "a", "v")
	ws.schedule(10, "b", "v")
	ws.schedule(20, "c", "v")
	var due: Array = ws.pop_due(25)
	assert_array(due.map(func(e: Dictionary) -> String: return e["id"])).is_equal(["b", "c"])
	assert_int(ws.sched.size()).is_equal(1)
	# Save mid-delay and resume.
	var other: RefCounted = WorldState.new()
	other.restore(_json(ws.snapshot()))
	assert_array(other.pop_due(31).map(func(e: Dictionary) -> String: return e["id"])).is_equal(["a"])


func test_snapshot_cost_is_small() -> void:
	var ws: RefCounted = WorldState.new()
	for i in 1500:
		ws.set_state("town%d/door/%d" % [i % 6, i], {"open": true, "broken": i % 3 == 0}, {"open": false, "broken": false})
	var t0 := Time.get_ticks_usec()
	var snap: Dictionary = ws.snapshot()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var bytes := JSON.stringify(snap).length()
	print("PERF world_state snapshot: 1500 deltas %.2f ms, %d KB" % [ms, bytes / 1024])
	assert_float(ms).is_less(5.0)
	assert_int(bytes).is_less(200 * 1024)


## The whole path: doors + locks + evidence -> snapshot_fn -> SaveManager atomic write -> load -> restore_fn -> rebuild.
func test_save_manager_round_trip_restores_doors_chests_and_evidence() -> void:
	var live: RefCounted = WorldState.shared()
	live.call("clear")
	Locks.reset()
	DoorModel.reset()
	Evidence.reset()
	Locks.define("lot:5_5", "lot:5_5", 1, true)
	var door := DoorModel.create("ash/door/5_5", Vector2(5, 6), "lot:5_5")
	door.use("unlock", Locks.holder(["lot:5_5"]))
	door.use("open", {})
	door.settle()
	var broken := DoorModel.create("ash/door/9_9", Vector2(9, 9))
	for i in 3:
		broken.use("break", {})
	live.call("set_state", "ash/chest/1", {"loot_taken": 4, "locked": false}, {"loot_taken": 0, "locked": true})
	Evidence.add(Evidence.Kind.BODY, Vector2(3, 4), 0, 0, "c9")
	var snapshot_fn := func() -> Dictionary:
		var inter: Dictionary = live.call("snapshot")
		inter["evidence"] = Evidence.serialize()
		return {"interactives": inter, "world": {}, "game": {}}
	var box := {}
	var m: Node = SaveManager.new()
	m.root_dir = "user://test_saves_world_state/"
	m.autosave_enabled = false
	m.capture_thumbnails = false
	m.snapshot_fn = snapshot_fn
	m.restore_fn = func(data: Dictionary) -> void: box["d"] = data
	add_child(m)
	auto_free(m)
	var slot: String = SaveManager.manual_id(1)
	assert_bool(m.save_slot(slot)).override_failure_message("save failed: " + m.last_error).is_true()
	assert_bool(m.load_slot(slot)).is_true()
	var restored: Dictionary = box.get("d", {})
	assert_bool(restored.has("interactives")).is_true()
	# Wipe the world, then restore exactly as Life.restore does and rebuild the objects by id.
	live.call("clear")
	Locks.reset()
	DoorModel.reset()
	Evidence.reset()
	live.call("restore", restored["interactives"])
	Evidence.deserialize(restored["interactives"].get("evidence", []))
	Locks.define("lot:5_5", "lot:5_5", 1, true)            # default says locked; the save says unlocked
	var d2 := DoorModel.create("ash/door/5_5", Vector2(5, 6), "lot:5_5")
	assert_bool(Locks.is_locked("lot:5_5")).is_false()
	assert_int(d2.state).is_equal(DoorModel.State.OPEN)
	var b2 := DoorModel.create("ash/door/9_9", Vector2(9, 9))
	assert_int(b2.state).is_equal(DoorModel.State.BROKEN)
	assert_int(live.call("get_state", "ash/chest/1", {"loot_taken": 0})["loot_taken"]).is_equal(4)
	assert_int(Evidence.count).is_equal(1)
	# An old save without the key restores to a clean world (defaults), no error.
	live.call("restore", {})
	assert_int(live.call("size")).is_equal(0)
	m.delete_slot(slot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves_world_state/"))
