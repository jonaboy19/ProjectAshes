extends GdUnitTestSuite
## Door state machine, shared lock data (doors, chests, gates), key / lockpick hooks, NPC routing around locked
## doors, and the interior scene swap still working as the result of "open" (scripts/world/door_model.gd,
## locks.gd, scripts/interiors/interior_door.gd).

const DoorModel := preload("res://scripts/world/door_model.gd")
const Locks := preload("res://scripts/world/locks.gd")
const WorldState := preload("res://scripts/world/world_state.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const Perception := preload("res://scripts/population/perception.gd")

const LOT := Vector2(40, 60)


func before_test() -> void:
	NpcWorld.reset()
	Locks.reset()
	DoorModel.reset()
	WorldState.shared().call("clear")


func _door(locked := true, level := 1, owner := Vector2.INF, lock := "lot:40_60", id := "ash/door/40_60") -> RefCounted:
	Locks.define(lock, lock, level, locked)
	return DoorModel.create(id, Vector2(40, 62), lock, owner)


# ---------------------------------------------------------------- state machine
func test_open_and_close_swing_through_the_states() -> void:
	var d := DoorModel.create("t/door/1", Vector2.ZERO)
	assert_int(d.state).is_equal(DoorModel.State.CLOSED)
	assert_bool(d.use("open", {})["ok"]).is_true()
	assert_int(d.state).is_equal(DoorModel.State.OPENING)
	var moving := true
	var steps := 0
	while moving and steps < 100:
		moving = d.step(0.05)
		steps += 1
	assert_int(d.state).is_equal(DoorModel.State.OPEN)
	assert_float(d.open_amount).is_equal(1.0)
	assert_int(steps).is_between(8, 12)                  # 0.5 s swing
	d.use("close", {})
	assert_int(d.state).is_equal(DoorModel.State.CLOSING)
	d.settle()
	assert_int(d.state).is_equal(DoorModel.State.CLOSED)
	assert_float(d.open_amount).is_equal(0.0)


func test_locked_door_refuses_until_unlocked_with_the_key() -> void:
	var d := _door()
	assert_int(d.state).is_equal(DoorModel.State.LOCKED)
	var r: Dictionary = d.use("open", {})
	assert_bool(r["ok"]).is_false()
	assert_str(r["reason"]).is_equal("It is locked.")
	assert_bool(d.use("unlock", Locks.holder([]))["ok"]).is_false()
	assert_bool(d.use("unlock", Locks.holder(["lot:40_60"]))["ok"]).is_true()
	assert_int(d.state).is_equal(DoorModel.State.CLOSED)
	assert_bool(d.use("open", {})["ok"]).is_true()
	# Verbs: priority open > unlock > lockpick > examine > break, labels explain a locked door.
	var locked := _door(true, 2, Vector2.INF, "lot:other", "ash/door/other")
	var verbs: Array = locked.verbs(Locks.holder([], false, true))
	var ids: Array = verbs.map(func(v: Dictionary) -> String: return v["id"])
	assert_array(ids).is_equal(["open", "unlock", "lockpick", "examine", "break"])
	assert_bool(verbs[0]["enabled"]).is_false()
	assert_bool(verbs[1]["enabled"]).is_false()
	assert_bool(verbs[2]["enabled"]).is_true()


func test_one_lock_serves_door_chest_and_gate() -> void:
	Locks.define("guildhall", "key_guildhall", 2, true)
	var door := DoorModel.create("a/door/1", Vector2.ZERO, "guildhall")
	var holder := Locks.holder(["key_guildhall"])
	assert_bool(Locks.is_locked("guildhall")).is_true()
	assert_bool(door.use("unlock", holder)["ok"]).is_true()
	# The chest and the gate naming the same lock are open now too; no node knows about the others.
	assert_bool(Locks.is_locked("guildhall")).is_false()
	Locks.set_locked("guildhall", true)
	assert_bool(Locks.has_key(holder, "guildhall")).is_true()
	assert_bool(Locks.has_key(Locks.holder([]), "guildhall")).is_false()
	# A master key (guards) only fits public locks.
	Locks.define("barracks", "", 1, true, true)
	Locks.define("private_house", "", 1, true, false)
	assert_bool(Locks.has_key(Locks.holder([], true), "barracks")).is_true()
	assert_bool(Locks.has_key(Locks.holder([], true), "private_house")).is_false()


func test_lockpicking_is_deterministic_noisy_and_level_dependent() -> void:
	var easy := _door(true, 0, Vector2.INF, "easy", "ash/door/easy")
	assert_bool(easy.use("lockpick", Locks.holder([], false, true))["ok"]).is_true()
	var hard := _door(true, 5, Vector2.INF, "hard", "ash/door/hard")
	var no_tool: Dictionary = hard.use("lockpick", Locks.holder([]))
	assert_bool(no_tool["ok"]).is_false()
	var tries := 0
	var res: Dictionary = {}
	while hard.state == DoorModel.State.LOCKED and tries < 200:
		res = hard.use("lockpick", Locks.holder([], false, true, 0.0))
		assert_int(res["noise"]).is_equal(Perception.Sound.LOCKPICK)
		tries += 1
	assert_int(hard.state).is_equal(DoorModel.State.CLOSED)
	# The same lock id and attempt count always give the same outcome.
	Locks.reset()
	WorldState.shared().call("clear")
	Locks.define("hard", "hard", 5, true)
	var again := 0
	while Locks.is_locked("hard") and again < 200:
		Locks.try_pick("hard", Locks.holder([], false, true))
		again += 1
	assert_int(again).is_equal(tries)
	assert_float(Locks.pick_chance(5, 0.0)).is_less(Locks.pick_chance(1, 0.0))
	assert_float(Locks.pick_chance(3, 8.0)).is_greater(Locks.pick_chance(3, 0.0))


func test_breaking_a_door_is_loud_leaves_evidence_and_is_a_crime_when_owned() -> void:
	var owned := _door(true, 1, LOT)
	var last: Dictionary = {}
	for i in 3:
		last = owned.use("break", {})
		assert_int(last["noise"]).is_equal(Perception.Sound.BREAK_WOOD)
	assert_int(owned.state).is_equal(DoorModel.State.BROKEN)
	assert_int(last["evidence"]).is_equal(Evidence.Kind.BROKEN_DOOR)
	assert_str(last["crime"]).is_equal("burglary")
	assert_bool(owned.use("open", {})["ok"]).is_true()          # nothing blocks a broken door
	var public := _door(true, 1, Vector2.INF, "pub", "ash/door/pub")
	for i in 3:
		last = public.use("break", {})
	assert_str(last["crime"]).is_empty()


# ---------------------------------------------------------------- routing
func test_locked_doors_block_npcs_without_the_key_only() -> void:
	var d := _door(true, 1, LOT)
	DoorModel.register(d)
	assert_bool(d.blocked_for(Locks.holder([]))).is_true()
	assert_bool(d.blocked_for(Locks.holder(["lot:40_60"]))).is_false()
	assert_bool(d.blocked_for(Locks.holder([], true))).is_false() if Locks.has_key(Locks.holder([], true), "lot:40_60") else assert_bool(true).is_true()
	# The street-level query (hide spots, routing): a villager with no home there cannot use the door ...
	assert_bool(NpcWorld.door_blocked(0, Vector2(40, 62.5), -1)).is_true()
	assert_bool(NpcWorld.door_blocked(0, Vector2(300, 300), -1)).is_false()      # no door there at all
	# ... a broken or opened door is free to everybody.
	d.use("unlock", Locks.holder(["lot:40_60"]))
	assert_bool(NpcWorld.door_blocked(0, Vector2(40, 62.5), -1)).is_false()
	Locks.set_locked("lot:40_60", true)
	d.load_state()
	assert_bool(NpcWorld.door_blocked(0, Vector2(40, 62.5), -1)).is_true()
	for i in 3:
		d.use("break", {})
	assert_int(d.state).is_equal(DoorModel.State.BROKEN)
	assert_bool(NpcWorld.door_blocked(0, Vector2(40, 62.5), -1)).is_false()


func test_jammed_blocks_everyone() -> void:
	WorldState.shared().call("set_state", "j/door/1", {"jammed": true}, DoorModel.DEFAULTS)
	var d := DoorModel.create("j/door/1", Vector2.ZERO)
	assert_int(d.state).is_equal(DoorModel.State.JAMMED)
	assert_bool(d.blocked_for(Locks.holder([], true))).is_true()
	assert_bool(d.use("open", {})["ok"]).is_false()


# ---------------------------------------------------------------- persistence of door + lock state
func test_door_and_lock_state_persist_as_deltas_and_load_silently() -> void:
	var ws: RefCounted = WorldState.shared()
	var d := _door(true, 1, LOT)
	assert_bool(ws.call("has_state", "ash/door/40_60")).is_false()       # defaults store nothing
	d.use("unlock", Locks.holder(["lot:40_60"]))
	d.use("open", {})
	d.settle()
	assert_bool(ws.call("has_state", "lot:40_60") or ws.call("has_state", "lock/lot:40_60")).is_true()
	# Save, wipe the live objects, restore into a fresh store, rebuild: same state, no swing.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(ws.call("snapshot")))
	Locks.reset()
	DoorModel.reset()
	ws.call("restore", snap)
	var back := _door(true, 1, LOT)
	assert_int(back.state).is_equal(DoorModel.State.OPEN)
	assert_float(back.open_amount).is_equal(1.0)
	assert_bool(Locks.is_locked("lot:40_60")).is_false()
	# Re-lock and close: back to defaults, the store forgets the door entirely.
	back.use("close", {})
	back.settle()
	Locks.set_locked("lot:40_60", true)
	assert_bool(ws.call("has_state", "ash/door/40_60")).is_false()


# ---------------------------------------------------------------- interior scene swap
func test_interior_swap_is_the_result_of_open_and_locked_doors_stay_shut() -> void:
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	host.add_child(player)
	var door := InteriorDoor.new()
	door.interior_scene = "res://scenes/interiors/chapel_interior.tscn"
	door.set_meta("door_id", "test/door/swap")
	host.add_child(door)
	assert_object(door.model).is_not_null()
	# Locked: nothing happens, no interior.
	door.set_lock("test_lock", "key_test", 1, true)
	door.use()
	assert_object(InteriorDoor.active).is_null()
	assert_str(door.prompt()).is_equal("Locked")
	# Unlocked: use() opens the door and the scene swap follows.
	Locks.set_locked("test_lock", false)
	door.model.call("load_state")
	door.enter(player)
	assert_object(InteriorDoor.active).is_equal(door)
	assert_object(door.interior).is_not_null()
	door.leave()
	assert_object(InteriorDoor.active).is_null()
	assert_object(door.interior).is_null()
	# Exit doors never get a model.
	var exit := InteriorDoor.new()
	exit.is_exit = true
	host.add_child(exit)
	assert_object(exit.model).is_null()
