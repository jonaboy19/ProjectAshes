extends "res://scripts/quests/objective.gd"
## Collect: gather `count` of an item (item {item, amount} adds; inventory {counts} sets).
## Data: item, count (default 1).


func need() -> float:
	return float(maxi(1, int(data.get("count", 1))))


func _label() -> String:
	return "Gather %d %s" % [int(need()), _noun(String(data.get("item", "items")))]


func _counter() -> String:
	return "%d/%d" % [int(minf(have, need())), int(need())]


func _handle(t: String, ev: Dictionary) -> void:
	var item := String(data.get("item", ""))
	if t == "item" and String(ev.get("item", "")) == item:
		have = maxf(0.0, have + float(ev.get("amount", 1)))
	elif t == "inventory":
		have = float((ev.get("counts", {}) as Dictionary).get(item, have))
