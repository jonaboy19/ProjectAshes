extends "res://scripts/quests/objective.gd"
## Kill: kill `count` of a target (kill {target, place, amount}). Data: target, place, count (default 1).


func need() -> float:
	return float(maxi(1, int(data.get("count", 1))))


func _label() -> String:
	var who := _noun(String(data.get("target", "enemies")))
	var where := (" near %s" % _noun(String(data["place"]))) if data.has("place") else ""
	return "Kill %d %s%s" % [int(need()), who, where]


func _counter() -> String:
	return "%d/%d" % [int(have), int(need())]


func _handle(t: String, ev: Dictionary) -> void:
	if t == "kill" and _matches(ev, ["target", "place"]):
		have += float(ev.get("amount", 1))
