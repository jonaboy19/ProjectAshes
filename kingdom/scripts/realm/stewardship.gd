extends "res://scripts/realm/realm_module.gd"
## Authority chain and running a territory (Living World section 7, LW-6.2).
##
## AUTHORITY CHAIN PER LOCATION. Every place answers to four offices, from the bottom: village headman, district magistrate,
## governor or noble, crown. Each office is one record "seat:level" with a real holder (a governance leader or a society NPC, the king
## from nations.json for the crown), a jurisdiction, permissions (the petition types it may grant) and limits (how much tax, levy,
## building and how long a term it may set). chain(sid) is the lookup every petition starts with.
##
## RUNNING A TERRITORY. A holder owes five duties: roads, taxes, levies, petitions heard, records kept. NPC holders do them by their
## competence; a player holder must call perform(). Each week an overdue duty adds neglect; done duties repay it. At NEGLECT_LIMIT the
## office is taken away, a successor is seated and every privilege the old holder granted goes into review (audiences.gd).

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const DUTIES := {"roads": 30, "taxes": 28, "levies": 90, "petitions": 14, "records": 30}
const NEGLECT_LIMIT := 12.0
const RANK_OF_LEVEL := {0: 1, 1: 2, 2: 3, 3: 5}
const BACKLOG_DAYS := 14

var _off: Dictionary = {}       # "seat:level" -> office record
var _relief: Dictionary = {}    # str(sid) -> [fraction, until_day]
var _log: Array = []
var _day := 0
var stats := {"dismissed": 0, "performed": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ the chain

func seat_of(sid: int, level: int) -> int:
	var kind := PD.kind_of(sid)
	match level:
		0:
			return sid
		1:
			if kind in ["town", "frontier_town", "castle", "capital"]:
				return sid
			var d := PD.nearest_of(sid, ["town", "frontier_town", "castle", "capital"])
			return d if d >= 0 else sid
		2:
			if PD.is_seat(kind):
				var other := PD.nearest_of(sid, ["castle", "capital"], sid)
				return other if other >= 0 else sid
			var g := PD.nearest_of(sid, ["castle", "capital"])
			return g if g >= 0 else sid
		_:
			var c := PD.capital_sid()
			return c if c >= 0 else sid


func office_key(sid: int, level: int) -> String:
	return "%d:%d" % [seat_of(sid, level), level]


func _holder_from_society(seat: int, level: int) -> Dictionary:
	var soc: Variant = _mod("society")
	if soc == null:
		return {}
	var ids: Array = soc.npcs_in(seat)
	if ids.is_empty():
		var near := PD.nearest_of(seat, ["village", "town", "castle", "capital", "frontier_town"], seat)
		if near >= 0:
			ids = soc.npcs_in(near)
	var best := ""
	var bs := -1.0
	for id: String in ids:
		var n: Dictionary = soc.npcs[id]
		var s := float(int(n["class"])) * 10.0 + float(int(n["tier"])) + float((n["pers"] as Dictionary)["honor"]) * 2.0
		if String(n["job"]) in ["scribe", "guard"]:
			s += 6.0
		s += float(absi(hash([WorldSim.SEED, "hold", id, level])) % 100) / 100.0
		if s > bs:
			bs = s
			best = id
	if best == "":
		return {}
	var np: Dictionary = soc.npcs[best]
	return {"id": best, "name": String(np["name"]), "comp": 0.35 + float((np["pers"] as Dictionary)["ambition"]) * 0.4 + float(int(np["tier"])) * 0.02,
		"honest": float((np["pers"] as Dictionary)["honor"])}


func _holder_from_governance(seat: int) -> Dictionary:
	var gv: Variant = _mod("governance")
	if gv == null:
		return {}
	var p: Dictionary = gv.leader_of_settlement(seat)
	if p.is_empty():
		return {}
	var tr: Dictionary = p.get("tr", {})
	return {"id": String(p["id"]), "name": String(p["n"]), "comp": float(tr.get("competence", 0.5)), "honest": 1.0 - float(tr.get("greed", 0.5))}


func _crown_holder() -> Dictionary:
	for n: Dictionary in preload("res://scripts/realm/factions.gd").nations_data():
		if String(n["id"]) == PD.HOME:
			var r: Dictionary = n.get("ruler", {})
			return {"id": "ruler:" + PD.HOME, "name": "%s %s" % [String(r.get("title", "King")), String(r.get("name", "the king"))], "comp": 0.6, "honest": 0.6}
	return {"id": "ruler:" + PD.HOME, "name": "the King", "comp": 0.6, "honest": 0.6}


func _new_office(seat: int, level: int) -> Dictionary:
	var h: Dictionary = {}
	if level == 3:
		h = _crown_holder()
	elif level in [0, 2]:
		h = _holder_from_governance(seat)
	if h.is_empty():
		h = _holder_from_society(seat, level)
	if h.is_empty():
		h = {"id": "vacant", "name": "no one", "comp": 0.3, "honest": 0.5}
	var duties := {}
	for d: String in DUTIES:
		duties[d] = {"last": _now(), "missed": 0}
	return {"seat": seat, "level": level, "role": String((PD.OFFICES[level] as Dictionary)["role"]), "holder": String(h["id"]), "name": String(h["name"]),
		"comp": snappedf(float(h["comp"]), 0.01), "honest": snappedf(float(h["honest"]), 0.01), "since": _now(), "neglect": 0.0, "duties": duties,
		"player": false, "vacant": String(h["id"]) == "vacant", "prev": ""}


func office(key: String) -> Dictionary:
	if _off.has(key):
		return _off[key]
	var bits := key.split(":")
	if bits.size() != 2 or not bits[0].is_valid_int() or not bits[1].is_valid_int():
		return {}
	var lv := int(bits[1])
	if lv < 0 or lv > 3:
		return {}
	_off[key] = _new_office(int(bits[0]), lv)
	return _off[key]


## The four offices over a location, lowest first: {level, key, seat, seat_name, role, gatekeeper, holder, name, jurisdiction, limits, vacant}.
func chain(sid: int) -> Array:
	var out: Array = []
	for lv in 4:
		var k := office_key(sid, lv)
		var o := office(k)
		var spec: Dictionary = PD.OFFICES[lv]
		out.append({"level": lv, "key": k, "seat": int(o["seat"]), "seat_name": PD.sname(int(o["seat"])), "role": String(o["role"]),
			"gatekeeper": String(spec["gatekeeper"]), "holder": String(o["holder"]), "name": String(o["name"]), "jurisdiction": String(spec["jurisdiction"]),
			"limits": (spec["limits"] as Dictionary).duplicate(), "vacant": bool(o["vacant"]), "player": bool(o["player"])})
	return out


func permits(level: int, ptype: String) -> bool:
	return PD.PETITIONS.has(ptype) and level >= int((PD.PETITIONS[ptype] as Dictionary)["level"])


func limit(level: int, what: String) -> float:
	return float(((PD.OFFICES[clampi(level, 0, 3)] as Dictionary)["limits"] as Dictionary).get(what, 0.0))


## Settlements whose chain passes through this office.
func jurisdiction(key: String) -> Array:
	var o := office(key)
	var out: Array = []
	if o.is_empty():
		return out
	for s: Dictionary in WorldGen.settlements:
		if seat_of(int(s["id"]), int(o["level"])) == int(o["seat"]):
			out.append(int(s["id"]))
	return out


## Rank of a person: 0 commoner, 1 headman or burgher, 2 magistrate or knight, 3 lord, 4 count, 5 crown. Titles come from audiences.gd grants.
func rank_of(who: String) -> int:
	var best := 0
	var aud: Variant = _mod("audiences")
	if aud != null:
		best = int(aud.title_rank(who))
	for k: String in _off:
		var o: Dictionary = _off[k]
		if String(o["holder"]) == who and not bool(o["vacant"]):
			best = maxi(best, int(RANK_OF_LEVEL[int(o["level"])]))
	return best


# ------------------------------------------------------------------ seating

## Seats `who` (a person id and name) in an office, e.g. from a commission or a succession. Returns false for a bad office.
func assume(key: String, who: String, hname: String, is_player := false, comp := 0.5, honest := 0.6) -> bool:
	var o := office(key)
	if o.is_empty() or who == "":
		return false
	var old := String(o["holder"])
	o["prev"] = old
	o["holder"] = who
	o["name"] = hname
	o["comp"] = comp
	o["honest"] = honest
	o["since"] = _now()
	o["neglect"] = 0.0
	o["player"] = is_player
	o["vacant"] = false
	for d: String in DUTIES:
		o["duties"][d] = {"last": _now(), "missed": 0}
	_note("%s takes the office of %s at %s" % [hname, String(o["role"]), PD.sname(int(o["seat"]))])
	Events.log_to(hub, "succession", "ss:%d" % int(o["seat"]), [who, old], "office", "%s becomes %s" % [hname, String(o["role"])], 3)
	var aud: Variant = _mod("audiences")
	if aud != null and old != who:
		aud.on_ruler_change(key, old, who)
	return true


func dismiss(key: String, reason: String) -> bool:
	var o := office(key)
	if o.is_empty() or bool(o["vacant"]):
		return false
	var old := String(o["holder"])
	var oldn := String(o["name"])
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("i:" + old, "neglected_office", int(o["seat"]), 1.0)
	stats["dismissed"] = int(stats["dismissed"]) + 1
	var nh := _holder_from_society(int(o["seat"]), int(o["level"]) + 7)
	if nh.is_empty() or String(nh["id"]) == old:
		nh = {"id": "vacant", "name": "no one", "comp": 0.3, "honest": 0.5}
	_note("%s loses the office of %s (%s)" % [oldn, String(o["role"]), reason])
	if String(nh["id"]) == "vacant":
		o["holder"] = "vacant"
		o["name"] = "no one"
		o["vacant"] = true
		o["player"] = false
		o["prev"] = old
		Events.log_to(hub, "succession", "ss:%d" % int(o["seat"]), [old], "dismissed", "%s loses office: %s" % [oldn, reason], 4)
		var aud: Variant = _mod("audiences")
		if aud != null:
			aud.on_ruler_change(key, old, "vacant")
		return true
	return assume(key, String(nh["id"]), String(nh["name"]), false, float(nh["comp"]), float(nh["honest"]))


# ------------------------------------------------------------------ duties

func perform(key: String, duty: String, amount := 1.0) -> bool:
	var o := office(key)
	if o.is_empty() or not DUTIES.has(duty) or bool(o["vacant"]):
		return false
	var d: Dictionary = o["duties"][duty]
	d["last"] = _now()
	d["missed"] = 0
	o["neglect"] = maxf(0.0, float(o["neglect"]) - 1.0 * amount)
	stats["performed"] = int(stats["performed"]) + 1
	return true


## What the holder owes now: [{duty, every, due_in, overdue}].
func obligations(key: String) -> Array:
	var o := office(key)
	var out: Array = []
	if o.is_empty():
		return out
	for duty: String in DUTIES:
		var left := int((o["duties"][duty] as Dictionary)["last"]) + int(DUTIES[duty]) - _now()
		out.append({"duty": duty, "every": int(DUTIES[duty]), "due_in": left, "overdue": left < 0})
	return out


func neglect(key: String) -> float:
	return float(office(key).get("neglect", 0.0))


func _backlog(o: Dictionary, bmap: Dictionary) -> int:
	return int(bmap.get("%d:%d" % [int(o["seat"]), int(o["level"])], 0))


func _week_office(key: String, o: Dictionary, bmap: Dictionary) -> void:
	if bool(o["vacant"]):
		return
	var bad := 0
	for duty: String in DUTIES:
		var d: Dictionary = o["duties"][duty]
		var due := int(d["last"]) + int(DUTIES[duty])
		if not bool(o["player"]) and _now() >= due - 7:
			var p := 0.5 + 0.45 * float(o["comp"])
			if PD.rng("duty", _now(), [key, duty]).randf() < p:
				d["last"] = _now()
				d["missed"] = 0
				continue
		if _now() > due:
			d["missed"] = int(d["missed"]) + 1
			bad += 1
	if _backlog(o, bmap) > 0 and bool(o["player"]):
		bad += 1
	if bad > 0:
		o["neglect"] = float(o["neglect"]) + float(bad) * (1.0 + (1.0 - float(o["honest"])) * 0.3)
	else:
		o["neglect"] = maxf(0.0, float(o["neglect"]) - 0.75)
	if float(o["neglect"]) >= NEGLECT_LIMIT:
		dismiss(key, "neglect of duty")


func _note(line: String) -> void:
	_log.append("d%d: %s" % [_now(), line])
	if _log.size() > 30:
		_log.pop_front()


func log_lines(limit_n := 10) -> Array:
	return _log.slice(maxi(0, _log.size() - limit_n))


# ------------------------------------------------------------------ tax relief and rates

func set_relief(sid: int, fraction: float, until: int) -> void:
	_relief[str(sid)] = [clampf(fraction, 0.0, 1.0), until]


func relief(sid: int) -> float:
	var r: Array = _relief.get(str(sid), [])
	if r.is_empty() or _now() > int(r[1]):
		return 0.0
	return float(r[0])


func tax_rate(sid: int) -> float:
	var gv: Variant = _mod("governance")
	var base := float(gv.tax(sid)) if gv != null else 0.1
	return base * (1.0 - relief(sid))


## What the treasury actually gets of the rate in force: a delegated governor (follower_will) multiplies by their output and loses
## the share they skim. 1:1 with tax_rate when nobody governs.
func tax_yield(sid: int) -> float:
	var wm: Variant = _mod("will")
	if wm == null:
		return tax_rate(sid)
	var m: Dictionary = wm.settlement_modifier(sid)
	return tax_rate(sid) * float(m["output"]) * (1.0 - float(m["leak"]))


# ------------------------------------------------------------------ ticks

func tick_week(_week: int, _ctx: Dictionary) -> Array:
	for s: String in _relief.keys():
		if _now() > int((_relief[s] as Array)[1]):
			_relief.erase(s)
	return []


## Each office is checked once every seven days, on the day its key hashes to, so the weekly duty round is spread over the week.
func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var slot := day % 7
	var bmap: Dictionary = {}
	var due: Array = []
	for k: String in _off:
		if k.hash() % 7 == slot:
			due.append(k)
	if due.is_empty():
		return []
	var aud: Variant = _mod("audiences")
	if aud != null:
		bmap = aud.backlog_map(BACKLOG_DAYS)
	for k: String in due:
		_week_office(k, _off[k], bmap)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	# Closed form: unwatched NPC offices keep their duties; player offices accrue neglect for the weeks they were left.
	var weeks := days / 7
	for k: String in _off:
		var o: Dictionary = _off[k]
		if bool(o["player"]) and not bool(o["vacant"]):
			o["neglect"] = float(o["neglect"]) + float(weeks) * 0.5
			if float(o["neglect"]) >= NEGLECT_LIMIT:
				dismiss(k, "neglect of duty")
		else:
			for d: String in DUTIES:
				o["duties"][d]["last"] = _day
	return []


func serialize() -> Dictionary:
	return {"off": _off.duplicate(true), "relief": _relief.duplicate(true), "log": _log.duplicate(), "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_off = (d.get("off", {}) as Dictionary).duplicate(true)
	for k: String in _off:
		var o: Dictionary = _off[k]
		PD.fix_ints(o, ["seat", "level", "since"])
		for dn: String in o["duties"]:
			PD.fix_ints(o["duties"][dn], ["last", "missed"])
	_relief = (d.get("relief", {}) as Dictionary).duplicate(true)
	for s: String in _relief:
		_relief[s][1] = int(_relief[s][1])
	_log = (d.get("log", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
