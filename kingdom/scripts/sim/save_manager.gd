extends Node
## Save system: 3 manual slots, 3 rotating autosaves and a quicksave, as JSON
## files in user://saves/ (portable between phones: no device-bound encryption).
##
## Every save is written atomically: the text goes to `<slot>.json.tmp`, is read
## back and checked, the previous `<slot>.json` becomes `<slot>.json.bak`, and
## only then is the temp file renamed into place. A crash at any point leaves
## either the old save, the backup, or the new save intact, never half a file.
##
## File envelope (schema 2):
##   {"schema": 2, "meta": {...}, "checksum": "<md5 of the data text>", "data": {...}}
## `meta` (character name, age, title, day, time, location, playtime, game
## version, when, kind) is also cached in `<slot>.meta.json` so the save screen
## never parses a whole world, and `<slot>.png` holds a small thumbnail.
##
## Loading validates (parse, schema, checksum, required keys), runs the
## MIGRATIONS table up to SCHEMA_VERSION, and falls back to the backup (then to
## a complete temp file) with a readable `last_error` when the main file is bad.
##
## Autosaves: every 10 real minutes, after sleeping / any big time skip, on
## entering or leaving a settlement, before fast travel (hook), and on quitting
## or going to the background. Never in combat (a live "team1" node near the
## player) or while any node is in the "cutscene_active" group.
##
## Ideas (named slots, checkpoints, autosave, recovery, migration) follow
## youssof20/savestate (MIT); this is an independent rewrite for Rising Ashes.
##
## Owned by Life: `Life.saves`. Standalone use (tests):
##   var m := preload("res://scripts/sim/save_manager.gd").new()
##   m.root_dir = "user://test_saves/"; m.snapshot_fn = ...; m.restore_fn = ...

signal saved(slot_id: String, ok: bool)
signal loaded(slot_id: String, ok: bool)
## A readable problem for the player (damaged file, backup used, disk full...).
signal problem(text: String)

const SCHEMA_VERSION := 2
const MANUAL_SLOTS := 3
const AUTO_SLOTS := 3
const QUICK := "quick"
const AUTOSAVE_INTERVAL := 600.0        # real seconds
## Two autosaves closer than this collapse into one (except on quit / background).
const AUTOSAVE_MIN_GAP := 30.0
const HOSTILE_RADIUS := 30.0
const THUMB_SIZE := Vector2i(240, 135)
const LEGACY_PATH := "user://save_%d.json"
## Time skip (in-game hours in one frame) that counts as sleeping / waiting.
const REST_SKIP_HOURS := 1.0
const SETTLEMENT_POLL := 1.0
const SETTLEMENT_EXIT_FACTOR := 1.25

## Migration hooks: from-schema -> method name taking the envelope and returning
## it at from+1. Add `2: "_migrate_2_to_3"` (and bump SCHEMA_VERSION) when the
## save layout changes; keep old steps so any save can climb to the current one.
const MIGRATIONS := {
	1: "_migrate_1_to_2",
}

var root_dir := "user://saves/"
## () -> Dictionary: the game state to save. Defaults to Life.snapshot().
var snapshot_fn: Callable
## (Dictionary) -> void: applies a loaded state. Defaults to Life.restore().
var restore_fn: Callable
## () -> Dictionary: extra/override metadata merged over the defaults.
var meta_fn: Callable
## Tests set this; otherwise Life.player.
var player_override: Node3D
## Top-level keys the data must carry to count as a real save (empty = any).
var required_keys: Array = ["world", "game"]
var autosave_enabled := true
var capture_thumbnails := true
## Real seconds played in this run of the character (carried in every save).
var playtime := 0.0
## The last readable error (empty when the last operation went fine).
var last_error := ""
## Slot id of the last successful save or load.
var last_slot := ""

var _auto_timer := 0.0
var _last_autosave_ms := -1
var _quiet_until_ms := 0
var _settlement := -2              # -2 unknown, -1 outside, else settlement index
var _settle_poll := 0.0
var _last_abs_hours := -1.0
var _migrated_legacy := false


func _ready() -> void:
	migrate_legacy()


func _process(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	playtime += delta
	if not autosave_enabled:
		return
	_auto_timer += delta
	if _auto_timer >= AUTOSAVE_INTERVAL:
		if autosave("timer", true) != "":
			_auto_timer = 0.0
		else:
			_auto_timer = AUTOSAVE_INTERVAL - 5.0   # busy (combat): retry in a few seconds
	_watch_time_skip()
	_settle_poll += delta
	if _settle_poll >= SETTLEMENT_POLL:
		_settle_poll = 0.0
		_watch_settlement(p)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		# The app may be killed right after this: save now, without the GPU readback.
		if _player() != null:
			autosave("background" if what == NOTIFICATION_APPLICATION_PAUSED else "quit", false, true)


# --- slots -----------------------------------------------------------------------

static func manual_id(n: int) -> String:
	return "manual_%d" % n


static func auto_id(n: int) -> String:
	return "auto_%d" % n


## Every slot id in display order: quicksave, manual 1-3, autosave 1-3.
static func all_ids() -> PackedStringArray:
	var out := PackedStringArray([QUICK])
	for i in MANUAL_SLOTS:
		out.append(manual_id(i + 1))
	for i in AUTO_SLOTS:
		out.append(auto_id(i + 1))
	return out


static func slot_label(id: String) -> String:
	if id == QUICK:
		return "Quicksave"
	if id.begins_with("manual_"):
		return "Slot %s" % id.trim_prefix("manual_")
	if id.begins_with("auto_"):
		return "Autosave %s" % id.trim_prefix("auto_")
	return id.capitalize()


static func is_valid_id(id: String) -> bool:
	return id in all_ids()


func path_of(id: String) -> String:
	return root_dir.path_join(id + ".json")


func thumb_path(id: String) -> String:
	return root_dir.path_join(id + ".png")


func meta_path(id: String) -> String:
	return root_dir.path_join(id + ".meta.json")


func has_slot(id: String) -> bool:
	var p := path_of(id)
	return FileAccess.file_exists(p) or FileAccess.file_exists(p + ".bak")


## Metadata for one slot ({} if empty). Reads the small sidecar, falling back
## to the save itself when the sidecar is missing or damaged.
func slot_meta(id: String) -> Dictionary:
	if not has_slot(id):
		return {}
	var m: Variant = _read_json(meta_path(id))
	if m is Dictionary and not (m as Dictionary).is_empty():
		return m
	var env := _read_valid(path_of(id))
	if env.is_empty():
		env = _read_valid(path_of(id) + ".bak")
	return env.get("meta", {"damaged": true})


## [{id, label, kind, exists, meta, thumb (path or "")}] for every slot.
func list_slots() -> Array:
	var out := []
	for id in all_ids():
		var exists := has_slot(id)
		out.append({"id": id, "label": slot_label(id), "kind": _kind(id), "exists": exists,
			"meta": slot_meta(id) if exists else {},
			"thumb": thumb_path(id) if exists and FileAccess.file_exists(thumb_path(id)) else ""})
	return out


## The newest existing save of any kind ("" if none).
func latest_id() -> String:
	var best := ""
	var best_t := -INF
	for id in all_ids():
		if not has_slot(id):
			continue
		var t := float(slot_meta(id).get("saved_at", 0.0))
		if t > best_t:
			best_t = t
			best = id
	return best


func load_thumbnail(id: String) -> Texture2D:
	var p := thumb_path(id)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


func delete_slot(id: String) -> bool:
	if not is_valid_id(id):
		return false
	var any := false
	for p: String in [path_of(id), path_of(id) + ".bak", path_of(id) + ".tmp", meta_path(id), thumb_path(id)]:
		if FileAccess.file_exists(p):
			any = DirAccess.remove_absolute(_abs(p)) == OK or any
	return any


# --- save ------------------------------------------------------------------------

## Saves the current game into `id`. `thumb` grabs a small viewport screenshot.
func save_slot(id: String, reason := "manual", thumb := true) -> bool:
	last_error = ""
	if not is_valid_id(id):
		return _fail("Unknown save slot '%s'." % id)
	var data: Dictionary = _snapshot()
	if data.is_empty():
		return _fail("Nothing to save yet.")
	var ok := write_envelope(id, data, _build_meta(id, reason))
	if ok:
		last_slot = id
		if thumb and capture_thumbnails:
			_save_thumbnail(id)
	saved.emit(id, ok)
	return ok


func quick_save() -> bool:
	return save_slot(QUICK, "quick")


## Writes `data` + `meta` into slot `id` atomically, keeping the previous file
## as the backup. Public so tools and tests can write a known state.
func write_envelope(id: String, data: Dictionary, meta: Dictionary) -> bool:
	if not _ensure_dir():
		return _fail("Could not create the save folder.")
	var data_text := JSON.stringify(data)
	meta.erase("data")              # the data section must be the only "data" key
	meta["schema"] = SCHEMA_VERSION
	var text := _envelope_text(meta, data_text)
	if not _atomic_write(path_of(id), text, true):
		return false
	_atomic_write(meta_path(id), JSON.stringify(meta, "\t"), false)
	return true


## Autosaves into the oldest of the rotating slots. Returns the slot id, or ""
## when skipped (in combat, cutscene, too soon after the last one, no game).
func autosave(reason := "auto", thumb := true, force := false) -> String:
	if not autosave_enabled or not can_autosave():
		return ""
	var now := Time.get_ticks_msec()
	if not force and (now < _quiet_until_ms
			or (_last_autosave_ms >= 0 and now - _last_autosave_ms < AUTOSAVE_MIN_GAP * 1000.0)):
		return ""
	var id := next_auto_id()
	if not save_slot(id, reason, thumb):
		return ""
	_last_autosave_ms = now
	_auto_timer = 0.0
	return id


## The rotating slot the next autosave overwrites: an empty one, else the oldest.
func next_auto_id() -> String:
	var best := ""
	var best_serial := INF
	for i in AUTO_SLOTS:
		var id := auto_id(i + 1)
		if not has_slot(id):
			return id
		var s := float(slot_meta(id).get("serial", 0))
		if s < best_serial:
			best_serial = s
			best = id
	return best


## True when an autosave is safe: a game is running, no cutscene, no hostile
## ("team1") alive within HOSTILE_RADIUS of the player.
func can_autosave() -> bool:
	var p := _player()
	if p == null or not is_inside_tree():
		return false
	var tree := get_tree()
	if not tree.get_nodes_in_group("cutscene_active").is_empty():
		return false
	var hp: Variant = p.get("health")
	if hp != null and float(hp) <= 0.0:
		return false
	for e in tree.get_nodes_in_group("team1"):
		if e == p or not e is Node3D or not is_instance_valid(e):
			continue
		if e.get("dead") == true:
			continue
		if (e as Node3D).global_position.distance_to(p.global_position) < HOSTILE_RADIUS:
			return false
	return true


# --- load ------------------------------------------------------------------------

## Loads `id`: validates, migrates, falls back to the backup if needed, then
## restores. Returns false (with `last_error`) when nothing usable was found.
func load_slot(id: String) -> bool:
	var env := read_slot(id)
	if env.is_empty():
		loaded.emit(id, false)
		return false
	_restore(env["data"])
	playtime = float((env.get("meta", {}) as Dictionary).get("playtime", playtime))
	last_slot = id
	_settlement = -2
	_last_abs_hours = -1.0
	_auto_timer = 0.0
	_quiet_until_ms = Time.get_ticks_msec() + 5000
	loaded.emit(id, true)
	return true


func quick_load() -> bool:
	return load_slot(QUICK)


## The validated, migrated envelope of `id` without restoring it ({} on failure,
## with `last_error` set). Falls back to `.bak`, then to a complete `.tmp`.
func read_slot(id: String) -> Dictionary:
	last_error = ""
	if not is_valid_id(id):
		_fail("Unknown save slot '%s'." % id)
		return {}
	var p := path_of(id)
	if not FileAccess.file_exists(p) and not FileAccess.file_exists(p + ".bak"):
		_fail("%s is empty." % slot_label(id))
		return {}
	var errors := PackedStringArray()
	for candidate: String in [p, p + ".bak", p + ".tmp"]:
		if not FileAccess.file_exists(candidate):
			continue
		var why := []
		var env := _read_valid(candidate, why)
		if not env.is_empty():
			if candidate != p:
				last_error = "%s was damaged (%s). Loaded the %s instead." % [slot_label(id),
					errors[0] if not errors.is_empty() else "missing",
					"backup" if candidate.ends_with(".bak") else "unfinished save"]
				problem.emit(last_error)
			return env
		errors.append(why[0] if not why.is_empty() else "unreadable")
	_fail("%s could not be loaded: %s." % [slot_label(id), "; ".join(errors)])
	return {}


## Parses and validates one file into a current-schema envelope ({} if bad; the
## reason goes into `why`).
func _read_valid(path: String, why: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path):
		why.append("file missing")
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		why.append("file is empty")
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		why.append("not valid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		why.append("not a save file")
		return {}
	var env: Dictionary = json.data
	if env.has("schema"):
		var sum := String(env.get("checksum", ""))
		if sum != "":
			var data_text := _data_text(text)
			if data_text.md5_text() != sum:
				why.append("checksum mismatch (file corrupted)")
				return {}
	else:
		# Schema 1: the old single-file save was the raw Life.snapshot().
		env = {"schema": 1, "meta": {}, "data": env}
	var schema := int(env.get("schema", 0))
	if schema > SCHEMA_VERSION:
		why.append("made by a newer version of the game (save v%d, game v%d)" % [schema, SCHEMA_VERSION])
		return {}
	env = migrate(env, why)
	if env.is_empty():
		return {}
	if not env.get("data") is Dictionary:
		why.append("no game data")
		return {}
	var data: Dictionary = env["data"]
	for k: String in required_keys:
		if not data.has(k):
			why.append("missing '%s' section" % k)
			return {}
	if not env.get("meta") is Dictionary:
		env["meta"] = {}
	return env


## Runs MIGRATIONS until the envelope reaches SCHEMA_VERSION ({} if a step is missing).
func migrate(env: Dictionary, why: Array = []) -> Dictionary:
	var schema := int(env.get("schema", 1))
	while schema < SCHEMA_VERSION:
		if not MIGRATIONS.has(schema) or not has_method(MIGRATIONS[schema]):
			why.append("no migration from save v%d" % schema)
			return {}
		env = call(MIGRATIONS[schema], env)
		if env.is_empty() or int(env.get("schema", 0)) != schema + 1:
			why.append("migration from save v%d failed" % schema)
			return {}
		schema += 1
	return env


## v1 (raw snapshot, user://save_N.json) -> v2 envelope with metadata derived
## from the data itself.
func _migrate_1_to_2(env: Dictionary) -> Dictionary:
	var data: Variant = env.get("data")
	if not data is Dictionary:
		return {}
	var d: Dictionary = data
	var world: Dictionary = d.get("world", {}) if d.get("world") is Dictionary else {}
	var lp: Dictionary = d.get("life_path", {}) if d.get("life_path") is Dictionary else {}
	var meta: Dictionary = (env.get("meta", {}) as Dictionary).duplicate()
	var char_name := ("%s %s" % [lp.get("given_name", ""), lp.get("family_name", "")]).strip_edges()
	meta.merge({"name": char_name if char_name != "" else "Wanderer", "age": -1, "title": "",
		"day": int(world.get("day", 1)), "time": float(world.get("time", 8.0)),
		"location": "", "playtime": 0.0, "game_version": "legacy", "saved_at": 0.0,
		"saved_at_text": "", "kind": "manual", "reason": "migrated", "serial": 0})
	meta["schema"] = 2
	return {"schema": 2, "meta": meta, "data": d}


## Moves the old single-file saves (user://save_N.json) into manual slot N once.
## The old file is kept, renamed to `.migrated`.
func migrate_legacy() -> int:
	if _migrated_legacy:
		return 0
	_migrated_legacy = true
	var moved := 0
	for n in MANUAL_SLOTS:
		var old := LEGACY_PATH % (n + 1)
		var id := manual_id(n + 1)
		if not FileAccess.file_exists(old) or has_slot(id):
			continue
		var why := []
		var env := _read_valid(old, why)
		if env.is_empty():
			push_warning("[save] legacy %s not migrated: %s" % [old, ", ".join(why)])
			continue
		var meta: Dictionary = env["meta"]
		meta["saved_at"] = float(FileAccess.get_modified_time(old))
		meta["saved_at_text"] = Time.get_datetime_string_from_unix_time(int(meta["saved_at"]), true)
		if write_envelope(id, env["data"], meta):
			DirAccess.rename_absolute(_abs(old), _abs(old + ".migrated"))
			moved += 1
	return moved


# --- metadata --------------------------------------------------------------------

func _build_meta(id: String, reason: String) -> Dictionary:
	var m := {"name": "Wanderer", "age": -1, "title": "", "day": 1, "time": 8.0, "location": "",
		"playtime": playtime, "game_version": game_version(), "kind": _kind(id), "reason": reason,
		"saved_at": Time.get_unix_time_from_system(),
		"saved_at_text": Time.get_datetime_string_from_system(false, true),
		"platform": OS.get_name(), "serial": _next_serial()}
	m.merge(_life_meta(), true)
	if meta_fn.is_valid():
		m.merge(meta_fn.call(), true)
	return m


func _life_meta() -> Dictionary:
	var life := get_node_or_null("/root/Life")
	var ws := get_node_or_null("/root/WorldSim")
	var m := {}
	if ws:
		m["day"] = int(ws.get("day"))
		m["time"] = float(ws.get("time_of_day"))
	if life == null or not life.get("life_path"):
		return m
	var lp: RefCounted = life.get("life_path")
	var n := String(lp.call("full_name"))
	if n != "":
		m["name"] = n
	if life.has_method("age"):
		m["age"] = int(life.call("age"))
	var title := ""
	var titles: RefCounted = life.get("titles")
	if titles and titles.has_method("earned_list"):
		var got: Array = titles.call("earned_list")
		if not got.is_empty():
			title = String((got[-1] as Dictionary).get("name", ""))
	if title == "" and ws and lp.has_method("stage_name"):
		title = String(lp.call("stage_name", int(ws.get("day")), float(ws.get("time_of_day"))))
	m["title"] = title
	m["location"] = location_name()
	return m


## "Emberfall", "Near Emberfall", a named wild place, or "The wilds".
func location_name() -> String:
	var p := _player()
	if p == null:
		return ""
	var at := Vector2(p.global_position.x, p.global_position.z)
	var near: Dictionary = WorldGen.nearest_settlement(at) if not WorldGen.settlements.is_empty() else {}
	if not near.is_empty():
		var d := at.distance_to(near["pos"])
		if d <= float(near["radius"]) * SETTLEMENT_EXIT_FACTOR:
			return String(near["name"])
	var life := get_node_or_null("/root/Life")
	if life and life.has_method("place_at"):
		var pl: Dictionary = life.call("place_at", at)
		if not pl.is_empty() and String(pl.get("name", "")) != "":
			return String(pl["name"])
	if not near.is_empty() and at.distance_to(near["pos"]) < float(near["radius"]) * 4.0:
		return "Near %s" % near["name"]
	return "The wilds"


static func game_version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "0.1.0"


func _next_serial() -> int:
	var hi := 0
	for id in all_ids():
		if has_slot(id):
			hi = maxi(hi, int(slot_meta(id).get("serial", 0)))
	return hi + 1


static func _kind(id: String) -> String:
	if id == QUICK:
		return "quick"
	return "auto" if id.begins_with("auto_") else "manual"


# --- autosave triggers -----------------------------------------------------------

## A big in-game time jump in one frame means sleeping or waiting.
func _watch_time_skip() -> void:
	var ws := get_node_or_null("/root/WorldSim")
	if ws == null:
		return
	var now := int(ws.get("day")) * 24.0 + float(ws.get("time_of_day"))
	if _last_abs_hours >= 0.0 and now - _last_abs_hours >= REST_SKIP_HOURS:
		autosave("rest")
	_last_abs_hours = now


func _watch_settlement(p: Node3D) -> void:
	if WorldGen.settlements.is_empty():
		return
	var at := Vector2(p.global_position.x, p.global_position.z)
	var now := _settlement
	if _settlement >= 0 and _settlement < WorldGen.settlements.size():
		var s: Dictionary = WorldGen.settlements[_settlement]
		if at.distance_to(s["pos"]) > float(s["radius"]) * SETTLEMENT_EXIT_FACTOR:
			now = -1
	else:
		now = -1
	if now == -1:
		for i in WorldGen.settlements.size():
			var s: Dictionary = WorldGen.settlements[i]
			if at.distance_to(s["pos"]) <= float(s["radius"]):
				now = i
				break
	if now == _settlement:
		return
	var was := _settlement
	_settlement = now
	if was == -2:
		return          # first reading after start / load: no save
	var s_name := String(WorldGen.settlements[now if now >= 0 else was]["name"])
	autosave(("enter:" if now >= 0 else "leave:") + s_name)


# --- internals -------------------------------------------------------------------

func _player() -> Node3D:
	if player_override and is_instance_valid(player_override):
		return player_override
	var life := get_node_or_null("/root/Life")
	if life == null:
		return null
	var p: Variant = life.get("player")
	# is_instance_valid() MUST run before `p is Node3D`: once the player node is freed
	# (death/respawn, scene reload, a QA harness freeing the game scene on exit), `p`
	# is a dangling reference and `is` on it throws "Left operand of 'is' is a
	# previously freed instance" -- every frame, since this runs from _process(). Found
	# during the stability soak (docs/qa/stability.md): it flooded the log and kept
	# SaveManager polling a dead node instead of going quiet.
	return p if is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree() else null


func _snapshot() -> Dictionary:
	if snapshot_fn.is_valid():
		return snapshot_fn.call()
	var life := get_node_or_null("/root/Life")
	return life.call("snapshot") if life else {}


func _restore(data: Dictionary) -> void:
	if restore_fn.is_valid():
		restore_fn.call(data)
		return
	var life := get_node_or_null("/root/Life")
	if life:
		life.call("restore", data)


func _fail(msg: String) -> bool:
	last_error = msg
	push_warning("[save] " + msg)
	problem.emit(msg)
	return false


func _ensure_dir() -> bool:
	return DirAccess.dir_exists_absolute(_abs(root_dir)) or DirAccess.make_dir_recursive_absolute(_abs(root_dir)) == OK


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## meta and checksum first, data last, so the data text can be cut out and
## hashed exactly as written.
static func _envelope_text(meta: Dictionary, data_text: String) -> String:
	return '{"schema":%d,"meta":%s,"checksum":"%s","data":%s}' % [SCHEMA_VERSION,
		JSON.stringify(meta), data_text.md5_text(), data_text]


static func _data_text(text: String) -> String:
	var at := text.find(',"data":')
	if at < 0:
		return ""
	var body := text.substr(at + 8).strip_edges()
	return body.substr(0, body.length() - 1) if body.ends_with("}") else body


## tmp -> verify -> (old -> .bak) -> rename. Returns false and leaves the old
## file (or its backup) in place on any failure.
func _atomic_write(path: String, text: String, keep_backup: bool) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("Could not write the save (%s)." % error_string(FileAccess.get_open_error()))
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	var expect := text.to_utf8_buffer().size()
	if err != OK or FileAccess.get_file_as_bytes(tmp).size() != expect:
		DirAccess.remove_absolute(_abs(tmp))
		return _fail("The save did not finish writing (disk full?). Your previous save is untouched.")
	var bak := path + ".bak"
	var had_old := FileAccess.file_exists(path)
	if had_old:
		if keep_backup:
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(_abs(bak))
			if DirAccess.rename_absolute(_abs(path), _abs(bak)) != OK:
				DirAccess.remove_absolute(_abs(tmp))
				return _fail("Could not keep a backup of the previous save.")
		else:
			DirAccess.remove_absolute(_abs(path))
	if DirAccess.rename_absolute(_abs(tmp), _abs(path)) != OK:
		if had_old and keep_backup:
			DirAccess.copy_absolute(_abs(bak), _abs(path))
		return _fail("Could not finish the save (rename failed).")
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _save_thumbnail(id: String) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	# Crop to 16:9 around the centre, then shrink.
	var sz := img.get_size()
	var want := Vector2i(sz.x, int(sz.x * 9.0 / 16.0))
	if want.y > sz.y:
		want = Vector2i(int(sz.y * 16.0 / 9.0), sz.y)
	if want != sz:
		img = img.get_region(Rect2i((sz - want) / 2, want))
	img.convert(Image.FORMAT_RGB8)
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var png := img.save_png_to_buffer()
	var tmp := thumb_path(id) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(png)
	f.close()
	if FileAccess.file_exists(thumb_path(id)):
		DirAccess.remove_absolute(_abs(thumb_path(id)))
	DirAccess.rename_absolute(_abs(tmp), _abs(thumb_path(id)))


## Test / tooling hook: clears the autosave debounce and quiet window.
func reset_autosave_clock() -> void:
	_last_autosave_ms = -1
	_quiet_until_ms = 0
	_auto_timer = 0.0
