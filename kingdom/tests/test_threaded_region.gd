extends GdUnitTestSuite
## WP-05: interiors / dungeon floors / streamer spawners go through the threaded loader; no blocking load() path is left
## in the transition code, the queue respects its budget, and THREADED never takes mesh-carrying resources.

const Loader := preload("res://scripts/core/threaded_loader.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const INTERIORS := [
	"res://scenes/interiors/house_interior.tscn",
	"res://scenes/interiors/inn_interior.tscn",
	"res://scenes/interiors/blacksmith_interior.tscn",
]
const SOURCES := [
	"res://scripts/interiors/interior_door.gd",
	"res://scripts/interiors/dungeon_root.gd",
	"res://scripts/interiors/dungeon_door.gd",
	"res://scripts/core/cell_streamer.gd",
]


func after_test() -> void:
	Loader.reset()
	CellStreamer.reset_shared()


func _drain(max_polls := 500) -> void:
	var n := 0
	while Loader.pending() > 0 and n < max_polls:
		Loader.poll(50.0)
		n += 1


func test_three_interiors_load_through_queue() -> void:
	var got := {}
	Loader.request_many(INTERIORS, func(r: Dictionary) -> void: got = r)
	assert_dict(got).is_empty()                 # request never blocks the caller
	_drain()
	assert_int(got.size()).is_equal(3)
	for p: String in INTERIORS:
		assert_object(got[p]).is_instanceof(PackedScene)
		assert_bool(Loader.is_ready(p)).is_true()
	assert_int(int(Loader.stats["blocking"])).is_equal(0)
	assert_int(int(Loader.stats["completed"])).is_equal(3)


func test_budget_limits_work_per_poll() -> void:
	var done := []
	for p: String in INTERIORS:
		Loader.request(p, func(path: String, _r: Variant) -> void: done.append(path))
	Loader.poll(0.0)                             # budget already spent: exactly one item per poll
	assert_int(done.size()).is_equal(1)
	_drain()
	assert_int(done.size()).is_equal(3)


func test_cached_request_is_answered_without_load() -> void:
	Loader.load_now(INTERIORS[0])
	var base := int(Loader.stats["main"])
	var hit := [false]
	Loader.request(INTERIORS[0], func(_p: String, r: Variant) -> void: hit[0] = r != null)
	_drain()
	assert_bool(hit[0]).is_true()
	assert_int(int(Loader.stats["main"])).is_equal(base)
	assert_int(int(Loader.stats["cache_hits"])).is_equal(1)


func test_threaded_backend_never_takes_scenes() -> void:
	Loader.backend = Loader.Backend.THREADED
	var ok := [false]
	Loader.request(INTERIORS[1], func(_p: String, r: Variant) -> void: ok[0] = r is PackedScene)
	_drain()
	assert_bool(ok[0]).is_true()
	assert_int(int(Loader.stats["threaded"])).is_equal(0)     # scenes carry meshes: stays on the main thread (docs/qa/stability.md)


func test_defer_runs_within_budget_queue() -> void:
	var order := []
	Loader.defer(func() -> void: order.append(1))
	Loader.defer(func() -> void: order.append(2))
	_drain()
	assert_array(order).is_equal([1, 2])


func test_door_enters_after_async_load() -> void:
	var door := InteriorDoor.new()
	door.interior_scene = INTERIORS[2]
	add_child(door)
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	assert_bool(Loader.is_ready(INTERIORS[2])).is_false()
	door.enter(player, true)
	assert_object(door.interior).is_null()       # not built in the pressing frame
	_drain()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(door.interior).is_not_null()
	assert_int(int(Loader.stats["blocking"])).is_equal(0)
	door.leave()
	door.free()
	player.free()


func test_no_synchronous_load_path_remains() -> void:
	for path: String in SOURCES:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_object(f).is_not_null()
		var n := 0
		for line in f.get_as_text().split("\n"):
			var code := line.split("#")[0]
			var i := code.find("load(")
			while i >= 0:
				var pre := code.substr(maxi(0, i - 3), 3)
				if pre != "pre" and not code.substr(maxi(0, i - 5), 5).ends_with("load_") and not code.substr(maxi(0, i - 9), 9).ends_with("request_"):
					n += 1
				i = code.find("load(", i + 1)
		assert_int(n).override_failure_message("blocking load( in %s" % path).is_equal(0)
