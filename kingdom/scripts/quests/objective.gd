extends RefCounted
## Base of every quest objective. An objective is built from a JSON dictionary (`setup`), listens to the
## shared QuestBus through `on_event`, and reports `progress()` (0..1), `is_done()`, `is_failed()` and
## `describe()` (plain words for the journal). `save()` is JSON-safe and carries the data, so it restores
## without the definition. Subclasses override `_handle`, `_label`, `need` and `_save_extra`/`_load_extra`.
##
## Common data keys: id, type, text (replaces the generated label), optional (does not block a stage),
## pos [x, y] (optional position, only shown to the player when the quest is pinned).

var data: Dictionary = {}
var id := ""
var type := ""
var optional := false
var done := false
var failed := false
## Progress in the objective's own units (kills, hours, seconds, clues, ...).
var have := 0.0


func setup(d: Dictionary) -> RefCounted:
	data = d.duplicate(true)
	id = String(d.get("id", ""))
	type = String(d.get("type", ""))
	optional = bool(d.get("optional", false))
	_setup()
	return self


func _setup() -> void:
	pass


## Units needed to finish (1 for yes/no objectives).
func need() -> float:
	return 1.0


func progress() -> float:
	if done:
		return 1.0
	return clampf(have / maxf(need(), 0.0001), 0.0, 1.0)


func is_done() -> bool:
	return done


func is_failed() -> bool:
	return failed


## Feeds one bus event. Returns true when the objective's state changed.
func on_event(t: StringName, ev: Dictionary) -> bool:
	if done or failed:
		return false
	var before := [have, done, failed]
	_handle(String(t), ev)
	if not failed and not done and have >= need() - 0.0001 and _complete_by_units():
		done = true
		have = maxf(have, need())
	return before != [have, done, failed]


## Objectives finished by something other than their unit count override this to false.
func _complete_by_units() -> bool:
	return true


func _handle(_t: String, _ev: Dictionary) -> void:
	pass


## The plain-words journal line, e.g. "Kill 3 wolves (1/3)".
func describe() -> String:
	var s := String(data.get("text", "")) if data.has("text") else _label()
	if failed:
		return s + " (failed)"
	if done:
		return s + " (done)"
	var c := _counter()
	return s + (" (%s)" % c if c != "" else "")


func _label() -> String:
	return type.capitalize()


## "2/3" for counted objectives, "" for yes/no ones.
func _counter() -> String:
	return ""


## Where the objective is, for a pinned marker. Vector2 or null.
func marker_pos() -> Variant:
	return _vec(data.get("pos", null))


# --- helpers for subclasses -------------------------------------------------------------

## True when every key the objective sets equals the event's (case-insensitive strings).
func _matches(ev: Dictionary, keys: Array) -> bool:
	for k: String in keys:
		if data.has(k) and String(data[k]) != "" and String(ev.get(k, "")).to_lower() != String(data[k]).to_lower():
			return false
	return true


static func _vec(v: Variant) -> Variant:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return null


## Position carried by an event: {x, y} or pos [x, y]. Vector2.INF when absent.
static func event_pos(ev: Dictionary) -> Vector2:
	if ev.has("x") and ev.has("y"):
		return Vector2(float(ev["x"]), float(ev["y"]))
	var p: Variant = _vec(ev.get("pos", null))
	return p if p is Vector2 else Vector2.INF


## True when `hour` lies in [from, to) (wraps past midnight). No window means always.
static func in_window(window: Variant, hour: float) -> bool:
	if not (window is Array) or (window as Array).size() < 2:
		return true
	var a := float(window[0])
	var b := float(window[1])
	return (hour >= a and hour < b) if a <= b else (hour >= a or hour < b)


func _noun(s: String) -> String:
	return s.replace("_", " ")


# --- save -------------------------------------------------------------------------------

func save() -> Dictionary:
	var d := {"id": id, "type": type, "data": data.duplicate(true), "done": done, "failed": failed, "have": have}
	d.merge(_save_extra())
	return d


func load_state(d: Dictionary) -> void:
	done = bool(d.get("done", false))
	failed = bool(d.get("failed", false))
	have = float(d.get("have", 0.0))
	_load_extra(d)


func _save_extra() -> Dictionary:
	return {}


func _load_extra(_d: Dictionary) -> void:
	pass
