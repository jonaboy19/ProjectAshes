extends "res://scripts/realm/realm_module.gd"
## Religion and culture (LW-8.1, docs/design/LIVING_WORLD_SANDBOX.md section 14).
##
## FAITHS. `runes` (the Caldric runestone tradition of Valencios), `dawn` (the Church of the Dawn Throne of the eastern kingdoms),
## `wild` (the old ways of the Urrokai and Veyl minorities) and `folk` (no organised church). Each NPC the minds module simulates has a
## belief record: which faith and how intensely (0..100). Belief drifts toward the town's church, rises at festivals and with the
## devout trait, falls with scandal and when a person moves to a kingdom of another faith.
##
## CHURCHES are organizations (organizations.gd, type religious_order) with a record here: the town, the faith, land owned (organization
## assets), a school (seats for children, added to homes.school_seats), a shelter (beds for the hungry and the sick) and INFLUENCE 0..1
## in the town. A church collects a weekly tithe from the town's aggregate households (the money leaves them: minds.agg_take), buys
## land, then a school, then a shelter as it can afford them, and loses influence to scandal. A priest has two routes, parish
## (acolyte, priest, dean, bishop) and cloister (novice, monk, prior, abbot); a step needs belief, years of service and, higher up,
## the church's standing in the town.
##
## THE EASTERN CHURCH KINGDOMS (solmarch with the Aurelis Patriarchate, varska_marches, serathi_lowlands) have a strong church
## (power 0.6..0.85, a closed border, a tithe) while Valencios (caldrenn) has a weak one (0.25): its churches are small, its law is
## secular and a Dawn chapel exists only in the capital. `kingdom_profile` carries the numbers.
##
## CULTURE TAGS belong to a town (primary + at most one minority). They change ETIQUETTE (`etiquette_mod`: how a haggle, a gift, an oath,
## a bribe or an insult lands, -0.5..0.5), PRICES (`price_mult`: a class of goods costs more or less) and LAW (`law_mult`: the fine
## multiplier; `apply_laws` writes the church kingdoms' stricter fines into courts.gd). FESTIVALS are dated; for their days a town's
## trade rises, its mood improves, belief grows and crime falls (`trade_mult`, `mood_bonus`).
##
## Nothing here is per frame: festivals are looked up by day, tithes are weekly, belief drift is a monthly roll bucketed by id.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const YEAR := 360
const FAITHS := ["runes", "dawn", "wild", "folk"]
const BELIEF_MAX := 1000
const CHURCH_MAX := 60
const LAND_COST := 400
const SCHOOL_COST := 250
const SHELTER_COST := 300
const SCHOOL_SEATS := 12
const SHELTER_BEDS := 8
const TITHE_RATE := 0.25
const FESTIVAL_DAYS := 3
const PRIEST_ROUTES := {"parish": ["acolyte", "priest", "dean", "bishop"], "cloister": ["novice", "monk", "prior", "abbot"]}
const PRIEST_BELIEF := [20, 40, 60, 75]
const PRIEST_YEARS := [0, 1, 3, 6]
const PRIEST_INF := [0.0, 0.0, 0.25, 0.5]

## kingdom -> {faith, power, border, tithe}
const KINGDOM_FAITH := {
	"caldrenn": {"faith": "runes", "power": 0.25, "tithe": 0.02, "secular": true},
	"solmarch": {"faith": "dawn", "power": 0.85, "tithe": 0.10, "secular": false, "seat": "Aurelion"},
	"varska_marches": {"faith": "dawn", "power": 0.70, "tithe": 0.08, "secular": false},
	"serathi_lowlands": {"faith": "dawn", "power": 0.60, "tithe": 0.06, "secular": false},
	"seirune_isles": {"faith": "folk", "power": 0.45, "tithe": 0.03, "secular": true},
	"urrokai_clanlands": {"faith": "wild", "power": 0.35, "tithe": 0.0, "secular": true},
	"veylwood": {"faith": "wild", "power": 0.40, "tithe": 0.01, "secular": true},
}
const CHURCH_KINGDOMS := ["solmarch", "varska_marches", "serathi_lowlands"]

const CULTURES := {
	"caldric": {"faith": "runes", "eti": {"haggle": 0.0, "gift": 0.1, "oath": 0.2, "bribe": -0.2, "insult": -0.3},
		"price": {"food": 1.0, "drink": 1.0, "tools": 1.0, "luxury": 1.0, "arms": 1.0, "books": 1.0}, "fine": 1.0},
	"urrokai": {"faith": "wild", "eti": {"haggle": 0.25, "gift": 0.3, "oath": 0.4, "bribe": -0.4, "insult": -0.5},
		"price": {"food": 0.95, "drink": 0.9, "tools": 1.05, "luxury": 1.15, "arms": 0.9, "books": 1.2}, "fine": 0.8},
	"veyl": {"faith": "wild", "eti": {"haggle": -0.1, "gift": 0.35, "oath": 0.1, "bribe": -0.4, "insult": -0.2},
		"price": {"food": 0.92, "drink": 1.0, "tools": 1.08, "luxury": 1.05, "arms": 1.15, "books": 0.85}, "fine": 0.9},
	"solenne": {"faith": "dawn", "eti": {"haggle": -0.25, "gift": 0.0, "oath": 0.45, "bribe": -0.5, "insult": -0.5},
		"price": {"food": 1.05, "drink": 1.1, "tools": 0.95, "luxury": 1.25, "arms": 1.1, "books": 0.9}, "fine": 1.3},
	"frontier": {"faith": "runes", "eti": {"haggle": 0.15, "gift": 0.05, "oath": 0.1, "bribe": -0.05, "insult": -0.1},
		"price": {"food": 1.1, "drink": 1.0, "tools": 1.1, "luxury": 1.1, "arms": 0.9, "books": 1.2}, "fine": 0.9},
}
const KINGDOM_CULTURE := {"caldrenn": "caldric", "solmarch": "solenne", "varska_marches": "solenne", "serathi_lowlands": "solenne",
	"urrokai_clanlands": "urrokai", "veylwood": "veyl"}
const ETIQUETTE := ["haggle", "gift", "oath", "bribe", "insult"]
const GOODS_CLASSES := ["food", "drink", "tools", "luxury", "arms", "books"]

## id -> {name, day of year, faith ("" = all), trade, mood, scale}
const FESTIVALS := {
	"spring_fair": {"name": "Spring Fair", "doy": 40, "faith": "", "trade": 0.22, "mood": 8.0},
	"dawn_feast": {"name": "Dawn Feast", "doy": 95, "faith": "dawn", "trade": 0.12, "mood": 10.0},
	"moonrun": {"name": "Moonrun", "doy": 150, "faith": "wild", "trade": 0.08, "mood": 9.0},
	"harvest_feast": {"name": "Harvest Feast", "doy": 265, "faith": "", "trade": 0.18, "mood": 9.0},
	"kindling_night": {"name": "Kindling Night", "doy": 292, "faith": "runes", "trade": 0.10, "mood": 10.0},
	"midwinter": {"name": "Midwinter Fire", "doy": 350, "faith": "", "trade": 0.10, "mood": 8.0},
}

var auto_seed := true
var seeded := false
var _ch: Dictionary = {}         # org id -> church record
var _bel: Dictionary = {}        # ch -> [faith idx, intensity]
var _share: Dictionary = {}      # sid -> {faith: share} (only towns that differ from the culture's default)
var _pr: Dictionary = {}         # ch -> [route idx, step, since day]
var _kinf: Dictionary = {}       # kingdom -> church influence (changes only)
var _fest_log: Dictionary = {}   # sid -> last festival id announced
var _day := 0
var _seed_todo: Array = []
var _bk: Array = []
var _bk_n := -1
var stats := {"churches": 0, "tithes": 0, "land": 0, "schools": 0, "shelters": 0, "festivals": 0, "conversions": 0, "ordained": 0, "scandals": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ cultures and kingdoms

func kingdom_profile(k: String) -> Dictionary:
	var p: Dictionary = (KINGDOM_FAITH.get(k, {"faith": "folk", "power": 0.3, "tithe": 0.0, "secular": true}) as Dictionary).duplicate()
	p["influence"] = float(_kinf.get(k, p["power"]))
	p["closed"] = k in CHURCH_KINGDOMS
	p["culture"] = String(KINGDOM_CULTURE.get(k, "caldric"))
	return p


## Culture tags of a town: the kingdom's own, a minority in about one village of four, "frontier" on the frontier.
func culture_tags(sid: int) -> Array:
	var tags: Array = ["caldric"]
	var h := absi(hash([WorldSim.SEED, "cult", sid]))
	if h % 100 < 26 and PD.kind_of(sid) in ["village", "frontier_town"]:
		tags.append("urrokai" if (h / 100) % 2 == 0 else "veyl")
	if PD.kind_of(sid) == "frontier_town":
		tags.append("frontier")
	return tags


func tags_of(where: Variant) -> Array:
	if where is String:
		return [String(KINGDOM_CULTURE.get(where, "caldric"))]
	return culture_tags(int(where))


func _tag_avg(tags: Array, getter: Callable) -> float:
	var s := 0.0
	var w := 0.0
	for i in tags.size():
		var wt := 1.0 if i == 0 else 0.5
		s += float(getter.call(String(tags[i]))) * wt
		w += wt
	return s / w if w > 0.0 else 0.0


## How an act lands in a place (a town id or a kingdom id): -0.5 insulting .. +0.5 well thought of.
func etiquette_mod(where: Variant, act: String) -> float:
	return _tag_avg(tags_of(where), func(t: String) -> float: return float(((CULTURES[t] as Dictionary)["eti"] as Dictionary).get(act, 0.0)))


func price_mult(where: Variant, cls: String) -> float:
	if not seeded and hub != null:
		return 1.0
	return _tag_avg(tags_of(where), func(t: String) -> float: return float(((CULTURES[t] as Dictionary)["price"] as Dictionary).get(cls, 1.0)))


func law_mult(where: Variant) -> float:
	var m := _tag_avg(tags_of(where), func(t: String) -> float: return float((CULTURES[t] as Dictionary)["fine"]))
	if where is String and where in CHURCH_KINGDOMS:
		m *= 1.0 + 0.3 * float(kingdom_profile(String(where))["influence"])
	return m


## Writes the church kingdoms' fines (culture + church) into courts.gd. Idempotent.
func apply_laws() -> int:
	var ct: Variant = _mod("courts")
	if ct == null:
		return 0
	var n := 0
	for k: String in KINGDOM_FAITH:
		var m := law_mult(k)
		if absf(m - 1.0) < 0.02:
			continue
		for crime: String in ["assault", "fraud", "robbery", "trespass", "black_market", "extortion"]:
			if ct.set_law(k, crime, "fine_mult", snappedf(m, 0.01)):
				n += 1
	return n


# ------------------------------------------------------------------ shares and festivals

## Faith shares of a town (sum 1): its culture's faith, shifted by the church there.
func faith_share(sid: int) -> Dictionary:
	if _share.has(sid):
		return (_share[sid] as Dictionary).duplicate()
	var out := {}
	for f: String in FAITHS:
		out[f] = 0.0
	var tags := culture_tags(sid)
	var base := String((CULTURES[String(tags[0])] as Dictionary)["faith"])
	out[base] = 0.8
	out["folk"] = 0.2
	if tags.size() > 1 and tags[1] in ["urrokai", "veyl"]:
		out["wild"] = 0.45
		out[base] = 0.4
		out["folk"] = 0.15
	return out


func dominant_faith(sid: int) -> String:
	var sh := faith_share(sid)
	var best := "folk"
	var bv := -1.0
	for f: String in FAITHS:
		if float(sh[f]) > bv:
			bv = float(sh[f])
			best = f
	return best


func festival_on(doy: int, sid: int) -> String:
	for fid: String in FESTIVALS:
		var f: Dictionary = FESTIVALS[fid]
		var start := int(f["doy"])
		if doy >= start and doy < start + FESTIVAL_DAYS:
			if String(f["faith"]) == "" or float(faith_share(sid).get(String(f["faith"]), 0.0)) >= 0.2:
				return fid
	return ""


func festival_at(sid: int, day := -1) -> String:
	if not seeded and hub != null:
		return ""
	var d := _now() if day < 0 else day
	return festival_on(posmod(d, YEAR), sid)


## Trade multiplier of a town today (1.0 outside festivals).
func trade_mult(sid: int) -> float:
	var f := festival_at(sid)
	return 1.0 + float((FESTIVALS[f] as Dictionary)["trade"]) if f != "" else 1.0


## Average trade multiplier of a town over the `days` days that end on `day` (a closed-form settle covers a stretch, not a day).
func trade_avg(sid: int, day: int, days: int) -> float:
	if not seeded and hub != null:
		return 1.0
	var extra := 0.0
	for fid: String in FESTIVALS:
		var f: Dictionary = FESTIVALS[fid]
		if String(f["faith"]) != "" and float(faith_share(sid).get(String(f["faith"]), 0.0)) < 0.2:
			continue
		for y in range((day - days) / YEAR - 1, day / YEAR + 2):
			var a: int = y * YEAR + int(f["doy"])
			var lo := maxi(a, day - days + 1)
			var hi := mini(a + FESTIVAL_DAYS - 1, day)
			if hi >= lo:
				extra += float(f["trade"]) * float(hi - lo + 1)
	return 1.0 + extra / float(maxi(1, days))


## A town's general price level for what a shop sells (food, drink, tools, luxuries), from its culture tags; 1.0 until the world is seeded.
func goods_mult(sid: int) -> float:
	if not seeded and hub != null:
		return 1.0
	return (price_mult(sid, "food") + price_mult(sid, "drink") + price_mult(sid, "tools") + price_mult(sid, "luxury")) / 4.0


func mood_bonus(sid: int) -> float:
	var f := festival_at(sid)
	return float((FESTIVALS[f] as Dictionary)["mood"]) if f != "" else 0.0


# ------------------------------------------------------------------ belief

func belief_of(ch: String) -> float:
	return float((_bel.get(ch, [0, 0]) as Array)[1])


func faith_of(ch: String) -> String:
	var b: Array = _bel.get(ch, [])
	return String(FAITHS[int(b[0])]) if not b.is_empty() else "folk"


func belief_count() -> int:
	return _bel.size()


func set_belief(ch: String, faith: String, intensity: float) -> bool:
	var fi := FAITHS.find(faith)
	if fi < 0:
		return false
	if not _bel.has(ch) and _bel.size() >= BELIEF_MAX:
		return false
	_bel[ch] = [fi, clampi(int(intensity), 0, 100)]
	return true


func adjust_belief(ch: String, d: float) -> void:
	if _bel.has(ch):
		(_bel[ch] as Array)[1] = clampi(int((_bel[ch] as Array)[1]) + int(round(d)), 0, 100)


## Initial belief of a new character: the town's faith, devout people believe hard, sly or curious ones less.
func seed_belief(ch: String, sid: int, traits: Array) -> void:
	if _bel.has(ch):
		return
	var h := absi(hash([WorldSim.SEED, "bel", ch]))
	var sh := faith_share(sid)
	var roll := float(h % 1000) / 1000.0
	var acc := 0.0
	var pick := "folk"
	for f: String in FAITHS:
		acc += float(sh[f])
		if roll <= acc:
			pick = f
			break
	var inten := 25 + (h / 1000) % 45
	if "devout" in traits:
		inten += 25
	if "curious" in traits or "sly" in traits:
		inten -= 12
	if pick == "folk":
		inten = mini(inten, 40)
	set_belief(ch, pick, inten)


func drop_character(ch: String) -> void:
	_bel.erase(ch)
	_pr.erase(ch)


func on_emigrated(ch: String, kingdom: String) -> void:
	if not _bel.has(ch):
		return
	var kp := kingdom_profile(kingdom)
	var cur := faith_of(ch)
	if String(kp["faith"]) != cur:
		adjust_belief(ch, -10)
		# A new land's church pulls on the convert: stronger churches convert more.
		if float(absi(hash([WorldSim.SEED, "conv", ch, _now()])) % 1000) / 1000.0 < float(kp["power"]) * 0.5:
			set_belief(ch, String(kp["faith"]), float(belief_of(ch)) * 0.6)
			stats["conversions"] = int(stats["conversions"]) + 1


func scandal(sid: int, oid := "") -> void:
	stats["scandals"] = int(stats["scandals"]) + 1
	var key := oid if oid != "" else church_org_at(sid)
	if key != "" and _ch.has(key):
		(_ch[key] as Dictionary)["inf"] = clampf(float((_ch[key] as Dictionary)["inf"]) - 0.08, 0.0, 1.0)
		var mn: Variant = _mod("minds")
		if mn != null and bool(mn.has_method("believers_at")):
			for c: Variant in mn.believers_at(sid, 6, 0):
				adjust_belief(String(c), -4)
	Events.log_to(hub, "emergency", "ss:%d" % sid, [key], "scandal", "A scandal shakes the church", 3)


# ------------------------------------------------------------------ churches

func church(oid: String) -> Dictionary:
	return (_ch.get(oid, {}) as Dictionary).duplicate(true)


func churches(sid := -1) -> Array:
	var out: Array = []
	for oid: Variant in _ch:
		if sid < 0 or int((_ch[oid] as Dictionary)["sid"]) == sid:
			out.append(String(oid))
	out.sort()
	return out


func church_org_at(sid: int) -> String:
	for oid: String in churches(sid):
		return oid
	return ""


## The church of a town as a record: found one with a funded priest (an organization of type religious_order, organizations.gd).
func found_church(sid: int, faith: String, founder := "", nm := "", cash := 500) -> Dictionary:
	var om: Variant = _mod("organizations")
	if om == null or _ch.size() >= CHURCH_MAX or not (faith in FAITHS):
		return {"ok": false, "reason": "No more churches can be founded."}
	var lead := founder
	if lead == "":
		var reg: Variant = _mod("registry")
		lead = String(reg.mint("ch")) if reg != null else ""
		if lead == "":
			return {"ok": false, "reason": "No ids left."}
		om.ensure_char(lead, {"prof": "priest", "cash": cash, "sid": sid, "sk": {"faith": 0.7, "lore": 0.6}, "rep": 15.0, "amb": "found"})
	var label := nm if nm != "" else _church_name(sid, faith)
	var res: Dictionary = om.start_founding(lead, "religious_order", label, sid, "autonomous")
	if not bool(res.get("ok", false)):
		return res
	var oid := String(res["org"])
	_ch[oid] = {"sid": sid, "faith": faith, "land": [], "school": 0, "shelter": 0, "inf": _base_influence(sid, faith), "tithe": 0, "priests": 1, "day": _now(), "name": label}
	stats["churches"] = int(stats["churches"]) + 1
	set_belief(lead, faith, 85.0)
	_ordain_raw(lead, 0)
	return {"ok": true, "org": oid, "founder": lead}


func _church_name(sid: int, faith: String) -> String:
	var kind := {"runes": "Keepers of the Runestone", "dawn": "Chapel of the Dawn Throne", "wild": "Circle of the Old Ways", "folk": "Wayside Shrine"}
	return "%s of %s" % [String(kind[faith]), PD.sname(sid)]


func _base_influence(sid: int, faith: String) -> float:
	var kp := kingdom_profile(PD.kingdom_of(sid))
	var m := float(kp["power"])
	if faith != String(kp["faith"]):
		m *= 0.4                                           # a foreign church starts small (the Dawn chapel in Kingsreach)
	return clampf(m + float(absi(hash([WorldSim.SEED, "inf", sid])) % 20) / 200.0 - 0.05, 0.02, 1.0)


func influence_at(sid: int) -> float:
	var best := 0.0
	for oid: String in churches(sid):
		best = maxf(best, float((_ch[oid] as Dictionary)["inf"]))
	return best


func school_seats(sid: int) -> int:
	var n := 0
	for oid: String in churches(sid):
		n += int((_ch[oid] as Dictionary)["school"])
	return n


func shelter_capacity(sid: int) -> int:
	var n := 0
	for oid: String in churches(sid):
		n += int((_ch[oid] as Dictionary)["shelter"])
	return n


## Beds taken by the poor and sick of the town: returns how many were housed (the rest are turned away).
func shelter_take(sid: int, n: int) -> int:
	var got := mini(n, shelter_capacity(sid))
	if got > 0:
		for oid: String in churches(sid):
			(_ch[oid] as Dictionary)["inf"] = clampf(float((_ch[oid] as Dictionary)["inf"]) + 0.01 * float(got) / 4.0, 0.0, 1.0)
			break
	return got


## Warm start: runestone keepers in the towns of Valencios (small), one Dawn chapel in the capital, as organizations. `seed_world()` does it all at
## once (tests, tools); the game's first days call `_seed_some` so no single job founds fifteen churches.
func seed_world() -> void:
	_seed_plan()
	while not _seed_todo.is_empty():
		_seed_some(1000)


func _seed_plan() -> void:
	seeded = true
	apply_laws()
	_seed_todo = []
	var n := 0
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var kind := String(s.get("kind", "village"))
		var want := kind != "village" or absi(hash([WorldSim.SEED, "church", sid])) % 3 == 0
		if want and n < 14:
			_seed_todo.append([sid, "runes"])
			n += 1
	var cap := PD.capital_sid()
	if cap >= 0:
		_seed_todo.append([cap, "dawn"])


func _seed_some(k: int) -> void:
	var done := 0
	while not _seed_todo.is_empty() and done < k:
		var t: Array = _seed_todo.pop_front()
		if int(t[0]) >= 0:
			if String(t[1]) == "dawn":
				if church_org_at(int(t[0])) != "":
					found_church(int(t[0]), "dawn", "", "Dawn Chapel of %s" % PD.sname(int(t[0])), 400)
			else:
				found_church(int(t[0]), String(t[1]))
		done += 1


# ------------------------------------------------------------------ priests

func priest_step(ch: String) -> Dictionary:
	var p: Array = _pr.get(ch, [])
	if p.is_empty():
		return {}
	var route: String = ["parish", "cloister"][int(p[0])]
	return {"route": route, "step": int(p[1]), "title": String((PRIEST_ROUTES[route] as Array)[int(p[1])]), "since": int(p[2])}


func _ordain_raw(ch: String, route: int) -> void:
	_pr[ch] = [route, 0, _now()]


func ordain(ch: String, route: String) -> Dictionary:
	if not PRIEST_ROUTES.has(route):
		return {"ok": false, "reason": "No such route."}
	if _pr.has(ch):
		return {"ok": false, "reason": "Already ordained."}
	if belief_of(ch) < float(PRIEST_BELIEF[0]) or faith_of(ch) == "folk":
		return {"ok": false, "reason": "The calling is not strong enough."}
	_ordain_raw(ch, ["parish", "cloister"].find(route))
	stats["ordained"] = int(stats["ordained"]) + 1
	return {"ok": true, "title": (PRIEST_ROUTES[route] as Array)[0]}


## Next step if belief, years of service and (higher up) the church's standing allow it.
func advance_priest(ch: String, sid: int) -> Dictionary:
	var p: Array = _pr.get(ch, [])
	if p.is_empty():
		return {"ok": false, "reason": "Not ordained."}
	var nxt := int(p[1]) + 1
	if nxt >= 4:
		return {"ok": false, "reason": "Already at the top."}
	if belief_of(ch) < float(PRIEST_BELIEF[nxt]):
		return {"ok": false, "reason": "Faith is not deep enough."}
	if float(_now() - int(p[2])) / float(YEAR) < float(PRIEST_YEARS[nxt]) - 0.001:
		return {"ok": false, "reason": "Not enough years of service."}
	if influence_at(sid) < float(PRIEST_INF[nxt]):
		return {"ok": false, "reason": "The church here is too weak to seat you."}
	p[1] = nxt
	var route: String = ["parish", "cloister"][int(p[0])]
	return {"ok": true, "title": String((PRIEST_ROUTES[route] as Array)[nxt])}


func priests_in(sid: int) -> int:
	var n := 0
	for oid: String in churches(sid):
		n += int((_ch[oid] as Dictionary)["priests"])
	return n


# ------------------------------------------------------------------ ticks

func _week_church(week: int) -> void:
	var om: Variant = _mod("organizations")
	var mn: Variant = _mod("minds")
	var ids := churches()
	for oid: String in ids:
		var c: Dictionary = _ch[oid]
		if om != null and not om.exists(oid):
			_ch.erase(oid)
			continue
		var sid := int(c["sid"])
		if mn != null and om != null and int(om.org(oid).get("stage", 4)) < 3:
			mn.advance_founding(oid, _now(), true)               # the church's own founding is walked through its steps
		var pop := int(PD.settlement(sid).get("population", 200))
		var kp := kingdom_profile(PD.kingdom_of(sid))
		var sh := float(faith_share(sid).get(String(c["faith"]), 0.2))
		var want := int(round(float(pop) * sh * float(c["inf"]) * TITHE_RATE * (0.5 + float(kp["tithe"]) * 5.0)))
		var got := want
		if mn != null:
			got = int(mn.agg_take(sid, want))
		if om != null and got > 0:
			om.pay_to(oid, got)
		c["tithe"] = int(c["tithe"]) + got
		stats["tithes"] = int(stats["tithes"]) + got
		# What the church does with its money, in order: land, school, shelter.
		var treasury := int(om.org(oid).get("treasury", 0)) if om != null else 0
		if (c["land"] as Array).is_empty() and treasury >= LAND_COST:
			if om.pay_from(oid, LAND_COST):
				var aid: String = om.add_asset(oid, "land", "Glebe of %s" % PD.sname(sid), LAND_COST)
				(c["land"] as Array).append(aid)
				stats["land"] = int(stats["land"]) + 1
		elif int(c["school"]) == 0 and not (c["land"] as Array).is_empty() and treasury >= SCHOOL_COST:
			if om.pay_from(oid, SCHOOL_COST):
				c["school"] = SCHOOL_SEATS
				stats["schools"] = int(stats["schools"]) + 1
		elif int(c["shelter"]) == 0 and not (c["land"] as Array).is_empty() and treasury >= SHELTER_COST:
			if om.pay_from(oid, SHELTER_COST):
				c["shelter"] = SHELTER_BEDS
				stats["shelters"] = int(stats["shelters"]) + 1
		# Influence: grows with works, drifts back toward the kingdom's church power.
		var target := float(kp["power"]) * (0.7 if String(c["faith"]) == String(kp["faith"]) else 0.3)
		target += 0.05 * float(int(c["school"]) > 0) + 0.05 * float(int(c["shelter"]) > 0) + 0.02 * float(c["priests"])
		c["inf"] = snappedf(clampf(float(c["inf"]) + (target - float(c["inf"])) * 0.02, 0.0, 1.0), 0.001)
	# The eastern kingdoms' churches grow slowly with their tithes.
	for k: String in CHURCH_KINGDOMS:
		var base := float(kingdom_profile(k)["power"])
		_kinf[k] = snappedf(clampf(float(_kinf.get(k, base)) + (absi(hash([WorldSim.SEED, "kinf", k, week])) % 21 - 10) * 0.0004, 0.2, 1.0), 0.001)


func _festival_day(day: int) -> void:
	var doy := posmod(day, YEAR)
	for fid: String in FESTIVALS:
		if doy != int((FESTIVALS[fid] as Dictionary)["doy"]):
			continue
		stats["festivals"] = int(stats["festivals"]) + 1
		var nw: Variant = _mod("news")
		var mn: Variant = _mod("minds")
		for s: Dictionary in WorldGen.settlements:
			var sid := int(s["id"])
			if festival_on(doy, sid) != fid:
				continue
			if sid % 5 == day / YEAR % 5 and nw != null:
				nw.post("festival", sid, "%s begins in %s." % [String((FESTIVALS[fid] as Dictionary)["name"]), PD.sname(sid)], 0.6)
			if mn != null and bool(mn.has_method("believers_at")):
				for c: Variant in mn.believers_at(sid, 8, 0):
					adjust_belief(String(c), 3)
		Events.log_to(hub, "trade", "", [], "festival", "%s is kept" % String((FESTIVALS[fid] as Dictionary)["name"]), 2)


func _drift(day: int) -> void:
	# A monthly nudge: each believer's id picks its day; the town's church pulls belief toward its faith.
	if _bk_n != _bel.size() or _bk.is_empty() or day % 30 == 0:
		_bk = []
		for i in 30:
			_bk.append([])
		for ch2: Variant in _bel:
			(_bk[ch2.hash() % 30] as Array).append(String(ch2))
		_bk_n = _bel.size()
	var mn: Variant = _mod("minds")
	for ch: String in _bk[day % 30]:
		if not _bel.has(ch):
			continue
		var b: Array = _bel[ch]
		var sid: int = int(mn.town_of(ch)) if mn != null else -1
		if sid < 0:
			continue
		var inf := influence_at(sid)
		var dom := dominant_faith(sid)
		if FAITHS[int(b[0])] == dom:
			b[1] = clampi(int(b[1]) + (1 if inf > 0.3 else 0) - (1 if inf < 0.12 and int(b[1]) > 50 else 0), 0, 100)
		elif int(b[1]) < 35 and float(absi(hash([WorldSim.SEED, "cv", ch, day])) % 1000) / 1000.0 < 0.1 + inf * 0.2:
			b[0] = FAITHS.find(dom)
			stats["conversions"] = int(stats["conversions"]) + 1


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	if auto_seed and not seeded and hub != null and hub.mod("organizations") != null and bool(hub.mod("organizations").auto_seed):
		_seed_plan()
	if not _seed_todo.is_empty():
		_seed_some(2)
	_festival_day(day)
	_drift(day)
	return []


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_week_church(week)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	for i in mini(days / 7, 6):
		_week_church(_day / 7 - i)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var ch: Dictionary = {}
	for oid: Variant in _ch:
		var c: Dictionary = _ch[oid]
		ch[oid] = [int(c["sid"]), FAITHS.find(c["faith"]), (c["land"] as Array).duplicate(), int(c["school"]), int(c["shelter"]), float(c["inf"]), int(c["tithe"]), int(c["priests"]),
			int(c["day"]), String(c["name"])]
	return {"ch": ch, "bel": _bel.duplicate(true), "pr": _pr.duplicate(true), "kinf": _kinf.duplicate(), "seeded": seeded, "todo": _seed_todo.duplicate(true), "day": _day,
		"st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ch = {}
	_bel = {}
	_pr = {}
	_kinf = {}
	var chs: Dictionary = d.get("ch", {})
	for oid: Variant in chs:
		var a: Array = chs[oid]
		var land: Array = []
		for l: Variant in a[2]:
			land.append(String(l))
		_ch[String(oid)] = {"sid": int(a[0]), "faith": String(FAITHS[clampi(int(a[1]), 0, FAITHS.size() - 1)]), "land": land, "school": int(a[3]), "shelter": int(a[4]),
			"inf": float(a[5]), "tithe": int(a[6]), "priests": int(a[7]), "day": int(a[8]), "name": String(a[9])}
	var bel: Dictionary = d.get("bel", {})
	for k: Variant in bel:
		_bel[String(k)] = [int((bel[k] as Array)[0]), int((bel[k] as Array)[1])]
	var pr: Dictionary = d.get("pr", {})
	for k: Variant in pr:
		_pr[String(k)] = [int((pr[k] as Array)[0]), int((pr[k] as Array)[1]), int((pr[k] as Array)[2])]
	var kinf: Dictionary = d.get("kinf", {})
	for k: Variant in kinf:
		_kinf[String(k)] = float(kinf[k])
	seeded = bool(d.get("seeded", false))
	_seed_todo = []
	for t: Variant in d.get("todo", []):
		_seed_todo.append([int((t as Array)[0]), String((t as Array)[1])])
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
