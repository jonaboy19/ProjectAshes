extends "res://scripts/quests/objective.gd"
## Protect: keep `actor` alive for `hours` of game time (hours {amount}), or until an `until` event
## ({type, ...keys it must match}) arrives. Fails when the actor dies (died {actor}).
## Data: actor, name, hours (default 1, ignored when `until` is set), until.


func need() -> float:
	return 1.0 if data.has("until") else maxf(0.01, float(data.get("hours", 1.0)))


func _who() -> String:
	return String(data.get("name", _noun(String(data.get("actor", "them")))))


func _label() -> String:
	if data.has("until"):
		return "Keep %s safe until the danger passes" % _who()
	return "Keep %s alive for %s" % [_who(), _hours_text(need())]


func _counter() -> String:
	return "" if data.has("until") else "%s of %s" % [_hours_text(have), _hours_text(need())]


static func _hours_text(h: float) -> String:
	return "%d hour%s" % [int(ceil(h)), "" if int(ceil(h)) == 1 else "s"] if h >= 1.0 else "%d minutes" % int(h * 60.0)


func _handle(t: String, ev: Dictionary) -> void:
	if t == "died" and _matches(ev, ["actor"]):
		failed = true
		return
	var until: Dictionary = data.get("until", {})
	if not until.is_empty():
		if t == String(until.get("type", "")):
			var ok := true
			for k: String in until:
				if k != "type" and String(ev.get(k, "")) != String(until[k]):
					ok = false
			if ok:
				have = 1.0
	elif t == "hours":
		have += float(ev.get("amount", 0.0))
