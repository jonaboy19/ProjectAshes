extends RefCounted
## Radiant quests expressed with the objective library. radiant_quests.gd keeps its public API (generate, accept,
## update, turn_in, journal_lines, save); this adapter turns a radiant quest's stages into library objectives and
## whole radiant quests into QuestDefs, so the same quest can run on the QuestRunner and the journal shows the
## library's describe() text. A radiant stage of type
##   reach    -> goto (position within radius)     gather -> collect (item count)
##   kill_den -> kill (count, near the den)        return -> talk_to (the giver; deliver when goods are carried)
## and an escort quest (two reach stages with a trader) becomes goto + escort.

const Objectives := preload("res://scripts/quests/quest_objectives.gd")
const Def := preload("res://scripts/quests/quest_def.gd")
const KIND_GIVER := {"fetch_herbs": "herbalist", "clear_wolves": "receptionist", "deliver": "", "escort": "receptionist",
	"lost_child": ""}


## One radiant stage -> library objective data.
static func objective_for_stage(stage: Dictionary, quest: Dictionary, index := 0) -> Dictionary:
	var id := "o%d" % (index + 1)
	var text := String(stage.get("text", ""))
	var pos: Variant = stage.get("pos", null)
	var p: Variant = [pos.x, pos.y] if pos is Vector2 else null
	var giver := String(quest.get("giver", KIND_GIVER.get(String(quest.get("kind", "")), "")))
	match String(stage.get("type", "reach")):
		"gather":
			return {"id": id, "type": "collect", "item": String(stage.get("item", "")), "count": int(stage.get("amount", 1)), "text": text}
		"kill_den":
			var o := {"id": id, "type": "kill", "target": String(quest.get("data", {}).get("species", "")), "count": int(stage.get("kills", 1)), "text": text}
			if p != null:
				o["pos"] = p
			return o
		"return":
			return {"id": id, "type": "talk_to", "npc": giver, "text": text}
		_:
			var o2 := {"id": id, "type": "goto", "radius": float(stage.get("radius", 10.0)), "text": text}
			if p != null:
				o2["pos"] = p
			return o2


## A radiant quest dictionary (RadiantQuests.generate output) -> a QuestDef: one sequence stage of library
## objectives with the quest's reward (gold, reputation, opinion with the giver).
static func to_def(q: Dictionary) -> QuestDef:
	var objs: Array = []
	var stages: Array = q.get("stages", [])
	for i in stages.size():
		var s: Dictionary = stages[i]
		if String(q.get("kind", "")) in ["escort", "soldier_escort_caravan"] and i == stages.size() - 1 and i > 0:
			var trader := String(q.get("data", {}).get("trader", "trader"))
			var o := objective_for_stage(s, q, i)
			o["type"] = "escort"
			o["actor"] = trader.to_lower().replace(" ", "_")
			o["name"] = trader
			objs.append(o)
		else:
			objs.append(objective_for_stage(s, q, i))
	var r: Dictionary = q.get("reward", {})
	var rewards := {"gold": int(r.get("gold", 0)), "rep": (r.get("rep", {}) as Dictionary).duplicate()}
	var giver := String(q.get("giver", ""))
	if giver != "" and int(r.get("opinion", 0)) != 0:
		rewards["relationship"] = [{"npc": giver, "label": "Did me a good turn", "value": float(r["opinion"]), "days": 60.0, "id": "quest"}]
	return Def.from_dict({"id": String(q.get("id", "")), "title": String(q.get("title", "")), "summary": String(q.get("desc", "")),
		"giver": {"npc": giver, "name": String(q.get("giver_name", ""))},
		"stages": [{"id": "main", "title": String(q.get("title", "")), "mode": "sequence", "objectives": objs}],
		"rewards": rewards})
