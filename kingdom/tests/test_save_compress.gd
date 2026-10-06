extends GdUnitTestSuite
## Save pass 2026-10-06: schema 3 stores a big save zstd-compressed (base64 in the JSON envelope); small saves stay plain
## JSON; schema 1 and 2 files from older builds still load; damage to the compressed form is caught like any other.

const SaveManager := preload("res://scripts/sim/save_manager.gd")
const TEST_DIR := "user://test_saves_compress/"

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


func _big_state(day: int) -> Dictionary:
	var rows: Array = []
	for i in 2500:
		rows.append({"id": "row_%d" % i, "n": i, "x": 0.1 * float(i % 17), "tags": ["a", "b", "c"], "name": "Resident number %d of the realm" % i})
	return {"world": {"day": day, "time": 9.5}, "game": {"gold": 12}, "realm": {"rows": rows}}


func _file_text(id: String) -> String:
	return FileAccess.get_file_as_string(_mgr.path_of(id))


func test_a_big_save_is_stored_compressed_and_round_trips() -> void:
	var id := SaveManager.manual_id(1)
	_state = _big_state(7)
	var plain_len := JSON.stringify(_state).length()
	assert_int(plain_len).is_greater(SaveManager.COMPRESS_MIN)
	assert_bool(_mgr.save_slot(id)).is_true()
	var text := _file_text(id)
	assert_bool(text.contains('"enc":"zstd"')).is_true()
	assert_int(text.length()).is_less(plain_len / 3)
	var before := _state.duplicate(true)
	_state = {}
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_str(_mgr.last_error).is_equal("")
	# the same content, numbers as floats (JSON has no integer type)
	assert_str(JSON.stringify(_state)).is_equal(JSON.stringify(JSON.parse_string(JSON.stringify(before))))
	assert_int(int((_state["realm"]["rows"] as Array).size())).is_equal(2500)
	assert_int(int(_mgr.read_slot(id)["schema"])).is_equal(SaveManager.SCHEMA_VERSION)


func test_a_small_save_stays_plain_json() -> void:
	var id := SaveManager.manual_id(1)
	assert_bool(_mgr.save_slot(id)).is_true()
	var text := _file_text(id)
	assert_bool(text.contains('"enc"')).is_false()
	var parsed: Variant = JSON.parse_string(text)
	assert_int(int(parsed["schema"])).is_equal(3)
	assert_int(int((parsed["data"] as Dictionary)["world"]["day"])).is_equal(1)


func test_a_schema_2_file_from_an_older_build_still_loads() -> void:
	var id := SaveManager.manual_id(2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var data_text := JSON.stringify({"world": {"day": 41, "time": 6.0}, "game": {"gold": 99}})
	var meta := {"schema": 2, "name": "Old Hero", "day": 41}
	var text := '{"schema":2,"meta":%s,"checksum":"%s","data":%s}' % [JSON.stringify(meta), data_text.md5_text(), data_text]
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var env := _mgr.read_slot(id)
	assert_bool(env.is_empty()).is_false()
	assert_int(int(env["schema"])).is_equal(SaveManager.SCHEMA_VERSION)
	assert_int(int((env["data"] as Dictionary)["world"]["day"])).is_equal(41)
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_int(int(_state["game"]["gold"])).is_equal(99)


func test_a_newer_schema_is_refused() -> void:
	var id := SaveManager.manual_id(2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string('{"schema":99,"meta":{},"data":{"world":{},"game":{}}}')
	f.close()
	assert_bool(_mgr.read_slot(id).is_empty()).is_true()
	assert_str(_mgr.last_error).contains("newer version")


func test_a_damaged_compressed_save_falls_back_to_the_backup() -> void:
	var id := SaveManager.manual_id(1)
	_state = _big_state(1)
	_mgr.save_slot(id)
	_state = _big_state(2)
	_mgr.save_slot(id)
	var text := _file_text(id)
	var at := text.find('"data":"') + 40
	var broken := text.substr(0, at) + ("A" if text[at] != "A" else "B") + text.substr(at + 1)
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string(broken)
	f.close()
	_state = {}
	assert_bool(_mgr.load_slot(id)).is_true()
	assert_int(int(_state["world"]["day"])).is_equal(1)
	assert_str(_mgr.last_error).contains("backup")
	assert_str(_mgr.last_error).contains("checksum")


func test_a_truncated_compressed_save_is_rejected() -> void:
	var id := SaveManager.manual_id(1)
	_state = _big_state(3)
	_mgr.save_slot(id)
	var text := _file_text(id)
	var f := FileAccess.open(_mgr.path_of(id), FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))
	f.close()
	assert_bool(_mgr.read_slot(id).is_empty()).is_true()
	assert_str(_mgr.last_error).is_not_empty()


# --- the real game state through both file formats -------------------------------------------------------------------------------

func _life_manager() -> SaveManager:
	var m := SaveManager.new()
	m.root_dir = TEST_DIR
	m.autosave_enabled = false
	m.capture_thumbnails = false
	m.snapshot_fn = func() -> Dictionary: return Life.snapshot()
	m.restore_fn = func(d: Dictionary) -> void: Life.restore(d)
	add_child(m)
	auto_free(m)
	return m


## Top-level sections whose JSON text differs (never compare the huge texts with assert_str: a failure would diff 2 MB strings).
func _differing_sections(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for k: String in keys:
		if JSON.stringify(a.get(k)).md5_text() != JSON.stringify(b.get(k)).md5_text():
			out.append(k)
	return out


func _normalised(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))       # JSON has no integer type: ints come back as floats


func test_life_snapshot_round_trips_through_the_compressed_file() -> void:
	var m := _life_manager()
	var id := SaveManager.manual_id(3)
	var before := _normalised(Life.snapshot())
	assert_int(JSON.stringify(before).length()).is_greater(SaveManager.COMPRESS_MIN)
	assert_bool(m.save_slot(id)).is_true()
	assert_bool(FileAccess.get_file_as_string(m.path_of(id)).contains('"enc":"zstd"')).is_true()
	assert_int(FileAccess.get_file_as_bytes(m.path_of(id)).size()).is_less(JSON.stringify(before).length() / 3)
	assert_bool(m.load_slot(id)).is_true()
	assert_str(m.last_error).is_equal("")
	var after := _normalised(Life.snapshot())
	assert_array(_differing_sections(before, after)).is_empty()


func test_life_snapshot_loads_from_a_plain_schema_2_file() -> void:
	var m := _life_manager()
	var id := SaveManager.manual_id(3)
	var snap := _normalised(Life.snapshot())
	var data_text := JSON.stringify(snap)
	var meta := {"schema": 2, "name": "Old Save", "day": int(WorldSim.day)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var f := FileAccess.open(m.path_of(id), FileAccess.WRITE)
	f.store_string('{"schema":2,"meta":%s,"checksum":"%s","data":%s}' % [JSON.stringify(meta), data_text.md5_text(), data_text])
	f.close()
	var env := m.read_slot(id)
	assert_bool(env.is_empty()).is_false()
	assert_int(int(env["schema"])).is_equal(SaveManager.SCHEMA_VERSION)
	assert_bool(m.load_slot(id)).is_true()
	assert_str(m.last_error).is_equal("")
	assert_array(_differing_sections(snap, _normalised(Life.snapshot()))).is_empty()
