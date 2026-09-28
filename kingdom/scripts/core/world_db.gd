extends RefCounted
class_name WorldDB
## Thin wrapper around the godot-sqlite GDExtension (kingdom/addons/godot-sqlite,
## MIT, vendored from github.com/2shady4u/godot-sqlite v4.8).
##
## Scope: vendoring + a tiny convenience wrapper only. This class is NOT an
## autoload and is NOT wired into the save system. Nothing in the game calls
## it yet; the cloud session decides if/when world state moves off the
## existing JSON save files and onto this database.
##
## -- Graceful degradation (read this before using) -----------------------
## godot-sqlite ships Windows, Linux, macOS, Android arm64-v8a + x86_64 and
## iOS arm64 binaries, but NOT armeabi-v7a (32-bit ARM Android) -- upstream
## has never shipped that architecture for any Godot 4 GDExtension release
## (checked v4.0 through v4.9). Rising Ashes still exports armeabi-v7a
## (kingdom/export_presets.cfg) for old 32-bit phones, so on those devices
## the "SQLite" class is simply absent at runtime: Godot skips loading a
## GDExtension library for an architecture it has no entry for, it does not
## fail the export or crash the app (see docs/OPEN_SOURCE_AUDIT.md red flag 7
## for the *different* failure mode -- a declared-but-missing binary path --
## which does not apply here since no android arm32 keys are declared in
## addons/godot-sqlite/gdsqlite.gdextension).
##
## Callers MUST check WorldDB.available() before using this class, and MUST
## fall back to the existing JSON save path (see scripts/core/save_manager.gd
## or equivalent) whenever it returns false. Every public method below is
## also individually safe to call when unavailable: open() returns false and
## every other method becomes a no-op that returns an empty/false result
## instead of erroring, so a caller that forgets the availability check still
## fails soft rather than crashing.
##
## -- API ---------------------------------------------------------------
##   WorldDB.available() -> bool                          (static, no instance needed)
##   db.open(path := "user://world.db") -> bool
##   db.exec(sql: String, params: Array = []) -> bool
##   db.query(sql: String, params: Array = []) -> Array[Dictionary]
##   db.begin_transaction() -> bool
##   db.commit_transaction() -> bool
##   db.rollback_transaction() -> bool
##   db.close() -> void
##   db.is_open() -> bool


var _sqlite: Object = null
var _path: String = ""
var _open: bool = false


## True if the godot-sqlite GDExtension class is registered on this build/
## architecture. Check this before doing anything else with WorldDB.
static func available() -> bool:
	return ClassDB.class_exists("SQLite")


## Opens (creating if needed) a SQLite database at `path` (defaults to a
## user:// path, which is safe on mobile -- app-private storage, no
## permissions needed, present on both Android and iOS). Enables WAL mode
## for better concurrent read performance. Returns false, and leaves this
## WorldDB unopened, when godot-sqlite isn't available on this build or the
## file can't be opened; callers must fall back to JSON saves in that case.
func open(path: String = "user://world.db") -> bool:
	if not available():
		push_warning("WorldDB: SQLite GDExtension not available on this build/arch (expected on armeabi-v7a); falling back to JSON saves.")
		return false
	if _open:
		return true

	_sqlite = ClassDB.instantiate(&"SQLite")
	_sqlite.set("path", path)

	var opened: bool = _sqlite.call("open_db")
	if not opened:
		push_warning("WorldDB: failed to open database at '%s'." % path)
		_sqlite = null
		return false

	_path = path
	_open = true

	# WAL mode: readers don't block the writer, better for a game that may
	# read world state on one thread while autosaving on another. godot-sqlite
	# has no dedicated journal_mode property, so this is a plain PRAGMA.
	_sqlite.call("query", "PRAGMA journal_mode=WAL;")

	return true


func is_open() -> bool:
	return _open


## Runs a statement that doesn't return rows (CREATE TABLE, INSERT, UPDATE,
## DELETE, ...) using a prepared statement with bound parameters (`?`
## placeholders in `sql`, values in `params`, in order). Returns true on
## success. No-op (returns false) if the database isn't open.
func exec(sql: String, params: Array = []) -> bool:
	if not _open:
		return false
	if params.is_empty():
		return _sqlite.call("query", sql)
	return _sqlite.call("query_with_bindings", sql, params)


## Runs a SELECT (or any statement that returns rows) using a prepared
## statement with bound parameters, and returns the result as an
## Array[Dictionary] (one Dictionary per row, keyed by column name). Returns
## an empty array on failure or if the database isn't open.
func query(sql: String, params: Array = []) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not _open:
		return rows
	var ok: bool
	if params.is_empty():
		ok = _sqlite.call("query", sql)
	else:
		ok = _sqlite.call("query_with_bindings", sql, params)
	if not ok:
		return rows
	var result: Array = _sqlite.get("query_result")
	for row in result:
		rows.append(row as Dictionary)
	return rows


## Begins a transaction. Wrap batches of inserts/updates in
## begin_transaction()/commit_transaction() -- committing once per batch
## instead of once per statement is the single biggest SQLite performance
## lever (see kingdom/tests/test_world_db.gd for the measured difference).
func begin_transaction() -> bool:
	if not _open:
		return false
	return _sqlite.call("query", "BEGIN TRANSACTION;")


func commit_transaction() -> bool:
	if not _open:
		return false
	return _sqlite.call("query", "COMMIT;")


func rollback_transaction() -> bool:
	if not _open:
		return false
	return _sqlite.call("query", "ROLLBACK;")


## Closes the database. Safe to call even if it was never opened.
func close() -> void:
	if _sqlite != null:
		_sqlite.call("close_db")
	_sqlite = null
	_open = false
	_path = ""
