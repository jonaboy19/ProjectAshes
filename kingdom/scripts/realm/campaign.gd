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

const WarUnits := preload("res://scripts/realm/war_units.gd")
const Tactical := preload("res://scripts/realm/tactical.gd")
const Siege := preload("res://scripts/realm/siege.gd")
const WarAdvisors := preload("res://scripts/realm/war_advisors.gd")
const Military := preload("res://scripts/sim/military.gd")
const SightingReport := preload("res://scripts/realm/sighting_report.gd")
const MAX_SPY_REPORTS := 64
var _spy_reports: Array[Dictionary] = []

const PLAYER := "player"
const ARMY_SPEED := 180.0          # metres per hour on a road (world is 12 km wide; 60 on the 4 km map, 120 on the 8 km map)
const COURIER_SPEED := 540.0        # (180 on the 4 km map, 360 on the 8 km map)
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
var _life: Variant = null                # the Life node (or a stand-in with .war) from the last tick ctx / bind_life()
var _treaty_applied := -1                # day of the last peace deal whose terms were applied

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
	_init_field(a)
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
## opts.speed_mult: a faster rider (the player carrying it himself rides 1.6x a hired courier); opts.safe: the
## message cannot be cut down on the road (the bearer slips past patrols).
func issue_order(army_id: int, order: Dictionary, opts: Dictionary = {}) -> Dictionary:
	_ensure()
	var a := _army(army_id)
	if a.is_empty() or a["faction"] != PLAYER:
		return {}
	var origin := _player_node
	var p := path(origin, int(a["node"]))
	var hours := 1.0
	var legs: Array = []
	var spd := COURIER_SPEED * maxf(0.5, float(opts.get("speed_mult", 1.0)))
	if p.size() >= 2:
		var acc := 0.0
		for i in range(1, p.size()):
			acc += _elen(p[i - 1], p[i])
			legs.append([int(p[i]), acc / spd])
		hours = maxf(1.0, ceil(acc / spd))
	var c := {"id": _next_id, "army_id": army_id, "order": order.duplicate(true), "sent_hour": _hours, "sent_day": _day,
		"eta_hours": int(hours), "elapsed": 0, "legs": legs, "checked": 0, "intercepted": false, "safe": bool(opts.get("safe", false))}
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
				if e["faction"] != PLAYER and int(e["node"]) == nd and (e["route"] as Array).is_empty() and not bool(c.get("safe", false)) and \
						_rng("intercept", int(c["id"]) * 97 + nd).randf() < 0.22:
					c["intercepted"] = true
					dead = true
					out.append("A courier was cut down near %s. The order never arrived." % _nname(nd))
					_gain_intel_on_courier(e)
					break
			if dead:
				break
		if dead:
			if c.has("unit_id"):
				_log_order(int(c["id"]), "lost")
			continue
		if int(c["elapsed"]) >= int(c["eta_hours"]) and c.has("unit_id"):
			var fate := _unit_courier_fate(c)
			if fate == "late":
				c["eta_hours"] = int(c["eta_hours"]) + 2
				c["late"] = true
				keep.append(c)
			elif fate == "lost":
				_log_order(int(c["id"]), "lost")
			else:
				_deliver_unit(c, out)
		elif int(c["elapsed"]) >= int(c["eta_hours"]):
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
	if ctx.get("life") != null:
		_life = ctx["life"]
	var out: Array = []
	if WorldGen.settlements.is_empty():
		return out
	_hours += 1
	_deliver_spy_reports(out)
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2:
		_player_node = nearest_node(pp)
		if (pp as Vector2).distance_to(node_pos(_player_node)) < 300.0:
			_mark_explored(_player_node)
	_courier_step(ctx, out)
	for a: Dictionary in _armies:
		_move(a, ctx)
	_battles_step(ctx, out)
	_field_step(ctx, out)
	_report_step(out)
	if pp is Vector2:
		for a: Dictionary in _armies:
			if a["faction"] != PLAYER and army_pos(a).distance_to(pp) < 250.0:
				_see(a, "direct", 0.1, 1.0, _day)
	return out


func _move(a: Dictionary, ctx: Dictionary) -> void:
	if int(a["stunned_until"]) > _hours or (a["route"] as Array).is_empty() or a["state"] == "engaged" or _dispersed(a):
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
	if ctx.get("life") != null:
		_life = ctx["life"]
	var out: Array = []
	if WorldGen.settlements.is_empty():
		return out
	if not _seeded_player:
		_seeded_player = true
		add_depot(PLAYER, _hq, 400.0)
		_mark_explored(_hq)
	_sync_war(ctx, out)
	_feed_casus_belli(out)
	_field_day()
	_supply_day(out)
	_enemy_ai(ctx)
	_autonomy(out)
	_intel_day(ctx)
	_evidence_day(out)
	_siege_day(out)
	_goals_day(out)
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
	_field_catch_up(days, out)
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
		out.append_array(_apply_treaty(_enemy))
		_enemy = ""


func _enemy_ai(_ctx: Dictionary) -> void:
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER or not (a["route"] as Array).is_empty() or int(a["stunned_until"]) > _hours or a["state"] == "engaged":
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
		if (a["route"] as Array).is_empty() and a["state"] != "engaged" and not _dispersed(a):
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
## (target army id; opts.node to misdirect) | spy (target army id: precise intel on it and the enemy court).
## opts.crestless defaults true. Every op leaves evidence (here and in society.evidence_items): a clumsy or
## failed one is easy to find, and a found one sours relations, gives the enemy a casus belli and raises tension.
## Returns {ok, kind, evidence_id, society_evidence, target_faction}.
func covert_op(kind: String, target: int, opts: Dictionary = {}) -> Dictionary:
	_ensure()
	_op_counter += 1
	var r := _rng("covert", _op_counter)
	var crestless := bool(opts.get("crestless", true))
	var res := {"ok": false, "kind": kind, "evidence_id": -1, "society_evidence": "", "target_faction": ""}
	var skill := 1
	var tf := _enemy if _enemy != "" else "enemy"
	var node := target
	var ta := {}
	if kind in ["assassination", "forged_letter", "spy"]:
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
	var chance := clampf((0.85 if kind == "spy" else 0.7) - 0.08 * float(skill) + float(opts.get("agent_skill", 0)) * 0.05, 0.1, 0.9)
	var ok := r.randf() < chance
	res["ok"] = ok
	var war: Variant = _war()
	if ok:
		match kind:
			"sabotage":
				cut_supply_line(node, 4)
				for d: Dictionary in _depots:
					if d["faction"] == tf:
						d["stock"] = float(d["stock"]) * 0.7
				if opts.has("bridge_to"):
					block_edge(node, int(opts["bridge_to"]), 6)
				if war != null:
					war.add_support(0.03)
			"assassination":
				ta["commander"] = {"name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]],
					"personality": PERSONALITIES[r.randi() % PERSONALITIES.size()], "skill": 1}
				ta["morale"] = clampf(float(ta["morale"]) - 0.3, 0.0, 1.0)
				ta["stunned_until"] = _hours + 12
				if war != null:
					war.add_support(0.06)
			"forged_letter":
				ta["misled_until"] = _hours + 48
				ta["order"] = {"kind": "hold", "target": node}
				ta["route"] = []
				ta["state"] = "camped"
				if opts.has("node"):
					_set_route(ta, int(opts["node"]))
				if war != null:
					war.add_support(0.02)
			"spy":
				add_intel(target, "spy", 0.1, 0.95)
				res["comp_known"] = true
	var clarity := (0.15 if crestless else 0.5) + (0.0 if ok else 0.35) + r.randf_range(0.0, 0.2)
	if kind == "spy":
		clarity *= 0.5     # watching leaves fewer marks than cutting
	var ev := {"id": _next_id, "kind": kind, "day": _day, "node": node, "target_faction": tf, "clarity": clarity, "discovered": false, "success": ok, "soc": ""}
	_next_id += 1
	ev["soc"] = _society_evidence(kind, node, clarity)
	_evidence.append(ev)
	res["evidence_id"] = ev["id"]
	res["society_evidence"] = ev["soc"]
	return res


## Records a trace of something the player did that is not a covert_op (a provocation): it can surface like one.
func note_trace(kind: String, node: int, target_faction: String, clarity: float, soc_id := "") -> int:
	var ev := {"id": _next_id, "kind": kind, "day": _day, "node": node, "target_faction": target_faction, "clarity": clarity, "discovered": false, "success": true, "soc": soc_id}
	_next_id += 1
	_evidence.append(ev)
	return int(ev["id"])


const EVIDENCE_TYPE := {"sabotage": "cut_rope", "assassination": "blade_and_badge", "forged_letter": "forged_seal", "spy": "coded_note"}


func _society_evidence(kind: String, node: int, clarity: float) -> String:
	if hub == null:
		return ""
	var soc: RefCounted = hub.mod("society")
	if soc == null or not soc.has_method("add_evidence"):
		return ""
	return String(soc.call("add_evidence", "war_" + kind, String(EVIDENCE_TYPE.get(kind, "trace")), clarity, node))


## The bound Life's war_sim, or null.
func _war() -> Variant:
	if _life != null and "war" in _life and _life.war != null and _life.war.has_method("add_tension"):
		return _life.war
	return null


func bind_life(life: Variant) -> void:
	_life = life


func evidence() -> Array:
	return _evidence.duplicate(true)


## Burying the trail: burns the clues of one op (costs the caller's time and gold). Returns true if it was still buried.
func cover_tracks(evidence_id: int) -> bool:
	for ev: Dictionary in _evidence:
		if int(ev["id"]) == evidence_id and not bool(ev["discovered"]):
			ev["clarity"] = float(ev["clarity"]) * 0.3
			if hub != null and String(ev.get("soc", "")) != "":
				var soc: RefCounted = hub.mod("society")
				if soc != null and soc.has_method("destroy_evidence"):
					soc.call("destroy_evidence", String(ev["soc"]))
			return true
	return false


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
			var war: Variant = _war()
			if war != null and String(ev["target_faction"]) in war.WAR_CANDIDATES:
				var tfn := String(ev["target_faction"])
				war.add_tension(tfn, 12.0)
				war.offer_cb(tfn, "incident", "Crown agents were caught behind a %s near %s." % [String(ev["kind"]).replace("_", " "), _nname(int(ev["node"]))], _day, "enemy")
			_rep(PLAYER, "covert_exposed")
			keep.append(ev)
		elif _day - int(ev["day"]) < 30:
			keep.append(ev)
	_evidence = keep


# --- player influence on the war (scripts/realm/war_influence.gd drives these) ---------------------------

## Feeds war_sim reasons to fight that only the realm knows about: a claim on land the player holds or that
## is contested, and a succession vacuum in a great house. Checked once a day, at peace.
func _feed_casus_belli(out: Array) -> void:
	var war: Variant = _war()
	if war == null or war.is_at_war() or hub == null:
		return
	var r := _rng("cb_feed", _day)
	var cands: Array = []
	for id: String in war.WAR_CANDIDATES:
		if not war.under_truce(id):
			cands.append(id)
	if cands.is_empty():
		return
	var land: RefCounted = hub.mod("land")
	if land != null and r.randf() < 0.05:
		for region in land.regions():
			var d: Dictionary = land.deed(region)
			var sid := int(str(region)) if str(region).is_valid_int() else -1
			if sid < 0 or sid >= WorldGen.settlements.size():
				continue
			var frontier := String(WorldGen.settlements[sid].get("kind", "")) == "frontier_town"
			var mine := String(d.get("holder", "")) == "player" or String(d.get("occupier", "")) == "player"
			var contested: bool = land.in_conflict(region)
			if frontier and (mine or contested):
				var id: String = cands[r.randi() % cands.size()]
				war.offer_cb(id, "claim", "%s presses its claim to %s, %s." % [war.display_name(id), String(d["name"]), "now in your hands" if mine else "where the crown's rule is contested"], _day, "enemy" if mine else "caldrenn")
				out.append("Envoys from %s dispute the title to %s." % [war.display_name(id), String(d["name"])])
				break
	var nob: Variant = _life.nobility if _life != null and "nobility" in _life else null
	if nob != null and "houses" in nob and r.randf() < 0.0012:
		for h: Dictionary in nob.houses:
			if (h.get("heirs", []) as Array).is_empty():
				var id2: String = cands[r.randi() % cands.size()]
				if war.has_cb_kind(id2, "succession"):
					break
				war.offer_cb(id2, "succession", "%s has no heir, and %s courts its vassals." % [String(h.get("name", "A great house")), war.display_name(id2)], _day, "enemy")
				break


## Applies a concluded peace's land, tribute, marriage and warmth to the realm. `enemy` is the nation id.
func _apply_treaty(enemy: String) -> Array:
	var out: Array = []
	var war: Variant = _war()
	if war == null:
		return out
	var t: Dictionary = war.last_treaty
	if t.is_empty() or String(t.get("enemy", "")) != enemy or int(t.get("day", -1)) <= _treaty_applied:
		return out
	_treaty_applied = int(t["day"])
	var winner := String(t.get("winner", "draw"))
	var f: RefCounted = hub.mod("factions") if hub != null else null
	var land: RefCounted = hub.mod("land") if hub != null else null
	var land_name := String(t.get("land", ""))
	if land_name != "" and land != null:
		for s: Dictionary in WorldGen.settlements:
			if String(s["name"]) == land_name:
				var sid := int(s["id"])
				if winner == "enemy":
					land.seize(sid, enemy, _treaty_applied)
					_captured[str(nearest_node(s["pos"]))] = enemy
					out.append("%s passes to %s under the treaty." % [land_name, war.display_name(enemy)])
				else:
					land.remember(sid, "liberation", 0.5, _treaty_applied)
					_captured.erase(str(nearest_node(s["pos"])))
					out.append("%s is confirmed in the crown's hands." % land_name)
				break
	var tr := int(t.get("tribute", 0))
	if f != null and tr > 0 and f.has_method("add_wealth") and winner != "draw":
		f.call("add_wealth", "caldrenn", float(tr) * (0.02 if winner == "caldrenn" else -0.02))
		f.call("add_wealth", enemy, float(tr) * (-0.02 if winner == "caldrenn" else 0.02))
	if f != null and not (t.get("marriage", {}) as Dictionary).is_empty() and f.has_method("propose_marriage"):
		var m: Dictionary = f.call("propose_marriage", "caldrenn", enemy, false)
		if bool(m.get("accepted", false)):
			out.append("A royal match seals the peace with %s." % war.display_name(enemy))
	if f != null:
		f.call("change_relation", "caldrenn", enemy, "grievance", -10.0)
		f.call("change_relation", "caldrenn", enemy, "trust", 6.0)
	return out


## Supplies a player depot (created at `node` if none): army quartermasters buy from merchants. Returns the stock.
func supply_depot(node: int, amount: float) -> float:
	_ensure()
	add_depot(PLAYER, node, amount)
	var stock := 0.0
	for d: Dictionary in _depots:
		if d["faction"] == PLAYER and int(d["node"]) == node:
			stock = float(d["stock"])
	# armies camped at or next to the depot eat a little better right away
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER and int(a["node"]) == node:
			a["supply"] = minf(MAX_SUPPLY, float(a["supply"]) + amount / maxf(50.0, float(a["strength"])) * 0.6)
	return stock


## A local levy under the player's own banner at `node` (strength men). Returns the army id.
func raise_militia(node: int, men: int, army_name := "Militia") -> int:
	_ensure()
	var id := spawn_army(PLAYER, node, men, "loyal", army_name)
	var a := _army(id)
	a["morale"] = 0.7
	a["commander"]["skill"] = 1
	return id


## The player fights personally in engagement `eng_id`, on the crown's side (or `side` "a"/"b" if given):
## an elite champion joins that side (and the tactical map, if open), and its troops fight steadier.
## Returns {ok, reason, side, wounded, risk}.
func join_engagement(eng_id: int, side := "") -> Dictionary:
	var e := engagement_raw(eng_id)
	if e.is_empty() or String(e["status"]) == "ended":
		return {"ok": false, "reason": "That fight is over."}
	var s := side
	if s == "":
		if _eng_has_player(e, "a"):
			s = "a"
		elif _eng_has_player(e, "b"):
			s = "b"
		elif String(e["fa"]) in [PLAYER, "caldrenn"]:
			s = "a"
		elif String(e["fb"]) in [PLAYER, "caldrenn"]:
			s = "b"
	if s == "":
		return {"ok": false, "reason": "Neither side there fights for the crown."}
	if String(e.get("champion_side", "")) != "":
		return {"ok": false, "reason": "You are already in the line."}
	e["champion_side"] = s
	(e["log"] as Array).append("You take a place in the line.")
	var r := _rng("champion", eng_id)
	var risk := 0.18
	var wounded := r.randf() < risk
	e["champion_wounded"] = wounded
	_rep(PLAYER, "victory")
	var tt: RefCounted = _tacs.get(eng_id)
	if tt != null and String(tt.phase) in ["battle", "deploy"]:
		var ks := 0 if s == "a" else 1
		tt.add_unit(ks, {"kind": "champion", "name": "You, sword in hand", "men": 1, "quality": 0.95, "morale": 1.0, "hero": true, "layer": "front"})
	return {"ok": true, "reason": "", "side": s, "wounded": wounded, "risk": risk}


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


# --- war field: formations, pieces, authority, orders, fog, engagements -------------------
# War Map phase A (docs/design/WAR_COMMAND_RULEBOOK.md). Every army owns `units` (its internal
# formations, R§3). A unit is "attached" (it travels with its army along the road graph) until it is
# given its own order, then it is "detached": an independent piece with its own position that walks
# the real terrain. Contact with a detached piece opens an engagement record (R§7-8) that is
# resolved hour by hour from the factors list until somebody breaks or the player intervenes.

const CONTACT_R := 100.0            # metres: pieces this close can clash
const JOIN_R := 170.0               # friendly pieces this close join an engagement
const MERGE_R := 150.0              # pieces must be this close to merge / rejoin
const AMBUSH_R := 190.0
const HARASS_R := 220.0
const PLAYER_BASE_CAP := 600        # men the player can direct personally without a rank
const APPOINTED_CAP := 4000         # ... while appointed to a campaign command (R§14)
const ENG_MAX_ROUNDS := 30
const SIGHT_KEEP_HOURS := 120
const ORDERS_KEEP := 60
const ENGS_KEEP := 24
const MAP_HALF := WorldGen.WORLD_HALF
const TERR_CELL := 128.0

var _engs: Array = []               # engagement records
var _tacs: Dictionary = {}          # engagement id -> Tactical battle (phase B)
var _sieges: Dictionary = {}        # key -> Siege
var _goals: Array = []              # war goals (R§55)
var _next_goal := 1
var _wstaff: Array = []             # battlefield assistants (R§18)
var _sight: Dictionary = {}         # piece key -> last sighting of an enemy piece
var _orders_log: Array = []         # the player's orders and what they know about them
var _pcmd: Dictionary = {"rank": "recruit", "appointed": {}}
var _captured: Dictionary = {}      # "node" -> faction that took it
var _next_uid := 1                  # units, commanders, engagements
var _weather := "clear"
var _season := "spring"
# derived (not serialised)
var _terr_cache: Dictionary = {}
var _terr_tab: Dictionary = {}
var _uidx: Dictionary = {}          # unit id -> army id
var _uidx_dirty := true
var _perf: Dictionary = {}          # microseconds per phase of the field step (diagnostics)


func _uid() -> int:
	_next_uid += 1
	return _next_uid - 1


func _hash_f(tag: String, id: int) -> float:
	return float(hash([WorldSim.SEED, tag, id]) % 10000) / 10000.0


# --- terrain -----------------------------------------------------------------------

func _terr_dict(id: String) -> Dictionary:
	if not _terr_tab.has(id):
		var t: Dictionary = (WarUnits.terrain(id) as Dictionary).duplicate()
		t["id"] = id
		_terr_tab[id] = t
	return _terr_tab[id]


## The ground at a world position (WorldGen: water, roads, towns, forest, slope), cached per 128 m cell.
## Returns a WarUnits.TERRAIN entry plus "id".
func terrain_at(p: Vector2) -> Dictionary:
	var cx := int(floor(p.x / TERR_CELL))
	var cy := int(floor(p.y / TERR_CELL))
	var key := (cx + 100) * 1000 + (cy + 100)
	if _terr_cache.has(key):
		return _terr_dict(String(_terr_cache[key]))
	var x := (float(cx) + 0.5) * TERR_CELL
	var y := (float(cy) + 0.5) * TERR_CELL
	var id := "plain"
	if WorldGen.settlements.is_empty() or absf(x) > MAP_HALF or absf(y) > MAP_HALF:
		id = "mountain" if not WorldGen.settlements.is_empty() else "plain"
	elif WorldGen.is_water(x, y):
		id = "ford"
	else:
		var town := false
		for s: Dictionary in WorldGen.settlements:
			if (s["pos"] as Vector2).distance_to(Vector2(x, y)) < float(s["radius"]) * 1.2:
				town = true
				break
		if town:
			id = "town"
		elif WorldGen.road_distance(x, y) < 14.0:
			id = "road"
		else:
			var h := WorldGen.height(x, y)
			var hx := WorldGen.height(x + 60.0, y) - h
			var hy := WorldGen.height(x, y + 60.0) - h
			var sl := sqrt(hx * hx + hy * hy) / 60.0
			if h > 100.0 or sl > 1.0:
				id = "mountain"
			elif sl > 0.55 or h > 70.0:
				id = "hills"
			elif WorldGen.forest_density(x, y) > 0.55:
				id = "forest"
	_terr_cache[key] = id
	return _terr_dict(id)


func _place_name(p: Vector2) -> String:
	if WorldGen.settlements.is_empty():
		return "the field"
	var n := nearest_node(p)
	var c := node_pos(n)
	var d := p - c
	if d.length() < 260.0:
		return _nname(n)
	var dir := ""
	dir += "North" if d.y < -absf(d.x) * 0.4 else ("South" if d.y > absf(d.x) * 0.4 else "")
	dir += "East" if d.x > absf(d.y) * 0.4 else ("West" if d.x < -absf(d.y) * 0.4 else "")
	return "%s of %s" % [dir, _nname(n)]


# --- units & commanders (R§3, R§9-11) --------------------------------------------------

static func _wing_of(kind: String) -> String:
	if kind in ["archer", "mage"]:
		return "ranged"
	if kind in ["heavy_cav", "light_cav", "scout"]:
		return "cavalry"
	return "infantry"


func _mk_sub(a: Dictionary, wing: String, r: RandomNumberGenerator) -> Dictionary:
	var pers: String = WarUnits.PERSONALITIES[r.randi() % WarUnits.PERSONALITIES.size()]
	var skill := 1 + r.randi() % 3
	var sub := {"id": _uid(), "name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]],
		"personality": pers, "skill": skill, "wing": wing}
	var at := WarUnits.make_attrs(skill, pers, r)
	for k: String in at:
		sub[k] = at[k]
	return sub


func _mk_unit(a: Dictionary, uname: String, kind: String, men: int, r: RandomNumberGenerator) -> Dictionary:
	var skill := int((a["commander"] as Dictionary)["skill"])
	var q := clampf(0.42 + 0.06 * float(skill) + r.randf_range(-0.1, 0.15) + (0.05 if kind == "heavy_cav" else 0.0), 0.2, 0.95)
	return {"id": _uid(), "army": int(a["id"]), "name": uname, "base": uname, "kind": kind, "men": men, "max_men": men,
		"quality": snappedf(q, 0.01), "morale": float(a["morale"]), "fatigue": 0.0, "cmd": 0, "owner": "kingdom", "assigned": "",
		"detached": false, "x": 0.0, "y": 0.0, "order": {"behavior": "hold", "since": _hours}, "state": "idle", "eng": 0, "cap": 0}


func _init_field(a: Dictionary) -> void:
	var r := _rng("field_init", int(a["id"]))
	var cmd: Dictionary = a["commander"]
	var at := WarUnits.make_attrs(int(cmd["skill"]), String(cmd["personality"]), r)
	for k: String in at:
		cmd[k] = at[k]
	cmd["id"] = _uid()
	var rows := WarUnits.alloc_units(int(a["strength"]))
	var subs: Array = []
	var wings := {}
	if rows.size() >= 3:
		for w: String in ["infantry", "ranged", "cavalry"]:
			var sub := _mk_sub(a, w, r)
			subs.append(sub)
			wings[w] = int(sub["id"])
	a["subs"] = subs
	var units: Array = []
	for row: Array in rows:
		var u := _mk_unit(a, String(row[0]), String(row[1]), int(row[2]), r)
		u["cmd"] = int(wings.get(_wing_of(String(row[1])), 0))
		units.append(u)
	a["units"] = units
	a["ndet"] = 0
	a["usum"] = int(a["strength"])
	a["umor"] = float(a["morale"])
	_uidx_dirty = true


func _index_units() -> void:
	_uidx.clear()
	for a: Dictionary in _armies:
		for u: Dictionary in (a["units"] as Array):
			_uidx[int(u["id"])] = int(a["id"])
	_uidx_dirty = false


func _unit(uid: int) -> Dictionary:
	if _uidx_dirty:
		_index_units()
	if not _uidx.has(uid):
		return {}
	var a := _army(int(_uidx[uid]))
	if a.is_empty():
		return {}
	for u: Dictionary in (a["units"] as Array):
		if int(u["id"]) == uid:
			return u
	return {}


func _army_of(u: Dictionary) -> Dictionary:
	return _army(int(u["army"]))


func _cmd_of(a: Dictionary, u: Dictionary) -> Dictionary:
	var cid := int(u.get("cmd", 0))
	if cid != 0:
		for s: Dictionary in (a["subs"] as Array):
			if int(s["id"]) == cid:
				return s
	return a["commander"]


func _upos(a: Dictionary, u: Dictionary) -> Vector2:
	return Vector2(float(u["x"]), float(u["y"])) if bool(u["detached"]) else army_pos(a)


func _men_of(a: Dictionary) -> int:
	var s := 0
	for u: Dictionary in (a["units"] as Array):
		s += int(u["men"])
	return s


## Keeps units and the army's legacy strength / morale in step: the old army-level code changes
## `strength` and `morale`, the new unit-level code changes the units.
func _sync(a: Dictionary) -> void:
	var units: Array = a["units"]
	if units.is_empty():
		return
	var sum := 0
	for u: Dictionary in units:
		sum += int(u["men"])
	var s := int(a["strength"])
	if sum != s:
		# the army-level code changed the strength (a strategic battle, hunger): it touches the units that are
		# with the army, not the pieces that went off on their own
		var att: Array = []
		var att_sum := 0
		for u: Dictionary in units:
			if not bool(u["detached"]):
				att.append(u)
				att_sum += int(u["men"])
		var det_sum := sum - att_sum
		if not att.is_empty() and att.size() < units.size() and s - det_sum >= 0 and att_sum > 0:
			_scale_units(att, s - det_sum, att_sum)
		else:
			_scale_units(units, s, sum)
		a["usum"] = s
		_prune(a)
	var dm := float(a["morale"]) - float(a["umor"])
	if absf(dm) > 0.000001:
		for u: Dictionary in units:
			u["morale"] = clampf(float(u["morale"]) + dm, 0.0, 1.0)
		a["umor"] = float(a["morale"])


func _scale_units(units: Array, target: int, sum: int) -> void:
	if sum <= 0 or target < 0:
		return
	var fr: Array = []
	var used := 0
	for i in units.size():
		var exact := float(int((units[i] as Dictionary)["men"])) * float(target) / float(sum)
		var n := int(floor(exact))
		(units[i] as Dictionary)["men"] = n
		used += n
		fr.append([exact - float(n), i])
	fr.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var left := target - used
	var k := 0
	while left > 0 and not fr.is_empty():
		var idx: int = fr[k % fr.size()][1]
		(units[idx] as Dictionary)["men"] = int((units[idx] as Dictionary)["men"]) + 1
		left -= 1
		k += 1


## After unit-level fighting: the army's strength and morale follow its units.
func _recalc(a: Dictionary) -> void:
	var units: Array = a["units"]
	var men := 0
	var mor := 0.0
	for u: Dictionary in units:
		men += int(u["men"])
		mor += float(u["morale"]) * float(u["men"])
	a["strength"] = men
	a["usum"] = men
	if men > 0:
		a["morale"] = clampf(mor / float(men), 0.0, 1.0)
		a["umor"] = float(a["morale"])


func _prune(a: Dictionary) -> void:
	var units: Array = a["units"]
	var keep: Array = []
	for u: Dictionary in units:
		if int(u["men"]) > 0:
			keep.append(u)
	if keep.size() != units.size():
		a["units"] = keep
		_recount(a)
		_uidx_dirty = true


func _recount(a: Dictionary) -> void:
	var n := 0
	for u: Dictionary in (a["units"] as Array):
		if bool(u["detached"]):
			n += 1
	a["ndet"] = n


func _copy_unit(a: Dictionary, u: Dictionary) -> Dictionary:
	var c := u.duplicate(true)
	var p := _upos(a, u)
	c["pos"] = p
	c["x"] = p.x
	c["y"] = p.y
	c["army_name"] = a["name"]
	c["faction"] = a["faction"]
	c["commander_name"] = String(_cmd_of(a, u)["name"])
	c["personality"] = String(_cmd_of(a, u)["personality"])
	c["terrain"] = String(terrain_at(p)["name"])
	return c


func army_units(army_id: int) -> Array:
	var a := _army(army_id)
	var out: Array = []
	if a.is_empty():
		return out
	_sync(a)
	for u: Dictionary in (a["units"] as Array):
		out.append(_copy_unit(a, u))
	return out


func unit(unit_id: int) -> Dictionary:
	var u := _unit(unit_id)
	if u.is_empty():
		return {}
	var a := _army_of(u)
	_sync(a)
	return _copy_unit(a, u)


func unit_pos(unit_id: int) -> Vector2:
	var u := _unit(unit_id)
	return Vector2.ZERO if u.is_empty() else _upos(_army_of(u), u)


## Army commander + sub-commanders with their attributes, capacity and current load (R§9-11, R§16).
func army_command(army_id: int) -> Dictionary:
	var a := _army(army_id)
	if a.is_empty():
		return {}
	_sync(a)
	var cmd: Dictionary = (a["commander"] as Dictionary).duplicate(true)
	cmd["men"] = _men_of(a)
	cmd["load"] = snappedf(float(cmd["men"]) / maxf(1.0, float(cmd["capacity"])), 0.01)
	var subs: Array = []
	for s: Dictionary in (a["subs"] as Array):
		var c := s.duplicate(true)
		var men := 0
		var names: Array = []
		for u: Dictionary in (a["units"] as Array):
			if int(u["cmd"]) == int(s["id"]):
				men += int(u["men"])
				names.append(String(u["name"]))
		c["men"] = men
		c["units"] = names
		c["load"] = snappedf(float(men) / maxf(1.0, float(s["capacity"])), 0.01)
		subs.append(c)
	return {"commander": cmd, "subs": subs}


## Splits `n` men off a unit into a new piece (R§4). The new unit is created next to its parent and
## inherits its order. Returns the new unit id, or 0 when the split is not allowed.
func split_unit(unit_id: int, n: int) -> int:
	var u := _unit(unit_id)
	if u.is_empty() or int(u["eng"]) != 0:
		return 0
	var a := _army_of(u)
	_sync(a)
	var min_n := WarUnits.MIN_UNIT
	if n < min_n or int(u["men"]) - n < min_n:
		return 0
	var base := String(u["base"])
	var letters := 0
	for o: Dictionary in (a["units"] as Array):
		if String(o["base"]) == base:
			letters += 1
	if letters == 1 and not String(u["name"]).ends_with(" A"):
		u["name"] = "%s A" % base
	var frac := float(n) / float(u["men"])
	var nu := (u as Dictionary).duplicate(true)
	nu["id"] = _uid()
	nu["men"] = n
	nu["max_men"] = maxi(n, int(round(float(u["max_men"]) * frac)))
	u["men"] = int(u["men"]) - n
	u["max_men"] = maxi(int(u["men"]), int(u["max_men"]) - int(nu["max_men"]))
	nu["name"] = "%s %s" % [base, String.chr(65 + mini(letters, 25))]
	nu["cap"] = 0
	(a["units"] as Array).append(nu)
	_recount(a)
	_uidx_dirty = true
	return int(nu["id"])


## Merges unit b into unit a (R§4): same army, same kind, both close together and free of combat.
## The result keeps a's id and commander; men, quality, morale and fatigue are averaged by men.
func merge_units(a_id: int, b_id: int) -> bool:
	if a_id == b_id:
		return false
	var ua := _unit(a_id)
	var ub := _unit(b_id)
	if ua.is_empty() or ub.is_empty() or int(ua["army"]) != int(ub["army"]) or String(ua["kind"]) != String(ub["kind"]):
		return false
	if int(ua["eng"]) != 0 or int(ub["eng"]) != 0:
		return false
	var a := _army_of(ua)
	_sync(a)
	var pa := _upos(a, ua)
	var pb := _upos(a, ub)
	if pa.distance_to(pb) > MERGE_R:
		return false
	var ma := float(ua["men"])
	var mb := float(ub["men"])
	var t := ma + mb
	ua["quality"] = snappedf((float(ua["quality"]) * ma + float(ub["quality"]) * mb) / t, 0.01)
	ua["morale"] = (float(ua["morale"]) * ma + float(ub["morale"]) * mb) / t
	ua["fatigue"] = (float(ua["fatigue"]) * ma + float(ub["fatigue"]) * mb) / t
	ua["men"] = int(ua["men"]) + int(ub["men"])
	ua["max_men"] = int(ua["max_men"]) + int(ub["max_men"])
	ua["name"] = String(ua["base"]) if not _has_sibling(a, ua, ub) else ua["name"]
	var both_det := bool(ua["detached"]) and bool(ub["detached"])
	if both_det:
		var mid := (pa * ma + pb * mb) / t
		ua["x"] = mid.x
		ua["y"] = mid.y
	elif bool(ua["detached"]) or bool(ub["detached"]):
		ua["detached"] = false   # rejoins the army column
		ua["order"] = {"behavior": "hold", "since": _hours}
		ua["state"] = "idle"
	(a["units"] as Array).erase(ub)
	_recount(a)
	_uidx_dirty = true
	return true


func _has_sibling(a: Dictionary, keep: Dictionary, gone: Dictionary) -> bool:
	for o: Dictionary in (a["units"] as Array):
		if o != keep and o != gone and String(o["base"]) == String(keep["base"]):
			return true
	return false


## Detach (R§4): make a unit an independent piece, or first split `n` men off it (a cavalry detachment,
## forty archers, a scout team). Returns the id of the detached piece (0 on failure).
func detach(unit_id: int, n := 0) -> int:
	var id := unit_id
	if n > 0:
		id = split_unit(unit_id, n)
		if id == 0:
			return 0
		var nu := _unit(id)
		nu["name"] = "%s Detachment" % String(nu["base"])
	var u := _unit(id)
	if u.is_empty() or int(u["eng"]) != 0:
		return 0
	var a := _army_of(u)
	if not bool(u["detached"]):
		var p := army_pos(a)
		u["detached"] = true
		u["x"] = p.x
		u["y"] = p.y
		_recount(a)
	return id


## Rejoin a detached piece with its army (must be close to it).
func attach(unit_id: int) -> bool:
	var u := _unit(unit_id)
	if u.is_empty() or not bool(u["detached"]) or int(u["eng"]) != 0:
		return false
	var a := _army_of(u)
	if _upos(a, u).distance_to(army_pos(a)) > MERGE_R:
		return false
	u["detached"] = false
	u["order"] = {"behavior": "hold", "since": _hours}
	u["state"] = "idle"
	_recount(a)
	return true


func set_army_owner(army_id: int, owner: String) -> void:
	var a := _army(army_id)
	for u: Dictionary in ([] if a.is_empty() else a["units"] as Array):
		u["owner"] = owner


# --- command authority (R§12-15) --------------------------------------------------------

func set_player_rank(rank_id: String) -> void:
	_pcmd["rank"] = rank_id


func player_rank() -> String:
	return String(_pcmd["rank"])


func rank_capacity() -> int:
	return Military.command_size(String(_pcmd["rank"]))


## The rank grants command over troops the kingdom assigns to you: fills the rank's capacity with whole
## units of the player's faction (kingdom-owned), and releases whatever was assigned before.
func grant_rank_command(rank_id: String) -> void:
	set_player_rank(rank_id)
	var cap := rank_capacity()
	for a: Dictionary in _armies:
		for u: Dictionary in (a["units"] as Array):
			if String(u["assigned"]) == PLAYER:
				u["assigned"] = ""
	if cap <= 1:
		return
	var used := 0
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		for u: Dictionary in (a["units"] as Array):
			if String(u["owner"]) == "kingdom" and used + int(u["men"]) <= cap:
				u["assigned"] = PLAYER
				used += int(u["men"])


## A superior assigns a unit to the player's command (may exceed capacity: then the player is overloaded).
func assign_command(unit_id: int, to := PLAYER) -> bool:
	var u := _unit(unit_id)
	if u.is_empty():
		return false
	u["assigned"] = to
	return true


## The king puts you in charge of a war (R§14): temporary authority over these armies, then it lapses.
func appoint_command(army_ids: Array, days := 30) -> void:
	for id in army_ids:
		(_pcmd["appointed"] as Dictionary)[str(int(id))] = _day + days


func can_command(unit_id: int) -> Dictionary:
	var u := _unit(unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "There is no such unit.", "source": ""}
	var a := _army_of(u)
	if a["faction"] != PLAYER:
		return {"ok": false, "reason": "That force does not answer to you.", "source": ""}
	if String(u["owner"]) == "personal":
		return {"ok": true, "reason": "", "source": "personal"}
	var appo: Dictionary = _pcmd["appointed"]
	if appo.has(str(int(a["id"]))) and int(appo[str(int(a["id"]))]) > _day:
		return {"ok": true, "reason": "", "source": "appointed"}
	if String(u["assigned"]) == PLAYER and rank_capacity() > 1:
		return {"ok": true, "reason": "", "source": "rank"}
	var rk: Dictionary = Military.rank(String(_pcmd["rank"]))
	var who := String(_cmd_of(a, u)["name"])
	return {"ok": false, "source": "", "reason": "%s's troops do not belong to your command. As a %s you can only request assistance." %
		[who, String(rk.get("title", "soldier"))]}


## What the player can direct right now: {rank, capacity, men, units, load, appointed, personal}.
func command_scope() -> Dictionary:
	var ids: Array = []
	var men := 0
	var personal := 0
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		for u: Dictionary in (a["units"] as Array):
			var c := can_command(int(u["id"]))
			if bool(c["ok"]):
				ids.append(int(u["id"]))
				men += int(u["men"])
				if c["source"] == "personal":
					personal += int(u["men"])
	var cap := _player_capacity()
	return {"rank": String(_pcmd["rank"]), "rank_title": String((Military.rank(String(_pcmd["rank"]))).get("title", "")),
		"capacity": cap, "men": men, "units": ids, "personal_men": personal,
		"overload": snappedf(WarUnits.overload(men, cap), 0.01), "appointed": (_pcmd["appointed"] as Dictionary).duplicate()}


func _player_capacity() -> int:
	var cap := maxi(PLAYER_BASE_CAP, rank_capacity())
	for k: String in (_pcmd["appointed"] as Dictionary):
		if int((_pcmd["appointed"] as Dictionary)[k]) > _day:
			cap = maxi(cap, APPOINTED_CAP)
	return cap


## R§13: you cannot order a captain's troops, but you can ask. The superior decides, deterministically,
## from his personality, the risk of the request and your rank. A granted request goes out by courier.
func request_assistance(unit_id: int, order: Dictionary) -> Dictionary:
	var u := _unit(unit_id)
	if u.is_empty():
		return {"ok": false, "decision": "refused", "by": "", "text": "There is no such unit.", "courier": {}}
	var a := _army_of(u)
	if a["faction"] != PLAYER:
		return {"ok": false, "decision": "refused", "by": "", "text": "That force does not answer to you.", "courier": {}}
	if bool(can_command(unit_id)["ok"]):
		var direct := order_unit(unit_id, order)
		return {"ok": bool(direct["ok"]), "decision": "own", "by": "", "text": "It is your own command.", "courier": direct.get("courier", {})}
	var sup: Dictionary = a["commander"]
	var pers := String(sup["personality"])
	var beh := String(order.get("behavior", "advance"))
	var offensive := beh in ["advance", "charge", "intercept", "flank", "harass"]
	var passive := beh in ["hold", "defend", "screen", "escort", "follow", "retreat", "withdraw_fighting", "avoid", "attack_if_attacked"]
	var p := 0.5 + 0.03 * float(Military.rank_index(String(_pcmd["rank"])) - 6)
	match pers:
		"loyal":
			p += 0.3
		"cautious":
			p += 0.25 if passive else -0.3
		"aggressive":
			p += 0.25 if offensive else -0.25
		"stubborn":
			p -= 0.3
		"independent":
			p -= 0.25 if String((u["order"] as Dictionary).get("behavior", "")) != beh else 0.0
		"ambitious":
			p += 0.2 if offensive else -0.1
	if int(u["eng"]) != 0 and passive == false:
		p -= 0.2
	var roll := _rng("assist", unit_id * 31 + int(_orders_log.size())).randf()
	var granted := roll < clampf(p, 0.05, 0.95)
	var res := {"ok": granted, "decision": "granted" if granted else "refused", "by": String(sup["name"]), "courier": {}, "denied": true}
	if granted:
		res["text"] = "%s agrees to your request and passes the word to %s." % [sup["name"], u["name"]]
		res["courier"] = _send_unit_order(a, u, order, true)
	else:
		res["text"] = "%s refuses: \"%s\"" % [sup["name"], _refusal(pers)]
	return res


static func _refusal(pers: String) -> String:
	match pers:
		"cautious":
			return "Not until the scouts confirm it. I will not risk my men on a guess."
		"aggressive":
			return "You would have me give ground? No."
		"stubborn":
			return "My orders stand. I take them from the marshal, not from you."
		"independent":
			return "I know this ground better than you do."
		"ambitious":
			return "There is no glory in that. Ask someone else."
	return "I cannot spare them, my lord."


# --- orders by courier (R§5, R§21-22) -----------------------------------------------------

## How far the player's span of control is stretched (R§11, R§17): the men in the pieces they are directly
## ordering (this order included) against their capacity, or the men assigned to them against their rank.
func _load_over(extra_uid := 0) -> float:
	var seen := {}
	for e: Dictionary in _orders_log:
		if int(e["sent_hour"]) >= _hours - 12:
			seen[int(e["unit_id"])] = true
	if extra_uid != 0:
		seen[extra_uid] = true
	var direct := 0
	var assigned := 0
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		for u: Dictionary in (a["units"] as Array):
			if seen.has(int(u["id"])):
				direct += int(u["men"])
			if String(u["assigned"]) == PLAYER:
				assigned += int(u["men"])
	return maxf(WarUnits.overload(direct, _player_capacity()), WarUnits.overload(assigned, maxi(PLAYER_BASE_CAP, rank_capacity())))


func _order_delay_mult(extra_uid := 0) -> float:
	var seen := {}
	for e: Dictionary in _orders_log:
		if int(e["sent_hour"]) >= _hours - 6:
			seen[int(e["unit_id"])] = true
	var micro := maxf(0.0, float(seen.size() - 12) / 12.0)
	return clampf(1.0 + 1.2 * _load_over(extra_uid) + 0.5 * micro, 1.0, 3.0)


## Order a unit (a "piece") to do something: {behavior, x, y | node, target_unit, formation?}.
## Returns {ok, denied, reason, courier}. Denied when the unit is not in the player's command (R§13).
func order_unit(unit_id: int, order: Dictionary) -> Dictionary:
	_ensure()
	var c := can_command(unit_id)
	if not bool(c["ok"]):
		return {"ok": false, "denied": true, "reason": c["reason"], "courier": {}}
	var u := _unit(unit_id)
	var a := _army_of(u)
	var o := _clean_order(order)
	if o.is_empty():
		return {"ok": false, "denied": false, "reason": "That order is incomplete.", "courier": {}}
	return {"ok": true, "denied": false, "reason": "", "courier": _send_unit_order(a, u, o, false)}


func order_units(ids: Array, order: Dictionary) -> Array:
	var out: Array = []
	for id in ids:
		out.append(order_unit(int(id), order))
	return out


func _clean_order(order: Dictionary) -> Dictionary:
	var beh := String(order.get("behavior", ""))
	if not WarUnits.BEHAVIOURS.has(beh):
		return {}
	var o := {"behavior": beh}
	var needs := String((WarUnits.behaviour(beh) as Dictionary)["needs"])
	if order.has("node"):
		var np := node_pos(int(order["node"]))
		o["x"] = np.x
		o["y"] = np.y
		o["node"] = int(order["node"])
	elif order.has("x") and order.has("y"):
		o["x"] = clampf(float(order["x"]), -MAP_HALF, MAP_HALF)
		o["y"] = clampf(float(order["y"]), -MAP_HALF, MAP_HALF)
	if order.has("target_unit"):
		o["target_unit"] = int(order["target_unit"])
	if needs == "point" and not o.has("x") and beh not in ["retreat", "withdraw_fighting"]:
		return {}
	if needs == "unit" and not o.has("target_unit"):
		return {}
	return o


func _send_unit_order(a: Dictionary, u: Dictionary, order: Dictionary, requested: bool) -> Dictionary:
	var upos := _upos(a, u)
	var onode := nearest_node(upos)
	var p := path(_player_node, onode)
	var dist := 0.0
	var legs: Array = []
	if p.size() >= 2:
		var acc := 0.0
		for i in range(1, p.size()):
			acc += _elen(p[i - 1], p[i])
			legs.append([int(p[i]), acc / COURIER_SPEED])
		dist = acc
	dist += node_pos(onode).distance_to(upos) * 1.15
	var mult := _order_delay_mult(int(u["id"]))
	var hours := maxi(1, int(ceil(dist / COURIER_SPEED * mult)))
	var c := {"id": _next_id, "army_id": int(a["id"]), "unit_id": int(u["id"]), "order": order.duplicate(true),
		"sent_hour": _hours, "sent_day": _day, "eta_hours": hours, "elapsed": 0, "legs": legs, "checked": 0, "intercepted": false,
		"mult": snappedf(mult, 0.01), "over": snappedf(_load_over(int(u["id"])) if a["faction"] == PLAYER else 0.0, 0.01)}
	_next_id += 1
	_couriers.append(c)
	_orders_log.append({"id": int(c["id"]), "unit_id": int(u["id"]), "army_id": int(a["id"]), "name": String(u["name"]),
		"behavior": String(order["behavior"]), "x": float(order.get("x", 0.0)), "y": float(order.get("y", 0.0)), "has_pos": order.has("x"),
		"sent_hour": _hours, "eta_hour": _hours + hours, "truth": "riding", "ack_hour": -1, "requested": requested, "mult": snappedf(mult, 0.01)})
	if _orders_log.size() > ORDERS_KEEP:
		_orders_log.pop_front()
	return c.duplicate(true)


func _log_order(courier_id: int, truth: String, ack_in := -1) -> void:
	for e: Dictionary in _orders_log:
		if int(e["id"]) == courier_id:
			e["truth"] = truth
			if ack_in >= 0:
				e["ack_hour"] = _hours + ack_in
			return


## The player's order list with only what they can know: riding, awaiting word, acknowledged, or silence.
func orders() -> Array:
	var out: Array = []
	for e: Dictionary in _orders_log:
		var eta_left := maxi(0, int(e["eta_hour"]) - _hours)
		var ret := maxi(1, int(e["eta_hour"]) - int(e["sent_hour"]))
		var state := "riding"
		var text := "Courier riding, about %d h" % eta_left
		if String(e["truth"]) == "delivered" and int(e["ack_hour"]) <= _hours:
			state = "acked"
			text = "Acknowledged"
		elif _hours >= int(e["eta_hour"]):
			state = "awaiting"
			text = "Should have arrived, awaiting word"
			if _hours >= int(e["eta_hour"]) + ret + 6 and String(e["truth"]) != "delivered":
				state = "silent"
				text = "No word. The courier may be lost"
		var bh: Dictionary = WarUnits.behaviour(String(e["behavior"]))
		out.append({"id": int(e["id"]), "unit_id": int(e["unit_id"]), "army_id": int(e["army_id"]), "name": e["name"], "behavior": e["behavior"],
			"behavior_name": bh["name"], "eta_left": eta_left, "state": state, "text": text, "requested": bool(e["requested"]),
			"pos": Vector2(float(e["x"]), float(e["y"])) if bool(e["has_pos"]) else Vector2.INF, "sent_hour": int(e["sent_hour"]), "mult": e["mult"]})
	return out


## What a move would involve: distance, march time, ground, courier time, risk (the reference's "Move Here" card).
func estimate_order(unit_id: int, dest: Vector2) -> Dictionary:
	var u := _unit(unit_id)
	if u.is_empty():
		return {}
	var a := _army_of(u)
	var from := _upos(a, u)
	var dist := from.distance_to(dest)
	var slow := 1.0
	var worst := "plain"
	var worst_speed := 9.0
	for i in 6:
		var t := terrain_at(from.lerp(dest, float(i) / 5.0))
		if float(t["speed"]) < worst_speed:
			worst_speed = float(t["speed"])
			worst = String(t["id"])
		slow += 1.0 / float(t["speed"])
	var avg_speed := 6.0 / (slow - 1.0)
	var march := dist / (ARMY_SPEED * float((WarUnits.kind(String(u["kind"])) as Dictionary)["speed"]) * avg_speed)
	var dt := terrain_at(dest)
	var risk := "Low"
	var foe_near := false
	for s: Dictionary in _sight.values():
		if Vector2(float(s["x"]), float(s["y"])).distance_to(dest) < 500.0:
			foe_near = true
	if foe_near:
		risk = "Enemy reported nearby"
	elif float(dt["ambush"]) >= 0.2:
		risk = "Possible ambush"
	elif float(dt["ambush"]) > 0.0:
		risk = "Some risk of ambush"
	var cdist := node_pos(nearest_node(from)).distance_to(from) + 0.0
	var p := path(_player_node, nearest_node(from))
	if p.size() >= 2:
		cdist += path_length(p)
	return {"distance": dist, "hours": march, "terrain": String(dt["name"]), "terrain_id": String(dt["id"]), "slowest": String((terrain(worst))["name"]),
		"visibility": "Low" if float(dt["vision"]) < 0.7 else ("High" if float(dt["vision"]) > 1.1 else "Normal"), "risk": risk,
		"courier_hours": maxi(1, int(ceil(cdist * _order_delay_mult(unit_id) / COURIER_SPEED)))}


func terrain(id: String) -> Dictionary:
	return _terr_dict(id)


## R§22: a rider may be caught near enemy pieces, lose the way on a long ride, or arrive late.
func _unit_courier_fate(c: Dictionary) -> String:
	if bool(c.get("late", false)):
		return "ok"
	var u := _unit(int(c["unit_id"]))
	if u.is_empty():
		return "lost"
	var p := _upos(_army_of(u), u)
	var chance := 0.0
	for o: Dictionary in _armies:
		if o["faction"] != PLAYER and army_pos(o).distance_to(p) < 350.0:
			chance += 0.2
			break
	var eta := int(c["eta_hours"])
	if eta > 6:
		chance += minf(0.15, 0.03 + 0.005 * float(eta - 6))
	var r := _rng("courier_fate", int(c["id"]))
	var roll := r.randf()
	if roll < chance:
		return "lost"
	if roll < chance + 0.07:
		return "late"
	return "ok"


func _deliver_unit(c: Dictionary, out: Array) -> void:
	var u := _unit(int(c["unit_id"]))
	if u.is_empty():
		_log_order(int(c["id"]), "lost")
		return
	var a := _army_of(u)
	var res := _apply_unit_order(a, u, c["order"] as Dictionary, int(c["id"]), float(c.get("over", 0.0)))
	_log_order(int(c["id"]), "delivered", maxi(1, int(c["eta_hours"])))
	for m: String in res:
		out.append(m)


func _apply_unit_order(a: Dictionary, u: Dictionary, order: Dictionary, salt: int, over := 0.0) -> Array:
	var msgs: Array = []
	var o := order.duplicate(true)
	var r := _rng("unit_order", int(u["id"]) * 13 + salt)
	var cmd := _cmd_of(a, u)
	var beh := String(o["behavior"])
	# R§11: an overstretched player sends muddled orders (the load is what it was when the order left).
	if over > 0.0 and o.has("x") and _hash_f("garble", int(u["id"]) * 97 + salt * 31) < clampf(0.3 * over, 0.0, 0.5):
		var ang := r.randf() * TAU
		o["x"] = clampf(float(o["x"]) + cos(ang) * r.randf_range(150.0, 400.0), -MAP_HALF, MAP_HALF)
		o["y"] = clampf(float(o["y"]) + sin(ang) * r.randf_range(150.0, 400.0), -MAP_HALF, MAP_HALF)
		o["garbled"] = true
		msgs.append("%s misread the confused orders and marched to the wrong ground." % u["name"])
	# scouts go where they are sent: their job is to look, not to win
	var sit := {"foe_ratio": 0.0 if String(u["kind"]) in ["scout", "medical", "engineer"] else _foe_ratio(a, u), "morale": float(u["morale"])}
	var rx := WarUnits.personality_reaction(String(cmd["personality"]), beh, sit, r)
	if String(rx["behavior"]) != beh:
		beh = String(rx["behavior"])
		o["behavior"] = beh
		if not (WarUnits.behaviour(beh) as Dictionary)["moves"]:
			o.erase("x")
			o.erase("y")
		elif not o.has("x"):
			var p0 := _upos(a, u)
			o["x"] = p0.x
			o["y"] = p0.y
		var note := "%s %s." % [cmd["name"], rx["note"]]
		msgs.append(note)
		if a["faction"] == PLAYER:
			_dispatch(a, note)
	if not bool(u["detached"]):
		var p1 := army_pos(a)
		u["detached"] = true
		u["x"] = p1.x
		u["y"] = p1.y
		_recount(a)
	if beh in ["retreat", "withdraw_fighting"] and not o.has("x"):
		var hp := _home_pos(a)
		o["x"] = hp.x
		o["y"] = hp.y
	if beh == "flank" and o.has("x"):
		var from := Vector2(float(u["x"]), float(u["y"]))
		var to := Vector2(float(o["x"]), float(o["y"]))
		var dirv := (to - from)
		if dirv.length() > 1.0:
			var perp := dirv.orthogonal().normalized() * (1.0 if r.randf() < 0.5 else -1.0)
			var w := from.lerp(to, 0.55) + perp * clampf(dirv.length() * 0.35, 120.0, 450.0)
			o["wx"] = w.x
			o["wy"] = w.y
	if not bool((WarUnits.behaviour(beh) as Dictionary)["moves"]) and o.has("x"):
		var here := Vector2(float(u["x"]), float(u["y"]))
		if here.distance_to(Vector2(float(o["x"]), float(o["y"]))) > 30.0:
			o["then"] = beh          # go there first, then hold / lie in wait / fight only if attacked
			o["behavior"] = "march"
			beh = "march"
	o["since"] = _hours
	u["order"] = o
	if int(u["eng"]) != 0 and beh in ["retreat", "withdraw_fighting"]:
		_disengage(u, beh == "withdraw_fighting")
	u["state"] = "moving" if (WarUnits.behaviour(beh) as Dictionary)["moves"] else "idle"
	return msgs


func _foe_ratio(a: Dictionary, u: Dictionary) -> float:
	var p := _upos(a, u)
	var own := float(a["strength"]) if not bool(u["detached"]) else float(u["men"])
	var foe := 0.0
	if a["faction"] == PLAYER:
		for s: Dictionary in _sight.values():
			if Vector2(float(s["x"]), float(s["y"])).distance_to(p) < 700.0:
				foe += (float(s["min"]) + float(s["max"])) * 0.5
	else:
		for o: Dictionary in _armies:
			if o["faction"] == PLAYER and army_pos(o).distance_to(p) < 700.0:
				foe += float(o["strength"])
	return foe / maxf(own, 1.0)


func _home_pos(a: Dictionary) -> Vector2:
	if a["faction"] == PLAYER:
		var n := _nearest_depot_node(a)
		return node_pos(n if n >= 0 else _hq)
	return node_pos(int(a["prev_node"]))


# --- movement of detached pieces (R§6) ---------------------------------------------------

func _unit_speed(a: Dictionary, u: Dictionary, terr: Dictionary, beh: Dictionary) -> float:
	var s := ARMY_SPEED * float((WarUnits.kind(String(u["kind"])) as Dictionary)["speed"]) * float(beh["speed"]) * float(terr["speed"])
	s *= 1.0 - 0.3 * float(u["fatigue"])
	if _season == "winter":
		s *= 0.8
	if float(a["supply"]) <= 0.0:
		s *= 0.8
	return s


## Walks toward `tgt`; returns the distance left. Tires the unit.
func _walk(a: Dictionary, u: Dictionary, tgt: Vector2, beh: Dictionary, stop: float) -> float:
	var p := Vector2(float(u["x"]), float(u["y"]))
	var d := tgt - p
	var dist := d.length()
	if dist <= stop:
		return dist
	var mid := p + d / dist * minf(dist, 48.0)
	var t := terrain_at(mid)
	var step := minf(_unit_speed(a, u, t, beh), dist - stop)
	p += d / dist * step
	u["x"] = p.x
	u["y"] = p.y
	u["fatigue"] = clampf(float(u["fatigue"]) + step / ARMY_SPEED * 0.035 * float(t["fatigue"]) * float(beh["fatigue"]), 0.0, 1.0)
	u["state"] = "retreating" if String((u["order"] as Dictionary)["behavior"]) in ["retreat", "withdraw_fighting"] else "moving"
	return dist - step


func _piece_pos(uid: int, for_player: bool) -> Variant:
	var t := _unit(uid)
	if t.is_empty():
		return null
	var ta := _army_of(t)
	var truth := _upos(ta, t)
	if not for_player or ta["faction"] == PLAYER:
		return truth
	var key := "u%d" % uid if bool(t["detached"]) else "a%d" % int(ta["id"])
	if _sight.has(key):
		var s: Dictionary = _sight[key]
		return Vector2(float(s["x"]), float(s["y"]))
	return null


func _field_move(a: Dictionary, u: Dictionary) -> void:
	if int(u["eng"]) != 0:
		return
	var o: Dictionary = u["order"]
	var bname := String(o["behavior"])
	if bool(o.get("arrived", false)) and bname in ["advance", "charge", "flank", "retreat", "withdraw_fighting", "avoid", "intercept", "march"]:
		bname = String(o.get("then", "hold"))
		u["order"] = {"behavior": bname, "since": _hours, "arrived": true}
		if bool(o.get("garbled", false)):
			(u["order"] as Dictionary)["garbled"] = true   # where it ended up stays on the record
		u["state"] = "idle"
		o = u["order"]
	var beh: Dictionary = WarUnits.behaviour(bname)
	var p := Vector2(float(u["x"]), float(u["y"]))
	var moved := false
	var dest := Vector2.INF
	var stop := 12.0
	var for_player: bool = a["faction"] == PLAYER
	if bool(beh["moves"]):
		if bname in ["intercept", "follow", "escort"]:
			var tp: Variant = _piece_pos(int(o.get("target_unit", 0)), for_player)
			if tp is Vector2:
				dest = tp
			elif o.has("x"):
				dest = Vector2(float(o["x"]), float(o["y"]))
			stop = 70.0 if bname != "intercept" else 30.0
		elif bname == "avoid":
			var away := _flee_dir(a, u, p)
			if away != Vector2.ZERO:
				dest = p + away * 500.0
		elif o.has("wx"):
			dest = Vector2(float(o["wx"]), float(o["wy"]))
		elif o.has("x"):
			dest = Vector2(float(o["x"]), float(o["y"]))
		if bname == "harass" and o.has("x"):
			var foe_near := _nearest_foe(a, p, HARASS_R)
			if foe_near != Vector2.INF:
				_skirmish(a, u, foe_near)
				dest = p + (p - foe_near).normalized() * 120.0
				stop = 0.0
		if dest != Vector2.INF:
			var left := _walk(a, u, dest, beh, stop)
			moved = left < p.distance_to(dest) - 0.5
			if left <= stop + 0.5:
				if o.has("wx"):
					o.erase("wx")
					o.erase("wy")
				elif bname in ["advance", "charge", "flank", "retreat", "withdraw_fighting", "avoid", "intercept", "march"]:
					o["arrived"] = true   # turns into "hold" (or its "then") next hour, after contact has had its chance
					u["state"] = "idle"
				elif bname == "capture":
					_capture_tick(a, u)
				elif bname in ["follow", "escort", "screen", "defend", "harass"]:
					u["state"] = "idle"
	if not moved:
		var rest := 0.02 if bname in ["hold", "ambush", "attack_if_attacked"] or String(u["state"]) == "idle" else 0.01
		u["fatigue"] = maxf(0.0, float(u["fatigue"]) - rest)
		if String(u["state"]) == "moving" or String(u["state"]) == "retreating":
			u["state"] = "idle"


func _flee_dir(a: Dictionary, u: Dictionary, p: Vector2) -> Vector2:
	var foe := _nearest_foe(a, p, 650.0)
	return Vector2.ZERO if foe == Vector2.INF else (p - foe).normalized()


## Position of the nearest hostile piece within `radius` (what the piece's own side can see: player pieces
## only react to sighted enemies).
func _nearest_foe(a: Dictionary, p: Vector2, radius: float) -> Vector2:
	var best := Vector2.INF
	var bd := radius
	if a["faction"] == PLAYER:
		for s: Dictionary in _sight.values():
			if int(s["hour"]) < _hours - 2:
				continue
			var sp := Vector2(float(s["x"]), float(s["y"]))
			if sp.distance_to(p) < bd:
				bd = sp.distance_to(p)
				best = sp
	else:
		for o: Dictionary in _armies:
			if o["faction"] == PLAYER:
				for u: Dictionary in (o["units"] as Array):
					var up := _upos(o, u)
					if up.distance_to(p) < bd:
						bd = up.distance_to(p)
						best = up
	return best


## Harass (R§5): a light exchange of missiles without committing to an engagement.
func _skirmish(a: Dictionary, u: Dictionary, foe_pos: Vector2) -> void:
	var k: Dictionary = WarUnits.kind(String(u["kind"]))
	if not (bool(k["ranged"]) or bool(k["mounted"])):
		return
	var r := _rng("skirmish", int(u["id"]))
	var loss_f := 0.004 * (float(u["men"]) / 60.0) * (0.7 + 0.6 * float(u["quality"]))
	for o: Dictionary in _armies:
		if (o["faction"] == PLAYER) == (a["faction"] == PLAYER):
			continue
		if army_pos(o).distance_to(foe_pos) < 60.0:
			for ou: Dictionary in (o["units"] as Array):
				if not bool(ou["detached"]) and int(ou["men"]) > 0:
					var lost := mini(int(ou["men"]) - 1, int(round(float(ou["men"]) * loss_f * (0.8 + 0.4 * r.randf()))))
					ou["men"] = int(ou["men"]) - maxi(0, lost)
					ou["morale"] = clampf(float(ou["morale"]) - 0.01, 0.0, 1.0)
			_recalc(o)
		for ou2: Dictionary in (o["units"] as Array):
			if bool(ou2["detached"]) and Vector2(float(ou2["x"]), float(ou2["y"])).distance_to(foe_pos) < 60.0:
				var lost2 := mini(int(ou2["men"]) - 1, int(round(float(ou2["men"]) * loss_f * (0.8 + 0.4 * r.randf()))))
				ou2["men"] = int(ou2["men"]) - maxi(0, lost2)
				ou2["morale"] = clampf(float(ou2["morale"]) - 0.01, 0.0, 1.0)


func _capture_tick(a: Dictionary, u: Dictionary) -> void:
	var p := Vector2(float(u["x"]), float(u["y"]))
	var n := nearest_node(p)
	if node_pos(n).distance_to(p) > 260.0:
		return
	u["state"] = "capturing"
	u["cap"] = int(u["cap"]) + 1
	if int(u["cap"]) >= 3 and String(_captured.get(str(n), "")) != String(a["faction"]):
		_captured[str(n)] = String(a["faction"])
		if a["faction"] == PLAYER:
			_dispatch(a, "%s has taken %s." % [u["name"], _nname(n)])
		u["order"] = {"behavior": "hold", "since": _hours, "arrived": true}
		u["state"] = "idle"
		u["cap"] = 0


func captured() -> Dictionary:
	return _captured.duplicate()


# --- contact and engagements (R§7-8) -----------------------------------------------------

func _stance(a: Dictionary, u: Dictionary) -> String:
	if not bool(u["detached"]):
		var k := String((a["order"] as Dictionary).get("kind", "hold"))
		return "seek" if (k in ["attack", "raid"] and not (a["route"] as Array).is_empty()) else "accept"
	return String((WarUnits.behaviour(String((u["order"] as Dictionary)["behavior"])) as Dictionary)["engage"])


func _group_units(a: Dictionary, det: bool) -> Array:
	var out: Array = []
	for u: Dictionary in (a["units"] as Array):
		if bool(u["detached"]) == det and int(u["eng"]) == 0 and int(u["men"]) > 0:
			out.append(u)
	return out


func _contacts(out: Array) -> void:
	var any := false
	for a: Dictionary in _armies:
		if int(a["ndet"]) > 0:
			any = true
			break
	if not any:
		return
	# entities: attached groups (at their army's position) and detached pieces
	var ents: Array = []
	for a: Dictionary in _armies:
		var det: int = int(a["ndet"])
		var total: int = (a["units"] as Array).size()
		if det < total and a["state"] != "engaged":
			ents.append({"a": a, "det": false, "pos": army_pos(a), "u": null})
		if det > 0:
			for u: Dictionary in (a["units"] as Array):
				if bool(u["detached"]) and int(u["eng"]) == 0 and int(u["men"]) > 0:
					ents.append({"a": a, "det": true, "pos": Vector2(float(u["x"]), float(u["y"])), "u": u})
	var n := ents.size()
	var epos := PackedVector2Array()
	var eside := PackedByteArray()
	epos.resize(n)
	eside.resize(n)
	for i in n:
		epos[i] = (ents[i] as Dictionary)["pos"]
		eside[i] = 1 if ((ents[i] as Dictionary)["a"] as Dictionary)["faction"] == PLAYER else 0
	var claimed := {}
	var amb_sq := AMBUSH_R * AMBUSH_R
	for i in n:
		var e: Dictionary = ents[i]
		if not bool(e["det"]):
			continue
		var u: Dictionary = e["u"]
		if int(u["eng"]) != 0:
			continue
		var ea: Dictionary = e["a"]
		for j in n:
			if eside[j] == eside[i] or epos[i].distance_squared_to(epos[j]) > amb_sq:
				continue
			var f: Dictionary = ents[j]
			var fa: Dictionary = f["a"]
			var d := epos[i].distance_to(epos[j])
			var ambusher := String((u["order"] as Dictionary)["behavior"]) == "ambush" and d <= AMBUSH_R
			if d > CONTACT_R and not ambusher:
				continue
			var fu: Variant = f["u"]
			if fu != null and int((fu as Dictionary)["eng"]) != 0:
				continue
			if fu == null and fa["state"] == "engaged":
				continue
			var se := _stance(ea, u)
			var sf := _stance(fa, (fu as Dictionary) if fu != null else {"detached": false})
			var open := false
			var attacker := "e"
			if ambusher:
				open = true
			elif se == "seek" or sf == "seek":
				open = true
				attacker = "e" if se == "seek" else "f"
				# an avoider that is at least as fast slips away
				var loser_stance := sf if attacker == "e" else se
				if loser_stance == "avoid":
					var sp_e := ARMY_SPEED * float((WarUnits.kind(String(u["kind"])) as Dictionary)["speed"])
					var sp_f := ARMY_SPEED * (float((WarUnits.kind(String((fu as Dictionary)["kind"])) as Dictionary)["speed"]) if fu != null else 0.8)
					if (attacker == "e" and sp_f >= sp_e) or (attacker == "f" and sp_e >= sp_f):
						open = false
			if not open:
				continue
			if claimed.has(int(u["id"])) or (fu != null and claimed.has(int((fu as Dictionary)["id"]))):
				continue
			_open_from_contact(e, f, attacker, ambusher, ents, claimed, out)
			break


func _open_from_contact(e: Dictionary, f: Dictionary, attacker: String, ambush: bool, ents: Array, claimed: Dictionary, out: Array) -> void:
	var ea: Dictionary = e["a"]
	var side_e: Array = [e["u"]]
	var side_f: Array = []
	if f["u"] != null:
		side_f.append(f["u"])
	else:
		side_f = _group_units(f["a"], false)
	for g: Dictionary in ents:
		if g == e or g == f:
			continue
		var ga: Dictionary = g["a"]
		var gu: Variant = g["u"]
		if gu != null and int((gu as Dictionary)["eng"]) != 0:
			continue
		if gu == null and ga["state"] == "engaged":
			continue
		var gd := (g["pos"] as Vector2)
		var same_e: bool = (ga["faction"] == PLAYER) == (ea["faction"] == PLAYER)
		var centre: Vector2 = e["pos"] if same_e else f["pos"]
		if gd.distance_to(centre) > JOIN_R:
			continue
		if gu != null:
			if String((gu as Dictionary)["state"]) == "retreating":
				continue
			(side_e if same_e else side_f).append(gu)
		else:
			for gg: Dictionary in _group_units(ga, false):
				(side_e if same_e else side_f).append(gg)
	if side_e.is_empty() or side_f.is_empty():
		return
	for x: Dictionary in side_e + side_f:
		claimed[int(x["id"])] = true
	var pos: Vector2 = ((e["pos"] as Vector2) + (f["pos"] as Vector2)) * 0.5
	var attacker_side := "e" if (attacker == "e" or ambush) else "f"
	var surprise_side := ""
	if ambush:
		surprise_side = "e"
	elif f["u"] != null and String(((f["u"] as Dictionary)["order"] as Dictionary)["behavior"]) == "ambush":
		surprise_side = "f"
	elif attacker_side == "e" and String(((e["u"] as Dictionary)["order"] as Dictionary)["behavior"]) == "flank":
		surprise_side = "e"
	# side "a" is the player's whenever the player is involved, otherwise the initiator's
	var swap: bool = ea["faction"] != PLAYER and f["a"]["faction"] == PLAYER
	var lab := {"e": "b" if swap else "a", "f": "a" if swap else "b"}
	_open_engagement(side_f if swap else side_e, side_e if swap else side_f, String(lab[attacker_side]), pos,
		"" if surprise_side == "" else String(lab[surprise_side]), out)


func _open_engagement(ua: Array, ub: Array, attacker: String, pos: Vector2, surprise: String, out: Array) -> Dictionary:
	var t := terrain_at(pos)
	var id := _uid()
	var men_a := 0
	var men_b := 0
	var ids_a: Array = []
	var ids_b: Array = []
	for u: Dictionary in ua:
		ids_a.append(int(u["id"]))
		men_a += int(u["men"])
		u["eng"] = id
		u["state"] = "engaged"
		_army_of(u)["state"] = "engaged" if not bool(u["detached"]) else _army_of(u)["state"]
	for u2: Dictionary in ub:
		ids_b.append(int(u2["id"]))
		men_b += int(u2["men"])
		u2["eng"] = id
		u2["state"] = "engaged"
		_army_of(u2)["state"] = "engaged" if not bool(u2["detached"]) else _army_of(u2)["state"]
	var a0 := _army_of(ua[0])
	var b0 := _army_of(ub[0])
	var e := {"id": id, "name": "%s Engagement" % _place_name(pos), "x": pos.x, "y": pos.y, "start_hour": _hours, "end_hour": -1,
		"a": ids_a, "b": ids_b, "fa": String(a0["faction"]), "fb": String(b0["faction"]), "attacker": attacker, "surprise": surprise,
		"terrain": String(t["id"]), "rounds": 0, "men0": {"a": men_a, "b": men_b}, "cas": {"a": 0, "b": 0}, "ratio": 0.5,
		"status": "fighting", "outcome": "", "factors": {"a": {}, "b": {}}, "lead": {"a": "", "b": ""}, "control": "commander",
		"press": false, "log": ["Contact at %s." % _place_name(pos)]}
	_engs.append(e)
	var player_side := "a" if _eng_has_player(e, "a") else ("b" if _eng_has_player(e, "b") else "")
	if player_side != "":
		var mine: Array = ua if player_side == "a" else ub
		var pa := _army_of(mine[0])
		_dispatch(pa, "Contact at %s: %s engaged." % [_place_name(pos), (mine[0] as Dictionary)["name"]])
	if out.size() < 8 and player_side != "":
		out.append("Engagement at %s." % _place_name(pos))
	return e


func _eng_has_player(e: Dictionary, side: String) -> bool:
	return String(e["fa" if side == "a" else "fb"]) == PLAYER


func _eng_units(e: Dictionary, side: String) -> Array:
	var out: Array = []
	for id: int in (e[side] as Array):
		var u := _unit(id)
		if not u.is_empty() and int(u["men"]) > 0 and int(u["eng"]) == int(e["id"]):
			out.append(u)
	return out


func _side_env(e: Dictionary, side: String, mine: Array, foes: Array, t: Dictionary) -> Dictionary:
	var best_a: Dictionary = {}
	var best_t := -1
	var sup := 0.0
	var men := 0
	var cx := Vector2.ZERO
	var form := "line"
	var big := -1
	for u: Dictionary in mine:
		var a := _army_of(u)
		var c := _cmd_of(a, u)
		if int(c["tactics"]) > best_t:
			best_t = int(c["tactics"])
			best_a = c
		sup += float(a["supply"]) * float(u["men"])
		men += int(u["men"])
		cx += _upos(a, u) * float(u["men"])
		if int(u["men"]) > big:
			big = int(u["men"])
			form = String(a["formation"])
	var mounted := 0
	var foe_men := 0
	for u: Dictionary in foes:
		foe_men += int(u["men"])
		if bool((WarUnits.kind(String(u["kind"])) as Dictionary)["mounted"]):
			mounted += int(u["men"])
	var over := 0.0
	if not best_a.is_empty():
		var under := 0
		for u: Dictionary in mine:
			if int(_cmd_of(_army_of(u), u)["id"]) == int(best_a["id"]):
				under += int(u["men"])
		over = WarUnits.overload(under, int(best_a["capacity"]))
	var role := "attack" if String(e["attacker"]) == side else "defend"
	var sur := 1.0
	if int(e["rounds"]) < 3 and String(e["surprise"]) != "":
		sur = 1.25 if String(e["surprise"]) == side else 0.85
	return {"terrain": t, "role": role, "weather": _weather, "season": _season, "supply": sup / maxf(1.0, float(men)), "surprise": sur,
		"formation": FORMATIONS.get(form, FORMATIONS["line"]), "leader": best_a, "confusion": over,
		"foe_mounted": float(mounted) / maxf(1.0, float(foe_men)), "high_ground": 0, "centre": cx / maxf(1.0, float(men))}


func _eng_round(e: Dictionary, out: Array) -> void:
	if _tacs.has(int(e["id"])):
		_tac_hour(e, out)
		return
	var ua := _eng_units(e, "a")
	var ub := _eng_units(e, "b")
	if ua.is_empty() or ub.is_empty():
		_end_engagement(e, "b" if ua.is_empty() else "a", "The line was destroyed.", out)
		return
	var pos := Vector2(float(e["x"]), float(e["y"]))
	var t := terrain_at(pos)
	var env_a := _side_env(e, "a", ua, ub, t)
	var env_b := _side_env(e, "b", ub, ua, t)
	var ha := WorldGen.height((env_a["centre"] as Vector2).x, (env_a["centre"] as Vector2).y)
	var hb := WorldGen.height((env_b["centre"] as Vector2).x, (env_b["centre"] as Vector2).y)
	if ha - hb > 6.0:
		env_a["high_ground"] = 1
		env_b["high_ground"] = -1
	elif hb - ha > 6.0:
		env_a["high_ground"] = -1
		env_b["high_ground"] = 1
	if String(e.get("champion_side", "")) == "a":
		env_a["surprise"] = float(env_a["surprise"]) * 1.08
	elif String(e.get("champion_side", "")) == "b":
		env_b["surprise"] = float(env_b["surprise"]) * 1.08
	if bool(e["press"]):
		env_a["surprise"] = float(env_a["surprise"]) * (1.1 if _eng_has_player(e, "a") else 1.0)
		env_b["surprise"] = float(env_b["surprise"]) * (1.1 if _eng_has_player(e, "b") and not _eng_has_player(e, "a") else 1.0)
		e["press"] = false
	var sa := WarUnits.side_power(ua, env_a)
	var sb := WarUnits.side_power(ub, env_b)
	var pa := maxf(float(sa["power"]), 0.001)
	var pb := maxf(float(sb["power"]), 0.001)
	var ratio := pa / (pa + pb)
	e["ratio"] = snappedf(ratio, 0.001)
	e["factors"] = {"a": sa["factors"], "b": sb["factors"]}
	e["lead"] = {"a": String((env_a["leader"] as Dictionary).get("name", "")), "b": String((env_b["leader"] as Dictionary).get("name", ""))}
	var r := _rng("eng", int(e["id"]) * 1000 + int(e["rounds"]))
	var na := 1.0 + (r.randf() - 0.5) * 0.1
	var nb := 1.0 + (r.randf() - 0.5) * 0.1
	var inten := 0.55 if int(e["rounds"]) == 0 else 1.0
	var fa := clampf(0.045 * pow(pb / pa, 0.7) * inten * na, 0.002, 0.2)
	var fb := clampf(0.045 * pow(pa / pb, 0.7) * inten * nb, 0.002, 0.2)
	fa *= 1.0 - minf(0.12, _med_share(ua) * 2.5)
	fb *= 1.0 - minf(0.12, _med_share(ub) * 2.5)
	var la := _apply_losses(ua, fa, ratio)
	var lb := _apply_losses(ub, fb, 1.0 - ratio)
	(e["cas"] as Dictionary)["a"] = int((e["cas"] as Dictionary)["a"]) + la
	(e["cas"] as Dictionary)["b"] = int((e["cas"] as Dictionary)["b"]) + lb
	e["rounds"] = int(e["rounds"]) + 1
	for u: Dictionary in ua + ub:
		u["fatigue"] = clampf(float(u["fatigue"]) + 0.05, 0.0, 1.0)
	e["status"] = "holding" if absf(ratio - 0.5) < 0.1 else "fighting"
	# withdrawals ordered earlier take effect at the start of a round
	for u: Dictionary in ua + ub:
		var bn := String((u["order"] as Dictionary)["behavior"])
		if bn in ["retreat", "withdraw_fighting"] and int(u["eng"]) == int(e["id"]):
			_disengage(u, bn == "withdraw_fighting")
	ua = _eng_units(e, "a")
	ub = _eng_units(e, "b")
	if ua.is_empty() or ub.is_empty():
		_end_engagement(e, "b" if ua.is_empty() else "a", "The other side left the field.", out)
		return
	# break check: the commander gives the order to quit unless the player has taken command
	var broke := ""
	for pair: Array in [["a", ua, sa], ["b", ub, sb]]:
		var side: String = pair[0]
		var us: Array = pair[1]
		var mor := 0.0
		var men := 0
		for u: Dictionary in us:
			mor += float(u["morale"]) * float(u["men"])
			men += int(u["men"])
		mor /= maxf(1.0, float(men))
		var thr := float((WarUnits.BREAK_MORALE as Dictionary).get(String((_cmd_of(_army_of(us[0]), us[0]) as Dictionary)["personality"]), 0.2))
		if String(e["control"]) == "player" and _eng_has_player(e, side):
			thr = 0.08
		if mor < thr or float(men) < 0.25 * float((e["men0"] as Dictionary)[side]):
			broke = side
			break
	if broke != "":
		_end_engagement(e, "b" if broke == "a" else "a", "%s broke." % ("Our line" if _eng_has_player(e, broke) else "Their line"), out)
	elif int(e["rounds"]) >= ENG_MAX_ROUNDS:
		_end_engagement(e, "", "Both sides drew apart at nightfall.", out)
	elif (e["log"] as Array).size() < 40 and int(e["rounds"]) % 3 == 0:
		(e["log"] as Array).append("Hour %d: %s." % [int(e["rounds"]), "the line holds" if e["status"] == "holding" else ("we press them" if ratio > 0.5 and _eng_has_player(e, "a") else "under pressure")])


func _med_share(us: Array) -> float:
	var med := 0
	var men := 0
	for u: Dictionary in us:
		men += int(u["men"])
		if String(u["kind"]) == "medical":
			med += int(u["men"])
	return float(med) / maxf(1.0, float(men))


## Spreads a side's losses over its units by exposure, and shakes their morale. Returns men lost.
func _apply_losses(us: Array, frac: float, share: float) -> int:
	var total := 0
	var wsum := 0.0
	for u: Dictionary in us:
		total += int(u["men"])
		wsum += float(u["men"]) * float((WarUnits.kind(String(u["kind"])) as Dictionary)["exposure"])
	var lost_total := int(round(float(total) * frac))
	var lost := 0
	for u: Dictionary in us:
		var w := float(u["men"]) * float((WarUnits.kind(String(u["kind"])) as Dictionary)["exposure"]) / maxf(wsum, 0.001)
		var l := mini(int(u["men"]), int(round(float(lost_total) * w)))
		u["men"] = int(u["men"]) - l
		lost += l
		u["morale"] = clampf(float(u["morale"]) - (0.02 + 0.6 * frac) + (share - 0.5) * 0.05, 0.0, 1.0)
	return lost


func _disengage(u: Dictionary, fighting: bool) -> void:
	var e := engagement_raw(int(u["eng"]))
	u["eng"] = 0
	u["state"] = "retreating"
	var pen := 0.02 if fighting else 0.06
	var lost := int(round(float(u["men"]) * pen))
	u["men"] = maxi(1, int(u["men"]) - lost)
	if not e.is_empty():
		(e["log"] as Array).append("%s %s%s." % [u["name"], "withdrew fighting" if fighting else "broke off", " (lost %d)" % lost if lost > 0 else ""])
	var a := _army_of(u)
	if not bool(u["detached"]):
		# an attached unit leaving detaches: it goes its own way
		var p := army_pos(a)
		u["detached"] = true
		u["x"] = p.x
		u["y"] = p.y
		_recount(a)
	if String(a["state"]) == "engaged":
		_release_army(a)


func _release_army(a: Dictionary) -> void:
	for u: Dictionary in (a["units"] as Array):
		if not bool(u["detached"]) and int(u["eng"]) != 0:
			return
	a["state"] = "moving" if not (a["route"] as Array).is_empty() else "camped"


func _end_engagement(e: Dictionary, winner: String, why: String, out: Array) -> void:
	e["end_hour"] = _hours
	e["status"] = "ended"
	e["outcome"] = winner if winner != "" else "stalemate"
	(e["log"] as Array).append(why)
	var losers: Array = []
	var winners: Array = []
	for side: String in ["a", "b"]:
		for id: int in (e[side] as Array):
			var u := _unit(id)
			if u.is_empty() or int(u["eng"]) != int(e["id"]):
				continue
			u["eng"] = 0
			u["state"] = "idle"
			var a := _army_of(u)
			if winner == "":
				continue
			if side == winner:
				u["morale"] = clampf(float(u["morale"]) + 0.06, 0.0, 1.0)
				winners.append(u)
			else:
				losers.append(u)
	for u: Dictionary in losers:
		var a2 := _army_of(u)
		var rout := float(u["morale"]) < 0.18
		if rout:
			u["men"] = maxi(1, int(u["men"]) - int(round(float(u["men"]) * 0.06)))
			u["morale"] = clampf(float(u["morale"]) - 0.1, 0.0, 1.0)
		var hp := _home_pos(a2)
		if not bool(u["detached"]):
			var p := army_pos(a2)
			u["detached"] = true
			u["x"] = p.x
			u["y"] = p.y
			_recount(a2)
		u["order"] = {"behavior": "retreat", "x": hp.x, "y": hp.y, "since": _hours, "retreat": "rout" if rout else "orderly"}
		u["state"] = "retreating"
	var seen := {}
	for side2: String in ["a", "b"]:
		for id2: int in (e[side2] as Array):
			var u2 := _unit(id2)
			if u2.is_empty():
				continue
			var ar := _army_of(u2)
			if not seen.has(int(ar["id"])):
				seen[int(ar["id"])] = true
				_recalc(ar)
				_release_army(ar)
	for aid: int in seen:
		_prune(_army(aid))
	_armies = _armies.filter(func(x: Dictionary) -> bool: return int(x["strength"]) > 0)
	# record for the strategic battle list
	var wf := ""
	if winner != "":
		wf = String(e["fa"] if winner == "a" else e["fb"])
	var pside := "a" if _eng_has_player(e, "a") else ("b" if _eng_has_player(e, "b") else "")
	var cas := e["cas"] as Dictionary
	var rec := {"id": _next_id, "day": _day, "node": nearest_node(Vector2(float(e["x"]), float(e["y"]))), "name": String(e["name"]),
		"attackers": [], "defenders": [], "winner": "attackers" if winner == String(e["attacker"]) else "defenders", "winner_faction": wf if wf != "" else "none",
		"live": false, "casualties": {"player": int(cas[pside]) if pside != "" else 0, "enemy": int(cas["b" if pside == "a" else "a"]) if pside != "" else 0},
		"retreat": "orderly", "eng": int(e["id"])}
	_next_id += 1
	_battles.append(rec)
	if _battles.size() > BATTLES_MAX:
		_battles.pop_front()
	if pside != "":
		var won := winner == pside
		out.append("%s at %s (you lost %d, they lost %d)." % ["Victory" if won else ("Stalemate" if winner == "" else "Defeat"), _place_name(Vector2(float(e["x"]), float(e["y"]))),
			int(cas[pside]), int(cas["b" if pside == "a" else "a"])])
		if winner != "":
			_rep(PLAYER, "victory" if won else "")
		var wsim: Variant = _war()
		if wsim != null:
			wsim.note_engagement(won and winner != "", int(cas[pside]), int(cas["b" if pside == "a" else "a"]), Vector2(float(e["x"]), float(e["y"])))
	while _engs.size() > ENGS_KEEP:
		var idx := -1
		for i in _engs.size():
			if String((_engs[i] as Dictionary)["status"]) == "ended":
				idx = i
				break
		if idx < 0:
			break
		_engs.remove_at(idx)


## Scripted clash between two groups of pieces (events, tests): side a attacks side b at (x, y).
func open_engagement(ids_a: Array, ids_b: Array, x: float, y: float) -> Dictionary:
	var ua: Array = []
	var ub: Array = []
	for id in ids_a:
		var u := _unit(int(id))
		if not u.is_empty() and int(u["eng"]) == 0:
			ua.append(u)
	for id2 in ids_b:
		var u2 := _unit(int(id2))
		if not u2.is_empty() and int(u2["eng"]) == 0:
			ub.append(u2)
	if ua.is_empty() or ub.is_empty():
		return {}
	var e := _open_engagement(ua, ub, "a", Vector2(x, y), "", [])
	return engagement_view(int(e["id"]))


## Adjust a unit's stats (quality, morale, fatigue, men) for scripted events and tests.
func tune_unit(unit_id: int, changes: Dictionary) -> bool:
	var u := _unit(unit_id)
	if u.is_empty():
		return false
	for k: String in changes:
		if k in ["quality", "morale", "fatigue"]:
			u[k] = clampf(float(changes[k]), 0.0, 1.0)
		elif k == "men":
			u["men"] = maxi(0, int(changes[k]))
			u["max_men"] = maxi(int(u["max_men"]), int(u["men"]))
	_recalc(_army_of(u))
	return true



func engagement_raw(id: int) -> Dictionary:
	for e: Dictionary in _engs:
		if int(e["id"]) == id:
			return e
	return {}


## Engagement records (newest last). Enemy numbers are what the player's side knows, never the truth.
func engagements(active_only := false) -> Array:
	var out: Array = []
	for e: Dictionary in _engs:
		if active_only and String(e["status"]) == "ended":
			continue
		out.append(engagement_view(int(e["id"])))
	return out


func engagement_view(id: int) -> Dictionary:
	var e := engagement_raw(id)
	if e.is_empty():
		return {}
	var v := e.duplicate(true)
	var pside := "a" if _eng_has_player(e, "a") else ("b" if _eng_has_player(e, "b") else "a")
	var eside := "b" if pside == "a" else "a"
	v["pos"] = Vector2(float(e["x"]), float(e["y"]))
	v["player_side"] = pside
	v["player_involved"] = _eng_has_player(e, "a") or _eng_has_player(e, "b")
	var ours: Dictionary = {}
	var men := 0
	for id2: int in (e[pside] as Array):
		var u := _unit(id2)
		if u.is_empty():
			continue
		men += int(u["men"])
		ours[String(u["kind"])] = int(ours.get(String(u["kind"]), 0)) + int(u["men"])
	v["your_forces"] = ours
	v["your_men"] = men
	var pmin := 0
	var pmax := 0
	var comp: Dictionary = {}
	var exact := true
	var unknown := 0
	var seen_keys := {}
	for id3: int in (e[eside] as Array):
		var t := _unit(id3)
		if t.is_empty():
			continue
		var ta := _army_of(t)
		var key := "u%d" % id3 if bool(t["detached"]) else "a%d" % int(ta["id"])
		if seen_keys.has(key):
			continue
		seen_keys[key] = true
		if _sight.has(key):
			var s: Dictionary = _sight[key]
			pmin += int(s["min"])
			pmax += int(s["max"])
			exact = exact and bool(s["exact"])
			for k: String in (s["comp"] as Dictionary):
				comp[k] = int(comp.get(k, 0)) + int((s["comp"] as Dictionary)[k])
		else:
			unknown += 1
			exact = false
	v["enemy_min"] = pmin
	v["enemy_max"] = pmax + (unknown * 100 if unknown > 0 else 0)
	v["enemy_exact"] = exact
	v["enemy_comp"] = comp
	v["enemy_unknown_support"] = unknown > 0 or not exact
	var my_side_lead := String((e["lead"] as Dictionary).get(pside, ""))
	v["commander"] = my_side_lead
	v["ratio_player"] = float(e["ratio"]) if pside == "a" else 1.0 - float(e["ratio"])
	v["casualties_player"] = int((e["cas"] as Dictionary)[pside])
	v["casualties_enemy"] = int((e["cas"] as Dictionary)[eside])
	v["hours"] = (_hours if int(e["end_hour"]) < 0 else int(e["end_hour"])) - int(e["start_hour"])
	v["has_tactical"] = _tacs.has(id)
	return v


## The player steps in on an engagement (R§7): "take_command" | "leave_command" | "press" | "withdraw".
## Withdrawing sends withdraw-fighting orders by courier to every piece the player may command.
func intervene(eng_id: int, action: String) -> Dictionary:
	var e := engagement_raw(eng_id)
	if e.is_empty() or String(e["status"]) == "ended":
		return {"ok": false, "reason": "That engagement is over."}
	var pside := "a" if _eng_has_player(e, "a") else ("b" if _eng_has_player(e, "b") else "")
	if pside == "":
		return {"ok": false, "reason": "You have no forces there."}
	match action:
		"take_command":
			e["control"] = "player"
			return {"ok": true, "reason": ""}
		"leave_command":
			e["control"] = "commander"
			return {"ok": true, "reason": ""}
		"press":
			e["press"] = true
			return {"ok": true, "reason": ""}
		"withdraw":
			var sent := 0
			var denied := 0
			for id: int in (e[pside] as Array):
				var u := _unit(id)
				if u.is_empty():
					continue
				var res := order_unit(id, {"behavior": "withdraw_fighting"})
				if bool(res["ok"]):
					sent += 1
				else:
					denied += 1
			return {"ok": sent > 0, "sent": sent, "denied": denied, "reason": "" if sent > 0 else "None of those troops are yours to order."}
	return {"ok": false, "reason": "Unknown action."}


# --- tactical battles (phase B: docs/design/WAR_COMMAND_RULEBOOK.md §1, §25-40, §48-50) -------------------
# An engagement can be fought on a battlefield generated from the real ground where it stands. While a tactical
# battle exists for an engagement the hourly factor rounds are replaced by 360 battle steps of the same forces; the
# result (casualties, morale, fatigue, winner) is written back to the campaign pieces and the engagement ends the
# same way a factor-resolved one does.

const FORM_MAP := {"line": "line", "wedge": "wedge", "square": "square", "skirmish": "loose", "column": "column"}


func tactical_battle(eng_id: int, create := true) -> RefCounted:
	if _tacs.has(eng_id):
		return _tacs[eng_id]
	if not create:
		return null
	var e := engagement_raw(eng_id)
	if e.is_empty() or String(e["status"]) == "ended":
		return null
	var tt: RefCounted = Tactical.create(_tactical_spec(e))
	_tacs[eng_id] = tt
	e["tac"] = true
	return tt


func has_tactical(eng_id: int) -> bool:
	return _tacs.has(eng_id)


func _unit_spec(u: Dictionary, a: Dictionary) -> Dictionary:
	var p := _upos(a, u)
	return {"cid": int(u["id"]), "name": String(u["name"]), "kind": String(u["kind"]), "men": int(u["men"]), "quality": float(u["quality"]), "morale": float(u["morale"]),
		"fatigue": float(u["fatigue"]), "wx": p.x, "wy": p.y}


func _side_spec(e: Dictionary, side: String, mine: Array, foes: Array, t: Dictionary) -> Dictionary:
	var env := _side_env(e, side, mine, foes, t)
	var leader: Dictionary = (env["leader"] as Dictionary).duplicate(true)
	var units: Array = []
	var fac := String(e["fa" if side == "a" else "fb"])
	var form := "line"
	var big := -1
	for u: Dictionary in mine:
		var a := _army_of(u)
		units.append(_unit_spec(u, a))
		if int(u["men"]) > big:
			big = int(u["men"])
			form = String(a["formation"])
	var cmd := {"name": String(leader.get("name", "Captain")), "personality": String(leader.get("personality", "loyal")), "skill": int(leader.get("skill", 2))}
	for k: String in WarUnits.ATTRS:
		cmd[k] = int(leader.get(k, 50))
	var elites: Array = []
	if int(cmd.get("experience", 0)) >= 70 and _hash_f("champion", int(e["id"]) * 2 + (0 if side == "a" else 1)) < 0.5:
		elites.append({"kind": "champion", "name": "%s's Champion" % String(cmd["name"]), "men": 1, "quality": 0.95, "morale": 0.95, "fatigue": 0.0})
	if String(e.get("champion_side", "")) == side:
		elites.append({"kind": "champion", "name": "You, sword in hand", "men": 1, "quality": 0.95, "morale": 1.0, "fatigue": 0.0, "hero": true, "layer": "front"})
	return {"faction": fac, "player": fac == PLAYER, "name": ("Your army" if fac == PLAYER else fac.capitalize().replace("_", " ")), "cmd": cmd, "units": units, "elites": elites,
		"supply": float(env["supply"]), "formation": String(FORM_MAP.get(form, "line"))}


func _tactical_spec(e: Dictionary) -> Dictionary:
	var ua := _eng_units(e, "a")
	var ub := _eng_units(e, "b")
	var t := terrain_at(Vector2(float(e["x"]), float(e["y"])))
	var sa := _side_spec(e, "a", ua, ub, t)
	var sb := _side_spec(e, "b", ub, ua, t)
	var ea := _side_env(e, "a", ua, ub, t)
	var eb := _side_env(e, "b", ub, ua, t)
	ea["high_ground"] = 0
	eb["high_ground"] = 0
	var fa: Dictionary = WarUnits.side_power(ua, ea)["factors"]
	var fb: Dictionary = WarUnits.side_power(ub, eb)["factors"]
	var involved := _eng_has_player(e, "a") or _eng_has_player(e, "b")
	return {"seed": int(hash([WorldSim.SEED, int(e["id"])])) & 0x7fffffff, "name": "Battle of %s" % _place_name(Vector2(float(e["x"]), float(e["y"]))), "center": [float(e["x"]), float(e["y"])],
		"n": 40, "cell": 40.0, "weather": _weather, "season": _season, "hour": _hours % 24, "attacker": String(e["attacker"]), "surprise": String(e["surprise"]),
		"deploy": involved, "sides": {"a": sa, "b": sb}, "factors": {"a": fa, "b": fb}}


## The player takes the battle map (R§48): opens it for an engagement he is part of. Returns the Tactical battle or null.
func tactical_open(eng_id: int) -> RefCounted:
	var tt := tactical_battle(eng_id)
	if tt == null:
		return null
	var e := engagement_raw(eng_id)
	e["control"] = "player"
	tt.set("ui_attached", true)
	var pside := 0 if _eng_has_player(e, "a") else (1 if _eng_has_player(e, "b") else -1)
	if pside >= 0:
		tt.auto[pside] = false
	return tt


## Back to the campaign map (R§50): the commander takes over the side, the battle goes on by the hour.
func tactical_leave(eng_id: int) -> void:
	var tt := tactical_battle(eng_id, false)
	var e := engagement_raw(eng_id)
	if tt == null:
		return
	tt.set("ui_attached", false)
	if not e.is_empty():
		e["control"] = "commander"
	tt.auto = [true, true]
	if String(tt.phase) == "deploy":
		tt.begin()


func _tac_hour(e: Dictionary, out: Array) -> void:
	var id := int(e["id"])
	var tt: RefCounted = _tacs[id]
	if bool(tt.get("ui_attached")):
		return
	if String(tt.phase) == "deploy":
		tt.begin()
	var keep: Array = tt.auto.duplicate()
	tt.auto = [true, true]
	var before := (tt.events as Array).size()
	tt.advance(360)
	tt.auto = keep
	e["rounds"] = int(e["rounds"]) + 1
	var fa: Dictionary = tt.forces(0)
	var fb: Dictionary = tt.forces(1)
	var pa := float(fa["men"]) * (0.5 + float(fa["morale"]))
	var pb := float(fb["men"]) * (0.5 + float(fb["morale"]))
	e["ratio"] = snappedf(pa / maxf(pa + pb, 1.0), 0.001)
	e["status"] = "holding" if absf(float(e["ratio"]) - 0.5) < 0.1 else "fighting"
	if (e["log"] as Array).size() < 40:
		var evs: Array = tt.events
		for ev: Dictionary in evs.slice(maxi(before, evs.size() - 2)):
			if String(ev["kind"]) in ["rout", "destroyed", "retreat", "duel_end", "elite_dead", "commander_down"]:
				(e["log"] as Array).append(String(ev["text"]))
	if String(tt.phase) == "ended":
		tactical_apply(id, out)


## Writes a finished battle back into the campaign (casualties, morale, fatigue) and ends the engagement.
func tactical_apply(eng_id: int, out: Array = []) -> Dictionary:
	var e := engagement_raw(eng_id)
	var tt := tactical_battle(eng_id, false)
	if e.is_empty() or tt == null or String(tt.phase) != "ended":
		return {}
	var r: Dictionary = (tt.result as Dictionary).duplicate(true)
	var lost := {"a": 0, "b": 0}
	for ud: Dictionary in (r["units"] as Array):
		var cid := int(ud["cid"])
		if cid == 0:
			continue
		var u := _unit(cid)
		if u.is_empty():
			continue
		var before := int(u["men"])
		u["men"] = maxi(0, mini(before, int(ud["men"])))
		u["morale"] = clampf(float(ud["morale"]), 0.0, 1.0)
		u["fatigue"] = clampf(float(ud["fatigue"]), 0.0, 1.0)
		lost["a" if int(ud["side"]) == 0 else "b"] = int(lost["a" if int(ud["side"]) == 0 else "b"]) + (before - int(u["men"]))
		_recalc(_army_of(u))
	e["cas"] = {"a": int(lost["a"]), "b": int(lost["b"])}
	e["tac_result"] = {"winner": String(r["winner"]), "why": String(r["why"]), "t": float(r["t"]), "cas": e["cas"], "duels": int(r["duels"]), "terrain": String(r["terrain"]), "weather": String(r["weather"])}
	e["rounds"] = maxi(int(e["rounds"]), int(ceil(float(r["t"]) / 3600.0)))
	_tacs.erase(eng_id)
	_end_engagement(e, String(r["winner"]), String(r["why"]), out)
	return r


## Sends the player's idle pieces near the battle as reinforcements (R§27, "send reinforcements"). Returns {ok, sent, eta_min}.
func tactical_reinforce(eng_id: int) -> Dictionary:
	var e := engagement_raw(eng_id)
	var tt := tactical_battle(eng_id, false)
	if e.is_empty() or tt == null or String(tt.phase) == "ended":
		return {"ok": false, "sent": 0, "reason": "No battle to reinforce."}
	var side := "a" if _eng_has_player(e, "a") else ("b" if _eng_has_player(e, "b") else "")
	if side == "":
		return {"ok": false, "sent": 0, "reason": "You have no forces in this battle."}
	var pos := Vector2(float(e["x"]), float(e["y"]))
	var specs: Array = []
	var far := 0.0
	var moved: Array = []
	for a: Dictionary in _armies:
		if String(a["faction"]) != PLAYER:
			continue
		for u: Dictionary in (a["units"] as Array):
			if int(u["eng"]) != 0 or int(u["men"]) <= 0:
				continue
			var d := _upos(a, u).distance_to(pos)
			if d > 2200.0:
				continue
			far = maxf(far, d)
			var sp := _unit_spec(u, a)
			sp["layer"] = "second"
			specs.append(sp)
			moved.append([u, a])
	if specs.is_empty():
		return {"ok": false, "sent": 0, "reason": "No free formations within reach."}
	var eta := 120.0 + far / 1.5
	var pside := 0 if side == "a" else 1
	var ids: Array = tt.send_reinforcements(pside, specs, eta)
	for i in ids.size():
		(tt.u_meta[ids[i]] as Dictionary)["known"] = false
	for pr: Array in moved:
		var mu: Dictionary = pr[0]
		mu["eng"] = int(e["id"])
		mu["state"] = "engaged"
		(e[side] as Array).append(int(mu["id"]))
	return {"ok": true, "sent": specs.size(), "eta_min": int(ceil(eta / 60.0))}


func tactical_view(eng_id: int) -> Dictionary:
	var tt := tactical_battle(eng_id, false)
	if tt == null:
		return {}
	return {"phase": String(tt.phase), "time": String(tt.time_text()), "terrain": String(tt.terrain_name), "weather": String(tt.weather)}


# --- sieges (phase B: R§41-47) ------------------------------------------------------------------------------

func _siege_key_for_stronghold(id: int) -> String:
	return "sh:%d" % id


## Opens a siege of stronghold `id` (strongholds.gd) by the armies `army_ids` (default: the player's armies near it).
## Returns the Siege or null.
func siege_begin(stronghold_id: int, attacker := PLAYER, army_ids: Array = []) -> RefCounted:
	if hub == null:
		return null
	var sh: RefCounted = hub.mod("strongholds")
	if sh == null:
		return null
	var st: Dictionary = sh.call("stronghold", stronghold_id)
	if st.is_empty():
		return null
	var key := _siege_key_for_stronghold(stronghold_id)
	if _sieges.has(key):
		return _sieges[key]
	var pos: Vector2 = st["pos"]
	var units: Array = []
	var eng := 0
	var men := 0
	var ids := army_ids
	if ids.is_empty():
		for a: Dictionary in _armies:
			if String(a["faction"]) == attacker and army_pos(a).distance_to(pos) < 600.0:
				ids.append(int(a["id"]))
	for aid in ids:
		var a2 := _army(int(aid))
		if a2.is_empty():
			continue
		for u: Dictionary in (a2["units"] as Array):
			men += int(u["men"])
			if String(u["kind"]) == "engineer":
				eng += int(u["men"])
			elif String(u["kind"]) not in ["medical", "scout"]:
				units.append(_unit_spec(u, a2))
	if men <= 0:
		men = 400
	var r := _rng("siege", stronghold_id)
	var kind := String(st["kind"])
	var sk := "castle" if kind == "castle" else ("fort" if kind in ["fort", "watchfort", "junction", "pass", "rift_outpost"] else "town")
	var g := maxi(40, int(st["garrison"]) * 5)
	var spec := {"key": key, "name": String(st["name"]), "pos": [pos.x, pos.y], "kind": sk, "defender": String(st["owner"]), "attacker": attacker, "seed": int(hash([WorldSim.SEED, stronghold_id])) & 0x7fffffff,
		"garrison": g, "garrison_max": maxi(g, int(st["garrison_max"]) * 5), "food_days": float(st["supply"]) * 0.5, "water_days": 14.0 + r.randf() * 12.0, "well": r.randf() < 0.5,
		"civilians": g * 2, "wall_age": r.randf_range(0.1, 0.7), "wall_radius": 95.0 if sk == "fort" else 110.0, "gates": [0.0, PI], "day": _day,
		"commander": {"name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]], "personality": WarUnits.PERSONALITIES[r.randi() % WarUnits.PERSONALITIES.size()]},
		"camp": {"men": men, "engineers": maxi(eng, 10), "guards": int(men * 0.15), "medical": int(men * 0.04), "mages": 0}, "tech": 1 if _day < 400 else 2,
		"timber": clampf(WorldGen.forest_density(pos.x - 190.0, pos.y + 140.0) * 1.2 + 0.25, 0.15, 1.0), "att_units": units}
	var sg: RefCounted = Siege.create(spec)
	_sieges[key] = sg
	sh.call("begin_siege", stronghold_id, attacker, men)
	return sg


func siege(key: String) -> RefCounted:
	return _sieges.get(key)


func sieges(active_only := true) -> Array:
	var out: Array = []
	for k: String in _sieges:
		var sg: RefCounted = _sieges[k]
		if not active_only or String(sg.s["status"]) == "active":
			var v: Dictionary = sg.view()
			v["key"] = k
			out.append(v)
	return out


func _siege_day(out: Array) -> void:
	for k: String in _sieges.keys():
		var sg: RefCounted = _sieges[k]
		if String(sg.s["status"]) != "active":
			continue
		var lines: Array = sg.tick_day()
		if String(sg.s["attacker"]) == PLAYER:
			for ln in lines.slice(0, 2):
				if out.size() < 8:
					out.append("%s: %s" % [String(sg.s["name"]), String(ln)])
		if bool(sg.s["sortie_due"]):
			var res: Dictionary = sg.auto_sortie()
			if String(sg.s["attacker"]) == PLAYER and out.size() < 8:
				out.append(String((res["lines"] as Array)[0]))
		if String(sg.s["status"]) == "active" and String(sg.s["attacker"]) == PLAYER:
			var present := false
			var p := Vector2(float((sg.s["pos"] as Array)[0]), float((sg.s["pos"] as Array)[1]))
			for a: Dictionary in _armies:
				if String(a["faction"]) == PLAYER and army_pos(a).distance_to(p) < 700.0:
					present = true
			if not present:
				sg.lift()
		if String(sg.s["status"]) == "fallen":
			_siege_fell(k, sg, out)


func siege_assault(key: String, auto := true) -> Dictionary:
	var sg: RefCounted = _sieges.get(key)
	if sg == null or String(sg.s["status"]) != "active":
		return {}
	var res: Dictionary = sg.auto_assault() if auto else {}
	if String(sg.s["status"]) == "fallen":
		_siege_fell(key, sg, [])
	return res


func siege_negotiate(key: String, terms := {}) -> Dictionary:
	var sg: RefCounted = _sieges.get(key)
	if sg == null:
		return {}
	var rep := {}
	if hub != null:
		var f: RefCounted = hub.mod("factions")
		if f != null and f.has_method("war_rep"):
			rep = f.call("war_rep", String(sg.s["attacker"]))
	var ev: Dictionary = sg.negotiate(rep, terms)
	if bool(ev["surrendered"]):
		_rep_act(String(sg.s["attacker"]), "honour_surrender")
		_siege_fell(key, sg, [])
	return ev


func siege_conduct(key: String, kind: String) -> void:
	var sg: RefCounted = _sieges.get(key)
	if sg == null:
		return
	var act: String = sg.conduct(kind)
	if act != "":
		_rep_act(String(sg.s["attacker"]), act)


func _rep_act(actor: String, act: String) -> void:
	if hub == null:
		return
	var f: RefCounted = hub.mod("factions")
	if f != null and f.has_method("record_war_act"):
		f.call("record_war_act", actor, act)


## The place changes hands: stronghold captured, land gets a claim for the old holder (R§59), victory recorded.
func _siege_fell(key: String, sg: RefCounted, out: Array) -> void:
	if bool(sg.s.get("_handled", false)):
		return
	sg.s["_handled"] = true
	var att := String(sg.s["attacker"])
	if key.begins_with("sh:") and hub != null:
		var sid := int(key.substr(3))
		var sh: RefCounted = hub.mod("strongholds")
		if sh != null:
			sh.call("capture", sid, att)
		var land: RefCounted = hub.mod("land")
		if land != null and att == PLAYER:
			var nn := nearest_node(Vector2(float((sg.s["pos"] as Array)[0]), float((sg.s["pos"] as Array)[1])))
			if land.has_method("conquer") and String(land.call("deed", str(nn)).get("holder", "")) != PLAYER:
				land.call("conquer", str(nn), PLAYER, _day)
	_captured[key] = att
	if att == PLAYER:
		_rep_act(PLAYER, "victory")
		if out.size() < 8:
			out.append("%s has fallen to you." % String(sg.s["name"]))


# --- war goals and political costs (R§55), claims and independence (R§56-59) ---------------------------------

const GOAL_KINDS := {
	"capture_fortress": "Capture a border fortress", "recover_land": "Recover disputed land", "tribute": "Force tribute", "free_prisoners": "Free prisoners",
	"protect_ally": "Protect an ally", "install_claimant": "Install a claimant", "destroy_sect": "Destroy a sect", "seize_rift": "Seize a Rift entrance", "secure_road": "Secure a trade road",
}


func add_war_goal(kind: String, target: int, enemy: String, opts := {}) -> int:
	if not GOAL_KINDS.has(kind):
		return -1
	var g := {"id": _next_goal, "kind": kind, "target": target, "enemy": enemy, "day": _day, "done": false, "done_day": -1, "text": String(opts.get("text", GOAL_KINDS[kind])), "extra": opts.duplicate(true)}
	_next_goal += 1
	_goals.append(g)
	return int(g["id"])


func war_goals() -> Array:
	return _goals.duplicate(true)


func war_goal_achieve(goal_id: int) -> bool:
	for g: Dictionary in _goals:
		if int(g["id"]) == goal_id and not bool(g["done"]):
			g["done"] = true
			g["done_day"] = _day
			return true
	return false


func _goals_day(out: Array) -> void:
	if _goals.is_empty() or hub == null:
		return
	var sh: RefCounted = hub.mod("strongholds")
	var land: RefCounted = hub.mod("land")
	for g: Dictionary in _goals:
		if bool(g["done"]):
			continue
		var ok := false
		match String(g["kind"]):
			"capture_fortress", "seize_rift":
				if sh != null:
					ok = String((sh.call("stronghold", int(g["target"])) as Dictionary).get("owner", "")) == PLAYER
			"recover_land":
				if land != null:
					ok = String((land.call("deed", str(int(g["target"]))) as Dictionary).get("occupier", "")) == PLAYER
			"secure_road":
				ok = true
				if sh != null:
					var ex: Dictionary = g["extra"]
					var c: Dictionary = sh.call("controls_route", int(ex.get("a", 0)), int(ex.get("b", 1)))
					ok = c.is_empty() or String(c.get("owner", "")) == PLAYER
		if ok:
			g["done"] = true
			g["done_day"] = _day
			if out.size() < 8:
				out.append("War goal achieved: %s." % String(g["text"]))


## Once the aims are met, going on is politically expensive: loyalty and treasury drain per day (R§55).
func war_cost() -> Dictionary:
	var open := 0
	var last := -1
	for g: Dictionary in _goals:
		if bool(g["done"]):
			last = maxi(last, int(g["done_day"]))
		else:
			open += 1
	var achieved := not _goals.is_empty() and open == 0
	var over := (_day - last) if achieved else 0
	return {"achieved": achieved, "open": open, "days_over": over, "cost_per_day": (4.0 + 1.5 * float(over)) if achieved else 1.0, "advice": "The objective is won; every further day costs loyalty and gold. Consider peace." if achieved else ""}


## R§56-59: how ready is a settlement to stand alone? stats 0..1 each: population, food, money, army, defences, officers,
## recognition, legitimacy, trade, administration. Returns {score, verdict, weakest, paths}.
func independence_readiness(region: String, stats: Dictionary, overlord_power := 1.0) -> Dictionary:
	var keys := ["population", "food", "money", "army", "defences", "officers", "recognition", "legitimacy", "trade", "administration"]
	var sum := 0.0
	var weakest := ""
	var wv := 2.0
	for k: String in keys:
		var v := clampf(float(stats.get(k, 0.0)), 0.0, 1.0)
		sum += v
		if v < wv:
			wv = v
			weakest = k
	var score := sum / float(keys.size())
	var claims: Array = []
	var holder := ""
	if hub != null:
		var land: RefCounted = hub.mod("land")
		if land != null:
			claims = land.call("claimants", region)
			holder = String((land.call("deed", region) as Dictionary).get("holder", ""))
	var strength := score / maxf(overlord_power, 0.05)
	var verdict := "destroyed" if strength < 0.25 else ("fragile" if strength < 0.5 else ("contested" if strength < 0.8 else "viable"))
	return {"score": snappedf(score, 0.001), "verdict": verdict, "weakest": weakest, "holder": holder, "claims": claims,
		"paths": ["royal recognition", "collapse of the former kingdom", "marriage claim", "rebellion", "foreign support", "religious recognition", "purchase of sovereignty", "military victory", "political treaty"]}


# --- battlefield assistants (R§18-19) ---------------------------------------------------------------------------

func war_staff() -> Array:
	if _wstaff.is_empty():
		_wstaff = WarAdvisors.roster(int(WorldSim.SEED))
	return _wstaff.duplicate(true)


func battle_advice(eng_id: int) -> Array:
	var tt := tactical_battle(eng_id, false)
	if tt == null:
		return []
	var e := engagement_raw(eng_id)
	var side := 0 if _eng_has_player(e, "a") else 1
	return WarAdvisors.battle_advice(tt, side, war_staff(), int(float(tt.t) / 600.0))


func siege_advice(key: String) -> Array:
	var sg: RefCounted = _sieges.get(key)
	if sg == null:
		return []
	return WarAdvisors.siege_advice(sg.view(), war_staff(), int(sg.s["seed"]), int(sg.s["day"]) / 3, sg.s["walls"])


# --- fog of war (R§23-24) ----------------------------------------------------------------

func _vision_step() -> void:
	var opos := PackedVector2Array()
	var orad := PackedFloat32Array()
	var oex := PackedFloat32Array()
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		var scouting := 1.0 + (float((a["commander"] as Dictionary)["scouting"]) - 50.0) / 200.0
		var ndet := int(a["ndet"])
		var units: Array = a["units"]
		if ndet < units.size():
			var rad := 0.0
			var ex := 0.0
			for u: Dictionary in units:
				if not bool(u["detached"]):
					var k: Dictionary = WarUnits.kind(String(u["kind"]))
					rad = maxf(rad, float(k["vision"]))
					if String(u["kind"]) == "scout":
						ex = 260.0
			opos.append(army_pos(a))
			orad.append(rad * scouting)
			oex.append(ex)
		if ndet > 0:
			for u2: Dictionary in units:
				if bool(u2["detached"]):
					var k2: Dictionary = WarUnits.kind(String(u2["kind"]))
					opos.append(Vector2(float(u2["x"]), float(u2["y"])))
					orad.append(float(k2["vision"]) * scouting)
					oex.append(260.0 if String(u2["kind"]) == "scout" else 0.0)
	if opos.is_empty():
		return
	var visible := {}
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER:
			continue
		var units2: Array = a["units"]
		if int(a["ndet"]) < units2.size():
			_try_see("a%d" % int(a["id"]), a, null, army_pos(a), opos, orad, oex, visible)
		if int(a["ndet"]) > 0:
			for u3: Dictionary in units2:
				if bool(u3["detached"]):
					_try_see("u%d" % int(u3["id"]), a, u3, Vector2(float(u3["x"]), float(u3["y"])), opos, orad, oex, visible)
	# scouts confirm absence: a sighting whose ground is now watched but empty is dropped
	for key: String in _sight.keys():
		if visible.has(key) or int((_sight[key] as Dictionary)["hour"]) >= _hours:
			continue
		var sp := Vector2(float((_sight[key] as Dictionary)["x"]), float((_sight[key] as Dictionary)["y"]))
		for i in opos.size():
			if opos[i].distance_to(sp) < float(orad[i]) * 0.5:
				_sight.erase(key)
				break


func _try_see(key: String, a: Dictionary, u: Variant, p: Vector2, opos: PackedVector2Array, orad: PackedFloat32Array, oex: PackedFloat32Array, visible: Dictionary) -> void:
	var t := terrain_at(p)
	var hidden := u != null and String(((u as Dictionary)["order"] as Dictionary)["behavior"]) == "ambush"
	var vm := float(t["vision"])
	var best_d := 1e18
	var best_r := 0.0
	var best_ex := 0.0
	for i in opos.size():
		var d := opos[i].distance_to(p)
		var r := float(orad[i]) * vm
		if hidden:
			r = minf(r, 120.0)
		if d <= r and d < best_d:
			best_d = d
			best_r = r
			best_ex = float(oex[i]) * vm
	if best_d > 1e17:
		return
	visible[key] = true
	var men := 0
	var comp := {}
	var mounted_men := 0
	var list: Array = [u] if u != null else _group_units(a, false)
	if u == null:
		list = []
		for x: Dictionary in (a["units"] as Array):
			if not bool(x["detached"]):
				list.append(x)
	for x2: Dictionary in list:
		men += int(x2["men"])
		comp[String(x2["kind"])] = int(comp.get(String(x2["kind"]), 0)) + int(x2["men"])
		if bool((WarUnits.kind(String(x2["kind"])) as Dictionary)["mounted"]):
			mounted_men += int(x2["men"])
	if men <= 0:
		return
	var exact := best_d <= maxf(best_ex, 90.0)
	var pr := 0.0 if exact else clampf(0.12 + 0.5 * best_d / maxf(best_r, 1.0), 0.12, 0.6)
	var hr := float(hash([WorldSim.SEED, key, _hours]) % 1000) / 1000.0
	var hr2 := float(hash([WorldSim.SEED, key, _hours, 7]) % 1000) / 1000.0
	var rg := WarUnits.est_range(men, pr, hr, hr2)
	var old: Dictionary = _sight.get(key, {})
	var known_comp: Dictionary = comp if exact else (old.get("comp", {}) as Dictionary)
	_sight[key] = {"key": key, "army_id": int(a["id"]), "unit_id": int(u["id"]) if u != null else 0, "faction": String(a["faction"]),
		"x": p.x, "y": p.y, "hour": _hours, "min": rg.x, "max": rg.y, "exact": exact, "comp": known_comp.duplicate(),
		"comp_hour": _hours if exact else int(old.get("comp_hour", -1)), "mounted": float(mounted_men) > 0.15 * float(men),
		"source": "scouts" if best_ex > 0.0 else ("contact" if best_d < 130.0 else "patrol"), "terrain": String(t["id"])}


## Enemy pieces as the player knows them (R§23-24): last confirmed position, an estimate that widens with
## age, the area they could have reached since, and the composition only if a scout confirmed it.
func enemy_pieces() -> Array:
	var out: Array = []
	for key: String in _sight:
		var s: Dictionary = _sight[key]
		if int(s["hour"]) > _hours or int(s.get("received_hour", s["hour"])) > _hours:
			continue
		var age := maxi(0, _hours - int(s["hour"]))
		if age > SIGHT_KEEP_HOURS:
			continue
		var widen := 1.0 + minf(float(age) * 0.01, 2.0)
		var mid := (float(s["min"]) + float(s["max"])) * 0.5
		var half := (float(s["max"]) - float(s["min"])) * 0.5
		var exact := bool(s["exact"]) and age == 0
		var lo := int(s["min"]) if exact or age == 0 else maxi(0, int(mid - half * widen))
		var hi := int(s["max"]) if exact or age == 0 else int(mid + half * widen)
		var conf := (1.0 if bool(s["exact"]) else 0.7) * pow(0.5, float(age) / 30.0)
		var ago := "in sight" if age == 0 else "last confirmed %d h ago" % age
		var label := ""
		if bool(s["exact"]) and age == 0:
			label = "Confirmed: %d men" % int(s["max"])
		elif bool(s["exact"]):
			label = "Was %d men, %s" % [int(s["max"]), ago]
		else:
			label = "Estimated %d-%d, %s" % [lo, hi, ago]
		out.append({"key": key, "army_id": int(s["army_id"]), "unit_id": int(s["unit_id"]), "faction": s["faction"],
			"pos": Vector2(float(s["x"]), float(s["y"])), "hour": int(s["hour"]), "age_hours": age, "est_min": lo, "est_max": hi,
			"exact": bool(s["exact"]), "comp": (s["comp"] as Dictionary).duplicate(), "comp_age": (_hours - int(s["comp_hour"])) if int(s["comp_hour"]) >= 0 else -1,
			"mounted": bool(s["mounted"]), "radius": minf(3000.0, float(age) * 0.5 * ARMY_SPEED), "confidence": snappedf(conf, 0.001),
			"live": age == 0, "label": label, "source": s["source"], "terrain": s["terrain"]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return String(x["key"]) < String(y["key"]))
	return out


## Other systems (merchants, rumours, spies, allies) can hand the war table a sighting of an enemy army:
## a rough estimate at its current place, aged from now. Returns false if there is no such army.
func report_sighting(army_id: int, source := "rumour", precision := 0.4) -> bool:
	var a := _army(army_id)
	if a.is_empty() or a["faction"] == PLAYER:
		return false
	var p := army_pos(a)
	var men := 0
	var comp := {}
	for u: Dictionary in (a["units"] as Array):
		if not bool(u["detached"]):
			men += int(u["men"])
	var key := "a%d" % army_id
	var rg := WarUnits.est_range(men, clampf(precision, 0.1, 0.8), _hash_f("sight_lo", army_id + _hours), _hash_f("sight_hi", army_id + _hours))
	var old: Dictionary = _sight.get(key, {})
	_sight[key] = {"key": key, "army_id": army_id, "unit_id": 0, "faction": String(a["faction"]), "x": p.x, "y": p.y, "hour": _hours,
		"min": rg.x, "max": rg.y, "exact": false, "comp": (old.get("comp", comp) as Dictionary).duplicate(), "comp_hour": int(old.get("comp_hour", -1)),
		"mounted": false, "source": source, "terrain": String(terrain_at(p)["id"])}
	return true


## Delayed scouts/spies submit what they actually observed, never current truth.
## Caller authenticates the witness and communication path before delivery.
## Old observations must not replace more recent knowledge or refresh its age.
func report_observation(army_id: int, faction: String, source: String, position: Vector2,
		observed_hour: int, minimum: int, maximum: int) -> bool:
	var report := SightingReport.build(army_id, faction, source, position,
		observed_hour, _hours, SIGHT_KEEP_HOURS, minimum, maximum)
	if report.is_empty():
		return false
	var key: String = report["key"]
	var previous: Dictionary = _sight.get(key, {})
	if not previous.is_empty() and int(previous["hour"]) >= observed_hour:
		return false
	if previous.is_empty() and _sight.size() >= 128:
		return false
	_sight[key] = report
	return true


## Called after a validated witness sends a report. Travel time is supplied by
## the host's communication route, not recomputed from live enemy positions.
func queue_observation(army_id: int, faction: String, source: String, position: Vector2,
		observed_hour: int, minimum: int, maximum: int, travel_hours: int) -> bool:
	if travel_hours < 1 or travel_hours > SIGHT_KEEP_HOURS or observed_hour > _hours \
			or _spy_reports.size() >= MAX_SPY_REPORTS:
		return false
	var report := SightingReport.build(army_id, faction, source, position,
		observed_hour, _hours + travel_hours, SIGHT_KEEP_HOURS, minimum, maximum)
	if report.is_empty():
		return false
	for pending: Dictionary in _spy_reports:
		if pending["key"] == report["key"] and pending["source"] == source and int(pending["hour"]) == observed_hour:
			return false
	_spy_reports.append(report)
	return true


func _deliver_spy_reports(out: Array) -> void:
	var keep: Array[Dictionary] = []
	for report: Dictionary in _spy_reports:
		if int(report["received_hour"]) > _hours:
			keep.append(report)
			continue
		if report_observation(int(report["army_id"]), String(report["faction"]), String(report["source"]),
				Vector2(float(report["x"]), float(report["y"])), int(report["hour"]), int(report["min"]), int(report["max"])):
			out.append("A scout report arrived: an enemy force was observed %d hours ago." % (_hours - int(report["hour"])))
	_spy_reports = keep


func _restore_spy_reports(rows: Variant) -> void:
	_spy_reports.clear()
	if not rows is Array:
		return
	for index in range(mini(rows.size(), MAX_SPY_REPORTS)):
		if not rows[index] is Dictionary:
			continue
		var row: Dictionary = rows[index]
		var report := SightingReport.build(int(row.get("army_id", 0)), String(row.get("faction", "")),
			String(row.get("source", "")), Vector2(float(row.get("x", INF)), float(row.get("y", INF))),
			int(row.get("hour", -1)), int(row.get("received_hour", -1)), SIGHT_KEEP_HOURS,
			int(row.get("min", -1)), int(row.get("max", -1)))
		if not report.is_empty() and int(report["hour"]) <= _hours:
			_spy_reports.append(report)



## The player's own pieces (truth: your own forces are always known), with their orders.
func own_pieces() -> Array:
	var out: Array = []
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		_sync(a)
		for u: Dictionary in (a["units"] as Array):
			var c := _copy_unit(a, u)
			var can := can_command(int(u["id"]))
			c["can_command"] = bool(can["ok"])
			c["source"] = can["source"]
			out.append(c)
	return out


func _field_day() -> void:
	for key: String in _sight.keys():
		if _hours - int((_sight[key] as Dictionary)["hour"]) > SIGHT_KEEP_HOURS:
			_sight.erase(key)
	for k: String in (_pcmd["appointed"] as Dictionary).keys():
		if int((_pcmd["appointed"] as Dictionary)[k]) <= _day:
			(_pcmd["appointed"] as Dictionary).erase(k)
	for a: Dictionary in _armies:
		for u: Dictionary in (a["units"] as Array):
			# rest and recovery: fed, still units recover morale and shed fatigue
			if String(u["state"]) == "idle":
				u["fatigue"] = maxf(0.0, float(u["fatigue"]) - 0.08)
				u["morale"] = clampf(float(u["morale"]) + 0.01, 0.0, 1.0)


func _field_step(ctx: Dictionary, out: Array) -> void:
	_weather = String(ctx.get("weather", _weather))
	_season = String(ctx.get("season", _season))
	var t0 := Time.get_ticks_usec()
	for a: Dictionary in _armies:
		_sync(a)
		if int(a["ndet"]) > 0:
			for u: Dictionary in (a["units"] as Array):
				if bool(u["detached"]):
					_field_move(a, u)
			if a["faction"] != PLAYER:
				for u2: Dictionary in (a["units"] as Array):
					if bool(u2["detached"]) and int(u2["eng"]) == 0 and bool((u2["order"] as Dictionary).get("arrived", false)):
						u2["detached"] = false
						u2["order"] = {"behavior": "hold", "since": _hours}
				_recount(a)
			if int(a["ndet"]) == (a["units"] as Array).size() and not (a["units"] as Array).is_empty():
				_rehome(a)
	var t1 := Time.get_ticks_usec()
	_contacts(out)
	var t2 := Time.get_ticks_usec()
	for e: Dictionary in _engs.duplicate():
		if String(e["status"]) != "ended":
			_eng_round(e, out)
	var t3 := Time.get_ticks_usec()
	_vision_step()
	var t4 := Time.get_ticks_usec()
	_perf["move"] = int(_perf.get("move", 0)) + t1 - t0
	_perf["contacts"] = int(_perf.get("contacts", 0)) + t2 - t1
	_perf["rounds"] = int(_perf.get("rounds", 0)) + t3 - t2
	_perf["vision"] = int(_perf.get("vision", 0)) + t4 - t3


## An army whose pieces have all gone their own way keeps its legacy graph position near them.
func _rehome(a: Dictionary) -> void:
	var c := Vector2.ZERO
	var m := 0.0
	for u: Dictionary in (a["units"] as Array):
		c += Vector2(float(u["x"]), float(u["y"])) * float(u["men"])
		m += float(u["men"])
	if m <= 0.0:
		return
	var n := nearest_node(c / m)
	if n != int(a["node"]):
		a["node"] = n
		a["prev_node"] = n
	a["route"] = []
	a["leg"] = 0.0
	if a["state"] != "engaged":
		a["state"] = "camped"


func _dispersed(a: Dictionary) -> bool:
	return int(a["ndet"]) > 0 and int(a["ndet"]) == (a["units"] as Array).size()


## "Pass time" for the war table: runs `hours` hourly ticks (and a day tick at each midnight).
func advance_hours(hours: int, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for i in hours:
		out.append_array(tick_hour(_hours % 24, ctx))
		if _hours % 24 == 0:
			out.append_array(tick_day(_day + 1, ctx))
	return out


func perf_stats() -> Dictionary:
	return _perf.duplicate()


func now_hours() -> int:
	return _hours


func now_day() -> int:
	return _day


## Where the player's side has scouted or walked: [{pos, radius, age_days}] for the map's fog.
func known_areas() -> Array:
	var out: Array = []
	for k: String in _explored:
		var n := int(k)
		out.append({"pos": node_pos(n), "radius": 620.0, "age_days": maxi(0, _day - int(_explored[k]))})
	for a: Dictionary in _armies:
		if a["faction"] == PLAYER:
			out.append({"pos": army_pos(a), "radius": 520.0, "age_days": 0})
			for u: Dictionary in (a["units"] as Array):
				if bool(u["detached"]):
					out.append({"pos": Vector2(float(u["x"]), float(u["y"])), "radius": float((WarUnits.kind(String(u["kind"])) as Dictionary)["vision"]) * 0.9, "age_days": 0})
	return out


## Nearest depot / supply route for the tactical view: [[from, to]] lines from each army to its depot.
func supply_routes() -> Array:
	var out: Array = []
	for a: Dictionary in _armies:
		if a["faction"] != PLAYER:
			continue
		var n := _nearest_depot_node(a)
		if n >= 0:
			out.append([army_pos(a), node_pos(n)])
	return out


func node_count() -> int:
	return WorldGen.settlements.size()


func roads_list() -> Array:
	var out: Array = []
	for e: Vector2i in WorldGen.roads:
		out.append([node_pos(e.x), node_pos(e.y)])
	return out


## Normalises a deserialised army (JSON turns ints into floats).
func _fix_field(a: Dictionary) -> void:
	if not a.has("units"):
		return
	var cmd: Dictionary = a["commander"]
	_ii(cmd, ["id", "tactics", "leadership", "discipline", "adaptability", "logistics", "scouting", "experience", "capacity"])
	for s: Dictionary in (a["subs"] as Array):
		_ii(s, ["id", "skill", "tactics", "leadership", "discipline", "adaptability", "logistics", "scouting", "experience", "capacity"])
	for u: Dictionary in (a["units"] as Array):
		_ii(u, ["id", "army", "men", "max_men", "cmd", "eng", "cap"])
		_ii(u["order"], ["since", "target_unit", "node"])
	_ii(a, ["ndet", "usum"])


func _field_catch_up(days: int, out: Array) -> void:
	var budget := float(mini(days, 30)) * 24.0
	for a: Dictionary in _armies:
		if int(a["ndet"]) == 0:
			continue
		for u: Dictionary in (a["units"] as Array):
			if not bool(u["detached"]) or int(u["eng"]) != 0:
				continue
			var o: Dictionary = u["order"]
			var beh: Dictionary = WarUnits.behaviour(String(o["behavior"]))
			if not bool(beh["moves"]) or not o.has("x"):
				continue
			var p := Vector2(float(u["x"]), float(u["y"]))
			var dest := Vector2(float(o["x"]), float(o["y"]))
			var reach := budget * ARMY_SPEED * float((WarUnits.kind(String(u["kind"])) as Dictionary)["speed"]) * float(beh["speed"]) * 0.75
			var np := p.move_toward(dest, reach)
			u["x"] = np.x
			u["y"] = np.y
			if np.distance_to(dest) < 12.0 and String(o["behavior"]) in ["advance", "charge", "flank", "retreat", "withdraw_fighting", "avoid", "intercept"]:
				u["order"] = {"behavior": "hold", "since": _hours, "arrived": true}
			u["state"] = "idle"
			u["fatigue"] = 0.0
	for e: Dictionary in _engs.duplicate():
		var n := 0
		while String(e["status"]) != "ended" and n < 40:
			_eng_round(e, out)
			n += 1


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
		"enemy": _enemy, "seeded_player": _seeded_player, "treaty_applied": _treaty_applied,
		"engs": _engs.duplicate(true), "sight": _sight.duplicate(true), "spy_reports": _spy_reports.duplicate(true), "orders_log": _orders_log.duplicate(true),
		"pcmd": _pcmd.duplicate(true), "captured": _captured.duplicate(true), "next_uid": _next_uid, "weather": _weather, "season": _season,
		"tacs": _ser_tacs(), "sieges": _ser_sieges(), "goals": _goals.duplicate(true), "next_goal": _next_goal, "wstaff": _wstaff.duplicate(true)}


func _ser_sieges() -> Dictionary:
	var out := {}
	for k: String in _sieges:
		out[k] = (_sieges[k] as RefCounted).call("serialize")
	return out


func _ser_tacs() -> Dictionary:
	var out := {}
	for id: int in _tacs:
		out[str(id)] = (_tacs[id] as RefCounted).call("serialize")
	return out


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
		_fix_field(a)
	_couriers = (d.get("couriers", []) as Array).duplicate(true)
	for c: Dictionary in _couriers:
		_ii(c, ["id", "army_id", "sent_hour", "sent_day", "eta_hours", "elapsed", "checked", "unit_id"])
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
	_treaty_applied = int(d.get("treaty_applied", -1))
	_next_id = int(d.get("next_id", 1))
	_hours = int(d.get("hours", 0))
	_restore_spy_reports(d.get("spy_reports", []))
	_day = int(d.get("day", 0))
	_hq = int(d.get("hq", 0))
	_player_node = int(d.get("player_node", 0))
	_op_counter = int(d.get("op_counter", 0))
	_enemy = String(d.get("enemy", ""))
	_seeded_player = bool(d.get("seeded_player", false))
	_engs = (d.get("engs", []) as Array).duplicate(true)
	for e: Dictionary in _engs:
		_ii(e, ["id", "start_hour", "end_hour", "rounds"])
		e["a"] = _int_arr(e["a"])
		e["b"] = _int_arr(e["b"])
		_ii(e["men0"], ["a", "b"])
		_ii(e["cas"], ["a", "b"])
	_sight = (d.get("sight", {}) as Dictionary).duplicate(true)
	for k5: String in _sight:
		_ii(_sight[k5], ["army_id", "unit_id", "hour", "received_hour", "min", "max", "comp_hour"])
		_ii(_sight[k5]["comp"], (_sight[k5]["comp"] as Dictionary).keys())
	_orders_log = (d.get("orders_log", []) as Array).duplicate(true)
	for ol: Dictionary in _orders_log:
		_ii(ol, ["id", "unit_id", "army_id", "sent_hour", "eta_hour", "ack_hour"])
	_pcmd = (d.get("pcmd", {"rank": "recruit", "appointed": {}}) as Dictionary).duplicate(true)
	for k6: String in _pcmd["appointed"]:
		_pcmd["appointed"][k6] = int(_pcmd["appointed"][k6])
	_captured = (d.get("captured", {}) as Dictionary).duplicate(true)
	_next_uid = int(d.get("next_uid", 1))
	_weather = String(d.get("weather", "clear"))
	_season = String(d.get("season", "spring"))
	_sieges.clear()
	for k8: String in (d.get("sieges", {}) as Dictionary):
		_sieges[k8] = Siege.restore((d["sieges"] as Dictionary)[k8])
	_goals = (d.get("goals", []) as Array).duplicate(true)
	for g2: Dictionary in _goals:
		_ii(g2, ["id", "target", "day", "done_day"])
	_next_goal = int(d.get("next_goal", 1))
	_wstaff = (d.get("wstaff", []) as Array).duplicate(true)
	_tacs.clear()
	for k7: String in (d.get("tacs", {}) as Dictionary):
		_tacs[int(k7)] = Tactical.restore((d["tacs"] as Dictionary)[k7])
	_uidx_dirty = true
	for a2: Dictionary in _armies:
		if not a2.has("units"):
			_init_field(a2)
