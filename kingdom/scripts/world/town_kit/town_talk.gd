extends RefCounted
## Talk-menu side of the town quests (called from VillageServices, which stays small):
##   ctx_extra(info)      dialogue keys a town's conversations use (the town's special script supplies them)
##   on_node(info, node)  fires `talk {npc, node}` on the quest bus when a conversation enters a node
##   add_options(opts, info)   "Hand over ..." for open Deliver objectives aimed at this person
## `info` is VillageServices._npc_info(): {id, name, ...}; roster residents carry their roster id, so the quest
## data's npc ids (hesta_thorne, wilm_garrow, thornfield_miller, the generated towns' ids) match directly (QuestTalk also
## tries the lower-cased, underscored name). Works for every kit town; nothing here names one.

const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const TownData := preload("res://scripts/world/town_kit/town_data.gd")

static var _specials: Dictionary = {}      # town id -> stateless special instance (only ctx_extra is called on it)


static func keys_of(info: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := String(info.get("id", ""))
	if id != "":
		out.append(id)
	var slug := String(info.get("name", "")).to_lower().replace(" ", "_")
	if slug != "" and slug != id:
		out.append(slug)
	return out


## Dialogue keys from the special script of the town the person lives in ({} for people of towns without one).
static func ctx_extra(info: Dictionary) -> Dictionary:
	var tid := TownRoster.town_of(String(info.get("id", "")))
	if tid == "":
		return {}
	if not _specials.has(tid):
		var path := String(TownData.town(tid).get("special", ""))
		_specials[tid] = (load(path) as GDScript).new() if path != "" and ResourceLoader.exists(path) else null
	var sp: Variant = _specials[tid]
	return sp.ctx_extra(info) if sp != null else {}


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
