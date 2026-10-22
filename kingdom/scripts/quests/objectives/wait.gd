extends "res://scripts/quests/objective.gd"
## Wait: let `hours` of WorldSim time pass (hours {amount, hour}). With `window` [from, to] only the hours
## that start inside that part of the day count (e.g. [21, 5] waits through the night). Data: hours, window, text.


func need() -> float:
	return maxf(0.01, float(data.get("hours", 1.0)))


func _label() -> String:
	var w: Variant = data.get("window", null)
	var span := (" (%s to %s)" % [_clock(float(w[0])), _clock(float(w[1]))]) if w is Array and (w as Array).size() >= 2 else ""
	return "Wait %d hour%s%s" % [int(need()), "" if int(need()) == 1 else "s", span]


static func _clock(h: float) -> String:
	return "%02d:00" % (int(h) % 24)


func _counter() -> String:
	return "%d/%d hours" % [int(have), int(need())]


func _handle(t: String, ev: Dictionary) -> void:
	if t == "hours" and in_window(data.get("window", null), float(ev.get("hour", 12.0))):
		have += float(ev.get("amount", 0.0))
