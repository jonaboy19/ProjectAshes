extends RefCounted
## Quest entries for the talk menu. VillageServices._talk_page adds these options after the conversation's own
## choices, so quests are offered by people in the world (never by a marker): "Ask about work", reporting back,
## and the Choose options a quest is waiting on. Everything is optional; the player can ignore all of it.
##
##   QuestTalk.add_options(opts, info, hud)   # info = {id, name}


static func add_options(opts: Array, info: Dictionary, hud: Node = null) -> void:
	var npc := String(info.get("id", ""))
	var nm := String(info.get("name", ""))
	var r := QuestHub.runner()
	for key: String in [npc, _slug(nm)]:
		if key == "":
			continue
		for o: Array in options_for(r, key):
			if not _has(opts, String(o[0])):
				opts.append(o)


## [[label, Callable() -> String], ...] for this person against a runner.
static func options_for(r: QuestRunner, npc: String) -> Array:
	var out: Array = []
	for d: QuestDef in r.offers_for(npc):
		out.append(["Ask about work: %s" % d.title, func() -> String:
			var why := r.start(d.id)
			return String(d.data.get("offer_text", "Quest started: %s" % d.title)) if why == "" else why])
	for qid: String in r.quests_awaiting_talk(npc):
		var ev := {"npc": npc}
		var d2 := r.def(qid)
		out.append(["Report: %s" % d2.title if d2 != null else "Report", func() -> String:
			r.notify(&"talk", ev)
			return "" if r.run(qid) == null else _after_talk(r, qid)])
	for qid2: String in r.active_ids():
		for c: Dictionary in r.pending_choices(qid2):
			if String(c["npc"]).to_lower() != npc.to_lower() and String(c["npc"]) != "":
				continue
			for opt: Dictionary in c["options"]:
				var oid := String(opt.get("id", ""))
				var cid := String(c["objective"])
				out.append([String(opt.get("text", oid)), func() -> String:
					r.notify(&"choose", {"choice": cid, "option": oid})
					return String(opt.get("say", ""))])
	return out


static func _after_talk(r: QuestRunner, qid: String) -> String:
	var run := r.run(qid)
	var d := r.def(qid)
	if run != null and run.state == "done" and d != null:
		return String(d.data.get("turn_in_text", "")) if d.data.has("turn_in_text") else ""
	return ""


static func _slug(nm: String) -> String:
	return nm.to_lower().replace(" ", "_")


static func _has(opts: Array, label: String) -> bool:
	for o: Variant in opts:
		if o is Array and String((o as Array)[0]) == label:
			return true
	return false
