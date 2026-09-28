extends GdUnitTestSuite
## Save system: round trip, atomic-write backups, corruption fallback, v1
## migration, autosave rotation, the hostile-nearby guard, and slot deletion.
## Runs a standalone scripts/sim/save_manager.gd with fake snapshot/restore
## functions so nothing touches the real Life autoload's state.

const SaveManager := preload("res://scripts/sim/save_manager.gd")

const TEST_DIR := "user://test_saves/"

var _mgr: SaveManager
var _state: Dictionary


func before_test() -> void:
	_clear_dir()
	_state = {"world": {"day": 1, "time": 8.0}, "game": {"gold": 0}}
	_mgr = SaveManager.new()
	_mgr.root_dir = TEST_DIR
	_mgr.autosave_enabled = false
	_mgr.capture_thumbnails = false
	_mgr.snapshot_fn = func() -> Dictionary: return _state.duplicate(true)
	_mgr.restore_fn = func(d: Dictionary) -> void: _state = (d as Dictionary).duplicate(true)
	add_child(_mgr)
	auto_free(_mgr)


func after_test() -> void:
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


func _spawn_actor(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	auto_free(n)
	n.global_position = pos
	return n


# --- round trip --------------------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	_state = {"world": {"day": 3, "time": 14.5}, "game": {"gold": 42}}
	assert_bool(_mgr.save_slot(SaveManager.manual_id(1))).is_true()
	assert_str(_mgr.last_error).is_equal("")
	_state = {}
	assert_bool(_mgr.load_slot(SaveManager.manual_id(1))).is_true()
	# JSON has no integer type, so numbers come back as floats.
	assert_dict(_state).is_equal({"world": {"day": 3.0, "time": 14.5}, "game": {"gold": 42.0}})
	assert_str(_mgr.last_slot).is_equal(SaveManager.manual_id(1))


# --- atomic write / backup ----------------------------------------------------------------

func test_atomic_write_keeps_a_backup_of_the_previous_version() -> void:
	var id := SaveManager.manual_id(1)
	_state = {"world": {"day": 1, "time": 0.0}, "game": {}}
	assert_bool(_mgr.save_slot(id)).is_true()
	assert_bool(FileAccess.file_exists(_mgr.path_of(id) + ".bak")).is_false()
	_state = {"world": {"day": 2, "time": 0.0}, "game": {}}
	assert_bool(_mgr.save_slot(id)).is_true()
	var bak := _mgr.path_of(id) + ".bak"
	assert_bool(FileAccess.file_exists(bak)).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(bak))
	assert_int(int((parsed["data"] as Dictionary)["world"]["day"])).is_equal(1)
	# The main file holds the newest version.
	var main_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_mgr.path_of(id)))
	assert_int(int((main_parsed["data"] as Dictionary)["world"]["day"])).is_equal(2)


func test_corrupted_main_file_falls_back_to_backup() -> void:
	var id := SaveManager.manual_id(1)
	_state = {"world": {"day": 1, "time": 0.0}, "game": {}}
	_mgr.save_slot(id)
	_state = {"world": {"day": 2, "time": 0.0}, "game": {}}
	_mgr.save_slot(id)
	# Corrupt the main file; the backup (day 1) should still be readable.
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	_state = {}
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_int(int((_state["world"] as Dictionary)["day"])).is_equal(1)
	assert_str(_mgr.last_error).contains("backup")


# --- migration ---------------------------------------------------------------------------

func test_migrates_a_v1_envelope() -> void:
	var id := SaveManager.manual_id(1)
	# Force the folder to exist, then drop a raw v1 file (no envelope wrapper).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var raw := {"world": {"day": 5, "time": 10.0}, "game": {"gold": 7},
		"life_path": {"given_name": "Ada", "family_name": "Hero"}}
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	var env := _mgr.read_slot(id)
	assert_bool(env.is_empty()).is_false()
	assert_int(int(env["schema"])).is_equal(SaveManager.SCHEMA_VERSION)
	assert_str(String((env["meta"] as Dictionary)["name"])).is_equal("Ada Hero")
	assert_int(int((env["data"] as Dictionary)["world"]["day"])).is_equal(5)
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_int(int((_state["world"] as Dictionary)["day"])).is_equal(5)


# --- autosave rotation ---------------------------------------------------------------------

func test_autosave_rotates_across_the_three_auto_slots() -> void:
	_mgr.player_override = _spawn_actor(Vector3.ZERO)
	_mgr.autosave_enabled = true
	var got := PackedStringArray()
	for i in 4:
		_state = {"world": {"day": i, "time": 0.0}, "game": {}}
		got.append(_mgr.autosave("test", false, true))
	assert_str(got[0]).is_equal(SaveManager.auto_id(1))
	assert_str(got[1]).is_equal(SaveManager.auto_id(2))
	assert_str(got[2]).is_equal(SaveManager.auto_id(3))
	# The fourth overwrites the oldest (lowest serial): auto_1.
	assert_str(got[3]).is_equal(SaveManager.auto_id(1))
	for id in [SaveManager.auto_id(1), SaveManager.auto_id(2), SaveManager.auto_id(3)]:
		assert_bool(_mgr.has_slot(id)).is_true()
	# auto_1 now holds the 4th save's data (day 3), not the 1st's (day 0).
	var env := _mgr.read_slot(SaveManager.auto_id(1))
	assert_int(int((env["data"] as Dictionary)["world"]["day"])).is_equal(3)


# --- combat guard ----------------------------------------------------------------------

func test_no_autosave_while_a_hostile_is_close() -> void:
	_mgr.player_override = _spawn_actor(Vector3.ZERO)
	_mgr.autosave_enabled = true
	var hostile := _spawn_actor(Vector3(SaveManager.HOSTILE_RADIUS * 0.5, 0, 0))
	hostile.add_to_group("team1")
	assert_bool(_mgr.can_autosave()).is_false()
	assert_str(_mgr.autosave("test", false, true)).is_equal("")
	# Moving it out of range lifts the guard.
	hostile.global_position = Vector3(SaveManager.HOSTILE_RADIUS * 3.0, 0, 0)
	assert_bool(_mgr.can_autosave()).is_true()


# --- delete ------------------------------------------------------------------------------

func test_delete_slot_removes_its_files() -> void:
	var id := SaveManager.manual_id(2)
	_mgr.save_slot(id)
	assert_bool(_mgr.has_slot(id)).is_true()
	assert_bool(_mgr.delete_slot(id)).is_true()
	assert_bool(_mgr.has_slot(id)).is_false()
	assert_bool(FileAccess.file_exists(_mgr.path_of(id))).is_false()
	assert_bool(FileAccess.file_exists(_mgr.meta_path(id))).is_false()
