extends "res://scripts/quests/objective.gd"
## GoTo: reach a named place (enter_area {place}) or a spot (position {x, y} within `radius` of `pos`).
## Data: place, pos [x, y], radius (default 10), text.


func _label() -> String:
	if data.has("place"):
		return "Go to %s" % _noun(String(data["place"]))
	return "Reach the marked spot"


func _handle(t: String, ev: Dictionary) -> void:
	if t == "enter_area" and data.has("place"):
		if String(ev.get("place", "")).to_lower() == String(data["place"]).to_lower():
			have = 1.0
		return
	if t == "enter_area" and not data.has("pos"):
		have = 1.0
		return
	if (t == "position" or t == "enter_area") and data.has("pos"):
		var p := event_pos(ev)
		var target: Variant = marker_pos()
		if p != Vector2.INF and target is Vector2 and p.distance_to(target) <= float(data.get("radius", 10.0)):
			have = 1.0
