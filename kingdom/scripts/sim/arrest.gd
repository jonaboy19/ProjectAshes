extends RefCounted
## The arrest, fine and jail flow (package F5). A guard who catches a player with a bounty in his town offers
## three choices:
##   pay    - pay the bounty (Society.pay_bounty); you walk away clean
##   jail   - serve the time: the clock skips `jail_hours` (WorldSim.advance_hours), every item flagged stolen is
##            confiscated, the bounty is wiped, you are let out at the plaza
##   resist - fight: the bounty rises (assault + resisting), the town's guard alert climbs two levels and the
##            watch hunts you (AlertNet / Search)
## Pure logic over Society (duck-typed), with the clock and the world's reaction passed in so tests need no scene.
## `menu` builds the hud.show_menu dictionary. Preload; no class_name.

const Theft := preload("res://scripts/sim/theft.gd")

## A guard this close (metres) with a clear look can make the arrest.
const CATCH_RADIUS := 3.2
## After a choice the same town's guards leave you alone this long (ms), except after resisting.
const COOLDOWN_MS := 60000
const RESIST_SURCHARGE := 40
const MIN_JAIL_HOURS := 6.0
const MAX_JAIL_HOURS := 72.0

static var _last_offer_ms := -1000000
static var last: Dictionary = {}


static func reset() -> void:
	_last_offer_ms = -1000000
	last = {}


## Can a guard arrest now: a bounty in this settlement and the offer is not on cooldown.
static func can_offer(bounty: int, now_ms: int) -> bool:
	return bounty > 0 and now_ms - _last_offer_ms >= COOLDOWN_MS


static func note_offer(now_ms: int) -> void:
	_last_offer_ms = now_ms


static func jail_hours(bounty: int) -> float:
	return clampf(MIN_JAIL_HOURS + float(bounty) / 10.0, MIN_JAIL_HOURS, MAX_JAIL_HOURS)


## The three choices: [{id, label, enabled, reason}].
static func choices(bounty: int, gold: int) -> Array:
	return [
		{"id": "pay", "label": "Pay the fine  -  %dg" % bounty, "enabled": gold >= bounty,
			"reason": "" if gold >= bounty else "You cannot cover %d gold." % bounty},
		{"id": "jail", "label": "Go to jail  -  about %d hours" % int(jail_hours(bounty)), "enabled": true, "reason": ""},
		{"id": "resist", "label": "Resist arrest", "enabled": true, "reason": ""},
	]


## Pays the bounty. {ok, cost, text}. The cost is spent through `take_gold` Callable(spent: int) (Game.add_gold(-n))
## so the caller owns the purse; pass an invalid Callable to leave it to Society's pending gold.
static func pay(soc: Object, sid: int, gold: int, take_gold := Callable()) -> Dictionary:
	if soc == null:
		return {"ok": false, "cost": 0, "text": "Nobody is there to take it."}
	var b := int(soc.call("bounty", sid))
	if gold < b:
		return {"ok": false, "cost": b, "text": "You cannot cover %d gold." % b}
	soc.call("set_player", {"gold": gold})
	var r: Dictionary = soc.call("pay_bounty", sid)
	if not bool(r.get("ok", false)):
		return {"ok": false, "cost": b, "text": String(r.get("reason", "The guard shakes his head."))}
	if take_gold.is_valid():
		soc.call("take_pending_gold")      # pay_bounty parked the cost there; the caller's purse settles it now
		take_gold.call(int(r.get("cost", b)))
	return {"ok": true, "cost": int(r.get("cost", b)), "text": "You pay %d gold. \"Keep your nose clean.\"" % int(r.get("cost", b))}


## Serves the sentence. `advance` Callable(hours: float) skips the clock (WorldSim.advance_hours). Confiscates stolen
## goods, wipes the bounty. {ok, hours, confiscated: [{item, qty}], text}.
static func jail(soc: Object, sid: int, advance: Callable) -> Dictionary:
	var b := int(soc.call("bounty", sid)) if soc != null else 0
	var hours := jail_hours(b)
	var taken := Theft.confiscate()
	if advance.is_valid():
		advance.call(hours)
	if soc != null:
		(soc.get("bounties") as Dictionary).erase(str(sid))
	var text := "You spend %d hours in a cold cell." % int(hours)
	if not taken.is_empty():
		var n := 0
		for t: Dictionary in taken:
			n += int(t["qty"])
		text += " The guards confiscate %d stolen item%s." % [n, "" if n == 1 else "s"]
	return {"ok": true, "hours": hours, "confiscated": taken, "text": text}


## Resists: the bounty climbs (an assault plus a surcharge), the guard alert goes up and the search starts.
## `alarm` Callable(levels: int) raises AlertNet and starts the Search (crime_watch.gd gives it). {ok, added, text}.
static func resist(soc: Object, sid: int, alarm := Callable()) -> Dictionary:
	var added := RESIST_SURCHARGE
	if soc != null:
		var defs: Dictionary = (load("res://scripts/realm/society.gd") as GDScript).get_script_constant_map().get("CRIMES", {})
		added += int((defs.get("assault", {}) as Dictionary).get("fine", 30))
		var bd: Dictionary = soc.get("bounties")
		bd[str(sid)] = int(bd.get(str(sid), 0)) + added
	if alarm.is_valid():
		alarm.call(2)
	return {"ok": true, "added": added, "text": "You shove the guard away. \"To arms! He's resisting!\""}


## The hud.show_menu dictionary. `ctx`: {soc, sid, gold, advance: Callable, take_gold: Callable, alarm: Callable,
## on_done: Callable(choice_id)}. Each option runs its choice and returns the message line.
static func menu(ctx: Dictionary) -> Dictionary:
	var soc: Object = ctx.get("soc")
	var sid := int(ctx.get("sid", -1))
	var b := int(soc.call("bounty", sid)) if soc != null else 0
	var gold := int(ctx.get("gold", 0))
	var opts: Array = []
	for c: Dictionary in choices(b, gold):
		var id := String(c["id"])
		opts.append([String(c["label"]), _run.bind(id, ctx), bool(c["enabled"])])
	return {"title": "Halt!",
		"body": "\"You are wanted in this town. There is a price of %d gold on your head.\"\nYou carry %d gold." % [b, gold],
		"options": opts}


static func _run(id: String, ctx: Dictionary) -> String:
	var soc: Object = ctx.get("soc")
	var sid := int(ctx.get("sid", -1))
	var res: Dictionary
	match id:
		"pay":
			res = pay(soc, sid, int(ctx.get("gold", 0)), ctx.get("take_gold", Callable()))
		"jail":
			res = jail(soc, sid, ctx.get("advance", Callable()))
		_:
			res = resist(soc, sid, ctx.get("alarm", Callable()))
	last = {"choice": id, "result": res}
	var done: Variant = ctx.get("on_done", Callable())
	if done is Callable and (done as Callable).is_valid():
		(done as Callable).call(id)
	return String(res.get("text", ""))
