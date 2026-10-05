extends RefCounted
## Library quests in the shape the journal's Quests tab shows (gamemenu/menu_data.gd `quests()` merges these in).
## Objective text is each objective's describe(), plain words with counters. A quest only gets a `pos` while an open
## objective has one; the tab's "Pin to World" stays the one way a marker ever appears.


## {active: [], completed: [], failed: []}; empty lists when the game has no library runner yet.
static func entries(r: QuestRunner = null) -> Dictionary:
	var out := {"active": [], "completed": [], "failed": []}
	if r == null:
		r = QuestHub.peek()
	if r == null:
		return out
	for e: Dictionary in r.journal():
		var d := r.def(String(e["id"]))
		var state := String(e["state"])
		var objectives: Array[Dictionary] = []
		for l: Dictionary in e["lines"]:
			objectives.append({"text": String(l["text"]), "done": bool(l["done"])})
		var pos: Variant = null
		if state == "active":
			for o: RefCounted in r.objectives_of(String(e["id"])):
				var p: Variant = o.marker_pos()
				if p is Vector2 and not o.is_done():
					pos = p
					break
		var sub := "Side Quest"
		if String(e["giver"]) != "":
			sub += " · " + String(e["giver"])
		if String(e["stage"]) != "" and state == "active":
			sub += " · " + String(e["stage"])
		if state != "active":
			sub += " · " + ("Completed" if state == "done" else "Failed")
		var desc := String(e["summary"])
		if state == "done" and String(e["paid"]) != "":
			desc += "\n" + String(e["paid"])
		var entry := {"id": "lib_" + String(e["id"]), "title": String(e["title"]), "subtitle": sub, "desc": desc,
			"group": "side", "state": state, "objectives": objectives, "rewards": _rows(d.rewards() if d != null else {}),
			"pos": pos, "tracked": bool(e["pinned"]), "source": "quest_lib"}
		out["active" if state == "active" else ("completed" if state == "done" else "failed")].append(entry)
	return out


static func _rows(reward: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if int(reward.get("gold", 0)) > 0:
		rows.append({"icon": "rw_gold", "text": "%d" % int(reward["gold"]), "kind": "gold"})
	var rep: Dictionary = reward.get("rep", {})
	for f: String in rep:
		rows.append({"icon": "rw_rep", "text": "Reputation (%s) %+d" % [f.capitalize(), int(rep[f])], "kind": "rep"})
	return rows
