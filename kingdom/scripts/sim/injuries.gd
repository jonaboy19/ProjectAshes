class_name RAInjuries
extends RefCounted
## Injuries on one body (the player, an NPC or a named subordinate). Each has a
## severity, an effects dict (multiplier offsets such as {"stamina": -0.2}) and
## either a natural recovery time in days or "healer_only": it stays until a
## healer who can handle its severity treats it (for gold and time).
##
## Healer services (HEALERS) are priced against the economy: wages 5..30 gold a
## day (Guard 9). A cut costs less than a day's wage; a broken arm about three
## days; a Fractured Core is a real setback (two to three weeks of guard pay)
## and only a temple or sect physician can mend it.
##
## INTEGRATION (for Life; not wired yet):
## - Life owns `var injuries := RAInjuries.new()`; at hour 5 call
##   `injuries.tick_day(WorldSim.day)` and show the recovered list.
## - After any change: `magicules.apply_effects(injuries.effects())`; apply
##   effects["stamina"] / ["max_health"] / ["attack"] to the player as multipliers
##   (1.0 + value).
## - Combat: a heavy wolf bite can `injuries.add("wolf_bite", WorldSim.day)`.
## - A healer station (village_services) lists `injuries.healer_menu("herbalist")`;
##   on choose: `var r := injuries.treat(uid, "herbalist", Game.gold, WorldSim.day)`;
##   if r.ok: Game.add_gold(-r.cost); WorldSim.advance_hours(r.hours).
## - Save: snapshot["injuries"] = injuries.serialize().

const HEALER_ONLY := -1

## type -> {name, severity 1..4, effects, recovery_days (HEALER_ONLY = never heals alone),
##          treat_cost (gold, base), treat_hours}
const TYPES := {
	"bruised_ribs": {"name": "Bruised Ribs", "severity": 1, "effects": {"stamina": -0.1},
		"recovery_days": 3, "treat_cost": 3, "treat_hours": 1},
	"deep_cut": {"name": "Deep Cut", "severity": 1, "effects": {"max_health": -0.1},
		"recovery_days": 4, "treat_cost": 5, "treat_hours": 2},
	"magicule_burn": {"name": "Magicule Burn", "severity": 1, "effects": {"magicule_regen": -0.3},
		"recovery_days": 2, "treat_cost": 6, "treat_hours": 2},
	"wolf_bite": {"name": "Festering Wolf Bite", "severity": 2, "effects": {"stamina": -0.2, "max_health": -0.1},
		"recovery_days": 6, "treat_cost": 12, "treat_hours": 4},
	"soul_fatigue": {"name": "Soul Fatigue", "severity": 2,
		"effects": {"magicule_regen": -0.5, "stamina": -0.15, "xp_gain": -0.25},
		"recovery_days": 3, "treat_cost": 18, "treat_hours": 8},
	"broken_arm": {"name": "Broken Arm", "severity": 2, "effects": {"attack": -0.35},
		"recovery_days": 24, "treat_cost": 28, "treat_hours": 12},
	"torn_meridian": {"name": "Torn Meridian", "severity": 3, "effects": {"magicule_max": -0.2, "stamina": -0.1},
		"recovery_days": HEALER_ONLY, "treat_cost": 60, "treat_hours": 24},
	"fractured_core": {"name": "Fractured Core", "severity": 4,
		"effects": {"magicule_max": -0.35, "magicule_regen": -0.5, "max_health": -0.1},
		"recovery_days": HEALER_ONLY, "treat_cost": 140, "treat_hours": 48},
}

## Healer services. cost = ceil(treat_cost * fee_mult) + visit_fee; hours = treat_hours * hours_mult.
const HEALERS := {
	"herbalist": {"name": "Village Herbalist", "max_severity": 2, "fee_mult": 1.0, "visit_fee": 1, "hours_mult": 1.0},
	"temple": {"name": "Temple Healer", "max_severity": 4, "fee_mult": 1.2, "visit_fee": 3, "hours_mult": 1.0},
	"sect_physician": {"name": "Sect Physician", "max_severity": 4, "fee_mult": 2.0, "visit_fee": 10, "hours_mult": 0.5},
}

## Active: [{uid, type, since, heals_on (day, or HEALER_ONLY)}]
var active: Array[Dictionary] = []
var _next_uid := 1


static func info(type: String) -> Dictionary:
	return TYPES.get(type, {})


static func is_healer_only(type: String) -> bool:
	return int(info(type).get("recovery_days", 0)) == HEALER_ONLY


## Add an injury. `days` overrides the natural recovery time (ignored for
## healer-only injuries). Returns the instance.
func add(type: String, day: int, days := -1) -> Dictionary:
	var t := info(type)
	if t.is_empty():
		push_warning("Unknown injury type %s" % type)
		return {}
	var rec := int(t["recovery_days"])
	var heals_on := HEALER_ONLY
	if rec != HEALER_ONLY:
		heals_on = day + (days if days > 0 else rec)
	var inj := {"uid": _next_uid, "type": type, "since": day, "heals_on": heals_on}
	_next_uid += 1
	active.append(inj)
	return inj


func has(type: String) -> bool:
	return not find(type).is_empty()


func find(type: String) -> Dictionary:
	for inj in active:
		if inj["type"] == type:
			return inj
	return {}


func get_uid(uid: int) -> Dictionary:
	for inj in active:
		if int(inj["uid"]) == uid:
			return inj
	return {}


func label(inj: Dictionary) -> String:
	var t := info(String(inj["type"]))
	if int(inj["heals_on"]) == HEALER_ONLY:
		return "%s (needs a healer)" % t["name"]
	return "%s (heals on day %d)" % [t["name"], int(inj["heals_on"])]


## Sum of effect offsets of all active injuries, e.g. {"stamina": -0.3}.
func effects() -> Dictionary:
	var out := {}
	for inj in active:
		var eff: Dictionary = info(String(inj["type"]))["effects"]
		for k: String in eff:
			out[k] = float(out.get(k, 0.0)) + float(eff[k])
	return out


## Natural recovery. Returns the injuries that healed today.
func tick_day(day: int) -> Array:
	var healed := []
	var keep: Array[Dictionary] = []
	for inj in active:
		var h := int(inj["heals_on"])
		if h != HEALER_ONLY and day >= h:
			healed.append(inj)
		else:
			keep.append(inj)
	active = keep
	return healed


## Price and time for a healer to treat one injury: {ok, cost, hours, text}.
func quote(uid: int, healer_id: String) -> Dictionary:
	var inj := get_uid(uid)
	var h: Dictionary = HEALERS.get(healer_id, {})
	if inj.is_empty() or h.is_empty():
		return {"ok": false, "cost": 0, "hours": 0.0, "text": "Nothing to treat."}
	var t := info(String(inj["type"]))
	if int(t["severity"]) > int(h["max_severity"]):
		return {"ok": false, "cost": 0, "hours": 0.0,
			"text": "The %s cannot mend a %s. Seek a temple or sect." % [h["name"], t["name"]]}
	var cost := int(ceil(float(t["treat_cost"]) * float(h["fee_mult"]))) + int(h["visit_fee"])
	var hours := float(t["treat_hours"]) * float(h["hours_mult"])
	return {"ok": true, "cost": cost, "hours": hours,
		"text": "%s: %d gold, %d hours." % [t["name"], cost, int(ceil(hours))]}


## Treat one injury if `gold` covers it. Removes it. Returns {ok, cost, hours, text};
## the caller deducts the gold and advances time.
func treat(uid: int, healer_id: String, gold: int, _day := 0) -> Dictionary:
	var q := quote(uid, healer_id)
	if not q["ok"]:
		return q
	if gold < int(q["cost"]):
		return {"ok": false, "cost": q["cost"], "hours": q["hours"], "text": "Treatment costs %d gold." % q["cost"]}
	var inj := get_uid(uid)
	active.erase(inj)
	q["text"] = "The %s treats your %s." % [HEALERS[healer_id]["name"], info(String(inj["type"]))["name"]]
	return q


## A healer's menu for this body's current injuries: [{uid, name, ok, cost, hours, text}].
func healer_menu(healer_id: String) -> Array:
	var out := []
	for inj in active:
		var q := quote(int(inj["uid"]), healer_id)
		q["uid"] = int(inj["uid"])
		q["name"] = info(String(inj["type"]))["name"]
		out.append(q)
	return out


## The full service definition of a healer: {name, max_severity, services: [{type, name, cost, hours}]}.
static func healer_service(healer_id: String) -> Dictionary:
	var h: Dictionary = HEALERS.get(healer_id, {})
	if h.is_empty():
		return {}
	var services := []
	for type: String in TYPES:
		var t: Dictionary = TYPES[type]
		if int(t["severity"]) <= int(h["max_severity"]):
			services.append({"type": type, "name": t["name"],
				"cost": int(ceil(float(t["treat_cost"]) * float(h["fee_mult"]))) + int(h["visit_fee"]),
				"hours": float(t["treat_hours"]) * float(h["hours_mult"])})
	return {"id": healer_id, "name": h["name"], "max_severity": h["max_severity"], "services": services}


func serialize() -> Dictionary:
	var arr := []
	for inj in active:
		arr.append(inj.duplicate())
	return {"active": arr, "next_uid": _next_uid}


func deserialize(d: Dictionary) -> void:
	active.clear()
	for inj: Dictionary in d.get("active", []):
		active.append({"uid": int(inj["uid"]), "type": String(inj["type"]), "since": int(inj["since"]),
			"heals_on": int(inj["heals_on"])})
	_next_uid = int(d.get("next_uid", _next_uid))
