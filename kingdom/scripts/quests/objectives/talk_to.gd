extends "res://scripts/quests/objective.gd"
## TalkTo: talk to a person (talk {npc, node}). Data: npc, node (a dialogue node), text.


func _label() -> String:
	return "Talk to %s" % _noun(String(data.get("npc", data.get("node", "someone")))).capitalize()


func _handle(t: String, ev: Dictionary) -> void:
	if t == "talk" and _matches(ev, ["npc", "node"]):
		have = 1.0
