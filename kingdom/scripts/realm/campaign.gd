extends "res://scripts/realm/realm_module.gd"
## Campaign / War Room simulation (R§9-21, R§35). Pure data.
##
## The road graph is WorldGen.settlements (nodes) + WorldGen.roads (edges).
## Armies are dictionaries moving hour by hour along it. The player never sees
## the truth: known_map() lists only intel (source, day_seen, confidence that
## decays with age). Orders travel by courier and apply on arrival, filtered
## through the commander's personality. Battles resolve live (if the player is
## there, see pending_live_battle()) or strategically.
##
## Integration: ctx["life"].war (read is_at_war / enemy_id / front only).
## Optional siblings via hub.mod(): "factions" (record_war_act,
## change_relation) and "strongholds" (nearest, begin_siege).

const PLAYER := "player"
const ARMY_SPEED := 120.0          # metres per hour on a road (world is 8 km wide; was 60 on the 4 km map)
const COURIER_SPEED := 360.0        # (was 180 on the 4 km map)
const INTEL_HALF_LIFE := 5.0       # days
const INTEL_DROP := 0.04
const MAX_SUPPLY := 6.0
const LIVE_TIMEOUT_HOURS := 3
const LIVE_RADIUS := 220.0
const BATTLES_MAX := 20
const PERSONALITIES := ["cautious", "aggressive", "loyal", "ambitious"]
const FORMATIONS := {
	"line": {"atk": 1.0, "def": 1.1, "mob": 1.0},
	"wedge": {"atk": 1.25, "def": 0.85, "mob": 1.0},
	"square": {"atk": 0.8, "def": 1.3, "mob": 0.7},
	"skirmish": {"atk": 0.95, "def": 0.95, "mob": 1.2},
	"column": {"atk": 0.75, "def": 0.7, "mob": 1.3},
}
const TERRAIN_DEF := {"castle": 1.5, "frontier_town": 1.3, "town": 1.15, "village": 1.05}
const FIRST := ["Varin", "Oswin", "Kessa", "Marek", "Ilse", "Dorn", "Hale", "Bryn", "Torvald", "Sela"]
const LAST := ["Ashgrove", "Blackmere", "Coldwater", "Dunmark", "Ironvale", "Stonebridge"]
const ADVISOR_ROLES := ["marshal", "quartermaster", "scout", "mage", "steward"]
const ROLE_PERSONALITY := {"marshal": "aggressive", "quartermaster": "cautious", "scout": "ambitious", "mage": "ambitious", "steward": "loyal"}

var _armies: Array = []
var _couriers: Array = []
var _reports: Array = []            # {due_hour, text, army_id}
var _intel: Dictionary = {}         # key -> entry
var _explored: Dictionary = {}      # "node" -> day
var _depots: Array = []             # {node, faction, stock}
var _cut: Dictionary = {}           # "node" -> until_day
var _blocked: Dictionary = {}       # "a-b" -> until_day
var _battles: Array = []
var _pending_live: Dictionary = {}
var _evidence: Array = []
var _advisors: Array = []
var _next_id := 1
var _hours := 0
var _day := 0
var _hq := 0
var _player_node := 0
var _op_counter := 0
var _enemy := ""                     # enemy faction whose armies we auto-manage
var _seeded_player := false

# derived (not serialised)
var _adj: Dictionary = {}           # node -> [[nb, len]]
var _len: Dictionary = {}
var _graph_ready := false


func _rng(tag: String, id: Variant = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, _hours, _day, id])
	return r


# --- graph -----------------------------------------------------------------------

func _ensure() -> void:
	if _graph_ready or WorldGen.settlements.is_empty():
		return
	_graph_ready = true
	_adj.clear()
	_len.clear()
	for i in WorldGen.settlements.size():
		_adj[i] = []
	for e: Vector2i in WorldGen.roads:
		var l: float = (WorldGen.settlements[e.x]["pos"] as Vector2).distance_to(WorldGen.settlements[e.y]["pos"])
		_adj[e.x].append([e.y, l])
		_adj[e.y].append([e.x, l])
		_len[_ek(e.x, e.y)] = l


static func _ek(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


func _elen(a: int, b: int) -> float:
	return float(_len.get(_ek(a, b), 500.0))


func node_pos(n: int) -> Vector2:
	return WorldGen.settlements[n]["pos"] as Vector2 if n >= 0 and n < WorldGen.settlements.size() else Vector2.ZERO


func nearest_node(p: Vector2) -> int:
	var best := 0
	var bd := 1e18
	for i in WorldGen.settlements.size():
		var d := (WorldGen.settlements[i]["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Shortest path (incl. start) avoiding `avoid` nodes and blocked edges. [] if none.
func path(a: int, b: int, avoid: Dictionary = {}) -> Array:
	_ensure()
	if a == b:
		return [a]
	if not _adj.has(a) or not _adj.has(b):
		return []
	var dist := {a: 0.0}
	var prev := {}
	var open: Array = [a]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var u: int = open[bi]
		open.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		if u == b:
			break
		for e: Array in _adj[u]:
			var v: int = e[0]
			if done.has(v) or (avoid.has(v) and v != b) or _edge_blocked(u, v):
				continue
			var nd: float = float(dist[u]) + float(e[1])
			if not dist.has(v) or nd < float(dist[v]):
				dist[v] = nd
				prev[v] = u
				open.append(v)
	if not prev.has(b):
		return []
	var out: Array = [b]
	var cur := b
	while cur != a:
		cur = prev[cur]
		out.push_front(cur)
	return out


func path_length(p: Array) -> float:
	var t := 0.0
	for i in range(1, p.size()):
		t += _elen(p[i - 1], p[i])
	return t


func _edge_blocked(a: int, b: int) -> bool:
	return int(_blocked.get(_ek(a, b), -1)) > _day


# --- armies ----------------------------------------------------------------------

func spawn_army(faction: String, node: int, strength: int, personality := "loyal", army_name := "") -> int:
	_ensure()
	var r := _rng("army_spawn", _next_id)
	var cname := "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]]
	var a := {"id": _next_id, "faction": faction, "name": army_name if army_name != "" else "%s Company" % cname.get_slice(" ", 1),
		"node": node, "route": [], "leg": 0.0, "prev_node": node, "strength": strength, "max_strength": strength,
		"morale": 0.8, "supply": 4.0, "formation": "line",
		"commander": {"name": cname, "personality": personality, "skill": 1 + r.randi() % 4},
		"order": {"kind": "hold", "target": node}, "state": "camped", "arrived_hour": _hours, "engaged_day": -1,
		"misled_until": -1, "ambush_until": -1, "stunned_until": -1, "auto": false, "sent_day": -1}
	_next_id += 1
	_armies.append(a)
	if faction == PLAYER:
		_report_intel_own(a)
	return int(a["id"])


func add_depot(faction: String, node: int, stock: float) -> void:
	for d: Dictionary in _depots:
		if d["faction"] == faction and int(d["node"]) == node:
			d["stock"] = float(d["stock"]) + stock
			return
	_depots.append({"node": node, "faction": faction, "stock": stock})


func depots() -> Array:
	return _depots.duplicate(true)


func set_hq(node: int) -> void:
	_hq = node
	_player_node = node
	_mark_explored(node)


func _army(id: int) -> Dictionary:
	for a: Dictionary in _armies:
		if int(a["id"]) == id:
			return a
	return {}


## Snapshot of armies. NOTE: this is ground truth for the game's own use
## (rendering the player's own forces, live battle setup); the War Room must
## show known_map() only.
func armies() -> Array:
	var out: Array = []
	for a: Dictionary in _armies:
		var c := a.duplicate(true)
		c["pos"] = army_pos(a)
		out.append(c)
	return out


func player_armies() -> Array:
	return armies().filter(func(a: Dictionary) -> bool: return a["faction"] == PLAYER)


func army_pos(a: Dictionary) -> Vector2:
	var from := node_pos(int(a["node"]))
	if (a["route"] as Array).is_empty():
		return from
	var to := node_pos(int(a["route"][0]))
	var l := maxf(_elen(int(a["node"]), int(a["route"][0])), 1.0)
	return from.lerp(to, clampf(float(a["leg"]) / l, 0.0, 1.0))


func _is_hostile(a: Dictionary, b: Dictionary) -> bool:
	return (a["faction"] == PLAYER) != (b["faction"] == PLAYER)


func _speed(a: Dictionary, ctx: Dictionary) -> float:
	var s := ARMY_SPEED * float((FORMATIONS[a["formation"]] as Dictionary)["mob"])
	if String(ctx.get("season", "")) == "winter":
		s *= 0.7
	if float(a["supply"]) <= 0.0:
		s *= 0.7
	if float(a["morale"]) < 0.3:
		s *= 0.8
	return s


func estimated_arrival_hours(army_id: int, node: int) -> float:
	var a := _army(army_id)
	if a.is_empty():
		return -1.0
	var p := path(int(a["node"]), node)
	if p.is_empty():
		return -1.0
	return path_length(p) / (ARMY_SPEED * float(FORMATIONS[a["formation"]]["mob"]))


func _set_route(a: Dictionary, target: int) -> bool:
	var avoid := {}
	var p := path(int(a["node"]), target, avoid)
	if p.size() < 2:
		a["route"] = []
		return p.size() == 1
	# mid-leg armies cannot reverse: they finish the current leg first
	if float(a["leg"]) > 0.0 and not (a["route"] as Array).is_empty():
		var nxt: int = a["route"][0]
		var p2 := path(nxt, target)
		if p2.is_empty():
			return false
		a["route"] = p2
		return true
	p.remove_at(0)
	a["route"] = p
	a["state"] = "moving"
	return true


# --- orders (R§12) -----------------------------------------------------------------

## Send an order to one of the player's armies. It reaches it after the courier
## has ridden there, and the commander interprets it. Returns the courier record
## ({} if the army does not exist or is not yours).
## order: {kind: move|attack|hold|camp|retreat|raid, target: node, retreat: orderly|rout|feigned|scorched, formation}
func issue_order(army_id: int, order: Dictionary) -> Dictionary:
	_ensure()
	var a := _army(army_id)
	if a.is_empty() or a["faction"] != PLAYER:
		return {}
	var origin := _player_node
	var p := path(origin, int(a["node"]))
	var hours := 1.0
	var legs: Array = []
	if p.size() >= 2:
		var acc := 0.0
		for i in range(1, p.size()):
			acc += _elen(p[i - 1], p[i])
			legs.append([int(p[i]), acc / COURIER_SPEED])
		hours = maxf(1.0, ceil(acc / COURIER_SPEED))
	var c := {"id": _next_id, "army_id": army_id, "order": order.duplicate(true), "sent_hour": _hours, "sent_day": _day,
		"eta_hours": int(hours), "elapsed": 0, "legs": legs, "checked": 0, "intercepted": false}
	_next_id += 1
	_couriers.append(c)
	return c.duplicate(true)


func couriers() -> Array:
	return _couriers.duplicate(true)


func _courier_step(ctx: Dictionary, out: Array) -> void:
	var keep: Array = []
	for c: Dictionary in _couriers:
		c["elapsed"] = int(c["elapsed"]) + 1
		var dead := false
		# interception at every node the rider has now passed
		var legs: Array = c["legs"]
		while int(c["checked"]) < legs.size() and float(legs[int(c["checked"])][1]) <= float(c["elapsed"]):
			var nd: int = legs[int(c["checked"])][0]
			c["checked"] = int(c["checked"]) + 1
			for e: Dictionary in _armies:
				if e["faction"] != PLAYER and int(e["node"]) == nd and (e["route"] as Array).is_empty() and \
						_rng("intercept", int(c["id"]) * 97 + nd).randf() < 0.22:
					c["intercepted"] = true
					dead = true
					out.append("A courier was cut down near %s. The order never arrived." % _nname(nd))
					_gain_intel_on_courier(e)
					break
			if dead:
				break
		if dead:
			continue
		if int(c["elapsed"]) >= int(c["eta_hours"]):
			out.append_array(_deliver(c, ctx))
		else:
			keep.append(c)
	_couriers = keep


func _gain_intel_on_courier(_enemy_army: Dictionary) -> void:
	pass   # the enemy AI is omniscient about the player; kept as a hook for evidence/rumours


func _deliver(c: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	var a := _army(int(c["army_id"]))
	if a.is_empty():
		return out
	if int(a["engaged_day"]) >= int(c["sent_day"]) and int(a["engaged_day"]) >= 0:
		out.append("Your order to %s arrived after the fighting had begun." % a["commander"]["name"])
	var res := _interpret(a, c["order"])
	a["order"] = res["order"]
	_execute(a, res["order"])
	if res["note"] != "":
		_dispatch(a, res["note"])
	return out


func _enemies_adjacent(a: Dictionary) -> Array:
	var out: Array = []
	var nodes: Array = [int(a["node"])]
	for e: Array in _adj.get(int(a["node"]), []):
		nodes.append(int(e[0]))
	for o: Dictionary in _armies:
		if _is_hostile(a, o) and int(o["node"]) in nodes:
			out.append(o)
	return out


## R§13: the commander decides how an order is carried out.
func _interpret(a: Dictionary, order: Dictionary) -> Dictionary:
	var o := order.duplicate(true)
	var cmd: Dictionary = a["commander"]
	var pers := String(cmd["personality"])
	var r := _rng("interpret", int(a["id"]))
	var note := ""
	var kind := String(o.get("kind", "hold"))
	var foes := _enemies_adjacent(a)
	var foe_str := 0
	for f: Dictionary in foes:
		foe_str += int(f["strength"])
	match pers:
		"cautious":
			if kind in ["attack", "raid"] and foe_str > int(a["strength"]) * 0.9 and not foes.is_empty():
				o["kind"] = "hold"
				note = "%s judged the attack unwise and holds position." % cmd["name"]
			elif kind == "attack" and float(a["morale"]) < 0.5:
				o["kind"] = "camp"
				note = "%s will not march on a wavering army." % cmd["name"]
			a["formation"] = "square" if kind in ["hold", "camp"] or o["kind"] in ["hold", "camp"] else "line"
		"aggressive":
			if kind in ["hold", "camp"] and not foes.is_empty() and int(a["strength"]) >= foe_str * 0.7:
				o["kind"] = "attack"
				o["target"] = int((foes[0] as Dictionary)["node"])
				note = "%s sortied against the enemy instead of holding." % cmd["name"]
			elif kind == "retreat" and r.randf() < 0.4:
				o["kind"] = "hold"
				note = "%s refuses to give ground." % cmd["name"]
			a["formation"] = "wedge" if o["kind"] == "attack" else a["formation"]
		"ambitious":
			if kind == "move" and r.randf() < 0.35 and not foes.is_empty():
				o["kind"] = "attack"
				o["target"] = int((foes[0] as Dictionary)["node"])
				note = "%s diverted to seek glory against the enemy." % cmd["name"]
		"loyal":
			a["formation"] = "square" if kind in ["hold", "camp"] else a["formation"]
	if o.has("formation") and FORMATIONS.has(String(o["formation"])) and pers != "aggressive":
		a["formation"] = o["formation"]
	return {"order": o, "note": note}


func _execute(a: Dictionary, o: Dictionary) -> void:
	var kind := String(o.get("kind", "hold"))
	var target := int(o.get("target", a["node"]))
	match kind:
		"hold", "camp":
			a["route"] = []
			a["leg"] = 0.0 if (a["route"] as Array).is_empty() else a["leg"]
			a["state"] = "camped"
		"move", "attack", "raid":
			_set_route(a, target)
		"retreat":
			var dest := _retreat_dest(a) if not o.has("target") else target
			a["retreat_type"] = String(o.get("retreat", "orderly"))
			a["state"] = "retreating"
			_set_route(a, dest)
	a["order"] = o


func _retreat_dest(a: Dictionary) -> int:
	if a["faction"] == PLAYER:
		return _nearest_depot_node(a) if _nearest_depot_node(a) >= 0 else _hq
	var p := int(a["prev_node"])
	return p if p != int(a["node"]) else int(a["node"])


func _nearest_depot_node(a: Dictionary) -> int:
	var best := -1
	var bl := 1e18
	for d: Dictionary in _depots:
		if d["faction"] == a["faction"]:
			var p := path(int(a["node"]), int(d["node"]))
			if not p.is_empty() and path_length(p) < bl:
				bl = path_length(p)
				best = int(d["node"])
	return best


# --- intel (R§10) ---------------------------------------------------------------

func _estimate(strength: int, precision: float, r: RandomNumberGenerator) -> Vector2i:
	var centre := float(strength) * r.randf_range(1.0 - precision * 0.5, 1.0 + precision * 0.5)
	return Vector2i(int(centre * (1.0 - precision)), int(centre * (1.0 + precision)))


func _see(e: Dictionary, source: String, precision: float, base_conf: float, day_seen: int, wrong_node := false) -> void:
	var r := _rng("see_%s" % source, int(e["id"]))
	var est := _estimate(int(e["strength"]), precision, r)
	var node := int(e["node"])
	if wrong_node:
		var nb: Array = _adj.get(node, [])
		if not nb.is_empty():
			node = int((nb[r.randi() % nb.size()] as Array)[0])
	var key := "f%d" % int(e["id"])
	var old: Dictionary = _intel.get(key, {})
	if not old.is_empty() and int(old["day_seen"]) > day_seen:
		return
	_intel[key] = {"key": key, "kind": "force", "army_id": int(e["id"]), "faction": e["faction"], "node": node,
		"est_min": est.x, "est_max": est.y, "cavalry": r.randf() < 0.3 if e["faction"] != PLAYER else false,
		"source": source, "day_seen": day_seen, "base_conf": base_conf}
	_mark_explored(node)


func _report_intel_own(a: Dictionary) -> void:
	var key := "f%d" % int(a["id"])
	_intel[key] = {"key": key, "kind": "force", "army_id": int(a["id"]), "faction": PLAYER, "node": int(a["node"]),
		"est_min": int(a["strength"]), "est_max": int(a["strength"]), "cavalry": false, "source": "own report",
		"day_seen": _day, "base_conf": 1.0}


func _mark_explored(node: int) -> void:
	_explored[str(node)] = _day


## Other systems (scouts, followers, merchants) can feed the war room.
func add_intel(army_id: int, source: String, precision := 0.3, base_conf := 0.7) -> bool:
	var e := _army(army_id)
	if e.is_empty():
		return false
	_see(e, source, precision, base_conf, _day)
	return true


## R§10: only what the player faction knows, aged. Each entry: {key, kind,
## node, name, pos, source, day_seen, age_days, confidence, est_min, est_max,
## label, ...}. Nothing here reveals true strengths or positions.
func known_map() -> Array:
	_ensure()
	var out: Array = []
	for key: String in _intel:
		var e: Dictionary = (_intel[key] as Dictionary).duplicate()
		var age := maxi(0, _day - int(e["day_seen"]))
		e["age_days"] = age
		e["confidence"] = snappedf(float(e["base_conf"]) * pow(0.5, float(age) / INTEL_HALF_LIFE), 0.001)
		var widen := 1.0 + float(age) * 0.12
		var mid := (float(e["est_min"]) + float(e["est_max"])) * 0.5
		var half := (float(e["est_max"]) - float(e["est_min"])) * 0.5 * widen
		e["est_min"] = maxi(0, int(mid - half))
		e["est_max"] = int(mid + half)
		e["name"] = _nname(int(e["node"]))
		e["pos"] = node_pos(int(e["node"]))
		var who := "Your force" if e["faction"] == PLAYER else "Unknown force"
		var when := "today" if age == 0 else ("%d day%s ago" % [age, "" if age == 1 else "s"])
		e["label"] = "%s, est. %d-%d%s, last seen %s" % [who, e["est_min"], e["est_max"], ", possibly cavalry" if e["cavalry"] else "", when]
		out.append(e)
	for k: String in _explored:
		var n := int(k)
		var age2 := maxi(0, _day - int(_explored[k]))
		out.append({"key": "n%d" % n, "kind": "region", "node": n, "name": _nname(n), "pos": node_pos(n), "source": "explored",
			"day_seen": int(_explored[k]), "age_days": age2, "confidence": snappedf(pow(0.5, float(age2) / 20.0), 0.001),
			"label": "%s, last visited %d days ago" % [_nname(n), age2]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["key"]) < String(b["key"]))
	return out


func _nname(n: int) -> String:
	return String(WorldGen.settlements[n]["name"]) if n >= 0 and n < WorldGen.settlements.size() else "the wilds"


func _intel_day(_ctx: Dictionary) -> void:
	var r := _rng("intel_day")
	var enemies: Array = _armies.filter(func(x: Dictionary) -> bool: return x["faction"] != PLAYER)
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		_mark_explored(int(a["node"]))
		for e: Array in _adj.get(int(a["node"]), []):
			_mark_explored(int(e[0]))
		for f: Dictionary in _enemies_adjacent(a):
			_see(f, "scout", 0.2 + 0.05 * (4 - int(a["commander"]["skill"])), 0.9, _day)
	if not enemies.is_empty():
		if r.randf() < 0.3:
			_see(enemies[r.randi() % enemies.size()], "merchant", 0.45, 0.55, maxi(0, _day - 1))
		if r.randf() < 0.2:
			_see(enemies[r.randi() % enemies.size()], "rumour", 0.8, 0.3, maxi(0, _day - 2), r.randf() < 0.4)
	for key: String in _intel.keys():
		var e2: Dictionary = _intel[key]
		var conf := float(e2["base_conf"]) * pow(0.5, float(_day - int(e2["day_seen"])) / INTEL_HALF_LIFE)
		if conf < INTEL_DROP or (e2["kind"] == "force" and _army(int(e2["army_id"])).is_empty() and e2["faction"] != PLAYER and conf < 0.2):
			_intel.erase(key)


# --- dispatches (news travels at courier speed) -----------------------------------

func _dispatch(a: Dictionary, text: String) -> void:
	var p := path(int(a["node"]), _player_node)
	var h := 1 if p.size() < 2 else int(ceil(path_length(p) / COURIER_SPEED))
	_reports.append({"due_hour": _hours + h, "text": text, "army_id": int(a["id"]), "day": _day})


func _report_step(out: Array) -> void:
	var keep: Array = []
	for rp: Dictionary in _reports:
		if int(rp["due_hour"]) <= _hours:
			out.append(String(rp["text"]))
			var a := _army(int(rp["army_id"]))
			if not a.is_empty() and a["faction"] == PLAYER:
				var key := "f%d" % int(a["id"])
				_report_intel_own(a)
				_intel[key]["day_seen"] = int(rp["day"])
		else:
			keep.append(rp)
	_reports = keep


# --- ticks ---------------------------------------------------------------------

func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	if WorldGen.settlements.is_empty():
		return out
	_hours += 1
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2:
		_player_node = nearest_node(pp)
		if (pp as Vector2).distance_to(node_pos(_player_node)) < 300.0:
			_mark_explored(_player_node)
	_courier_step(ctx, out)
	for a: Dictionary in _armies:
		_move(a, ctx)
	_battles_step(ctx, out)
	_report_step(out)
	if pp is Vector2:
		for a: Dictionary in _armies:
			if a["faction"] != PLAYER and army_pos(a).distance_to(pp) < 250.0:
				_see(a, "direct", 0.1, 1.0, _day)
	return out


func _move(a: Dictionary, ctx: Dictionary) -> void:
	if int(a["stunned_until"]) > _hours or (a["route"] as Array).is_empty() or a["state"] == "engaged":
		return
	if a["state"] == "camped":
		return
	var budget := _speed(a, ctx)
	while budget > 0.0 and not (a["route"] as Array).is_empty():
		var nxt: int = a["route"][0]
		if _edge_blocked(int(a["node"]), nxt):
			a["route"] = []
			a["leg"] = 0.0
			a["state"] = "camped"
			return
		var l := _elen(int(a["node"]), nxt)
		var need := l - float(a["leg"])
		if budget >= need:
			budget -= need
			a["prev_node"] = int(a["node"])
			a["node"] = nxt
			a["leg"] = 0.0
			(a["route"] as Array).remove_at(0)
			a["arrived_hour"] = _hours
			# stop at a node with a hostile army in it
			for o: Dictionary in _armies:
				if _is_hostile(a, o) and int(o["node"]) == nxt and (o["route"] as Array).is_empty():
					a["route"] = []
					budget = 0.0
					break
		else:
			a["leg"] = float(a["leg"]) + budget
			budget = 0.0
	if (a["route"] as Array).is_empty():
		a["state"] = "camped" if a["state"] != "retreating" else "camped"
		a["retreat_type"] = ""
		if String((a["order"] as Dictionary).get("kind", "")) in ["attack", "raid"] and a["faction"] == PLAYER:
			_maybe_siege(a)


func _maybe_siege(a: Dictionary) -> void:
	if hub == null:
		return
	var sh: RefCounted = hub.mod("strongholds")
	if sh == null or not sh.has_method("nearest"):
		return
	var s: Dictionary = sh.call("nearest", node_pos(int(a["node"])))
	if not s.is_empty() and (s["pos"] as Vector2).distance_to(node_pos(int(a["node"]))) < 250.0 and s["owner"] != PLAYER and s["owner"] != "caldrenn" \
			and sh.has_method("begin_siege"):
		sh.call("begin_siege", int(s["id"]), PLAYER, int(a["strength"]))
		a["state"] = "besieging"


func tick_day(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	var out: Array = []
	if WorldGen.settlements.is_empty():
		return out
	if not _seeded_player:
		_seeded_player = true
		add_depot(PLAYER, _hq, 400.0)
		_mark_explored(_hq)
	_sync_war(ctx, out)
	_supply_day(out)
	_enemy_ai(ctx)
	_autonomy(out)
	_intel_day(ctx)
	_evidence_day(out)
	for k: String in _cut.keys():
		if int(_cut[k]) <= day:
			_cut.erase(k)
	for k2: String in _blocked.keys():
		if int(_blocked[k2]) <= day:
			_blocked.erase(k2)
	return out


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	if days <= 0 or WorldGen.settlements.is_empty():
		return out
	# deliver every courier / report at once, teleport armies to their destinations
	for c: Dictionary in _couriers.duplicate():
		out.append_array(_deliver(c, ctx))
	_couriers.clear()
	for a: Dictionary in _armies:
		if not (a["route"] as Array).is_empty():
			var hours_left := path_length([int(a["node"])] + a["route"]) / ARMY_SPEED
			if hours_left <= days * 24.0:
				a["node"] = int(a["route"][-1])
				a["route"] = []
				a["leg"] = 0.0
				a["state"] = "camped"
	# strategic auto-resolution of any co-located hostile armies
	for i in 3:
		_battles_step(ctx, out, true)
	# closed-form supply: each unsupplied day costs a day of food
	var d := mini(days, 30)
	for a2: Dictionary in _armies:
		if _supplied(a2):
			a2["supply"] = minf(MAX_SUPPLY, float(a2["supply"]) + d * 1.5)
		else:
			var left := maxf(0.0, float(a2["supply"]) - d)
			var starving := maxf(0.0, d - float(a2["supply"]))
			a2["supply"] = left
			a2["strength"] = int(float(a2["strength"]) * pow(0.97, starving))
			a2["morale"] = clampf(float(a2["morale"]) - 0.05 * starving, 0.0, 1.0)
	_armies = _armies.filter(func(x: Dictionary) -> bool: return int(x["strength"]) > 0)
	_day += days
	# intel ages by itself (day_seen stays); drop stale entries
	for key: String in _intel.keys():
		var e: Dictionary = _intel[key]
		if float(e["base_conf"]) * pow(0.5, float(_day - int(e["day_seen"])) / INTEL_HALF_LIFE) < INTEL_DROP and e["faction"] != PLAYER:
			_intel.erase(key)
	_hours += days * 24
	if days >= 3 and not _armies.is_empty():
		out.append("Your commanders' dispatches have piled up while you were away.")
	return out


# --- war integration ---------------------------------------------------------------

func _sync_war(ctx: Dictionary, out: Array) -> void:
	var life: Variant = ctx.get("life")
	var war: Variant = null
	if life != null and "war" in life:
		war = life.war
	var at_war := false
	var enemy := ""
	if war != null and war.has_method("is_at_war") and war.is_at_war():
		at_war = true
		enemy = String(war.enemy_id())
	elif war == null and bool(ctx.get("at_war", false)):
		at_war = _enemy != ""
		enemy = _enemy
	if at_war and enemy != "":
		_enemy = enemy
		var have := 0
		for a: Dictionary in _armies:
			if a["faction"] == enemy:
				have += 1
		if have == 0:
			var front: Array = war.front() if war != null and war.has_method("front") else []
			var r := _rng("war_spawn", enemy)
			var n := 2 + r.randi() % 2
			for i in n:
				var node := _hq
				if not front.is_empty():
					node = nearest_node((front[i % front.size()] as Dictionary)["pos"])
				var id := spawn_army(enemy, node, 120 + r.randi() % 220, PERSONALITIES[r.randi() % PERSONALITIES.size()], "%s host" % enemy.get_slice("_", 0).capitalize())
				_army(id)["auto"] = true
				if i == 0:
					add_depot(enemy, node, 500.0)
			out.append("Enemy columns are on the march.")
	elif _enemy != "" and not at_war:
		var gone := 0
		for a2: Dictionary in _armies:
			if a2["faction"] == _enemy and a2["auto"]:
				gone += 1
		if gone > 0:
			_armies = _armies.filter(func(x: Dictionary) -> bool: return not (x["faction"] == _enemy and x["auto"]))
			out.append("The enemy armies have withdrawn under the treaty.")
		_enemy = ""


func _enemy_ai(_ctx: Dictionary) -> void:
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER or not (a["route"] as Array).is_empty() or int(a["stunned_until"]) > _hours:
			continue
		var best := -1
		var bd := 1e18
		for o: Dictionary in _armies:
			if _is_hostile(a, o):
				var p := path(int(a["node"]), int(o["node"]))
				if not p.is_empty() and path_length(p) < bd and int(o["strength"]) < int(a["strength"]) * 1.6:
					bd = path_length(p)
					best = int(o["node"])
		if best < 0:
			best = _hq if float(a["morale"]) > 0.4 else int(a["node"])
		if best != int(a["node"]) and float(a["supply"]) > 1.0:
			_set_route(a, best)
			a["order"] = {"kind": "attack", "target": best}
			a["formation"] = "wedge"


## R§13: commanders with initiative act without waiting for orders.
func _autonomy(_out: Array) -> void:
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER or a["state"] == "engaged":
			continue
		var pers := String(a["commander"]["personality"])
		var foes := _enemies_adjacent(a)
		if foes.is_empty():
			continue
		var r := _rng("autonomy", int(a["id"]))
		var foe: Dictionary = foes[0]
		var ratio := float(a["strength"]) / maxf(1.0, float(foe["strength"]))
		if pers in ["aggressive", "ambitious"] and ratio > 0.8 and a["state"] == "camped" and r.randf() < 0.5:
			_set_route(a, int(foe["node"]))
			a["order"] = {"kind": "attack", "target": int(foe["node"]), "own_initiative": true}
			a["formation"] = "wedge"
			_dispatch(a, "%s attacked at %s on his own initiative." % [a["commander"]["name"], _nname(int(foe["node"]))])
		elif pers == "cautious" and ratio < 0.7 and r.randf() < 0.6:
			var dest := _retreat_dest(a)
			if dest != int(a["node"]):
				_set_route(a, dest)
				a["state"] = "retreating"
				a["retreat_type"] = "orderly"
				a["order"] = {"kind": "retreat", "target": dest, "own_initiative": true}
				_dispatch(a, "%s pulled back from %s without waiting for word." % [a["commander"]["name"], _nname(int(foe["node"]))])


# --- supply (R§18/19) --------------------------------------------------------------

func _supplied(a: Dictionary) -> bool:
	var avoid := {}
	for o: Dictionary in _armies:
		if _is_hostile(a, o) and int(o["node"]) != int(a["node"]):
			avoid[int(o["node"])] = true
	for k: String in _cut:
		if int(_cut[k]) > _day:
			avoid[int(k)] = true
	for d: Dictionary in _depots:
		if d["faction"] == a["faction"] and float(d["stock"]) > 0.0:
			var p := path(int(a["node"]), int(d["node"]), avoid)
			if not p.is_empty() and p.size() <= 7:
				return true
	return false


func _supply_day(out: Array) -> void:
	for a: Dictionary in _armies:
		var cost := float(a["strength"]) / 100.0 * 1.5
		if _supplied(a):
			for d: Dictionary in _depots:
				if d["faction"] == a["faction"] and float(d["stock"]) > 0.0:
					d["stock"] = maxf(0.0, float(d["stock"]) - cost)
					break
			a["supply"] = minf(MAX_SUPPLY, float(a["supply"]) + 1.0)   # +1.5 fed, -1 eaten... net kept simple
		else:
			a["supply"] = maxf(0.0, float(a["supply"]) - 1.0)
			if float(a["supply"]) <= 0.0:
				a["strength"] = int(float(a["strength"]) * 0.97)
				a["morale"] = clampf(float(a["morale"]) - 0.05, 0.0, 1.0)
				if a["faction"] == PLAYER and _rng("starve_note", int(a["id"])).randf() < 0.3:
					_dispatch(a, "%s reports the army is starving: the supply line is cut." % a["commander"]["name"])
		a["morale"] = clampf(float(a["morale"]) + 0.01, 0.0, 1.0)
		if a["faction"] == PLAYER:
			# corrupt drift: an ambitious commander may skim a little
			pass
	_armies = _armies.filter(func(x: Dictionary) -> bool: return int(x["strength"]) > 0)
	if out.is_empty():
		pass


func cut_supply_line(node: int, days := 4) -> void:
	_cut[str(node)] = _day + days


func block_edge(a: int, b: int, days := 5) -> void:
	_blocked[_ek(a, b)] = _day + days


func supply_status(army_id: int) -> Dictionary:
	var a := _army(army_id)
	if a.is_empty():
		return {}
	return {"supply_days": float(a["supply"]), "connected": _supplied(a)}


# --- battles (R§14-17, R§20) -------------------------------------------------------

func battles() -> Array:
	return _battles.duplicate(true)


func pending_live_battle() -> Dictionary:
	return _pending_live.duplicate(true)


func _side_power(ids: Array, defending: bool, node: int) -> float:
	var total := 0.0
	for id: int in ids:
		var a := _army(id)
		if a.is_empty():
			continue
		var f: Dictionary = FORMATIONS[a["formation"]]
		var supply_f := 0.6 + 0.4 * minf(float(a["supply"]), 3.0) / 3.0
		var terr := 1.0
		if defending:
			terr = float(TERRAIN_DEF.get(String(WorldGen.settlements[node]["kind"]), 1.0))
			if String((a["order"] as Dictionary).get("kind", "")) == "camp":
				terr += 0.1
		var ambush := 0.75 if int(a["ambush_until"]) > _hours else 1.0
		var misled := 0.85 if int(a["misled_until"]) > _hours else 1.0
		var lead := 1.0 + 0.06 * float(a["commander"]["skill"])
		total += float(a["strength"]) * (0.5 + float(a["morale"])) * supply_f * terr * float(f["def"] if defending else f["atk"]) * ambush * misled * lead
	return total


func _battles_step(ctx: Dictionary, out: Array, force_strategic := false) -> void:
	# live battle timing out becomes strategic
	if not _pending_live.is_empty() and (_hours - int(_pending_live["start_hour"]) >= LIVE_TIMEOUT_HOURS or force_strategic):
		out.append_array(_resolve(_pending_live["node"], _pending_live["attackers"], _pending_live["defenders"], false, {}))
		_pending_live = {}
	var by_node := {}
	for a: Dictionary in _armies:
		if (a["route"] as Array).is_empty() and a["state"] != "engaged":
			var n := int(a["node"])
			if not by_node.has(n):
				by_node[n] = []
			by_node[n].append(a)
	for n: int in by_node:
		var here: Array = by_node[n]
		var sides := {true: [], false: []}
		for a: Dictionary in here:
			sides[a["faction"] == PLAYER].append(int(a["id"]))
		if sides[true].is_empty() or sides[false].is_empty():
			continue
		# attackers: whoever arrived last
		var last_arr := -1
		var last_is_player := true
		for a: Dictionary in here:
			if int(a["arrived_hour"]) > last_arr:
				last_arr = int(a["arrived_hour"])
				last_is_player = a["faction"] == PLAYER
		var att: Array = sides[last_is_player]
		var deff: Array = sides[not last_is_player]
		var pp: Variant = ctx.get("player_pos")
		if _pending_live.is_empty() and not force_strategic and pp is Vector2 and (pp as Vector2).distance_to(node_pos(n)) < LIVE_RADIUS:
			_pending_live = {"id": _next_id, "node": n, "name": _nname(n), "pos": node_pos(n), "attackers": att, "defenders": deff,
				"start_hour": _hours, "attacker_strength": _sum_strength(att), "defender_strength": _sum_strength(deff)}
			_next_id += 1
			for id: int in att + deff:
				_army(id)["state"] = "engaged"
				_army(id)["engaged_day"] = _day
			out.append("Battle is joined at %s. Your presence may turn it." % _nname(n))
			continue
		out.append_array(_resolve(n, att, deff, false, {}))


func _sum_strength(ids: Array) -> int:
	var s := 0
	for id: int in ids:
		var a := _army(id)
		if not a.is_empty():
			s += int(a["strength"])
	return s


## The game reports a live battle's result. result: {winner: "attackers"|"defenders",
## attacker_losses: 0..1, defender_losses: 0..1}
func resolve_live_battle(result: Dictionary) -> Array:
	if _pending_live.is_empty():
		return []
	var b := _pending_live
	_pending_live = {}
	return _resolve(int(b["node"]), b["attackers"], b["defenders"], true, result)


func _resolve(node: int, att: Array, deff: Array, live: bool, forced: Dictionary) -> Array:
	var out: Array = []
	for id: int in att + deff:
		var a0 := _army(id)
		if not a0.is_empty():
			a0["engaged_day"] = _day
			if a0["state"] == "engaged":
				a0["state"] = "camped"
	var pa := _side_power(att, false, node)
	var pd := _side_power(deff, true, node)
	if pa <= 0.0 and pd <= 0.0:
		return out
	var r := _rng("battle", node * 131 + int(pa))
	var score := pa / maxf(pa + pd, 1.0) + r.randf_range(-0.12, 0.12)
	var att_wins := score > 0.5
	var margin := absf(score - 0.5)
	var a_loss := clampf(0.12 + (0.35 - margin) * (pd / maxf(pa, 1.0)) * 0.6, 0.05, 0.6) if att_wins else clampf(0.28 + margin * 0.9, 0.2, 0.75)
	var d_loss := clampf(0.12 + (0.35 - margin) * (pa / maxf(pd, 1.0)) * 0.6, 0.05, 0.6) if not att_wins else clampf(0.28 + margin * 0.9, 0.2, 0.75)
	if live and forced.has("winner"):
		att_wins = String(forced["winner"]) == "attackers"
		a_loss = clampf(float(forced.get("attacker_losses", a_loss)), 0.0, 0.95)
		d_loss = clampf(float(forced.get("defender_losses", d_loss)), 0.0, 0.95)
	var losses := {"player": 0, "enemy": 0}
	var retreat := "none"
	var winners: Array = att if att_wins else deff
	var losers: Array = deff if att_wins else att
	for id: int in att:
		losses[_side_key(id)] = int(losses[_side_key(id)]) + _hurt(id, a_loss)
	for id: int in deff:
		losses[_side_key(id)] = int(losses[_side_key(id)]) + _hurt(id, d_loss)
	for id: int in winners:
		var w := _army(id)
		if not w.is_empty():
			w["morale"] = clampf(float(w["morale"]) + 0.1, 0.0, 1.0)
	for id: int in losers:
		var l := _army(id)
		if not l.is_empty() and int(l["strength"]) > 0:
			l["morale"] = clampf(float(l["morale"]) - 0.25, 0.0, 1.0)
			retreat = _retreat(l, winners)
	var fname := "attackers" if att_wins else "defenders"
	var first_w := _army(int(winners[0])) if not winners.is_empty() else {}
	var first_l := _army(int(losers[0])) if not losers.is_empty() else {}
	var winner_faction := String(first_w.get("faction", "?")) if not first_w.is_empty() else String(first_l.get("faction", "?"))
	var rec := {"id": _next_id, "day": _day, "node": node, "name": _nname(node), "attackers": att.duplicate(), "defenders": deff.duplicate(),
		"winner": fname, "winner_faction": winner_faction, "live": live, "casualties": losses, "retreat": retreat}
	_next_id += 1
	_battles.append(rec)
	if _battles.size() > BATTLES_MAX:
		_battles.pop_front()
	var player_won := winner_faction == PLAYER
	var involves_player := _side_has_player(att) or _side_has_player(deff)
	if involves_player:
		out.append("%s at %s: %s (you lost %d, they lost %d)." % ["Victory" if player_won else "Defeat", _nname(node), "field held" if player_won else "retreat: %s" % retreat, losses["player"], losses["enemy"]])
		_rep(PLAYER, "victory" if player_won else ("rout" if retreat == "rout" else ""))
	_armies = _armies.filter(func(x: Dictionary) -> bool: return int(x["strength"]) > 0)
	return out


func _side_key(id: int) -> String:
	var a := _army(id)
	return "player" if not a.is_empty() and a["faction"] == PLAYER else "enemy"


func _side_has_player(ids: Array) -> bool:
	for id: int in ids:
		if _side_key(id) == "player":
			return true
	return false


func _hurt(id: int, frac: float) -> int:
	var a := _army(id)
	if a.is_empty():
		return 0
	var lost := int(float(a["strength"]) * frac)
	a["strength"] = int(a["strength"]) - lost
	return lost


## R§20: how the loser gets away.
func _retreat(l: Dictionary, winners: Array) -> String:
	var cmd: Dictionary = l["commander"]
	var r := _rng("retreat", int(l["id"]))
	var kind := "orderly"
	var ordered := String((l["order"] as Dictionary).get("retreat", ""))
	if float(l["morale"]) < 0.25:
		kind = "rout"
	elif ordered in ["feigned", "scorched", "orderly"] and ordered != "":
		kind = ordered
	elif String(cmd["personality"]) == "ambitious" and int(cmd["skill"]) >= 3 and r.randf() < 0.3:
		kind = "feigned"
	elif String(cmd["personality"]) == "aggressive" and r.randf() < 0.3:
		kind = "orderly"
	match kind:
		"rout":
			l["strength"] = int(float(l["strength"]) * r.randf_range(0.8, 0.9))
			l["stunned_until"] = _hours + 12
			l["morale"] = clampf(float(l["morale"]) - 0.1, 0.0, 1.0)
		"orderly":
			l["strength"] = int(float(l["strength"]) * 0.97)
		"feigned":
			for id: int in winners:
				var w := _army(id)
				if not w.is_empty():
					w["ambush_until"] = _hours + 24
					w["morale"] = clampf(float(w["morale"]) - 0.05, 0.0, 1.0)
			l["morale"] = clampf(float(l["morale"]) + 0.15, 0.0, 1.0)
		"scorched":
			for id: int in winners:
				var w2 := _army(id)
				if not w2.is_empty():
					w2["supply"] = maxf(0.0, float(w2["supply"]) - 1.5)
			_cut[str(int(l["node"]))] = _day + 3
	var dest := _retreat_dest(l)
	l["retreat_type"] = kind
	if dest != int(l["node"]):
		l["state"] = "retreating"
		_set_route(l, dest)
	else:
		l["state"] = "camped"
	l["order"] = {"kind": "retreat", "target": dest, "retreat": kind}
	if l["faction"] == PLAYER and kind == "rout":
		_dispatch(l, "%s's army broke and fled in disorder." % cmd["name"])
	if l["faction"] == PLAYER and String(cmd["personality"]) == "loyal" and int(l["strength"]) < int(l["max_strength"]) * 0.3 and r.randf() < 0.3:
		_dispatch(l, "%s fell defending the line." % cmd["name"])
		l["strength"] = 0
	return kind


func _rep(actor: String, act: String) -> void:
	if act == "" or hub == null:
		return
	var f: RefCounted = hub.mod("factions")
	if f != null and f.has_method("record_war_act"):
		f.call("record_war_act", actor, act)


# --- covert ops (R§21) -------------------------------------------------------------

## kind: sabotage (target node) | assassination (target army id) | forged_letter
## (target army id; opts.node to misdirect). opts.crestless defaults true.
## Returns {ok, kind, evidence_id, target_faction}.
func covert_op(kind: String, target: int, opts: Dictionary = {}) -> Dictionary:
	_ensure()
	_op_counter += 1
	var r := _rng("covert", _op_counter)
	var crestless := bool(opts.get("crestless", true))
	var res := {"ok": false, "kind": kind, "evidence_id": -1, "target_faction": ""}
	var skill := 1
	var tf := _enemy if _enemy != "" else "enemy"
	var node := target
	var ta := {}
	if kind in ["assassination", "forged_letter"]:
		ta = _army(target)
		if ta.is_empty():
			return res
		tf = String(ta["faction"])
		node = int(ta["node"])
		skill = int(ta["commander"]["skill"])
	else:
		for a: Dictionary in _armies:
			if a["faction"] != PLAYER:
				tf = String(a["faction"])
				break
	res["target_faction"] = tf
	var chance := clampf(0.7 - 0.08 * float(skill) + float(opts.get("agent_skill", 0)) * 0.05, 0.1, 0.9)
	var ok := r.randf() < chance
	res["ok"] = ok
	if ok:
		match kind:
			"sabotage":
				cut_supply_line(node, 4)
				for d: Dictionary in _depots:
					if d["faction"] == tf:
						d["stock"] = float(d["stock"]) * 0.7
				if opts.has("bridge_to"):
					block_edge(node, int(opts["bridge_to"]), 6)
			"assassination":
				ta["commander"] = {"name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]],
					"personality": PERSONALITIES[r.randi() % PERSONALITIES.size()], "skill": 1}
				ta["morale"] = clampf(float(ta["morale"]) - 0.3, 0.0, 1.0)
				ta["stunned_until"] = _hours + 12
			"forged_letter":
				ta["misled_until"] = _hours + 48
				ta["order"] = {"kind": "hold", "target": node}
				ta["route"] = []
				ta["state"] = "camped"
				if opts.has("node"):
					_set_route(ta, int(opts["node"]))
	var clarity := (0.15 if crestless else 0.5) + (0.0 if ok else 0.35) + r.randf_range(0.0, 0.2)
	var ev := {"id": _next_id, "kind": kind, "day": _day, "node": node, "target_faction": tf, "clarity": clarity, "discovered": false, "success": ok}
	_next_id += 1
	_evidence.append(ev)
	res["evidence_id"] = ev["id"]
	return res


func evidence() -> Array:
	return _evidence.duplicate(true)


func _evidence_day(out: Array) -> void:
	var keep: Array = []
	for ev: Dictionary in _evidence:
		if ev["discovered"]:
			keep.append(ev)
			continue
		var r := _rng("evidence", int(ev["id"]))
		if r.randf() < float(ev["clarity"]) * 0.12:
			ev["discovered"] = true
			out.append("Evidence surfaces: the %s near %s was your doing." % [String(ev["kind"]).replace("_", " "), _nname(int(ev["node"]))])
			if hub != null:
				var f: RefCounted = hub.mod("factions")
				if f != null and f.has_method("change_relation"):
					f.call("change_relation", PLAYER, String(ev["target_faction"]), "grievance", 25.0)
					f.call("change_relation", PLAYER, String(ev["target_faction"]), "trust", -15.0)
			_rep(PLAYER, "covert_exposed")
			keep.append(ev)
		elif _day - int(ev["day"]) < 30:
			keep.append(ev)
	_evidence = keep


# --- war council (R§35) ------------------------------------------------------------

func _roster() -> void:
	if not _advisors.is_empty():
		return
	for i in ADVISOR_ROLES.size():
		var r := RandomNumberGenerator.new()
		r.seed = hash([WorldSim.SEED, "advisor", i])
		_advisors.append({"name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]], "role": ADVISOR_ROLES[i],
			"personality": ROLE_PERSONALITY[ADVISOR_ROLES[i]], "competence": snappedf(r.randf_range(0.35, 0.95), 0.01)})


func _threat_target() -> Dictionary:
	var best := {}
	for e: Dictionary in known_map():
		if e["kind"] == "force" and e["faction"] != PLAYER and (best.is_empty() or float(e["confidence"]) > float(best["confidence"])):
			best = e
	return best


## Advisors' plans for the current situation. They differ by personality, may
## be wrong (hidden), and rely on known_map() only. Pick one with follow_advice().
func council_advice() -> Array:
	_ensure()
	_roster()
	var out: Array = []
	var foe := _threat_target()
	var own := 0
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER:
			own += int(a["strength"])
	var est := 0.0 if foe.is_empty() else (float(foe["est_min"]) + float(foe["est_max"])) * 0.5
	var ratio := float(own) / maxf(est, 1.0)
	var where := "the enemy" if foe.is_empty() else String(foe["name"])
	for i in _advisors.size():
		var adv: Dictionary = _advisors[i]
		var r := RandomNumberGenerator.new()
		r.seed = hash([WorldSim.SEED, "advice", _day, i])
		var plan := ""
		var text := ""
		match String(adv["role"]):
			"marshal":
				plan = "frontal_assault"
				text = "Strike them at %s now, before they gather. Steel decides this." % where
			"quartermaster":
				plan = "starve_them" if ratio < 1.5 else "secure_supplies"
				text = "Cut their supply near %s and let hunger fight for us." % where
			"scout":
				plan = "mountain_path"
				text = "There is a hill track round %s. We could fall on their flank." % where
			"mage":
				plan = "destroy_bridge"
				text = "Break the crossing at %s. They cannot bring their host across." % where
			"steward":
				plan = "hold_the_line" if ratio < 1.0 else "secure_supplies"
				text = "Hold the line and keep the depots full. We cannot afford a long campaign."
		var confidence := clampf(float(adv["competence"]) * 0.6 + 0.3 + (0.15 if adv["personality"] == "aggressive" else 0.0) + r.randf_range(-0.1, 0.1), 0.1, 0.99)
		out.append({"index": i, "advisor": adv["name"], "role": adv["role"], "personality": adv["personality"], "plan": plan, "text": text,
			"confidence": snappedf(confidence, 0.01)})
	return out


## Act on advice (0-based index from council_advice()). The plan may prove flawed.
func follow_advice(index: int) -> Dictionary:
	_roster()
	var advice := council_advice()
	if index < 0 or index >= advice.size():
		return {}
	var adv: Dictionary = advice[index]
	var lead := {}
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER and (lead.is_empty() or int(a["strength"]) > int(lead["strength"])):
			lead = a
	var foe := _threat_target()
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, "flaw", _day, index])
	var flawed := r.randf() > float(_advisors[index]["competence"]) + 0.15
	var res := {"plan": adv["plan"], "courier": {}, "flawed": false}
	if lead.is_empty():
		return res
	var target := int(foe.get("node", lead["node"]))
	match String(adv["plan"]):
		"frontal_assault":
			res["courier"] = issue_order(int(lead["id"]), {"kind": "attack", "target": target, "formation": "wedge"})
		"starve_them":
			cut_supply_line(target, 5)
			res["courier"] = issue_order(int(lead["id"]), {"kind": "camp", "target": int(lead["node"])})
		"mountain_path":
			res["courier"] = issue_order(int(lead["id"]), {"kind": "attack", "target": target, "formation": "skirmish"})
		"destroy_bridge":
			var p := path(int(lead["node"]), target)
			if p.size() >= 2:
				block_edge(int(p[-2]), int(p[-1]), 6)
			res["courier"] = issue_order(int(lead["id"]), {"kind": "camp", "target": int(lead["node"])})
		_:
			res["courier"] = issue_order(int(lead["id"]), {"kind": "hold", "target": int(lead["node"]), "formation": "square"})
	if flawed:
		lead["misled_until"] = _hours + 48
		res["flawed"] = true   # revealed to callers only as a consequence, never in council_advice()
	return res


# --- persistence ---------------------------------------------------------------

func serialize() -> Dictionary:
	var pl := _pending_live.duplicate(true)
	if not pl.is_empty():
		pl["pos"] = [(pl["pos"] as Vector2).x, (pl["pos"] as Vector2).y]
	return {"armies": _armies.duplicate(true), "couriers": _couriers.duplicate(true), "reports": _reports.duplicate(true),
		"intel": _intel.duplicate(true), "explored": _explored.duplicate(true), "depots": _depots.duplicate(true),
		"cut": _cut.duplicate(true), "blocked": _blocked.duplicate(true), "battles": _battles.duplicate(true),
		"pending_live": pl, "evidence": _evidence.duplicate(true), "advisors": _advisors.duplicate(true),
		"next_id": _next_id, "hours": _hours, "day": _day, "hq": _hq, "player_node": _player_node, "op_counter": _op_counter,
		"enemy": _enemy, "seeded_player": _seeded_player}


static func _ii(d: Dictionary, keys: Array) -> void:
	for k: String in keys:
		if d.has(k):
			d[k] = int(d[k])


static func _int_arr(a: Array) -> Array:
	var o: Array = []
	for v in a:
		o.append(int(v))
	return o


func deserialize(d: Dictionary) -> void:
	if not d.has("armies"):
		return
	_armies = (d["armies"] as Array).duplicate(true)
	for a: Dictionary in _armies:
		_ii(a, ["id", "node", "prev_node", "strength", "max_strength", "arrived_hour", "engaged_day", "misled_until", "ambush_until", "stunned_until", "sent_day"])
		a["route"] = _int_arr(a["route"])
		a["commander"]["skill"] = int(a["commander"]["skill"])
		_ii(a["order"], ["target"])
	_couriers = (d.get("couriers", []) as Array).duplicate(true)
	for c: Dictionary in _couriers:
		_ii(c, ["id", "army_id", "sent_hour", "sent_day", "eta_hours", "elapsed", "checked"])
		_ii(c["order"], ["target"])
		for lg: Array in c["legs"]:
			lg[0] = int(lg[0])
	_reports = (d.get("reports", []) as Array).duplicate(true)
	for rp: Dictionary in _reports:
		_ii(rp, ["due_hour", "army_id", "day"])
	_intel = (d.get("intel", {}) as Dictionary).duplicate(true)
	for k: String in _intel:
		_ii(_intel[k], ["army_id", "node", "est_min", "est_max", "day_seen"])
	_explored = (d.get("explored", {}) as Dictionary).duplicate(true)
	for k2: String in _explored:
		_explored[k2] = int(_explored[k2])
	_depots = (d.get("depots", []) as Array).duplicate(true)
	for dp: Dictionary in _depots:
		dp["node"] = int(dp["node"])
	_cut = (d.get("cut", {}) as Dictionary).duplicate(true)
	for k3: String in _cut:
		_cut[k3] = int(_cut[k3])
	_blocked = (d.get("blocked", {}) as Dictionary).duplicate(true)
	for k4: String in _blocked:
		_blocked[k4] = int(_blocked[k4])
	_battles = (d.get("battles", []) as Array).duplicate(true)
	for b: Dictionary in _battles:
		_ii(b, ["id", "day", "node"])
		b["attackers"] = _int_arr(b["attackers"])
		b["defenders"] = _int_arr(b["defenders"])
		_ii(b["casualties"], ["player", "enemy"])
	_pending_live = (d.get("pending_live", {}) as Dictionary).duplicate(true)
	if not _pending_live.is_empty():
		_ii(_pending_live, ["id", "node", "start_hour", "attacker_strength", "defender_strength"])
		_pending_live["attackers"] = _int_arr(_pending_live["attackers"])
		_pending_live["defenders"] = _int_arr(_pending_live["defenders"])
		var pv: Array = _pending_live["pos"]
		_pending_live["pos"] = Vector2(float(pv[0]), float(pv[1]))
	_evidence = (d.get("evidence", []) as Array).duplicate(true)
	for ev: Dictionary in _evidence:
		_ii(ev, ["id", "day", "node"])
	_advisors = (d.get("advisors", []) as Array).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	_hours = int(d.get("hours", 0))
	_day = int(d.get("day", 0))
	_hq = int(d.get("hq", 0))
	_player_node = int(d.get("player_node", 0))
	_op_counter = int(d.get("op_counter", 0))
	_enemy = String(d.get("enemy", ""))
	_seeded_player = bool(d.get("seeded_player", false))
