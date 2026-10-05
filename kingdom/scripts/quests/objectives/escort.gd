extends "res://scripts/quests/objective.gd"
## Escort: bring `actor` to a place (arrive {actor, place}) or within `radius` of `pos` (actor_pos {actor, x, y}).
## Fails when the actor dies (died {actor}). Data: actor, name, place, pos, radius (default 12).


func _who() -> String:
	return String(data.get("name", _noun(String(data.get("actor", "them")))))


func _label() -> String:
	var dest := _noun(String(data["place"])) if data.has("place") else "the marked spot"
	return "Escort %s to %s" % [_who(), dest]


func _handle(t: String, ev: Dictionary) -> void:
	if not _matches(ev, ["actor"]):
		return
	match t:
		"died":
			failed = true
		"arrive":
			if not data.has("place") or String(ev.get("place", "")).to_lower() == String(data["place"]).to_lower():
				have = 1.0
		"actor_pos":
			var p := event_pos(ev)
			var target: Variant = marker_pos()
			if p != Vector2.INF and target is Vector2 and p.distance_to(target) <= float(data.get("radius", 12.0)):
				have = 1.0
