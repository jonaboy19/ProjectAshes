extends "res://scripts/realm/realm_module.gd"
## R§6 settlement identity drift, R§37 emergencies with response windows,
## R§36 absence digest, and per-settlement supply chains seeded from
## WorldGen.settlements. Pure data; JSON-safe save.

const IDENTITIES := ["merchant", "fortress", "religious", "farming", "mining", "scholarly", "criminal"]
## structure kind -> {identity: weight per building}
const STRUCT_WEIGHT := {
	"farm": {"farming": 1.0}, "mill": {"farming": 0.6, "merchant": 0.2},
	"market": {"merchant": 2.0}, "warehouse": {"merchant": 1.0}, "dock": {"merchant": 1.5},
	"wall": {"fortress": 2.0}, "barracks": {"fortress": 1.5}, "tower": {"fortress": 1.0}, "gate": {"fortress": 0.7},
	"temple": {"religious": 2.5}, "shrine": {"religious": 1.0},
	"mine": {"mining": 2.0}, "forge": {"mining": 1.0},
	"library": {"scholarly": 2.5}, "school": {"scholarly": 1.5},
	"tavern": {"criminal": 0.3, "merchant": 0.3}, "den": {"criminal": 2.5}, "smithy": {"mining": 0.4},
}
## resident occupation share -> identity weights (per resident fraction).
const OCC_WEIGHT := {
	"farmer": {"farming": 4.0}, "merchant": {"merchant": 5.0}, "soldier": {"fortress": 5.0},
	"priest": {"religious": 8.0}, "miner": {"mining": 5.0}, "scholar": {"scholarly": 8.0}, "thief": {"criminal": 8.0},
}
const DRIFT_PER_DAY := 0.06
const IDENTITY_K := 3.0
const FOOD_PER_RESIDENT := 0.0016         # bread-equivalents per resident per day
const STOCK_CAP := 4000.0
## Natural recovery: logistic growth (per day) of pop toward its seeded carrying capacity while the place
## is fed. Emergencies only ever subtracted people before (balance run: -29% in two years), so this closes
## the ratchet; the equilibrium sits at roughly 1 - loss_rate / POP_REGROWTH of the seeded size.
const POP_REGROWTH := 0.005

## chain id -> {inputs, outputs, per_day (at 100 workers-equivalents)}
const CHAINS := {
	"farm": {"inputs": {}, "outputs": {"grain": 1.0}, "seasonal": true},
	"woodcutter": {"inputs": {}, "outputs": {"wood": 1.0}},
	"fishery": {"inputs": {}, "outputs": {"fish": 0.6}},
	"mine": {"inputs": {}, "outputs": {"ore": 0.8}},
	"mill": {"inputs": {"grain": 1.0}, "outputs": {"flour": 0.9}},
	"bakery": {"inputs": {"flour": 1.0, "wood": 0.15}, "outputs": {"bread": 1.3}},
	"smelter": {"inputs": {"ore": 1.0, "wood": 0.5}, "outputs": {"iron": 0.6}},
	"smithy": {"inputs": {"iron": 0.5, "wood": 0.2}, "outputs": {"tools": 0.5}},
}
const SEASON_FARM := {"spring": 0.5, "summer": 1.0, "autumn": 2.0, "winter": 0.1}

const EMERGENCY := {
	"fire": {"window": 8, "cost": 30, "text": "A fire is spreading through %s."},
	"plague": {"window": 96, "cost": 80, "text": "Sickness is spreading in %s."},
	"famine": {"window": 120, "cost": 100, "text": "%s is running out of food."},
	"strike": {"window": 72, "cost": 50, "text": "Workers in %s have downed tools."},
	"raid_aftermath": {"window": 48, "cost": 60, "text": "%s is reeling from a raid."},
}
const EMERGENCY_MAX := 12

## sid -> {identity:{..}, residents:{occ:n}, structures:{kind:n}, chains:{id:n_units},
##         stock:{item:float}, shortage:{item:days}, trade:float, pop:int}
var _s: Dictionary = {}
var _emerg: Array = []
var _next_emerg := 1
var _digest: Array = []
var _inited := false


func _rng(tag: String, day: int, id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _ensure() -> void:
	if _inited:
		return
	_inited = true
	for s in WorldGen.settlements:
		_seed_settlement(s)


func _seed_settlement(s: Dictionary) -> void:
	var sid: int = s["id"]
	var kind: String = s["kind"]
	var pop: int = s["population"]
	var r := _rng("seed", 0, sid)
	var st := {}
	var chains := {}
	var units := maxi(1, pop / 40)
	match kind:
		"castle":
			st = {"wall": 3, "barracks": 3, "market": 2, "temple": 1, "gate": 2, "tower": 3}
			chains = {"farm": units / 2, "mill": 3, "bakery": 4, "smithy": 3, "woodcutter": 2}
		"town":
			st = {"market": 2, "warehouse": 2, "temple": 1, "tavern": 2, "gate": 1}
			chains = {"farm": units, "mill": 2, "bakery": 3, "smithy": 2, "woodcutter": 2}
		"frontier_town":
			st = {"wall": 2, "tower": 2, "barracks": 1, "gate": 1}
			chains = {"farm": units, "woodcutter": 2, "mill": 1, "bakery": 1}
		_:
			st = {"farm": 0, "market": 1 if r.randf() < 0.4 else 0, "shrine": 1}
			chains = {"farm": units, "woodcutter": 1, "mill": 1, "bakery": 1}
	st["farm"] = int(chains.get("farm", 0))
	var flavour := r.randi() % 4
	if flavour == 0:
		st["mine"] = 2
		chains["mine"] = 2
		chains["smelter"] = 1
		chains["smithy"] = maxi(1, int(chains.get("smithy", 0)))
	elif flavour == 1:
		chains["fishery"] = 2
		st["dock"] = 1
	elif flavour == 2 and pop >= 700:
		st["library"] = 1
	var occ := {
		"farmer": int(pop * (0.6 if kind == "village" else 0.3)),
		"merchant": int(pop * (0.04 if kind == "village" else 0.14)),
		"soldier": int(pop * (0.20 if kind in ["castle", "frontier_town"] else 0.03)),
		"priest": int(pop * 0.015), "miner": int(pop * (0.15 if st.has("mine") else 0.0)),
		"scholar": int(pop * (0.03 if st.has("library") else 0.005)),
		"thief": int(pop * (0.02 + 0.03 * r.randf())),
	}
	var stock := {}
	for it in ["grain", "flour", "bread", "wood", "fish", "ore", "iron", "tools"]:
		stock[it] = 0.0
	stock["bread"] = pop * FOOD_PER_RESIDENT * (20.0 + 20.0 * r.randf())
	stock["grain"] = pop * FOOD_PER_RESIDENT * (10.0 + 20.0 * r.randf())
	stock["wood"] = 40.0 + 60.0 * r.randf()
	stock["iron"] = 8.0 + 10.0 * r.randf()
	stock["flour"] = 10.0
	_s[sid] = {"identity": {}, "residents": occ, "structures": st, "chains": chains, "stock": stock,
		"shortage": {}, "trade": 0.2 if kind == "village" else 0.6, "pop": pop, "kind": kind, "cap": pop}
	_s[sid]["identity"] = _target_identity(_s[sid])
	# Rounded so identities start settled, then drift with change.


func _target_identity(d: Dictionary) -> Dictionary:
	var raw := {}
	for i in IDENTITIES:
		raw[i] = 0.0
	for k in d["structures"]:
		var w: Dictionary = STRUCT_WEIGHT.get(k, {})
		for i in w:
			raw[i] += w[i] * float(d["structures"][k]) * (0.35 if k == "farm" else 1.0)
	raw["merchant"] += d["trade"] * 4.0
	var pop := maxf(1.0, float(d["pop"]))
	for o in d["residents"]:
		var w: Dictionary = OCC_WEIGHT.get(o, {})
		var share := float(d["residents"][o]) / pop
		for i in w:
			raw[i] += w[i] * share * 5.0
	var out := {}
	for i in IDENTITIES:
		out[i] = raw[i] / (raw[i] + IDENTITY_K)
	return out


# --------------------------------------------------------------- getters

func settlement_ids() -> Array:
	_ensure()
	var k := _s.keys()
	k.sort()
	return k


func identity(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("identity", {})


## Highest-scoring identity. A fortress beats a bigger town on military weight.
func dominant(sid: int) -> String:
	var idt := identity(sid)
	var best := ""
	var bv := -1.0
	for i in IDENTITIES:
		if float(idt.get(i, 0.0)) > bv:
			bv = idt[i]
			best = i
	return best


func stock(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("stock", {})


func supply_of(sid: int, item: String) -> float:
	return float(stock(sid).get(item, 0.0))


func shortages(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("shortage", {})


func emergencies(sid := -1) -> Array:
	if sid < 0:
		return _emerg
	return _emerg.filter(func(e: Dictionary) -> bool: return int(e["sid"]) == sid)


func digest() -> Array:
	return _digest


func population(sid: int) -> int:
	_ensure()
	return int(_s.get(sid, {}).get("pop", 0))


func sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "settlement %d" % sid


# --------------------------------------------------------------- lifecycle hooks (realm/civilization.gd, migration.gd)

## Carrying capacity the logistic regrowth aims at (civilization raises it with housing and boom, lowers it in decline).
func capacity(sid: int) -> int:
	_ensure()
	return _pop_cap(sid, _s[sid]) if _s.has(sid) else 0


func set_capacity(sid: int, cap: int) -> void:
	_ensure()
	if _s.has(sid):
		_s[sid]["cap"] = maxi(0, cap)


func residents(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("residents", {})


func structures(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("structures", {})


func chains(sid: int) -> Dictionary:
	_ensure()
	return _s.get(sid, {}).get("chains", {})


func trade_level(sid: int) -> float:
	_ensure()
	return float(_s.get(sid, {}).get("trade", 0.0))


func set_chain(sid: int, chain: String, n: int) -> void:
	_ensure()
	if _s.has(sid):
		_s[sid]["chains"][chain] = maxi(0, n)


## Moves the population by `delta` (negative = emigration/decline), spread over the occupations in proportion
## (stochastic rounding from `r`). `bias` optionally steers arrivals to one occupation. Unlike _loss there is no floor of 20.
func adjust_population(sid: int, delta: int, r: RandomNumberGenerator, bias := "") -> int:
	_ensure()
	if not _s.has(sid) or delta == 0:
		return 0
	var d: Dictionary = _s[sid]
	var res: Dictionary = d["residents"]
	if delta > 0:
		if bias != "" and OCC_WEIGHT.has(bias):
			res[bias] = int(res.get(bias, 0)) + delta
		else:
			var total := 0.0
			for o in res:
				total += float(res[o])
			var given := 0
			for o in res:
				var share := float(res[o]) / maxf(total, 1.0)
				var n := int(delta * share)
				res[o] = int(res[o]) + n
				given += n
			res["farmer"] = int(res.get("farmer", 0)) + (delta - given)
		d["pop"] = int(d["pop"]) + delta
		return delta
	var take := mini(-delta, int(d["pop"]))
	var total2 := 0.0
	for o in res:
		total2 += float(res[o])
	var removed := 0
	for o in res:
		var exp_n := float(take) * float(res[o]) / maxf(total2, 1.0)
		var n := mini(int(res[o]), int(exp_n) + (1 if r.randf() < exp_n - floorf(exp_n) else 0))
		res[o] = int(res[o]) - n
		removed += n
	d["pop"] = maxi(0, int(d["pop"]) - removed)
	return -removed


# --------------------------------------------------------------- hooks other modules/player use

func add_structure(sid: int, kind: String, n := 1) -> void:
	_ensure()
	if _s.has(sid):
		var st: Dictionary = _s[sid]["structures"]
		st[kind] = int(st.get(kind, 0)) + n
		if CHAINS.has(kind):
			var ch: Dictionary = _s[sid]["chains"]
			ch[kind] = int(ch.get(kind, 0)) + n


func add_residents(sid: int, occupation: String, n: int) -> void:
	_ensure()
	if _s.has(sid):
		var d: Dictionary = _s[sid]
		d["residents"][occupation] = maxi(0, int(d["residents"].get(occupation, 0)) + n)
		d["pop"] = maxi(0, int(d["pop"]) + n)


func add_stock(sid: int, item: String, amount: float) -> void:
	_ensure()
	if _s.has(sid):
		var st: Dictionary = _s[sid]["stock"]
		st[item] = clampf(float(st.get(item, 0.0)) + amount, 0.0, STOCK_CAP)


func set_trade(sid: int, level: float) -> void:
	_ensure()
	if _s.has(sid):
		_s[sid]["trade"] = clampf(level, 0.0, 2.0)


## Raid aftermath is triggered by strongholds/campaign/war.
func raid_aftermath(sid: int, severity := 0.5) -> void:
	_ensure()
	if _s.has(sid):
		_start(sid, "raid_aftermath", severity)


func _start(sid: int, kind: String, severity: float) -> Dictionary:
	for e in _emerg:
		if int(e["sid"]) == sid and e["kind"] == kind:
			return {}
	if _emerg.size() >= EMERGENCY_MAX:
		return {}
	var def: Dictionary = EMERGENCY[kind]
	var e := {"id": _next_emerg, "sid": sid, "kind": kind, "severity": clampf(severity, 0.1, 1.0),
		"hours_left": int(def["window"]), "cost": int(def["cost"] * (0.5 + severity)), "paid": 0}
	_next_emerg += 1
	_emerg.append(e)
	return e


## Respond to an emergency with gold (or labour valued in gold). Fully paying
## resolves it; partial help lowers its severity. Returns a Game.say line.
func respond(eid: int, gold: int) -> String:
	for e in _emerg:
		if int(e["id"]) != eid:
			continue
		e["paid"] = int(e["paid"]) + maxi(gold, 0)
		var name := sname(int(e["sid"]))
		if int(e["paid"]) >= int(e["cost"]):
			_emerg.erase(e)
			# Helping is remembered.
			var land := _mod("land")
			if land != null:
				land.remember(int(e["sid"]), "relief", 0.5 * float(e["severity"]))
			return "You saved %s from the %s." % [name, String(e["kind"]).replace("_", " ")]
		e["severity"] = maxf(0.1, float(e["severity"]) * 0.8)
		return "%s: %d more gold would end the %s." % [name, int(e["cost"]) - int(e["paid"]), String(e["kind"]).replace("_", " ")]
	return ""


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _ignored(e: Dictionary) -> String:
	## Consequences of an unanswered emergency; returns a line.
	var sid: int = e["sid"]
	var d: Dictionary = _s.get(sid, {})
	if d.is_empty():
		return ""
	var sev: float = e["severity"]
	var name := sname(sid)
	var land := _mod("land")
	match String(e["kind"]):
		"fire":
			var lost := 0
			for k in ["market", "warehouse", "farm", "mill"]:
				if int(d["structures"].get(k, 0)) > 0 and lost < 1 + int(sev * 2):
					d["structures"][k] -= 1
					lost += 1
			for it in d["stock"]:
				d["stock"][it] = float(d["stock"][it]) * (1.0 - 0.5 * sev)
			_loss(d, 0.01 * sev)
			if land != null:
				land.remember(sid, "neglect", 0.3 * sev)
			return "The fire in %s burned unchecked; buildings and stores are lost." % name
		"plague":
			_loss(d, 0.06 * sev)
			if land != null:
				land.remember(sid, "neglect", 0.5 * sev)
			return "The sickness took many lives in %s." % name
		"famine":
			_loss(d, 0.05 * sev)
			if land != null:
				land.remember(sid, "neglect", 0.6 * sev)
			return "People starved in %s; many have left." % name
		"strike":
			d["trade"] = maxf(0.0, d["trade"] - 0.3 * sev)
			return "The strike in %s ground trade to a halt." % name
		_:
			_loss(d, 0.03 * sev)
			d["stock"]["grain"] = float(d["stock"].get("grain", 0.0)) * (1.0 - 0.4 * sev)
			if land != null:
				land.remember(sid, "neglect", 0.3 * sev)
			return "%s was left to bury its dead after the raid." % name


## Carrying capacity: the seeded population (saves from before `cap` existed fall back to the world seed).
func _pop_cap(sid: Variant, d: Dictionary) -> int:
	if d.has("cap"):
		return int(d["cap"])
	var c := int(d["pop"])
	if int(sid) >= 0 and int(sid) < WorldGen.settlements.size():
		c = maxi(c, int(WorldGen.settlements[int(sid)]["population"]))
	d["cap"] = c
	return c


## Closed-form logistic regrowth over `days`; new people are spread over the occupations (stochastic
## rounding, seeded) so residents keep summing to pop. No growth while the settlement is short of food.
func _regrow(sid: Variant, d: Dictionary, days: float, r: RandomNumberGenerator) -> void:
	if d["shortage"].has("food"):
		return
	var cap := float(_pop_cap(sid, d))
	var p0 := float(d["pop"])
	if p0 >= cap or p0 < 1.0:
		return
	var p1 := cap / (1.0 + (cap / p0 - 1.0) * exp(-POP_REGROWTH * days))
	var add := p1 - p0
	var total := 0.0
	for o in d["residents"]:
		total += float(d["residents"][o])
	if total <= 0.0 or add <= 0.0:
		return
	var added := 0
	for o in d["residents"]:
		var exp_n := add * float(d["residents"][o]) / total
		var n := int(exp_n) + (1 if r.randf() < exp_n - floorf(exp_n) else 0)
		d["residents"][o] = int(d["residents"][o]) + n
		added += n
	d["pop"] = int(d["pop"]) + added


func _loss(d: Dictionary, frac: float) -> void:
	var lost := int(d["pop"] * frac)
	d["pop"] = maxi(20, int(d["pop"]) - lost)
	for o in d["residents"]:
		d["residents"][o] = int(int(d["residents"][o]) * (1.0 - frac))


# --------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	var i := _emerg.size() - 1
	while i >= 0:
		var e: Dictionary = _emerg[i]
		e["hours_left"] -= 1
		if e["hours_left"] <= 0:
			var line := _ignored(e)
			if line != "":
				out.append(line)
			_emerg.remove_at(i)
		i -= 1
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## One chunk per settlement, in sid order (the same loop tick_day always ran).
func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_ensure()
	var ids := _s.keys()
	ids.sort()
	var chunks: Array = []
	for sid in ids:
		chunks.append(func() -> Array: return _tick_day_one(sid, day, ctx))
	return chunks


func _tick_day_one(sid: Variant, day: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var season: String = str(ctx.get("season", "spring"))
	var at_war: bool = bool(ctx.get("at_war", false))
	var d: Dictionary = _s[sid]
	_run_chains(d, SEASON_FARM.get(season, 1.0), 1.0)
	_eat(d, 1.0)
	var tgt := _target_identity(d)
	for i in IDENTITIES:
		d["identity"][i] += (tgt[i] - d["identity"][i]) * DRIFT_PER_DAY
	var r := _rng("emerg", day, sid)
	_regrow(sid, d, 1.0, _rng("grow", day, int(sid)))
	var roll := r.randf()
	var kind := ""
	var bread: float = d["stock"].get("bread", 0.0) + d["stock"].get("grain", 0.0) * 0.6
	var starving: bool = int(d["shortage"].get("food", 0)) >= 3
	if starving:
		kind = "famine"
	elif roll < 0.010 + (0.010 if season == "summer" else 0.0) + 0.000005 * d["pop"]:
		kind = "fire"
	elif roll < 0.016 + 0.000004 * d["pop"] and (bread < d["pop"] * FOOD_PER_RESIDENT * 6.0 or season == "winter"):
		kind = "plague"
	elif int(d["shortage"].get("tools", 0)) + int(d["shortage"].get("bread", 0)) >= 5 and r.randf() < 0.2:
		kind = "strike"
	elif at_war and d["kind"] in ["frontier_town", "village"] and r.randf() < 0.02:
		kind = "raid_aftermath"
	if kind != "":
		var e := _start(int(sid), kind, 0.3 + 0.7 * r.randf())
		if not e.is_empty():
			out.append(EMERGENCY[kind]["text"] % sname(int(sid)))
	return out


func _run_chains(d: Dictionary, farm_mult: float, days: float) -> void:
	var stock: Dictionary = d["stock"]
	var pop_f := clampf(float(d["pop"]) / 200.0, 0.3, 4.0)
	for cid in ["farm", "woodcutter", "fishery", "mine", "mill", "bakery", "smelter", "smithy"]:
		var n := int(d["chains"].get(cid, 0))
		if n <= 0:
			continue
		var def: Dictionary = CHAINS[cid]
		var scale := float(n) * 4.0 * days * (farm_mult if def.get("seasonal", false) else 1.0)
		scale = minf(scale, 400.0 * days)
		# Limit by available inputs.
		for it in def["inputs"]:
			scale = minf(scale, float(stock.get(it, 0.0)) / float(def["inputs"][it]))
		if scale <= 0.0:
			var ins: Dictionary = def["inputs"]
			for it in ins:
				if float(stock.get(it, 0.0)) < 0.5:
					d["shortage"][it] = int(d["shortage"].get(it, 0)) + 1
			continue
		for it in def["inputs"]:
			stock[it] = float(stock[it]) - scale * float(def["inputs"][it])
		for it in def["outputs"]:
			stock[it] = minf(STOCK_CAP, float(stock.get(it, 0.0)) + scale * float(def["outputs"][it]))
	pop_f = pop_f  # kept for tuning hooks


func _eat(d: Dictionary, days: float) -> void:
	var need: float = d["pop"] * FOOD_PER_RESIDENT * days * 25.0
	var stock: Dictionary = d["stock"]
	for it in ["bread", "grain", "fish"]:
		var have: float = stock.get(it, 0.0)
		var take := minf(have, need)
		stock[it] = have - take
		need -= take
		if need <= 0.0:
			break
	if need > 0.01:
		d["shortage"]["food"] = int(d["shortage"].get("food", 0)) + 1
		d["shortage"]["bread"] = int(d["shortage"].get("bread", 0)) + 1
	else:
		d["shortage"].erase("food")
		d["shortage"].erase("bread")
	if float(stock.get("tools", 0.0)) < 0.5 and int(d["structures"].get("smithy", 0)) > 0:
		d["shortage"]["tools"] = int(d["shortage"].get("tools", 0)) + 1
	else:
		d["shortage"].erase("tools")


## R§36: resolves `days` away in O(settlements): net chain rates, closed-form
## identity drift, statistical emergencies. Fills digest() and returns lines.
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	_digest = []
	if days < 1:
		return _digest
	var season: String = str(ctx.get("season", "spring"))
	var fm: float = SEASON_FARM.get(season, 1.0)
	var decay := 1.0 - pow(1.0 - DRIFT_PER_DAY, float(days))
	var ids := _s.keys()
	ids.sort()
	var day0 := int(ctx.get("abs_hours", 0)) / 24
	for sid in ids:
		var d: Dictionary = _s[sid]
		var before_food: float = d["stock"].get("bread", 0.0) + d["stock"].get("grain", 0.0)
		# Production and eating are linear in the window: one step with days scale,
		# capped at 30 days so nothing runs away.
		var span := float(mini(days, 30))
		_run_chains(d, fm, span)
		_eat(d, span)
		_regrow(sid, d, float(days), _rng("grow_away", day0, int(sid)))
		var tgt := _target_identity(d)
		for i in IDENTITIES:
			d["identity"][i] += (tgt[i] - d["identity"][i]) * decay
		var after_food: float = d["stock"].get("bread", 0.0) + d["stock"].get("grain", 0.0)
		var name := sname(int(sid))
		if int(d["shortage"].get("food", 0)) > 0 and before_food > after_food:
			_digest.append("Food ran short in %s while you were away." % name)
		elif after_food > before_food * 1.5 + 50.0:
			_digest.append("%s has stores to spare after a good spell." % name)
		# Emergencies: chance grows with days; the unanswered ones already played out.
		var r := _rng("away", day0, int(sid))
		var p := 1.0 - pow(1.0 - 0.012, float(days))
		if r.randf() < p:
			var kinds := ["fire", "plague", "strike", "famine"]
			var kind: String = kinds[r.randi() % kinds.size()]
			if kind == "famine" and int(d["shortage"].get("food", 0)) == 0:
				kind = "fire"
			var e := {"sid": sid, "severity": 0.3 + 0.7 * r.randf(), "kind": kind}
			var w: int = EMERGENCY[kind]["window"]
			if days * 24 > w:
				var line := _ignored(e)
				if line != "":
					_digest.append(line)
			else:
				var ne := _start(int(sid), kind, e["severity"])
				if not ne.is_empty():
					ne["hours_left"] = maxi(1, w - days * 24)
					_digest.append(EMERGENCY[kind]["text"] % name)
	# Emergencies already open have aged.
	var i2 := _emerg.size() - 1
	while i2 >= 0:
		var e2: Dictionary = _emerg[i2]
		e2["hours_left"] -= days * 24
		if e2["hours_left"] <= 0:
			var l2 := _ignored(e2)
			if l2 != "":
				_digest.append(l2)
			_emerg.remove_at(i2)
		i2 -= 1
	if _digest.size() > 8:
		_digest.resize(8)
	return _digest.duplicate()


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	var sd := {}
	for k in _s:
		sd[str(k)] = _s[k].duplicate(true)
	return {"s": sd, "emerg": _emerg.duplicate(true), "next_emerg": _next_emerg,
		"digest": _digest.duplicate(), "inited": _inited}


func deserialize(d: Dictionary) -> void:
	_s = {}
	for k in d.get("s", {}):
		_s[int(k)] = (d["s"][k] as Dictionary).duplicate(true)
	_emerg = (d.get("emerg", []) as Array).duplicate(true)
	_next_emerg = int(d.get("next_emerg", 1))
	_digest = (d.get("digest", []) as Array).duplicate()
	_inited = bool(d.get("inited", false))
