extends "res://scripts/quests/objective.gd"
## Deliver: hand goods to someone or somewhere (deliver {item, to, amount}).
## Data: item, count (default 1), to (npc or place id), text.


func need() -> float:
	return float(maxi(1, int(data.get("count", 1))))


func _label() -> String:
	var what := _noun(String(data.get("item", "the goods")))
	var n := int(need())
	return "Deliver %s%s to %s" % [("%d " % n) if n > 1 else "", what, _noun(String(data.get("to", "its owner"))).capitalize()]


func _counter() -> String:
	return "%d/%d" % [int(have), int(need())] if int(need()) > 1 else ""


func _handle(t: String, ev: Dictionary) -> void:
	if t == "deliver" and _matches(ev, ["item", "to"]):
		have += float(ev.get("amount", 1))
