extends GdUnitTestSuite
## Region 1 scaffold (scripts/region1): the sim base class (deterministic by seed, events,
## save shape), the Region1State save registry (round trip through JSON, migration, orphan
## data kept, dead providers skipped) and Region1Root (clock slicing, presenter refresh).

const DemoSim := preload("res://scripts/region1/demo_sim.gd")
const Root := preload("res://scripts/region1/region1_root.gd")
const State := preload("res://scripts/region1/region1_state.gd")


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


func _run(seed_value: int, days: int) -> DemoSim:
	var s := DemoSim.new()
	s.setup(seed_value)
	for i in days * 2:
		s.tick(0.5)
	return s


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


# --- Region1Sim ---------------------------------------------------------------------

func test_same_seed_gives_identical_state() -> void:
	assert_str(_run(7, 20).digest()).is_equal(_run(7, 20).digest())


func test_different_seed_gives_different_state() -> void:
	assert_str(_run(7, 20).digest()).is_not_equal(_run(8, 20).digest())


func test_tick_ignores_non_positive_dt_and_counts_time() -> void:
	var s := DemoSim.new().setup(1) as DemoSim
	s.tick(0.0)
	s.tick(-1.0)
	assert_int(s.tick_count).is_equal(0)
	s.tick(0.5)
	s.tick(0.25)
	assert_float(s.day_f).is_equal_approx(0.75, 0.0001)
	assert_int(s.tick_count).is_equal(2)


func test_events_are_signalled_and_logged() -> void:
	var s := DemoSim.new().setup(3) as DemoSim
	var seen: Array = []
	s.event.connect(func(kind: StringName, _d: Dictionary) -> void: seen.append(kind))
	s.emit_event(&"hello", {"a": 1})
	assert_array(seen).is_equal([&"hello"])
	assert_int(s.event_log.size()).is_equal(1)
	for i in Region1Sim.EVENT_LOG_MAX + 10:
		s.emit_event(&"spam")
	assert_int(s.event_log.size()).is_equal(Region1Sim.EVENT_LOG_MAX)


func test_serialize_is_json_safe_and_restores_exactly() -> void:
	var a := _run(11, 15)
	var b := DemoSim.new()
	b.deserialize(_roundtrip(a.serialize()))
	assert_str(b.digest()).is_equal(a.digest())
	# and both continue identically (the rng state survived JSON as text)
	a.tick(1.0)
	b.tick(1.0)
	assert_str(b.digest()).is_equal(a.digest())


func test_debug_image_is_provided_by_the_demo() -> void:
	var img := _run(1, 5).debug_image(64)
	assert_object(img).is_not_null()
	assert_int(img.get_width()).is_equal(64)


# --- Region1State -------------------------------------------------------------------

func test_snapshot_restore_round_trip_through_json() -> void:
	var a := _run(5, 10)
	State.register_sim(a)
	var saved := _roundtrip(State.snapshot())
	assert_int(int(saved["version"])).is_equal(State.SAVE_VERSION)
	assert_bool((saved["modules"] as Dictionary).has("demo_sim")).is_true()

	State.clear()
	var b := DemoSim.new()
	b.setup(99)   # different seed: restore must overwrite it
	State.register_sim(b)
	State.restore(saved)
	assert_str(b.digest()).is_equal(a.digest())


func test_plain_callable_module_round_trips() -> void:
	var store := {"n": 3}
	State.register(&"custom", func() -> Dictionary: return store.duplicate(),
		func(d: Dictionary) -> void:
			store["n"] = int(d.get("n", -1)))
	var saved := _roundtrip(State.snapshot())
	store["n"] = 0
	State.restore(saved)
	assert_int(store["n"]).is_equal(3)


func test_module_missing_from_save_is_reset_with_empty_dict() -> void:
	var got := {"d": null}
	State.register(&"newmod", func() -> Dictionary: return {},
		func(d: Dictionary) -> void: got["d"] = d)
	State.restore({"version": 1, "modules": {}})
	assert_dict(got["d"]).is_empty()
	got["d"] = null
	State.restore({})   # old save without any region1 block
	assert_dict(got["d"]).is_empty()


func test_migration_runs_stepwise_up_to_current_version() -> void:
	var calls: Array = []
	var got := {"d": {}}
	State.register(&"mig", func() -> Dictionary: return {},
		func(d: Dictionary) -> void: got["d"] = d, 3,
		func(from_v: int, d: Dictionary) -> Dictionary:
			calls.append(from_v)
			d["migrated_" + str(from_v)] = true
			return d)
	State.restore({"version": 1, "modules": {"mig": {"v": 1, "data": {"x": 1}}}})
	assert_array(calls).is_equal([1, 2])
	assert_bool(got["d"].has("migrated_2")).is_true()
	assert_int(got["d"]["x"]).is_equal(1)


func test_demo_sim_migrates_v1_data() -> void:
	var s := DemoSim.new()
	State.register_sim(s)
	State.restore({"version": 1, "modules": {"demo_sim": {"v": 1, "data": {
		"seed": 4, "rng_state": "1234", "day_f": 2.0, "ticks": 4, "state": {"count": 17}}}}})
	assert_int(s.sparks).is_equal(17)
	assert_int(s.tick_count).is_equal(4)


func test_unknown_module_data_is_kept_and_adopted_later() -> void:
	var payload := {"version": 1, "modules": {"future": {"v": 1, "data": {"q": 42}}}}
	State.restore(payload)
	var kept := _roundtrip(State.snapshot())
	assert_int(int(kept["modules"]["future"]["data"]["q"])).is_equal(42)   # written back verbatim
	var got := {"q": 0}
	State.register(&"future", func() -> Dictionary: return {"q": got["q"]},
		func(d: Dictionary) -> void: got["q"] = int(d.get("q", 0)))
	assert_int(got["q"]).is_equal(42)   # late registration receives its waiting data


func test_freed_provider_is_skipped_not_fatal() -> void:
	var holder := RefCounted.new()
	var n := Node.new()
	State.register(&"gone", n.get_class, func(_d: Dictionary) -> void: pass)
	State.register(&"gone2", Callable(n, "get_name"), Callable(n, "queue_free"))
	n.free()
	holder = null
	var snap := State.snapshot()   # must not error
	assert_bool((snap["modules"] as Dictionary).has("gone2")).is_false()
	State.restore(snap)


func test_register_sim_replaces_and_unregister_removes() -> void:
	var a := DemoSim.new()
	var b := DemoSim.new()
	State.register_sim(a)
	State.register_sim(b)
	assert_object(State.sim(&"demo_sim")).is_same(b)
	State.unregister(&"demo_sim")
	assert_bool(State.has(&"demo_sim")).is_false()
	assert_object(State.sim(&"demo_sim")).is_null()


# --- Region1Root --------------------------------------------------------------------

func _make_root(clock_day: Array) -> Node3D:
	var root: Node3D = auto_free(Root.new())
	root.auto_bootstrap = false
	root.auto_timer = false
	root.clock = func() -> float: return clock_day[0]
	add_child(root)
	return root


func test_root_slices_time_and_ticks_registered_sims() -> void:
	var day := [10.0]
	var root := _make_root(day)
	var s := DemoSim.new().setup(1) as DemoSim
	State.register_sim(s)
	assert_int(root.advance_to(10.0)).is_equal(0)   # first call anchors
	assert_int(root.advance_to(10.5)).is_equal(1)
	assert_float(s.day_f).is_equal_approx(0.5, 0.0001)
	# a 3.5-day sleep: 1.0-day chunks (3 x 1.0 + 0.5) fit in the 4-chunk budget
	assert_int(root.advance_to(14.0)).is_equal(4)
	assert_float(s.day_f).is_equal_approx(4.0, 0.0001)
	assert_int(root.advance_to(20.0)).is_equal(Root.MAX_CHUNKS_PER_TICK)   # 6 days owed: 4 now, rest next tick
	assert_float(s.day_f).is_equal_approx(4.0 + float(Root.MAX_CHUNKS_PER_TICK), 0.0001)


func test_root_reanchors_when_clock_goes_backwards() -> void:
	var day := [5.0]
	var root := _make_root(day)
	var s := DemoSim.new().setup(1) as DemoSim
	State.register_sim(s)
	root.advance_to(5.0)
	root.advance_to(6.0)
	assert_int(root.advance_to(2.0)).is_equal(0)
	assert_int(root.advance_to(2.5)).is_equal(1)


func test_root_refreshes_presenters_in_group() -> void:
	var day := [0.0]
	var root := _make_root(day)
	State.register_sim(DemoSim.new().setup(1))
	var pres := PresenterProbe.new()
	pres.add_to_group(Root.GROUP_PRESENTER)
	auto_free(pres)
	add_child(pres)
	root.advance_to(0.0)
	root.advance_to(0.5)
	assert_int(pres.count).is_equal(1)


func test_root_bootstrap_is_idempotent_and_registers_what_it_creates() -> void:
	# Manifest-free: whatever modules the shipped manifest lists, each created one must be a
	# registered sim afterwards and a second call must create nothing new.
	var root: Node3D = auto_free(Root.new())
	root.auto_timer = false
	root.auto_bootstrap = false
	add_child(root)
	var made: PackedStringArray = root.bootstrap_modules()
	for mod_name in made:
		assert_object(State.sim(StringName(mod_name))).is_not_null()
	assert_int(root.bootstrap_modules().size()).is_equal(0)


class PresenterProbe extends Node:
	var count := 0
	func region1_present(_root: Node) -> void:
		count += 1


func test_root_reanchors_after_a_save_is_restored() -> void:
	var day := [1.0]
	var root := _make_root(day)
	var s := DemoSim.new().setup(1) as DemoSim
	State.register_sim(s)
	root.advance_to(1.0)
	root.advance_to(1.5)
	State.restore(State.snapshot())   # what Life.restore does through hook H2
	assert_int(root.advance_to(50.0)).is_equal(0)   # loaded at day 50: no 48-day fast-forward
	assert_int(root.advance_to(50.5)).is_equal(1)
