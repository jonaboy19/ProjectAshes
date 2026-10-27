extends RefCounted
## The section 0 chain, wired end to end: settlement grain stock -> caravan -> garrison food ->
## garrison morale -> a hostile neighbour's opportunity score in war_sim.gd.
##
## Owns no state of its own beyond which caravans it dispatched: stock lives in realm/settlements.gd,
## cargo in sim/caravans.gd, garrison food and hunger in realm/armies.gd, morale maths in army/morale.gd,
## the neighbour's reading in sim/war_sim.gd. Every step is published to systems/world_event_log.gd with
## the previous step as cause_id, so the journal reads as one causal chain.
##
## Events: grain_dispatched -> caravan_arrived / caravan_lost -> garrison_hungry -> war_opportunity.

const Morale := preload("res://scripts/army/morale.gd")

## Rations a garrison gets from one unit of grain.
const RATIONS_PER_GRAIN := 1.0

var settlements: Object      # realm/settlements.gd
var armies: Object           # realm/armies.gd
var caravans: Object         # sim/caravans.gd
var war: Object              # sim/war_sim.gd
var log: RefCounted          # systems/world_event_log.gd

## caravan id -> {event: id of grain_dispatched, grain: float}
var _ours: Dictionary = {}


func setup(p_settlements: Object, p_armies: Object, p_caravans: Object, p_war: Object, p_log: RefCounted) -> void:
	settlements = p_settlements
	armies = p_armies
	caravans = p_caravans
	war = p_war
	log = p_log


func _publish(kind: String, actor: String, target: String, hour: float, payload: Dictionary, cause: int = 0) -> int:
	return int(log.publish(kind, actor, target, hour, payload, cause).get("id", 0))


## Takes up to `qty` grain out of `from_sid`'s stock and puts it on the road to `to_sid`.
func dispatch(from_sid: int, to_sid: int, qty: float, now_h: float, seed_value: int, guards := 0,
		road_tier := "rural", stone_risk := 0.0) -> Dictionary:
	var have: float = settlements.supply_of(from_sid, "grain")
	var n := int(floor(minf(qty, have)))
	if n <= 0:
		return {"ok": false, "reason": "no_grain"}
	settlements.add_stock(from_sid, "grain", -float(n))
	var c: Dictionary = caravans.send(from_sid, to_sid, {"grain": n}, guards, road_tier, stone_risk, now_h, seed_value)
	var ev := _publish("grain_dispatched", "ss:%d" % from_sid, "ss:%d" % to_sid, now_h,
		{"caravan": int(c["id"]), "grain": n, "risk": float(c["risk"]), "stock_left": settlements.supply_of(from_sid, "grain")})
	_ours[int(c["id"])] = {"event": ev, "grain": n}
	return {"ok": true, "caravan": int(c["id"]), "grain": n, "arrive": float(c["arrive"]), "event": ev}


## Resolves arrivals due by `now_h`. Surviving grain feeds the destination garrison's store (or, with no
## garrison there, the settlement's own stock); an ambushed caravan delivers less and says so.
func tick(now_h: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rep: Dictionary in caravans.tick(now_h, null):
		var cid := int(rep["id"])
		if not _ours.has(cid):
			continue
		var mine: Dictionary = _ours[cid]
		_ours.erase(cid)
		var to_sid := int(rep["to"])
		var kept := float((rep["kept_cargo"] as Dictionary).get("grain", 0))
		var lost := float((rep["lost_cargo"] as Dictionary).get("grain", 0))
		var garrisoned: bool = not armies.defence(to_sid).is_empty()
		if kept > 0.0:
			if garrisoned:
				armies.stock_up(to_sid, "food", kept * RATIONS_PER_GRAIN)
			else:
				settlements.add_stock(to_sid, "grain", kept)
		var kind := "caravan_lost" if lost > 0.0 else "caravan_arrived"
		var ev := _publish(kind, "ss:%d" % int(rep["from"]), "ss:%d" % to_sid, now_h,
			{"caravan": cid, "kept": kept, "lost": lost, "to_garrison": garrisoned}, int(mine["event"]))
		out.append({"caravan": cid, "kept": kept, "lost": lost, "event": ev, "kind": kind})
	return out


## What the garrison at `sid` looks like to an outsider: food in days, hungry days, and its morale 0..100
## through army/morale.gd (steadiness of the troops, minus hunger).
func garrison_state(sid: int) -> Dictionary:
	var p: Dictionary = armies.defence(sid)
	if p.is_empty() or String(p["garrison"]) == "":
		return {}
	var aid := String(p["garrison"])
	var a: Dictionary = armies.army(aid)
	var hungry := int(a.get("hungry", 0))
	var base: float = armies.morale(aid) * 100.0
	return {"aid": aid, "food_days": armies.food_days(sid), "hungry_days": hungry,
		"morale": Morale.target({"base": base, "hungry_days": hungry}), "men": armies.men(aid)}


## Closes the chain: reads the garrison at `sid` and hands the hostile `nation` its opportunity score.
## `cause` is the last event of the chain (an arrival or a loss) so the journal links them.
func assess(sid: int, nation: String, now_h: float, cause := 0) -> Dictionary:
	var g := garrison_state(sid)
	if g.is_empty():
		return {}
	var cid := cause
	if int(g["hungry_days"]) > 0:
		cid = _publish("garrison_hungry", "ss:%d" % sid, String(g["aid"]), now_h,
			{"hungry_days": int(g["hungry_days"]), "food_days": float(g["food_days"]), "morale": float(g["morale"])}, cause)
	var score: float = war.note_opportunity(nation, float(g["morale"]), float(g["food_days"]))
	var ev := _publish("war_opportunity", nation, "ss:%d" % sid, now_h,
		{"score": score, "morale": float(g["morale"]), "food_days": float(g["food_days"])}, cid)
	g["score"] = score
	g["event"] = ev
	return g
