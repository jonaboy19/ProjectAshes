extends Node
## PlatformServices (autoload): thin, safe facade over Google Play Games / Apple Game Center.
##
## Game code only talks to this node. Every call is silent and harmless when no
## backend is available or the player is signed out (desktop, editor, tests).
## To add a real backend: subclass Backend, override the methods you support,
## and return it from _pick_backend(). Plugin classes must only be reached via
## Engine.has_singleton() / ClassDB (dynamic calls) so this file always parses on desktop.
##
## See docs/platform/ACCOUNTS_AND_SERVICES.md.

signal signed_in_changed(signed_in: bool)
signal achievement_unlocked(id: String)
signal cloud_save_synced(ok: bool)

## Logical achievement name -> per-platform id. Fill in from Play Console / App Store Connect.
## Empty string = not configured yet (the unlock is skipped silently).
const ACHIEVEMENTS: Dictionary = {
	"first_steps": {"android": "", "ios": ""},
	"first_kill": {"android": "", "ios": ""},
	"reach_militia": {"android": "", "ios": ""},
	"discover_10_places": {"android": "", "ios": ""},
	"survive_first_winter": {"android": "", "ios": ""},
}

## Logical leaderboard name -> per-platform id (same idea as ACHIEVEMENTS).
const LEADERBOARDS: Dictionary = {
	"score": {"android": "", "ios": ""},
}


# ---------------------------------------------------------------------------
# Backend interface
# ---------------------------------------------------------------------------

class Backend extends RefCounted:
	func name() -> String:
		return "base"

	func is_available() -> bool:
		return false

	## cb(ok: bool) is called when the attempt finishes.
	func sign_in(cb: Callable) -> void:
		if cb.is_valid():
			cb.call(false)

	func sign_out() -> void:
		pass

	func is_signed_in() -> bool:
		return false

	func player_name() -> String:
		return ""

	func unlock_achievement(_id: String) -> void:
		pass

	func increment_achievement(_id: String, _steps: int) -> void:
		pass

	func submit_score(_board_id: String, _score: int) -> void:
		pass

	func show_achievements() -> void:
		pass

	func show_leaderboard(_board_id: String) -> void:
		pass

	## cb(ok: bool)
	func cloud_save_upload(_slot: String, _bytes: PackedByteArray, cb: Callable) -> void:
		if cb.is_valid():
			cb.call(false)

	## cb(ok: bool, bytes: PackedByteArray)
	func cloud_save_download(_slot: String, cb: Callable) -> void:
		if cb.is_valid():
			cb.call(false, PackedByteArray())


class NullBackend extends Backend:
	func name() -> String:
		return "null"


## Skeleton for Google Play Games Services v2 (plugin "GodotPlayGameServices",
## https://github.com/godot-sdk-integrations/godot-play-game-services).
## The plugin's exact Android singleton name and method names must be checked
## against the installed release before filling in the TODOs.
class GooglePlayBackend extends Backend:
	const SINGLETON: String = "GodotPlayGameServices"
	var _singleton: Object = null
	var _signed_in: bool = false
	var _name: String = ""

	static func plugin_present() -> bool:
		return OS.get_name() == "Android" and Engine.has_singleton(SINGLETON)

	func _init() -> void:
		if plugin_present():
			_singleton = Engine.get_singleton(SINGLETON)

	func name() -> String:
		return "google_play"

	func is_available() -> bool:
		return _singleton != null

	func sign_in(cb: Callable) -> void:
		# TODO: call the plugin's sign-in (e.g. _singleton.call("signIn")), connect its
		# result signal, set _signed_in / _name, then cb.call(_signed_in).
		if cb.is_valid():
			cb.call(false)

	func is_signed_in() -> bool:
		return _signed_in

	func player_name() -> String:
		return _name

	# TODO: unlock_achievement / increment_achievement / submit_score / show_* /
	# cloud_save_* via _singleton.call(...) guarded with `if not _signed_in: return`.
	# Cloud save maps to Play Games "Saved Games" (snapshots).


## Skeleton for Apple Game Center via GodotApplePlugins
## (https://github.com/migueldeicaza/GodotApplePlugins, class GameCenterManager).
## It is a GDExtension, so ClassDB can see it; on desktop the addon ships stubs.
class GameCenterBackend extends Backend:
	const MANAGER_CLASS: String = "GameCenterManager"
	var _manager: Object = null
	var _signed_in: bool = false

	static func plugin_present() -> bool:
		return OS.get_name() == "iOS" and ClassDB.class_exists(MANAGER_CLASS)

	func _init() -> void:
		if plugin_present():
			_manager = ClassDB.instantiate(MANAGER_CLASS)

	func name() -> String:
		return "game_center"

	func is_available() -> bool:
		return _manager != null

	func sign_in(cb: Callable) -> void:
		# TODO: connect _manager "authentication_result" / "authentication_error",
		# call _manager.call("authenticate"), set _signed_in, then cb.call(_signed_in).
		if cb.is_valid():
			cb.call(false)

	func is_signed_in() -> bool:
		return _signed_in

	# TODO: achievements / leaderboards via the GK* classes; cloud save via
	# iCloud key-value or Saved Games (GKSavedGame) once the addon exposes it.


# ---------------------------------------------------------------------------
# Autoload node
# ---------------------------------------------------------------------------

var _backend: Backend = NullBackend.new()
var _was_signed_in: bool = false


func _ready() -> void:
	_backend = _pick_backend()
	print("[services] backend=%s" % _backend.name())


func _pick_backend() -> Backend:
	if GooglePlayBackend.plugin_present():
		return GooglePlayBackend.new()
	if GameCenterBackend.plugin_present():
		return GameCenterBackend.new()
	return NullBackend.new()


func backend_name() -> String:
	return _backend.name()


func is_signed_in() -> bool:
	return _backend.is_available() and _backend.is_signed_in()


func player_name() -> String:
	return _backend.player_name() if is_signed_in() else ""


func sign_in() -> void:
	if not _backend.is_available():
		return
	_backend.sign_in(_on_sign_in_done)


func sign_out() -> void:
	_backend.sign_out()
	_update_signed_in()


func unlock(id: String) -> void:
	if not is_signed_in():
		return
	var pid: String = _platform_id(ACHIEVEMENTS, id)
	if pid.is_empty():
		return
	_backend.unlock_achievement(pid)
	achievement_unlocked.emit(id)


func increment(id: String, steps: int = 1) -> void:
	if not is_signed_in():
		return
	var pid: String = _platform_id(ACHIEVEMENTS, id)
	if not pid.is_empty():
		_backend.increment_achievement(pid, steps)


func submit_score(board: String, score: int) -> void:
	if not is_signed_in():
		return
	var pid: String = _platform_id(LEADERBOARDS, board)
	if not pid.is_empty():
		_backend.submit_score(pid, score)


func show_achievements() -> void:
	if is_signed_in():
		_backend.show_achievements()


func show_leaderboard(board: String) -> void:
	if not is_signed_in():
		return
	var pid: String = _platform_id(LEADERBOARDS, board)
	if not pid.is_empty():
		_backend.show_leaderboard(pid)


func upload_cloud_save(slot: String, bytes: PackedByteArray) -> void:
	if not is_signed_in():
		return
	_backend.cloud_save_upload(slot, bytes, _on_cloud_synced)


## cb(ok: bool, bytes: PackedByteArray). Always called, even when unavailable.
func download_cloud_save(slot: String, cb: Callable) -> void:
	if not is_signed_in():
		if cb.is_valid():
			cb.call(false, PackedByteArray())
		return
	_backend.cloud_save_download(slot, func(ok: bool, bytes: PackedByteArray) -> void:
		cloud_save_synced.emit(ok)
		if cb.is_valid():
			cb.call(ok, bytes))


func _platform_id(table: Dictionary, logical: String) -> String:
	var entry: Variant = table.get(logical)
	if not (entry is Dictionary):
		return ""
	var key: String = "android" if OS.get_name() == "Android" else "ios"
	return str((entry as Dictionary).get(key, ""))


func _on_sign_in_done(_ok: bool) -> void:
	_update_signed_in()


func _on_cloud_synced(ok: bool) -> void:
	cloud_save_synced.emit(ok)


func _update_signed_in() -> void:
	var now: bool = is_signed_in()
	if now != _was_signed_in:
		_was_signed_in = now
		signed_in_changed.emit(now)
