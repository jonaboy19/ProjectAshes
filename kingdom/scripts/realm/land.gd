extends "res://scripts/realm/realm_module.gd"
## R§7 deeds (legal claim vs occupation), R§8 conquest is not ownership
## (per-region loyalty, unrest, rebellion with a leader NPC), R§34 territory
## memory (decaying events that bias loyalty), R§38 generational consequences
## (memory and claims pass to descendants at reduced weight).
## Regions are keyed by settlement id (int) or any custom string; all keys are
## stored as strings so saves survive JSON.

const DEED_KINDS := ["royal", "noble_estate", "church", "commons", "unclaimed", "tribal", "sect", "contested", "abandoned", "rift"]
const ACQUIRE := ["purchase", "grant", "inheritance", "seizure", "charter", "occupation", "conquest", "founding"]
const HOUSES := ["House Varrick", "House Aldane", "House Corvane", "House Thessaly", "House Morrow"]

## kind -> {sign, decay per day, loyalty scale, tag}. Positive weights push
## loyalty up (relief, fair rule), negative down (massacre).
const MEMORY := {
	"massacre": {"sign": -1.0, "decay": 0.9985, "scale": 55.0},
	"conquest": {"sign": -1.0, "decay": 0.985, "scale": 30.0},
	"desecration": {"sign": -1.0, "decay": 0.995, "scale": 35.0},
	"tax_burden": {"sign": -1.0, "decay": 0.97, "scale": 20.0},
	"neglect": {"sign": -1.0, "decay": 0.98, "scale": 25.0},
	"relief": {"sign": 1.0, "decay": 0.985, "scale": 30.0},
	"fair_rule": {"sign": 1.0, "decay": 0.992, "scale": 30.0},
	"liberation": {"sign": 1.0, "decay": 0.99, "scale": 35.0},
}
const MEMORY_MAX := 12
const GENERATION_DAYS := 360            # a "generation" in game days
const GEN_DECAY := 0.5                  # weight kept by descendants
const CLAIM_DECAY := 0.9996
const LOYALTY_DRIFT := 0.04
const REBEL_LOYALTY := 22.0
const REBEL_BREW_DAYS := 6
## Regions nobody is playing for: the holder's levies crush an open revolt (per day, base + per-unrest) and,
## once rebel rule has lasted REBEL_RULE_DAYS, the old holder retakes the region (per day). Without these
## every revolt ended in "succeeded" and rebel-held regions never came back (balance run: 9 of 20 regions
## lost after two years, none recovered). Player-held regions are never auto-resolved.
const AUTO_CRUSH_CHANCE := 0.05
const REBEL_RULE_DAYS := 60
const REBEL_RETAKE_CHANCE := 0.03
const REBELS_KEEP := 20
## After a revolt is put down (or rebel rule ends) the region stays quiet this long (deed["calm_until"]);
## otherwise chronically low-loyalty regions re-brewed a revolt straight away (50 in two years).
const REBEL_CALM_DAYS := 60
const FIRST := ["Bram", "Kerrin", "Orla", "Tavis", "Maren", "Edric", "Sela", "Rook", "Halla", "Joss"]
const EPITHET := ["the Red", "Longstride", "of the Hollow", "Ash-hand", "the Elder", "Oathkeeper", "Grey", "the Lame"]

## region -> {region, name, kind, holder, claimant, occupier, acquired_by, since_day, history:[..]}
var _deeds: Dictionary = {}
## region -> float 0..100 toward the region's current occupier.
var _loyalty: Dictionary = {}
## region -> [{kind, weight (>0), day, who, gen}]
var _memory: Dictionary = {}
## region -> [{who, weight, since, gen}] : old claims that outlive their holders.
var _claims: Dictionary = {}
var _rebels: Array = []
var _next_rebel := 1
var _day := 0
var _inited := false
var _conflicts_flag: Dictionary = {}


func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


static func _k(region: Variant) -> String:
	return str(region)


func _ensure() -> void:
	if _inited:
		return
	_inited = true
	for s in WorldGen.settlements:
		var sid: int = s["id"]
		var r := _rng("deed", 0, sid)
		var kind := "noble_estate"
		var holder: String = HOUSES[r.randi() % HOUSES.size()]
		match String(s["kind"]):
			"castle":
				kind = "royal"
				holder = "crown"
			"town":
				kind = "royal" if r.randf() < 0.5 else "church"
				holder = "crown" if kind == "royal" else "church"
			"frontier_town":
				kind = "royal"
				holder = "crown"
			_:
				if r.randf() < 0.25:
					kind = "commons"
					holder = "commons"
		_deeds[_k(sid)] = {"region": _k(sid), "name": String(s["name"]), "kind": kind, "holder": holder,
			"claimant": holder, "occupier": holder, "acquired_by": "charter", "since_day": 0, "history": []}
		_loyalty[_k(sid)] = 55.0 + 25.0 * r.randf()


func regions() -> Array:
	_ensure()
	var k := _deeds.keys()
	k.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b) if a.is_valid_int() and b.is_valid_int() else a < b)
	return k


# --------------------------------------------------------------- deeds R§7

func deed(region: Variant) -> Dictionary:
	_ensure()
	return _deeds.get(_k(region), {})


## True when the person holding the land differs from the person on it.
func in_conflict(region: Variant) -> bool:
	var d := deed(region)
	return not d.is_empty() and (d["holder"] != d["occupier"] or d["kind"] == "contested")


func conflicts() -> Array:
	_ensure()
	var out: Array = []
	for k in regions():
		if in_conflict(k):
			out.append(_deeds[k])
	return out


func _record(d: Dictionary, how: String, who: String, day: int) -> void:
	(d["history"] as Array).append({"holder": d["holder"], "how": how, "to": who, "day": day})
	if (d["history"] as Array).size() > 10:
		(d["history"] as Array).pop_front()


func _add_claim(region: String, who: String, weight: float, day: int) -> void:
	if who == "" or who == "unclaimed":
		return
	var arr: Array = _claims.get(region, [])
	for c in arr:
		if c["who"] == who:
			c["weight"] = minf(1.0, float(c["weight"]) + weight)
			return
	arr.append({"who": who, "weight": minf(1.0, weight), "since": day, "gen": 0})
	_claims[region] = arr


## Legal sale. The old holder keeps a faint claim (family memory).
func purchase(region: Variant, buyer: String, price := 0, day := -1) -> bool:
	return _transfer(region, buyer, "purchase", day, false)


func grant(region: Variant, to: String, by := "crown", day := -1) -> bool:
	var d := deed(region)
	if d.is_empty() or (d["holder"] != by and by != "*"):
		return false
	return _transfer(region, to, "grant", day, false)


func inherit(region: Variant, heir: String, day := -1) -> bool:
	return _transfer(region, heir, "inheritance", day, true)


## Seizure changes possession, not law: the legal claimant stays the same and
## the land is in conflict until a settlement charter or grant is recorded.
func seize(region: Variant, by: String, day := -1) -> bool:
	var d := deed(region)
	if d.is_empty():
		return false
	var dd := _day if day < 0 else day
	_record(d, "seizure", by, dd)
	_add_claim(_k(region), d["holder"], 0.8, dd)
	d["occupier"] = by
	d["acquired_by"] = "seizure"
	d["since_day"] = dd
	_conquest_effects(_k(region), by, dd)
	return true


## Move in without paying: occupation on unclaimed/abandoned land, or a squat.
func occupy(region: Variant, who: String, day := -1) -> bool:
	var d := deed(region)
	if d.is_empty():
		return false
	var dd := _day if day < 0 else day
	d["occupier"] = who
	d["since_day"] = dd
	if d["kind"] in ["unclaimed", "abandoned"] or d["holder"] in ["unclaimed", ""]:
		d["holder"] = who
		d["claimant"] = who
		d["kind"] = "noble_estate" if who != "player" else "unclaimed"
		d["acquired_by"] = "occupation"
	return true


## Conquest: you control it, they do not accept you (R§8).
func conquer(region: Variant, by: String, day := -1) -> void:
	if seize(region, by, day):
		_deeds[_k(region)]["acquired_by"] = "conquest"


## A charter/decree turns occupation into the legal holder.
func legitimise(region: Variant, day := -1) -> bool:
	var d := deed(region)
	if d.is_empty():
		return false
	return _transfer(region, d["occupier"], "charter", day, false)


func _transfer(region: Variant, to: String, how: String, day: int, keep_family: bool) -> bool:
	var d := deed(region)
	if d.is_empty() or to == "":
		return false
	var dd := _day if day < 0 else day
	var old: String = d["holder"]
	_record(d, how, to, dd)
	_add_claim(_k(region), old, 0.9 if how in ["grant", "purchase"] else (0.2 if keep_family else 0.6), dd)
	d["holder"] = to
	d["claimant"] = to
	d["occupier"] = to
	d["acquired_by"] = how
	d["since_day"] = dd
	if d["kind"] in ["contested", "unclaimed", "abandoned"]:
		d["kind"] = "noble_estate"
	# Peaceful transfers barely stir the people; the loyalty target moves anyway.
	if how in ["purchase", "grant", "inheritance", "charter"]:
		_loyalty[_k(region)] = float(_loyalty.get(_k(region), 50.0)) - 3.0
	return true


func claimants(region: Variant) -> Array:
	return _claims.get(_k(region), [])


## Someone with a claim heavy enough to challenge the current holder.
func strongest_claim(region: Variant) -> Dictionary:
	var best := {}
	var bw := 0.0
	var cur: String = deed(region).get("holder", "")
	for c in _claims.get(_k(region), []):
		if c["who"] != cur and float(c["weight"]) > bw:
			bw = c["weight"]
			best = c
	return best


# --------------------------------------------------------------- loyalty and memory R§8/R§34

func loyalty(region: Variant) -> float:
	_ensure()
	return float(_loyalty.get(_k(region), 50.0))


func adjust_loyalty(region: Variant, delta: float) -> void:
	_ensure()
	var k := _k(region)
	_loyalty[k] = clampf(float(_loyalty.get(k, 50.0)) + delta, 0.0, 100.0)


func unrest(region: Variant) -> float:
	return clampf((45.0 - loyalty(region)) / 45.0, 0.0, 1.0)


## Record something the region will not forget. `weight` is a magnitude >= 0.
func remember(region: Variant, kind: String, weight: float, day := -1) -> void:
	_ensure()
	if not MEMORY.has(kind) or weight <= 0.0:
		return
	var k := _k(region)
	var arr: Array = _memory.get(k, [])
	var who: String = deed(region).get("occupier", "")
	arr.append({"kind": kind, "weight": minf(weight, 2.0), "day": _day if day < 0 else day, "who": who, "gen": 0})
	if arr.size() > MEMORY_MAX:
		var wi := 0
		for i in arr.size():
			if float(arr[i]["weight"]) * (0.5 ** int(arr[i]["gen"])) < float(arr[wi]["weight"]) * (0.5 ** int(arr[wi]["gen"])):
				wi = i
		arr.remove_at(wi)
	_memory[k] = arr
	# The act hits loyalty immediately, then settles toward the memory target.
	adjust_loyalty(region, float(MEMORY[kind]["sign"]) * float(MEMORY[kind]["scale"]) * 0.25 * minf(weight, 1.5))


func memories(region: Variant) -> Array:
	return _memory.get(_k(region), [])


## Net memory pull on loyalty: -50..+40.
func memory_bias(region: Variant) -> float:
	var b := 0.0
	for m in _memory.get(_k(region), []):
		var def: Dictionary = MEMORY[m["kind"]]
		b += float(def["sign"]) * float(def["scale"]) * float(m["weight"]) * 0.5
	return clampf(b, -50.0, 40.0)


func _target(region: String) -> float:
	var d: Dictionary = _deeds.get(region, {})
	var t := 55.0 + memory_bias(region)
	if not d.is_empty():
		# Being ruled by someone other than the legal holder is resented.
		if d["holder"] != d["occupier"]:
			t -= 10.0
		var age := _day - int(d["since_day"])
		if d["acquired_by"] in ["conquest", "seizure"] and age < 60:
			t -= 12.0 * (1.0 - age / 60.0)
		if d["occupier"] == "rebels":
			t = maxf(t, 60.0)
	return clampf(t, 2.0, 98.0)


func _conquest_effects(region: String, by: String, day: int) -> void:
	remember(region, "conquest", 0.8, day)
	_loyalty[region] = minf(float(_loyalty.get(region, 50.0)), 35.0)


# --------------------------------------------------------------- rebellion

func rebellions() -> Array:
	return _rebels


func rebellion_at(region: Variant) -> Dictionary:
	for r in _rebels:
		if r["region"] == _k(region) and r["status"] in ["brewing", "open"]:
			return r
	return {}


func _new_leader(region: String, day: int) -> Dictionary:
	var r := _rng("leader", day, region)
	return {"id": "rebel_%d" % _next_rebel, "name": "%s %s" % [FIRST[r.randi() % FIRST.size()], EPITHET[r.randi() % EPITHET.size()]],
		"charisma": snappedf(0.4 + 0.5 * r.randf(), 0.01), "grudge": memory_bias(region) < -10.0}


## Suppress a rebellion with force (0..1+). Returns a Game.say line.
func crush(region: Variant, force: float) -> String:
	var rb := rebellion_at(region)
	if rb.is_empty():
		return ""
	var name: String = deed(region).get("name", _k(region))
	if force >= float(rb["strength"]):
		rb["status"] = "crushed"
		if _deeds.has(_k(region)):
			_deeds[_k(region)]["calm_until"] = _day + REBEL_CALM_DAYS
		adjust_loyalty(region, -6.0)
		remember(region, "massacre" if force > 1.5 * float(rb["strength"]) else "conquest", 0.4)
		return "%s's rebellion under %s is crushed." % [name, rb["leader"]["name"]]
	rb["strength"] = float(rb["strength"]) * 0.7
	return "The rebels of %s hold out." % name


## Concede to the rebels: loyalty recovers, the rebellion ends without blood.
func appease(region: Variant) -> String:
	var rb := rebellion_at(region)
	if rb.is_empty():
		return ""
	rb["status"] = "resolved"
	if _deeds.has(_k(region)):
		_deeds[_k(region)]["calm_until"] = _day + REBEL_CALM_DAYS
	adjust_loyalty(region, 18.0)
	remember(region, "fair_rule", 0.5)
	return "You met the demands of %s; the region calms." % rb["leader"]["name"]


func _player_region(region: String) -> bool:
	var d: Dictionary = _deeds[region]
	return d["occupier"] == "player" or d["holder"] == "player"


## The old holder's retinue takes back a region the rebels have ruled for a while.
func _retake(region: String, day: int, out: Array, span := 1) -> void:
	var d: Dictionary = _deeds[region]
	if d["occupier"] != "rebels" or _player_region(region):
		return
	var ruled := clampi(day - int(d["since_day"]) - REBEL_RULE_DAYS, 0, span)   # days of eligibility in this window
	if ruled <= 0:
		return
	if _rng("retake", day, region).randf() >= 1.0 - pow(1.0 - REBEL_RETAKE_CHANCE, float(ruled)):
		return
	var holder := String(d["holder"])
	if holder == "rebels" or holder == "player":
		return
	_record(d, "reconquest", holder, day)
	d["occupier"] = holder
	d["acquired_by"] = "conquest"
	d["since_day"] = day
	remember(region, "conquest", 0.5, day)
	_loyalty[region] = minf(float(_loyalty.get(region, 50.0)), 35.0)
	d["calm_until"] = day + REBEL_CALM_DAYS
	out.append("%s has retaken %s from the rebels." % [holder.capitalize(), d["name"]])


func _rebel_day(region: String, day: int, out: Array) -> void:
	var lo := float(_loyalty.get(region, 50.0))
	var name: String = _deeds[region]["name"]
	_retake(region, day, out)
	var rb := rebellion_at(region)
	if rb.is_empty():
		if lo < REBEL_LOYALTY and _deeds[region]["occupier"] != "rebels" and day >= int(_deeds[region].get("calm_until", -1)):
			var r := _rng("rebel", day, region)
			if r.randf() < 0.25 + 0.5 * unrest(region):
				var ldr := _new_leader(region, day)
				_rebels.append({"id": _next_rebel, "region": region, "leader": ldr, "strength": 0.15,
					"start_day": day, "status": "brewing", "against": _deeds[region]["occupier"]})
				_next_rebel += 1
				out.append("Whispers of revolt in %s; a leader, %s, is rallying followers." % [name, ldr["name"]])
		return
	if lo >= REBEL_LOYALTY + 15.0:
		rb["status"] = "faded"
		return
	if rb["status"] == "open" and not _player_region(region) and _rng("crush", day, region).randf() < AUTO_CRUSH_CHANCE:
		rb["status"] = "crushed"
		_deeds[region]["calm_until"] = day + REBEL_CALM_DAYS
		adjust_loyalty(region, 6.0)
		remember(region, "conquest", 0.3, day)
		out.append("The levies of %s have crushed the revolt under %s." % [name, rb["leader"]["name"]])
		return
	rb["strength"] = float(rb["strength"]) + 0.04 + 0.05 * unrest(region) * float(rb["leader"]["charisma"])
	if rb["status"] == "brewing" and day - int(rb["start_day"]) >= REBEL_BREW_DAYS:
		rb["status"] = "open"
		out.append("%s has risen in open rebellion under %s!" % [name, rb["leader"]["name"]])
	if rb["status"] == "open" and float(rb["strength"]) >= 1.0:
		rb["status"] = "succeeded"
		var d: Dictionary = _deeds[region]
		_record(d, "rebellion", "rebels", day)
		d["occupier"] = "rebels"
		d["acquired_by"] = "seizure"
		d["since_day"] = day
		out.append("The rebels have taken %s. %s holds it now." % [name, rb["leader"]["name"]])
		remember(region, "liberation", 0.6, day)


# --------------------------------------------------------------- generations R§38

func _generation_pass(region: String, day: int) -> void:
	var arr: Array = _memory.get(region, [])
	for m in arr:
		var gens := int((day - int(m["day"])) / GENERATION_DAYS)
		while int(m["gen"]) < gens:
			m["gen"] = int(m["gen"]) + 1
			m["weight"] = float(m["weight"]) * GEN_DECAY
			if not String(m["who"]).begins_with("descendants of "):
				m["who"] = "descendants of " + String(m["who"])
	for c in _claims.get(region, []):
		var g := int((day - int(c["since"])) / GENERATION_DAYS)
		if g > int(c["gen"]):
			c["weight"] = float(c["weight"]) * pow(GEN_DECAY, g - int(c["gen"]))
			c["gen"] = g


func _decay_memory(region: String, days: float) -> void:
	var arr: Array = _memory.get(region, [])
	var i := arr.size() - 1
	while i >= 0:
		var m: Dictionary = arr[i]
		m["weight"] = float(m["weight"]) * pow(float(MEMORY[m["kind"]]["decay"]), days)
		if float(m["weight"]) < 0.02:
			arr.remove_at(i)
		i -= 1
	var cl: Array = _claims.get(region, [])
	var j := cl.size() - 1
	while j >= 0:
		cl[j]["weight"] = float(cl[j]["weight"]) * pow(CLAIM_DECAY, days)
		if float(cl[j]["weight"]) < 0.03:
			cl.remove_at(j)
		j -= 1


# --------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	var out: Array = []
	var sm: RefCounted = hub.mod("settlements") if hub != null else null
	_trim_rebels()
	for region in _deeds:
		_decay_memory(region, 1.0)
		if day % 30 == 0:
			_generation_pass(region, day)
		var lo: float = _loyalty.get(region, 50.0)
		lo += (_target(region) - lo) * LOYALTY_DRIFT
		_loyalty[region] = clampf(lo, 0.0, 100.0)
		if sm != null and region.is_valid_int():
			for e in sm.emergencies(int(region)):
				if e["kind"] in ["famine", "plague"]:
					_loyalty[region] = maxf(0.0, _loyalty[region] - 0.3)
		_rebel_day(region, day, out)
		# A family with a claim presses it.
		var cl := strongest_claim(region)
		var mine: bool = _deeds[region]["occupier"] == "player" or _deeds[region]["holder"] == "player"
		if not cl.is_empty() and mine and float(cl["weight"]) > 0.35:
			var r := _rng("claim", day, region)
			if r.randf() < 0.01 * float(cl["weight"]) and not _conflicts_flag.get(region, false):
				_conflicts_flag[region] = true
				out.append("%s claims %s is theirs by right of old ownership." % [str(cl["who"]).capitalize(), _deeds[region]["name"]])
				_deeds[region]["kind"] = "contested"
	return out


## Keeps the rebellion ledger bounded: every live one, then the newest finished ones, REBELS_KEEP in all.
func _trim_rebels() -> void:
	if _rebels.size() <= REBELS_KEEP:
		return
	var live: Array = []
	var done: Array = []
	for x: Dictionary in _rebels:
		(live if x["status"] in ["brewing", "open"] else done).append(x)
	var room := maxi(0, REBELS_KEEP - live.size())
	_rebels = live + done.slice(maxi(0, done.size() - room))


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	if days < 1:
		return out
	var day := _day + days
	for region in _deeds:
		_decay_memory(region, float(days))
		_generation_pass(region, day)
		var lo: float = _loyalty.get(region, 50.0)
		var f := 1.0 - pow(1.0 - LOYALTY_DRIFT, float(days))
		_day = day
		_loyalty[region] = clampf(lo + (_target(region) - lo) * f, 0.0, 100.0)
		_retake(region, day, out, days)
		var rb := rebellion_at(region)
		var name: String = _deeds[region]["name"]
		if not rb.is_empty() and not _player_region(region) and _rng("crush_away", day, region).randf() < 1.0 - pow(1.0 - AUTO_CRUSH_CHANCE, float(mini(days, 60))):
			rb["status"] = "crushed"
			_deeds[region]["calm_until"] = day + REBEL_CALM_DAYS
			_loyalty[region] = minf(100.0, float(_loyalty[region]) + 6.0)
		elif not rb.is_empty():
			rb["strength"] = float(rb["strength"]) + 0.05 * days
			if float(rb["strength"]) >= 1.0 and rb["status"] != "succeeded":
				rb["status"] = "succeeded"
				_record(_deeds[region], "rebellion", "rebels", day)
				_deeds[region]["occupier"] = "rebels"
				out.append("While you were away the rebels seized %s under %s." % [name, rb["leader"]["name"]])
			elif rb["status"] == "brewing":
				rb["status"] = "open"
				out.append("%s rose in revolt while you were away." % name)
		elif _loyalty[region] < REBEL_LOYALTY and _deeds[region]["occupier"] != "rebels" and day >= int(_deeds[region].get("calm_until", -1)):
			var r := _rng("rebel_away", day, region)
			if r.randf() < 1.0 - pow(0.9, minf(float(days), 20.0)):
				var ldr := _new_leader(region, day)
				_rebels.append({"id": _next_rebel, "region": region, "leader": ldr, "strength": 0.3,
					"start_day": day, "status": "open", "against": _deeds[region]["occupier"]})
				_next_rebel += 1
				out.append("%s stirred against you while you were away; %s leads them." % [name, ldr["name"]])
		# A noble presses an old claim.
		var cl := strongest_claim(region)
		if not cl.is_empty() and days >= 5 and _deeds[region]["holder"] == "player":
			var r2 := _rng("claim_away", day, region)
			if r2.randf() < minf(0.6, 0.02 * days * float(cl["weight"])) and not _conflicts_flag.get(region, false):
				_conflicts_flag[region] = true
				_deeds[region]["kind"] = "contested"
				out.append("%s has challenged your claim to %s." % [str(cl["who"]).capitalize(), name])
	if out.size() > 6:
		out.resize(6)
	return out


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"deeds": _deeds.duplicate(true), "loyalty": _loyalty.duplicate(), "memory": _memory.duplicate(true),
		"claims": _claims.duplicate(true), "rebels": _rebels.duplicate(true), "next_rebel": _next_rebel,
		"day": _day, "inited": _inited, "cflag": _conflicts_flag.duplicate()}


func deserialize(d: Dictionary) -> void:
	_deeds = (d.get("deeds", {}) as Dictionary).duplicate(true)
	_loyalty = (d.get("loyalty", {}) as Dictionary).duplicate()
	_memory = (d.get("memory", {}) as Dictionary).duplicate(true)
	_claims = (d.get("claims", {}) as Dictionary).duplicate(true)
	_rebels = (d.get("rebels", []) as Array).duplicate(true)
	_next_rebel = int(d.get("next_rebel", 1))
	_day = int(d.get("day", 0))
	_inited = bool(d.get("inited", false))
	_conflicts_flag = (d.get("cflag", {}) as Dictionary).duplicate()
