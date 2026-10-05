extends RefCounted
## Talk-menu side of the Thornfield quests (called from VillageServices, which stays small):
##   ctx_extra(info)      dialogue keys the generated resident files use (Wilm's confession / bribe nodes)
##   on_node(info, node)  fires `talk {npc, node}` on the quest bus when a conversation enters a node
##   add_options(opts, info)   "Hand over ..." for open Deliver objectives aimed at this person
## `info` is VillageServices._npc_info(): {id, name, ...}; roster residents carry their roster id, so the quest
## data's npc ids (hesta_thorne, wilm_garrow, thornfield_miller) match directly (QuestTalk also tries the
## lower-cased, underscored name).

const CULPRIT := "thornfield_the_culprit"


static func keys_of(info: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := String(info.get("id", ""))
	if id != "":
		out.append(id)
	var slug := String(info.get("name", "")).to_lower().replace(" ", "_")
	if slug != "" and slug != id:
		out.append(slug)
	return out


static func ctx_extra(info: Dictionary) -> Dictionary:
	var r := QuestHub.peek()
	if r == null or String(info.get("id", "")) != "wilm_garrow":
		return {}
	return {"thornfield_confront": r.is_active(CULPRIT) and r.stage_of(CULPRIT) == "confront",
		"thornfield_bribe_paid": r.is_active(CULPRIT) and r.stage_of(CULPRIT) == "bribed"}


static func on_node(info: Dictionary, node: String) -> void:
	for k: String in keys_of(info):
		QuestBus.shared().emit_event(&"talk", {"npc": k, "node": node})


## Open Deliver objectives of active quests whose `to` is this person: [[quest id, objective, item, still needed]].
static func pending_deliveries(r: QuestRunner, info: Dictionary) -> Array:
	var out: Array = []
	var keys := keys_of(info)
	for qid: String in r.active_ids():
		for o: RefCounted in r.objectives_of(qid):
			if String(o.type) != "deliver" or o.is_done() or o.is_failed():
				continue
			if keys.has(String(o.data.get("to", "")).to_lower()):
				out.append([qid, o, String(o.data.get("item", "")), int(ceil(o.need() - o.have))])
	return out


static func add_options(opts: Array, info: Dictionary) -> void:
	var r := QuestHub.peek()
	if r == null:
		return
	for d: Array in pending_deliveries(r, info):
		var item := String(d[2])
		var left := int(d[3])
		var have: int = Life.count(item) if Engine.get_main_loop() != null and Life.get("inventory") != null else 0
		var n := mini(have, left)
		var label := "Hand over %d %s" % [maxi(n, left), item.replace("_", " ")]
		opts.append([label, func() -> String: return hand_over(info, item, n), n > 0])


## Gives `n` of `item` to this person for the quest bus. Returns what to show.
static func hand_over(info: Dictionary, item: String, n: int) -> String:
	if n <= 0 or not Life.take(item, n):
		return "You do not have enough."
	for k: String in keys_of(info):
		QuestBus.shared().emit_event(&"deliver", {"item": item, "to": k, "amount": n})
	return "You hand over %d %s." % [n, item.replace("_", " ")]
