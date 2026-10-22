extends "res://scripts/quests/objective.gd"
## Investigate: interact with `count` different clues (interact {id}, fired by clue interactables of the F1
## interaction framework, scripts/interaction/kinds/clue.gd). Data: clues [ids] (an id ending in * is a prefix),
## count (default: all of them), text.

var found: Array = []


func need() -> float:
	var c: Array = data.get("clues", [])
	return float(clampi(int(data.get("count", c.size())), 1, maxi(1, c.size())))


func _label() -> String:
	return "Look for clues"


func _counter() -> String:
	return "%d/%d found" % [int(have), int(need())]


func _handle(t: String, ev: Dictionary) -> void:
	if t != "interact":
		return
	var cid := String(ev.get("id", ""))
	if cid == "" or found.has(cid):
		return
	for c: Variant in data.get("clues", []):
		var s := String(c)
		if s == cid or (s.ends_with("*") and cid.begins_with(s.trim_suffix("*"))):
			found.append(cid)
			have = float(found.size())
			return


func _save_extra() -> Dictionary:
	return {"found": found.duplicate()}


func _load_extra(d: Dictionary) -> void:
	found = (d.get("found", []) as Array).duplicate()
	while found.size() < int(have):      # restored from bare units (story saves): keep the count
		found.append("#%d" % found.size())
