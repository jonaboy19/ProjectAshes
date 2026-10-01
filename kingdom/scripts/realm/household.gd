extends "res://scripts/realm/realm_module.gd"
## Household (docs/design/CHILDHOOD_ACADEMIES.md C§1, C§18-19, C§39-43; ACADEMY_PLAN.md P1).
##
## The player's family is a small economy with two autonomous parents: jobs, food,
## tax, house repairs, debt, bad harvests, injuries and illness. When a child's
## schooling strains the budget the parents sacrifice on their own (a second job,
## a sold tool, a loan, skipped meals) without telling the player; the player
## finds out through clues that are society facts (society.learn).
##
## Family travel is exposed to the world sim (war, unrest, raids, road risk, the
## campaign map). A raid can separate the family: the child can be taken far away
## (captured -> transported -> sold/held -> forced labour) and can escape or be
## rescued; the parents can be taken instead. Searching for missing family is
## optional and has no quest marker: only leads (society facts with vague text).
## Parents have no plot armour but die only from believable causes with a chain.
##
## Pure data, deterministic (hash([WorldSim.SEED, tag, day, id])), JSON-safe.
## Money rule: never touches the purse; pending_gold is the signed ledger and
## Life calls take_pending_gold().

const REGION := "caldrenn"
const TRAVEL_SPEED := 60.0             # metres per hour with a cart (40 before the 12 km world; x1.5)
const STAY_HOURS := 36
const ENCOUNTER_TIMEOUT_H := 2
const TAX_EVERY := 30
const HOUSE_REPAIR_AT := 0.4
const REPAIR_COST := 25.0
const DEBT_RATE_WEEK := 0.02
const DEBT_CAP := 120.0
const CLUES_NEEDED := 2
const SYL_A := ["Al", "Bre", "Cor", "Dar", "El", "Fen", "Gil", "Har", "Ise", "Jor", "Kel", "Lor", "Mar", "Nor", "Ori", "Pel", "Ren", "Sel", "Tor", "Ulf"]
const SYL_B := ["ric", "na", "dan", "wen", "mund", "la", "gar", "ith", "os", "ra", "vin", "el", "bert", "ly"]
const SURN := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]

## job -> weekly wage (gold), daily accident hazard, tags
const JOBS := {
	"farmer": {"wage": 15, "hazard": 0.0002, "farm": true}, "farmhand": {"wage": 11, "hazard": 0.0003, "farm": true},
	"woodcutter": {"wage": 14, "hazard": 0.0007, "farm": false}, "miller": {"wage": 16, "hazard": 0.0003, "farm": false},
	"weaver": {"wage": 14, "hazard": 0.0001, "farm": false}, "shepherd": {"wage": 12, "hazard": 0.0003, "farm": false},
	"fisher": {"wage": 13, "hazard": 0.0006, "farm": false}, "smith": {"wage": 20, "hazard": 0.0006, "farm": false},
	"hunter": {"wage": 14, "hazard": 0.0008, "farm": false}, "baker": {"wage": 16, "hazard": 0.0002, "farm": false},
	"carter": {"wage": 15, "hazard": 0.0004, "farm": false}, "tanner": {"wage": 15, "hazard": 0.0003, "farm": false},
	"mason": {"wage": 19, "hazard": 0.0007, "farm": false}, "guard": {"wage": 18, "hazard": 0.0008, "farm": false},
	"miner": {"wage": 20, "hazard": 0.0012, "farm": false}, "laundress": {"wage": 11, "hazard": 0.0001, "farm": false},
	"washerwoman": {"wage": 10, "hazard": 0.0001, "farm": false}, "servant": {"wage": 12, "hazard": 0.0001, "farm": false},
	"militia": {"wage": 12, "hazard": 0.0015, "farm": false},
}
const KIND_JOBS := {
	"village": ["farmer", "farmer", "farmhand", "woodcutter", "miller", "weaver", "shepherd", "fisher", "smith", "hunter"],
	"town": ["baker", "weaver", "smith", "carter", "tanner", "mason", "laundress", "servant"],
	"castle": ["mason", "smith", "servant", "baker", "guard", "carter"],
	"frontier_town": ["woodcutter", "guard", "hunter", "miner", "smith", "farmhand"],
}
const PARENT_ITEMS := ["father's good axe", "mother's silver brooch", "the family's second cow", "grandfather's sword", "the good winter cloak"]
const SACRIFICE_KINDS := ["extra_job", "sell_item", "borrow", "skip_meals"]
const CLUE_TEXT := {
	"extra_job": ["The parent has been coming home long after dark, smelling of another trade.", "The parent falls asleep at the table, too tired to eat.",
		"You see the parent working a second job you were never told about."],
	"sell_item": ["A familiar thing is missing from its place on the wall.", "There is a pawnbroker's ticket in a coat pocket.",
		"A neighbour mentions who bought the thing you thought was still at home."],
	"borrow": ["A hard-faced stranger stopped at the door and left without a word.", "You overhear your parents arguing in low voices about 'what we owe'.",
		"The moneylender's ledger has your family's name in it."],
	"skip_meals": ["The parent's plate is always half empty.", "The parent has grown thin and says it is nothing.",
		"A neighbour says the parent gave away their own bread twice this week."],
}
const ENCOUNTERS := {
	"bandits": {"sev": 0.55, "captor": "bandit_gang", "toll": 25, "text": "Armed men step out of the trees and block the road."},
	"rebels": {"sev": 0.6, "captor": "rebels", "toll": 15, "text": "A rebel band stops the cart and questions every face."},
	"war": {"sev": 0.7, "captor": "press_gang", "toll": 0, "text": "A column of soldiers is pressing every fit hand on the road."},
	"monsters": {"sev": 0.65, "captor": "", "toll": 0, "text": "Something large and hungry has followed the cart from the treeline."},
	"road_closure": {"sev": 0.0, "captor": "", "toll": 0, "text": "A landslide has closed the road; you wait while it is cleared."},
	"criminal_group": {"sev": 0.5, "captor": "slavers", "toll": 30, "text": "A well-organised gang offers to 'escort' you through their territory."},
	"corrupt_official": {"sev": 0.2, "captor": "", "toll": 20, "text": "A toll-keeper invents a fee and will not let you pass without it."},
}
const CAPTOR_ROUTE := {
	"slavers": ["captured", "transported", "sold", "forced_labour"], "bandit_gang": ["captured", "transported", "held", "forced_labour"],
	"rebels": ["captured", "transported", "held", "forced_labour"], "press_gang": ["captured", "transported", "conscripted", "forced_labour"],
}
const STAGE_DAYS := {"captured": 2, "transported": 4, "sold": 3, "held": 14, "conscripted": 5}
const LABOUR_SITES := ["quarry", "mine", "galley", "estate fields", "workhouse", "logging camp"]
const DEATH_CAUSES := ["war", "disease", "crime", "accident", "poverty", "monster", "captivity", "old_age"]

var player: Dictionary = {"age": 4, "sid": 0, "home_sid": 0, "class": 0, "gold": 0, "fighting": 0.0, "charm": 10}
var pending_gold: int = 0
var fam: Dictionary = {}
var sacrifice_list: Array = []
var trip_state: Dictionary = {}
var trip_log: Array = []
var encounter: Dictionary = {}
var captive: Dictionary = {}          # parents taken: {who:[roles], captor, stage, ...}
var displaced_state: Dictionary = {}  # player taken/far from home
var leads_state: Dictionary = {}      # discovered leads keyed by fact
var death_log: Array = []
var _next_id := 1
var _day := 0
var _hour := 8
var _at_war := false
var _season := "spring"
var _season_seen := ""
var _student_support := 0.0
var _inited := false


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


func _new_id(prefix: String) -> String:
	var s := "%s%d" % [prefix, _next_id]
	_next_id += 1
	return s


func _soc() -> RefCounted:
	if hub != null:
		return hub.mod("society")
	return null


func _edu() -> RefCounted:
	if hub != null:
		return hub.mod("education")
	return null


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _skind(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["kind"])
	return "village"


func _person(r: RandomNumberGenerator, surname: String) -> String:
	return "%s%s %s" % [_pick(r, SYL_A), _pick(r, SYL_B), surname]


func set_player(d: Dictionary) -> void:
	for k: String in d:
		player[k] = d[k]
	if d.has("home_sid"):
		player["_home_set"] = true


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func _gold() -> int:
	return int(player.get("gold", 0)) + pending_gold


func _sync(ctx: Dictionary) -> void:
	_at_war = bool(ctx.get("at_war", false))
	_season = String(ctx.get("season", _season))
	if ctx.has("gold"):
		player["gold"] = int(ctx["gold"])
	if ctx.get("stats") is Dictionary:
		for k: String in ctx["stats"]:
			player[k] = ctx["stats"][k]
	if ctx.has("age"):
		player["age"] = int(ctx["age"])
	var life: Variant = ctx.get("life")
	if life != null and life is Object:
		if not ctx.has("age") and (life as Object).has_method("age"):
			player["age"] = int((life as Object).call("age"))
		var lp: Variant = (life as Object).get("life_path")
		if lp != null and lp is Object and not bool(player.get("_home_set", false)):
			var hs: Variant = (lp as Object).get("home_settlement")
			if hs != null:
				player["home_sid"] = int(hs)
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		var n := _nearest(p2)
		if n >= 0:
			player["sid"] = n


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = (s["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = int(s["id"])
	if best >= 0 and bd > pow(float(WorldGen.settlements[best].get("radius", 100.0)) * 2.5, 2.0):
		return -1
	return best


func _dist(a: int, b: int) -> float:
	if a < 0 or b < 0 or a >= WorldGen.settlements.size() or b >= WorldGen.settlements.size():
		return 2000.0
	return (WorldGen.settlements[a]["pos"] as Vector2).distance_to(WorldGen.settlements[b]["pos"])


func _fighting() -> float:
	var e := _edu()
	if e != null and e.has_method("fighting_ability"):
		return maxf(float(player.get("fighting", 0.0)), float(e.call("fighting_ability")))
	return float(player.get("fighting", 0.0))


func _unrest(sid: int) -> float:
	if hub != null:
		var l: RefCounted = hub.mod("land")
		if l != null and l.has_method("unrest"):
			return float(l.call("unrest", sid))
	return 0.0


func _emergency(sid: int, kinds: Array) -> bool:
	if hub != null:
		var sm: RefCounted = hub.mod("settlements")
		if sm != null and sm.has_method("emergencies"):
			for e: Dictionary in sm.call("emergencies", sid):
				if String(e.get("kind", "")) in kinds:
					return true
	return false


# ---------------------------------------------------------------- family (C§1)

func _ensure() -> void:
	if _inited:
		return
	_inited = true
	_build_family()


func _build_family() -> void:
	var sid := int(player["home_sid"])
	var r := _rng("family", 0, sid)
	var surname: String = String(_pick(r, SURN))
	var kind := _skind(sid)
	var jobs: Array = KIND_JOBS.get(kind, KIND_JOBS["village"])
	var parents: Array = []
	for role: String in ["father", "mother"]:
		var jn: String = String(_pick(r, jobs))
		if role == "mother" and r.randf() < 0.4:
			jn = "weaver" if kind != "village" else "farmhand"
		var jd: Dictionary = JOBS[jn]
		var abirth := 22 + r.randi() % 19
		parents.append({"id": role, "name": _person(r, surname), "age_at_birth": abirth, "job": jn, "wage": int(jd["wage"]),
			"health": snappedf(0.85 + r.randf() * 0.15, 0.01), "status": "home", "alive": true, "pride": snappedf(r.randf(), 0.01),
			"love": snappedf(0.6 + r.randf() * 0.4, 0.01), "extra_job": false, "skipping": false, "injured_until": -1, "ill_until": -1,
			"illness": "", "cause": "", "chain": [], "trauma": 0.0})
	fam = {"sid": sid, "surname": surname, "parents": parents, "savings": 20.0 + r.randf() * 25.0, "debt": {"amount": 0.0, "creditor": "", "since": -1},
		"house": 0.85, "tax_owed": 0.0, "tax_arrears": 0.0, "next_tax": TAX_EVERY, "bad_harvest_until": -1, "strain": 0.0, "sold": [], "income_day": 0.0,
		"food_days": 6.0, "weeks": 0, "orphan": false, "guardian": "", "repairs_pending": false}


func family() -> Dictionary:
	_ensure()
	return fam.duplicate(true)


func parents() -> Array:
	_ensure()
	return (fam["parents"] as Array).duplicate(true)


func parent(role: String) -> Dictionary:
	_ensure()
	for p: Dictionary in fam["parents"]:
		if String(p["id"]) == role:
			return p.duplicate(true)
	return {}


func _parent(role: String) -> Dictionary:
	for p: Dictionary in fam["parents"]:
		if String(p["id"]) == role:
			return p
	return {}


func _alive() -> Array:
	var out: Array = []
	for p: Dictionary in fam["parents"]:
		if bool(p["alive"]):
			out.append(p)
	return out


func parent_age(role: String) -> int:
	_ensure()
	var p := _parent(role)
	return int(p.get("age_at_birth", 30)) + int(player["age"])


func money() -> Dictionary:
	_ensure()
	var d: Dictionary = fam["debt"]
	return {"savings": snappedf(float(fam["savings"]), 0.1), "debt": snappedf(float(d["amount"]), 0.1), "creditor": d["creditor"], "tax_arrears": snappedf(float(fam["tax_arrears"]), 0.1),
		"income_week": snappedf(_income_day() * 7.0, 0.1), "expense_week": snappedf(_expense_day() * 7.0, 0.1), "house": snappedf(float(fam["house"]), 0.01),
		"strain": snappedf(float(fam["strain"]), 0.01), "bad_harvest": int(fam["bad_harvest_until"]) > _day, "food_days": snappedf(float(fam["food_days"]), 0.1)}


func _eff(p: Dictionary) -> float:
	if not bool(p["alive"]) or String(p["status"]) != "home":
		return 0.0
	if int(p["injured_until"]) > _day or int(p["ill_until"]) > _day:
		return 0.0
	return clampf(float(p["health"]) + 0.15, 0.2, 1.0)


func _income_day() -> float:
	var t := 0.0
	var bad := int(fam["bad_harvest_until"]) > _day
	for p: Dictionary in fam["parents"]:
		var w := float(p["wage"])
		if bad and bool(JOBS[String(p["job"])]["farm"]):
			w *= 0.5
		t += w / 7.0 * _eff(p)
		if bool(p["extra_job"]) and _eff(p) > 0.0:
			t += 12.0 / 7.0
	return t


func _mouths() -> int:
	var n := 1
	for p: Dictionary in fam["parents"]:
		if bool(p["alive"]) and String(p["status"]) in ["home", "travelling"]:
			n += 1
	if String(player_status()) == "displaced":
		n -= 1
	return maxi(1, n)


func _expense_day() -> float:
	var price := 1.6 if int(fam["bad_harvest_until"]) > _day else 1.0
	var skip := 0.0
	for p: Dictionary in fam["parents"]:
		if bool(p["skipping"]) and bool(p["alive"]):
			skip += 0.15
	return 0.85 * float(_mouths()) * price * (1.0 - minf(0.3, skip)) + tax_rate_day() + (0.3 if bool(fam["repairs_pending"]) else 0.1)


func tax_rate_day() -> float:
	var t := 0.5
	if hub != null:
		var l: RefCounted = hub.mod("land")
		if l != null and l.has_method("memories"):
			for m: Dictionary in l.call("memories", int(fam["sid"])):
				if String(m.get("kind", "")) == "tax_burden":
					t *= 1.3
	if _at_war:
		t *= 1.2
	return t


# ---------------------------------------------------------------- support for a child's schooling (C§18, C§19)

## Parents cover part of a student's shortfall on their own. Returns the gold covered.
func support_student(shortfall: float) -> float:
	_ensure()
	if shortfall <= 0.0 or _alive().is_empty() or String(player_status()) == "displaced":
		return 0.0
	var love := 0.0
	for p: Dictionary in _alive():
		love = maxf(love, float(p["love"]))
	var d: Dictionary = fam["debt"]
	var cap := float(fam["savings"]) * 0.6 * love
	var headroom := maxf(0.0, DEBT_CAP - float(d["amount"]))
	var covered := minf(shortfall, cap)
	fam["savings"] = float(fam["savings"]) - covered
	var rest := shortfall - covered
	if rest > 0.0 and headroom > 0.0 and love > 0.7:
		var loan := minf(rest * 0.5, headroom)
		d["amount"] = float(d["amount"]) + loan
		if String(d["creditor"]) == "":
			d["creditor"] = "the moneylender"
			d["since"] = _day
		covered += loan
		if loan > 0.0:
			_ensure_sacrifice("borrow", false)
	_student_support += covered
	return covered


# ---------------------------------------------------------------- sacrifice and clues (C§19)

func sacrifices(known_only := false) -> Array:
	var out: Array = []
	for s: Dictionary in sacrifice_list:
		if known_only and not bool(s["known"]):
			continue
		out.append(s.duplicate(true))
	return out


func _ensure_sacrifice(kind: String, apply_effect := true) -> void:
	for s: Dictionary in sacrifice_list:
		if String(s["kind"]) == kind and String(s["status"]) == "active":
			return
	var r := _rng("sacrifice", _day, kind)
	var alive := _alive()
	if alive.is_empty():
		return
	var pi: Dictionary = alive[r.randi() % alive.size()]
	start_sacrifice(kind, String(pi["id"]), apply_effect)


## A parent quietly starts sacrificing for the child. Returns the record.
func start_sacrifice(kind: String, role: String, apply_effect := true) -> Dictionary:
	_ensure()
	var p := _parent(role)
	if p.is_empty() or not bool(p["alive"]) or not (kind in SACRIFICE_KINDS):
		return {}
	var idx := sacrifice_list.size() + 1
	var n_clues := 3
	var facts: Array = []
	for i in n_clues:
		facts.append("clue:%s_%s_%d" % [kind, role, i + 1])
	var rec := {"id": _new_id("sac"), "kind": kind, "parent": role, "since": _day, "status": "active", "known": false, "clues": facts, "found": [], "size": 0.0, "idx": idx,
		"item": ""}
	if not apply_effect:
		sacrifice_list.append(rec)
		return rec
	match kind:
		"extra_job":
			p["extra_job"] = true
			rec["size"] = 12.0
		"sell_item":
			var item := String(PARENT_ITEMS[idx % PARENT_ITEMS.size()])
			rec["item"] = item
			(fam["sold"] as Array).append(item)
			fam["savings"] = float(fam["savings"]) + 30.0
			rec["size"] = 30.0
		"borrow":
			var d: Dictionary = fam["debt"]
			d["amount"] = float(d["amount"]) + 30.0
			if String(d["creditor"]) == "":
				d["creditor"] = "the moneylender"
				d["since"] = _day
			fam["savings"] = float(fam["savings"]) + 30.0
			rec["size"] = 30.0
		"skip_meals":
			p["skipping"] = true
			rec["size"] = 6.0
	sacrifice_list.append(rec)
	return rec


func _clue_text(rec: Dictionary, i: int) -> String:
	var t: String = String((CLUE_TEXT[String(rec["kind"])] as Array)[i])
	if String(rec["kind"]) == "sell_item" and i == 0 and String(rec["item"]) != "":
		t = "%s is gone from its place." % String(rec["item"]).capitalize()
	return t


func _reveal_clue(rec: Dictionary, out: Array) -> String:
	var found: Array = rec["found"]
	for i in (rec["clues"] as Array).size():
		var f: String = String(rec["clues"][i])
		if found.has(f):
			continue
		found.append(f)
		var soc := _soc()
		var text := _clue_text(rec, i)
		if soc != null:
			soc.learn(f, text)
		if found.size() >= mini(CLUES_NEEDED, (rec["clues"] as Array).size()) and not bool(rec["known"]):
			rec["known"] = true
			var pn := String(_parent(String(rec["parent"])).get("name", "Your parent"))
			out.append("You finally understand: %s is going without so that you can stay in school." % pn)
			if soc != null:
				soc.learn("topic:parents_sacrifice", "Your parents are making sacrifices you were never told about.")
				soc.learn("secret:parents_%s" % String(rec["kind"]), "%s has been quietly sacrificing for you." % pn)
		return text
	return ""


## Player action at home: look around, ask neighbours. Reveals the next clue of the oldest hidden sacrifice.
func investigate_home(_ctx := {}) -> Dictionary:
	_ensure()
	var out: Array = []
	if int(player["sid"]) != int(fam["sid"]):
		return {"ok": false, "reason": "You are not at home.", "messages": out}
	for rec: Dictionary in sacrifice_list:
		if String(rec["status"]) != "active":
			continue
		if (rec["found"] as Array).size() >= (rec["clues"] as Array).size():
			continue
		var t := _reveal_clue(rec, out)
		if t != "":
			return {"ok": true, "clue": t, "sacrifice": rec["id"], "known": rec["known"], "messages": out, "reason": ""}
	return {"ok": false, "reason": "Nothing seems out of place.", "messages": out}


func clues_known() -> Array:
	var soc := _soc()
	var out: Array = []
	for rec: Dictionary in sacrifice_list:
		for f: String in rec["found"]:
			out.append({"fact": f, "known": soc != null and soc.knows(f)})
	return out


## Choices once you know: continue_studying, get_job, leave_school, send_money, ask_stop, find_solution.
func respond_to_sacrifice(sac_id: String, choice: String, gold := 0) -> Dictionary:
	for rec: Dictionary in sacrifice_list:
		if String(rec["id"]) != sac_id or String(rec["status"]) != "active":
			continue
		if not bool(rec["known"]):
			return {"ok": false, "reason": "You do not know about it."}
		var p := _parent(String(rec["parent"]))
		match choice:
			"continue_studying":
				return {"ok": true, "reason": "You keep studying, and carry the weight."}
			"send_money":
				if gold <= 0 or _gold() < gold:
					return {"ok": false, "reason": "You cannot send that."}
				pending_gold -= gold
				fam["savings"] = float(fam["savings"]) + gold
				if float(fam["savings"]) > 40.0:
					_stop_sacrifice(rec, "You sent enough that they can stop.")
				return {"ok": true, "reason": "You send money home."}
			"ask_stop":
				var r := _rng("askstop", _day, sac_id)
				if r.randf() > float(p.get("pride", 0.5)) * 0.9:
					_stop_sacrifice(rec, "They agree to stop.")
					return {"ok": true, "reason": "%s finally agrees to stop." % p.get("name", "They")}
				return {"ok": false, "reason": "%s waves you off: it is not your burden." % p.get("name", "They")}
			"get_job":
				return {"ok": true, "reason": "You find work of your own. The pressure at home eases.", "eases": true}
			"leave_school":
				var e := _edu()
				if e != null and e.has_method("drop_out"):
					e.call("drop_out", "family_needs")
				_stop_sacrifice(rec, "You leave school so they can stop.")
				return {"ok": true, "reason": "You leave school. What you learned stays with you."}
			"find_solution":
				return {"ok": true, "reason": "You start looking for another way."}
		return {"ok": false, "reason": "Unknown choice."}
	return {"ok": false, "reason": "No such sacrifice."}


func _stop_sacrifice(rec: Dictionary, _why: String) -> void:
	rec["status"] = "stopped"
	var p := _parent(String(rec["parent"]))
	if p.is_empty():
		return
	match String(rec["kind"]):
		"extra_job":
			p["extra_job"] = false
		"skip_meals":
			p["skipping"] = false


func _sacrifice_day(day: int) -> void:
	var r := _rng("clueday", day, "x")
	var home := int(player["sid"]) == int(fam["sid"])
	for rec: Dictionary in sacrifice_list:
		if String(rec["status"]) != "active" or bool(rec["known"]):
			continue
		if (rec["found"] as Array).size() >= (rec["clues"] as Array).size():
			continue
		if r.randf() < (0.07 if home else 0.01):
			var msgs: Array = []
			_reveal_clue(rec, msgs)
			for m in msgs:
				_flush.append(m)


var _flush: Array = []


func _weekly_sacrifice(week: int) -> void:
	# Pressure from schooling: consider a new sacrifice when the budget is blown.
	var pressure := float(fam["strain"]) + (0.3 if _student_support > 0.0 else 0.0)
	var active := 0
	for s: Dictionary in sacrifice_list:
		if String(s["status"]) == "active":
			active += 1
	if _student_support > 0.0 and float(fam["savings"]) < 20.0 and active < 3:
		var r := _rng("sacweek", week, "x")
		if r.randf() < clampf(0.3 + pressure * 0.6, 0.0, 0.95):
			var alive := _alive()
			if not alive.is_empty():
				var pi: Dictionary = alive[r.randi() % alive.size()]
				var opts: Array = []
				if not bool(pi["extra_job"]) and float(pi["health"]) >= 0.5:
					opts.append("extra_job")
				if (fam["sold"] as Array).size() < PARENT_ITEMS.size():
					opts.append("sell_item")
				if float((fam["debt"] as Dictionary)["amount"]) < DEBT_CAP * 0.7:
					opts.append("borrow")
				if not bool(pi["skipping"]) and float(pi["health"]) >= 0.4:
					opts.append("skip_meals")
				if not opts.is_empty():
					start_sacrifice(String(opts[r.randi() % opts.size()]), String(pi["id"]))
	_student_support = 0.0
	# End sacrifices when the pressure is gone.
	for s: Dictionary in sacrifice_list:
		if String(s["status"]) == "active" and float(fam["savings"]) > 60.0 and float((fam["debt"] as Dictionary)["amount"]) < 5.0 and s["kind"] in ["extra_job", "skip_meals"]:
			_stop_sacrifice(s, "no longer needed")


# ---------------------------------------------------------------- economy ticks (C§1)

func _economy_day(day: int, out: Array[String]) -> void:
	var inc := _income_day()
	var spend := _expense_day()
	# Food: a bad harvest empties the larder faster.
	fam["food_days"] = clampf(float(fam["food_days"]) + (0.1 if float(fam["savings"]) > 5.0 else -0.4), 0.0, 14.0)
	var net := inc - spend
	# Tax accrues into an owed pile, collected every TAX_EVERY days.
	fam["tax_owed"] = float(fam["tax_owed"]) + tax_rate_day()
	if day >= int(fam["next_tax"]):
		fam["next_tax"] = day + TAX_EVERY
		var owed := float(fam["tax_owed"]) + float(fam["tax_arrears"])
		fam["tax_owed"] = 0.0
		var pay := minf(owed, maxf(0.0, float(fam["savings"]) + net))
		fam["savings"] = float(fam["savings"]) - pay
		fam["tax_arrears"] = owed - pay
		if float(fam["tax_arrears"]) > 1.0:
			out.append("The tax collector has called at your family's door; %d gold is still owed." % int(fam["tax_arrears"]))
			fam["strain"] = minf(1.0, float(fam["strain"]) + 0.08)
	# House: decay, repair when affordable.
	fam["house"] = clampf(float(fam["house"]) - 0.0015, 0.0, 1.0)
	fam["repairs_pending"] = float(fam["house"]) < HOUSE_REPAIR_AT
	if bool(fam["repairs_pending"]) and float(fam["savings"]) >= REPAIR_COST + 10.0:
		fam["savings"] = float(fam["savings"]) - REPAIR_COST
		fam["house"] = 0.85
		fam["repairs_pending"] = false
	fam["savings"] = float(fam["savings"]) + net
	if float(fam["savings"]) < 0.0:
		var d: Dictionary = fam["debt"]
		d["amount"] = float(d["amount"]) - float(fam["savings"])
		if String(d["creditor"]) == "":
			d["creditor"] = "the moneylender"
			d["since"] = day
		fam["savings"] = 0.0
		fam["strain"] = minf(1.0, float(fam["strain"]) + 0.01)
	else:
		fam["strain"] = maxf(0.0, float(fam["strain"]) - 0.004)
	# Bad harvest on the turn of autumn.
	if _season != _season_seen:
		_season_seen = _season
		if _season == "autumn":
			var r := _rng("harvest", day, int(fam["sid"]))
			if r.randf() < 0.14 or _emergency(int(fam["sid"]), ["famine"]):
				fam["bad_harvest_until"] = day + 120
				out.append("The harvest has failed around %s. Food will cost more this winter." % _sname(int(fam["sid"])))
	# Injury and illness.
	for p: Dictionary in fam["parents"]:
		if not bool(p["alive"]) or String(p["status"]) != "home":
			continue
		var r2 := _rng("hurt", day, String(p["id"]))
		var hz := float(JOBS[String(p["job"])]["hazard"]) * (1.6 if bool(p["extra_job"]) else 1.0)
		if int(p["injured_until"]) <= day and r2.randf() < hz * 6.0:
			injure_parent(String(p["id"]), r2.randi_range(8, 30), "an accident at work")
			out.append("%s was hurt at work and cannot earn for a while." % p["name"])
		var ill_p := 0.0008 + (0.002 if _season == "winter" else 0.0) + (0.003 if float(p["health"]) < 0.5 else 0.0) + (0.002 if float(fam["house"]) < HOUSE_REPAIR_AT else 0.0)
		if _emergency(int(fam["sid"]), ["plague"]):
			ill_p += 0.01
		if int(p["ill_until"]) <= day and r2.randf() < ill_p:
			p["ill_until"] = day + r2.randi_range(6, 20)
			p["illness"] = "winter fever" if _season == "winter" else "a wasting sickness"
			(p["chain"] as Array).append("fell ill with %s" % p["illness"])
		# Health drift: rest and food heal, overwork and hunger wear.
		var drain := 0.0
		if bool(p["extra_job"]):
			drain += 0.006
		if bool(p["skipping"]):
			drain += 0.004
		if float(fam["food_days"]) <= 0.5:
			drain += 0.004
		if int(p["ill_until"]) > day:
			drain += 0.005
		p["health"] = clampf(float(p["health"]) + (0.003 - drain), 0.02, 1.0)
		if int(p["ill_until"]) > day and float(p["health"]) < 0.3:
			(p["chain"] as Array).append("weakened by overwork and hunger")


func injure_parent(role: String, days: int, cause := "an accident") -> void:
	_ensure()
	var p := _parent(role)
	if p.is_empty() or not bool(p["alive"]):
		return
	p["injured_until"] = _day + days
	p["health"] = maxf(0.05, float(p["health"]) - 0.15)
	(p["chain"] as Array).append("was hurt in %s" % cause)


# ---------------------------------------------------------------- parents die from believable causes (C§42)

func hazards(role: String) -> Dictionary:
	_ensure()
	var p := _parent(role)
	if p.is_empty() or not bool(p["alive"]):
		return {"total": 0.0}
	var age := parent_age(role)
	var h := {}
	h["old_age"] = 0.0 if age < 60 else 0.00004 * float(age - 58) * float(age - 58)
	var hp := float(p["health"])
	var ill := int(p["ill_until"]) > _day
	h["disease"] = (0.0004 + (0.004 if ill else 0.0)) * (1.0 + (0.6 - hp) * 4.0 if hp < 0.6 else 1.0)
	h["poverty"] = 0.012 if (hp < 0.25 and (bool(p["skipping"]) or float(fam["food_days"]) < 1.0)) else 0.0
	h["accident"] = float(JOBS[String(p["job"])]["hazard"]) * 0.1 * (1.6 if bool(p["extra_job"]) else 1.0)
	h["war"] = 0.0
	if _at_war and String(p["job"]) in ["guard", "militia"]:
		h["war"] = 0.0025
	h["crime"] = 0.00012 * (2.0 if _skind(int(fam["sid"])) != "village" else 1.0) + (0.0003 if float((fam["debt"] as Dictionary)["amount"]) > 60.0 else 0.0)
	h["monster"] = 0.0004 if _skind(int(fam["sid"])) == "frontier_town" else 0.00005
	if String(p["status"]) in ["captive", "forced_labour"]:
		h["captivity"] = 0.006 * (1.6 - hp)
	var t := 0.0
	for k: String in h:
		t += float(h[k])
	h["total"] = t
	return h


func _cause_text(role: String, cause: String) -> String:
	var p := _parent(role)
	var chain: Array = p.get("chain", [])
	var lead := ""
	if not chain.is_empty():
		lead = ", after they " + String(chain[chain.size() - 1])
	match cause:
		"war":
			return "fell in the war%s" % lead
		"disease":
			return "died of %s%s" % [String(p.get("illness", "a fever")) if String(p.get("illness", "")) != "" else "a fever", lead]
		"crime":
			return "was killed in a robbery%s" % lead
		"accident":
			return "died in a workplace accident%s" % lead
		"poverty":
			return "wasted away from hunger and overwork%s" % lead
		"monster":
			return "was killed by a beast%s" % lead
		"captivity":
			return "died in forced labour far from home%s" % lead
		"old_age":
			return "died of old age%s" % lead
	return "died"


func kill_parent(role: String, cause: String, msgs: Array = []) -> void:
	_ensure()
	var p := _parent(role)
	if p.is_empty() or not bool(p["alive"]):
		return
	p["alive"] = false
	p["status"] = "dead"
	p["cause"] = cause
	var text := "%s %s." % [p["name"], _cause_text(role, cause)]
	death_log.append({"role": role, "day": _day, "cause": cause, "text": text, "chain": (p["chain"] as Array).duplicate()})
	msgs.append(text)
	for rec: Dictionary in sacrifice_list:
		if String(rec["parent"]) == role and String(rec["status"]) == "active":
			rec["status"] = "ended"
	fam["strain"] = minf(1.0, float(fam["strain"]) + 0.25)
	if _alive().is_empty():
		fam["orphan"] = true
		var r := _rng("guardian", _day, "x")
		fam["guardian"] = String(_pick(r, ["an aunt in the next village", "the temple almoner", "the master of the local guild", "a neighbour family"]))
		msgs.append("With both parents gone you are taken in by %s." % fam["guardian"])
	# Keep the older Life.family in step (guarded).
	if hub != null:
		pass
	var soc := _soc()
	if soc != null:
		soc.learn("topic:%s_death" % role, text)


func _sync_life_deaths(ctx: Dictionary) -> void:
	var life: Variant = ctx.get("life")
	if life == null or not (life is Object):
		return
	var fm: Variant = (life as Object).get("family")
	if fm == null or not (fm is Object):
		return
	var ps: Variant = (fm as Object).get("parent_state")
	if ps is Dictionary:
		for p: Dictionary in fam["parents"]:
			if not bool(p["alive"]) and (ps as Dictionary).has(String(p["id"])):
				var st: Variant = (ps as Dictionary)[String(p["id"])]
				if st is Dictionary and bool((st as Dictionary).get("alive", true)):
					(st as Dictionary)["alive"] = false
					(st as Dictionary)["death_day"] = _day


func _death_day(day: int, out: Array[String]) -> void:
	for p: Dictionary in fam["parents"]:
		if not bool(p["alive"]):
			continue
		var h := hazards(String(p["id"]))
		if float(h["total"]) <= 0.0:
			continue
		var r := _rng("pdeath", day, String(p["id"]))
		if r.randf() < float(h["total"]):
			var roll := r.randf() * float(h["total"])
			var cause := "disease"
			for k: String in h:
				if k == "total":
					continue
				roll -= float(h[k])
				if roll <= 0.0:
					cause = k
					break
			kill_parent(String(p["id"]), cause, out)


func deaths() -> Array:
	return death_log.duplicate(true)


# ---------------------------------------------------------------- family travel (C§39)

## Danger 0..1 of a road leg from the world sim: war, unrest, raids, road risk, hostile armies, season.
func leg_danger(a: int, b: int, ctx := {}) -> float:
	var d := 0.06
	for s in [a, b]:
		var k := _skind(int(s))
		d += 0.05 if k == "frontier_town" else 0.0
		d += 0.15 * _unrest(int(s)) * 0.5
		if _emergency(int(s), ["raid", "raid_aftermath"]):
			d += 0.1
	var war := bool(ctx.get("at_war", _at_war))
	if war:
		d += 0.15
	var life: Variant = ctx.get("life")
	if life != null and life is Object:
		var eco: Variant = (life as Object).get("economy")
		if eco != null and eco is Object:
			var rr: Variant = (eco as Object).get("road_risk")
			if rr is Dictionary:
				d += 0.25 * maxf(float((rr as Dictionary).get(a, 0.0)), float((rr as Dictionary).get(b, 0.0)))
	if hub != null:
		var c: RefCounted = hub.mod("campaign")
		if c != null and c.has_method("armies") and a >= 0 and b >= 0 and a < WorldGen.settlements.size() and b < WorldGen.settlements.size():
			var mid: Vector2 = (WorldGen.settlements[a]["pos"] as Vector2).lerp(WorldGen.settlements[b]["pos"], 0.5)
			for army: Dictionary in c.call("armies"):
				if not (String(army.get("faction", "")) in ["player", "crown"]) and (army["pos"] as Vector2).distance_to(mid) < 300.0:
					d += 0.2
					break
	if String(ctx.get("season", _season)) == "winter":
		d += 0.04
	return clampf(d, 0.0, 0.95)


func _route(a: int, b: int) -> Array:
	if hub != null:
		var c: RefCounted = hub.mod("campaign")
		if c != null and c.has_method("path"):
			var p: Array = c.call("path", a, b)
			if p.size() >= 2:
				return p
	return [a, b]


func trip() -> Dictionary:
	return trip_state.duplicate(true)


## Plan a family trip to `dest`. With the player, encounters are interactive.
func plan_trip(dest: int, ctx := {}, with_player := true) -> Dictionary:
	_ensure()
	if not trip_state.is_empty():
		return {"ok": false, "reason": "A trip is already under way."}
	if _alive().is_empty():
		return {"ok": false, "reason": "There is no family to travel with."}
	if String(player_status()) == "displaced":
		return {"ok": false, "reason": "You are not with your family."}
	var from := int(fam["sid"])
	var fwd := _route(from, dest)
	var full: Array = fwd.duplicate()
	var back := fwd.duplicate()
	back.reverse()
	for i in range(1, back.size()):
		full.append(back[i])
	var hours: Array = []
	for i in range(1, full.size()):
		hours.append(maxi(2, int(ceil(_dist(int(full[i - 1]), int(full[i])) / TRAVEL_SPEED))))
	trip_state = {"id": _new_id("trip"), "from": from, "to": dest, "route": full, "hours": hours, "leg": 0, "hours_left": int(hours[0]) if not hours.is_empty() else 1,
		"with_player": with_player, "day": _day, "status": "travelling", "stay_left": STAY_HOURS, "turned": (fwd.size() - 1), "incidents": 0}
	for p: Dictionary in _alive():
		p["status"] = "travelling"
	return {"ok": true, "trip": trip_state.duplicate(true), "reason": "You set out for %s." % _sname(dest)}


func cancel_trip() -> void:
	if trip_state.is_empty():
		return
	trip_state = {}
	encounter = {}
	for p: Dictionary in fam["parents"]:
		if bool(p["alive"]) and String(p["status"]) == "travelling":
			p["status"] = "home"


func pending_encounter() -> Dictionary:
	return encounter.duplicate(true)


func _pick_kind(a: int, b: int, ctx: Dictionary, r: RandomNumberGenerator) -> String:
	var w := {"bandits": 1.0, "corrupt_official": 0.35, "road_closure": 0.35}
	if bool(ctx.get("at_war", _at_war)):
		w["war"] = 1.4
	var un := maxf(_unrest(a), _unrest(b))
	if un > 0.3:
		w["rebels"] = 1.6 * un
	if _skind(a) == "frontier_town" or _skind(b) == "frontier_town":
		w["monsters"] = 0.9
	if _skind(a) in ["town", "castle"] or _skind(b) in ["town", "castle"]:
		w["criminal_group"] = 0.6
	var tot := 0.0
	for k: String in w:
		tot += float(w[k])
	var roll := r.randf() * tot
	for k: String in w:
		roll -= float(w[k])
		if roll <= 0.0:
			return k
	return "bandits"


func _trip_hour(ctx: Dictionary, out: Array[String]) -> void:
	if trip_state.is_empty():
		return
	if not encounter.is_empty():
		if _hour_diff(int(encounter["hour"])) >= ENCOUNTER_TIMEOUT_H or int(encounter["day"]) != _day:
			out.append_array(_auto_resolve(ctx))
		return
	var t: Dictionary = trip_state
	var route: Array = t["route"]
	var leg := int(t["leg"])
	if leg >= route.size() - 1:
		_finish_trip(out)
		return
	var turned := int(t["turned"])
	# Stay at the destination for a while.
	if leg == turned and int(t["stay_left"]) > 0:
		t["stay_left"] = int(t["stay_left"]) - 1
		return
	var a := int(route[leg])
	var b := int(route[leg + 1])
	var hl := int(t["hours_left"])
	var dg := leg_danger(a, b, ctx)
	var r := _rng("enc", _day * 24 + _hour, String(t["id"]))
	var night := _hour >= 21 or _hour < 5
	if r.randf() < dg * 0.03 * (1.4 if night else 1.0):
		var kind := _pick_kind(a, b, ctx, r)
		t["incidents"] = int(t["incidents"]) + 1
		encounter = {"kind": kind, "text": String(ENCOUNTERS[kind]["text"]), "day": _day, "hour": _hour, "leg": leg, "danger": snappedf(dg, 0.01),
			"choices": ["fight", "flee", "bargain", "hide", "surrender"] if kind != "road_closure" else ["wait"]}
		out.append(String(encounter["text"]))
		if not bool(t["with_player"]):
			out.append_array(_auto_resolve(ctx))
		return
	hl -= 1
	if hl <= 0:
		t["leg"] = leg + 1
		if leg + 1 < route.size() - 1:
			t["hours_left"] = int((t["hours"] as Array)[leg + 1])
		else:
			_finish_trip(out)
			return
		if leg + 1 == turned:
			out.append("The family reaches %s." % _sname(int(route[leg + 1])))
	else:
		t["hours_left"] = hl


func _hour_diff(h: int) -> int:
	return (_hour - h + 24) % 24


func _finish_trip(out: Array[String]) -> void:
	trip_log.append({"id": trip_state["id"], "day": _day, "to": trip_state["to"], "incidents": trip_state["incidents"], "result": "home"})
	if trip_log.size() > 20:
		trip_log.pop_front()
	for p: Dictionary in fam["parents"]:
		if bool(p["alive"]) and String(p["status"]) == "travelling":
			p["status"] = "home"
	out.append("The family is home again.")
	trip_state = {}


func _auto_resolve(ctx: Dictionary) -> Array:
	var choice := "surrender" if float(_fighting()) < 30.0 else "fight"
	if String(encounter.get("kind", "")) == "road_closure":
		choice = "wait"
	var res := resolve_encounter(choice, ctx)
	return res.get("messages", [])


## Resolve the live encounter. choices: fight, flee, bargain, hide, surrender, wait.
func resolve_encounter(choice: String, ctx := {}) -> Dictionary:
	if encounter.is_empty() or trip_state.is_empty():
		return {"ok": false, "reason": "Nothing is happening.", "messages": []}
	var kind: String = String(encounter["kind"])
	var def: Dictionary = ENCOUNTERS[kind]
	var r := _rng("encres", int(encounter["day"]) * 24 + int(encounter["hour"]), String(trip_state["id"]))
	var msgs: Array = []
	var sev := float(def["sev"])
	var with_p := bool(trip_state["with_player"])
	var power := 0.15 + (_fighting() / 100.0 * 0.8 if with_p else 0.0)
	var outcome := "safe"
	var toll := int(def["toll"])
	var bad := 0.0
	match choice:
		"wait":
			outcome = "delayed"
		"fight":
			bad = sev * clampf(1.15 - power * 1.4, 0.05, 1.0)
		"flee":
			bad = sev * 0.8
		"hide":
			bad = sev * 0.65
		"surrender":
			bad = sev * 0.5
		"bargain":
			if toll > 0 and (_gold() >= toll or not with_p):
				if with_p:
					pending_gold -= toll
				else:
					fam["savings"] = maxf(0.0, float(fam["savings"]) - toll)
				outcome = "paid"
				msgs.append("Coin changes hands and the road opens.")
			else:
				bad = sev
	if outcome == "safe" and r.randf() < bad:
		var r2 := r.randf()
		if r2 < 0.3:
			outcome = "robbed"
			if with_p:
				pending_gold -= mini(_gold(), 20)
			msgs.append("You are robbed of what you carry.")
		elif r2 < 0.5:
			outcome = "injured"
			var al := _alive()
			if not al.is_empty():
				var pi: Dictionary = al[r.randi() % al.size()]
				injure_parent(String(pi["id"]), 15, "an ambush on the road")
				msgs.append("%s is hurt in the struggle." % pi["name"])
		elif r2 < 0.5 + 0.35 * (1.0 if String(def["captor"]) != "" else 0.4):
			outcome = "separated"
			var who := "parents"
			var wr := r.randf()
			if with_p:
				who = "player" if wr < 0.45 else ("parents" if wr < 0.8 else "both")
			var captor: String = String(def["captor"])
			if captor == "":
				captor = "bandit_gang"
			msgs.append_array(kidnap(who, captor, ctx))
		else:
			outcome = "killed"
			var al2 := _alive()
			if not al2.is_empty() and kind in ["war", "monsters", "bandits"]:
				var pk: Dictionary = al2[r.randi() % al2.size()]
				kill_parent(String(pk["id"]), "war" if kind == "war" else ("monster" if kind == "monsters" else "crime"), msgs)
	elif outcome == "safe":
		msgs.append("You get through unharmed.")
	var out := {"ok": true, "outcome": outcome, "kind": kind, "messages": msgs}
	encounter = {}
	return out


# ---------------------------------------------------------------- kidnapping and displacement (C§40)

func _far_from(sid: int, r: RandomNumberGenerator) -> int:
	var ranked: Array = []
	for s: Dictionary in WorldGen.settlements:
		ranked.append([_dist(sid, int(s["id"])), int(s["id"])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var top := mini(3, ranked.size())
	return int(ranked[r.randi() % top][1]) if top > 0 else sid


func player_status() -> String:
	if not displaced_state.is_empty():
		return "displaced" if not bool(displaced_state.get("free", false)) else "free_far"
	if not trip_state.is_empty() and bool(trip_state.get("with_player", false)):
		return "travelling"
	return "home"


func displaced() -> Dictionary:
	return displaced_state.duplicate(true)


## Capture `who` ("player", "parents", "both") by `captor`. Returns messages.
func kidnap(who: String, captor: String, _ctx := {}) -> Array:
	_ensure()
	var msgs: Array = []
	var r := _rng("kidnap", _day, who + captor)
	var home := int(fam["sid"])
	var route: Array = CAPTOR_ROUTE.get(captor, CAPTOR_ROUTE["bandit_gang"])
	var loc := _far_from(home, r)
	var site: String = String(_pick(r, LABOUR_SITES))
	var last_seen := int(trip_state.get("route", [home])[mini(int(trip_state.get("leg", 0)), (trip_state.get("route", [home]) as Array).size() - 1)]) if not trip_state.is_empty() else home
	if who in ["player", "both"]:
		displaced_state = {"stage": String(route[0]), "route": route, "captor": captor, "loc": loc, "from": home, "day": _day, "stage_day": 0, "site": site, "free": false,
			"escape": 0.0, "days": 0}
		msgs.append("A raid separates you from your family. You are taken.")
		var e := _edu()
		if e != null and e.has_method("on_displaced"):
			e.call("on_displaced", loc)
	if who in ["parents", "both"]:
		var roles: Array = []
		for p: Dictionary in _alive():
			p["status"] = "captive"
			roles.append(String(p["id"]))
		if not roles.is_empty():
			captive = {"who": roles, "captor": captor, "route": route, "stage": String(route[0]), "loc": loc, "from": home, "day": _day, "stage_day": 0, "site": site,
				"last_seen": last_seen, "weeks": 0, "rescued": false}
			msgs.append("Your parents were taken in the raid.")
			_add_lead("lead:family_missing", "Your parents never arrived. The cart was found near %s, empty." % _sname(last_seen))
	trip_state = {}
	encounter = {}
	return msgs


func _add_lead(fact: String, text: String) -> bool:
	if leads_state.has(fact):
		return false
	leads_state[fact] = {"day": _day, "text": text}
	var soc := _soc()
	if soc != null:
		soc.learn(fact, text)
	return true


func _captive_day(day: int, out: Array[String]) -> void:
	if not captive.is_empty() and not bool(captive["rescued"]):
		var route: Array = captive["route"]
		var st: String = String(captive["stage"])
		captive["stage_day"] = int(captive["stage_day"]) + 1
		if STAGE_DAYS.has(st) and int(captive["stage_day"]) >= int(STAGE_DAYS[st]):
			var idx := route.find(st)
			if idx >= 0 and idx < route.size() - 1:
				captive["stage"] = String(route[idx + 1])
				captive["stage_day"] = 0
				if String(captive["stage"]) == "transported":
					_add_lead("lead:family_transported", "A witness saw a covered wagon heading %s in the night." % _compass(int(captive["from"]), int(captive["loc"])))
				elif String(captive["stage"]) in ["sold", "held", "conscripted"]:
					_add_lead("lead:family_market", "Someone at the roadhouse remembers a buyer in a grey coat asking about two new hands.")
				elif String(captive["stage"]) == "forced_labour":
					for role: String in captive["who"]:
						var p := _parent(role)
						if not p.is_empty():
							p["status"] = "forced_labour"
	if not displaced_state.is_empty() and not bool(displaced_state["free"]):
		var ds: Dictionary = displaced_state
		ds["days"] = int(ds["days"]) + 1
		ds["stage_day"] = int(ds["stage_day"]) + 1
		var st2: String = String(ds["stage"])
		if STAGE_DAYS.has(st2) and int(ds["stage_day"]) >= int(STAGE_DAYS[st2]):
			var rt: Array = ds["route"]
			var i2 := rt.find(st2)
			if i2 >= 0 and i2 < rt.size() - 1:
				ds["stage"] = String(rt[i2 + 1])
				ds["stage_day"] = 0
				if String(ds["stage"]) == "forced_labour":
					out.append("You wake up hundreds of kilometres from home, chained to the work at the %s near %s. The life you planned is gone; what happens next is yours to decide." % [ds["site"], _sname(int(ds["loc"]))])


func _compass(a: int, b: int) -> String:
	if a < 0 or b < 0 or a >= WorldGen.settlements.size() or b >= WorldGen.settlements.size():
		return "away"
	var d: Vector2 = (WorldGen.settlements[b]["pos"] as Vector2) - (WorldGen.settlements[a]["pos"] as Vector2)
	if absf(d.x) > absf(d.y):
		return "east" if d.x > 0.0 else "west"
	return "south" if d.y > 0.0 else "north"


## Escape attempt for a displaced player. plan: sneak, fight, bribe, wait.
func attempt_escape(plan: String, ctx := {}) -> Dictionary:
	if displaced_state.is_empty() or bool(displaced_state["free"]):
		return {"ok": false, "reason": "You are not held."}
	if String(displaced_state["stage"]) in ["captured", "transported"] and plan != "wait":
		var early := _rng("escape_early", _day, plan)
		if early.randf() > 0.15:
			return {"ok": false, "reason": "You are watched too closely on the road."}
	var ds: Dictionary = displaced_state
	var r := _rng("escape", _day, plan + str(int(ds["days"])))
	var p := 0.0
	match plan:
		"sneak":
			p = 0.18 + float(ds["escape"]) * 0.5 + float(ctx.get("stealth", 0.0)) / 200.0
		"fight":
			p = 0.05 + _fighting() / 220.0
		"bribe":
			p = 0.3 if _gold() >= 30 else 0.0
			if p > 0.0:
				pending_gold -= 30
		"wait":
			ds["escape"] = minf(1.0, float(ds["escape"]) + 0.08)
			return {"ok": false, "reason": "You watch, and learn the guards' habits."}
	if r.randf() < p:
		ds["free"] = true
		ds["stage"] = "escaped"
		return {"ok": true, "reason": "You get away in the night, far from anywhere you know.", "loc": int(ds["loc"])}
	ds["escape"] = minf(1.0, float(ds["escape"]) + 0.04)
	if plan == "fight" and r.randf() < 0.4:
		return {"ok": false, "reason": "They beat you down and chain you tighter."}
	return {"ok": false, "reason": "It does not work this time."}


func _return_check(ctx: Dictionary, out: Array[String]) -> void:
	if displaced_state.is_empty() or not bool(displaced_state["free"]):
		return
	if int(player["sid"]) == int(fam["sid"]):
		out.append("After everything, you are home.")
		displaced_state = {}
		var e := _edu()
		if e != null and e.has_method("on_returned"):
			e.call("on_returned")


# ---------------------------------------------------------------- missing family: leads only, no marker (C§41)

func missing_family() -> Dictionary:
	if captive.is_empty():
		return {"missing": false, "leads": []}
	return {"missing": not bool(captive["rescued"]), "leads": search_leads()}


func search_leads() -> Array:
	var out: Array = []
	for f: String in leads_state:
		out.append({"fact": f, "text": String(leads_state[f]["text"]), "day": int(leads_state[f]["day"])})
	return out


## Ask around / follow a lead. Reveals the next lead with a chance. No coordinates, ever.
func follow_lead(fact: String, ctx := {}) -> Dictionary:
	if captive.is_empty() or bool(captive["rescued"]):
		return {"ok": false, "reason": "There is nothing to follow."}
	if not leads_state.has(fact):
		return {"ok": false, "reason": "You have no such lead."}
	var r := _rng("follow", _day, fact + str(leads_state.size()))
	var charm := float(ctx.get("charm", player.get("charm", 10)))
	var stage: String = String(captive["stage"])
	var p := 0.35 + charm / 200.0
	var got := ""
	if fact == "lead:family_missing" and not leads_state.has("lead:family_transported"):
		if String(captive["stage"]) != "captured":
			_add_lead("lead:family_transported", "A witness saw a covered wagon heading %s in the night." % _compass(int(captive["from"]), int(captive["loc"])))
			got = "lead:family_transported"
	elif fact == "lead:family_transported" and stage in ["sold", "held", "conscripted", "forced_labour"] and not leads_state.has("lead:family_market"):
		_add_lead("lead:family_market", "Someone at the roadhouse remembers a buyer in a grey coat asking about two new hands.")
		got = "lead:family_market"
	elif fact == "lead:family_market" and stage == "forced_labour" and r.randf() < p and not leads_state.has("lead:family_location"):
		_add_lead("lead:family_location", "A drover says two people matching your parents' description work the %s near %s." % [captive["site"], _sname(int(captive["loc"]))])
		got = "lead:family_location"
	if got == "":
		return {"ok": false, "reason": "Nobody knows more, or nobody will say."}
	return {"ok": true, "lead": got, "reason": String(leads_state[got]["text"])}


## Attempt to free captive parents once the location is known. methods: fight, ransom, bribe, sneak, hire_help
func rescue_attempt(method: String, ctx := {}, gold := 0) -> Dictionary:
	if captive.is_empty() or bool(captive["rescued"]):
		return {"ok": false, "reason": "There is nobody to rescue."}
	if not leads_state.has("lead:family_location"):
		return {"ok": false, "reason": "You do not know where they are."}
	var r := _rng("rescue", _day, method + str(int(captive["stage_day"])))
	var p := 0.0
	match method:
		"fight":
			p = 0.05 + _fighting() / 140.0
		"ransom":
			p = 0.85 if gold >= 120 else 0.0
			if p > 0.0:
				pending_gold -= gold
		"bribe":
			p = 0.55 if gold >= 50 else 0.0
			if p > 0.0:
				pending_gold -= gold
		"sneak":
			p = 0.2 + float(ctx.get("stealth", 0.0)) / 200.0
		"hire_help":
			p = 0.6 if gold >= 80 else 0.0
			if p > 0.0:
				pending_gold -= gold
	if p <= 0.0:
		return {"ok": false, "reason": "You cannot manage that yet."}
	if r.randf() < p:
		_free_captives("You free your family.")
		return {"ok": true, "reason": "You bring them out."}
	return {"ok": false, "reason": "It goes wrong. They are moved somewhere else."}


func _free_captives(text: String) -> void:
	if captive.is_empty():
		return
	captive["rescued"] = true
	for role: String in captive["who"]:
		var p := _parent(role)
		if not p.is_empty() and bool(p["alive"]):
			p["status"] = "home"
			p["trauma"] = float(p["trauma"]) + 0.5
			p["health"] = clampf(float(p["health"]) - 0.2, 0.05, 1.0)
			(p["chain"] as Array).append("came back from captivity broken")
	_flush.append(text)


func _captive_week(week: int, out: Array[String]) -> void:
	if not captive.is_empty() and not bool(captive["rescued"]):
		captive["weeks"] = int(captive["weeks"]) + 1
		var r := _rng("capweek", week, "x")
		var labouring: bool = String(captive["stage"]) == "forced_labour"
		# Someone else may find them, or they may get out on their own.
		if labouring and r.randf() < 0.02:
			_free_captives("Word reaches you: your parents were freed by a patrol.")
			_flush.append("Your parents are free and coming home.")
		elif labouring and r.randf() < 0.03:
			_free_captives("Your parents escaped forced labour and made their way home.")
		if not bool(captive["rescued"]):
			for role: String in captive["who"]:
				var p := _parent(role)
				if p.is_empty() or not bool(p["alive"]):
					continue
				p["health"] = clampf(float(p["health"]) - (0.02 if labouring else 0.005), 0.02, 1.0)
				if labouring and (p["chain"] as Array).size() < 6:
					(p["chain"] as Array).append("worked to exhaustion in %s" % captive["site"])
				var hz := hazards(role)
				if labouring and r.randf() < 1.0 - pow(1.0 - float(hz.get("captivity", 0.0)), 7.0):
					kill_parent(role, "captivity", out)
			# Trail goes cold if nobody follows it.
			if int(captive["weeks"]) == 12 and leads_state.has("lead:family_market"):
				leads_state.erase("lead:family_market")
	if not displaced_state.is_empty() and not bool(displaced_state["free"]):
		var ds: Dictionary = displaced_state
		var r2 := _rng("dispweek", week, "x")
		var rescue_p := 0.02
		if not _alive().is_empty() and float(fam["savings"]) > 30.0:
			rescue_p += 0.03
		rescue_p += float(ds["escape"]) * 0.02
		if String(ds["stage"]) == "forced_labour" and r2.randf() < rescue_p:
			ds["free"] = true
			ds["stage"] = "rescued"
			out.append("A passing patrol breaks up the labour gang and you are let go, far from home.")


## Accidental discovery: glimpses when the player walks through the place they are held (C§41).
func _glimpse(day: int) -> void:
	if captive.is_empty() or bool(captive["rescued"]) or String(captive["stage"]) != "forced_labour":
		return
	if int(player["sid"]) != int(captive["loc"]):
		return
	var r := _rng("glimpse", day, "x")
	if r.randf() < 0.15 and not leads_state.has("lead:family_glimpse"):
		_add_lead("lead:family_glimpse", "In %s you glimpse two thin, tired people hauling stone at the %s, faces you almost know." % [_sname(int(captive["loc"])), captive["site"]])
		_flush.append("You think you saw someone familiar in the labour gangs.")
		if not leads_state.has("lead:family_location"):
			_add_lead("lead:family_location", "The gangs at the %s in %s are worked hard; those two are still there." % [captive["site"], _sname(int(captive["loc"]))])


# ---------------------------------------------------------------- ticks

func tick_hour(hour: int, ctx: Dictionary) -> Array:
	_hour = hour
	var out: Array[String] = []
	if trip_state.is_empty():
		return out
	_ensure()
	_sync(ctx)
	_trip_hour(ctx, out)
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	_day = day
	var out: Array[String] = []
	_economy_day(day, out)
	_sacrifice_day(day)
	_captive_day(day, out)
	_death_day(day, out)
	_glimpse(day)
	_return_check(ctx, out)
	_sync_life_deaths(ctx)
	out.append_array(_flush_out())
	if float(fam["strain"]) > 0.7 and day % 30 == 0:
		out.append("Things are hard at home.")
	return out


func _flush_out() -> Array:
	var o := _flush.duplicate()
	_flush.clear()
	return o


func tick_week(week: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	var out: Array[String] = []
	fam["weeks"] = int(fam["weeks"]) + 1
	var d: Dictionary = fam["debt"]
	if float(d["amount"]) > 0.0:
		d["amount"] = float(d["amount"]) * (1.0 + DEBT_RATE_WEEK)
		# Savings first pay the debt down a little.
		var pay := minf(float(d["amount"]), maxf(0.0, float(fam["savings"]) - 15.0) * 0.4)
		d["amount"] = float(d["amount"]) - pay
		fam["savings"] = float(fam["savings"]) - pay
		if float(d["amount"]) < 0.5:
			d["amount"] = 0.0
			d["creditor"] = ""
	_weekly_sacrifice(week)
	_captive_week(week, out)
	out.append_array(_flush_out())
	return out


## Sleep / travel / load: closed-form. O(parents + sacrifices), never O(days * entities).
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	var out: Array[String] = []
	if days < 1:
		return out
	var day := _day + days
	# Economy: net cash flow over the span, shortfalls become debt, debt compounds weekly.
	var weeks := float(days) / 7.0
	var net := (_income_day() - _expense_day()) * float(days)
	var sv := float(fam["savings"]) + net
	var d: Dictionary = fam["debt"]
	if sv < 0.0:
		d["amount"] = float(d["amount"]) - sv
		if String(d["creditor"]) == "":
			d["creditor"] = "the moneylender"
			d["since"] = day
		sv = 0.0
	fam["savings"] = sv
	if float(d["amount"]) > 0.0:
		d["amount"] = minf(DEBT_CAP * 3.0, float(d["amount"]) * pow(1.0 + DEBT_RATE_WEEK, weeks))
	fam["house"] = clampf(float(fam["house"]) - 0.0015 * float(days), 0.0, 1.0)
	if float(fam["house"]) < HOUSE_REPAIR_AT and float(fam["savings"]) > REPAIR_COST + 10.0:
		fam["savings"] = float(fam["savings"]) - REPAIR_COST
		fam["house"] = 0.85
	fam["tax_owed"] = 0.0
	fam["next_tax"] = maxi(int(fam["next_tax"]), day + 1)
	if int(fam["bad_harvest_until"]) < day:
		fam["bad_harvest_until"] = -1
	_day = day
	# Trips resolve statistically.
	if not trip_state.is_empty():
		var t: Dictionary = trip_state
		var route: Array = t["route"]
		var risk := 0.0
		for i in range(int(t["leg"]), route.size() - 1):
			risk = maxf(risk, leg_danger(int(route[i]), int(route[i + 1]), ctx))
		var r := _rng("trip_cu", day, String(t["id"]))
		if not encounter.is_empty():
			encounter = {}
		if r.randf() < risk * 0.45:
			var kind := _pick_kind(int(route[0]), int(route[route.size() - 1]), ctx, r)
			encounter = {"kind": kind, "text": String(ENCOUNTERS[kind]["text"]), "day": day, "hour": 0, "leg": int(t["leg"]), "danger": risk, "choices": []}
			t["with_player"] = false
			var res := resolve_encounter("surrender", ctx)
			out.append_array(res.get("messages", []))
			if not trip_state.is_empty():
				_finish_trip(out)
		else:
			_finish_trip(out)
	# Captivity progresses by expected values.
	if not captive.is_empty() and not bool(captive["rescued"]):
		captive["weeks"] = int(captive["weeks"]) + int(weeks)
		var total_days := int(captive["stage_day"]) + days
		var route2: Array = captive["route"]
		while total_days > 0:
			var st: String = String(captive["stage"])
			var need: int = int(STAGE_DAYS.get(st, 9999))
			if total_days < need:
				break
			total_days -= need
			var idx := route2.find(st)
			if idx < 0 or idx >= route2.size() - 1:
				break
			captive["stage"] = String(route2[idx + 1])
			if String(captive["stage"]) == "transported":
				_add_lead("lead:family_transported", "A witness saw a covered wagon heading %s in the night." % _compass(int(captive["from"]), int(captive["loc"])))
			if String(captive["stage"]) in ["sold", "held", "conscripted"]:
				_add_lead("lead:family_market", "Someone at the roadhouse remembers a buyer in a grey coat asking about two new hands.")
		captive["stage_day"] = maxi(0, total_days)
		if String(captive["stage"]) == "forced_labour":
			var r3 := _rng("cap_cu", day, "x")
			var weeks_l := maxf(0.0, weeks - 1.0)
			for role: String in captive["who"]:
				var p := _parent(role)
				if p.is_empty() or not bool(p["alive"]):
					p["status"] = "dead"
					continue
				p["status"] = "forced_labour"
				p["health"] = clampf(float(p["health"]) - 0.02 * weeks_l, 0.02, 1.0)
				var hz := 0.006 * (1.6 - float(p["health"]))
				if r3.randf() < 1.0 - pow(1.0 - hz, weeks_l * 7.0):
					kill_parent(role, "captivity", out)
			if not bool(captive["rescued"]) and r3.randf() < 1.0 - pow(0.95, weeks_l):
				_free_captives("Your parents escaped forced labour and made their way home.")
				out.append("While you were away your parents escaped their captors and came home, changed.")
	if not displaced_state.is_empty() and not bool(displaced_state["free"]):
		var ds: Dictionary = displaced_state
		ds["days"] = int(ds["days"]) + days
		var r4 := _rng("disp_cu", day, "x")
		if r4.randf() < 1.0 - pow(0.97, weeks) and String(ds["stage"]) != "captured":
			ds["free"] = true
			ds["stage"] = "rescued"
			out.append("You were let go from the labour gang, far from home.")
		else:
			ds["stage"] = "forced_labour"
	# Parents' fates: one closed-form roll each from the hazards at the start.
	for p: Dictionary in fam["parents"]:
		if not bool(p["alive"]):
			continue
		var h := hazards(String(p["id"]))
		var tot := float(h["total"])
		if tot <= 0.0:
			continue
		var r5 := _rng("pdeath_cu", day, String(p["id"]))
		if r5.randf() < 1.0 - pow(1.0 - minf(tot, 0.2), float(days)):
			var roll := r5.randf() * tot
			var cause := "disease"
			for k: String in h:
				if k == "total":
					continue
				roll -= float(h[k])
				if roll <= 0.0:
					cause = k
					break
			kill_parent(String(p["id"]), cause, out)
		else:
			p["health"] = clampf(float(p["health"]) + 0.003 * float(days) - (0.006 if bool(p["extra_job"]) else 0.0) * float(days), 0.05, 1.0)
	_weekly_sacrifice(int(day / 7))
	out.append_array(_flush_out())
	if out.size() > 6:
		out.resize(6)
	return out


# ---------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"player": player.duplicate(true), "pending_gold": pending_gold, "fam": fam.duplicate(true), "sacrifices": sacrifice_list.duplicate(true),
		"trip": trip_state.duplicate(true), "trip_log": trip_log.duplicate(true), "encounter": encounter.duplicate(true), "captive": captive.duplicate(true),
		"displaced": displaced_state.duplicate(true), "leads": leads_state.duplicate(true), "deaths": death_log.duplicate(true), "next_id": _next_id, "day": _day,
		"hour": _hour, "season_seen": _season_seen, "support": _student_support, "inited": _inited, "flush": _flush.duplicate()}


func deserialize(d: Dictionary) -> void:
	player = (d.get("player", player) as Dictionary).duplicate(true)
	pending_gold = int(d.get("pending_gold", 0))
	fam = (d.get("fam", {}) as Dictionary).duplicate(true)
	sacrifice_list = (d.get("sacrifices", []) as Array).duplicate(true)
	trip_state = (d.get("trip", {}) as Dictionary).duplicate(true)
	trip_log = (d.get("trip_log", []) as Array).duplicate(true)
	encounter = (d.get("encounter", {}) as Dictionary).duplicate(true)
	captive = (d.get("captive", {}) as Dictionary).duplicate(true)
	displaced_state = (d.get("displaced", {}) as Dictionary).duplicate(true)
	leads_state = (d.get("leads", {}) as Dictionary).duplicate(true)
	death_log = (d.get("deaths", []) as Array).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	_day = int(d.get("day", 0))
	_hour = int(d.get("hour", 8))
	_season_seen = String(d.get("season_seen", ""))
	_student_support = float(d.get("support", 0.0))
	_inited = bool(d.get("inited", false))
	_flush = (d.get("flush", []) as Array).duplicate()
