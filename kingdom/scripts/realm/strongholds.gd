extends "res://scripts/realm/realm_module.gd"
## Strongholds, dynamic raids and regional difficulty (R§29, R§30, R§33).
## Pure data. Strongholds sit at chokepoints derived deterministically from
## WorldGen.sites (bridges, forts, rift outposts) and road junctions / long
## road passes (WorldGen.roads is a graph of settlement index pairs).
##
## Raids: bands pick targets by wealth, weak garrison and road access, travel
## hour by hour, strike, loot and go home. Results are logged in
## recent_raid_results() and pushed to hub.mod("land").remember(...) when it
## exists (best effort, see _remember()).

const CHOKE_KINDS := ["bridge", "fort", "watchfort", "rift_outpost", "rift", "waystation"]
const RAIDER_KINDS := ["bandits", "monsters", "rival_lord", "mercenaries", "militants", "soulbeasts"]
const MAX_STRONGHOLDS := 64          # (30 on the 4 km map, 44 on the 8 km map; the 12 km world has ~60 chokepoint candidates)
const RAID_SPEED := 1260.0         # metres per hour (world is 12 km wide; 420 on the 4 km map, 840 on the 8 km map)
const MAX_RAIDS := 6
const RESULTS_MAX := 20
const PASS_MIN_LEN := 700.0

var _sh: Array = []                 # strongholds
var _built := false
var _raids: Array = []
var _results: Array = []
var _next_raid := 1
var _day := 0
var _hours := 0


func _rng(tag: String, day: int, id: Variant = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


# --- construction ---------------------------------------------------------------

func _ensure() -> void:
	if _built or WorldGen.settlements.is_empty():
		return
	_built = true
	_sh.clear()
	var settle := WorldGen.settlements
	var edges := WorldGen.roads
	var cands: Array = []
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) in CHOKE_KINDS and not bool(s.get("coach_inn", false)):      # a town's coach inn is not a chokepoint
			cands.append({"name": String(s.get("name", "Post")), "kind": String(s["kind"]), "pos": s["pos"]})
	# junctions (degree >= 3 settlements) and mountain passes on long roads
	var deg := {}
	for e: Vector2i in edges:
		deg[e.x] = int(deg.get(e.x, 0)) + 1
		deg[e.y] = int(deg.get(e.y, 0)) + 1
	for i: int in deg:
		if int(deg[i]) >= 3:
			cands.append({"name": "%s Crossing" % String(settle[i]["name"]), "kind": "junction", "pos": settle[i]["pos"] + Vector2(70, 40)})
	for e: Vector2i in edges:
		var pa: Vector2 = settle[e.x]["pos"]
		var pb: Vector2 = settle[e.y]["pos"]
		if pa.distance_to(pb) >= PASS_MIN_LEN:
			cands.append({"name": "%s Pass" % String(settle[e.y]["name"]), "kind": "pass", "pos": pa.lerp(pb, 0.5)})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]) if a["kind"] == b["kind"] else String(a["kind"]) < String(b["kind"]))
	var home: Vector2 = settle[0]["pos"]
	var seen_pos: Array = []
	for c: Dictionary in cands:
		if _sh.size() >= MAX_STRONGHOLDS:
			break
		var dup := false
		for p: Vector2 in seen_pos:
			if p.distance_to(c["pos"]) < 60.0:
				dup = true
				break
		if dup:
			continue
		seen_pos.append(c["pos"])
		var id := _sh.size()
		var r := _rng("stronghold", 0, id)
		# Names are unique (the map, war room and raid reports print them): a repeat gets a suffix.
		var nm := String(c["name"])
		var n2 := 2
		while _name_taken(nm):
			nm = "%s %s" % [String(c["name"]), ["", "II", "III", "IV", "V", "VI"][mini(n2 - 1, 5)]]
			n2 += 1
		c["name"] = nm
		var far: float = (c["pos"] as Vector2).distance_to(home)
		var owner := "caldrenn"
		if String(c["kind"]) in ["rift_outpost", "rift"]:
			owner = "independent"
		elif far > 1300.0 and r.randf() < 0.4:
			owner = "ongur_khanate" if c["pos"].x > home.x else "urrokai_clanlands"
		var gmax := 20 + r.randi() % 40
		if String(c["kind"]) in ["fort", "watchfort"]:
			gmax += 30
		_sh.append({"id": id, "name": c["name"], "kind": c["kind"], "pos": c["pos"], "owner": owner,
			"garrison": int(gmax * r.randf_range(0.6, 1.0)), "garrison_max": gmax, "toll": 2 + r.randi() % 8,
			"supply": 40 + r.randi() % 60, "wealth": 30 + r.randi() % 100, "siege": {}, "routes": _routes_for(c, edges, settle)})


func _name_taken(nm: String) -> bool:
	for s: Dictionary in _sh:
		if String(s["name"]) == nm:
			return true
	return false


func _routes_for(c: Dictionary, edges: Array, settle: Array) -> Array:
	# Junction: every edge at that settlement. Others: the nearest road edge.
	var out: Array = []
	if c["kind"] == "junction":
		var best := -1
		var bd := 1e9
		for i in settle.size():
			var d: float = (settle[i]["pos"] as Vector2).distance_to(c["pos"])
			if d < bd:
				bd = d
				best = i
		for e: Vector2i in edges:
			if e.x == best or e.y == best:
				out.append([mini(e.x, e.y), maxi(e.x, e.y)])
		return out
	var be := Vector2i(-1, -1)
	var bdist := 1e9
	for e: Vector2i in edges:
		var d := _seg_dist(c["pos"], settle[e.x]["pos"], settle[e.y]["pos"])
		if d < bdist:
			bdist = d
			be = e
	if be.x >= 0:
		out.append([mini(be.x, be.y), maxi(be.x, be.y)])
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- getters ----------------------------------------------------------------------

func strongholds() -> Array:
	_ensure()
	return _sh.duplicate(true)


func stronghold(id: int) -> Dictionary:
	_ensure()
	return (_sh[id] as Dictionary).duplicate(true) if id >= 0 and id < _sh.size() else {}


## Who controls the road between settlement indices a and b: returns
## {stronghold, owner, toll} of the strongest garrison on it, or {} if free.
func controls_route(a: int, b: int) -> Dictionary:
	_ensure()
	var key := [mini(a, b), maxi(a, b)]
	var best := {}
	var bg := -1
	for s: Dictionary in _sh:
		for rt: Array in s["routes"]:
			if int(rt[0]) == key[0] and int(rt[1]) == key[1] and int(s["garrison"]) > bg:
				bg = int(s["garrison"])
				best = {"stronghold": int(s["id"]), "owner": s["owner"], "toll": int(s["toll"])}
	return best


func raids() -> Array:
	return _raids.duplicate(true)


func recent_raid_results() -> Array:
	return _results.duplicate(true)


## Change hands (conquest hook for campaign / player).
func capture(id: int, new_owner: String) -> void:
	_ensure()
	if id < 0 or id >= _sh.size():
		return
	var s: Dictionary = _sh[id]
	s["owner"] = new_owner
	s["siege"] = {}
	s["garrison"] = maxi(5, int(s["garrison"]) / 3)


func begin_siege(id: int, attacker: String, strength: int) -> void:
	_ensure()
	if id >= 0 and id < _sh.size():
		_sh[id]["siege"] = {"attacker": attacker, "strength": strength, "day": _day, "progress": 0.0}


func nearest(pos: Vector2) -> Dictionary:
	_ensure()
	var best := {}
	var bd := 1e9
	for s: Dictionary in _sh:
		var d: float = (s["pos"] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = s
	return best.duplicate(true)


# --- ticks ---------------------------------------------------------------------

func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_ensure()
	_hours += 1
	var out: Array = []
	for rd: Dictionary in _raids:
		if rd["phase"] == "travel" or rd["phase"] == "return":
			var dest: Vector2 = rd["target_pos"] if rd["phase"] == "travel" else rd["origin"]
			var step := RAID_SPEED * (0.6 if ctx.get("season", "") == "winter" else 1.0)
			var cur: Vector2 = rd["pos"]
			if cur.distance_to(dest) <= step:
				rd["pos"] = dest
				if rd["phase"] == "travel":
					rd["phase"] = "strike"
				else:
					rd["phase"] = "done"
			else:
				rd["pos"] = cur + (dest - cur).normalized() * step
		if rd["phase"] == "strike":
			out.append_array(_strike(rd, ctx))
	_raids = _raids.filter(func(x: Dictionary) -> bool: return x["phase"] != "done")
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## Garrisons / sieges, then the raid roll (the two costly halves as separate pump jobs).
func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	var r := _rng("stronghold_day", day)
	return [
		func() -> Array:
			var out: Array = []
			for s: Dictionary in _sh:
				# garrisons refill from supply, supply drains, tolls fill wealth
				var need: int = int(s["garrison_max"]) - int(s["garrison"])
				if need > 0 and int(s["supply"]) > 5 and s["siege"].is_empty():
					s["garrison"] = int(s["garrison"]) + 1
				s["supply"] = clampi(int(s["supply"]) + (2 if s["siege"].is_empty() else -3), 0, 200)
				s["wealth"] = mini(400, int(s["wealth"]) + int(s["toll"]) / 2)
				if not s["siege"].is_empty():
					var sg: Dictionary = s["siege"]
					sg["progress"] = float(sg["progress"]) + float(sg["strength"]) / maxf(1.0, float(s["garrison"]) * 4.0) * 0.1 + (0.05 if int(s["supply"]) <= 0 else 0.0)
					if float(sg["progress"]) >= 1.0:
						out.append("%s falls to %s." % [s["name"], String(sg["attacker"]).capitalize()])
						capture(int(s["id"]), String(sg["attacker"]))
			return out,
		func() -> Array:
			var out: Array = []
			if _raids.size() < MAX_RAIDS and r.randf() < 0.55:
				var msg := _spawn_raid(r, day, ctx)
				if msg != "":
					out.append(msg)
			return out,
	]


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	if days <= 0:
		return out
	for s: Dictionary in _sh:
		s["garrison"] = mini(int(s["garrison_max"]), int(s["garrison"]) + days / 2) if s["siege"].is_empty() else s["garrison"]
		s["supply"] = clampi(int(s["supply"]) + 2 * days, 0, 200) if s["siege"].is_empty() else s["supply"]
	# in-flight raids resolve at once
	for rd: Dictionary in _raids.duplicate():
		if rd["phase"] != "done":
			rd["pos"] = rd["target_pos"]
			out.append_array(_strike(rd, ctx))
			rd["phase"] = "done"
	_raids.clear()
	# expected additional raids: closed form, a few resolved abstractly
	var n := mini(int(days * 0.4), 12)   # was capped at 5: a year away resolved 53 raids against 270 played out
	var r := _rng("stronghold_catch", _day + days)
	var hit := 0
	for i in n:
		var t := _pick_target(r, _pick_origin(r), ctx)
		if t.is_empty():
			continue
		var band := {"id": -1, "kind": RAIDER_KINDS[r.randi() % RAIDER_KINDS.size()], "strength": r.randi_range(8, 40), "target": t, "target_pos": t["pos"], "pos": t["pos"], "origin": t["pos"]}
		_strike(band, ctx)
		hit += 1
	if hit > 0:
		out.append("Raiders struck %d places while you were away." % hit)
	_day += days
	return out


# --- raids ----------------------------------------------------------------------

func _pick_origin(r: RandomNumberGenerator) -> Dictionary:
	var origins: Array = []
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) in ["bandit_camp", "rift", "rift_outpost", "tower_ruin"]:
			origins.append(s)
	var kind: String = RAIDER_KINDS[r.randi() % RAIDER_KINDS.size()]
	var pos := Vector2(r.randf_range(-1800, 1800), r.randf_range(-1800, 1800))
	if not origins.is_empty():
		pos = (origins[r.randi() % origins.size()] as Dictionary)["pos"]
	return {"pos": pos, "kind": kind}


func _road_access(pos: Vector2) -> float:
	# 1 = on a road, decays with distance (raiders like reachable prey)
	return clampf(1.0 - WorldGen.road_distance(pos.x, pos.y) / 400.0, 0.1, 1.0)


func _pick_target(r: RandomNumberGenerator, origin: Dictionary, _ctx: Dictionary) -> Dictionary:
	var best := {}
	var bs := -1.0
	var opos: Vector2 = origin["pos"]
	for s: Dictionary in _sh:
		if s["owner"] == "independent" and origin["kind"] == "monsters":
			continue
		var d: float = opos.distance_to(s["pos"])
		var sc := (float(s["wealth"]) + float(s["supply"]) * 0.5) / (float(s["garrison"]) + 8.0) * _road_access(s["pos"]) * (1.0 - clampf(d / 4000.0, 0.0, 0.8)) * r.randf_range(0.8, 1.2)
		if sc > bs:
			bs = sc
			best = {"type": "stronghold", "id": int(s["id"]), "name": String(s["name"]), "pos": s["pos"]}
	for s: Dictionary in WorldGen.settlements:
		var garrison := 6 if s["kind"] == "village" else (14 if s["kind"] in ["town", "frontier_town"] else 60)
		var wealth := float(s["population"]) / 5.0
		var d2: float = opos.distance_to(s["pos"])
		var sc2 := wealth / (garrison + 8.0) * _road_access(s["pos"]) * (1.0 - clampf(d2 / 4000.0, 0.0, 0.8)) * r.randf_range(0.8, 1.2)
		if sc2 > bs:
			bs = sc2
			best = {"type": "settlement", "id": int(s["id"]), "name": String(s["name"]), "pos": s["pos"]}
	return best


func _spawn_raid(r: RandomNumberGenerator, day: int, ctx: Dictionary) -> String:
	var origin := _pick_origin(r)
	var t := _pick_target(r, origin, ctx)
	if t.is_empty():
		return ""
	var rd := {"id": _next_raid, "kind": origin["kind"], "strength": r.randi_range(8, 45), "origin": origin["pos"], "pos": origin["pos"],
		"target": t, "target_pos": t["pos"], "phase": "travel", "day": day, "loot": 0}
	_next_raid += 1
	_raids.append(rd)
	# rumour only if the player is near enough to hear of it
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 and (pp as Vector2).distance_to(t["pos"]) < 800.0:
		return "Word spreads of %s massing against %s." % [String(origin["kind"]).replace("_", " "), t["name"]]
	return ""


func _strike(rd: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	var t: Dictionary = rd["target"]
	var strength := float(rd["strength"])
	var defence := 6.0
	var wealth := 40.0
	var name_s := String(t.get("name", "the target"))
	if t["type"] == "stronghold" and int(t["id"]) < _sh.size():
		var s: Dictionary = _sh[int(t["id"])]
		defence = float(s["garrison"]) * (1.4 if s["kind"] in ["fort", "watchfort"] else 1.0)
		wealth = float(s["wealth"])
	elif t["type"] == "settlement":
		defence = 6.0 + float(WorldGen.settlements[int(t["id"])]["population"]) / 60.0
		wealth = float(WorldGen.settlements[int(t["id"])]["population"]) / 5.0
	var r := _rng("raid_strike", int(rd.get("day", _day)), int(rd["id"]) * 31 + int(strength))
	var roll := strength * r.randf_range(0.7, 1.3) - defence * r.randf_range(0.7, 1.3)
	var res := {"day": _day, "target": name_s, "kind": rd["kind"], "pos": rd["target_pos"], "success": roll > 0.0, "loot": 0, "raider_losses": 0, "defender_losses": 0}
	if roll > 0.0:
		res["loot"] = int(wealth * clampf(roll / maxf(strength, 1.0), 0.1, 0.5))
		res["defender_losses"] = mini(int(defence * 0.5), int(strength * 0.4))
		res["raider_losses"] = int(strength * 0.15)
		rd["phase"] = "return" if rd["id"] > 0 else "done"
		rd["loot"] = res["loot"]
		out.append("%s raiders looted %s (%d gold)." % [String(rd["kind"]).capitalize().replace("_", " "), name_s, int(res["loot"])])
	else:
		res["raider_losses"] = int(strength * 0.6)
		rd["phase"] = "done"
		out.append("The raid on %s was beaten back." % name_s)
	if t["type"] == "stronghold" and int(t["id"]) < _sh.size():
		var s2: Dictionary = _sh[int(t["id"])]
		s2["garrison"] = maxi(0, int(s2["garrison"]) - int(res["defender_losses"]))
		s2["wealth"] = maxi(0, int(s2["wealth"]) - int(res["loot"]))
		s2["supply"] = maxi(0, int(s2["supply"]) - int(res["loot"]) / 2)
	rd["strength"] = maxi(1, int(strength) - int(res["raider_losses"]))
	_results.append(res)
	if _results.size() > RESULTS_MAX:
		_results.pop_front()
	_remember(res)
	return out


## Territory memory (R§34) and settlement aftermath: raids are remembered by
## the nearest settlement's region (land.gd keys regions by settlement id).
func _remember(res: Dictionary) -> void:
	if hub == null or WorldGen.settlements.is_empty():
		return
	var pos: Vector2 = res["pos"]
	var sid := 0
	var best := INF
	for st in WorldGen.settlements:
		var d: float = pos.distance_squared_to(st["pos"])
		if d < best:
			best = d
			sid = int(st["id"])
	var land: RefCounted = hub.mod("land")
	if land != null and land.has_method("remember"):
		if res["success"]:
			land.call("remember", sid, "neglect", clampf(float(res["loot"]) / 40.0, 0.1, 1.0), _day)   # was loot/20 up to 2.0: raids alone drove loyalty to ~0
		else:
			land.call("remember", sid, "fair_rule", 0.5, _day)
	var settlements: RefCounted = hub.mod("settlements")
	if res["success"] and settlements != null and settlements.has_method("raid_aftermath"):
		settlements.call("raid_aftermath", sid, clampf(float(res["loot"]) / 40.0, 0.2, 1.0))


# --- regional difficulty (R§33) ---------------------------------------------------

## `region` may be a settlement index (int), a settlement name (String) or a Vector2.
func recommended_preparation(region: Variant, ctx: Dictionary = {}) -> Dictionary:
	_ensure()
	var pos := Vector2.ZERO
	var label := "the wilds"
	if region is Vector2:
		pos = region
	elif region is int and int(region) >= 0 and int(region) < WorldGen.settlements.size():
		pos = WorldGen.settlements[int(region)]["pos"]
		label = String(WorldGen.settlements[int(region)]["name"])
	elif region is String:
		for s: Dictionary in WorldGen.settlements:
			if String(s["name"]) == region:
				pos = s["pos"]
				label = String(s["name"])
	var lines: Array[String] = []
	var danger := _base_threat(pos, ctx)
	var garrison := 0
	var bandit := 0.0
	for s: Dictionary in _sh:
		if (s["pos"] as Vector2).distance_to(pos) < 500.0:
			garrison += int(s["garrison"])
	for rs: Dictionary in _results:
		if (rs["pos"] as Vector2).distance_to(pos) < 600.0:
			bandit += 1.0
	for rd: Dictionary in _raids:
		if (rd["target_pos"] as Vector2).distance_to(pos) < 600.0:
			bandit += 1.5
	if danger >= 60.0:
		lines.append("Heavy monster activity")
	elif danger >= 30.0:
		lines.append("Moderate monster activity")
	else:
		lines.append("Quiet wilds")
	if bandit >= 3.0:
		lines.append("Frequent raiders")
	elif bandit >= 1.0:
		lines.append("Occasional raiders")
	if garrison >= 80:
		lines.append("Well garrisoned road")
	elif garrison == 0:
		lines.append("No garrison nearby: travel with escort")
	else:
		lines.append("Thin garrison")
	if String(ctx.get("season", "")) == "winter":
		lines.append("Cold weather equipment recommended")
	var score := clampf(danger / 100.0 + bandit * 0.06 - float(garrison) / 400.0, 0.0, 1.0)
	return {"region": label, "danger": snappedf(score, 0.01), "lines": lines, "text": ", ".join(lines) + "."}


func _base_threat(pos: Vector2, ctx: Dictionary) -> float:
	var fn: Variant = ctx.get("threat_at")
	if fn is Callable and (fn as Callable).is_valid():
		var v: Variant = (fn as Callable).call(pos)
		return float(v.get("total", 10.0)) if v is Dictionary else float(v)
	var life: Variant = ctx.get("life")
	if life != null and life.has_method("threat_at"):
		var v2: Variant = life.threat_at(pos)
		return float(v2.get("total", 10.0)) if v2 is Dictionary else float(v2)
	var home := Vector2.ZERO if WorldGen.settlements.is_empty() else WorldGen.settlements[0]["pos"] as Vector2
	return clampf(pos.distance_to(home) / 30.0 + WorldGen.forest_density(pos.x, pos.y) * 20.0, 0.0, 100.0)


# --- persistence ---------------------------------------------------------------

func serialize() -> Dictionary:
	_ensure()
	var sh: Array = []
	for s: Dictionary in _sh:
		var c := s.duplicate(true)
		c["pos"] = [s["pos"].x, s["pos"].y]
		sh.append(c)
	var rs: Array = []
	for rd: Dictionary in _raids:
		rs.append(_raid_out(rd))
	var res: Array = []
	for x: Dictionary in _results:
		var c2 := x.duplicate(true)
		c2["pos"] = [x["pos"].x, x["pos"].y]
		res.append(c2)
	return {"sh": sh, "built": _built, "raids": rs, "results": res, "next_raid": _next_raid, "day": _day, "hours": _hours}


static func _raid_out(rd: Dictionary) -> Dictionary:
	var c := rd.duplicate(true)
	for k: String in ["origin", "pos", "target_pos"]:
		c[k] = [rd[k].x, rd[k].y]
	c["target"]["pos"] = [rd["target"]["pos"].x, rd["target"]["pos"].y]
	return c


static func _v(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func deserialize(d: Dictionary) -> void:
	if not d.has("sh"):
		return
	_sh.clear()
	for s: Dictionary in d["sh"]:
		var c := s.duplicate(true)
		c["pos"] = _v(s["pos"])
		for k: String in ["id", "garrison", "garrison_max", "toll", "supply", "wealth"]:
			c[k] = int(c[k])
		var routes: Array = []
		for rt: Array in c["routes"]:
			routes.append([int(rt[0]), int(rt[1])])
		c["routes"] = routes
		if not c["siege"].is_empty():
			c["siege"]["strength"] = int(c["siege"]["strength"])
			c["siege"]["day"] = int(c["siege"]["day"])
		_sh.append(c)
	_built = bool(d.get("built", false))
	_raids.clear()
	for rd: Dictionary in d.get("raids", []):
		var c2 := rd.duplicate(true)
		for k: String in ["origin", "pos", "target_pos"]:
			c2[k] = _v(rd[k])
		c2["target"]["pos"] = _v(rd["target"]["pos"])
		c2["target"]["id"] = int(c2["target"]["id"])
		for k2: String in ["id", "strength", "day", "loot"]:
			c2[k2] = int(c2[k2])
		_raids.append(c2)
	_results.clear()
	for x: Dictionary in d.get("results", []):
		var c3 := x.duplicate(true)
		c3["pos"] = _v(x["pos"])
		for k3: String in ["day", "loot", "raider_losses", "defender_losses"]:
			c3[k3] = int(c3[k3])
		_results.append(c3)
	_next_raid = int(d.get("next_raid", 1))
	_day = int(d.get("day", 0))
	_hours = int(d.get("hours", 0))
