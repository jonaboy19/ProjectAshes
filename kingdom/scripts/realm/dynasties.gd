extends "res://scripts/realm/realm_module.gd"
## Dynasties and families as institutions (LW-8, docs/design/LIVING_WORLD_SANDBOX.md section 11 and 12).
##
## A HOUSE (a family name) is a record: a head, the line of heads, a seat, a family REPUTATION (kept in reputation.gd under the subject
## "h:<name>": what one member does moves it, and it moves what the town believes of every member), a SPECIALTY (the trade most of its
## members follow; children are steered to it and members of it work better), FEUDS with other houses, and an ESTATE. When a member
## dies their businesses (businesses.gd), farms (farming.gd) and cash go to an heir by the house's custom (spouse, eldest adult child,
## then other kin of the house in the town, else the lord's steward takes the land back), taxed like family.gd's inheritance; the heir is
## written into the line and the house's standing carries on. Noble houses are tied to succession.gd: the title holders there age and
## die here by the same mortality table, which makes the succession module run its claims, regencies and disputes.
##
## FEUDS start from a killing, a theft, a ruined business, a refused match or a lost dispute. Heat decays by itself, flares into violence
## when high (an assault event, rumours, the town's mood) and ends by blood price (gold to the injured house), by a marriage between the
## houses, or by time. A marriage into a feuding house is not made while the heat is high.
##
## The player: `sync_player_family(fam)` copies the family.gd children and spouse into the player's household in homes.gd;
## `player_succeeded(...)` carries the house to the heir (standing and feuds reduced, estate unchanged because the realm owns it under
## the player's id), driven by the "succession / heir" event family.gd writes.
##
## Nothing is per frame: weekly roll for nobles, weekly feud step, estates on death.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const HOUSE_MAX := 180
const LINE_MAX := 5
const FEUD_MAX := 4
const FEUD_FLARE := 60.0
const FEUD_PEACE := 8.0
const ESTATE_TAX := 0.25
const NOBLE_LORDS := 8
const LIFE_SCALE := {"shenlu_peaks": 2.0, "hollowdeep": 3.0, "veylwood": 10.0}
const SPEC_MIN_SHARE := 0.4
const SPEC_MIN_MEMBERS := 2
const HOUSE_NAMES := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne",
	"Wick", "Yarrow", "Corrin", "Dell", "Fenwick", "Garrow", "Holt", "Kemp", "Lorne", "Merrow", "Quill", "Rook", "Sedge", "Tarn", "Vane", "Wren"]

var _h: Dictionary = {}          # name -> house
var _kin: Dictionary = {}        # ch -> house name (maintained by minds)
var _nob: Dictionary = {}        # title key -> {house, watched}
var _day := 0
var _last_ev := 0
var _last_rv := 0
var stats := {"estates": 0, "heirless": 0, "feuds": 0, "violence": 0, "peace": 0, "successions": 0, "noble_deaths": 0, "taxed": 0, "inherited_biz": 0, "inherited_land": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 3) -> void:
	Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, w)


static func name_for(sid: int, k: int) -> String:
	return String(HOUSE_NAMES[absi(hash([WorldSim.SEED, "hn", sid, k])) % HOUSE_NAMES.size()])


# ------------------------------------------------------------------ houses

func ensure_house(nm: String, sid := -1, noble := false) -> Dictionary:
	if not _h.has(nm):
		if _h.size() >= HOUSE_MAX:
			return {}
		_h[nm] = {"n": nm, "sid": sid, "head": "", "line": [], "feud": {}, "noble": noble, "spec": "", "mem": 0, "founded": _now(), "est": 0, "lost": 0}
	return _h[nm]


func house(nm: String) -> Dictionary:
	return (_h.get(nm, {}) as Dictionary).duplicate(true)


func houses() -> Array:
	var out: Array = _h.keys()
	out.sort()
	return out


func house_count() -> int:
	return _h.size()


func house_of(ch: String) -> String:
	return String(_kin.get(ch, ""))


func set_house(ch: String, nm: String, sid := -1) -> void:
	var h := ensure_house(nm, sid)
	if h.is_empty():
		return
	_kin[ch] = nm
	h["mem"] = int(h["mem"]) + 1
	if String(h["head"]) == "":
		_set_head(h, ch)


func leave_house(ch: String) -> void:
	var nm := String(_kin.get(ch, ""))
	if nm == "":
		return
	_kin.erase(ch)
	if _h.has(nm):
		var h: Dictionary = _h[nm]
		h["mem"] = maxi(0, int(h["mem"]) - 1)


func _set_head(h: Dictionary, ch: String) -> void:
	h["head"] = ch
	var line: Array = h["line"]
	line.append(ch)
	if line.size() > LINE_MAX:
		line.pop_front()


func members_of(nm: String) -> Array:
	var out: Array = []
	for ch: Variant in _kin:
		if String(_kin[ch]) == nm:
			out.append(String(ch))
	return out


func head_of(nm: String) -> String:
	return String((_h.get(nm, {}) as Dictionary).get("head", ""))


## Reputation of the house: the mean of four truth axes of "h:<name>" (-100..100).
func family_rep(nm: String) -> float:
	var rep: Variant = _mod("reputation")
	if rep == null:
		return 0.0
	var t: Dictionary = rep.truth("h:" + nm)
	if t.is_empty():
		return 0.0
	return (float(t.get("trust", 0.0)) + float(t.get("legitimacy", 0.0)) + float(t.get("competence", 0.0)) + float(t.get("reliability", 0.0))) / 4.0


## A member's deed moves the house too. `deed` is one of reputation.gd's DEEDS.
func deed(ch: String, deed_: String, sid: int, mag := 1.0) -> void:
	var rep: Variant = _mod("reputation")
	if rep == null:
		return
	var nm := house_of(ch)
	rep.on_deed("i:" + ch, deed_, sid, mag, {"house": "h:" + nm} if nm != "" else {})
	if nm != "":
		rep.on_deed("h:" + nm, deed_, sid, mag * 0.5, {"channels": []})


# ------------------------------------------------------------------ specialty

## Recompute from the members given: {profession: count}. A specialty needs a share and a few members.
func set_specialty(nm: String, counts: Dictionary) -> String:
	var h: Dictionary = _h.get(nm, {})
	if h.is_empty():
		return ""
	var tot := 0
	var best := ""
	var bn := 0
	var keys: Array = counts.keys()
	keys.sort()
	for k: String in keys:
		tot += int(counts[k])
		if int(counts[k]) > bn:
			bn = int(counts[k])
			best = k
	h["spec"] = best if bn >= SPEC_MIN_MEMBERS and float(bn) / float(maxi(1, tot)) >= SPEC_MIN_SHARE else ""
	return String(h["spec"])


func specialty(nm: String) -> String:
	return String((_h.get(nm, {}) as Dictionary).get("spec", ""))


## Children of a house with a specialty follow it 6 times in 10. Deterministic.
func steer_trade(nm: String, ch: String, fallback: String) -> String:
	var sp := specialty(nm)
	if sp != "" and absi(hash([WorldSim.SEED, "steer", ch])) % 10 < 6:
		return sp
	return fallback


func skill_bonus(ch: String, prof: String) -> float:
	var sp := specialty(house_of(ch))
	return 0.1 if sp != "" and sp == prof else 0.0


# ------------------------------------------------------------------ feuds

func feud_heat(a: String, b: String) -> float:
	var f: Array = ((_h.get(a, {}) as Dictionary).get("feud", {}) as Dictionary).get(b, [])
	return float(f[0]) if not f.is_empty() else 0.0


func feuds_of(nm: String) -> Array:
	var out: Array = []
	for o: Variant in (_h.get(nm, {}) as Dictionary).get("feud", {}):
		var f: Array = (_h[nm]["feud"] as Dictionary)[o]
		out.append({"other": String(o), "heat": float(f[0]), "cause": String(f[1]), "since": int(f[2])})
	return out


func feud_count() -> int:
	var n := 0
	for nm: Variant in _h:
		n += ((_h[nm] as Dictionary)["feud"] as Dictionary).size()
	return n / 2


func open_feud(a: String, b: String, cause: String, heat := 40.0) -> bool:
	if a == b or a == "" or b == "":
		return false
	var ha := ensure_house(a)
	var hb := ensure_house(b)
	if ha.is_empty() or hb.is_empty():
		return false
	var fresh := not (ha["feud"] as Dictionary).has(b)
	for pair: Array in [[ha, b], [hb, a]]:
		var f: Dictionary = (pair[0] as Dictionary)["feud"]
		if f.has(String(pair[1])):
			(f[String(pair[1])] as Array)[0] = minf(100.0, float((f[String(pair[1])] as Array)[0]) + heat * 0.5)
		elif f.size() < FEUD_MAX:
			f[String(pair[1])] = [minf(100.0, heat), cause, _now()]
		else:
			return false
	if fresh:
		stats["feuds"] = int(stats["feuds"]) + 1
		_ev("emergency", int(ha["sid"]), [head_of(a), head_of(b)], "feud", "The houses of %s and %s fall out" % [a, b], 3)
	return true


## Ends a feud: "blood_price" (gold from `a` to `b`), "marriage" (the houses join), "time" (nothing but patience).
func end_feud(a: String, b: String, how: String, gold := 0) -> Dictionary:
	if not (((_h.get(a, {}) as Dictionary).get("feud", {}) as Dictionary).has(b)):
		return {"ok": false, "reason": "There is no feud."}
	var heat := feud_heat(a, b)
	if how == "blood_price":
		var om: Variant = _mod("organizations")
		if om == null or gold <= 0 or not om.pay(head_of(a), gold):
			return {"ok": false, "reason": "The injured house wants a price."}
		om.earn(head_of(b), gold)
		var need := heat * 2.0
		if float(gold) < need:
			((_h[a]["feud"] as Dictionary)[b] as Array)[0] = heat - float(gold) / 4.0
			((_h[b]["feud"] as Dictionary)[a] as Array)[0] = heat - float(gold) / 4.0
			return {"ok": true, "ended": false, "heat": heat - float(gold) / 4.0}
	elif how != "marriage" and how != "time":
		return {"ok": false, "reason": "No such way."}
	(_h[a]["feud"] as Dictionary).erase(b)
	(_h[b]["feud"] as Dictionary).erase(a)
	stats["peace"] = int(stats["peace"]) + 1
	_ev("contract", int(_h[a]["sid"]), [head_of(a), head_of(b)], "feud_ended", "The feud of %s and %s ends (%s)" % [a, b, how], 3)
	return {"ok": true, "ended": true}


func _week_feuds(week: int) -> void:
	var names := houses()
	for a: String in names:
		var h: Dictionary = _h[a]
		var f: Dictionary = h["feud"]
		var others: Array = f.keys()
		others.sort()
		for b: String in others:
			if a > b:
				continue
			var row: Array = f[b]
			var heat := snappedf(float(row[0]) * 0.965, 0.01)
			row[0] = heat
			var other: Array = (_h[b]["feud"] as Dictionary).get(a, [])
			if not other.is_empty():
				other[0] = heat
			if heat < FEUD_PEACE:
				f.erase(b)
				(_h[b]["feud"] as Dictionary).erase(a)
				stats["peace"] = int(stats["peace"]) + 1
				continue
			if heat > FEUD_FLARE and absi(hash([WorldSim.SEED, "flare", a, b, week])) % 100 < 14:
				stats["violence"] = int(stats["violence"]) + 1
				row[0] = minf(100.0, heat + 6.0)
				if not other.is_empty():
					other[0] = row[0]
				var sid := int(h["sid"])
				_ev("crime", sid, [head_of(a), head_of(b)], "feud_violence", "Men of %s and %s brawl" % [a, b], 4)
				var rm: Variant = _mod("rumours")
				if rm != null and head_of(a) != "":
					rm.say("crime", head_of(a), sid, -35.0, {"origin": "gossip"})


# ------------------------------------------------------------------ estates

## Who inherits from `ch`: spouse first if the house has no adult child; the eldest adult child otherwise; then kin of the house in the same town.
func heir_of(ch: String) -> String:
	var mn: Variant = _mod("minds")
	if mn == null:
		return ""
	var kids: Array = mn.children_of(ch)
	var best := ""
	var ba := -1
	for k: Variant in kids:
		var a: int = mn.age_of(String(k))
		if a > ba:
			ba = a
			best = String(k)
	if best != "":
		return best
	var sp: String = mn.spouse_of(ch)
	if sp != "" and mn.is_alive(sp):
		return sp
	var nm := house_of(ch)
	if nm == "":
		return ""
	var sid: int = mn.town_of(ch)
	var cand: Array = members_of(nm)
	cand.sort()
	for c: Variant in cand:
		if String(c) != ch and mn.is_alive(String(c)) and mn.town_of(String(c)) == sid and mn.age_of(String(c)) >= 16:
			return String(c)
	return ""


## Settle the estate of a dead character. Returns {heir, businesses, parcels, cash}.
func settle_estate(ch: String, cause := "age") -> Dictionary:
	var heir := heir_of(ch)
	var res := {"heir": heir, "businesses": [], "parcels": [], "cash": 0}
	var om: Variant = _mod("organizations")
	var bz: Variant = _mod("businesses")
	var fm: Variant = _mod("farming")
	if bz != null:
		for b: Variant in bz.owned_by(ch):
			var bid := String(b)
			if heir != "" and bz.transfer_shares(bid, ch, heir, int(bz.biz(bid).get("sh", {}).get(ch, 0)), 0):
				(res["businesses"] as Array).append(bid)
				stats["inherited_biz"] = int(stats["inherited_biz"]) + 1
			else:
				bz.liquidate(bid, "", "owner died")
	if fm != null:
		var fcash := 0
		var frow := -1
		if fm.farmers().has(ch):
			fcash = int(fm.farmer(ch)["cash"])
			frow = int(fm.farmer(ch)["row"])
		for p: Variant in fm.parcels_of(ch):
			var pid := String(p)
			if heir != "":
				fm.transfer(pid, heir, "inheritance")
				if not fm.farmers().has(heir):
					fm.add_farmer(heir, int(fm.parcel(pid)["sid"]), 0, 0.5, frow, "Farmer %s" % heir)
				(res["parcels"] as Array).append(pid)
				stats["inherited_land"] = int(stats["inherited_land"]) + 1
			else:
				fm.transfer(pid, "lord:crown", "escheat")
		if fm.farmers().has(ch):
			# Farming keeps a cached list of its farmers: the dead one is not removed, only emptied and put out of business for good.
			var dead_f: Dictionary = fm.farmer(ch)
			dead_f["cash"] = 0
			dead_f["amb"] = 0.0
			dead_f["bust"] = 1 << 30
			if heir != "" and fcash > 0 and om != null:
				om.earn(heir, int(float(fcash) * (1.0 - ESTATE_TAX)))
	if om != null:
		var cash := int(om.purse(ch))
		if cash > 0 and om.pay(ch, cash):
			var tax := int(float(cash) * ESTATE_TAX)
			stats["taxed"] = int(stats["taxed"]) + tax
			if heir != "":
				om.earn(heir, cash - tax)
			res["cash"] = cash - tax
	stats["estates"] = int(stats["estates"]) + 1
	if heir == "":
		stats["heirless"] = int(stats["heirless"]) + 1
	var nm := house_of(ch)
	if nm != "" and _h.has(nm):
		var h: Dictionary = _h[nm]
		if String(h["head"]) == ch:
			if heir != "":
				_set_head(h, heir)
				if house_of(heir) == "":
					set_house(heir, nm)
			else:
				h["head"] = ""
		h["est"] = int(h["est"]) + 1
		if heir != "" and not (res["businesses"] as Array).is_empty():
			deed(heir, "built", int(h["sid"]), 0.5)
	if heir != "":
		var rm: Variant = _mod("rumours")
		if rm != null:
			rm.say("succession", heir, _sid_of(ch), 10.0)
		_ev("succession", _sid_of(ch), [ch, heir], "estate", "%s's estate passes to an heir (%s)" % [ch, cause], 4)
	return res


func _sid_of(ch: String) -> int:
	var mn: Variant = _mod("minds")
	return int(mn.town_of(ch)) if mn != null else -1


## A character died. Settles the estate, takes the line forward, starts a feud when it was a killing.
func on_death(ch: String, cause := "age", killer := "") -> Dictionary:
	var nm := house_of(ch)
	var res := settle_estate(ch, cause)
	if killer != "" and house_of(killer) != "" and nm != "" and house_of(killer) != nm:
		open_feud(nm, house_of(killer), "killing", 70.0)
	leave_house(ch)
	return res


# ------------------------------------------------------------------ nobles (succession.gd)

func _noble_keys() -> Array:
	var keys: Array = []
	for k: String in PD.kingdoms():
		keys.append("crown:" + k)
	var lords := 0
	for s: Dictionary in WorldGen.settlements:
		if PD.is_seat(String(s.get("kind", "village"))) and lords < NOBLE_LORDS:
			keys.append("lord:%d" % int(s["id"]))
			lords += 1
	return keys


## Annual mortality of a title holder, by age (a harsher table than the commoners': campaigns, fevers, poison).
static func annual_risk(age: int) -> float:
	return 0.015 + 0.0008 * pow(maxf(0.0, float(age - 35)), 1.5)


func watch_nobles() -> int:
	var su: Variant = _mod("succession")
	if su == null:
		return 0
	su.warm()
	for key: String in _noble_keys():
		if not _nob.has(key):
			var t: Dictionary = su.title(key)
			if t.is_empty() or String(t["holder"]) == "":
				continue
			_nob[key] = {"house": String(su.person(String(t["holder"])).get("house", key))}
	return _nob.size()


func noble_count() -> int:
	return _nob.size()


func _week_nobles(week: int) -> void:
	var su: Variant = _mod("succession")
	if su == null:
		return
	if _nob.is_empty():
		watch_nobles()
	var keys: Array = _nob.keys()
	keys.sort()
	for key: String in keys:
		var hid: String = su.holder(key)
		if hid == "":
			continue
		var age: int = su.age_of(hid)
		# The long-lived peoples (the Veyl of the wood, the deep thrones, the Shenlu sects) age slowly: their ages are scaled to a human span.
		var span: float = float(LIFE_SCALE.get(key.trim_prefix("crown:"), 1.0)) if key.begins_with("crown:") else 1.0
		var p := annual_risk(int(float(age) / span)) / 52.0
		var em: Variant = _mod("emergence")
		if em != null:
			p *= float(em.mortality_mult(-1))
		if float(absi(hash([WorldSim.SEED, "nobdie", key, hid, week])) % 100000) / 100000.0 < p:
			var res: Dictionary = su.die(hid, "illness" if age < 60 else "age")
			stats["noble_deaths"] = int(stats["noble_deaths"]) + 1
			stats["successions"] = int(stats["successions"]) + (res.get("titles", []) as Array).size()
			_ev("death", -1, [hid], "noble_death", "%s dies; %s passes on" % [String(su.person(hid).get("name", hid)), key], 6)
			var nw: Variant = _mod("news")
			if nw != null:
				nw.post("noble_death", PD.capital_sid(), "%s is dead." % String(su.person(hid).get("name", hid)), 2.5, "", true)


# ------------------------------------------------------------------ the player's family (family.gd)

## Copies a family.gd family (children_list / spouse) into the player's household in homes.gd.
func sync_player_family(fam: Object, player: String, sid: int) -> int:
	var hm: Variant = _mod("homes")
	if hm == null or fam == null:
		return 0
	var hid: String = hm.ensure_household(player, sid)
	if hid == "":
		return 0
	var hh: Dictionary = hm._hh[hid]
	var n := 0
	var day := _now()
	var kids: Array = fam.call("children_list", day)
	hh["kids"] = []
	for c: Dictionary in kids:
		var age := int(c.get("age", 0))
		if (hh["kids"] as Array).size() < hm.KIDS_MAX:
			(hh["kids"] as Array).append([day - age * hm.YEAR, String(c.get("sex", "m"))[0], 0, 0])
			n += 1
	if bool(fam.call("is_married")) and String(hh["sp"]) == "":
		hh["sp"] = "sp:" + player
	return n


## family.gd passed the line to an heir: the house carries on with reduced standing and feuds.
func player_succeeded(house_name: String, player: String, heir: String) -> void:
	var h := ensure_house(house_name)
	if h.is_empty():
		return
	for o: Variant in (h["feud"] as Dictionary).keys():
		var f: Array = (h["feud"] as Dictionary)[o]
		f[0] = float(f[0]) * 0.7
	h["head"] = heir if heir != "" else player
	var line: Array = h["line"]
	line.append(h["head"])
	if line.size() > LINE_MAX:
		line.pop_front()
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("h:" + house_name, "recognised", -1, 0.2)
	stats["successions"] = int(stats["successions"]) + 1


## Daily: what happened in the ring since yesterday that makes houses fall out (a price war between two shopkeepers, a killing on the road).
func _scan_rivalry() -> void:
	var ev: Variant = _mod("events")
	var bz: Variant = _mod("businesses")
	if ev == null or bz == null:
		return
	for r: Dictionary in ev.after(_last_rv):
		_last_rv = maxi(_last_rv, int(r["n"]))
		if String(r["cause"]) != "price_war" or (r["actors"] as Array).is_empty():
			continue
		var bid := String((r["actors"] as Array)[0])
		if not bid.begins_with("bz:") or not bz.exists(bid):
			continue
		var owner := String(bz.biz(bid).get("owner", ""))
		for rv: Variant in bz.rivals(bid):
			var other := String(bz.biz(String(rv)).get("owner", ""))
			var a := house_of(owner)
			var b := house_of(other)
			if a != "" and b != "" and a != b:
				open_feud(a, b, "rivalry", 28.0)
				break


func _scan_player_succession() -> void:
	var ev: Variant = _mod("events")
	if ev == null:
		return
	var reg: Variant = _mod("registry")
	var pl: String = String(reg.lookup("pl:player")) if reg != null else ""
	if pl == "":
		return
	for r: Dictionary in ev.after(_last_ev):
		_last_ev = maxi(_last_ev, int(r["n"]))
		if String(r["kind"]) == "succession" and String(r["cause"]) == "heir" and (r["actors"] as Array).has(pl):
			var nm := house_of(pl)
			if nm == "":
				nm = "player_house"
			player_succeeded(nm, pl, pl)
			return


# ------------------------------------------------------------------ ticks

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_scan_player_succession()
	_scan_rivalry()
	return []


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_week_feuds(week)
	_week_nobles(week)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	for i in mini(days / 7, 8):
		_week_feuds(_day / 7 - i)
	return []


func forget_character(ch: String) -> void:
	_kin.erase(ch)


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var hs: Dictionary = {}
	for nm: Variant in _h:
		var h: Dictionary = _h[nm]
		var fe: Dictionary = {}
		for o: Variant in h["feud"]:
			fe[o] = (h["feud"][o] as Array).duplicate()
		hs[nm] = [int(h["sid"]), String(h["head"]), (h["line"] as Array).duplicate(), fe, 1 if bool(h["noble"]) else 0, String(h["spec"]), int(h["mem"]), int(h["founded"]),
			int(h["est"])]
	return {"h": hs, "kin": _kin.duplicate(), "nob": _nob.duplicate(true), "day": _day, "le": _last_ev, "lr": _last_rv, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_h = {}
	_kin = {}
	_nob = {}
	var hs: Dictionary = d.get("h", {})
	for nm: Variant in hs:
		var a: Array = hs[nm]
		var fe: Dictionary = {}
		for o: Variant in a[3]:
			var f: Array = a[3][o]
			fe[String(o)] = [float(f[0]), String(f[1]), int(f[2])]
		var line: Array = []
		for l: Variant in a[2]:
			line.append(String(l))
		_h[String(nm)] = {"n": String(nm), "sid": int(a[0]), "head": String(a[1]), "line": line, "feud": fe, "noble": int(a[4]) == 1, "spec": String(a[5]), "mem": int(a[6]),
			"founded": int(a[7]), "est": int(a[8]), "lost": 0}
	var kin: Dictionary = d.get("kin", {})
	for k: Variant in kin:
		_kin[String(k)] = String(kin[k])
	var nob: Dictionary = d.get("nob", {})
	for k: Variant in nob:
		_nob[String(k)] = {"house": String((nob[k] as Dictionary).get("house", ""))}
	_day = int(d.get("day", 0))
	_last_ev = int(d.get("le", 0))
	_last_rv = int(d.get("lr", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
