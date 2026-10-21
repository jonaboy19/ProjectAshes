extends "res://scripts/realm/realm_module.gd"
## Emergent events (LW-8.2, docs/design/LIVING_WORLD_SANDBOX.md section 15): a director over the EventRecord ring and the state of the other
## modules. It does not script a story: it watches for conditions that systems create (a dead noble, a dissolved guild, an army marching
## away, a raised tax, a dry harvest) and for rare natural hazards (a vein of ore, a fever, a Rift waking), starts a CHAIN, and lets each
## chain spread KNOCK-ON effects over days and weeks. Each effect is a real change to another module: a road's danger (homes.gd), a wave
## of migrants (migration.gd), a town's loyalty (land.gd), an alert (armies.gd), a mortality or price multiplier that minds.gd and homes.gd
## read, a petition filed by NPCs (audiences.gd), beds used (faith.gd). Everything is announced as NEWS with a delay: the post is dated
## in the future by the herald's/rumour's lag and then travels by road distance (news.gd), so a far town learns late.
##
## Chains (kinds): mine_discovery, noble_death, harvest_failure, unsafe_road, guild_collapse, rift_activation, tax_rise, army_departure,
## epidemic, recognition.
##
## Loop control (the doc asks for 20 different chains in five years and no repeating loop): one chain per (kind, place) per COOLDOWN
## days; a chain started by another may not start a kind already in its ancestry; depth is capped at MAX_DEPTH; at most MAX_LIVE chains
## run at once and MAX_NEW start per day.
##
## Cost: events are read once a day (the ring since yesterday), hazards once a week (30 towns, a hash each), stages from a day-bucket
## queue. Saved state: live chains, the effect list (bounded), 60 history lines.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const KINDS := ["mine_discovery", "noble_death", "harvest_failure", "unsafe_road", "guild_collapse", "rift_activation", "tax_rise", "army_departure", "epidemic", "recognition"]
const COOLDOWN := 120
const MAX_DEPTH := 4
const MAX_LIVE := 24
const MAX_NEW := 2
const FX_MAX := 160
const HIST_MAX := 60
const CHAIN_KEEP := 40            # finished chains kept as counts only after this many
## Weekly hazard per town (before multipliers) of the natural chains.
const HAZARD := {"mine_discovery": 0.0016, "harvest_failure": 0.0, "rift_activation": 0.0006, "epidemic": 0.0012, "unsafe_road": 0.0022}
const GUILD_TYPES := ["craft_guild", "merchant_company", "adventurer_guild", "mercenary_company", "farmers_coop"]

var _cn: Dictionary = {}         # cid -> chain
var _due: Dictionary = {}        # day -> [[cid, stage], ...]
var _fx: Array = []              # [key, sid, value, until, cid]
var _cool: Dictionary = {}       # "kind|place" -> day until which it may not start again
var _hist: Array = []            # one line per chain started
var _seen_tax: Dictionary = {}   # sid -> last tax seen
var _seen_army: Dictionary = {}  # aid -> sid it was camped at
var _last_ev := 0
var _ec: Dictionary = {}          # effect() answers for today (cleared when an effect is added or pruned)
var _ec_day := -1
var _next := 1
var _day := 0
var _new_today := 0
var _kind_n: Dictionary = {}     # kind -> chains ever started
var stats := {"started": 0, "children": 0, "blocked_loop": 0, "blocked_cool": 0, "news": 0, "effects": 0, "finished": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ reading state

func chain(cid: int) -> Dictionary:
	return (_cn.get(cid, {}) as Dictionary).duplicate(true)


func chains(live_only := true) -> Array:
	var out: Array = []
	var ids: Array = _cn.keys()
	ids.sort()
	for k: Variant in ids:
		if not live_only or not bool((_cn[k] as Dictionary)["done"]):
			out.append(int(k))
	return out


func history() -> Array:
	return _hist.duplicate()


func started_of(kind: String) -> int:
	return int(_kind_n.get(kind, 0))


func distinct_started() -> int:
	return int(stats["started"])


func effect(sid: int, key: String) -> float:
	var d := _now()
	if _ec_day != d:
		_ec = {}
		_ec_day = d
	var ck := "%d|%s" % [sid, key]
	if _ec.has(ck):
		return float(_ec[ck])
	var v := _effect(sid, key, d)
	_ec[ck] = v
	return v


func _effect(sid: int, key: String, d: int) -> float:
	var v := 1.0 if key in ["mort", "fert", "food", "rent", "trade"] else 0.0
	var mult := key in ["mort", "fert", "food", "rent", "trade"]
	for e: Array in _fx:
		if String(e[0]) == key and (int(e[1]) == sid or int(e[1]) == -1) and int(e[3]) >= d:
			if mult:
				v *= float(e[2])
			else:
				v += float(e[2])
	return v


func mortality_mult(sid: int) -> float:
	return effect(sid, "mort")


func fertility_mult(sid: int) -> float:
	return effect(sid, "fert")


func food_price_mult(sid: int) -> float:
	return effect(sid, "food")


func rent_mult(sid: int) -> float:
	return effect(sid, "rent")


func unrest_at(sid: int) -> float:
	return effect(sid, "unrest")


func danger_at(sid: int) -> float:
	return effect(sid, "danger")


## What is going on in a town, for the people who live there (they feel it without being told): {kind: severity}
func local(sid: int) -> Dictionary:
	var out := {}
	for k: Variant in _cn:
		var c: Dictionary = _cn[k]
		if not bool(c["done"]) and int(c["sid"]) == sid:
			out[String(c["k"])] = int(c["stage"]) + 1
	return out


# ------------------------------------------------------------------ writing

func _add_fx(key: String, sid: int, value: float, days: int, cid: int) -> void:
	if _fx.size() >= FX_MAX:
		_prune_fx()
		if _fx.size() >= FX_MAX:
			_fx.pop_front()
	_fx.append([key, sid, snappedf(value, 0.001), _now() + days, cid])
	_ec_day = -1
	stats["effects"] = int(stats["effects"]) + 1


func _prune_fx() -> void:
	var d := _now()
	_fx = _fx.filter(func(e: Array) -> bool: return int(e[3]) >= d)
	_ec_day = -1


func _news(kind: String, sid: int, text: String, mag: float, delay: int, official := false) -> void:
	var nw: Variant = _mod("news")
	if nw == null:
		return
	nw.post(kind, sid, text, mag, "", official, _now() + delay)
	stats["news"] = int(stats["news"]) + 1


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 3) -> void:
	Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, w)


func _plan(cid: int, stage: int, in_days: int) -> void:
	var d := _now() + maxi(1, in_days)                    # never today: the day tick has already run when a weekly scan starts a chain
	if not _due.has(d):
		_due[d] = []
	(_due[d] as Array).append([cid, stage])


## Start a chain. `parent` is a chain id whose ancestry must not already hold `kind`. Returns the chain id or 0.
func start(kind: String, sid: int, opts: Dictionary = {}) -> int:
	if not (kind in KINDS):
		return 0
	var parent := int(opts.get("parent", 0))
	var place := str(opts.get("place", sid))
	var anc: Array = []
	var depth := 0
	if parent > 0 and _cn.has(parent):
		anc = ((_cn[parent] as Dictionary)["anc"] as Array).duplicate()
		anc.append("%s|%s" % [String((_cn[parent] as Dictionary)["k"]), str((_cn[parent] as Dictionary)["place"])])
		depth = int((_cn[parent] as Dictionary)["depth"]) + 1
	# A knock-on may repeat a kind elsewhere (a fever spreading) but never the same kind in the same place down one line of causes.
	if ("%s|%s" % [kind, place]) in anc or depth > MAX_DEPTH:
		stats["blocked_loop"] = int(stats["blocked_loop"]) + 1
		return 0
	var ck := "%s|%s" % [kind, place]
	if int(_cool.get(ck, -1)) > _now():
		stats["blocked_cool"] = int(stats["blocked_cool"]) + 1
		return 0
	if chains(true).size() >= MAX_LIVE or (_new_today >= MAX_NEW and parent == 0):
		return 0
	var cid := _next
	_next += 1
	_cool[ck] = _now() + COOLDOWN
	_cn[cid] = {"k": kind, "sid": sid, "place": place, "d0": _now(), "stage": 0, "par": parent, "anc": anc, "depth": depth, "done": false,
		"data": (opts.get("data", {}) as Dictionary).duplicate(true)}
	if parent == 0:
		_new_today += 1
	stats["started"] = int(stats["started"]) + 1
	if parent > 0:
		stats["children"] = int(stats["children"]) + 1
	_kind_n[kind] = int(_kind_n.get(kind, 0)) + 1
	_hist.append("d%d %s@%s%s" % [_now(), kind, place, " <%d" % parent if parent > 0 else ""])
	if _hist.size() > HIST_MAX:
		_hist.pop_front()
	_plan(cid, 0, 0)
	return cid


func _child(parent: int, kind: String, sid: int, in_days: int, opts: Dictionary = {}) -> void:
	# A knock-on is started later, when its time comes (the stage runner calls start with the parent).
	var c: Dictionary = _cn.get(parent, {})
	if c.is_empty():
		return
	var ch: Array = c["data"].get("kids", [])
	ch.append([kind, sid, _now() + in_days, opts])
	c["data"]["kids"] = ch
	_plan(parent, 90 + ch.size() - 1, in_days)


func _finish(cid: int) -> void:
	var c: Dictionary = _cn.get(cid, {})
	if c.is_empty():
		return
	c["done"] = true
	stats["finished"] = int(stats["finished"]) + 1


func _nearest(sid: int, n: int) -> Array:
	var nw: Variant = _mod("news")
	var rows: Array = []
	for s: Dictionary in WorldGen.settlements:
		var t := int(s["id"])
		if t == sid:
			continue
		var d := float(nw.road_distance(sid, t)) if nw != null else 1000.0
		if d < 1.0e8:
			rows.append([d, t])
	rows.sort()
	var out: Array = []
	for i in mini(n, rows.size()):
		out.append(int((rows[i] as Array)[1]))
	return out


func _hm() -> Variant:
	return _mod("homes")


func _wave(from_sid: int, to_sid: int, n: int, kind: String, cause: String) -> bool:
	var mg: Variant = _mod("migration")
	if mg == null:
		return false
	var w: Dictionary = mg.send_wave("s%d" % from_sid if from_sid >= 0 else "", "s%d" % to_sid, n, kind, cause)
	return not w.is_empty()


func _petition(sid: int, ptype: String, who_name: String) -> bool:
	var au: Variant = _mod("audiences")
	if au == null:
		return false
	var by := {"id": "emerge:%d" % sid, "name": who_name, "kind": "npc", "fame": 4.0, "rank": 1, "sponsors": []}
	var r: Dictionary = au.file(ptype, sid, by, {}, {"npc": true, "proxy": true})
	return bool(r.get("ok", false))


# ------------------------------------------------------------------ the chains (one stage at a time)

func _run(cid: int, stage: int) -> void:
	var c: Dictionary = _cn.get(cid, {})
	if c.is_empty():
		return
	if stage >= 90:
		var kids: Array = c["data"].get("kids", [])
		var i := stage - 90
		if i < kids.size():
			var k: Array = kids[i]
			start(String(k[0]), int(k[1]), (k[3] as Dictionary).merged({"parent": cid}))
		return
	if bool(c["done"]):
		return
	c["stage"] = stage
	var sid := int(c["sid"])
	var name := PD.sname(sid) if sid >= 0 else "the realm"
	match String(c["k"]):
		"mine_discovery": _mine(cid, c, stage, sid, name)
		"noble_death": _noble(cid, c, stage, sid, name)
		"harvest_failure": _harvest(cid, c, stage, sid, name)
		"unsafe_road": _road(cid, c, stage, sid, name)
		"guild_collapse": _guild(cid, c, stage, sid, name)
		"rift_activation": _rift(cid, c, stage, sid, name)
		"tax_rise": _tax(cid, c, stage, sid, name)
		"army_departure": _army(cid, c, stage, sid, name)
		"epidemic": _epidemic(cid, c, stage, sid, name)
		"recognition": _recognition(cid, c, stage, sid, name)


func _mine(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_ev("trade", sid, [], "mine_discovery", "Ore is found near %s" % name, 5)
			_news("mine", sid, "A rich vein of ore is found near %s." % name, 2.0, 5)
			_add_fx("trade", sid, 1.12, 80, cid)
			_plan(cid, 1, 7)
		1:
			var from := int(_nearest(sid, 3).back()) if not _nearest(sid, 3).is_empty() else -1
			var ok := _wave(from, sid, 14 + absi(hash([WorldSim.SEED, "mw", cid])) % 14, "settlers", "ore rush")
			_news("migration", sid, "Fortune-seekers pour into %s." % name, 1.2, 2)
			_add_fx("rent", sid, 1.25, 90, cid)
			_plan(cid, 2, 14 if ok else 10)
		2:
			var hm: Variant = _hm()
			if hm != null:
				for t in _nearest(sid, 2):
					hm.set_road_mod(sid, t, 0.12, _now() + 60)
			_ev("trade", sid, [], "ore_rush", "%s is crowded and rents climb" % name, 3)
			_child(cid, "tax_rise", sid, 12)
			_child(cid, "unsafe_road", sid, 20, {"data": {"to": (_nearest(sid, 1)[0] if not _nearest(sid, 1).is_empty() else -1)}})
			_plan(cid, 3, 30)
		3:
			_finish(cid)


func _noble(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_news("noble_death", sid, "A great lord of %s is dead, and the succession is awaited." % name, 2.4, 2, true)
			_add_fx("unrest", sid, 0.08, 30, cid)
			_plan(cid, 1, 10)
		1:
			var su: Variant = _mod("succession")
			var disputed := su != null and not (su.disputes(true) as Array).is_empty()
			_ev("succession", sid, [], "noble_aftermath", "%s waits on its new lord%s" % [name, " amid a dispute" if disputed else ""], 4)
			if disputed:
				_add_fx("unrest", sid, 0.15, 40, cid)
				_child(cid, "army_departure", sid, 6)
			var lm: Variant = _mod("land")
			if lm != null:
				lm.adjust_loyalty(sid, -5.0 if disputed else -2.0)
			_plan(cid, 2, 25)
		2:
			_finish(cid)


func _harvest(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_ev("emergency", sid, [], "harvest_failure", "The harvest fails around %s" % name, 5)
			_news("harvest", sid, "The harvest has failed around %s; grain will be dear." % name, 2.0, 3)
			_add_fx("food", sid, 1.6, 120, cid)
			_add_fx("mort", sid, 1.25, 90, cid)
			_plan(cid, 1, 6)
		1:
			var fa: Variant = _mod("faith")
			var beds := 0
			if fa != null:
				beds = int(fa.shelter_take(sid, 10))
			if beds > 0:
				_add_fx("mort", sid, 0.9, 60, cid)
			_petition(sid, "tax_relief", "The farmers of %s" % name)
			var lm: Variant = _mod("land")
			if lm != null:
				lm.adjust_loyalty(sid, -6.0)
			_plan(cid, 2, 14)
		2:
			var near := _nearest(sid, 4)
			if not near.is_empty():
				_wave(sid, int(near[0]), 8 + absi(hash([WorldSim.SEED, "hw", cid])) % 10, "refugees", "hunger")
			_news("migration", sid, "Hungry families leave %s." % name, 1.2, 3)
			_child(cid, "unsafe_road", sid, 5, {"data": {"to": (near[0] if not near.is_empty() else -1)}})
			_plan(cid, 3, 40)
		3:
			_finish(cid)


func _road(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	var to := int((c["data"] as Dictionary).get("to", -1))
	if to < 0:
		var nb := _nearest(sid, 3)
		if nb.is_empty():
			_finish(cid)
			return
		to = int(nb[absi(hash([WorldSim.SEED, "rd", cid])) % nb.size()])
		c["data"]["to"] = to
	var hm: Variant = _hm()
	match stage:
		0:
			if hm != null:
				hm.set_road_mod(sid, to, 0.4, _now() + 70)
			_ev("crime", sid, [], "unsafe_road", "Bandits take the road between %s and %s" % [name, PD.sname(to)], 4)
			_news("road", sid, "Bandits hold the road from %s to %s." % [name, PD.sname(to)], 1.8, 2)
			_plan(cid, 1, 14)
		1:
			var ar: Variant = _mod("armies")
			var patrolled := false
			if ar != null and float(ar.defence_rating(sid)) + float(ar.defence_rating(to)) > 4.0:
				patrolled = true
			if patrolled and hm != null:
				hm.set_road_mod(sid, to, 0.1, _now() + 50)
				_news("road", sid, "The patrols clear the road to %s." % PD.sname(to), 1.0, 2)
			else:
				_news("road", sid, "Travellers on the road to %s are advised to hire guards." % PD.sname(to), 1.0, 3)
			_plan(cid, 2, 40)
		2:
			_finish(cid)


func _guild(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	var gname := String((c["data"] as Dictionary).get("name", "A guild"))
	match stage:
		0:
			_news("guild", sid, "%s has closed its doors in %s." % [gname, name], 1.6, 3)
			_add_fx("unrest", sid, 0.06, 50, cid)
			_plan(cid, 1, 10)
		1:
			# Its members are out of work: the town feels it, and a rival may take the trade.
			_ev("crime", sid, [], "guild_collapse", "Idle hands in %s turn to trouble" % name, 3)
			var mn: Variant = _mod("minds")
			if mn != null:
				mn.poke_town(sid, 12)
			_plan(cid, 2, 30)
		2:
			_finish(cid)


func _rift(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_ev("emergency", sid, [], "rift_activation", "A Rift wakes near %s" % name, 7)
			_news("rift", sid, "A Rift has woken near %s." % name, 3.0, 1, true)
			_add_fx("danger", sid, 0.25, 90, cid)
			_add_fx("mort", sid, 1.3, 60, cid)
			var ar: Variant = _mod("armies")
			if ar != null:
				ar.raise_alert(sid, 2)
			var hm: Variant = _hm()
			if hm != null:
				for t in _nearest(sid, 3):
					hm.set_road_mod(sid, t, 0.3, _now() + 60)
			_plan(cid, 1, 5)
		1:
			var fa: Variant = _mod("faith")
			if fa != null:
				fa.shelter_take(sid, 8)
			var near := _nearest(sid, 2)
			if not near.is_empty():
				_wave(sid, int(near[0]), 10 + absi(hash([WorldSim.SEED, "rw", cid])) % 12, "refugees", "rift")
			_news("migration", sid, "Refugees from %s arrive on the roads." % name, 1.5, 2)
			_plan(cid, 2, 25)
		2:
			_news("rift", sid, "The Rift near %s is sealed for now." % name, 1.0, 2)
			_finish(cid)


func _tax(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_news("tax", sid, "The tax in %s is raised." % name, 1.4, 2, true)
			var lm: Variant = _mod("land")
			if lm != null:
				lm.adjust_loyalty(sid, -8.0)
			_add_fx("unrest", sid, 0.1, 50, cid)
			_plan(cid, 1, 3)
		1:
			_petition(sid, "tax_relief", "The people of %s" % name)
			_plan(cid, 2, 14)
		2:
			var near := _nearest(sid, 3)
			if not near.is_empty():
				_wave(sid, int(near[0]), 6 + absi(hash([WorldSim.SEED, "tw", cid])) % 8, "settlers", "heavy taxes")
			_news("migration", sid, "Families leave %s for lighter lords." % name, 1.0, 3)
			_plan(cid, 3, 30)
		3:
			_finish(cid)


func _army(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_news("army", sid, "The soldiers have marched out of %s." % name, 1.5, 1)
			_add_fx("danger", sid, 0.12, 35, cid)
			var hm: Variant = _hm()
			if hm != null:
				for t in _nearest(sid, 3):
					hm.set_road_mod(sid, t, 0.12, _now() + 30)
			_plan(cid, 1, 12)
		1:
			var farms: Variant = _mod("farming")
			_ev("emergency", sid, [], "army_away", "%s keeps watch with fewer men" % name, 3)
			if absi(hash([WorldSim.SEED, "raid", cid])) % 100 < 30:
				_child(cid, "unsafe_road", sid, 3)
			_plan(cid, 2, 25)
			if farms == null:
				pass
		2:
			_news("army", sid, "The soldiers are back in %s." % name, 1.0, 1)
			_finish(cid)


func _epidemic(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	var sev := float((c["data"] as Dictionary).get("sev", 1.0))
	match stage:
		0:
			_ev("emergency", sid, [], "epidemic", "A fever breaks out in %s" % name, 6)
			_news("plague", sid, "A fever is killing people in %s." % name, 2.6, 2)
			_add_fx("mort", sid, 1.0 + 0.9 * sev, 70, cid)
			_add_fx("fert", sid, 0.6, 90, cid)
			_add_fx("trade", sid, 0.85, 60, cid)
			_plan(cid, 1, 8)
		1:
			var fa: Variant = _mod("faith")
			var beds := int(fa.shelter_take(sid, 12)) if fa != null else 0
			if beds > 0:
				_add_fx("mort", sid, 0.85, 50, cid)
			# It travels with the traffic: the nearest towns may catch it.
			for t in _nearest(sid, 2):
				if absi(hash([WorldSim.SEED, "spread", cid, t])) % 100 < 35:
					_child(cid, "epidemic", t, 6, {"data": {"sev": sev * 0.7}, "place": t})
			_plan(cid, 2, 30)
		2:
			_news("plague", sid, "The fever has passed in %s." % name, 1.0, 1)
			if absi(hash([WorldSim.SEED, "labour", cid])) % 100 < 25:
				_child(cid, "harvest_failure", sid, 10)
			_finish(cid)


func _recognition(cid: int, c: Dictionary, stage: int, sid: int, name: String) -> void:
	match stage:
		0:
			_news("recognition", sid, "The crown has recognised %s." % String((c["data"] as Dictionary).get("who", name)), 2.0, 2, true)
			var lm: Variant = _mod("land")
			if lm != null and sid >= 0:
				lm.adjust_loyalty(sid, 6.0)
			_add_fx("trade", sid, 1.08, 60, cid)
			_plan(cid, 1, 10)
		1:
			var near := _nearest(sid, 2)
			if not near.is_empty():
				_wave(int(near[0]), sid, 8 + absi(hash([WorldSim.SEED, "rec", cid])) % 8, "settlers", "better prospects")
			_news("migration", sid, "Settlers hear that %s is favoured and head there." % name, 1.0, 4)
			_plan(cid, 2, 30)
		2:
			_finish(cid)


# ------------------------------------------------------------------ triggers

func _scan_events() -> void:
	var ev: Variant = _mod("events")
	if ev == null:
		return
	var rows: Array = ev.after(_last_ev)
	var reg: Variant = _mod("registry")
	for r: Dictionary in rows:
		var n := int(r["n"])
		if n <= _last_ev:
			continue
		_last_ev = maxi(_last_ev, n)
		var cause := String(r["cause"])
		var kind := String(r["kind"])
		var sid := _sid_of(String(r["where"]), reg)
		if cause == "noble_death":
			start("noble_death", sid if sid >= 0 else PD.capital_sid())
		elif kind == "founding" and cause == "dissolved" and int(r["weight"]) >= 3:
			var om: Variant = _mod("organizations")
			for a: Variant in r["actors"]:
				var oid := String(a)
				if om != null and oid.begins_with("org:") and om.exists(oid) and String(om.org(oid).get("type", "")) in GUILD_TYPES \
						and int(om.org(oid).get("stage", 0)) >= 2 and int(om.org(oid).get("end", 0)) - int(om.org(oid).get("born", 0)) >= 40:
					var gs := int(om.org(oid).get("sid", sid))
					start("guild_collapse", gs, {"data": {"name": String(om.org(oid).get("name", "A guild"))}, "place": oid})
					break
		elif cause == "recognised" and kind == "military":
			start("recognition", sid if sid >= 0 else PD.capital_sid(), {"data": {"who": String(r["outcome"]).substr(0, 40)}})


func _sid_of(where: String, reg: Variant) -> int:
	if where == "":
		return -1
	if where.begins_with("ss:"):
		return int(where.substr(3))
	if reg != null:
		var lg: String = reg.legacy_of(where)
		if lg.begins_with("ss:"):
			return int(lg.substr(3))
	return -1


func _scan_state(week: int) -> void:
	# Tax levels: a rise of two points or more is a chain.
	var gv: Variant = _mod("governance")
	if gv != null:
		for s: Dictionary in WorldGen.settlements:
			var sid := int(s["id"])
			var t := float(gv.tax(sid))
			if _seen_tax.has(sid) and t >= float(_seen_tax[sid]) + 0.02:
				start("tax_rise", sid)
			_seen_tax[sid] = t
	# Armies that were camped and now march.
	var ar: Variant = _mod("armies")
	if ar != null:
		for aid: Variant in ar.ids():
			var a: Dictionary = ar.army(String(aid))
			if a.is_empty():
				continue
			var at := int(a.get("sid", -1))
			if String(a.get("state", "")) == "marching" and _seen_army.has(aid) and at >= 0:
				start("army_departure", at, {"place": String(aid)})
				_seen_army.erase(aid)
			elif String(a.get("state", "")) == "camped" and at >= 0:
				_seen_army[aid] = at
		if _seen_army.size() > 80:
			_seen_army = {}


func _hazards(week: int) -> void:
	var season := (posmod(_now(), 360)) / 90        # 0 spring, 1 summer, 2 autumn, 3 winter
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var pop := int(s.get("population", 200))
		for k: String in HAZARD:
			var p := float(HAZARD[k])
			if k == "epidemic":
				p *= 0.6 + float(pop) / 600.0
				p *= 1.6 if season == 3 else 1.0
			if k == "unsafe_road":
				p *= 1.0 + 0.5 * effect(sid, "unrest")
			if p <= 0.0:
				continue
			if float(absi(hash([WorldSim.SEED, "em", k, week, sid])) % 1000000) / 1000000.0 < p:
				var opts := {}
				if k == "epidemic":
					opts["data"] = {"sev": 0.6 + float(absi(hash([WorldSim.SEED, "sev", week, sid])) % 100) / 100.0}
				start(k, sid, opts)
		# The dry harvest: judged once a year, at the end of autumn, from a hash weighted by how much grain the town's farms have.
		if posmod(_now(), 360) / 7 == 262 / 7 and week > 0:
			var bad := 0.06
			var fm: Variant = _mod("farming")
			if fm != null and (fm.parcels() as Array).size() > 0:
				bad = 0.1
			if float(absi(hash([WorldSim.SEED, "harv", week / 52, sid])) % 1000) / 1000.0 < bad:
				start("harvest_failure", sid)


# ------------------------------------------------------------------ ticks

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_new_today = 0
	_scan_events()
	var list: Array = _due.get(day, [])
	_due.erase(day)
	for e: Array in list:
		_run(int(e[0]), int(e[1]))
	return []


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_scan_state(week)
	_hazards(week)
	_prune_fx()
	# Old finished chains fold into the history lines.
	var done: Array = []
	for k: Variant in _cn:
		if bool((_cn[k] as Dictionary)["done"]) and _now() - int((_cn[k] as Dictionary)["d0"]) > 150:
			done.append(k)
	if _cn.size() > CHAIN_KEEP:
		for k: Variant in done:
			_cn.erase(k)
	for ck: Variant in _cool.keys():
		if int(_cool[ck]) < _now():
			_cool.erase(ck)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Everything that was due has happened by now, in order (stages that plan further stages are followed until none falls inside the sleep).
	var target := maxi(_day, PD.today()) + days
	var saved := _day
	while true:
		var next := 1 << 30
		for d: Variant in _due:
			next = mini(next, int(d))
		if next > target:
			break
		_day = next
		var list: Array = _due.get(next, [])
		_due.erase(next)
		for e: Array in list:
			_run(int(e[0]), int(e[1]))
	_day = maxi(saved, target)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var cn: Dictionary = {}
	for k: Variant in _cn:
		var c: Dictionary = _cn[k]
		cn[str(k)] = [String(c["k"]), int(c["sid"]), int(c["d0"]), int(c["stage"]), int(c["par"]), (c["anc"] as Array).duplicate(), int(c["depth"]), 1 if bool(c["done"]) else 0,
			(c["data"] as Dictionary).duplicate(true), str(c["place"])]
	var due: Dictionary = {}
	for d: Variant in _due:
		due[str(d)] = _due[d]
	return {"cn": cn, "due": due, "fx": _fx.duplicate(true), "cool": _cool.duplicate(), "hist": _hist.duplicate(), "tax": _seen_tax.duplicate(), "kn": _kind_n.duplicate(),
		"le": _last_ev, "n": _next, "day": _day, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_cn = {}
	_due = {}
	_fx = []
	_ec_day = -1
	_cool = {}
	_hist = []
	_seen_tax = {}
	_seen_army = {}
	_kind_n = {}
	var cn: Dictionary = d.get("cn", {})
	for k: Variant in cn:
		var a: Array = cn[k]
		var anc: Array = []
		for x: Variant in a[5]:
			anc.append(String(x))
		_cn[int(k)] = {"k": String(a[0]), "sid": int(a[1]), "d0": int(a[2]), "stage": int(a[3]), "par": int(a[4]), "anc": anc, "depth": int(a[6]), "done": int(a[7]) == 1,
			"data": _fix_data((a[8] as Dictionary).duplicate(true)), "place": String(a[9])}
	var due: Dictionary = d.get("due", {})
	for k: Variant in due:
		var rows: Array = []
		for p: Variant in due[k]:
			rows.append([int((p as Array)[0]), int((p as Array)[1])])
		_due[int(k)] = rows
	for e: Variant in d.get("fx", []):
		var a2: Array = e
		_fx.append([String(a2[0]), int(a2[1]), float(a2[2]), int(a2[3]), int(a2[4])])
	var cool: Dictionary = d.get("cool", {})
	for k: Variant in cool:
		_cool[String(k)] = int(cool[k])
	for h: Variant in d.get("hist", []):
		_hist.append(String(h))
	var tax: Dictionary = d.get("tax", {})
	for k: Variant in tax:
		_seen_tax[int(k)] = float(tax[k])
	var kn: Dictionary = d.get("kn", {})
	for k: Variant in kn:
		_kind_n[String(k)] = int(kn[k])
	_last_ev = int(d.get("le", 0))
	_next = int(d.get("n", 1))
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))


## JSON turns the integers inside a chain's data into floats: put them back.
func _fix_data(data: Dictionary) -> Dictionary:
	if data.has("to"):
		data["to"] = int(data["to"])
	if data.has("kids"):
		var kids: Array = []
		for k: Variant in data["kids"]:
			var a: Array = k
			var o: Dictionary = (a[3] as Dictionary).duplicate(true)
			if o.has("place") and (o["place"] is float or o["place"] is int):
				o["place"] = int(o["place"])
			if o.has("data") and (o["data"] as Dictionary).has("to"):
				o["data"]["to"] = int(o["data"]["to"])
			kids.append([String(a[0]), int(a[1]), int(a[2]), o])
		data["kids"] = kids
	return data
