extends Node
## PlatformServices (autoload): thin, safe facade over the PC storefront layer (Steam).
##
## Game code only talks to this node. Every call is silent and harmless when no
## backend is available or the player is signed out (editor, tests, DRM-free builds).
## To add Steam: subclass Backend, override the methods you support, and return it
## from _pick_backend() (GodotSteam: https://godotsteam.com, reached via
## Engine.has_singleton("Steam") so this file always parses without the extension).
##
## See docs/platform/ACCOUNTS_AND_SERVICES.md.

signal signed_in_changed(signed_in: bool)
signal achievement_unlocked(id: String)
signal cloud_save_synced(ok: bool)

## Logical achievement name -> storefront id. Fill in from the Steamworks partner site.
## Empty string = not configured yet (the unlock is skipped silently).
const ACHIEVEMENTS: Dictionary = {
	"first_steps": {"steam": ""},
	"first_kill": {"steam": ""},
	"reach_militia": {"steam": ""},
	"discover_10_places": {"steam": ""},
	"survive_first_winter": {"steam": ""},
}

## Logical leaderboard name -> storefront id (same idea as ACHIEVEMENTS).
const LEADERBOARDS: Dictionary = {
	"score": {"steam": ""},
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


## Skeleton for Steamworks via GodotSteam (GDExtension, singleton "Steam").
## Method names must be checked against the installed GodotSteam release before
## filling in the TODOs. Nothing here runs unless the extension is present.
class SteamBackend extends Backend:
	const SINGLETON: String = "Steam"
	var _steam: Object = null
	var _signed_in: bool = false
	var _name: String = ""

	static func plugin_present() -> bool:
		return OS.get_name() in ["Windows", "Linux", "macOS"] and Engine.has_singleton(SINGLETON)

	func _init() -> void:
		if plugin_present():
			_steam = Engine.get_singleton(SINGLETON)

	func name() -> String:
		return "steam"

	func is_available() -> bool:
		return _steam != null

	func sign_in(cb: Callable) -> void:
		# TODO: steamInitEx() / isSteamRunning(), set _signed_in and _name from
		# getPersonaName(), then cb.call(_signed_in).
		if cb.is_valid():
			cb.call(false)

	func is_signed_in() -> bool:
		return _signed_in

	func player_name() -> String:
		return _name

	# TODO: unlock_achievement / increment_achievement (setAchievement, storeStats),
	# submit_score / show_leaderboard (Steam leaderboards), show_achievements (overlay),
	# cloud_save_* via Steam Remote Storage (fileWrite / fileRead), each guarded with
	# `if not _signed_in: return`.


# ---------------------------------------------------------------------------
# Autoload node
# ---------------------------------------------------------------------------

var _backend: Backend = NullBackend.new()
var _was_signed_in: bool = false


func _ready() -> void:
	_backend = _pick_backend()
	print("[services] backend=%s" % _backend.name())


func _pick_backend() -> Backend:
	if SteamBackend.plugin_present():
		return SteamBackend.new()
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
	return str((entry as Dictionary).get("steam", ""))


func _on_sign_in_done(_ok: bool) -> void:
	_update_signed_in()


func _on_cloud_synced(ok: bool) -> void:
	cloud_save_synced.emit(ok)


func _update_signed_in() -> void:
	var now: bool = is_signed_in()
	if now != _was_signed_in:
		_was_signed_in = now
		signed_in_changed.emit(now)
