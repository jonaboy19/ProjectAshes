extends RefCounted
## Theft (package F5): taking something owned by somebody else, what it costs, and what to do with the loot.
##
##  - `assess` / `steal`: taking an owned item or container stack is a theft check. The crime goes through the
##    existing witness path (NpcWorld.report_crime -> perception + witness.gd + evidence.gd): only a SEEN theft
##    becomes a Society crime ("pickpocket" for trifles, "robbery" for loose goods, "burglary" for a container),
##    an unseen one leaves evidence (a missing item) and nothing else.
##  - Stolen goods carry the inventory-item property `stolen` (= true) and `stolen_sid` (the victim's town). They
##    are never sold to an honest merchant of that town (`sale_gate`) but a fence (the black market) buys them
##    (`fence_sell`). Jail confiscates them (`confiscate`).
## Static, small, and the world call is behind `reporter` so tests can watch it. Preload; no class_name.

const Ownership := preload("res://scripts/sim/ownership.gd")

const PROP := "stolen"
const SID_PROP := "stolen_sid"
## Loot worth less than this is a pickpocket-sized offence, not a robbery.
const PETTY_VALUE := 5
## What a fence pays of an item's list price.
const FENCE_SHARE := 0.4
const NPC_WORLD := "res://scripts/population/npc_world.gd"

## Callable(tree, kind, pos: Vector2, sid) -> Dictionary. Defaults to NpcWorld.report_crime (witnesses, evidence).
static var reporter := Callable()
## Last theft result (QA / tests).
static var last: Dictionary = {}


## Settlement whose area holds world point `p` (x/z), -1 outside every town.
static func sid_at(p: Vector2) -> int:
	return int((load(NPC_WORLD) as GDScript).call("_sid_at", p))


static func _life() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null


# ---------------------------------------------------------------- the check
## {theft, owner, kind, value}: is taking `qty` of `item` from `owner` a theft and which crime would it be.
## `source` is "ground" (loose item) or "container" (breaking into someone's storage).
static func assess(owner: String, item: String, qty := 1, source := "ground", player: Variant = null) -> Dictionary:
	var value := Ownership.value_of(item, qty)
	if not Ownership.is_theft(owner, player):
		return {"theft": false, "owner": owner, "kind": "", "value": value}
	var kind := "burglary" if source == "container" else "robbery"
	if value < PETTY_VALUE:
		kind = "pickpocket"
	return {"theft": true, "owner": owner, "kind": kind, "value": value}


## The verb the interact label shows: a red "Steal" when taking it is theft, else `fallback`.
static func verb_for(owner: String, fallback := "Take", player: Variant = null) -> String:
	return "Steal" if Ownership.is_theft(owner, player) else fallback


## Reports a crime of `kind` at `pos` (x/z) in settlement `sid` through the witness path. Returns its result.
static func report(tree: SceneTree, kind: String, pos: Vector2, sid: int) -> Dictionary:
	if reporter.is_valid():
		return reporter.call(tree, kind, pos, sid)
	if tree == null:
		return {"ok": false, "seen_by": 0}
	return (load(NPC_WORLD) as GDScript).call("report_crime", tree, kind, pos, sid, true)


## Takes `qty` of `item` from `owner`'s stuff into the pack: gives the item (flagged stolen when it is theft) and
## runs the witness check. Returns {theft, kind, value, seen_by, stolen}. `at` is the world position (x/z); `sid` the
## settlement (-1 outside any town: nobody to report to, so the item is merely flagged).
static func steal(tree: SceneTree, owner: String, item: String, qty: int, source: String, at: Vector2, sid: int, player: Variant = null) -> Dictionary:
	var a := assess(owner, item, qty, source, player)
	var out := {"theft": bool(a["theft"]), "kind": String(a["kind"]), "value": int(a["value"]), "seen_by": 0, "stolen": false}
	if not bool(a["theft"]):
		_give(item, qty, false, -1)
		last = out
		return out
	var victim_sid := Ownership.sid_of(owner)
	if victim_sid < 0:
		victim_sid = sid
	_give(item, qty, true, victim_sid)
	out["stolen"] = true
	if sid >= 0 or tree != null:
		var res := report(tree, String(a["kind"]), at, sid)
		out["seen_by"] = int(res.get("seen_by", 0))
		out["report"] = res
	last = out
	return out


static func _give(item: String, qty: int, stolen: bool, victim_sid: int) -> void:
	if not stolen:
		var l := _life()
		if l != null:
			l.call("give", item, qty)
		return
	give_stolen(item, qty, victim_sid)


# ---------------------------------------------------------------- stolen flag
## Puts `qty` of `item` in the pack flagged stolen from town `victim_sid`. Stolen stacks never merge with clean ones.
static func give_stolen(item: String, qty: int, victim_sid: int) -> void:
	var l := _life()
	if l == null:
		return
	var inv: Inventory = l.get("inventory")
	for k in maxi(qty, 1):
		var it := inv.create_item(item)
		it.set_property(PROP, true)
		it.set_property(SID_PROP, victim_sid)
		inv.add_item_automerge(it)
	l.emit_signal("inventory_changed")


static func is_stolen(it: InventoryItem) -> bool:
	return it != null and bool(it.get_property(PROP, false))


## Units of `item` carried that are flagged stolen (any victim town, or only `sid` when >= 0).
static func stolen_count(item: String, sid := -1) -> int:
	var l := _life()
	if l == null:
		return 0
	var n := 0
	for it: InventoryItem in (l.get("inventory") as Inventory).get_items_with_prototype_id(item):
		if is_stolen(it) and (sid < 0 or int(it.get_property(SID_PROP, -1)) == sid):
			n += it.get_stack_size()
	return n


## Every stolen stack carried: [{item, qty, sid}].
static func stolen_stacks() -> Array:
	var out: Array = []
	var l := _life()
	if l == null:
		return out
	for it: InventoryItem in (l.get("inventory") as Inventory).get_items():
		if is_stolen(it):
			out.append({"item": it.get_prototype().get_prototype_id(), "qty": it.get_stack_size(), "sid": int(it.get_property(SID_PROP, -1))})
	return out


static func carries_stolen() -> bool:
	return not stolen_stacks().is_empty()


## Takes every stolen stack out of the pack (jail). `sid` >= 0 only those stolen from that town. Returns [{item, qty}].
static func confiscate(sid := -1) -> Array:
	var out: Array = []
	var l := _life()
	if l == null:
		return out
	var inv: Inventory = l.get("inventory")
	for it: InventoryItem in inv.get_items().duplicate():
		if is_stolen(it) and (sid < 0 or int(it.get_property(SID_PROP, -1)) == sid):
			out.append({"item": it.get_prototype().get_prototype_id(), "qty": it.get_stack_size()})
			inv.remove_item(it)
	if not out.is_empty():
		l.emit_signal("inventory_changed")
	return out


# ---------------------------------------------------------------- selling
## "" when an honest merchant of town `sid` may buy a unit of `item`, else the refusal line. A merchant refuses when
## every carried unit is stolen from that town (`sid` -1 = unknown town: any stolen unit counts as hot).
static func sale_gate(item: String, sid: int) -> String:
	var l := _life()
	if l == null:
		return ""
	var sellable := 0
	var hot := 0
	for it: InventoryItem in (l.get("inventory") as Inventory).get_items_with_prototype_id(item):
		if _hot_here(it, sid):
			hot += it.get_stack_size()
		else:
			sellable += it.get_stack_size()
	if sellable == 0 and hot > 0:
		return "\"Where did you get this? That's from around here. I'll not touch it.\""
	return ""


static func _hot_here(it: InventoryItem, sid: int) -> bool:
	if not is_stolen(it):
		return false
	var v := int(it.get_property(SID_PROP, -1))
	return sid < 0 or v < 0 or v == sid


## Removes one unit of `item` for a sale: an honest merchant takes a clean (or other-town) unit, a fence
## (`fence` true) takes stolen units first. False when there is nothing it may take.
static func take_one_for_sale(item: String, sid: int, fence := false) -> bool:
	var l := _life()
	if l == null:
		return false
	var inv: Inventory = l.get("inventory")
	var pick: InventoryItem = null
	for it: InventoryItem in inv.get_items_with_prototype_id(item):
		var hot := _hot_here(it, sid)
		if fence:
			if is_stolen(it):
				pick = it
				break
			if pick == null:
				pick = it
		elif not hot:
			pick = it
			break
	if pick == null:
		return false
	var n := pick.get_stack_size()
	if n > 1:
		pick.set_stack_size(n - 1)
	else:
		inv.remove_item(pick)
	l.emit_signal("inventory_changed")
	return true


## What a fence pays for one unit.
static func fence_price(item: String) -> int:
	return maxi(1, int(floor(float(Ownership.value_of(item)) * FENCE_SHARE)))


## True when the player has the standing to find a fence: a criminal reputation, a stolen pack, or a black-market hand.
static func fence_available() -> bool:
	if carries_stolen():
		return true
	var l := _life()
	if l == null or l.get("realm") == null:
		return false
	var soc: Object = (l.get("realm") as Object).call("mod", "society")
	return soc != null and float(soc.call("crim_rep", "underworld")) >= 3.0


## Sells one unit to the fence (stolen units first). {ok, gold, text}. Gold goes to Game; the underworld notices.
static func fence_sell(item: String, sid := -1) -> Dictionary:
	if not take_one_for_sale(item, sid, true):
		return {"ok": false, "gold": 0, "text": "You have no %s." % item}
	var price := fence_price(item)
	var g := _game()
	if g != null:
		g.call("add_gold", price)
	var l := _life()
	if l != null and l.get("realm") != null:
		var soc: Object = (l.get("realm") as Object).call("mod", "society")
		if soc != null:
			soc.call("add_crim_rep", "underworld", 0.5)
	return {"ok": true, "gold": price, "text": "The fence slides %d gold across, no questions asked." % price}


static func _game() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("Game") if loop is SceneTree else null
