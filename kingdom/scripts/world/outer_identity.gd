extends RefCounted
## Rising Ashes identity outside the walls (docs/design/VERTICAL_SLICE.md P1): the land beyond the last runestone looks
## different from the land inside the wards. Preload; no class_name.
##
## TWO JOBS in one file, like region_caves.gd:
##  1. `plan(seed, taken)` (static) appends site entries (kind "roadside", so Discovery never lists them and the world
##     lint treats them as road furniture) on its own RNG stream, and thins out roadside farms and fields beyond the wards.
##     One hook line at the very end of RegionSites.plan:
##       out.append_array(preload("res://scripts/world/outer_identity.gd").plan(seed_value, out))
##  2. `coverage(p)` is the plan-time protection map (the same road stones Frontier seeds), also used by the view
##     (outer_identity_view.gd: boundary ground tint, Soulbeast tracks) which must stay out of this file.
##
## Where the ward ends: every road is scanned for stretches of >= MIN_GAP metres below PROTECTED coverage. At the edge of
## each one a ward marker pair and a signpost stand on the protected side; some boundaries add a patrol checkpoint, a
## wayside shrine, and on the unprotected side a monster warning post, a cracked old runestone and an abandoned cart.
## Waiting caravans stand outside the town gates, and Rift traders keep a stall at the Rift outposts and on the road
## leaving the settlement nearest the Rift.
##
## Site extras: site["ident"] = ward_marker | checkpoint | shrine | warning_post | cracked_stone | abandoned_cart |
## caravan | rift_trader (QA, tests, quests). Caravans carry "escort": true (hook for escort quests), Rift traders
## "rift_trader": true.

const PROTECTED := 0.20       ## coverage at or above this reads as "inside the wards"
const MIN_GAP := 60.0         ## a stretch of unprotected road shorter than this is not a boundary
const STEP := 10.0
const ROAD_HALF := {"kingdom": 3.5, "rural": 2.25, "frontier": 1.25}
const MAX_PER_ROAD := 4
const MAX_SITES := 190
## Chance a roadside farm or field beyond the wards is dropped ("fewer farms beyond").
const FARM_THIN := 0.8

static var _net: RARunestoneNetwork = null
static var _net_roads := -1


## Plan-time stone network: the home ring and the road stones (what Frontier seeds), without simulation state.
static func network() -> RARunestoneNetwork:
	if _net != null and _net_roads == WorldGen.roads.size() and not WorldGen.settlements.is_empty():
		return _net
	var net := RARunestoneNetwork.new()
	if not WorldGen.settlements.is_empty():
		var home: Dictionary = WorldGen.settlements[0]
		var c: Vector2 = home["pos"]
		var r: float = home["radius"]
		for i in 6:
			var ang := TAU * i / 6.0 + 0.3
			net.add_stone(c + Vector2(cos(ang), sin(ang)) * (r + 18.0), r * 1.45, 0, "Ring %d" % i)
		var gates := WorldGen.gate_angles(home)
		if not gates.is_empty():
			var dir := Vector2(cos(gates[0]), sin(gates[0]))
			for k in 3:
				net.add_stone(c + dir * (r + 140.0 + k * 170.0), 110.0, 0, "Waystone %d" % k)
	net.seed_road_stones()
	_net = net
	_net_roads = WorldGen.roads.size()
	return net


## Ward protection 0..1 at a world point (the live network once Frontier exists, else the plan-time one).
static func coverage(p: Vector2) -> float:
	var live: Variant = Engine.get_main_loop().root.get_node_or_null("/root/Frontier") if Engine.get_main_loop() is SceneTree else null
	if live != null and live.get("runestones") != null:
		return float(live.runestones.coverage(p))
	return network().coverage(p)


## Plan-time coverage only (deterministic: the same for every seed-1066 world no matter the game's runestone state).
static func plan_coverage(p: Vector2) -> float:
	return network().coverage(p)


static func _ok(p: Vector2, rad: float, taken: Array[Dictionary], placed: Array[Dictionary], need_dry_treeless := true) -> bool:
	if absf(p.x) > WorldGen.WORLD_HALF - 300.0 or absf(p.y) > WorldGen.WORLD_HALF - 300.0:
		return false
	if WorldGen.near_water(p.x, p.y, rad + 2.0):
		return false
	if need_dry_treeless and WorldGen.forest_density(p.x, p.y) > 0.0:
		return false
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) < float(s["radius"]) * 1.15 + rad:
			return false
	for g in WorldGen.camp_grounds:
		if p.distance_to(g["pos"]) < float(g["radius"]) * 1.6 + rad:
			return false
	for lst: Array[Dictionary] in [taken, placed]:
		for t in lst:
			var reach := maxf(float(t.get("clear", 0.0)), 2.0) * 0.8 + 2.0
			if p.distance_to(t["pos"]) < rad + reach:
				return false
	# Level enough that the lowest-corner snap never buries or hangs a prop.
	var e := 2.5
	var dx := WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y)
	var dz := WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e) < 0.3


static func _site(name: String, ident: String, pos: Vector2, yaw: float, clear := 0.0) -> Dictionary:
	return {"name": name, "kind": "roadside", "pos": pos, "yaw": yaw, "clear": clear, "flatten": false,
		"parts": [], "lights": [], "ident": ident}


static func _part(site: Dictionary, asset: String, off: Vector2, yaw := 0.0, collide := false) -> void:
	site["parts"].append([asset, off, yaw, collide])


static func _yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


static func _side(dir: Vector2) -> Vector2:
	return Vector2(dir.y, -dir.x)


## Roadside sites facing the road from `sgn` side of it. `dir` is the road direction, `base` a point ON the road centre line.
## Returns the site position and its yaw (front = toward the road); local x then runs along the road.
static func _anchor(base: Vector2, dir: Vector2, along: float, lateral: float, sgn: float) -> Array:
	var p := base + dir * along + _side(dir) * sgn * lateral
	return [p, _yaw(-_side(dir) * sgn)]


static func plan(seed_value: int, taken: Array[Dictionary]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 97 + 41
	var out: Array[Dictionary] = []
	var placed: Array[Dictionary] = []
	_thin_farms(taken, rng)
	# --- boundaries ---
	for ri in WorldGen.roads.size():
		var road: Vector2i = WorldGen.roads[ri]
		var a: Vector2 = WorldGen.settlements[road.x]["pos"]
		var b: Vector2 = WorldGen.settlements[road.y]["pos"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var tier := WorldGen.road_tier(road.x, road.y)
		var half: float = ROAD_HALF[tier]
		var ra: float = float(WorldGen.settlements[road.x]["radius"]) * 1.25
		var rb: float = float(WorldGen.settlements[road.y]["radius"]) * 1.25
		# Unprotected runs [t0, t1] along the road.
		var runs: Array = []
		var t := ra
		var run_start := -1.0
		while t <= length - rb:
			var prot := plan_coverage(a + dir * t) >= PROTECTED
			if not prot and run_start < 0.0:
				run_start = t
			elif prot and run_start >= 0.0:
				if t - run_start >= MIN_GAP:
					runs.append([run_start, t])
				run_start = -1.0
			t += STEP
		if run_start >= 0.0 and (length - rb) - run_start >= MIN_GAP:
			runs.append([run_start, length - rb])
		var made := 0
		for run: Array in runs:
			if made >= MAX_PER_ROAD or out.size() >= MAX_SITES:
				break
			var t0: float = run[0]
			var t1: float = run[1]
			# One boundary at each end of the run that has protected road next to it.
			var ends: Array = []
			if t0 > ra + STEP * 1.5:
				ends.append([t0, 1.0])       # leaving the wards toward +dir
			if t1 < length - rb - STEP * 1.5:
				ends.append([t1, -1.0])      # coming back into the wards (seen from the unprotected side)
			if t0 <= ra + STEP * 1.5 and t1 - t0 >= 120.0:
				ends.append([ra + 24.0, 1.0])  # no ward at all outside this gate (frontier roads)
			for e: Array in ends:
				if made >= MAX_PER_ROAD or out.size() >= MAX_SITES:
					break
				_boundary(out, placed, taken, rng, a, dir, float(e[0]), float(e[1]), tier, half, t1 - t0, ri, road.x if float(e[1]) > 0.0 else road.y)
				made += 1
	# --- caravans at the gates, Rift traders ---
	_caravans(out, placed, taken, rng)
	_rift_traders(out, placed, taken, rng)
	return out


## Remove roadside farms and fields standing where the wards do not reach.
static func _thin_farms(taken: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for i in range(taken.size() - 1, -1, -1):
		var s := taken[i]
		if String(s.get("kind", "")) != "roadside":
			continue
		var nm := String(s.get("name", ""))
		if nm != "Roadside Farm" and nm != "Wheat Field":
			continue
		if plan_coverage(s["pos"]) < 0.08 and rng.randf() < FARM_THIN:
			taken.remove_at(i)


## The furniture of one ward boundary. `base` + `dir` * `t` is the boundary on the road centre line, `toward` = +1 when the
## unprotected road lies further along +dir, -1 when it lies back along -dir.
static func _boundary(out: Array[Dictionary], placed: Array[Dictionary], taken: Array[Dictionary], rng: RandomNumberGenerator,
		a: Vector2, dir: Vector2, t: float, toward: float, tier: String, half: float, gap: float, ri: int, town_id: int) -> void:
	var d := dir * toward                       # direction toward the unprotected side
	var bpos := a + dir * t
	var sgn := 1.0 if rng.randf() < 0.5 else -1.0
	var lat := half + 3.4
	# 1. Ward markers: a pair of standing stones either side of the road, a signpost on the protected side.
	var am := _anchor(bpos, d, 0.0, lat, sgn)
	if _ok(am[0], 3.0, taken, placed):
		var st := _site("Ward Marker", "ward_marker", am[0], am[1], 0.0)
		st["beyond"] = d            # unit vector toward the unprotected road (the view tints the ground that way)
		st["road_half"] = half
		_part(st, "road/milestone", Vector2.ZERO, 0.0, true)
		_part(st, "nature:flowers_warm", Vector2(1.3, -0.6), 0.0)
		_part(st, "nature:flowers_cool", Vector2(-1.2, -0.4), 0.0)
		# The twin across the road, local y offset negative = away from the road on the far side: place via a second part.
		_part(st, "road/milestone", Vector2(0.0, 2.0 * lat), PI, true)
		_part(st, "props/signpost", Vector2(3.4, 0.2), 0.2, true)
		st["lights"].append([Vector3(0, 1.2, 0.4), Color(0.45, 0.78, 1.0), 4.0, false])
		out.append(st)
		placed.append(st)
	# 2. Patrol checkpoint on the protected side of the road leaving the wards (most on kingdom and rural roads).
	if rng.randf() < (0.8 if tier != "frontier" else 0.4):
		var ac := _anchor(bpos, d, -22.0, half + 7.0, -sgn)
		if _ok(ac[0], 7.0, taken, placed):
			var cp := _site("Patrol Checkpoint", "checkpoint", ac[0], ac[1], 9.0)
			_part(cp, "road/checkpoint_barrier", Vector2(0, half + 7.0 - half * 0.5), 0.0, true)
			_part(cp, "ruins/campfire", Vector2(-4.2, -2.4), 0.0)
			_part(cp, "props/weapon_rack", Vector2(4.4, -2.0), 0.3)
			_part(cp, "props/crate_stack", Vector2(2.6, -3.6), 0.4)
			_part(cp, "props/barrel", Vector2(-2.4, -3.8), 0.0)
			_part(cp, "props/bench", Vector2(-4.4, -4.6), PI * 0.5)
			cp["lights"].append([Vector3(-4.2, 1.0, -2.4), Color(1.0, 0.65, 0.35), 6.0, true])
			cp["x"] = {"people": [{"look": "Guard", "at": [0.0, 1.2], "yaw": 180.0}, {"look": "Guard", "at": [3.2, -0.8], "yaw": 200.0}]}
			out.append(cp)
			placed.append(cp)
	# 3. A wayside shrine on the protected side, where travellers say a prayer before leaving the wards.
	if rng.randf() < 0.4:
		var asr := _anchor(bpos, d, -34.0, half + 4.4, sgn)
		if _ok(asr[0], 3.5, taken, placed):
			var sh := _site("Wayside Shrine", "shrine", asr[0], asr[1], 4.0)
			_part(sh, "road/wayshrine", Vector2.ZERO, 0.0, true)
			_part(sh, "nature:flowers_warm", Vector2(1.6, 0.8), 0.0)
			_part(sh, "nature:flowers_cool", Vector2(-1.5, 0.6), 0.0)
			_part(sh, "props/barrel", Vector2(2.8, -0.8), 0.0)
			sh["lights"].append([Vector3(0, 1.4, 0.3), Color(1.0, 0.75, 0.45), 4.0, true])
			out.append(sh)
			placed.append(sh)
	# 4. Beyond the wards: a monster warning post, a cracked old runestone, an abandoned cart.
	if rng.randf() < 0.75:
		var aw := _anchor(bpos, d, 16.0, half + 3.0, -sgn)
		if _ok(aw[0], 3.0, taken, placed):
			var wp := _site("Warning Post", "warning_post", aw[0], aw[1], 0.0)
			_part(wp, "props/signpost", Vector2.ZERO, 0.0, true)
			_part(wp, "ruins/goblin_totem_b", Vector2(2.6, -0.4), 0.3, true)
			for i in 3:
				_part(wp, "farm/fence_picket", Vector2(-2.2 - i * 1.6, -0.6 + i * 0.3), PI * 0.5 + 0.2 * i)
			out.append(wp)
			placed.append(wp)
	if gap >= 90.0 and rng.randf() < 0.6:
		var ak := _anchor(bpos, d, rng.randf_range(34.0, 70.0), half + rng.randf_range(5.0, 10.0), sgn)
		if _ok(ak[0], 5.0, taken, placed):
			var cs := _site("Cracked Runestone", "cracked_stone", ak[0], ak[1], 4.0)
			_part(cs, "gen:runestone@1.0", Vector2.ZERO, 0.4, true)
			_part(cs, "nature:rock_slab", Vector2(1.9, 0.9), 1.2)
			_part(cs, "nature:rock_slab", Vector2(-1.6, 1.3), 0.5)
			_part(cs, "nature:rock_medium", Vector2(-2.3, -0.2), 0.3)
			_part(cs, "nature:rock_cluster", Vector2(0.6, 2.0), 2.0)
			_part(cs, "nature:grass_tall", Vector2(-2.2, -0.4), 0.0)
			cs["lights"].append([Vector3(0, 0.9, 0.2), Color(0.35, 0.6, 0.9), 2.0, true])
			out.append(cs)
			placed.append(cs)
	if gap >= 140.0 and rng.randf() < 0.5:
		var ac2 := _anchor(bpos, d, rng.randf_range(60.0, minf(gap - 20.0, 170.0)), half + rng.randf_range(2.5, 6.0), -sgn)
		if _ok(ac2[0], 6.0, taken, placed):
			var ca := _site("Abandoned Cart", "abandoned_cart", ac2[0], ac2[1], 5.0)
			var covered := rng.randf() < 0.5
			_part(ca, "props/covered_wagon" if covered else "road/caravan_wagon", Vector2.ZERO, 0.5 + rng.randf() * 0.7, true)
			_part(ca, "props/crate", Vector2(3.4, -1.0), 0.9)
			_part(ca, "props/barrel", Vector2(-3.4, 1.2), 0.0)
			_part(ca, "props/sack_pile", Vector2(2.4, 3.0), 2.1)
			_part(ca, "nature:grass_tall", Vector2(-1.2, -2.4), 0.0)
			_part(ca, "nature:bush_dark", Vector2(4.2, 2.6), 0.4)
			out.append(ca)
			placed.append(ca)


## A caravan waits outside the gate for an escort: wagons, a fire, crates, drivers and one hired guard.
static func _caravans(out: Array[Dictionary], placed: Array[Dictionary], taken: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for s in WorldGen.settlements:
		if out.size() >= MAX_SITES + 40:
			return
		if s["kind"] == "village" and rng.randf() < 0.55:
			continue
		var gates := WorldGen.gate_angles(s)
		if gates.is_empty():
			continue
		# The gate onto the busiest road: the first (capital roads sort first by construction); rotate by town id for variety.
		var g: float = gates[int(s["id"]) % gates.size()]
		var d := Vector2(cos(g), sin(g))
		var base: Vector2 = (s["pos"] as Vector2) + d * (float(s["radius"]) * 1.1 + 48.0)
		var sgn := 1.0 if (int(s["id"]) % 2 == 0) else -1.0
		var an := _anchor(base, d, 0.0, 13.0, sgn)
		if not _ok(an[0], 9.0, taken, placed):
			an = _anchor(base, d, 0.0, 13.0, -sgn)
			if not _ok(an[0], 9.0, taken, placed):
				continue
		var site := _site("Caravan Awaiting Escort", "caravan", an[0], an[1], 11.0)
		_part(site, "road/caravan_wagon", Vector2(-5.5, 0.0), 0.15, true)
		_part(site, "props/covered_wagon", Vector2(1.0, -0.6), -0.1, true)
		_part(site, "road/caravan_wagon", Vector2(7.2, 0.3), 0.2, true)
		_part(site, "ruins/campfire", Vector2(-1.0, -5.6), 0.0)
		_part(site, "props/crate_stack", Vector2(4.2, -4.0), 0.5)
		_part(site, "props/barrel", Vector2(2.4, -5.4), 0.0)
		_part(site, "props/crate_stack", Vector2(-4.4, -4.6), 1.2)
		site["lights"].append([Vector3(-1.0, 1.0, -5.6), Color(1.0, 0.65, 0.35), 6.0, true])
		site["escort"] = true
		site["town"] = String(s["name"])
		site["x"] = {"people": [{"look": "Trader", "at": [-2.4, -4.4], "yaw": 150.0}, {"look": "Hunter", "at": [-3.8, -6.0], "yaw": 40.0},
			{"look": "Guard", "at": [5.4, -2.4], "yaw": 200.0}]}
		out.append(site)
		placed.append(site)


## Rift traders: a stall of shards, ember glass and moonpetal at every Rift outpost, and one on the road out of the
## settlement nearest the Rift.
static func _rift_traders(out: Array[Dictionary], placed: Array[Dictionary], taken: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var rift_pos := Vector2.INF
	var spots: Array = []
	for t in taken:
		if t["kind"] == "rift":
			rift_pos = t["pos"]
		elif t["kind"] == "rift_outpost":
			# Near the outpost's cleared ground: the first level, dry, treeless spot on a ring around it, facing the camp.
			var ctr: Vector2 = t["pos"]
			var found := false
			for ring: float in [float(t.get("clear", 20.0)) * 0.8 + 12.0, 34.0, 42.0, 52.0]:
				if found:
					break
				for k in 16:
					var ang := TAU * k / 16.0 + 0.4
					var q := ctr + Vector2(cos(ang), sin(ang)) * ring
					if _ok(q, 7.0, taken, placed):
						spots.append([q, _yaw(ctr - q), String(t["name"])])
						found = true
						break
	if rift_pos != Vector2.INF:
		var near: Dictionary = {}
		var bd := INF
		for s in WorldGen.settlements:
			var dd: float = (s["pos"] as Vector2).distance_to(rift_pos)
			if dd < bd:
				bd = dd
				near = s
		if not near.is_empty():
			var to := (rift_pos - (near["pos"] as Vector2)).normalized()
			var best_g := 0.0
			var best_dot := -2.0
			for g in WorldGen.gate_angles(near):
				var dot := Vector2(cos(g), sin(g)).dot(to)
				if dot > best_dot:
					best_dot = dot
					best_g = g
			if best_dot > -2.0:
				var d := Vector2(cos(best_g), sin(best_g))
				var base: Vector2 = (near["pos"] as Vector2) + d * (float(near["radius"]) * 1.1 + 95.0)
				for sg: float in [1.0, -1.0]:
					var an := _anchor(base, d, 0.0, 9.0, sg)
					spots.append([an[0], an[1], String(near["name"])])
	var done := {}
	for sp: Array in spots:
		if done.has(sp[2]) or not _ok(sp[0], 7.0, taken, placed):
			continue
		done[sp[2]] = true
		var site := _site("Rift Trader", "rift_trader", sp[0], float(sp[1]), 8.0)
		_part(site, "gen:market_stall_green@1.0", Vector2.ZERO, 0.0, true)
		_part(site, "r1:rift/crystals/scar_crystal_a@1.1", Vector2(-2.6, 1.4), 0.4)
		_part(site, "r1:rift/crystals/scar_crystal_b@0.8", Vector2(2.7, 1.2), 1.1)
		_part(site, "props/crate", Vector2(-2.4, -2.0), 0.3)
		_part(site, "props/basket_produce", Vector2(2.2, -2.2), 0.0)
		_part(site, "props/barrel", Vector2(3.8, -1.0), 0.0)
		site["lights"].append([Vector3(0.0, 1.6, 1.6), Color(0.7, 0.45, 1.0), 6.0, true])
		site["rift_trader"] = true
		site["town"] = String(sp[2])
		site["x"] = {"npcs": [{"name": "Vesh", "role": "Rift trader", "look": "Rogue_Hooded", "at": [0.0, 2.6], "yaw": 180.0,
			"greet": "Shards, ember glass, moonpetal. Nothing here was bought from anyone who is still alive to ask.",
			"lines": ["The stones along this road dim a little more every season. I price accordingly.",
				"Don't carry Rift glass past a ward at night. The stones notice.",
				"Bring me something that glows and I will not ask where you found it."],
			"trade": "Rift shards and ember glass, for those who work past the wards."}]}
		out.append(site)
		placed.append(site)
