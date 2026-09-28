extends GdUnitTestSuite
## scripts/core/world_db.gd: open/exec/query round trip, transaction-wrapped
## bulk insert performance (10k rows) and graceful degradation when the
## godot-sqlite GDExtension isn't available on this build/architecture
## (e.g. armeabi-v7a -- see world_db.gd's header comment).

const WorldDB := preload("res://scripts/core/world_db.gd")

const TEST_DB_PATH := "user://test_world_db/bench.db"
const ROW_COUNT := 10000


func before_test() -> void:
	_clear_test_db()


func after_test() -> void:
	_clear_test_db()


func _clear_test_db() -> void:
	var dir_path := TEST_DB_PATH.get_base_dir()
	if DirAccess.dir_exists_absolute(dir_path):
		var dir := DirAccess.open(dir_path)
		if dir:
			for file_name in dir.get_files():
				dir.remove(file_name)
	else:
		DirAccess.make_dir_recursive_absolute(dir_path)


func test_available_matches_classdb() -> void:
	assert_bool(WorldDB.available()).is_equal(ClassDB.class_exists("SQLite"))


func test_open_query_close_round_trip() -> void:
	var db := WorldDB.new()
	if not WorldDB.available():
		# Expected on armeabi-v7a and any other build without the SQLite
		# GDExtension: open() must fail soft, not error, so callers fall
		# back to the JSON save path.
		assert_bool(db.open(TEST_DB_PATH)).is_false()
		assert_bool(db.is_open()).is_false()
		return

	assert_bool(db.open(TEST_DB_PATH)).is_true()
	assert_bool(db.is_open()).is_true()

	assert_bool(db.exec("CREATE TABLE IF NOT EXISTS kv (id INTEGER PRIMARY KEY, key TEXT, value TEXT);")).is_true()
	assert_bool(db.exec("INSERT INTO kv (key, value) VALUES (?, ?);", ["hello", "world"])).is_true()

	var rows := db.query("SELECT key, value FROM kv WHERE key = ?;", ["hello"])
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["value"]).is_equal("world")

	db.close()
	assert_bool(db.is_open()).is_false()


func test_bulk_insert_and_query_10k_rows_reports_timing() -> void:
	if not WorldDB.available():
		print("WorldDB benchmark skipped: SQLite GDExtension not available on this build/arch.")
		return

	var db := WorldDB.new()
	assert_bool(db.open(TEST_DB_PATH)).is_true()
	assert_bool(db.exec(
		"CREATE TABLE IF NOT EXISTS bench (id INTEGER PRIMARY KEY, name TEXT, value REAL);"
	)).is_true()

	# Bulk insert, wrapped in a single transaction (the single biggest
	# lever for SQLite insert throughput -- see world_db.gd).
	var insert_start := Time.get_ticks_usec()
	assert_bool(db.begin_transaction()).is_true()
	for i in range(ROW_COUNT):
		assert_bool(db.exec(
			"INSERT INTO bench (id, name, value) VALUES (?, ?, ?);",
			[i, "row_%d" % i, float(i) * 0.5]
		)).is_true()
	assert_bool(db.commit_transaction()).is_true()
	var insert_usec := Time.get_ticks_usec() - insert_start

	var query_start := Time.get_ticks_usec()
	var rows := db.query("SELECT id, name, value FROM bench ORDER BY id;")
	var query_usec := Time.get_ticks_usec() - query_start

	assert_int(rows.size()).is_equal(ROW_COUNT)
	assert_str(rows[0]["name"]).is_equal("row_0")
	assert_str(rows[ROW_COUNT - 1]["name"]).is_equal("row_%d" % (ROW_COUNT - 1))
	assert_float(rows[5000]["value"]).is_equal_approx(2500.0, 0.001)

	var insert_ms := insert_usec / 1000.0
	var query_ms := query_usec / 1000.0
	print(
		"WorldDB benchmark: inserted %d rows in %.2f ms (%.2f rows/ms, txn-wrapped), queried back in %.2f ms."
		% [ROW_COUNT, insert_ms, ROW_COUNT / max(insert_ms, 0.001), query_ms]
	)

	db.close()
