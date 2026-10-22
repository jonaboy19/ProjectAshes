extends GdUnitTestSuite
## Save robustness: dirty-flag containers re-serialize only what changed; the app pause / focus loss
## notifications autosave through SaveManager's atomic write; clean focus loss is skipped.

const SaveManager := preload("res://scripts/sim/save_manager.gd")
const SaveContainers := preload("res://scripts/sim/save_containers.gd")
const WorldState := preload("res://scripts/world/world_state.gd")

const TEST_DIR := "user://test_saves_auto/"

var _mgr: SaveManager
var _player: Node3D
var _state: Dictionary
var _snaps := 0


func before_test() -> void:
	_clear_dir()
	WorldState.shared().call("clear")
	_state = {"world": {"day": 3}, "game": {"gold": 7}}
	_snaps = 0
	_player = Node3D.new()
	add_child(_player)
	auto_free(_player)
	_mgr = SaveManager.new()
	_mgr.root_dir = TEST_DIR
	_mgr.capture_thumbnails = false
	_mgr.player_override = _player
	_mgr.snapshot_fn = func() -> Dictionary:
		_snaps += 1
		return _state.duplicate(true)
	_mgr.restore_fn = func(d: Dictionary) -> void: _state = d.duplicate(true)
	add_child(_mgr)
	auto_free(_mgr)


func after_test() -> void:
	WorldState.shared().call("clear")
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


func test_containers_serialize_only_dirty() -> void:
	var c := SaveContainers.new()
	var calls := {"a": 0, "b": 0}
	c.register("a", func() -> Dictionary:
		calls["a"] += 1
		return {"v": calls["a"]})
	c.register("b", func() -> Dictionary:
		calls["b"] += 1
		return {"v": 1})
	var s1 := c.snapshot()
	assert_array(c.last_rebuilt).contains_exactly_in_any_order(["a", "b"])
	assert_bool(c.any_dirty()).is_false()
	c.snapshot()
	assert_array(c.last_rebuilt).is_empty()
	assert_int(calls["a"]).is_equal(1)
	c.mark_dirty("a")
	assert_array(c.dirty_names()).is_equal(["a"])
	var s3 := c.snapshot()
	assert_array(c.last_rebuilt).is_equal(["a"])
	assert_int(int((s3["a"] as Dictionary)["v"])).is_equal(2)
	assert_int(int((s3["b"] as Dictionary)["v"])).is_equal(1)
	assert_int(int((s1["a"] as Dictionary)["v"])).is_equal(1)
	assert_int(calls["b"]).is_equal(1)


func test_pause_autosaves_atomically_and_round_trips() -> void:
	var id: String = _mgr.handle_lifecycle(NOTIFICATION_APPLICATION_PAUSED)
	assert_str(id).is_not_empty()
	assert_bool(_mgr.has_slot(id)).is_true()
	assert_bool(FileAccess.file_exists(_mgr.path_of(id) + ".tmp")).is_false()    # temp renamed away
	_state = {}
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_int(int((_state["game"] as Dictionary)["gold"])).is_equal(7)


func test_pause_save_skips_gap_and_overwrites_previous_with_backup() -> void:
	var a: String = _mgr.handle_lifecycle(NOTIFICATION_APPLICATION_PAUSED)
	_state["game"]["gold"] = 99
	_mgr._last_bg_ms = -1
	var b: String = _mgr.handle_lifecycle(NOTIFICATION_APPLICATION_PAUSED)
	assert_str(b).is_not_empty()      # forced: ignores the 30 s autosave gap
	assert_str(b).is_not_equal(a)     # rotating slots


func test_focus_out_saves_when_dirty_then_skips_when_clean() -> void:
	_mgr.mark_dirty()
	assert_bool(_mgr.is_dirty()).is_true()
	var id: String = _mgr.handle_lifecycle(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_str(id).is_not_empty()
	assert_bool(_mgr.is_dirty()).is_false()       # a successful save clears the flag
	_mgr._last_bg_ms = -1
	assert_str(_mgr.handle_lifecycle(NOTIFICATION_WM_WINDOW_FOCUS_OUT)).is_empty()   # nothing changed
	_mgr.mark_dirty()
	assert_str(_mgr.handle_lifecycle(NOTIFICATION_WM_WINDOW_FOCUS_OUT)).is_not_empty()


func test_pause_right_after_focus_out_does_not_double_write() -> void:
	_mgr.mark_dirty()
	assert_str(_mgr.handle_lifecycle(NOTIFICATION_APPLICATION_FOCUS_OUT)).is_not_empty()
	var n := _snaps
	_mgr.mark_dirty()
	assert_str(_mgr.handle_lifecycle(NOTIFICATION_APPLICATION_FOCUS_OUT)).is_empty()   # debounced
	assert_int(_snaps).is_equal(n)


func test_world_state_overlay_counts_as_dirty() -> void:
	assert_bool(_mgr.is_dirty()).is_false()
	WorldState.shared().call("set_state", "x/dep/ore/0", {"q": 2.0, "d": 1})
	assert_bool(_mgr.is_dirty()).is_true()


func test_dirty_container_makes_manager_dirty_and_manager_uses_containers() -> void:
	var c := SaveContainers.new()
	c.register("game", func() -> Dictionary: return {"gold": 5})
	c.register("world", func() -> Dictionary: return {"day": 1})
	_mgr.snapshot_fn = Callable()
	_mgr.containers = c
	assert_bool(_mgr.is_dirty()).is_true()          # registered containers start dirty
	assert_bool(_mgr.save_slot("quick", "manual", false)).is_true()
	assert_bool(_mgr.is_dirty()).is_false()
	c.mark_dirty("game")
	assert_bool(_mgr.is_dirty()).is_true()
	assert_bool(_mgr.save_slot("quick", "manual", false)).is_true()
	assert_array(c.last_rebuilt).is_equal(["game"])
	assert_bool(_mgr.load_slot("quick")).is_true()
	assert_int(int((_state["game"] as Dictionary)["gold"])).is_equal(5)


func test_no_game_no_lifecycle_save() -> void:
	_mgr.player_override = null
	assert_str(_mgr.handle_lifecycle(NOTIFICATION_APPLICATION_PAUSED)).is_empty()
