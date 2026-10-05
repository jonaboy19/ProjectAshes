extends "res://scripts/quests/objective.gd"
## Observe: stay within `range` of `target` and unseen for `seconds` (observe {target, dist, unseen, dt, hour}).
## The world side computes `unseen` with Perception (see Observe.is_unseen). Being seen inside the range starts
## the watch over unless `reset_on_seen` is false. `window` [from, to] limits it to part of the day.
## Data: target, name, range (default 15), seconds (default 10), window, reset_on_seen (default true).

const Perception := preload("res://scripts/population/perception.gd")


func need() -> float:
	return maxf(0.1, float(data.get("seconds", 10.0)))


func _label() -> String:
	var night := " at night" if data.has("window") else ""
	return "Watch %s from a distance without being seen%s" % [String(data.get("name", _noun(String(data.get("target", "the figure"))))), night]


func _counter() -> String:
	return "%d/%d seconds" % [int(have), int(need())]


## True when a watcher at `target_pos` facing `facing` would not see the player at `player_pos` (Perception.vis below VIS_MIN).
static func is_unseen(target_pos: Vector2, facing: Vector2, player_pos: Vector2, light: float, stance := 1.0, still := false) -> bool:
	return Perception.vis(target_pos, facing, player_pos, light, stance, still) < Perception.VIS_MIN


func _handle(t: String, ev: Dictionary) -> void:
	if t != "observe" or not _matches(ev, ["target"]):
		return
	if not in_window(data.get("window", null), float(ev.get("hour", 12.0))):
		return
	if float(ev.get("dist", INF)) > float(data.get("range", 15.0)):
		return
	if bool(ev.get("unseen", false)):
		have += float(ev.get("dt", 0.0))
	elif bool(data.get("reset_on_seen", true)):
		have = 0.0
