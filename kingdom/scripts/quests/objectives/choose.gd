extends "res://scripts/quests/objective.gd"
## Choose: pick one of `options` [{id, text}] (choose {choice: <this objective's id>, option}). The chosen option
## id is kept in `chosen`; a stage's `branches` map it to the next stage. Data: options, npc (who asks), text.

var chosen := ""


func _label() -> String:
	var parts := PackedStringArray()
	for o: Variant in data.get("options", []):
		parts.append(String((o as Dictionary).get("text", (o as Dictionary).get("id", ""))))
	return String(data.get("text", "Decide: " + " or ".join(parts)))


func option_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for o: Variant in data.get("options", []):
		out.append(String((o as Dictionary).get("id", "")))
	return out


func _handle(t: String, ev: Dictionary) -> void:
	if t == "choose" and String(ev.get("choice", "")) == id and option_ids().has(String(ev.get("option", ""))):
		chosen = String(ev["option"])
		have = 1.0


func _save_extra() -> Dictionary:
	return {"chosen": chosen}


func _load_extra(d: Dictionary) -> void:
	chosen = String(d.get("chosen", ""))
