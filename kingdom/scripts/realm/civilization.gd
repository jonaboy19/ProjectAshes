extends "res://scripts/realm/realm_module.gd"
## CIV-A (docs/design/CIVILIZATION.md): settlement lifecycle. Every settlement, static (WorldGen) or founded along the way
## (a realm/camps.gd camp), is a "place" that grows and dies from pressure:
##   tier      camp -> outpost -> village -> town -> city -> trade hub, or ruin; promoted/demoted with hysteresis
##   pressure  housing / food / jobs supply-demand ratios; safety from the runestone network; roads from camps.gd
##   boom      a discovery (iron, rift crystal, monster parts) draws inflow waves, crime and prices
##   decline   finite deposits run dry, routes are lost, runestones fail: attraction falls and the place shrinks
##   projects  houses, walls, market, mine, road, runestone extension... queued by need and treasury, each a staged
##             realm/construction.gd NPC site whose stage is a pure function of the day
##   founding  new camps appear along safe routes / near finds (cap DYNAMIC_CAP), then climb the tiers themselves
## Extends realm/settlements.gd (capacity, residents, chains, stock), sim/runestone_network.gd, realm/camps.gd, realm/construction.gd
## and sim/economy.gd (price multiplier). People moving between places is realm/migration.gd.
##
## Time: every step is closed-form in `n` days (exp relaxation, linear depletion), so the daily tick is `n = 1` and catch_up is
## a handful of larger steps: O(places), never O(days * places).

const SettlementsScript := preload("res://scripts/realm/settlements.gd")
const D := preload("res://scripts/realm/construction_data.gd")

const TIERS := ["camp", "outpost", "village", "town", "city", "trade hub"]
const TIER_POP := [0, 35, 110, 380, 1300, 1900]              # population that earns tier i
const TIER_SAFETY := [0.0, 0.12, 0.22, 0.30, 0.38, 0.42]     # safety needed to climb into tier i
const DOWN_FRAC := 0.78                                      # a place falls a tier below this share of its threshold
const PROMOTE_DAYS := 20.0
const DEMOTE_DAYS := 45.0
const RUIN_POP := 6
const RUIN_DAYS := 60.0
const DYNAMIC_CAP := 12
const FARM_FEEDS_STATIC := 68.0                              # what a chain farm feeds in settlements.gd (4 grain/day x 0.94 seasons / 0.04 a head, less milling loss)
const FARM_FEEDS := 40.0                                     # people one farm unit feeds
const FARM_JOBS := 14.0
const SERVICE := 0.25                                        # shop/smith/carter jobs per resident at full trade
const OCCUPANCY := 0.9                                       # neutral pop / housing
const GROW_RATE := 0.0034
const SHRINK_RATE := 0.0055
const MAX_NEWS := 60
const CAMP_FAIL_P := 0.0012             # weekly base chance a young camp is given up (scaled up by danger, poor safety and unrest)
const FOUND_P := 0.06                   # weekly chance that founders set out (about 1.5 camps a year)
const FOUND_FROM := 120                 # no frontier camps in the first months of a world
const FOUND_GAP := 75                   # days between two foundings, whoever founds
const ECO_DANGER := 0.6                 # share of ecology danger_level (0..1) that weighs on a place as monster pressure
const ECO_PROSPERITY := 0.04            # attraction from an adventurer economy (inns, healers, bounties)
const NEWS_MAG := {"boom": 2.0, "founded": 1.5, "tier_up": 1.5, "tier_down": 1.5, "ruin": 2.5, "route_lost": 1.2, "depleted": 1.2, "resettled": 1.5, "project": 0.8, "failed": 1.5}
const MAX_HISTORY := 6
const KEEP_DONE_SITES := 40

## project kind -> {cost, days, site (construction catalog kind by tier band), label, per_pop (cost growth), max (per place)}
const PROJECTS := {
	"house": {"cost": 90.0, "per_pop": 0.5, "days": 26.0, "label": "houses", "max": 99},
	"well": {"cost": 70.0, "per_pop": 0.0, "days": 12.0, "label": "a well", "max": 1},
	"irrigation": {"cost": 160.0, "per_pop": 0.2, "days": 40.0, "label": "irrigation ditches", "max": 3},
	"guards": {"cost": 160.0, "per_pop": 0.3, "days": 30.0, "label": "a guard post", "max": 3},
	"wall": {"cost": 260.0, "per_pop": 0.8, "days": 70.0, "label": "a wall", "max": 3},
	"market": {"cost": 330.0, "per_pop": 0.4, "days": 60.0, "label": "a market", "max": 1},
	"mine": {"cost": 300.0, "per_pop": 0.0, "days": 70.0, "label": "a mine", "max": 3},
	"runestone": {"cost": 260.0, "per_pop": 0.0, "days": 45.0, "label": "a runestone extension", "max": 4},
	"road": {"cost": 240.0, "per_pop": 0.0, "days": 45.0, "label": "a road", "max": 3},
	"school": {"cost": 480.0, "per_pop": 0.5, "days": 120.0, "label": "a school", "max": 1},
	"bridge": {"cost": 560.0, "per_pop": 0.0, "days": 90.0, "label": "a bridge", "max": 1},
	"port": {"cost": 680.0, "per_pop": 0.0, "days": 160.0, "label": "a port", "max": 1},
}
const PROJECT_ORDER := ["house", "well", "irrigation", "guards", "wall", "market", "mine", "runestone", "road", "school", "bridge", "port"]
## Gold value of a worker-day of each resource; discovery kinds.
const RESOURCE_VALUE := {"iron": 0.3, "silver": 0.6, "rift_crystal": 1.0, "monster_parts": 0.45, "timber": 0.15}
const FIND_KINDS := ["iron", "iron", "silver", "rift_crystal", "monster_parts"]
const NAME_A := ["Iron", "Ash", "Raven", "Stone", "Fern", "Hollow", "Wolf", "Copper", "Sun", "Mist", "Elder", "Bright", "Cinder", "Gale", "Amber", "Thorn"]
const NAME_B := ["watch", "ford", "stead", "hollow", "rest", "cross", "wick", "haven", "barrow", "gate", "mere", "field"]
const FOUNDERS := ["a band of hunters", "a prospector and her crew", "a merchant's guild", "a company of adventurers", "a veteran captain and his men", "a hedge-priest and her flock"]

## Test/sim hook: a runestone network to read instead of Frontier's.
var runestones: RefCounted = null
## Scenario control: places that never get a random prospector's find (tests, the balance sim).
var no_finds: Dictionary = {}

## node -> place (see _new_place).
var _places: Dictionary = {}
var _projects: Dictionary = {}          # int id -> project
var _next_project := 1
var _finds: Array = []                  # undeveloped discoveries in the wild: {id,pos,kind,rich,day}
var _next_find := 1
var _blocked: Dictionary = {}           # edge key -> day the lost route reopens
var _isolated: Dictionary = {}          # node -> day it is reconnected (a town the world forgot)
var _news: Array = []
var _next_news := 1
var _seq := 0                           # news.gd cursor counter (= last event id)
var _digest: Array = []
var _day := 0
var _inited := false
var _ids_cache: Array = []               # transient: sorted place ids
var _adj: Dictionary = {}               # transient: node -> [edge]
var _adj_n := -1
var _adj_day := -999
const _NO_EDGES: Array = []
var prof_on := false                    # profiling hook for the balance sim: section -> [calls, usec]
var prof: Dictionary = {}


func _pf(key: String, t0: int) -> int:
	if prof_on:
		var e: Array = prof.get(key, [0, 0])
		e[0] += 1
		e[1] += Time.get_ticks_usec() - t0
		prof[key] = e
		return Time.get_ticks_usec()
	return 0



func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _rs() -> RefCounted:
	if runestones != null:
		return runestones
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var f: Node = (ml as SceneTree).root.get_node_or_null("Frontier")
		if f != null:
			return f.get("runestones") as RefCounted
	return null


func _coverage(pos: Vector2) -> float:
	var rs := _rs()
	return float(rs.call("coverage", pos)) if rs != null else 0.0


# --------------------------------------------------------------- seeding

func _ensure() -> void:
	if _inited:
		return
	_inited = true
	var stl := _mod("settlements")
	if stl != null:
		stl.call("_ensure")
	for s in WorldGen.settlements:
		var p := _seed_static(s)
		_places[String(p["node"])] = p


func _new_place(node: String, pname: String, pos: Vector2) -> Dictionary:
	return {"node": node, "name": pname, "dyn": false, "camp": -1, "sid": -1, "pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)],
		"tier": 0, "acc": 0.0, "since": 0, "last": -1, "popf": 0.0, "housing": 20.0, "jobs": 10.0, "farms": 0, "treasury": 0.0,
		"patrol": 0.05, "walls": 0, "built": {}, "res": [], "boom": {}, "crime": 0.1, "unrest": 0.0, "monster": 0.0, "war": 0.0,
		"famine": 0.0, "cut": 0.0, "stones": 0, "jobs_x": 0.0, "trade_x": 0.0, "road_x": 0.0, "food_x": 0.0, "ref": -1.0,
		"attr": 0.5, "S": 0.5, "F": 1.0, "J": 1.0, "R": 0.3, "H": 0.9, "ruin": false, "ruin_acc": 0.0, "ruin_day": -1,
		"fimp": 0.0, "inc": 0.0, "farms0": 0, "popc": 0.0, "cov": 0.0, "cov_day": -99, "rqR": 0.0, "rqL": 0, "rqT": 0.0, "rq_day": -99, "coast": -1, "defx": 0.0, "lead": 0.5, "lead_day": -99, "peak": 0, "abandoned": 0, "founded": 0, "founder": "", "hist": [], "maint": 0.0, "push": 0.0, "pull": 0.5,
		"refugees": 0, "proj": [], "pop_seed": 0}


func _seed_static(s: Dictionary) -> Dictionary:
	var sid: int = s["id"]
	var p := _new_place("s%d" % sid, String(s["name"]), s["pos"])
	var pop: int = s["population"]
	p["sid"] = sid
	p["pop_seed"] = pop
	p["peak"] = pop
	p["housing"] = float(pop) * 1.12
	p["treasury"] = float(pop) * 2.0
	p["tier"] = _tier_for_pop(pop)
	p["popf"] = float(pop)
	var stl := _mod("settlements")
	var r := _rng("seed", 0, sid)
	var cov := _coverage(s["pos"])
	var def := 0.0
	var jobs_dep := 0.0
	if stl != null:
		var st: Dictionary = stl.call("structures", sid)
		def = _struct_defence(st)
		p["farms"] = int((stl.call("chains", sid) as Dictionary).get("farm", 0))
		p["farms0"] = int(p["farms"])
		if int(st.get("mine", 0)) > 0:
			var wcap := 18.0 + float(pop) * 0.05
			var years := 12.0 + 18.0 * r.randf()
			var dep := {"kind": "iron", "reserve": wcap * 365.0 * years, "reserve0": wcap * 365.0 * years, "rich": 0.9, "wcap": wcap,
				"dev": true, "day": 0, "carry": 0.0}
			(p["res"] as Array).append(dep)
			jobs_dep = wcap
	p["patrol"] = maxf(0.0, 0.6 - 0.6 * cov - def)
	p["popc"] = float(pop)
	var rq := _road_quality(String(p["node"]), p, 0, 2.0)
	p["jobs"] = maxf(4.0, 0.69 * float(pop) - jobs_dep - FARM_JOBS * float(p["farms"]) - _service_jobs(p, float(rq["R"])))
	p["fimp"] = maxf(0.0, 1.08 * float(pop) - _food_cap(p, float(rq["R"])))
	return p


static func _struct_defence(st: Dictionary) -> float:
	return minf(0.25, 0.05 * float(st.get("wall", 0)) + 0.03 * float(st.get("tower", 0)) + 0.04 * float(st.get("barracks", 0)) + 0.02 * float(st.get("gate", 0)))


static func _tier_for_pop(pop: int) -> int:
	var t := 0
	for i in range(1, 5):   # trade hub is earned, never seeded
		if pop >= TIER_POP[i]:
			t = i
	return t


func _hid(node: String) -> int:
	return int(node.substr(1))


# --------------------------------------------------------------- public getters (UI / presentation / other modules)

func place_ids() -> Array:
	_ensure()
	if _ids_cache.size() != _places.size():
		_ids_cache = _places.keys()
		_ids_cache.sort_custom(func(a: String, b: String) -> bool: return a.substr(0, 1) + "%06d" % int(a.substr(1)) < b.substr(0, 1) + "%06d" % int(b.substr(1)))
	return _ids_cache


func has_place(node: String) -> bool:
	_ensure()
	return _places.has(node)


func place(node: String) -> Dictionary:
	_ensure()
	return _places.get(node, {})


func name_of(node: String) -> String:
	return String(place(node).get("name", node))


func population(node: String) -> int:
	_ensure()
	var p: Dictionary = _places.get(node, {})
	return 0 if p.is_empty() else _pop(p)


func tier(node: String) -> int:
	return int(place(node).get("tier", 0))


func tier_name(node: String) -> String:
	var p := place(node)
	if p.is_empty():
		return ""
	return "ruin" if bool(p["ruin"]) else String(TIERS[int(p["tier"])])


func is_ruin(node: String) -> bool:
	return bool(place(node).get("ruin", false))


## {housing, food, jobs}: supply / demand ratios (>1 is surplus), plus safety, attraction, unrest, crime.
func pressures(node: String) -> Dictionary:
	var p := place(node)
	if p.is_empty():
		return {}
	var pop := maxf(1.0, float(_pop(p)))
	return {"housing": snappedf(float(p["housing"]) / pop, 0.001), "food": snappedf(float(p["F"]), 0.001), "jobs": snappedf(float(p["J"]), 0.001),
		"safety": snappedf(float(p["S"]), 0.001), "roads": snappedf(float(p["R"]), 0.001), "attraction": snappedf(float(p["attr"]), 0.001),
		"unrest": snappedf(float(p["unrest"]), 0.001), "crime": snappedf(float(p["crime"]), 0.001), "cut_off": float(p["cut"]) > 20.0}


func boom_of(node: String, day := -1) -> Dictionary:
	var p := place(node)
	if p.is_empty() or (p["boom"] as Dictionary).is_empty():
		return {}
	var pw := _boom_power(p, _day if day < 0 else day)
	if pw <= 0.0:
		return {}
	return {"power": snappedf(pw, 0.001), "what": String((p["boom"] as Dictionary).get("what", "")), "until": int((p["boom"] as Dictionary)["start"]) + int((p["boom"] as Dictionary)["dur"])}


func deposits(node: String) -> Array:
	return (place(node).get("res", []) as Array).duplicate(true)


func projects(node := "") -> Array:
	var out: Array = []
	var ids := _projects.keys()
	ids.sort()
	for id: int in ids:
		var pr: Dictionary = _projects[id]
		if node == "" or String(pr["node"]) == node:
			out.append(pr)
	return out


func active_projects() -> Array:
	return projects().filter(func(pr: Dictionary) -> bool: return String(pr["state"]) != "done")


func ruins() -> Array:
	var out: Array = []
	for node in place_ids():
		var p: Dictionary = _places[node]
		if bool(p["ruin"]):
			out.append({"node": node, "name": String(p["name"]), "pos": Vector2(p["pos"][0], p["pos"][1]), "day": int(p["ruin_day"]), "was": String(TIERS[int(p["tier"])])})
	return out


func dynamic_count() -> int:
	_ensure()
	var n := 0
	for node: String in _places:
		if bool(_places[node]["dyn"]) and not bool(_places[node]["ruin"]):
			n += 1
	return n


func finds() -> Array:
	return _finds.duplicate(true)


func chronicle(node: String) -> Array:
	return (place(node).get("hist", []) as Array).duplicate()


func pos_of(node: String) -> Vector2:
	var p := place(node)
	return Vector2(p["pos"][0], p["pos"][1]) if not p.is_empty() else Vector2.ZERO


## Plain summary for UI: everything a settlement panel needs in one call.
func info(node: String) -> Dictionary:
	var p := place(node)
	if p.is_empty():
		return {}
	return {"node": node, "name": String(p["name"]), "tier": int(p["tier"]), "tier_name": tier_name(node), "pop": _pop(p), "dynamic": bool(p["dyn"]),
		"pressures": pressures(node), "boom": boom_of(node), "deposits": deposits(node), "projects": projects(node).filter(
			func(pr: Dictionary) -> bool: return String(pr["state"]) != "done"), "treasury": int(p["treasury"]), "founder": String(p["founder"]),
		"founded": int(p["founded"]), "ruin": bool(p["ruin"]), "refugees": int(p["refugees"]), "history": (p["hist"] as Array).duplicate()}


## Push/pull for migration.gd. Push: why people leave; pull: how much a place draws (less when it is already full).
func push_of(node: String) -> float:
	return float(place(node).get("push", 0.0))


func pull_of(node: String) -> float:
	return float(place(node).get("pull", 0.0))


func news_events(since := 0) -> Array:
	return _news if since <= 0 else _news.filter(func(e: Dictionary) -> bool: return int(e["seq"]) > since)


func news_since(last_id: int) -> Array:
	return _news.filter(func(e: Dictionary) -> bool: return int(e["id"]) > last_id)


func digest() -> Array:
	return _digest


# --------------------------------------------------------------- hooks other modules and the player use

## A find (rare Rift mineral, monster resource, a player discovery). Within reach of a place it becomes a boom there; in the
## wild it waits as a lead that founders look for.
func report_find(pos: Vector2, kind := "iron", rich := 0.7, day := -1) -> String:
	_ensure()
	var d := _day if day < 0 else day
	var best := ""
	var bd := 520.0
	for node: String in _places:
		var p: Dictionary = _places[node]
		if bool(p["ruin"]):
			continue
		var dist := pos.distance_to(Vector2(p["pos"][0], p["pos"][1]))
		if dist < bd:
			bd = dist
			best = node
	if best != "":
		discover(best, kind, rich, d)
		return best
	_finds.append({"id": _next_find, "pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)], "kind": kind, "rich": rich, "day": d})
	_next_find += 1
	if _finds.size() > 6:
		_finds.pop_front()
	return ""


## Deposit + boom at a place: attraction, inflow waves, crime and prices rise for a while.
func discover(node: String, kind := "iron", rich := 0.7, day := -1) -> void:
	_ensure()
	var p: Dictionary = _places.get(node, {})
	if p.is_empty() or bool(p["ruin"]):
		return
	var d := _day if day < 0 else day
	var wcap := 8.0 + 26.0 * rich
	var res0 := 60000.0 + 120000.0 * rich
	(p["res"] as Array).append({"kind": kind, "reserve": res0, "reserve0": res0, "rich": rich, "wcap": wcap, "dev": false, "day": d, "carry": 0.0})
	if (p["res"] as Array).size() > 4:
		(p["res"] as Array).pop_front()
	p["treasury"] = float(p["treasury"]) + 150.0 + 350.0 * rich   # investors and a prospector's claim fund the first works
	p["boom"] = {"start": d, "dur": int(540 + 360 * rich), "p0": clampf(0.45 + 0.55 * rich, 0.3, 1.0), "what": String(kind)}
	_news_add("boom", node, "%s has struck %s; word is spreading along the roads." % [String(kind).replace("_", " ").capitalize(), String(p["name"])], d)
	_hist(p, d, "%s found near the town" % String(kind).replace("_", " "))


## Something pushes people out (or keeps them away): "monster", "war", "famine", "rift", "law". Decays by itself.
func add_pressure(node: String, kind: String, amount: float) -> void:
	var p := place(node)
	if p.is_empty():
		return
	var key := "monster" if kind in ["monster", "monsters", "rift"] else ("war" if kind == "war" else "")
	if key != "":
		p[key] = clampf(float(p[key]) + amount, 0.0, 1.0)
	elif kind == "famine":
		p["famine"] = float(p["famine"]) + amount * 10.0
	elif kind == "law":
		p["unrest"] = clampf(float(p["unrest"]) + amount, 0.0, 1.0)


## Cuts the road(s) between two nodes for `days` (a rerouted caravan trade, a collapsed bridge, a sabotage). Returns edges cut.
func cut_route(a: String, b: String, days := 420) -> int:
	_ensure()
	var cm := _mod("camps")
	if cm == null:
		return 0
	var e: Dictionary = cm.call("road", a, b)
	if e.is_empty():
		return 0
	e["cond"] = 0.03
	_blocked[String(e["a"]) + "|" + String(e["b"])] = _day + days
	return 1


## Cuts every road of a place (a town the world forgot). Returns how many.
func isolate(node: String, days := 4000) -> int:
	_ensure()
	_isolated[node] = _day + days
	var cm := _mod("camps")
	var n := 0
	if cm == null:
		return 0
	for k: String in (cm.get("_edges") as Dictionary).keys():
		var e: Dictionary = cm.get("_edges")[k]
		if String(e["a"]) == node or String(e["b"]) == node:
			e["cond"] = 0.03
			_blocked[k] = _day + days
			n += 1
	return n


func is_isolated(node: String) -> bool:
	return int(_isolated.get(node, -1)) > _day


## A road only counts while it is passable and neither end is cut off.
func _edge_live(e: Dictionary) -> bool:
	return float(e["cond"]) >= 0.12 and not is_isolated(String(e["a"])) and not is_isolated(String(e["b"]))


## Adds (or removes) people from a place: returns the change applied. Migration and refugees use this.
func add_people(node: String, n: int, occupation := "", day := 0) -> int:
	_ensure()
	var p: Dictionary = _places.get(node, {})
	if p.is_empty() or n == 0:
		return 0
	if bool(p["ruin"]) and n > 0:
		return 0
	return _change_pop(p, n, _rng("addp", day, node), occupation)


func house_capacity(node: String) -> int:
	return int(place(node).get("housing", 0.0))


## Founds a dynamic camp-place (NPC founders call this weekly; the sim and tests call it to start a frontier camp).
func found_place(pos: Vector2, pname := "", founder := "", day := -1, pop := 12) -> String:
	_ensure()
	var cm := _mod("camps")
	if cm == null or dynamic_count() >= DYNAMIC_CAP:
		return ""
	var d := _day if day < 0 else day
	var r := _rng("found", d, int(pos.x * 7.0 + pos.y))
	if pname == "":
		pname = _make_name(r)
	var cid: int = int(cm.call("found_camp", pos, pname, d))
	if cid < 0:
		return ""
	var node := "c%d" % cid
	var p := _new_place(node, pname, pos)
	p["dyn"] = true
	p["camp"] = cid
	p["popf"] = float(pop)
	p["popc"] = float(pop)
	p["housing"] = float(pop) * 1.5 + 10.0
	p["jobs"] = 10.0 + float(pop) * 0.4
	p["treasury"] = 30.0 + 4.0 * pop
	p["founded"] = d
	p["since"] = d
	p["last"] = d
	p["founder"] = founder if founder != "" else String(FOUNDERS[r.randi() % FOUNDERS.size()])
	p["ref"] = 0.52
	p["patrol"] = 0.12
	p["peak"] = pop
	p["maint"] = float(d + 20)
	_places[node] = p
	var anchor := _nearest_place(pos, node)
	if anchor != "":
		cm.call("build_road", node, anchor, "dirt")
	_news_add("founded", node, "%s have raised a camp at %s." % [_up(String(p["founder"])), pname], d)
	_hist(p, d, "founded by %s" % p["founder"])
	return node


## Settlement id a news item is filed under: a static place's own sid, a dynamic camp files under the nearest static place (news.gd
## measures road distance between settlement ids only).
func news_sid(node: String) -> int:
	var p: Dictionary = _places.get(node, {})
	if p.is_empty():
		return -1
	if not bool(p["dyn"]):
		return int(p["sid"])
	var best := -1
	var bd := INF
	var pos := Vector2(p["pos"][0], p["pos"][1])
	for s: Dictionary in WorldGen.settlements:
		var d := pos.distance_squared_to(s["pos"])
		if d < bd:
			bd = d
			best = int(s["id"])
	return best


## notables.gd hook: an NPC founder stakes a claim near settlement `req.near`. req {founder, nid, near, name, kind}. Returns {ok, node}.
func request_founding(req: Dictionary) -> Dictionary:
	_ensure()
	var near := int(req.get("near", -1))
	if near < 0 or near >= WorldGen.settlements.size() or dynamic_count() >= DYNAMIC_CAP or _day - _last_found() < FOUND_GAP:
		return {"ok": false}
	var cm := _mod("camps")
	if cm == null:
		return {"ok": false}
	var home: Vector2 = WorldGen.settlements[near]["pos"]
	var r := _rng("reqfound", _day, String(req.get("nid", "")))
	var best := Vector2.ZERO
	var bs := -1.0
	for _i in 10:
		var ang := r.randf() * TAU
		var pos := home + Vector2(cos(ang), sin(ang)) * r.randf_range(130.0, 320.0)
		if _nearest_dist(pos) < 160.0:
			continue
		var sc := float(cm.call("score_site", pos)) + 0.3 * _coverage(pos)
		if sc > bs and float(cm.call("score_site", pos)) >= float(cm.get("MIN_CAMP_SCORE")) + 0.03:
			bs = sc
			best = pos
	if bs < 0.0:
		return {"ok": false}
	var node := found_place(best, String(req.get("name", "")), String(req.get("founder", "")), _day, 9 + r.randi() % 6)
	return {"ok": node != "", "node": node}


## governance.gd hook: a council approved a project at settlement `sid`. Kinds: market walls school temple granary hospital hostel.
## Queues it at the place with a high priority (the treasury still has to pay); returns {ok, id}.
func request_project(sid: int, kind: String) -> Dictionary:
	_ensure()
	var p: Dictionary = _places.get("s%d" % sid, {})
	var k: String = {"walls": "wall", "granary": "irrigation", "hospital": "well", "hostel": "house", "temple": "school"}.get(kind, kind)
	if p.is_empty() or bool(p["ruin"]) or not PROJECTS.has(k) or _proj_count(p, k) >= int(PROJECTS[k]["max"]) or _proj_open(p, k) >= 1 or (p["proj"] as Array).size() >= 6:
		return {"ok": false}
	var pid := _next_project
	_next_project += 1
	_projects[pid] = {"id": pid, "node": String(p["node"]), "kind": k, "cost": int(_project_cost(p, k)), "days": snappedf(_project_days(p, k), 0.1),
		"state": "queued", "queued": _day, "start": -1, "done": -1, "site": 0, "score": 0.95}
	(p["proj"] as Array).append(pid)
	return {"ok": true, "id": pid}


static func _a(word: String) -> String:
	return "an" if word.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a"


static func _up(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


func _make_name(r: RandomNumberGenerator) -> String:
	for _t in 12:
		var nm: String = String(NAME_A[r.randi() % NAME_A.size()]) + String(NAME_B[r.randi() % NAME_B.size()])
		var used := false
		for k: String in _places:
			if String(_places[k]["name"]) == nm:
				used = true
		if not used:
			return nm
	return "Newcamp"


func _nearest_place(pos: Vector2, except := "") -> String:
	var best := ""
	var bd := INF
	for node: String in _places:
		if node == except or bool(_places[node]["ruin"]):
			continue
		var d := pos.distance_squared_to(Vector2(_places[node]["pos"][0], _places[node]["pos"][1]))
		if d < bd:
			bd = d
			best = node
	return best


# --------------------------------------------------------------- people in a place

func _pop(p: Dictionary) -> int:
	if bool(p["dyn"]):
		return int(float(p["popf"]))
	var stl := _mod("settlements")
	return int(stl.call("population", int(p["sid"]))) if stl != null else int(p["popf"])


func _change_pop(p: Dictionary, n: int, r: RandomNumberGenerator, occupation := "") -> int:
	if bool(p["dyn"]):
		var before := float(p["popf"])
		p["popf"] = maxf(0.0, before + float(n))
		return int(float(p["popf"]) - before)
	var stl := _mod("settlements")
	if stl == null:
		p["popf"] = maxf(0.0, float(p["popf"]) + float(n))
		return n
	return int(stl.call("adjust_population", int(p["sid"]), n, r, occupation))


# --------------------------------------------------------------- inputs: pressures, safety, roads

## Roads touching a node (cached adjacency over camps.gd's edge dictionaries; rebuilt when an edge is added and every 10 days).
func _edges_of(node: String) -> Array:
	var cm := _mod("camps")
	if cm == null:
		return _NO_EDGES
	cm.call("_ensure")
	var all: Dictionary = cm.get("_edges")
	if _adj_n != all.size() or absi(_day - _adj_day) > 10:
		_adj = {}
		for k: String in all:
			var e: Dictionary = all[k]
			for end: String in [String(e["a"]), String(e["b"])]:
				if not _adj.has(end):
					_adj[end] = []
				(_adj[end] as Array).append(e)
		_adj_n = all.size()
		_adj_day = _day
	return _adj.get(node, _NO_EDGES)


func _boom_power(p: Dictionary, day: int) -> float:
	var b: Dictionary = p["boom"]
	if b.is_empty():
		return 0.0
	var t := float(day - int(b["start"])) / maxf(1.0, float(b["dur"]))
	return maxf(0.0, float(b["p0"]) * (1.0 - t)) if t >= 0.0 else 0.0


## Runestone coverage at a place, refreshed every 4 days (stones wear slowly) or whenever a step spans several days.
func _cov_of(p: Dictionary, day: int, n: float) -> float:
	if n > 1.5 or day - int(p["cov_day"]) >= 4 or day < int(p["cov_day"]):
		p["cov"] = _coverage(Vector2(p["pos"][0], p["pos"][1]))
		p["cov_day"] = day
		var dx := 0.0
		if bool(p["dyn"]):
			var cm := _mod("camps")
			if cm != null:
				dx = 0.3 * float(cm.call("defence_of", int(p["camp"])))
		else:
			var stl := _mod("settlements")
			if stl != null:
				dx = _struct_defence(stl.call("structures", int(p["sid"])))
		p["defx"] = dx
	return float(p["cov"])


## Ecology's view of the land around a place (null-guarded): {danger 0..1, prosperity 0..1}. A dynamic camp reads its nearest settlement's zone.
func _eco_read(p: Dictionary) -> Dictionary:
	var eco := _mod("ecology")
	if eco == null or not eco.has_method("danger_level"):
		return {"danger": 0.0, "prosperity": 0.0}
	var sid := int(p["sid"]) if not bool(p["dyn"]) else news_sid(String(p["node"]))
	if sid < 0:
		return {"danger": 0.0, "prosperity": 0.0}
	var ae: Dictionary = eco.call("adventurer_economy", sid) if eco.has_method("adventurer_economy") else {}
	return {"danger": clampf(float(eco.call("monster_pressure", sid)), 0.0, 1.0) * (1.0 if not bool(p["dyn"]) else 0.8), "prosperity": clampf(float(ae.get("prosperity", 0.0)), 0.0, 1.0)}


## The settlement's real farm chains follow what the place has built (farmsteads, irrigation): the food it is credited with is grown.
func _sync_farms(p: Dictionary) -> void:
	var stl := _mod("settlements")
	if stl == null or bool(p["dyn"]):
		return
	var sid := int(p["sid"])
	var want := int(round(float(p["farms"]) * (1.0 + float(p["food_x"]))))
	if want > int((stl.call("chains", sid) as Dictionary).get("farm", 0)):
		stl.call("set_chain", sid, "farm", want)


func _pc(p: Dictionary) -> float:
	return float(p["popc"])


func _safety(p: Dictionary, cov: float) -> float:
	return clampf(0.6 * cov + 0.12 * float(p["walls"]) + float(p["defx"]) + float(p["patrol"]) - 0.6 * float(p["monster"]) - 0.15 * float(p["war"]), 0.0, 1.0)


## How many people the land and the roads can feed (farms, hunting, imports); static places keep a seeded import term so the capital's
## grain from the provinces does not read as famine.
func _food_cap(p: Dictionary, R: float) -> float:
	return 18.0 + (FARM_FEEDS if bool(p["dyn"]) else FARM_FEEDS_STATIC) * float(p["farms"]) * (1.0 + float(p["food_x"])) + 40.0 * R + float(p["fimp"])


func _food_ratio(p: Dictionary, R: float) -> float:
	var pop := maxf(1.0, _pc(p))
	var f := clampf(_food_cap(p, R) / pop, 0.0, 2.0)
	if bool(p["dyn"]):
		return f
	var stl := _mod("settlements")
	if stl != null:
		var short: int = int((stl.call("shortages", int(p["sid"])) as Dictionary).get("food", 0))
		if short >= 3:
			f *= 0.7
		elif short > 0:
			f *= 0.85
	return f


func _jobs_supply(p: Dictionary, R := 0.4) -> float:
	var j: float = _fixed_jobs(p) + _service_jobs(p, R)
	return j


## 0..1 how long and how completely a place has been cut off (a mine with no road has no buyers).
func _cutfrac(p: Dictionary) -> float:
	return minf(1.0, float(p["cut"]) / 90.0)


## Jobs that do not depend on how many people live here: land, mines, projects.
func _fixed_jobs(p: Dictionary) -> float:
	var j: float = float(p["jobs"]) + float(p["jobs_x"]) + FARM_JOBS * float(p["farms"])
	for d: Dictionary in p["res"]:
		if bool(d["dev"]):
			j += float(d["wcap"]) * clampf(float(d["reserve"]) / (0.2 * float(d["reserve0"])), 0.0, 1.0) * (1.0 - 0.6 * _cutfrac(p))
	return j


## The population the jobs can carry (service jobs grow with the people, so this solves jobs = 0.69 * pop).
func _jobs_cap(p: Dictionary, R: float) -> float:
	var svc := _service_jobs(p, R) / maxf(1.0, _pc(p))
	return _fixed_jobs(p) / maxf(0.25, 0.69 - svc)


## Shops, smiths, carters: they follow the people and the roads.
func _service_jobs(p: Dictionary, R: float) -> float:
	return SERVICE * _pc(p) * (0.4 + 0.6 * clampf(R + float(p["trade_x"]), 0.0, 1.0))


func _leader_cached(p: Dictionary, day: int, n: float) -> float:
	if n > 1.5 or day - int(p["lead_day"]) >= 7 or day < int(p["lead_day"]):
		p["lead"] = _leader(String(p["node"]))
		p["lead_day"] = day
	return float(p["lead"])


func _leader(node: String) -> float:
	var g := _mod("governance")
	if g != null and g.has_method("leader_quality") and node.begins_with("s"):
		return clampf(float(g.call("leader_quality", int(node.substr(1)))), 0.0, 1.0)
	return 0.5


func _road_quality(node: String, p: Dictionary, day := 0, n := 1.0) -> Dictionary:
	if n <= 1.5 and day >= int(p["rq_day"]) and day - int(p["rq_day"]) < 3:
		return {"R": clampf((float(p["rqT"]) + float(p["road_x"])) / 1.4, 0.0, 1.0), "live": int(p["rqL"]), "trade": float(p["rqT"])}
	var trade := 0.0
	var live := 0
	var cm := _mod("camps")
	for e: Dictionary in _edges_of(node):
		if _edge_live(e):
			live += 1
			if cm != null:
				trade += float(cm.call("trade_volume", String(e["a"]), String(e["b"])))
	p["rqT"] = trade
	p["rqL"] = live
	p["rq_day"] = day
	return {"R": clampf((trade + float(p["road_x"])) / 1.4, 0.0, 1.0), "live": live, "trade": trade}


## Reads every pressure of a place and derives attraction. Pure (no mutation beyond the cached fields).
func _inputs(p: Dictionary, day: int, n := 1.0) -> Dictionary:
	var node: String = p["node"]
	var pop := maxf(1.0, _pc(p))
	var S := _safety(p, _cov_of(p, day, n))
	var rq := _road_quality(node, p, day, n)
	var R: float = rq["R"]
	var live: int = rq["live"]
	var trade: float = rq["trade"]
	var cut := live == 0
	var F := _food_ratio(p, R)
	var Jr := _jobs_supply(p, R) / maxf(1.0, 0.6 * pop)
	var Hr := pop / maxf(1.0, float(p["housing"]))
	var boom := _boom_power(p, day)
	var cut_pen := 0.35 * minf(1.0, float(p["cut"]) / 60.0) if cut else 0.0
	var eco_r := _eco_read(p)
	var A := 0.27 * S + 0.20 * clampf(F / 1.2, 0.0, 1.0) + 0.20 * clampf(Jr / 1.3, 0.0, 1.0) + 0.15 * R + 0.08 * _leader_cached(p, day, n) \
		+ 0.10 * clampf(1.25 - Hr, 0.0, 1.0) + 0.4 * boom - 0.25 * float(p["unrest"]) - 0.10 * float(p["crime"]) - cut_pen
	A += ECO_PROSPERITY * float(eco_r["prosperity"])
	var mg := _mod("migration")
	if mg != null and mg.has_method("master_count"):
		A += 0.04 * minf(2.0, float(mg.call("master_count", node)))
	return {"eco": float(eco_r["danger"]), "Kf": _food_cap(p, R), "Kj": _jobs_cap(p, R), "S": S, "F": F, "J": Jr, "R": R, "H": Hr, "boom": boom, "A": clampf(A, 0.0, 1.0), "cut": cut, "links": live, "trade": trade}


# --------------------------------------------------------------- the step (closed form in n days)

func _step_place(p: Dictionary, day: int, n: float, ctx: Dictionary) -> Array:
	var out: Array = []
	if bool(p["ruin"]):
		p["last"] = day
		return out
	var node: String = p["node"]
	var t0 := Time.get_ticks_usec() if prof_on else 0
	var r := _rng("step", day, node)
	var pop0 := float(_pop(p))
	p["popc"] = pop0
	# 1. deposits: extraction is linear in n (workers taken at the step's start)
	var income := 0.0
	var cm := _mod("camps")
	var stl := _mod("settlements")
	for d: Dictionary in p["res"]:
		if not bool(d["dev"]) or float(d["reserve"]) <= 0.0:
			continue
		var w := minf(float(d["wcap"]), pop0 * 0.22)
		var ext := minf(float(d["reserve"]), w * float(d["rich"]) * n)
		d["reserve"] = float(d["reserve"]) - ext
		income += ext * float(RESOURCE_VALUE.get(String(d["kind"]), 1.0)) * (1.0 - 0.7 * _cutfrac(p))
		if bool(p["dyn"]) and cm != null:
			d["carry"] = float(d["carry"]) + ext * 0.5
			var whole := int(float(d["carry"]))
			if whole > 0:
				d["carry"] = float(d["carry"]) - whole
				cm.call("add_stock", int(p["camp"]), "iron" if String(d["kind"]) == "iron" else String(d["kind"]), whole)
		if float(d["reserve"]) <= 0.0:
			d["reserve"] = 0.0
			out.append_array(_deposit_dry(p, d, day))
	t0 = _pf("1 deposits", t0)
	# 2. inputs and attraction
	var inp := _inputs(p, day, n)
	t0 = _pf("2 inputs", t0)
	if float(p["ref"]) < 0.0:
		p["ref"] = float(inp["A"])
	var R: float = inp["R"]
	var pop := maxf(1.0, pop0)
	# isolation, famine, unrest, crime (smoothed, closed form)
	p["cut"] = float(p["cut"]) + n if bool(inp["cut"]) else maxf(0.0, float(p["cut"]) - 2.0 * n)
	if float(inp["F"]) < 0.9:
		p["famine"] = float(p["famine"]) + n
	else:
		p["famine"] = maxf(0.0, float(p["famine"]) - 3.0 * n)
	var u_tgt := clampf(0.8 * maxf(0.0, float(inp["H"]) - 1.0) + 0.9 * maxf(0.0, 0.95 - float(inp["F"])) + 0.5 * maxf(0.0, 0.9 - float(inp["J"])), 0.0, 1.0)
	var k_fast := 1.0 - exp(-0.08 * n)
	p["unrest"] = float(p["unrest"]) + (u_tgt - float(p["unrest"])) * k_fast
	var c_tgt := clampf(0.08 + 0.55 * float(inp["boom"]) + 0.3 * float(p["unrest"]) + 0.03 * float(p["tier"]), 0.0, 1.0)
	p["crime"] = float(p["crime"]) + (c_tgt - float(p["crime"])) * k_fast
	var decay := exp(-0.02 * n)
	p["monster"] = float(p["monster"]) * decay
	if float(inp["eco"]) > 0.0:   # the wild around the place keeps pressing: monsters settle at a share of ecology's danger
		var m_tgt := ECO_DANGER * float(inp["eco"])
		if float(p["monster"]) < m_tgt:
			p["monster"] = float(p["monster"]) + (m_tgt - float(p["monster"])) * (1.0 - exp(-0.05 * n))
	if bool(ctx.get("at_war", false)):
		var frontier := bool(p["dyn"]) or (int(p["sid"]) < WorldGen.settlements.size() and String(WorldGen.settlements[int(p["sid"])]["kind"]) == "frontier_town")
		p["war"] = minf(1.0, float(p["war"]) + (0.004 if frontier else 0.0015) * n)
	else:
		p["war"] = float(p["war"]) * decay
	p["S"] = inp["S"]
	p["F"] = inp["F"]
	p["J"] = inp["J"]
	p["R"] = inp["R"]
	p["H"] = inp["H"]
	var A: float = inp["A"]
	p["attr"] = A
	# 3. population toward the carrying capacity the pressures allow
	var fill := clampf(1.0 + 0.9 * (A - float(p["ref"])), 0.3, 1.4)
	var K_house := OCCUPANCY * float(p["housing"]) * fill
	var K := minf(K_house, minf(float(inp["Kf"]) * 1.02, float(inp["Kj"]) * 1.0)) * (1.0 - 0.3 * _cutfrac(p))   # no merchants, no salt, no tools
	if bool(p["dyn"]):
		var rate := GROW_RATE if float(p["popf"]) < K else SHRINK_RATE
		p["popf"] = K + (float(p["popf"]) - K) * exp(-rate * n)
	elif stl != null:
		stl.call("set_capacity", int(p["sid"]), int(round(K)))
		if pop0 > K:
			var amount := (pop0 - K) * (1.0 - exp(-SHRINK_RATE * n))
			var whole2 := int(amount) + (1 if r.randf() < amount - floorf(amount) else 0)
			if whole2 > 0:
				_change_pop(p, -whole2, r)
	var pop2 := float(_pop(p))
	p["popc"] = pop2
	p["peak"] = maxi(int(p["peak"]), int(pop2))
	# push and pull for migration.gd
	p["push"] = clampf(0.9 * float(p["unrest"]) + 0.5 * float(p["monster"]) + 0.6 * float(p["war"]) + (0.3 if float(p["famine"]) > 10.0 else 0.0) \
		+ 0.3 * minf(1.0, float(p["cut"]) / 120.0) + 0.25 * maxf(0.0, float(p["ref"]) - A) * 2.0, 0.0, 1.0)
	p["pull"] = clampf(A - 0.3 * maxf(0.0, float(inp["H"]) - 1.0), 0.0, 1.0)
	t0 = _pf("3 pop", t0)
	# 4. treasury
	income += pop2 * 0.012 * (0.55 + 0.7 * R) * (0.6 + 0.4 * minf(1.0, float(inp["J"]))) * n + pop2 * 0.012 * float(inp["boom"]) * n
	income += float(p["trade_x"]) * pop2 * 0.006 * n
	p["inc"] = income / maxf(n, 1.0)
	p["treasury"] = minf(20000.0, float(p["treasury"]) + income)
	# 5. upkeep: runestones and roads (a place that cannot pay lets them go), a month and three weeks apart
	out.append_array(_maintain(p, day, n, inp))
	t0 = _pf("4 maintain", t0)
	# 6. projects
	out.append_array(_projects_step(p, day, n, inp))
	t0 = _pf("5 projects", t0)
	# 7. tier with hysteresis, ruin
	out.append_array(_tier_step(p, day, n, inp))
	t0 = _pf("6 tier", t0)
	p["last"] = day
	return out


func _deposit_dry(p: Dictionary, d: Dictionary, day: int) -> Array:
	var stl := _mod("settlements")
	if stl != null and not bool(p["dyn"]):
		stl.call("set_chain", int(p["sid"]), "mine", 0)
		stl.call("set_chain", int(p["sid"]), "smelter", 0)
	d["dev"] = false
	var line := "The %s at %s has run dry." % ["mine" if String(d["kind"]) in ["iron", "silver"] else "diggings", String(p["name"])]
	_news_add("depleted", String(p["node"]), line, day)
	_hist(p, day, "the %s ran dry" % String(d["kind"]).replace("_", " "))
	return [line]


func _maintain(p: Dictionary, day: int, n: float, _inp: Dictionary) -> Array:
	if float(p["maint"]) > float(day) or int(p["tier"]) < 1 and not bool(p["dyn"]):
		return []
	var times := maxi(1, int(n / 25.0))
	p["maint"] = float(day) + 25.0
	var node: String = p["node"]
	var cm := _mod("camps")
	var spent := 0.0
	var rs := _rs()
	var pos := Vector2(p["pos"][0], p["pos"][1])
	if rs != null and float(p["treasury"]) >= 20.0:
		var done := 0
		for s: Dictionary in (rs.get("stones") as Array):
			if done >= 3:
				break
			if pos.distance_to(s["pos"]) < float(s["radius"]) and float(s["condition"]) < 0.9:
				rs.call("maintain", int(s["id"]), day, minf(0.6, 0.3 * times))
				spent += 8.0
				done += 1
	if cm != null and float(p["treasury"]) >= 12.0:
		for e: Dictionary in _edges_of(node):
			var k := String(e["a"]) + "|" + String(e["b"])
			if int(_blocked.get(k, -1)) > day or is_isolated(String(e["a"])) or is_isolated(String(e["b"])):
				continue
			if float(e["cond"]) < 0.7:
				cm.call("maintain_road", String(e["a"]), String(e["b"]), 0.3 * times)
				spent += 4.0
	p["treasury"] = maxf(0.0, float(p["treasury"]) - spent)
	return []


# --------------------------------------------------------------- tiers

func _tier_step(p: Dictionary, day: int, n: float, inp: Dictionary) -> Array:
	var out: Array = []
	var pop := _pop(p)
	var t: int = p["tier"]
	# ruin
	if pop < RUIN_POP and (bool(p["dyn"]) or float(p["peak"]) > 0.0):
		p["ruin_acc"] = float(p["ruin_acc"]) + n
		if float(p["ruin_acc"]) >= RUIN_DAYS:
			return _make_ruin(p, day)
	else:
		p["ruin_acc"] = maxf(0.0, float(p["ruin_acc"]) - 2.0 * n)
	var up := false
	if t < 5 and pop >= TIER_POP[t + 1] and float(inp["S"]) >= TIER_SAFETY[t + 1] and float(inp["F"]) >= 0.8:
		up = true
		if t == 4:
			var has_market := int((p["built"] as Dictionary).get("market", 0)) > 0
			up = int(inp["links"]) >= 3 and (has_market or _merchant_identity(p) >= 0.4)
	var down := t > 0 and float(pop) < DOWN_FRAC * float(TIER_POP[t])
	if up:
		p["acc"] = maxf(0.0, float(p["acc"])) + n
		if float(p["acc"]) >= PROMOTE_DAYS:
			p["tier"] = t + 1
			p["acc"] = 0.0
			p["since"] = day
			var line := "%s has grown into %s %s." % [String(p["name"]), _a(String(TIERS[t + 1])), String(TIERS[t + 1])]
			_news_add("tier_up", String(p["node"]), line, day)
			_hist(p, day, "became %s %s" % [_a(String(TIERS[t + 1])), TIERS[t + 1]])
			out.append(line)
	elif down:
		p["acc"] = minf(0.0, float(p["acc"])) - n
		if -float(p["acc"]) >= DEMOTE_DAYS:
			p["tier"] = t - 1
			p["acc"] = 0.0
			p["since"] = day
			p["abandoned"] = int(p["abandoned"]) + 1 + pop / 150
			_abandon_building(p)
			var line2 := "%s has shrunk to %s %s; houses stand empty." % [String(p["name"]), _a(String(TIERS[t - 1])), String(TIERS[t - 1])]
			_news_add("tier_down", String(p["node"]), line2, day)
			_hist(p, day, "shrank to %s %s" % [_a(String(TIERS[t - 1])), TIERS[t - 1]])
			out.append(line2)
	else:
		p["acc"] = float(p["acc"]) * exp(-0.1 * n)
	return out


func _merchant_identity(p: Dictionary) -> float:
	var stl := _mod("settlements")
	if stl == null or bool(p["dyn"]):
		return 0.0
	return float((stl.call("identity", int(p["sid"])) as Dictionary).get("merchant", 0.0))


func _abandon_building(p: Dictionary) -> void:
	var stl := _mod("settlements")
	if stl == null or bool(p["dyn"]):
		return
	var st: Dictionary = stl.call("structures", int(p["sid"]))
	for k in ["market", "warehouse", "mill", "farm"]:
		if int(st.get(k, 0)) > 0:
			stl.call("add_structure", int(p["sid"]), k, -1)
			return


func _make_ruin(p: Dictionary, day: int) -> Array:
	p["ruin"] = true
	p["ruin_day"] = day
	p["popf"] = 0.0
	var stl := _mod("settlements")
	if stl != null and not bool(p["dyn"]):
		stl.call("set_capacity", int(p["sid"]), 0)
		var left := int(stl.call("population", int(p["sid"])))
		if left > 0:
			stl.call("adjust_population", int(p["sid"]), -left, _rng("ruin", day, String(p["node"])))
		for c in ["farm", "mine", "smelter", "mill", "bakery", "smithy", "woodcutter", "fishery"]:
			stl.call("set_chain", int(p["sid"]), c, 0)
	for pid: int in (p["proj"] as Array):
		_cancel_project(pid)
	p["proj"] = []
	var line := "%s is abandoned. Its empty streets remain as a ruin." % String(p["name"])
	_news_add("ruin", String(p["node"]), line, day)
	_hist(p, day, "abandoned")
	return [line]


# --------------------------------------------------------------- projects

func _proj_count(p: Dictionary, kind: String) -> int:
	var n := int((p["built"] as Dictionary).get(kind, 0))
	for pid: int in p["proj"]:
		if String(_projects[pid]["kind"]) == kind:
			n += 1
	return n


func _project_cost(p: Dictionary, kind: String) -> float:
	var def: Dictionary = PROJECTS[kind]
	return (float(def["cost"]) + float(def["per_pop"]) * _pc(p)) * (1.0 + 0.12 * float(p["tier"]))


func _project_days(p: Dictionary, kind: String) -> float:
	var def: Dictionary = PROJECTS[kind]
	var crew := clampf(120.0 / (_pc(p) + 20.0), 0.6, 3.0)
	var bonus := 1.0
	var mg := _mod("migration")
	if mg != null and mg.has_method("master_bonus"):
		bonus = 1.0 - clampf(float(mg.call("master_bonus", String(p["node"]), "architect")), 0.0, 0.4)
	return float(def["days"]) * crew * bonus


func _needs(p: Dictionary, inp: Dictionary) -> Dictionary:
	var cov: float = float(p["cov"])
	var sc := {}
	var pop := _pc(p)
	var t: int = p["tier"]
	var Hr: float = inp["H"]
	var kcap := minf(float(inp["Kf"]), float(inp["Kj"]))
	var fill_est := clampf(1.0 + 0.9 * (float(inp["A"]) - float(p["ref"])), 0.3, 1.4)
	if Hr > 0.93 and OCCUPANCY * float(p["housing"]) * fill_est <= 1.1 * kcap:
		sc["house"] = minf(1.6, 0.5 + (Hr - 0.93) * 3.0)
	if pop >= 15.0:
		sc["well"] = 0.6
	if pop > 0.9 * float(inp["Kf"]) and int(p["farms"]) > 0:
		sc["irrigation"] = 0.6 + (pop / maxf(1.0, float(inp["Kf"])) - 0.9)
	if float(inp["S"]) < 0.5 and t >= 1:
		sc["wall"] = (0.55 - float(inp["S"])) * 1.5 + (0.3 if float(p["war"]) > 0.1 else 0.0)
	if float(p["patrol"]) < 0.25 and t >= 1 and float(inp["S"]) < 0.55:
		sc["guards"] = 0.5
	if t >= 1 and pop >= 60.0:
		sc["market"] = 0.7
	for d: Dictionary in p["res"]:
		if not bool(d["dev"]) and float(d["reserve"]) > 0.0 and pop >= 8.0:
			sc["mine"] = 1.5
	if cov < 0.6 and pop >= 20.0:
		sc["runestone"] = (0.65 - cov) * 1.6 + 0.25 + 0.2 * float(p["monster"])
	if float(inp["R"]) < 0.55 and pop >= 25.0:
		sc["road"] = 0.6 - float(inp["R"])
	if t >= 2:
		sc["school"] = 0.45
		if float(inp["R"]) < 0.5:
			sc["bridge"] = 0.35
		if _coastal(p):
			sc["port"] = 0.4
	return sc


func _coastal(p: Dictionary) -> bool:
	if int(p["coast"]) < 0:
		var sd: float = WorldGen.shore_distance(float(p["pos"][0]), float(p["pos"][1]))
		p["coast"] = 1 if (sd > -INF and sd < 260.0) else 0
	return int(p["coast"]) == 1


func _projects_step(p: Dictionary, day: int, n: float, inp: Dictionary) -> Array:
	var out: Array = []
	var node: String = p["node"]
	var cons := _mod("construction")
	# progress and completion
	for pid: int in (p["proj"] as Array).duplicate():
		var pr: Dictionary = _projects[pid]
		if String(pr["state"]) != "building":
			continue
		var frac := (float(day) - float(pr["start"])) / maxf(1.0, float(pr["days"]))
		if cons != null and int(pr["site"]) > 0:
			cons.call("npc_set_progress", int(pr["site"]), frac)
		if frac >= 1.0:
			out.append_array(_complete_project(p, pr, day))
	# queue what the place needs (cheap, pressing things first), start what it can afford
	var rounds := 1 + int(n / 4.0)          # a long step (catch_up) queues and starts as much as the same days would have
	var cap := 3 + int(p["tier"]) / 2
	var sc := _needs(p, inp) if (n > 1.5 or (day + _hid(node)) % 3 == 0) else {}
	for _round in rounds:
		if (p["proj"] as Array).size() >= cap or sc.is_empty():
			break
		var best := ""
		var bs := 0.2
		for k: String in PROJECT_ORDER:
			if not sc.has(k) or _proj_count(p, k) >= int(PROJECTS[k]["max"]) or _proj_open(p, k) >= (2 if k == "house" else 1):
				continue
			var cost := maxf(1.0, _project_cost(p, k))
			var eff := float(sc[k]) * clampf((float(p["treasury"]) + 60.0 * float(p["inc"])) / cost, 0.15, 1.0)
			if eff > bs:
				bs = eff
				best = k
		if best == "":
			break
		var pid := _next_project
		_next_project += 1
		_projects[pid] = {"id": pid, "node": node, "kind": best, "cost": int(_project_cost(p, best)), "days": snappedf(_project_days(p, best), 0.1),
			"state": "queued", "queued": day, "start": -1, "done": -1, "site": 0, "score": snappedf(bs, 0.01)}
		(p["proj"] as Array).append(pid)
	for _round in rounds:
		var pick := 0
		var pick_score := -1.0
		for pid: int in p["proj"]:
			var pr2: Dictionary = _projects[pid]
			if String(pr2["state"]) == "queued" and float(p["treasury"]) >= float(pr2["cost"]) and float(pr2["score"]) > pick_score:
				pick = pid
				pick_score = float(pr2["score"])
		if pick == 0:
			break
		var pr3: Dictionary = _projects[pick]
		p["treasury"] = float(p["treasury"]) - float(pr3["cost"])
		pr3["state"] = "building"
		pr3["start"] = day
		pr3["days"] = snappedf(_project_days(p, String(pr3["kind"])), 0.1)
		if cons != null:
			pr3["site"] = _open_site(p, pr3, cons)
	return out


func _proj_open(p: Dictionary, kind: String) -> int:
	var n := 0
	for pid: int in p["proj"]:
		if String(_projects[pid]["kind"]) == kind:
			n += 1
	return n


func _site_kind(p: Dictionary, kind: String) -> String:
	var t: int = p["tier"]
	match kind:
		"house":
			return "hut" if t < 2 else ("timber_house" if t < 4 else "stone_house")
		"well":
			return "well"
		"irrigation":
			return "field"
		"guards":
			return "watchtower"
		"wall":
			return "palisade" if t < 3 else "stone_wall"
		"market":
			return "market"
		"mine":
			return "workshop"
		"runestone":
			return "watchtower"
		"road":
			return "storage_pile"
		"school":
			return "guild_hall"
		"bridge":
			return "stone_wall"
		_:
			return "barn"


func _open_site(p: Dictionary, pr: Dictionary, cons: RefCounted) -> int:
	var center := Vector2(p["pos"][0], p["pos"][1])
	var rad := 14.0
	if not bool(p["dyn"]) and int(p["sid"]) < WorldGen.settlements.size():
		rad = float(WorldGen.settlements[int(p["sid"])]["radius"]) * 0.75
	var r := _rng("site", int(pr["id"]), String(p["node"]))
	var pos := center
	for _t in 8:
		var ang := r.randf() * TAU
		var dd := rad * (0.45 + 0.75 * r.randf())
		pos = center + Vector2(cos(ang), sin(ang)) * dd
		if not WorldGen.is_water(pos.x, pos.y):
			break
	var kind := _site_kind(p, String(pr["kind"]))
	var hours: float = float(D.def(kind).get("hours", 40.0))
	return int(cons.call("npc_place", kind, pos, r.randf() * TAU, hours, "%s: %s" % [p["name"], PROJECTS[pr["kind"]]["label"]], String(p["node"])))


func _cancel_project(pid: int) -> void:
	var pr: Dictionary = _projects.get(pid, {})
	if pr.is_empty():
		return
	var cons := _mod("construction")
	if cons != null and int(pr["site"]) > 0:
		cons.call("npc_remove", int(pr["site"]))
	_projects.erase(pid)


func _complete_project(p: Dictionary, pr: Dictionary, day: int) -> Array:
	var kind: String = pr["kind"]
	pr["state"] = "done"
	pr["done"] = day
	(p["proj"] as Array).erase(int(pr["id"]))
	var b: Dictionary = p["built"]
	b[kind] = int(b.get(kind, 0)) + 1
	var cons := _mod("construction")
	if cons != null and int(pr["site"]) > 0:
		cons.call("npc_finish", int(pr["site"]))
	var stl := _mod("settlements")
	var cm := _mod("camps")
	var sid: int = p["sid"]
	match kind:
		"house":
			p["housing"] = float(p["housing"]) + maxf(16.0, 0.08 * float(p["housing"]))
		"well":
			p["housing"] = float(p["housing"]) + 6.0
		"irrigation":
			p["food_x"] = float(p["food_x"]) + 0.15
			_sync_farms(p)
		"guards":
			p["patrol"] = minf(0.35, float(p["patrol"]) + 0.08)
		"wall":
			p["walls"] = int(p["walls"]) + 1
			if stl != null and not bool(p["dyn"]):
				stl.call("add_structure", sid, "wall", 1)
		"market":
			p["jobs_x"] = float(p["jobs_x"]) + 14.0
			p["trade_x"] = float(p["trade_x"]) + 0.25
			if stl != null and not bool(p["dyn"]):
				stl.call("add_structure", sid, "market", 1)
				stl.call("set_trade", sid, float(stl.call("trade_level", sid)) + 0.15)
		"mine":
			for d: Dictionary in p["res"]:
				if not bool(d["dev"]) and float(d["reserve"]) > 0.0:
					d["dev"] = true
					if stl != null and not bool(p["dyn"]):
						stl.call("add_structure", sid, "mine", 1)
						stl.call("set_chain", sid, "mine", 2)
						stl.call("set_chain", sid, "smelter", 1)
					break
		"runestone":
			_extend_runestones(p, day)
		"road":
			_improve_road(p)
		"school":
			p["jobs_x"] = float(p["jobs_x"]) + 8.0
			if stl != null and not bool(p["dyn"]):
				stl.call("add_structure", sid, "school", 1)
		"bridge":
			p["road_x"] = float(p["road_x"]) + 0.12
		"port":
			p["jobs_x"] = float(p["jobs_x"]) + 20.0
			p["trade_x"] = float(p["trade_x"]) + 0.35
			if stl != null and not bool(p["dyn"]):
				stl.call("add_structure", sid, "dock", 1)
	if kind != "house" or int(b[kind]) % 3 == 1:
		_news_add("project", String(p["node"]), "%s has finished %s." % [p["name"], PROJECTS[kind]["label"]], day)
	_hist(p, day, "finished %s" % PROJECTS[kind]["label"])
	if cm != null and bool(p["dyn"]) and kind in ["well", "market", "wall"]:
		var sk := {"well": "well", "market": "market_stall", "wall": "palisade"}[kind] as String
		var st: Dictionary = cm.call("place_structure", int(p["camp"]), sk, Vector2(p["pos"][0], p["pos"][1]))
		if not st.is_empty():
			st["hours_left"] = 0
			st["active"] = true
	return []


## One stone further along the line toward the nearest neighbour: coverage grows, the line reaches the next settlement.
func _extend_runestones(p: Dictionary, day: int) -> void:
	var rs := _rs()
	if rs == null:
		return
	var node: String = p["node"]
	var center := Vector2(p["pos"][0], p["pos"][1])
	var tgt_node := _nearest_place(center, node)
	var dir := Vector2.RIGHT
	if tgt_node != "":
		dir = (pos_of(tgt_node) - center).normalized()
	var k := int(p["stones"])
	var dist := 70.0 + 75.0 * float(k)
	var at := center + dir.rotated(0.45 * float(k % 2) - 0.2) * dist
	if WorldGen.is_water(at.x, at.y):
		at = center + dir.rotated(1.2) * dist
	p["stones"] = k + 1
	rs.call("add_stone", at, 130.0, int(p["sid"]), "%s Stone %d" % [p["name"], k + 1])
	var st: Dictionary = (rs.get("stones") as Array)[-1]
	st["last_maintained"] = day


func _improve_road(p: Dictionary) -> void:
	var cm := _mod("camps")
	if cm == null or is_isolated(String(p["node"])):
		return
	var node: String = p["node"]
	var edges := _edges_of(node)
	if edges.is_empty():
		var near := _nearest_place(pos_of(node), node)
		if near != "":
			cm.call("build_road", node, near, "road")
		return
	var worst: Dictionary = edges[0]
	for e: Dictionary in edges:
		if float(e["cond"]) < float(worst["cond"]):
			worst = e
	var lvl_i: int = cm.get("LEVEL_ORDER").find(String(worst["level"]))
	if float(worst["cond"]) >= 0.8 and lvl_i < 2:
		cm.call("build_road", String(worst["a"]), String(worst["b"]), cm.get("LEVEL_ORDER")[lvl_i + 1])
	else:
		worst["cond"] = 1.0
	_blocked.erase(String(worst["a"]) + "|" + String(worst["b"]))


# --------------------------------------------------------------- weekly: discovery, farmsteads, route loss

func _weekly_place(p: Dictionary, day: int, weeks: float) -> Array:
	var out: Array = []
	if bool(p["ruin"]):
		return _resettle(p, day, weeks)
	var node: String = p["node"]
	var r := _rng("week", day, node)
	# a young frontier camp can simply fail: a hard winter, fever, raiders or the wild drive the settlers off
	if bool(p["dyn"]) and int(p["tier"]) == 0 and day - int(p["founded"]) > 90 and _pop(p) < 40:
		var eco_d := float(_eco_read(p)["danger"])
		var hz := CAMP_FAIL_P * (0.4 + 2.5 * eco_d + 1.2 * (1.0 - clampf(float(p["S"]), 0.0, 1.0)) + 0.6 * float(p["unrest"]))
		if r.randf() < 1.0 - pow(1.0 - hz, weeks):
			var why := "driven off by monsters" if eco_d > 0.25 else ("starved out by a hard winter" if float(p["F"]) < 1.0 else "emptied by fever")
			var fline := "The settlers at %s, %s, have given up." % [String(p["name"]), why]
			_news_add("failed", node, fline, day)
			_hist(p, day, "failed: %s" % why)
			return [fline] + _make_ruin(p, day)
	# a prospector finds something (rare)
	var q_find := 0.0012 * (0.6 + 0.2 * float(p["tier"]))
	if not no_finds.has(node) and r.randf() < 1.0 - pow(1.0 - q_find, weeks):
		var kind: String = FIND_KINDS[r.randi() % FIND_KINDS.size()]
		discover(node, kind, 0.4 + 0.55 * r.randf(), day)
		out.append("%s has struck %s near %s." % [String(kind).replace("_", " ").capitalize(), "a rich seam" if kind != "monster_parts" else "a den", p["name"]])
	# farmsteads spread where the stones make the land safe
	var cap := maxi(int(p["farms0"]) + 1, 2 + 2 * int(p["tier"]))
	var popw := float(_pop(p))
	var kmin := minf(_food_cap(p, float(p["R"])), _jobs_cap(p, float(p["R"])))
	if float(p["S"]) >= 0.1 + 0.1 * float(p["tier"]) and int(p["farms"]) < cap and float(p["treasury"]) >= 40.0 and popw > 0.85 * kmin and r.randf() < 1.0 - pow(0.75, weeks):
		p["treasury"] = float(p["treasury"]) - 30.0
		p["farms"] = int(p["farms"]) + 1
		var stl := _mod("settlements")
		if stl != null and not bool(p["dyn"]):
			stl.call("add_structure", int(p["sid"]), "farm", 1)
			_sync_farms(p)
		_hist(p, day, "new farmstead")
	# a trade route reroutes (rare)
	if int(p["tier"]) >= 1 and r.randf() < 1.0 - pow(1.0 - 0.0002, weeks):
		var edges := _edges_of(node)
		if edges.size() >= 2:
			var e: Dictionary = edges[r.randi() % edges.size()]
			if float(e["cond"]) > 0.3:
				var other := String(e["b"]) if String(e["a"]) == node else String(e["a"])
				cut_route(String(e["a"]), String(e["b"]), 360 + r.randi() % 200)
				var line := "Merchants have abandoned the road between %s and %s." % [p["name"], name_of(other)]
				_news_add("route_lost", node, line, day)
				_hist(p, day, "route to %s lost" % name_of(other))
				out.append(line)
	# blocked routes reopen
	for k: String in _blocked.keys():
		if int(_blocked[k]) <= day:
			_blocked.erase(k)
			var cm := _mod("camps")
			if cm != null:
				var parts := k.split("|")
				var e2: Dictionary = cm.call("road", parts[0], parts[1])
				if not e2.is_empty() and float(e2["cond"]) < 0.5:
					e2["cond"] = 0.6
	return out


func _resettle(p: Dictionary, day: int, weeks: float) -> Array:
	if day - int(p["ruin_day"]) < 365 or (bool(p["dyn"]) and dynamic_count() >= DYNAMIC_CAP):
		return []
	var r := _rng("resettle", day, String(p["node"]))
	if r.randf() < 1.0 - pow(1.0 - 0.004, weeks) and _safety(p, _coverage(Vector2(p["pos"][0], p["pos"][1]))) >= 0.35:
		p["ruin"] = false
		p["tier"] = 0
		p["ruin_acc"] = 0.0
		p["popf"] = 12.0
		p["popc"] = 12.0
		p["peak"] = 12
		p["housing"] = 30.0
		p["jobs"] = 10.0
		p["patrol"] = 0.1
		p["treasury"] = 40.0
		p["unrest"] = 0.0
		p["cut"] = 0.0
		p["ref"] = 0.52
		p["last"] = day
		p["founder"] = "settlers come back"
		var stl := _mod("settlements")
		if stl != null and not bool(p["dyn"]):
			stl.call("set_capacity", int(p["sid"]), 24)
			stl.call("adjust_population", int(p["sid"]), 12, r)
			stl.call("set_chain", int(p["sid"]), "farm", 1)
		var line := "Settlers have come back to the ruins of %s." % p["name"]
		_news_add("resettled", String(p["node"]), line, day)
		_hist(p, day, "resettled")
		return [line]
	return []


## Weekly founding of a dynamic camp along a safe route or near a find (cap DYNAMIC_CAP).
func _found_step(day: int, weeks: float) -> Array:
	if dynamic_count() >= DYNAMIC_CAP or day < FOUND_FROM or day - _last_found() < FOUND_GAP:
		return []
	var r := _rng("founding", day, 0)
	if r.randf() >= 1.0 - pow(1.0 - FOUND_P, weeks):
		return []
	var cm := _mod("camps")
	if cm == null:
		return []
	var cands: Array = []
	for f: Dictionary in _finds:
		cands.append({"pos": Vector2(f["pos"][0], f["pos"][1]), "bonus": 0.3, "find": int(f["id"])})
	var anchors: Array = []
	for node in place_ids():
		var p: Dictionary = _places[node]
		if not bool(p["ruin"]) and int(p["tier"]) >= 1 and float(p["S"]) >= 0.3:
			anchors.append(node)
	for _i in 4:
		if anchors.is_empty():
			break
		var an: String = anchors[r.randi() % anchors.size()]
		var edges := _edges_of(an)
		if edges.is_empty():
			continue
		var e: Dictionary = edges[r.randi() % edges.size()]
		var other := String(e["b"]) if String(e["a"]) == an else String(e["a"])
		var a: Vector2 = cm.call("node_pos", an)
		var b: Vector2 = cm.call("node_pos", other)
		var t := 0.3 + 0.4 * r.randf()
		var perp := (b - a).orthogonal().normalized()
		cands.append({"pos": a.lerp(b, t) + perp * (r.randf_range(40.0, 150.0) * (1.0 if r.randf() < 0.5 else -1.0)), "bonus": 0.0, "find": 0})
	var best := {}
	var bs := -1.0
	for c: Dictionary in cands:
		var pos: Vector2 = c["pos"]
		var cov := _coverage(pos)
		if cov < 0.2 and int(c["find"]) == 0:
			continue
		var sc: float = float(cm.call("score_site", pos)) + float(c["bonus"]) + 0.3 * cov
		if sc > bs and float(cm.call("score_site", pos)) >= float(cm.get("MIN_CAMP_SCORE")) + 0.03:
			if _nearest_dist(pos) < 220.0:
				continue
			bs = sc
			best = c
	if best.is_empty():
		return []
	var node := found_place(best["pos"], "", "", day, 10 + r.randi() % 7)
	if node == "":
		return []
	if int(best["find"]) > 0:
		for i in _finds.size():
			if int(_finds[i]["id"]) == int(best["find"]):
				var f: Dictionary = _finds[i]
				_finds.remove_at(i)
				discover(node, String(f["kind"]), float(f["rich"]), day)
				break
	return ["%s have raised a camp called %s." % [_up(String(_places[node]["founder"])), _places[node]["name"]]]


## Day the latest dynamic place was founded (founders, finds and notables share one pace: a camp every few months at most).
func _last_found() -> int:
	var d := -9999
	for node: String in _places:
		if bool(_places[node]["dyn"]):
			d = maxi(d, int(_places[node]["founded"]))
	return d


func _nearest_dist(pos: Vector2) -> float:
	var bd := INF
	for node: String in _places:
		bd = minf(bd, pos.distance_to(Vector2(_places[node]["pos"][0], _places[node]["pos"][1])))
	return bd


func _push_prices(ctx: Dictionary) -> void:
	var life: Variant = ctx.get("life")
	if not (life is Object) or life == null:
		return
	var eco: Variant = (life as Object).get("economy")
	if eco == null:
		return
	var m: Dictionary = (eco as Object).get("civ_price_mult")
	for node: String in _places:
		var p: Dictionary = _places[node]
		if bool(p["dyn"]):
			continue
		var mult := 1.0 + 0.18 * _boom_power(p, _day) + (0.22 * minf(1.0, float(p["cut"]) / 60.0))
		if mult > 1.001:
			m[int(p["sid"])] = snappedf(mult, 0.01)
		else:
			m.erase(int(p["sid"]))


# --------------------------------------------------------------- news / history

func _news_add(kind: String, node: String, text: String, day: int) -> void:
	_news.append({"id": _next_news, "seq": _next_news, "day": day, "kind": kind, "node": node, "name": name_of(node), "text": text,
		"sid": news_sid(node), "mag": float(NEWS_MAG.get(kind, 1.0)), "detail": "", "official": false})
	_seq = _next_news
	_next_news += 1
	if _news.size() > MAX_NEWS:
		_news.pop_front()


func _hist(p: Dictionary, day: int, text: String) -> void:
	var h: Array = p["hist"]
	h.append("y%d d%d: %s" % [day / 365, day % 365, text])
	while h.size() > MAX_HISTORY:
		h.pop_front()


# --------------------------------------------------------------- ticks

func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## One chunk per place (closed-form step of the days since it last ran), then the region-wide chores.
func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_ensure()
	var chunks: Array = []
	for node: String in place_ids():
		chunks.append(func() -> Array: return _place_day(node, day, ctx))
	chunks.append(func() -> Array: return _region_day(day, ctx))
	return chunks


func _place_day(node: String, day: int, ctx: Dictionary) -> Array:
	var p: Dictionary = _places.get(node, {})
	if p.is_empty():
		return []
	_day = maxi(_day, day)
	var n := 1.0 if int(p["last"]) < 0 else clampf(float(day - int(p["last"])), 1.0, 40.0)
	var out := _step_place(p, day, n, ctx)
	if (day + _hid(node) * 3) % 7 == 0:
		var t0 := Time.get_ticks_usec() if prof_on else 0
		out.append_array(_weekly_place(p, day, 1.0))
		_pf("7 weekly", t0)
	return out


func _region_day(day: int, ctx: Dictionary) -> Array:
	_day = maxi(_day, day)
	var out: Array = []
	if day % 7 == 3:
		out.append_array(_found_step(day, 1.0))
	if day % 7 == 5:
		_push_prices(ctx)
	if day % 30 == 11:
		var cons := _mod("construction")
		if cons != null:
			cons.call("npc_prune", KEEP_DONE_SITES)
		_prune_projects()
	return out


func _prune_projects() -> void:
	var done: Array = []
	for id: int in _projects:
		if String(_projects[id]["state"]) == "done":
			done.append(id)
	done.sort()
	while done.size() > 30:
		_projects.erase(done.pop_front())


## Closed form over `days`: a few big steps (never a loop over days). Fills digest().
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	_digest = []
	if days < 1:
		return _digest
	var news0 := _next_news
	var steps := clampi(int(ceil(float(days) / 8.0)), 1, 12)
	var start := _day
	var mg := _mod("migration")
	if mg != null:
		mg.call("catch_begin", days)   # migration steps inside the same windows, so waves meet the housing the place actually has then
	for k in steps:
		var to_day := start + int(round(float(k + 1) * float(days) / float(steps)))
		var span := to_day - (start + int(round(float(k) * float(days) / float(steps))))
		for node in place_ids():
			var p: Dictionary = _places[node]
			var n := float(maxi(span, 1))
			_step_place(p, to_day, n, ctx)
			_weekly_place(p, to_day, n / 7.0)
		_found_step(to_day, float(span) / 7.0)
		_day = to_day
		if mg != null:
			mg.call("catch_step", to_day, span)
	if mg != null:
		mg.call("catch_end", start + days)
	_push_prices(ctx)
	var cons := _mod("construction")
	if cons != null:
		cons.call("npc_prune", KEEP_DONE_SITES)
	_prune_projects()
	var rank := {"ruin": 0, "route_lost": 1, "tier_down": 2, "tier_up": 3, "founded": 4, "boom": 5, "depleted": 6, "resettled": 7, "project": 8}
	var evs := _news.filter(func(e: Dictionary) -> bool: return int(e["id"]) >= news0)
	evs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(rank.get(a["kind"], 9)) < int(rank.get(b["kind"], 9)))
	for e: Dictionary in evs:
		if _digest.size() >= 8:
			break
		if String(e["kind"]) == "project" and _digest.size() >= 5:
			continue
		_digest.append(String(e["text"]))
	return _digest.duplicate()


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	var pr := {}
	for id: int in _projects:
		pr[str(id)] = (_projects[id] as Dictionary).duplicate(true)
	return {"places": _places.duplicate(true), "projects": pr, "next_project": _next_project, "finds": _finds.duplicate(true), "next_find": _next_find,
		"blocked": _blocked.duplicate(), "isolated": _isolated.duplicate(), "news": _news.duplicate(true), "next_news": _next_news, "digest": _digest.duplicate(), "day": _day, "inited": _inited}


func deserialize(d: Dictionary) -> void:
	_places = (d.get("places", {}) as Dictionary).duplicate(true)
	for node: String in _places:
		var p: Dictionary = _places[node]
		p["sid"] = int(p["sid"])
		p["camp"] = int(p["camp"])
		p["tier"] = int(p["tier"])
		for i in (p["proj"] as Array).size():
			p["proj"][i] = int(p["proj"][i])
		for k in ["farms", "walls", "stones", "refugees", "peak", "abandoned", "pop_seed", "since", "last", "founded", "ruin_day"]:
			p[k] = int(p.get(k, 0))
	_projects = {}
	for k: String in d.get("projects", {}):
		var pr: Dictionary = (d["projects"][k] as Dictionary).duplicate(true)
		for f in ["id", "site", "cost", "queued", "start", "done"]:
			pr[f] = int(pr[f])
		_projects[int(k)] = pr
	_next_project = int(d.get("next_project", 1))
	_finds = (d.get("finds", []) as Array).duplicate(true)
	_next_find = int(d.get("next_find", 1))
	_blocked = (d.get("blocked", {}) as Dictionary).duplicate()
	_isolated = (d.get("isolated", {}) as Dictionary).duplicate()
	_adj_n = -1
	_ids_cache = []
	_news = (d.get("news", []) as Array).duplicate(true)
	_next_news = int(d.get("next_news", 1))
	_seq = _next_news - 1
	for e: Dictionary in _news:   # saves from before news.gd wiring
		if not e.has("seq"):
			e["seq"] = int(e["id"])
			e["sid"] = news_sid(String(e["node"]))
			e["mag"] = float(NEWS_MAG.get(String(e["kind"]), 1.0))
	_digest = (d.get("digest", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	_inited = bool(d.get("inited", false))
