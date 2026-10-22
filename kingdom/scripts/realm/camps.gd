extends "res://scripts/realm/realm_module.gd"
## R§3 camps on chosen terrain, R§4 placed structures as data with roles and
## supply-chain station links, R§5 roads whose condition changes travel time,
## trade volume and raid risk. Pure data; JSON-safe save.
##
## Nodes of the road graph are strings: "s<id>" (WorldGen settlement) and
## "c<id>" (a founded camp). Public calls also accept a bare int for a
## settlement id and a Vector2 (x, z) where noted.

const TRAVEL_M_PER_HOUR := 1050.0         # compressed world scale (350 on the 4 km map, 700 on the 8 km map, x1.5 for the 12 km map so a cross-map trip takes the same time)
const MIN_CAMP_SCORE := 0.22
const CAMP_SPACING := 60.0
const LINK_RANGE := 1500.0                # a new camp auto-links to a node this close (900 on the 4 km map, 1200 on the 8 km map)

## Road level -> {speed multiplier (lower = faster), trade weight, visibility}.
const ROAD_LEVELS := {
	"dirt": {"speed": 1.0, "trade": 0.6, "vis": 0.0},
	"road": {"speed": 0.8, "trade": 1.0, "vis": 0.5},
	"stone": {"speed": 0.66, "trade": 1.4, "vis": 1.0},
	"military": {"speed": 0.6, "trade": 1.1, "vis": 1.5},
}
const LEVEL_ORDER := ["dirt", "road", "stone", "military"]
const OFFROAD_FACTOR := 2.2
const DECAY_PER_DAY := 0.004
const MAINTAIN_GAIN := 0.25

## Structure kinds -> role, supply-chain station (inputs -> outputs per day),
## build hours.
const STRUCTURES := {
	"tent": {"role": "shelter", "hours": 2, "inputs": {}, "outputs": {}},
	"campfire": {"role": "shelter", "hours": 1, "inputs": {"wood": 1}, "outputs": {}},
	"palisade": {"role": "defence", "hours": 24, "inputs": {}, "outputs": {}},
	"watchtower": {"role": "defence", "hours": 18, "inputs": {}, "outputs": {}},
	"well": {"role": "water", "hours": 8, "inputs": {}, "outputs": {"water": 6}},
	"farm_plot": {"role": "food", "hours": 10, "inputs": {"water": 1}, "outputs": {"grain": 4}},
	"woodcutter": {"role": "wood", "hours": 8, "inputs": {}, "outputs": {"wood": 5}},
	"bakery": {"role": "food", "hours": 16, "inputs": {"grain": 3, "water": 1, "wood": 1}, "outputs": {"bread": 6}},
	"smithy": {"role": "craft", "hours": 20, "inputs": {"iron": 2, "wood": 1}, "outputs": {"tools": 2}},
	"stable": {"role": "animals", "hours": 14, "inputs": {"grain": 1}, "outputs": {}},
	"warehouse": {"role": "storage", "hours": 16, "inputs": {}, "outputs": {}},
	"market_stall": {"role": "trade", "hours": 6, "inputs": {}, "outputs": {}},
	"barracks": {"role": "defence", "hours": 30, "inputs": {"bread": 2}, "outputs": {}},
}

## Camp id -> {id, name, pos:[x,y], founded_day, score, stock:{}, structures:[]}.
var _camps: Dictionary = {}
var _next_camp := 1
var _next_struct := 1
## edge key "a|b" (sorted) -> {a, b, len, cond, level, guarded, built_day, maintained_day}.
var _edges: Dictionary = {}
var _inited := false
var _day := 0


# --------------------------------------------------------------- nodes

func _n(x: Variant) -> String:
	if x is int:
		return "s%d" % x
	return String(x)


func node_pos(node: Variant) -> Vector2:
	var n := _n(node)
	if n.begins_with("s"):
		var i := int(n.substr(1))
		if i >= 0 and i < WorldGen.settlements.size():
			return WorldGen.settlements[i]["pos"]
	elif n.begins_with("c"):
		var c: Dictionary = _camps.get(int(n.substr(1)), {})
		if not c.is_empty():
			return Vector2(c["pos"][0], c["pos"][1])
	return Vector2.ZERO


func has_node_id(node: Variant) -> bool:
	var n := _n(node)
	if n.begins_with("s"):
		var i := int(n.substr(1))
		return i >= 0 and i < WorldGen.settlements.size()
	return n.begins_with("c") and _camps.has(int(n.substr(1)))


func nearest_node(pos: Vector2) -> String:
	var best := ""
	var bd := INF
	for s in WorldGen.settlements:
		var d: float = pos.distance_squared_to(s["pos"])
		if d < bd:
			bd = d
			best = "s%d" % int(s["id"])
	for id in _camps:
		var c: Dictionary = _camps[id]
		var d := pos.distance_squared_to(Vector2(c["pos"][0], c["pos"][1]))
		if d < bd:
			bd = d
			best = "c%d" % int(id)
	return best


static func _ekey(a: String, b: String) -> String:
	return "%s|%s" % ([a, b] if a < b else [b, a])


func _ensure() -> void:
	if _inited:
		return
	_inited = true
	for r in WorldGen.roads:
		var a := "s%d" % r.x
		var b := "s%d" % r.y
		var lvl := {"kingdom": "stone", "rural": "road", "frontier": "dirt"}[WorldGen.road_tier(r.x, r.y)] as String
		_add_edge(a, b, lvl, 0.75)


func _add_edge(a: String, b: String, level: String, cond: float) -> void:
	var k := _ekey(a, b)
	_edges[k] = {"a": mini_s(a, b), "b": maxi_s(a, b), "len": node_pos(a).distance_to(node_pos(b)),
		"cond": cond, "level": level, "guarded": false, "built_day": _day, "maintained_day": _day}


static func mini_s(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_s(a: String, b: String) -> String:
	return b if a < b else a


# --------------------------------------------------------------- camps R§3

## Terrain components 0..1 for a spot: water, wood, defence, road access.
func site_breakdown(pos: Vector2) -> Dictionary:
	var sd: float = WorldGen.shore_distance(pos.x, pos.y)
	var water := 0.0
	if sd > -INF and sd < INF:
		water = clampf(1.0 - maxf(sd, 0.0) / 260.0, 0.0, 1.0)
	var wood := clampf(WorldGen.forest_density(pos.x, pos.y, false), 0.0, 1.0)
	var h0: float = WorldGen.height(pos.x, pos.y)
	var rise := 0.0
	for o in [Vector2(45, 0), Vector2(-45, 0), Vector2(0, 45), Vector2(0, -45)]:
		rise += h0 - WorldGen.height(pos.x + o.x, pos.y + o.y)
	var defence := clampf(rise / 4.0 / 9.0, 0.0, 1.0)
	var rd: float = WorldGen.road_distance(pos.x, pos.y)
	var road := 0.0 if rd == INF else clampf(1.0 - rd / 400.0, 0.0, 1.0)
	return {"water": water, "wood": wood, "defence": defence, "road": road,
		"flooded": WorldGen.is_water(pos.x, pos.y)}


func score_site(pos: Vector2) -> float:
	var b := site_breakdown(pos)
	if b["flooded"]:
		return 0.0
	var s: float = 0.32 * b["water"] + 0.24 * b["wood"] + 0.24 * b["defence"] + 0.20 * b["road"]
	s += preload("res://scripts/world/hidden_valley.gd").site_bonus(pos)   # Hidden valley hook: fertile vale soil
	return clampf(s, 0.0, 1.0)


## Found a camp; returns camp id or -1 (bad terrain / too close to another camp).
func found_camp(pos: Vector2, camp_name := "", day := 0) -> int:
	_ensure()
	if score_site(pos) < MIN_CAMP_SCORE:
		return -1
	for id in _camps:
		var c: Dictionary = _camps[id]
		if Vector2(c["pos"][0], c["pos"][1]).distance_to(pos) < CAMP_SPACING:
			return -1
	var id := _next_camp
	_next_camp += 1
	_day = day
	var b := site_breakdown(pos)
	_camps[id] = {"id": id, "name": camp_name if camp_name != "" else "Camp %d" % id,
		"pos": [pos.x, pos.y], "founded_day": day, "score": score_site(pos),
		"traits": {"water": b["water"], "wood": b["wood"], "defence": b["defence"], "road": b["road"]},
		"stock": {"wood": 4, "grain": 4, "water": 4}, "structures": []}
	# Trail to the nearest node so the camp is on the graph (a dirt path).
	var near := ""
	var bd := LINK_RANGE
	for s in WorldGen.settlements:
		var d: float = pos.distance_to(s["pos"])
		if d < bd:
			bd = d
			near = "s%d" % int(s["id"])
	if near != "":
		_add_edge("c%d" % id, near, "dirt", 0.6)
	return id


func camps() -> Array:
	var out: Array = []
	var ids := _camps.keys()
	ids.sort()
	for id in ids:
		out.append(_camps[id])
	return out


func camp(id: int) -> Dictionary:
	return _camps.get(id, {})


# --------------------------------------------------------------- structures R§4

## Place a structure. Returns its dict (with "hours_left" while under
## construction) or {} when the camp/kind is unknown.
func place_structure(camp_id: int, kind: String, pos := Vector2.ZERO, link_to: Variant = null) -> Dictionary:
	if not _camps.has(camp_id) or not STRUCTURES.has(kind):
		return {}
	var def: Dictionary = STRUCTURES[kind]
	var c: Dictionary = _camps[camp_id]
	var st := {"id": _next_struct, "kind": kind, "role": def["role"], "pos": [pos.x, pos.y],
		"hours_left": int(def["hours"]), "condition": 1.0, "active": false,
		"station": {"inputs": def["inputs"].duplicate(), "outputs": def["outputs"].duplicate()},
		"link": _n(link_to) if link_to != null else "c%d" % camp_id, "starved": false}
	_next_struct += 1
	(c["structures"] as Array).append(st)
	return st


func structures(camp_id: int, role := "") -> Array:
	var out: Array = []
	for st in _camps.get(camp_id, {}).get("structures", []):
		if role == "" or st["role"] == role:
			out.append(st)
	return out


func has_role(camp_id: int, role: String) -> bool:
	for st in _camps.get(camp_id, {}).get("structures", []):
		if st["role"] == role and st["hours_left"] <= 0:
			return true
	return false


## 0..1 defence of a camp: terrain plus finished defensive structures.
func defence_of(camp_id: int) -> float:
	var c: Dictionary = _camps.get(camp_id, {})
	if c.is_empty():
		return 0.0
	var d: float = c["traits"]["defence"] * 0.5
	for st in c["structures"]:
		if st["role"] == "defence" and st["hours_left"] <= 0:
			d += 0.15 * st["condition"]
	return clampf(d, 0.0, 1.0)


func add_stock(camp_id: int, item: String, n: int) -> void:
	if _camps.has(camp_id):
		var s: Dictionary = _camps[camp_id]["stock"]
		s[item] = maxi(0, int(s.get(item, 0)) + n)


func stock_of(camp_id: int, item: String) -> int:
	return int(_camps.get(camp_id, {}).get("stock", {}).get(item, 0))


# --------------------------------------------------------------- roads R§5

func road(a: Variant, b: Variant) -> Dictionary:
	_ensure()
	return _edges.get(_ekey(_n(a), _n(b)), {})


func edges() -> Array:
	_ensure()
	var keys := _edges.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(_edges[k])
	return out


static func condition_label(cond: float) -> String:
	if cond >= 0.66:
		return "built"
	if cond >= 0.33:
		return "maintained" if cond >= 0.5 else "worn"
	return "decayed"


func road_state(a: Variant, b: Variant) -> String:
	var e := road(a, b)
	return "none" if e.is_empty() else condition_label(e["cond"])


func build_road(a: Variant, b: Variant, level := "dirt") -> bool:
	_ensure()
	var na := _n(a)
	var nb := _n(b)
	if na == nb or not has_node_id(na) or not has_node_id(nb) or not ROAD_LEVELS.has(level):
		return false
	var k := _ekey(na, nb)
	if _edges.has(k):
		var e: Dictionary = _edges[k]
		if LEVEL_ORDER.find(level) <= LEVEL_ORDER.find(e["level"]):
			return false
		e["level"] = level
		e["cond"] = 1.0
		e["maintained_day"] = _day
	else:
		_add_edge(na, nb, level, 1.0)
	return true


func maintain_road(a: Variant, b: Variant, effort := 1.0) -> bool:
	var e := road(a, b)
	if e.is_empty():
		return false
	e["cond"] = minf(1.0, e["cond"] + MAINTAIN_GAIN * effort)
	e["maintained_day"] = _day
	return true


func set_guarded(a: Variant, b: Variant, on: bool) -> void:
	var e := road(a, b)
	if not e.is_empty():
		e["guarded"] = on


func _edge_factor(e: Dictionary) -> float:
	var lv: Dictionary = ROAD_LEVELS[e["level"]]
	return float(lv["speed"]) * lerpf(1.7, 1.0, clampf(e["cond"], 0.0, 1.0))


## Travel-time multiplier of one edge; OFFROAD_FACTOR when there is no road.
func road_factor(a: Variant, b: Variant) -> float:
	var e := road(a, b)
	return OFFROAD_FACTOR if e.is_empty() else _edge_factor(e)


## Goods flow along the edge, 0..~1.4 (decayed roads carry little).
func trade_volume(a: Variant, b: Variant) -> float:
	var e := road(a, b)
	if e.is_empty():
		return 0.0
	return float(ROAD_LEVELS[e["level"]]["trade"]) * e["cond"] * e["cond"] * clampf(400.0 / maxf(e["len"], 100.0), 0.3, 2.0)


## Chance of a raid per traversal: neglected roads are lawless, big roads visible.
func raid_risk(a: Variant, b: Variant) -> float:
	var e := road(a, b)
	if e.is_empty():
		return 0.12
	var r: float = 0.04 + 0.10 * (1.0 - e["cond"]) + 0.03 * float(ROAD_LEVELS[e["level"]]["vis"])
	if e["guarded"]:
		r *= 0.35
	return clampf(r, 0.0, 0.5)


## Cheapest route (list of node ids incl. ends) by travel hours; [] if unknown.
func route(a: Variant, b: Variant) -> Array:
	_ensure()
	var na := _n(a)
	var nb := _n(b)
	if na == nb:
		return [na]
	var dist := {na: 0.0}
	var prev := {}
	var open := [na]
	var done := {}
	var adj := {}
	for k in _edges:
		var e: Dictionary = _edges[k]
		if not adj.has(e["a"]):
			adj[e["a"]] = []
		if not adj.has(e["b"]):
			adj[e["b"]] = []
		adj[e["a"]].append(e["b"])
		adj[e["b"]].append(e["a"])
	while not open.is_empty():
		var cur: String = open[0]
		for o in open:
			if dist[o] < dist[cur]:
				cur = o
		open.erase(cur)
		if cur == nb:
			break
		done[cur] = true
		for nx in adj.get(cur, []):
			if done.has(nx):
				continue
			var e: Dictionary = _edges[_ekey(cur, nx)]
			var nd: float = dist[cur] + e["len"] * _edge_factor(e)
			if nd < dist.get(nx, INF):
				dist[nx] = nd
				prev[nx] = cur
				if not open.has(nx):
					open.append(nx)
	if not prev.has(nb):
		return []
	var path: Array = [nb]
	while path[0] != na:
		path.push_front(prev[path[0]])
	return path


## Hours to travel between two nodes along the road graph (off-road fallback).
func travel_hours(a: Variant, b: Variant) -> float:
	var na := _n(a)
	var nb := _n(b)
	if na == nb:
		return 0.0
	var path := route(na, nb)
	if path.is_empty():
		return node_pos(na).distance_to(node_pos(nb)) * OFFROAD_FACTOR / TRAVEL_M_PER_HOUR
	var h := 0.0
	for i in range(path.size() - 1):
		var e: Dictionary = _edges[_ekey(path[i], path[i + 1])]
		h += e["len"] * _edge_factor(e) / TRAVEL_M_PER_HOUR
	return h


## Raid risk of a whole route (1 - product of safe traversals).
func route_risk(a: Variant, b: Variant) -> float:
	var path := route(a, b)
	if path.size() < 2:
		return 0.0 if path.size() == 1 else 0.12
	var safe := 1.0
	for i in range(path.size() - 1):
		safe *= 1.0 - raid_risk(path[i], path[i + 1])
	return 1.0 - safe


# --------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	for id in _camps:
		for st in _camps[id]["structures"]:
			if st["hours_left"] > 0:
				st["hours_left"] -= 1
				if st["hours_left"] == 0:
					st["active"] = true
					out.append("%s: the %s is finished." % [_camps[id]["name"], String(st["kind"]).replace("_", " ")])
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	var out: Array = []
	var season: String = str(ctx.get("season", "spring"))
	var wet := 1.6 if season in ["spring", "autumn"] else (1.3 if season == "winter" else 1.0)
	for k in _edges:
		var e: Dictionary = _edges[k]
		var gd := 0.5 if e["guarded"] else 1.0
		e["cond"] = maxf(0.0, e["cond"] - DECAY_PER_DAY * wet * gd)
	for id in _camps:
		out.append_array(_camp_day(_camps[id]))
	return out


func _camp_day(c: Dictionary) -> Array:
	var out: Array = []
	var stock: Dictionary = c["stock"]
	for st in c["structures"]:
		if st["hours_left"] > 0:
			continue
		st["condition"] = maxf(0.0, st["condition"] - 0.002)
		var ins: Dictionary = st["station"]["inputs"]
		var ok := true
		for it in ins:
			if int(stock.get(it, 0)) < int(ins[it]):
				ok = false
				break
		var was: bool = st["starved"]
		st["starved"] = not ok
		if not ok:
			if not was and not ins.is_empty():
				out.append("%s: the %s lacks supplies." % [c["name"], String(st["kind"]).replace("_", " ")])
			continue
		for it in ins:
			stock[it] = int(stock.get(it, 0)) - int(ins[it])
		var eff: float = st["condition"]
		for it in st["station"]["outputs"]:
			stock[it] = int(stock.get(it, 0)) + int(round(int(st["station"]["outputs"][it]) * eff))
	return out


func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	var season: String = str(ctx.get("season", "spring"))
	var wet := 1.6 if season in ["spring", "autumn"] else 1.0
	var worst := ""
	var worst_c := 1.0
	for k in _edges:
		var e: Dictionary = _edges[k]
		var gd := 0.5 if e["guarded"] else 1.0
		e["cond"] = maxf(0.0, e["cond"] - DECAY_PER_DAY * wet * gd * days)
		if e["cond"] < worst_c:
			worst_c = e["cond"]
			worst = k
	for id in _camps:
		var c: Dictionary = _camps[id]
		for st in c["structures"]:
			if st["hours_left"] > 0:
				st["hours_left"] = maxi(0, st["hours_left"] - days * 24)
				st["active"] = st["hours_left"] == 0
			st["condition"] = maxf(0.0, st["condition"] - 0.002 * days)
		# One statistical production step, capped to a week of output.
		for i in mini(days, 7):
			_camp_day(c)
	if worst != "" and worst_c < 0.33 and days >= 3:
		out.append("The road %s has fallen into disrepair." % worst.replace("|", " to ").replace("s", "").replace("c", "camp "))
	return out


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"camps": _camps.duplicate(true), "next_camp": _next_camp, "next_struct": _next_struct,
		"edges": _edges.duplicate(true), "inited": _inited, "day": _day}


func deserialize(d: Dictionary) -> void:
	_camps = {}
	# JSON turns int keys into strings.
	for k in d.get("camps", {}):
		_camps[int(k)] = (d["camps"][k] as Dictionary).duplicate(true)
	_edges = (d.get("edges", {}) as Dictionary).duplicate(true)
	_next_camp = int(d.get("next_camp", 1))
	_next_struct = int(d.get("next_struct", 1))
	_inited = bool(d.get("inited", false))
	_day = int(d.get("day", 0))
