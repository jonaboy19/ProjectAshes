extends "res://scripts/realm/realm_module.gd"
## CIV-C living ecology (docs/design/CIVILIZATION.md). Extends sim/monster_ecology.gd (dens, species, migrations),
## sim/threat_map.gd and the goblin / orc camps with a per-zone population model.
##
##   * ZONES: one per settlement (nearest-settlement cells). Each holds populations for deer, boar, wolf,
##     corrupted wolf, bear, troll, wyvern, and a nest per present species. Danger on a road comes from the
##     specific pack whose territory covers it (danger_at / territories), never from random spawns.
##   * DYNAMICS: discrete Lotka-Volterra in exponential-Euler form (prey logistic, territorial mesopredators,
##     integer apex holders). catch_up integrates the same map with at most 30 larger substeps, so it is
##     O(zones) however long the absence. Migration is a continuous flow (season, crowding, apex pressure,
##     Rift instability) between neighbouring zones, planned weekly.
##   * SUCCESSION: an apex that leaves its niche lets prey boom; the boom and the vacancy raise the chance that a
##     WORSE apex moves in (bear -> troll -> wyvern). A wiped-out wolf pack lets corrupted wolves spread.
##   * FACTIONS (ecology_factions.gd): goblin / orc clans with a hidden intent (learn_intent reveals it).
##   * DOMESTICATION: slow per-settlement familiarity with boar, deer, wolf and wyvern (farming, resources, guarding,
##     transport).
##   * ADVENTURER ECONOMY: danger attracts adventurers; inn, equipment, healer, guide and bounty office levels follow
##     them and collapse when the danger is cleared.
## Live world: bind_frontier(eco, threat) mirrors zone populations into RAMonsterEcology dens (weekly) so the packs
## FrontierPresence spawns follow this simulation, and kills in the world flow back into it.
## Readers: hub.mod("ecology") with a null guard (civilization.gd, news.gd). See the getters below.

const D := preload("res://scripts/realm/ecology_data.gd")
const Factions := preload("res://scripts/realm/ecology_factions.gd")
const SEASONS := ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON := 28
const MAX_NEWS := 160
const MAX_SUBSTEPS := 30
const ZONES_PER_CHUNK := 4

## Static, derived from WorldGen (not saved): per zone {sid, name, pos, R, wild, kz, neigh, rift, dungeon, cap_dist}.
var _zones: Array = []
var _zone_of_sid: Dictionary = {}
## Saved: per zone {n[7], adv, svc[5], vac, lastA, starve, dom{}, seen{}, nest{}, boom, ema, acc{}, econ, gone{}}.
var _st: Array = []
var _route: Array = []
var _news: Array = []
var _seq := 0                     # monotonic event counter; news.gd consumes news_events(last_seq) with a cursor
var _msgs: Array = []
var _day := 0
var _season := "spring"
var rift := 0.1                   # Rift instability 0..1 (Frontier.rift_instability feeds it through the ctx or set_rift)
var events_enabled := true        # tests switch the discrete layer (apex arrivals, faction decisions) off
var _inited := false
var _factions: RefCounted = null
var _eco: RefCounted = null       # bound RAMonsterEcology (not saved)
var _eco_prev: RefCounted = null
var _threat: RefCounted = null
var _den_w: Dictionary = {}       # str(den id) -> [zone, species index, pop written]
var _capital := Vector2.ZERO
var _popc: Array = []             # settlement population per zone, refreshed once per day (hub lookups are not free)
var _atot := 0.0                  # total apex count / eligible zones, refreshed before each weekly apex pass
var _aelig := 1
var _fzone: Array = []            # zone each clan currently sits in (cache for _danger_x)
var _fort: Dictionary = {}        # str(settlement id) -> permanent defence bonus after raids (hired guards)
var _alert: Dictionary = {}       # str(settlement id) -> day until which it is on guard after a raid
var _told: Dictionary = {}        # "kind|faction|sid" -> last day a clan news line was written (throttle)


func seed_value() -> int:
	return int(WorldSim.SEED)


func _rng(tag: String, day: int, id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value(), tag, day, id])
	return r


# ====================================================================================================== setup

func _ensure() -> void:
	if _inited:
		return
	_inited = true
	_zones.clear()
	_st.clear()
	_route.clear()
	_zone_of_sid.clear()
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			_capital = s["pos"]
			break
	var rift_sites: Array = []
	var dungeon_sites: Array = []
	for site: Dictionary in WorldGen.sites:
		var k := String(site.get("kind", ""))
		if k == "rift" or k == "rift_outpost":
			rift_sites.append(site["pos"])
		if k in D.DUNGEON_KINDS:
			dungeon_sites.append(site["pos"])
	for g: Dictionary in WorldGen.camp_grounds:
		dungeon_sites.append(g["pos"])
	var n_set := WorldGen.settlements.size()
	for i in n_set:
		var s: Dictionary = WorldGen.settlements[i]
		var p: Vector2 = s["pos"]
		var near1 := INF
		var near2 := INF
		for j in n_set:
			if j == i:
				continue
			var d := p.distance_to(WorldGen.settlements[j]["pos"])
			if d < near1:
				near2 = near1
				near1 = d
			elif d < near2:
				near2 = d
		var R := clampf((near1 + near2) * 0.25, 450.0, 1400.0)
		var dens := 0.0
		for a in 12:
			var ang := TAU * a / 12.0
			var q := p + Vector2(cos(ang), sin(ang)) * R * 0.6
			dens += WorldGen.forest_density(q.x, q.y)
		var wild := clampf(dens / 12.0 / 0.55, 0.12, 1.0)
		var rsc := INF
		for rp: Vector2 in rift_sites:
			rsc = minf(rsc, p.distance_to(rp))
		_zones.append({"sid": int(s["id"]), "name": String(s["name"]), "pos": p, "R": R, "wild": wild, "kz": 0.25 + 0.85 * wild,
			"neigh": [], "rift": exp(-rsc / 1500.0) if rsc < INF else 0.0, "dungeon": 0.0, "cap_dist": p.distance_to(_capital),
			"kind": String(s["kind"])})
		_zone_of_sid[int(s["id"])] = i
	for i in n_set:
		var scored: Array = []
		for j in n_set:
			if j != i:
				scored.append([(_zones[i]["pos"] as Vector2).distance_to(_zones[j]["pos"]), j])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var nb: Array = []
		for k in mini(4, scored.size()):
			nb.append(int(scored[k][1]))
		_zones[i]["neigh"] = nb
	for dp: Vector2 in dungeon_sites:
		var zi := zone_of(dp)
		if zi >= 0:
			_zones[zi]["dungeon"] = float(_zones[zi]["dungeon"]) + 1.0
	for i in n_set:
		_st.append(_seed_state(i))
		_route.append([[-1, 0.0, ""], [-1, 0.0, ""], [-1, 0.0, ""], [-1, 0.0, ""]])
	_factions = Factions.new()
	_factions.seed_factions(self)
	_refresh_fzones()
	# Let the seed settle into its first equilibrium so the first in-game days are not a transient.
	for _k in 30:
		for i in n_set:
			_step_zone(i, 3.0, "summer", false)
	for i in n_set:
		var st: Dictionary = _st[i]
		for sp in D.SPECIES.size():
			if float((st["n"] as Array)[sp]) >= 1.0:
				(st["seen"] as Dictionary)[D.SPECIES[sp]] = 1
		st["ema"] = _prey_idx(i)
		st["econ"] = 1 if float(st["adv"]) >= 6.0 else 0
	_plan_routes("summer")


func _seed_state(i: int) -> Dictionary:
	var z: Dictionary = _zones[i]
	var r := _rng("ecoseed", 0, int(z["sid"]))
	var kz: float = z["kz"]
	var wild: float = z["wild"]
	var n := [D.PREY_K[0] * kz * r.randf_range(0.5, 0.8), D.PREY_K[1] * kz * r.randf_range(0.5, 0.8), 0.0, 0.0, 0.0, 0.0, 0.0]
	if wild >= 0.3:
		n[D.WOLF] = D.WOLF_K * kz * r.randf_range(0.4, 0.9)
	if float(z["rift"]) > 0.5:
		n[D.CORR] = r.randf_range(1.0, 3.0)
	var st := {"n": n, "adv": 0.0, "svc": [0.0, 0.0, 0.0, 0.0, 0.0], "vac": r.randi_range(40, 220), "lastA": "", "starve": 0,
		"dom": {}, "seen": {}, "nest": {}, "boom": 0, "ema": 0.7, "acc": {}, "econ": 0, "gone": {}}
	if wild >= 0.4 and r.randf() < 0.3:
		var cap := _apex_cap(i)
		var pick: int = D.BEAR
		var roll := r.randf()
		if roll > 0.85 and cap >= D.WYVERN:
			pick = D.WYVERN
		elif roll > 0.6 and cap >= D.TROLL:
			pick = D.TROLL
		n[pick] = 2.0 if pick == D.WYVERN else 1.0
		st["vac"] = 0
	for sp in D.DEN_SPECIES:
		if float(n[sp]) >= 0.5:
			(st["nest"] as Dictionary)[D.SPECIES[sp]] = _pick_nest(i, sp, r, false)
	return st


func _apex_cap(i: int) -> int:
	var d: float = _zones[i]["cap_dist"]
	for t: Array in D.TIER_MAX_APEX:
		if d < float(t[0]):
			return int(t[1])
	return D.WYVERN


func _pick_nest(i: int, sp: int, r: RandomNumberGenerator, near_village: bool) -> Array:
	var z: Dictionary = _zones[i]
	var c: Vector2 = z["pos"]
	var s: Dictionary = WorldGen.settlements[int(z["sid"])]
	var keep := float(s["radius"]) * 1.6
	var best := c
	var best_score := -INF
	for _t in 10:
		var ang := r.randf() * TAU
		var dist := r.randf_range(keep, maxf(keep + 60.0, float(z["R"]) * (0.4 if near_village else 0.85)))
		var q := c + Vector2(cos(ang), sin(ang)) * dist
		var score := WorldGen.forest_density(q.x, q.y) - (0.0 if not WorldGen.is_water(q.x, q.y) else 5.0)
		if near_village:
			score -= dist / 900.0
		if score > best_score:
			best_score = score
			best = q
	return [best.x, best.y]


# ====================================================================================================== spatial

func zone_count() -> int:
	_ensure()
	return _zones.size()


func zone_of(p: Vector2) -> int:
	if _zones.is_empty():
		_ensure()
	var best := -1
	var bd := INF
	for i in _zones.size():
		var d := p.distance_squared_to(_zones[i]["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func zone_index_of_settlement(sid: int) -> int:
	_ensure()
	return int(_zone_of_sid.get(sid, -1))


func sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[sid]["name"]))
	return "the frontier"


func _zname(i: int) -> String:
	return String(_zones[i]["name"])


func _nest_of(i: int, sp: int) -> Vector2:
	var nest: Variant = (_st[i]["nest"] as Dictionary).get(D.SPECIES[sp])
	if nest is Array and (nest as Array).size() == 2:
		return Vector2(float(nest[0]), float(nest[1]))
	return _zones[i]["pos"]


# ====================================================================================================== dynamics

func _prey_idx(i: int) -> float:
	var n: Array = _st[i]["n"]
	return (float(n[0]) + float(n[1])) / ((D.PREY_K[0] + D.PREY_K[1]) * float(_zones[i]["kz"]))


func prey_index_z(i: int) -> float:
	_ensure()
	return _prey_idx(i) if i >= 0 else 0.5


func apex_count_z(i: int) -> float:
	_ensure()
	if i < 0:
		return 0.0
	var n: Array = _st[i]["n"]
	return float(n[4]) + float(n[5]) + float(n[6])


func take_prey(i: int, amount: float) -> void:
	if i < 0 or amount <= 0.0:
		return
	var n: Array = _st[i]["n"]
	n[0] = maxf(float(n[0]) - amount * 0.6, 0.05)
	n[1] = maxf(float(n[1]) - amount * 0.4, 0.05)


func _danger_x(i: int) -> float:
	var n: Array = _st[i]["n"]
	var x := 0.0
	for sp in D.DEN_SPECIES:
		x += float(n[sp]) * D.THREAT[sp]
	if _factions != null:
		if _fzone.size() != _factions.list.size():
			_refresh_fzones()
		for k in _fzone.size():
			if int(_fzone[k]) == i:
				var f: Dictionary = _factions.list[k]
				if String(f["status"]) != "marching":
					x += float(f["strength"]) * 0.25
	return x


func _refresh_fzones() -> void:
	_fzone.clear()
	if _factions != null:
		for f: Dictionary in _factions.list:
			_fzone.append(zone_of(_factions.fpos(f)))


func _danger_of(i: int) -> float:
	var guard := float((_st[i]["dom"] as Dictionary).get("wolf", 0.0)) * 6.0
	return clampf(100.0 * (1.0 - exp(-_danger_x(i) / 25.0)) - guard, 0.0, 100.0)


func _refresh_pops() -> void:
	_popc.clear()
	for z: Dictionary in _zones:
		_popc.append(_pop_of(int(z["sid"])))


func _pop_z(i: int) -> int:
	if _popc.size() != _zones.size():
		_refresh_pops()
	return int(_popc[i])


func _pop_of(sid: int) -> int:
	var st: RefCounted = hub.mod("settlements") if hub != null else null
	if st != null and st.has_method("population"):
		return int(st.population(sid))
	if sid >= 0 and sid < WorldGen.settlements.size():
		return int(WorldGen.settlements[sid]["population"])
	return 100


func _step_zone(i: int, h: float, season: String, with_flows := true) -> void:
	var z: Dictionary = _zones[i]
	var st: Dictionary = _st[i]
	var n: Array = st["n"]
	var kz: float = z["kz"]
	var wild: float = z["wild"]
	var deer: float = n[0]
	var boar: float = n[1]
	var hz0 := 0.0
	var hz1 := 0.0
	var apex_w := 0.0
	for sp: int in [2, 3, 4, 5, 6]:
		var hz: Array = D.HAZARD[sp]
		var c: float = n[sp]
		hz0 += float(hz[0]) * c
		hz1 += float(hz[1]) * c
	for sp: int in D.APEX:
		apex_w += float(D.APEX_ON_WOLF[sp]) * float(n[sp])
	var kd: float = D.PREY_K[0] * kz
	var kb: float = D.PREY_K[1] * kz
	var g_d: float = float(D.PREY_R[0]) * (1.0 - (deer + float(D.PREY_CROSS[0]) * boar) / kd) - hz0
	var g_b: float = float(D.PREY_R[1]) * (1.0 - (boar + float(D.PREY_CROSS[1]) * deer) / kb) - hz1
	var f := clampf((deer + boar) / (0.6 * (kd + kb)), 0.05, 1.4)
	var human := (1.0 - wild) * (1.0 - wild) * D.HUMAN_HUNT * 8.0
	var adv: float = st["adv"]
	var adv_h: float = D.ADV_HUNT * adv
	var wolf: float = n[2]
	var corr: float = n[3]
	var kw: float = maxf(D.WOLF_K * kz * f, 0.3)
	var g_w := clampf(D.WOLF_R * (1.0 - wolf / kw) - apex_w - human - adv_h, -0.08, 0.05)
	var riftf := 0.25 + 1.4 * float(z["rift"]) * rift
	var kc: float = maxf(D.CORR_K * kz * f * riftf, 0.2)
	var g_c := clampf(D.CORR_R * (1.0 - (corr + 0.8 * wolf) / kc) - apex_w * 0.7 - human * 0.5 - adv_h, -0.08, 0.05)
	n[0] = maxf(deer * exp(clampf(g_d * h, -2.0, 2.0)), 0.05)
	n[1] = maxf(boar * exp(clampf(g_b * h, -2.0, 2.0)), 0.05)
	n[2] = wolf * exp(g_w * h)
	n[3] = corr * exp(g_c * h)
	if rift > 0.45 and float(z["rift"]) > 0.4:
		n[3] = float(n[3]) + D.RIFT_LEAK * float(z["rift"]) * (rift - 0.4) / 0.6 * h
	for sp: int in [2, 3]:
		if float(n[sp]) < D.EXTINCT_BELOW:
			if float(n[sp]) > 0.0:
				(st["gone"] as Dictionary)[D.SPECIES[sp]] = _day
			n[sp] = 0.0
	if with_flows:
		_apply_flows(i, h)
	_adventurers(i, h)
	_domestication(i, h)


func _apply_flows(i: int, h: float) -> void:
	var st: Dictionary = _st[i]
	var n: Array = st["n"]
	var routes: Array = _route[i]
	for s in 4:
		var rt: Array = routes[s]
		var dest := int(rt[0])
		var rate := float(rt[1])
		if dest < 0 or rate <= 0.0 or float(n[s]) < 0.05:
			continue
		var mv: float = float(n[s]) * (1.0 - exp(-rate * h))
		n[s] = float(n[s]) - mv
		(_st[dest]["n"] as Array)[s] = float((_st[dest]["n"] as Array)[s]) + mv
		var key: String = rt[3] if rt.size() > 3 else "%d|%d|%s" % [s, dest, String(rt[2])]
		var acc: Dictionary = st["acc"]
		acc[key] = float(acc.get(key, 0.0)) + mv


func _adventurers(i: int, h: float) -> void:
	var st: Dictionary = _st[i]
	var z: Dictionary = _zones[i]
	var dng := _danger_of(i)
	var att := smoothstep(14.0, 50.0, dng) * (1.0 - 0.6 * smoothstep(80.0, 100.0, dng))
	var size := clampf(0.5 + _pop_z(i) / 1200.0, 0.5, 2.0)
	var inflow: float = D.ADV_INFLOW * att * size + minf(float(z["dungeon"]), 4.0) * 0.12
	var lam: float = D.ADV_LEAVE_BASE + 0.05 * (1.0 - att)
	var e := exp(-lam * h)
	st["adv"] = float(st["adv"]) * e + inflow / lam * (1.0 - e)
	var svc: Array = st["svc"]
	var adv: float = st["adv"]
	for k in D.SERVICES.size():
		var target := minf(D.SERVICE_MAX, adv / float(D.SERVICE_PER[D.SERVICES[k]]))
		var cur: float = svc[k]
		var rate: float = D.SERVICE_UP if target > cur else D.SERVICE_DOWN
		svc[k] = target + (cur - target) * exp(-rate * h)


func _domestication(i: int, h: float) -> void:
	var st: Dictionary = _st[i]
	var n: Array = st["n"]
	var dom: Dictionary = st["dom"]
	var popf := clampf(0.6 + _pop_z(i) / 2000.0, 0.6, 1.3)
	for row: Array in D.DOM_ROWS:
		var sp_name: String = row[0]
		var p := clampf(float(n[int(row[1])]) / float(row[3]), 0.0, 1.0)
		var a: float = float(row[2]) * p * popf
		var b: float = D.DOMESTIC_DECAY * (1.0 - p)
		var s := a + b
		var fam: float = float(dom.get(sp_name, 0.0))
		if s > 0.0:
			var tgt := a / s
			fam = tgt + (fam - tgt) * exp(-s * h)
		if fam > 0.0005:
			dom[sp_name] = fam
		else:
			dom.erase(sp_name)


# ---------------------------------------------------------------------------------------- migration routes

func _plan_routes(season: String, from := 0, to := -1) -> void:
	for i in range(from, _zones.size() if to < 0 else to):
		var z: Dictionary = _zones[i]
		var n: Array = _st[i]["n"]
		var nb: Array = z["neigh"]
		var wild: float = z["wild"]
		var apex := apex_count_z(i)
		for s in 4:
			var dest := -1
			var rate := 0.0
			var why := ""
			if float(n[s]) < 0.2:
				_route[i][s] = [-1, 0.0, ""]
				continue
			if s == D.WOLF:
				if season == "winter":
					var d := _best_nb(nb, func(j: int) -> float: return -float(_zones[j]["wild"]))
					if d >= 0 and float(_zones[d]["wild"]) < wild - 0.08:
						dest = d
						rate = D.WINTER_WOLF_PUSH * minf((wild - float(_zones[d]["wild"])) / 0.4, 1.3)
						why = "winter"
				elif season == "spring":
					var d2 := _best_nb(nb, func(j: int) -> float: return float(_zones[j]["wild"]))
					if d2 >= 0 and float(_zones[d2]["wild"]) > wild + 0.08:
						dest = d2
						rate = D.SPRING_RETURN * (1.0 - wild)
						why = "return"
			elif s == D.DEER and season == "autumn":
				var d3 := _best_nb(nb, func(j: int) -> float: return float(_zones[j]["kz"]) * (1.0 - _prey_idx(j)))
				if d3 >= 0:
					dest = d3
					rate = D.AUTUMN_HERD_PUSH
					why = "autumn"
			# Crowding: prey near carrying capacity, wolves near their territory cap.
			var crowd := 0.0
			if s < 2:
				crowd = float(n[s]) / (float(D.PREY_K[s]) * float(z["kz"]))
			elif s == D.WOLF:
				crowd = float(n[s]) / maxf(D.WOLF_K * float(z["kz"]), 0.5)
			if crowd > 0.9 and _crowd_ok(s):
				var d4 := _best_nb(nb, func(j: int) -> float: return -_crowd_of(j, s))
				if d4 >= 0 and _crowd_of(d4, s) < crowd - 0.15 and D.CROWD_PUSH * (crowd - 0.9) > rate:
					dest = d4
					rate = D.CROWD_PUSH * minf(crowd - 0.9, 0.5)
					why = "crowding"
			# Apex pressure pushes wolves out, biased toward human land.
			if s == D.WOLF and apex > 0.4:
				var d5 := _best_nb(nb, func(j: int) -> float: return -apex_count_z(j) * 50.0 - _crowd_of(j, D.WOLF) + 0.6 * (1.0 - float(_zones[j]["wild"])))
				if d5 >= 0 and D.FLEE_PUSH * apex > rate:
					dest = d5
					rate = D.FLEE_PUSH * minf(apex, 2.0)
					why = "apex"
			if s == D.CORR and rift > 0.45 and float(z["rift"]) > 0.5:
				var d6 := _best_nb(nb, func(j: int) -> float: return -_crowd_of(j, D.CORR) - float(_zones[j]["rift"]))
				if d6 >= 0 and D.RIFT_PUSH * (rift - 0.4) / 0.6 > rate:
					dest = d6
					rate = D.RIFT_PUSH * (rift - 0.4) / 0.6
					why = "rift"
			_route[i][s] = [dest, rate, why, "%d|%d|%s" % [s, dest, why]] if dest >= 0 and rate > 0.0 else [-1, 0.0, ""]


func _crowd_ok(s: int) -> bool:
	return s != D.CORR


func _crowd_of(j: int, s: int) -> float:
	var nn: float = (_st[j]["n"] as Array)[s]
	if s < 2:
		return nn / (float(D.PREY_K[s]) * float(_zones[j]["kz"]))
	var kk: float = D.WOLF_K if s == D.WOLF else D.CORR_K
	return nn / maxf(kk * float(_zones[j]["kz"]), 0.5)


func _best_nb(nb: Array, score: Callable) -> int:
	var best := -1
	var bs := -INF
	for j: int in nb:
		var v: float = score.call(j)
		if v > bs:
			bs = v
			best = j
	return best


# ====================================================================================================== discrete layer

## Weekly: apex arrival, starvation, reproduction, adventurer kills, colonisation. `weeks` > 1 in catch_up
## (expected value: the per-week chance is compounded, one draw).
func _apex_week(i: int, weeks: float, tag: String, day: int) -> void:
	var st: Dictionary = _st[i]
	var n: Array = st["n"]
	var z: Dictionary = _zones[i]
	var r := _rng("apex" + tag, day, i)
	var apex := apex_count_z(i)
	if apex > 0.4:
		st["vac"] = 0
		var holder := D.BEAR
		for sp: int in D.APEX:
			if float(n[sp]) > float(n[holder]):
				holder = sp
		st["lastA"] = D.SPECIES[holder]
		var food := (( float(n[0]) + float(n[1])) * 0.5 + float(n[2]) * 3.0) / apex
		if food < D.APEX_NEED * 0.6:
			st["starve"] = int(st["starve"]) + int(ceil(weeks))
		else:
			st["starve"] = maxi(0, int(st["starve"]) - int(ceil(weeks)))
		if int(st["starve"]) >= 4:
			st["starve"] = 0
			_apex_lost(i, holder, "starved")
			return
		if not events_enabled:
			return
		var kill_p := clampf(0.0004 * float(st["adv"]) * weeks, 0.0, 0.25)
		if r.randf() < kill_p and float(st["adv"]) > 4.0:
			_apex_lost(i, holder, "slain")
			return
		if float(n[holder]) >= 2.0 and float(n[holder]) < D.APEX_MAX and food > D.APEX_NEED * 1.6 and r.randf() < 0.02 * weeks:
			n[holder] = float(n[holder]) + 1.0
			_news_add("brood", "The %s above %s has young; more are coming." % [D.LABEL[D.SPECIES[holder]], _zname(i)], i, 1)
		return
	st["vac"] = int(st["vac"]) + int(round(weeks * 7.0))
	if not events_enabled or float(z["wild"]) < 0.35:
		return
	var idx := _prey_idx(i)
	var surge := clampf((idx - 0.45) / 0.3, 0.0, 1.5)
	var vac_f := clampf(float(st["vac"]) / 90.0, 0.0, 2.0)
	var total_apex := _atot
	var eligible := _aelig
	var near_apex := 0.0
	for j: int in z["neigh"]:
		near_apex += apex_count_z(j)
	var room := clampf(1.0 - total_apex / (0.5 * maxf(eligible, 1.0)), 0.0, 1.0)
	var p_week := 0.005 * vac_f * surge * (1.6 if String(st["lastA"]) != "" else 1.0) * room / (1.0 + 1.5 * near_apex)
	var p := 1.0 - pow(1.0 - p_week, weeks)
	if r.randf() < p:
		var cap := _apex_cap(i)
		var pick := D.BEAR
		var last := String(st["lastA"])
		if last != "" and r.randf() < 0.7:
			pick = D.SPECIES.find(D.WORSE.get(last, last))
		else:
			var roll := r.randf()
			pick = D.WYVERN if roll > 0.85 else (D.TROLL if roll > 0.6 else D.BEAR)
		pick = mini(pick, cap)
		n[pick] = 2.0 if pick == D.WYVERN else 1.0
		st["vac"] = 0
		st["starve"] = 0
		(st["nest"] as Dictionary)[D.SPECIES[pick]] = _pick_nest(i, pick, r, false)
		st["lastA"] = D.SPECIES[pick]
		var sp_name: String = D.SPECIES[pick]
		var text := "A wyvern pair has nested above %s." % _zname(i) if pick == D.WYVERN else "A %s has moved into the hills above %s." % [D.LABEL[sp_name], _zname(i)]
		_news_add("apex_arrival", text, i, 3, _nest_of(i, pick), {"species": sp_name, "worse": last != "" and last != sp_name})
		(st["seen"] as Dictionary)[sp_name] = 1


func _refresh_apex_totals() -> void:
	_atot = 0.0
	_aelig = 0
	for j in _zones.size():
		_atot += apex_count_z(j)
		if float(_zones[j]["wild"]) >= 0.35:
			_aelig += 1


func _apex_lost(i: int, sp: int, how: String) -> void:
	var n: Array = _st[i]["n"]
	n[sp] = maxf(float(n[sp]) - 1.0, 0.0)
	if float(n[sp]) < 0.5:
		n[sp] = 0.0
	var name: String = D.LABEL[D.SPECIES[sp]]
	_st[i]["lastA"] = D.SPECIES[sp]
	if how == "slain":
		_news_add("apex_slain", "Adventurers have slain the %s that haunted %s." % [name, _zname(i)], i, 2)
	elif how == "hunted":
		_news_add("apex_slain", "The %s above %s is dead." % [name, _zname(i)], i, 3)
	else:
		_news_add("apex_gone", "The %s above %s has left, half starved." % [name, _zname(i)], i, 1)


## Crossing-threshold events, once a week: boom, bust, sightings, migrations, economy swings.
func _detect(i: int) -> void:
	var st: Dictionary = _st[i]
	var n: Array = st["n"]
	var idx := _prey_idx(i)
	var ema: float = st["ema"]
	var wolves_gone := float(n[2]) < 0.5
	if int(st["boom"]) == 0 and idx > 0.5 and idx > 1.45 * ema:
		st["boom"] = 1
		var why := "Wolves gone from %s, deer everywhere." % _zname(i) if wolves_gone else ("With the %s gone, deer and boar are everywhere around %s." % [String(st["lastA"]).replace("_", " "), _zname(i)] if String(st["lastA"]) != "" and apex_count_z(i) < 0.4 else "Deer and boar are multiplying around %s; the fields are trampled." % _zname(i))
		_news_add("prey_boom", why, i, 2, _zones[i]["pos"], {"pest": true})
	elif int(st["boom"]) == 1 and idx <= 1.25 * ema:
		st["boom"] = 0
	st["ema"] = lerpf(ema, idx, 0.12)
	var gone: Dictionary = st["gone"]
	for gname: String in gone.keys():
		if gname == "wolf" and _day > 28 and _day - int(gone[gname]) <= 7 and float(n[D.WOLF]) < 0.25 and float(_zones[i]["wild"]) >= 0.35:
			var gk := "gone|%d|%s" % [i, gname]
			if _day - int(_told.get(gk, -999)) > 560:
				_told[gk] = _day
				_news_add("species_gone", "The %s are gone from %s%s." % [_plural(D.LABEL[gname]), _zname(i), ", and the deer are already crowding the fields" if idx > 0.6 else ""], i, 2, _zones[i]["pos"], {"species": gname})
	var seen: Dictionary = st["seen"]
	for sp in D.SPECIES.size():
		var name: String = D.SPECIES[sp]
		if float(n[sp]) >= 1.0 and not seen.has(name):
			seen[name] = 1
			if sp != D.DEER and sp != D.BOAR and not _event_since(i, "apex_arrival", 3):
				_news_add("sighting", "%s folk see %s for the first time." % [_zname(i), _plural(D.LABEL[name])], i, 2, _zones[i]["pos"], {"species": name})
	# Flow accumulators -> migration news.
	var acc: Dictionary = st["acc"]
	var told := 0
	for key: String in acc:
		var amount: float = acc[key]
		if amount < 1.2 or told >= 1:
			continue
		var parts := key.split("|")
		var sp2 := int(parts[0])
		var dest := int(parts[1])
		var why2 := String(parts[2])
		if sp2 < 2:
			continue
		var cause: String = {"winter": "driven down by the winter cold", "apex": "fleeing the beast in the hills", "rift": "stirred by the Rift",
			"crowding": "crowded out of the hills", "return": "returning to the hills", "autumn": "on the autumn move"}.get(why2, "on the move")
		if why2 == "return":
			continue
		acc[key] = 0.0
		var mk := "mig|%d|%d|%s" % [dest, sp2, why2]
		if _day - int(_told.get(mk, -999)) < 56:
			continue
		_told[mk] = _day
		told += 1
		_news_add("migration", "%s are moving into the land around %s, %s." % [_plural(D.LABEL[D.SPECIES[sp2]]).capitalize(), _zname(dest), cause],
			dest, 2 if float((_zones[dest]["wild"])) < 0.5 else 1, _zones[dest]["pos"], {"species": D.SPECIES[sp2], "reason": why2, "from": _zname(i)})
	for key2: String in acc.keys():
		acc[key2] = float(acc[key2]) * 0.75
		if float(acc[key2]) < 0.05:
			acc.erase(key2)
	# Adventurer economy swings.
	var adv: float = st["adv"]
	var econ := int(st["econ"])
	if econ == 0 and adv >= 6.0:
		st["econ"] = 1
		_news_add("adventurers", "Adventurers are flocking to %s; the inn is full and the bounty board never empties." % _zname(i), i, 1)
	elif econ == 1 and adv < 2.0:
		st["econ"] = 0
		_news_add("adventurers_left", "With the danger gone, the adventurers have left %s; the inn sits empty." % _zname(i), i, 2)


func _plural(name: String) -> String:
	return name.substr(0, name.length() - 4) + "wolves" if name.ends_with("wolf") else name + "s"


func _event_since(i: int, kind: String, days: int) -> bool:
	for k in range(_news.size() - 1, maxi(-1, _news.size() - 12), -1):
		var e: Dictionary = _news[k]
		if String(e["kind"]) == kind and int(e["zone"]) == i and _day - int(e["day"]) <= days:
			return true
	return false


func _news_add(kind: String, text: String, zone: int, importance: int, pos: Variant = null, extra: Dictionary = {}) -> void:
	var p: Vector2 = pos if pos is Vector2 else (_zones[zone]["pos"] if zone >= 0 else Vector2.ZERO)
	_seq += 1
	var e := {"id": _seq, "seq": _seq, "day": _day, "kind": kind, "text": text, "zone": zone, "sid": int(_zones[zone]["sid"]) if zone >= 0 else -1,
		"importance": importance, "mag": float(importance), "detail": "", "official": false, "pos": [p.x, p.y], "topic": "ecology"}
	e.merge(extra)
	_news.append(e)
	if _news.size() > MAX_NEWS:
		_news = _news.slice(_news.size() - MAX_NEWS)
	_msgs.append([importance, p, text])


# ----------------------------------------------------------------------------------------- faction callbacks

func faction_news(f: Dictionary, kind: String, sid: int, _day_n: int) -> void:
	var clan := String(f["name"])
	var sp_label := "goblin" if String(f["species"]) == "goblin" else "orc"
	var place := sname(sid)
	var z := zone_of(Vector2(f["pos"][0], f["pos"][1]))
	var tk := "%s|%d|%d" % [kind, int(f["id"]), sid]
	if kind in ["trade_start", "parley", "parley_failed", "raid_repelled"]:
		if _day - int(_told.get(tk, -999)) < 84:
			return
		_told[tk] = _day
	match kind:
		"trade_start":
			_news_add("monster_trade", "%s traders from the %s have been seen at the market of %s." % [sp_label.capitalize(), clan, place], z, 1, _zones[z]["pos"], {"faction": int(f["id"]), "sid": sid})
		"raid":
			_news_add("monster_raid", "The %s raided %s and got away with food and plunder." % [clan, place], z, 3, WorldGen.settlements[sid]["pos"], {"faction": int(f["id"]), "sid": sid})
		"raid_repelled":
			_news_add("monster_raid", "Raiders of the %s were driven off from %s." % [clan, place], z, 2, WorldGen.settlements[sid]["pos"], {"faction": int(f["id"]), "sid": sid})
		"parley":
			_news_add("monster_parley", "%s envoys met the elders of %s and left in peace." % [sp_label.capitalize(), place], z, 1, _zones[z]["pos"], {"faction": int(f["id"]), "sid": sid})
		"parley_failed":
			_news_add("monster_parley", "Talks between %s and the %s ended in shouting." % [place, clan], z, 1, _zones[z]["pos"], {"faction": int(f["id"]), "sid": sid})
		"march":
			_news_add("monster_march", "A column of %ss has been seen marching away from their camp." % sp_label, z, 2, _zones[z]["pos"], {"faction": int(f["id"])})
		"settled":
			_news_add("monster_settled", "The %s have settled a new camp above %s." % [clan, _zname(z)], z, 2, _zones[z]["pos"], {"faction": int(f["id"])})
		"settle_near":
			_news_add("monster_settled", "The %s have pitched camp beside %s and ask to trade." % [clan, place], z, 2, _zones[z]["pos"], {"faction": int(f["id"]), "sid": sid})


func defense_of(sid: int) -> float:
	_ensure()
	var d := 3.0 + _pop_of(sid) * 0.025
	var zi := zone_index_of_settlement(sid)
	if zi >= 0:
		d += float(_st[zi]["adv"]) * 1.2 + float((_st[zi]["dom"] as Dictionary).get("wolf", 0.0)) * 6.0
	var stm: RefCounted = hub.mod("settlements") if hub != null else null
	if stm != null and stm.has_method("dominant"):
		if String(stm.dominant(sid)) == "fortress":
			d *= 1.5
	if int(_alert.get(str(sid), -1)) > _day:
		d *= 1.6
	return d * (1.0 + float(_fort.get(str(sid), 0.0)))


func raid_lands(sid: int, severity: float) -> void:
	_alert[str(sid)] = _day + 60
	_fort[str(sid)] = minf(float(_fort.get(str(sid), 0.0)) + 0.15, 1.0)
	var stm: RefCounted = hub.mod("settlements") if hub != null else null
	if stm != null and stm.has_method("raid_aftermath"):
		stm.raid_aftermath(sid, severity)


func trade_goods(sid: int, vol: float) -> void:
	var stm: RefCounted = hub.mod("settlements") if hub != null else null
	if stm == null or not stm.has_method("add_stock"):
		return
	stm.add_stock(sid, "ore", vol)
	if stm.has_method("supply_of") and float(stm.supply_of(sid, "grain")) > vol * 4.0:
		stm.add_stock(sid, "grain", -vol * 0.5)


## Where a clan that must move would go: a neighbouring zone with plenty of prey and no apex, away from human land.
func best_refuge(from: Vector2) -> Vector2:
	_ensure()
	var z0 := zone_of(from)
	var best := z0
	var bs := -INF
	for j in _zones.size():
		if j == z0:
			continue
		var d := from.distance_to(_zones[j]["pos"])
		if d > 3200.0:
			continue
		var sc := _prey_idx(j) * 2.0 - apex_count_z(j) * 1.2 - d / 2500.0 + float(_zones[j]["wild"]) * 0.6
		if sc > bs:
			bs = sc
			best = j
	var r := _rng("refuge", int(from.x), int(from.y))
	var nest := _pick_nest(best, D.WOLF, r, false)
	return Vector2(nest[0], nest[1])


# ====================================================================================================== ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	var out: Array = []
	out.append(func() -> Array:
		_ensure()
		_day = day
		_refresh_pops()
		var s := String(ctx.get("season", ""))
		_season = s if s in SEASONS else _season_of(day)
		var rv: float = _rift_from(ctx)
		if rv >= 0.0:
			rift = rv
		return [])
	for start in range(0, maxi(WorldGen.settlements.size(), 1), ZONES_PER_CHUNK):
		var a: int = start
		out.append(func() -> Array:
			for i in range(a, mini(a + ZONES_PER_CHUNK, _zones.size())):
				_step_zone(i, 1.0, _season)
			return [])
	out.append(func() -> Array:
		if events_enabled and _factions != null:
			_factions.tick_day(day)
			_refresh_fzones()
		return [])
	if day % 7 == 0:
		for third in 3:
			var t3: int = third
			out.append(func() -> Array:
				_plan_routes(_season, t3 * 7, mini(t3 * 7 + 7, _zones.size()))
				return [])
		out.append(func() -> Array:
			_refresh_apex_totals()
			for i in range(0, _zones.size()):
				_apex_week(i, 1.0, "w", day)
			return [])
		out.append(func() -> Array:
			for i in range(0, _zones.size()):
				_detect(i)
			return [])
		out.append(func() -> Array:
			_sync_dens()
			return [])
	out.append(func() -> Array:
		return _take_msgs(ctx))
	return out


func _season_of(day: int) -> String:
	return SEASONS[(posmod(day - 1, DAYS_PER_SEASON * 4)) / DAYS_PER_SEASON]


func _rift_from(ctx: Dictionary) -> float:
	if ctx.has("rift_instability"):
		return float(ctx["rift_instability"])
	if ctx.get("life") != null:
		var loop := Engine.get_main_loop()
		var fr: Node = (loop as SceneTree).root.get_node_or_null("Frontier") if loop is SceneTree else null
		if fr != null:
			return float(fr.get("rift_instability"))
	return -1.0


func set_rift(v: float) -> void:
	rift = clampf(v, 0.0, 1.0)


func _take_msgs(ctx: Dictionary) -> Array:
	var out: Array = []
	var pp: Variant = ctx.get("player_pos")
	for m: Array in _msgs:
		if int(m[0]) >= 3 or (int(m[0]) == 2 and pp is Vector2 and (pp as Vector2).distance_to(m[1]) < 1800.0):
			out.append(String(m[2]))
	_msgs.clear()
	return out.slice(0, 3)


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


## `days` passed unobserved. The same map as tick_day with at most MAX_SUBSTEPS larger steps (exponential Euler keeps
## it stable), expected-value discrete events, and a bounded number of faction decision cycles.
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	if days <= 0:
		return []
	var start_day := _day
	_refresh_pops()
	var rv := _rift_from(ctx)
	if rv >= 0.0:
		rift = rv
	var n_sub := clampi(int(ceil(days / 7.0)), 1, MAX_SUBSTEPS)
	var h := float(days) / n_sub
	var weeks := h / 7.0
	for k in n_sub:
		_day = start_day + int(round((k + 0.5) * h))
		_season = _season_of(_day)
		_plan_routes(_season)
		for i in _zones.size():
			_step_zone(i, h, _season)
		_refresh_apex_totals()
		for i in _zones.size():
			_apex_week(i, weeks, "cu%d" % k, start_day)
		for i in _zones.size():
			_detect(i)
	_day = start_day + days
	if events_enabled and _factions != null:
		var cycles := mini(int(days / D.DECISION_DAYS), 6)
		var step := float(days) / maxf(cycles, 1)
		for c in cycles:
			var dd := start_day + int(round((c + 1) * step))
			for f: Dictionary in _factions.list:
				_factions._upkeep(f, step)
				if String(f["status"]) == "marching":
					_factions._arrive(f, dd)
				elif int(f["exec"]) >= 0:
					_factions._execute(f, dd)
				_factions._decide(f, dd)
	_refresh_fzones()
	_sync_dens()
	var out := _take_msgs(ctx)
	if days >= 3 and not out.is_empty():
		out.push_front("While you were away: word of the wilds reached you.")
	return out


# ====================================================================================================== live den mirror

## Mirrors zone populations into a live RAMonsterEcology (FrontierPresence spawns packs from its dens). Kills and
## outside arrivals (frontier.gd apex arrivals, den migrations) flow back in. `threat` (RAThreatMap) gets the
## monster-clan bands through its territory_source hook.
func bind_frontier(eco: RefCounted, threat: RefCounted = null) -> void:
	_ensure()
	_eco = eco
	_threat = threat
	if threat != null:
		threat.set("territory_source", Callable(self, "threat_lines"))
	if _eco_prev != null and _eco_prev != eco:
		_den_w = {}                  # a new game replaced the live ecology: its den ids mean nothing here
	_eco_prev = eco
	var adopt := _den_w.is_empty()
	var keep := {}
	for k: String in _den_w:
		if int(k) < eco.dens.size():
			keep[k] = _den_w[k]
	_den_w = keep
	if adopt:
		_adopt_dens()


func is_bound_to(eco: RefCounted) -> bool:
	return _eco != null and _eco == eco


func _adopt_dens() -> void:
	var sums := {}
	for zi in _zones.size():
		for sp in D.DEN_SPECIES:
			sums["%d|%d" % [zi, sp]] = 0.0
	var cx := {}
	for den: Dictionary in _eco.dens:
		var sp: int = D.SPECIES.find(String(den["species"]))
		if sp < 0 or not sp in D.DEN_SPECIES:
			continue
		if not bool(den["alive"]) or int(den["population"]) <= 0:
			continue
		var zi := zone_of(den["pos"])
		var key := "%d|%d" % [zi, sp]
		sums[key] = float(sums[key]) + float(den["population"])
		cx[key] = den["pos"] if not cx.has(key) else cx[key]
		_den_w[str(int(den["id"]))] = [zi, sp, int(den["population"])]
	for zi in _zones.size():
		var n: Array = _st[zi]["n"]
		for sp in D.DEN_SPECIES:
			var key := "%d|%d" % [zi, sp]
			n[sp] = float(sums[key])
			if cx.has(key):
				var p: Vector2 = cx[key]
				(_st[zi]["nest"] as Dictionary)[D.SPECIES[sp]] = [p.x, p.y]
			else:
				(_st[zi]["nest"] as Dictionary).erase(D.SPECIES[sp])
			if float(n[sp]) >= 1.0:
				(_st[zi]["seen"] as Dictionary)[D.SPECIES[sp]] = 1


func _den_cap(sp: int) -> int:
	if sp in D.APEX:
		return 1
	return maxi(1, int(float(RAMonsterEcology.SPECIES[D.SPECIES[sp]]["max_pop"]) * 0.8))


func _sync_dens() -> void:
	if _eco == null:
		return
	# Pull: kills and starvation lower the zone, dens nobody here knew about add to it.
	for den: Dictionary in _eco.dens:
		var sp: int = D.SPECIES.find(String(den["species"]))
		if sp < 0 or not sp in D.DEN_SPECIES:
			continue
		var key := str(int(den["id"]))
		var cur: int = int(den["population"]) if bool(den["alive"]) else 0
		if _den_w.has(key):
			var e: Array = _den_w[key]
			var old := int(e[2])
			if cur < old:
				var n: Array = _st[int(e[0])]["n"]
				n[int(e[1])] = maxf(float(n[int(e[1])]) - float(old - cur), 0.0)
			e[2] = cur
		elif cur > 0:
			var zi := zone_of(den["pos"])
			var n2: Array = _st[zi]["n"]
			n2[sp] = float(n2[sp]) + float(cur)
			_den_w[key] = [zi, sp, cur]
			(_st[zi]["nest"] as Dictionary)[D.SPECIES[sp]] = [den["pos"].x, den["pos"].y]
	# Push: make the den list say what the zone holds.
	for zi in _zones.size():
		for sp in D.DEN_SPECIES:
			_push_zone_species(zi, sp)


func _push_zone_species(zi: int, sp: int) -> void:
	var n: Array = _st[zi]["n"]
	var target := int(round(float(n[sp]))) if float(n[sp]) >= 0.5 else 0
	var cap := _den_cap(sp)
	var ids: Array = []
	for k: String in _den_w:
		var e: Array = _den_w[k]
		if int(e[0]) == zi and int(e[1]) == sp and bool(_eco.dens[int(k)]["alive"]):
			ids.append(int(k))
	ids.sort()
	var need := int(ceil(float(target) / cap))
	var remaining := target
	var name: String = D.SPECIES[sp]
	var i := 0
	while remaining > 0:
		var id := -1
		if i < ids.size():
			id = ids[i]
		else:
			if _eco.alive_count() >= RAMonsterEcology.MAX_ALIVE_DENS + 40:
				break
			var r := _rng("denpos", _day, zi * 16 + sp + i * 97)
			var nest := _nest_of(zi, sp)
			var ang := r.randf() * TAU
			var pos := nest + Vector2(cos(ang), sin(ang)) * (r.randf_range(15.0, 70.0) if i > 0 else 0.0)
			var den: Dictionary
			if sp in D.APEX:
				den = _eco.spawn_apex(name, pos, _eco.current_day())
			else:
				den = _eco.add_den(name, pos, 0)
			id = int(den["id"])
			_den_w[str(id)] = [zi, sp, 0]
		var d: Dictionary = _eco.dens[id]
		var pop := mini(cap, remaining)
		d["population"] = pop
		d["alive"] = true
		var base_t: float = float(RAMonsterEcology.SPECIES[name]["territory"])
		d["territory"] = base_t * (0.75 + 0.35 * minf(1.0, float(pop) / float(cap)))
		(_den_w[str(id)] as Array)[2] = pop
		remaining -= pop
		i += 1
	for j in range(i, ids.size()):
		var d2: Dictionary = _eco.dens[ids[j]]
		d2["population"] = 0
		d2["alive"] = false
		(_den_w[str(ids[j])] as Array)[2] = 0
	if need > 0 and ids.size() > 0:
		var nd: Dictionary = _eco.dens[ids[0]]
		(_st[zi]["nest"] as Dictionary)[name] = [nd["pos"].x, nd["pos"].y]


## Threat-map hook (RAThreatMap.territory_source): [[label, value]] for the intelligent clans' hunting bands.
func threat_lines(p: Vector2) -> Array:
	_ensure()
	return _factions.band_threat(p) if _factions != null else []


# ====================================================================================================== readers (CIV-A / CIV-B / UI)

func population(sid: int, species: String) -> float:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	var sp := D.SPECIES.find(species)
	if zi < 0 or sp < 0:
		return 0.0
	return float((_st[zi]["n"] as Array)[sp])


func populations(sid: int) -> Dictionary:
	_ensure()
	var out := {}
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return out
	for sp in D.SPECIES.size():
		out[D.SPECIES[sp]] = int(round(float((_st[zi]["n"] as Array)[sp])))
	return out


func prey_index(sid: int) -> float:
	return prey_index_z(zone_index_of_settlement(sid))


## 0..100 danger of the land around a settlement (packs, apex, hostile clans, minus guard animals).
func danger_level(sid: int) -> float:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	return _danger_of(zi) if zi >= 0 else 0.0


## Migration push for CIV-A: 0..1 how much monsters press on the place (emigration pressure).
func monster_pressure(sid: int) -> float:
	return danger_level(sid) / 100.0


## Pests eating the fields: 0..1, high after a prey boom.
func crop_damage(sid: int) -> float:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return 0.0
	return clampf((_prey_idx(zi) - 0.7) / 0.3, 0.0, 1.0)


func species_seen(sid: int) -> Array:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	return (_st[zi]["seen"] as Dictionary).keys() if zi >= 0 else []


## Every territory: {zone, sid, species, group, nest, range, pop, name}. Danger on a road comes from these.
func territories() -> Array:
	_ensure()
	var out: Array = []
	for i in _zones.size():
		var n: Array = _st[i]["n"]
		for sp in D.DEN_SPECIES:
			if float(n[sp]) < 0.5:
				continue
			out.append(_territory(i, sp))
	return out


func _territory(i: int, sp: int) -> Dictionary:
	var n: Array = _st[i]["n"]
	var name: String = D.SPECIES[sp]
	var base := float(RAMonsterEcology.SPECIES[name]["territory"]) if RAMonsterEcology.SPECIES.has(name) else 200.0
	var cap := float(_den_cap(sp))
	var rng := base * (0.75 + 0.35 * minf(1.0, float(n[sp]) / cap))
	var group: String = D.GROUP_NAME.get(name, "pack")
	return {"zone": i, "sid": int(_zones[i]["sid"]), "species": name, "group": group, "nest": _nest_of(i, sp), "range": rng,
		"pop": float(n[sp]), "name": "%s %s %s" % [_zname(i), D.LABEL[name], group], "value": float(n[sp]) * D.THREAT[sp]}


## Explainable danger at p from specific packs: {total, sources: [{name, species, value, nest, zone, pop}]}.
func danger_at(p: Vector2) -> Dictionary:
	_ensure()
	var total := 0.0
	var sources: Array = []
	var zi := zone_of(p)
	var cand: Array = [zi]
	cand.append_array(_zones[zi]["neigh"])
	for i: int in cand:
		var n: Array = _st[i]["n"]
		for sp in D.DEN_SPECIES:
			if float(n[sp]) < 0.5:
				continue
			var t := _territory(i, sp)
			var d := p.distance_to(t["nest"])
			var r: float = t["range"]
			if d > r * 1.6:
				continue
			var v: float = float(n[sp]) * D.THREAT[sp] * (1.0 - smoothstep(r * 0.3, r * 1.6, d)) * 3.0
			if v > 0.5:
				sources.append({"name": t["name"], "species": t["species"], "value": v, "nest": t["nest"], "zone": i, "pop": t["pop"]})
				total += v
	if _factions != null:
		for line: Array in _factions.band_threat(p):
			sources.append({"name": line[0], "species": "clan", "value": line[1], "nest": p, "zone": zi, "pop": 0.0})
			total += float(line[1])
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["value"]) > float(b["value"]))
	return {"total": minf(total, 100.0), "sources": sources}


## Worst danger along a road segment (samples every ~120 m) with the pack responsible.
func road_danger(a: Vector2, b: Vector2) -> Dictionary:
	var steps := maxi(2, int(a.distance_to(b) / 120.0))
	var worst := {"total": -1.0, "sources": []}
	for k in steps + 1:
		var d := danger_at(a.lerp(b, float(k) / steps))
		if float(d["total"]) > float(worst["total"]):
			worst = d
	return worst


# ---- adventurer economy

func adventurers(sid: int) -> float:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	return float(_st[zi]["adv"]) if zi >= 0 else 0.0


## Service levels 0..4 (floats) for inn, equipment, healer, guide, bounty_office.
func services(sid: int) -> Dictionary:
	_ensure()
	var out := {}
	var zi := zone_index_of_settlement(sid)
	for k in D.SERVICES.size():
		out[D.SERVICES[k]] = float((_st[zi]["svc"] as Array)[k]) if zi >= 0 else 0.0
	return out


func adventurer_economy(sid: int) -> Dictionary:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return {}
	var svc := services(sid)
	var total := 0.0
	for k: String in svc:
		total += float(svc[k])
	return {"sid": sid, "adventurers": float(_st[zi]["adv"]), "danger": _danger_of(zi), "services": svc, "prosperity": total / (D.SERVICES.size() * D.SERVICE_MAX),
		"explorer_traffic": float(_zones[zi]["dungeon"]), "explorer_town": total > 2.5 and float(_zones[zi]["dungeon"]) > 0.0}


## Open bounties: one per pack or apex above a threat threshold; reward scales with threat.
func bounties(sid: int) -> Array:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	var out: Array = []
	if zi < 0 or float((_st[zi]["svc"] as Array)[4]) < 0.3:
		return out
	for sp in D.DEN_SPECIES:
		var pop: float = (_st[zi]["n"] as Array)[sp]
		if pop >= 1.0 and float(pop) * D.THREAT[sp] >= 4.0:
			out.append({"species": D.SPECIES[sp], "zone": zi, "reward": int(round(20.0 * D.THREAT[sp] * sqrt(pop))), "target": _territory(zi, sp)["name"]})
	return out


# ---- domestication

func domestication(sid: int) -> Dictionary:
	_ensure()
	var out := {}
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return out
	var dom: Dictionary = _st[zi]["dom"]
	for sp_name: String in D.DOMESTIC:
		var fam := float(dom.get(sp_name, 0.0))
		var level := "wild"
		for lv: Array in D.DOM_LEVELS:
			if fam < float(lv[0]):
				level = String(lv[1])
				break
		out[sp_name] = {"familiarity": fam, "level": level, "use": D.DOMESTIC[sp_name]["use"]}
	return out


## 0..1 strength of a use ("farming", "transport", "guarding", "resources") from domesticated stock near a settlement.
func domestic_bonus(sid: int, use: String) -> float:
	var tot := 0.0
	var dm := domestication(sid)
	for sp_name: String in dm:
		if String(dm[sp_name]["use"]) == use:
			tot += float(dm[sp_name]["familiarity"])
	return clampf(tot, 0.0, 1.0)


# ---- monster factions

func factions() -> Array:
	_ensure()
	var out: Array = []
	for f: Dictionary in _factions.list:
		out.append(_factions.view(int(f["id"])))
	return out


func faction_view(fid: int) -> Dictionary:
	_ensure()
	return _factions.view(fid)


## Gameplay (scouting, interrogation, a trader's tip) teaches the player a clan's intent. level 1 = its kind, 2 = exact.
func learn_intent(fid: int, level := 2) -> bool:
	_ensure()
	return _factions.learn(fid, level, _day)


func faction_index(place_id: String) -> int:
	_ensure()
	for f: Dictionary in _factions.list:
		if String(f["place"]) == place_id:
			return int(f["id"])
	return -1


## Monster camps (scripts/world/monster_camps.gd) ask: is this camp still occupied, and how strong are its residents
## relative to the roster (1.0 = as authored).
func camp_active(place_id: String) -> bool:
	var fi := faction_index(place_id)
	if fi < 0:
		return true
	var f: Dictionary = _factions.list[fi]
	if String(f["status"]) == "home":
		return true
	return _factions.fpos(f).distance_to(Vector2(f["home"][0], f["home"][1])) < 150.0 and String(f["status"]) != "marching"


func camp_strength(place_id: String) -> float:
	var fi := faction_index(place_id)
	if fi < 0:
		return 1.0
	var f: Dictionary = _factions.list[fi]
	return clampf(float(f["strength"]) / float(f["cap"]) * 1.25, 0.25, 1.3)


func camp_loss(place_id: String, n: int) -> void:
	var fi := faction_index(place_id)
	if fi >= 0:
		var f: Dictionary = _factions.list[fi]
		f["strength"] = maxf(float(f["strength"]) - n, 2.0)


# ---- player actions and news

## The player (or a patrol) killed `n` of `species` around a settlement. Apex kills call _apex_lost.
func hunt(sid: int, species: String, n: float) -> void:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	var sp := D.SPECIES.find(species)
	if zi < 0 or sp < 0:
		return
	var arr: Array = _st[zi]["n"]
	if sp in D.APEX:
		for _k in int(n):
			if float(arr[sp]) >= 0.5:
				_apex_lost(zi, sp, "hunted")
	else:
		arr[sp] = maxf(float(arr[sp]) - n, 0.0)
		if sp in [2, 3] and float(arr[sp]) < D.EXTINCT_BELOW:
			arr[sp] = 0.0


## Kills the apex (or the biggest one) in the zone around a settlement. Returns the species killed, "" if none.
func kill_apex(sid: int) -> String:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return ""
	var n: Array = _st[zi]["n"]
	for sp in [D.WYVERN, D.TROLL, D.BEAR]:
		if float(n[sp]) >= 0.5:
			var name: String = D.SPECIES[sp]
			n[sp] = 0.0
			_st[zi]["lastA"] = name
			_st[zi]["vac"] = 0
			_news_add("apex_slain", "The %s above %s is dead." % [D.LABEL[name], _zname(zi)], zi, 3)
			return name
	return ""


## Events with seq > `since` (news.gd keeps a cursor, like governance). Each: {seq (= id), day, kind, text, zone, sid,
## importance 1..3 (= mag), pos [x,y], topic, plus kind extras}. Faction intents never appear unless acted on.
## News.gd's item ring is small, so by default only importance >= 2 events are offered; pass min_importance 1 for the
## flavour lines too (clan traders at a market, envoys, a brood).
func news_events(since := 0, min_importance := 2) -> Array:
	var out: Array = []
	for e: Dictionary in _news:
		if int(e["seq"]) > since and int(e["importance"]) >= min_importance:
			out.append(e.duplicate(true))
	return out


func zone_summary(sid: int) -> Dictionary:
	_ensure()
	var zi := zone_index_of_settlement(sid)
	if zi < 0:
		return {}
	return {"name": _zname(zi), "wild": float(_zones[zi]["wild"]), "populations": populations(sid), "prey_index": _prey_idx(zi),
		"danger": _danger_of(zi), "adventurers": float(_st[zi]["adv"]), "seen": species_seen(sid)}


# ====================================================================================================== save

func serialize() -> Dictionary:
	_ensure()
	var facs: Array = _factions.list.duplicate(true)
	return {"v": 1, "day": _day, "season": _season, "rift": rift, "st": _st.duplicate(true), "route": _route.duplicate(true),
		"news": _news.duplicate(true), "seq": _seq, "den_w": _den_w.duplicate(true), "factions": facs, "alert": _alert.duplicate(true), "fort": _fort.duplicate(true), "told": _told.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	_inited = false
	_ensure()
	_day = int(d.get("day", 0))
	_season = String(d.get("season", "spring"))
	rift = float(d.get("rift", 0.1))
	var st: Array = d.get("st", [])
	if st.size() == _st.size():
		_st = st.duplicate(true)
		for z in _st:
			for k in ["n", "svc"]:
				var arr: Array = z[k]
				for j in arr.size():
					arr[j] = float(arr[j])
	var route: Array = d.get("route", [])
	if route.size() == _route.size():
		_route = route.duplicate(true)
		for z in _route:
			for s in z:
				s[0] = int(s[0])
	_news = (d.get("news", []) as Array).duplicate(true)
	_seq = int(d.get("seq", d.get("next_news", 0)))
	_den_w = (d.get("den_w", {}) as Dictionary).duplicate(true)
	var facs: Array = d.get("factions", [])
	if facs.size() == _factions.list.size():
		_factions.list = facs.duplicate(true)
	_refresh_fzones()
	_alert = (d.get("alert", {}) as Dictionary).duplicate(true)
	_fort = (d.get("fort", {}) as Dictionary).duplicate(true)
	_told = (d.get("told", {}) as Dictionary).duplicate(true)
	_msgs.clear()
