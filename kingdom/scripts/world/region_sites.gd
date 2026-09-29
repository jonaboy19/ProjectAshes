class_name RegionSites
extends RefCounted
## Plans the places between settlements: farmsteads with a windmill outside each
## village, bridges wherever a road crosses water, Cinderpost Waystation, waystones
## along the roads, the Shrine of the Sleeping Flame, Whisper Hollow, a bandit camp
## in Duskbriar Wood, a collapsed tower, a mine in the northern hills, the frontier
## watchfort and the Rift. Pure data from the seed, computed once in WorldGen.setup
## so terrain and trees can clear and level the ground before any chunk is built.
## RegionDressing gives the sites bodies near the player.
##
## Site: {id, name, pos: Vector2, yaw, clear: float (tree-free radius, 0 = none),
##        flatten: bool, parts: [[asset, Vector2 local offset, yaw, collide]],
##        lights: [[Vector3 local, Color, range, flicker]], kind}
## Local offsets: +y is the site's front (the way it faces), +x its right.

const REGION := "res://data/world/first_region.json"

static var _rng := RandomNumberGenerator.new()


static func plan(seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	_rng.seed = seed_value * 17 + 3
	var places := _places()
	var out: Array[Dictionary] = []
	for s in WorldGen.settlements:
		# Farmland rings every settlement people actually live in: one farm
		# outside a village, town or frontier town, a ring of 2-3 around the
		# capital's suburbs.
		var count := 3 if s["kind"] == "castle" else (1 if s["kind"] in ["village", "town", "frontier_town"] else 0)
		if WorldGen.core_settlement_count > 0 and int(s["id"]) >= WorldGen.core_settlement_count:
			count = 0     # the new land's farms are planned last, in _outer_sites()
		for i in count:
			var farm := _farmstead(s, rng, out)
			if not farm.is_empty():
				out.append(farm)
	out.append_array(_bridges())
	if places.has("cinderpost_waystation"):
		out.append(_waystation(places["cinderpost_waystation"]))
	out.append_array(_waystones(rng))
	if places.has("shrine_of_the_sleeping_flame"):
		out.append(_shrine(places["shrine_of_the_sleeping_flame"]))
	if places.has("whisper_hollow"):
		out.append(_hollow(places["whisper_hollow"]))
	if places.has("duskbriar_wood"):
		out.append(_bandit_camp(places["duskbriar_wood"], rng, out))
	var tower := _collapsed_tower(rng, out)
	if not tower.is_empty():
		out.append(tower)
	var mine := _mine(out)
	if not mine.is_empty():
		out.append(mine)
	out.append(_watchfort(places, out))
	out.append_array(_forts(rng, out))
	var rift := _rift(out)
	out.append(rift)
	var outpost := _rift_outpost(rift, out, rng)
	if not outpost.is_empty():
		out.append(outpost)
	# The new land (8 x 8 km) is planned after the valley, on its own RNG stream, so every
	# site of the original valley keeps its position and id.
	if WorldGen.core_settlement_count > 0:
		var rng_o := RandomNumberGenerator.new()
		rng_o.seed = seed_value * 53 + 19
		_outer_sites(out, rng_o, WorldGen.core_settlement_count)
	# Last, so every id above stays where it was: the academy takes what ground is left.
	var academy := _academy(out)
	if not academy.is_empty():
		out.append(academy)
	for i in out.size():
		out[i]["id"] = i
	return out


static func _places() -> Dictionary:
	var by_id := {}
	if not FileAccess.file_exists(REGION):
		return by_id
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION))
	if not data is Dictionary:
		return by_id
	for pl: Dictionary in data.get("places", []):
		var arr: Array = pl.get("pos", [0, 0])
		var d := pl.duplicate()
		d["pos"] = Vector2(float(arr[0]), float(arr[1]))
		by_id[String(pl.get("id", ""))] = d
	return by_id


static func _site(name: String, kind: String, pos: Vector2, yaw: float, clear := 0.0, flatten := false) -> Dictionary:
	return {"name": name, "kind": kind, "pos": pos, "yaw": yaw, "clear": clear, "flatten": flatten,
		"parts": [], "lights": []}


static func _part(site: Dictionary, asset: String, off: Vector2, yaw := 0.0, collide := false) -> void:
	site["parts"].append([asset, off, yaw, collide])


## Ground a site may use: dry, off the roads, clear of settlements, camps and other sites.
static func _free(p: Vector2, r: float, taken: Array[Dictionary], road_gap := 10.0) -> bool:
	if absf(p.x) > WorldGen.WORLD_HALF - 300.0 or absf(p.y) > WorldGen.WORLD_HALF - 300.0:
		return false
	if WorldGen.near_water(p.x, p.y, r + 4.0) or WorldGen.road_distance(p.x, p.y) < r + road_gap:
		return false
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) < float(s["radius"]) * 1.15 + r:
			return false
	for g in WorldGen.camp_grounds:
		if p.distance_to(g["pos"]) < float(g["radius"]) * 1.6 + r:
			return false
	for t in taken:
		if p.distance_to(t["pos"]) < r + maxf(float(t["clear"]), 12.0) + 6.0:
			return false
	return true


static func _slope(p: Vector2) -> float:
	var e := 3.0
	var dx := WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y)
	var dz := WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e)


static func _downhill(p: Vector2) -> Vector2:
	var e := 4.0
	var g := Vector2(WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y),
		WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e))
	return -g.normalized() if g.length() > 0.001 else Vector2(0, 1)


static func _yaw_to(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


# --- Farmsteads -----------------------------------------------------------------

## A working farm on a gentle slope just outside a village: windmill on the rise,
## barn, granary, coop, sty, hay wagon, a wheat and a cabbage plot, a scarecrow and
## rail fencing along the front. Faces the village.
static func _farmstead(s: Dictionary, rng: RandomNumberGenerator, taken: Array[Dictionary]) -> Dictionary:
	var c: Vector2 = s["pos"]
	var r: float = s["radius"]
	var gates := WorldGen.gate_angles(s)
	var best := Vector2.INF
	var best_score := INF
	for i in 24:
		var a := TAU * i / 24.0 + rng.randf() * 0.1
		var gate_gap := PI
		for g in gates:
			gate_gap = minf(gate_gap, absf(angle_difference(a, g)))
		if gate_gap < 0.45:
			continue
		var p := c + Vector2(cos(a), sin(a)) * (r * 1.3 + 30.0)
		if not _free(p, 26.0, taken, 6.0):
			continue
		var score := _slope(p) * 10.0 + rng.randf() * 0.5 - gate_gap * 0.2
		if score < best_score:
			best_score = score
			best = p
	if best == Vector2.INF:
		return {}
	var face := (c - best).normalized()
	var site := _site(s["name"] + " Farm", "farm", best, _yaw_to(face), 30.0, true)
	_part(site, "farm/windmill", Vector2(-14, -14), 0.3, true)
	_part(site, "farm/barn", Vector2(9, -8), PI * 0.5, true)
	_part(site, "farm/granary", Vector2(0, -12), 0.0, true)
	_part(site, "farm/chicken_coop", Vector2(16, 3), -PI * 0.5, true)
	_part(site, "farm/pig_sty", Vector2(-4, -2), 0.0, true)
	_part(site, "farm/hay_wagon", Vector2(3, -2), 1.9, true)
	_part(site, "props/hay_bales", Vector2(12, 1), 0.4)
	_part(site, "props/woodpile", Vector2(4, -16), 0.0)
	_part(site, "props/water_trough", Vector2(-9, -3), PI * 0.5)
	for row in 3:
		for col in 3:
			_part(site, "farm/crop_wheat", Vector2(-20 + col * 4.1, 4 + row * 4.1), 0.0)
			_part(site, "farm/crop_cabbage", Vector2(8 + col * 4.1, 8 + row * 4.1), 0.0)
	_part(site, "farm/scarecrow", Vector2(-16, 8.5), 0.4)
	for i in 8:
		_part(site, "farm/fence_rail", Vector2(-22.5 + i * 3.2, 17.5), 0.0)
	_part(site, "farm/fence_gate", Vector2(4.2, 17.5), 0.0)
	for i in 4:
		_part(site, "farm/fence_rail", Vector2(6.8 + i * 3.2, 17.5), 0.0)
	return site


# --- Roads ----------------------------------------------------------------------

## Wherever a road crosses a river or the lake's edge, a bridge spanning the wet
## stretch: stone over wide water, timber over narrow.
static func _bridges(outer := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in WorldGen.roads:
		if _is_outer_road(road) != outer:
			continue
		var a: Vector2 = WorldGen.settlements[road.x]["pos"]
		var b: Vector2 = WorldGen.settlements[road.y]["pos"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var t := 0.0
		var wet_from := -1.0
		while t <= length:
			var p := a + dir * t
			var wet := WorldGen.is_water(p.x, p.y)
			if wet and wet_from < 0.0:
				wet_from = t
			elif not wet and wet_from >= 0.0:
				var span := t - wet_from
				if span < 30.0:
					var mid := a + dir * (wet_from + span * 0.5)
					var bank_a := a + dir * (wet_from - 3.0)
					var bank_b := a + dir * (t + 3.0)
					var site := _site("Bridge", "bridge", mid, _yaw_to(dir))
					site["span"] = span + 6.0
					site["deck"] = maxf(WorldGen.height(bank_a.x, bank_a.y), WorldGen.height(bank_b.x, bank_b.y))
					site["asset"] = "road/bridge_stone" if span > 7.0 else "road/bridge_wood"
					out.append(site)
				wet_from = -1.0
			t += 1.0
	return out


## Cinderpost Waystation: a walled halfway post on the King's Ember Road with a
## bunkhouse inn, stable trough, notice board, patrol booth and a parked caravan.
static func _waystation(pl: Dictionary) -> Dictionary:
	var p: Vector2 = pl["pos"]
	var road_dir := _nearest_road_dir(p)
	var side := Vector2(road_dir.y, -road_dir.x)
	var ground := p + side * 18.0
	var site := _site("Cinderpost Waystation", "waystation", ground, _yaw_to(-side), 22.0, true)
	_part(site, "road/roadside_inn", Vector2(0, -3), 0.0, true)
	_part(site, "road/toll_booth", Vector2(-11, 9), 0.0, true)
	_part(site, "road/checkpoint_barrier", Vector2(-11, 14.5), 0.0)
	_part(site, "road/caravan_wagon", Vector2(11, 8), PI * 0.5 + 0.2, true)
	_part(site, "props/water_trough", Vector2(7, 3), 0.0)
	_part(site, "props/notice_board", Vector2(-6, 8), 0.0)
	_part(site, "props/lamp_post", Vector2(-3.5, 9), 0.0)
	_part(site, "props/lamp_post", Vector2(3.5, 9), 0.0)
	_part(site, "props/crate_stack", Vector2(9, -4), 0.3)
	_part(site, "props/sack_pile", Vector2(11, -2), 0.0)
	_part(site, "props/hay_bales", Vector2(-10, -4), 0.2)
	for i in 5:
		_part(site, "ruins/bandit_palisade", Vector2(-16 + i * 4.0, -12), 0.0, true)
	for i in 4:
		_part(site, "ruins/bandit_palisade", Vector2(-18, -10 + i * 4.0), PI * 0.5, true)
		_part(site, "ruins/bandit_palisade", Vector2(18, -10 + i * 4.0), PI * 0.5, true)
	site["lights"].append([Vector3(-3.5, 3.2, 9), Color(1.0, 0.72, 0.4), 8.0, false])
	return site


## A waystone every ~140 m along each road, alternating sides, with a small
## wayshrine at road midpoints.
static func _waystones(rng: RandomNumberGenerator, outer := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in WorldGen.roads:
		if _is_outer_road(road) != outer:
			continue
		var a: Vector2 = WorldGen.settlements[road.x]["pos"]
		var b: Vector2 = WorldGen.settlements[road.y]["pos"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var side := Vector2(dir.y, -dir.x)
		var ra: float = WorldGen.settlements[road.x]["radius"] * 1.3
		var rb: float = WorldGen.settlements[road.y]["radius"] * 1.3
		var t := ra + 40.0
		var flip := 1.0
		while t < length - rb - 20.0:
			var p := a + dir * t + side * 7.0 * flip   # clear of even the broad gate roads
			if not WorldGen.near_water(p.x, p.y, 3.0):
				var st := _site("Waystone", "waystone", p, _yaw_to(-side * flip))
				_part(st, "road/milestone", Vector2.ZERO, 0.0, true)
				out.append(st)
			flip = -flip
			t += 140.0 + rng.randf_range(-15.0, 15.0)
		if length > 380.0:
			var m := a + dir * length * 0.5 - side * 7.0
			if not WorldGen.near_water(m.x, m.y, 4.0):
				var ws := _site("Wayshrine", "wayshrine", m, _yaw_to(side), 5.0, false)
				_part(ws, "road/wayshrine", Vector2.ZERO, 0.0, true)
				_part(ws, "nature:flowers_warm", Vector2(1.4, 0.6), 0.0)
				_part(ws, "nature:flowers_cool", Vector2(-1.3, 0.4), 0.0)
				ws["lights"].append([Vector3(0, 1.4, 0.3), Color(1.0, 0.75, 0.45), 4.0, true])
				out.append(ws)
	return out


static func _nearest_road_dir(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(1, 0)
	for road in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[road.x]["pos"]
		var b: Vector2 = WorldGen.settlements[road.y]["pos"]
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d < best:
			best = d
			dir = (b - a).normalized()
	return dir


# --- Hidden and wild places -----------------------------------------------------

## Broken pillars and a cold brazier on the hilltop west of the Ashrun
## (hidden trigger ember_in_the_ruins).
static func _shrine(pl: Dictionary) -> Dictionary:
	var p: Vector2 = pl["pos"]
	var site := _site(pl.get("name", "Shrine"), "shrine", p, _yaw_to(-p.normalized()), 16.0, true)
	_part(site, "ruins/overgrown_shrine", Vector2.ZERO, 0.0, true)
	_part(site, "nature:boulder_large", Vector2(7, -3), 0.7, true)
	_part(site, "nature:rock_slab", Vector2(-6, 4), 1.9)
	_part(site, "nature:rock_medium", Vector2(5, 6), 0.4)
	_part(site, "nature:log_mossy", Vector2(-7, -5), 1.1)
	_part(site, "nature:stump_mossy", Vector2(9, 3), 0.0)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		_part(site, "nature:fern_a" if i % 2 == 0 else "nature:grass_tall", Vector2(cos(a), sin(a)) * 5.5, a)
	return site


## A mossy dell on the Ashrun below the Mere: an ancient snag over mossy logs and ferns.
static func _hollow(pl: Dictionary) -> Dictionary:
	var p: Vector2 = pl["pos"]
	var site := _site(pl.get("name", "Hollow"), "hollow", p, 0.0, 12.0, false)
	_part(site, "nature:dark_oak", Vector2(0, -2), 0.5, true)
	_part(site, "nature:log_mossy", Vector2(4, 2), 0.9)
	_part(site, "nature:log_branchy", Vector2(-4, 3), 2.4)
	_part(site, "nature:stump_broken", Vector2(-3, -5), 0.0)
	_part(site, "nature:boulder_large", Vector2(5, -4), 2.0, true)
	for i in 7:
		var a := TAU * i / 7.0
		_part(site, "nature:fern_a" if i % 2 == 0 else "nature:fern_b", Vector2(cos(a), sin(a)) * _rng.randf_range(3.0, 6.0), a)
	site["lights"].append([Vector3(0, 0.6, 1.0), Color(0.55, 0.9, 0.8), 5.0, true])
	return site


## Outlaws squatting deep in Duskbriar, well away from the warren and the road:
## tents and a lean-to around a campfire behind a broken palisade.
static func _bandit_camp(pl: Dictionary, rng: RandomNumberGenerator, taken: Array[Dictionary], camp_name := "Bandit Camp") -> Dictionary:
	var c: Vector2 = pl["pos"]
	var r: float = float(pl.get("radius", 300.0))
	var pos := c
	for i in 40:
		var a := rng.randf() * TAU
		var q := c + Vector2(cos(a), sin(a)) * rng.randf_range(r * 0.2, r * 0.6)
		if _free(q, 18.0, taken, 50.0) and _slope(q) < 0.25:
			pos = q
			break
	var site := _site(camp_name, "bandit_camp", pos, rng.randf() * TAU, 16.0, true)
	_part(site, "ruins/campfire", Vector2.ZERO, 0.0)
	_part(site, "ruins/bandit_tent", Vector2(-6, -4), 0.5, true)
	_part(site, "ruins/bandit_tent", Vector2(5, -5), -0.6, true)
	_part(site, "ruins/bandit_lean_to", Vector2(-6, 4), 2.2, true)
	_part(site, "ruins/bandit_stash", Vector2(6, 3), -2.0, true)
	_part(site, "props/crate", Vector2(7.5, 5), 0.3)
	_part(site, "props/barrel", Vector2(4, 6), 0.0)
	_part(site, "props/weapon_rack", Vector2(0, -8), 0.0)
	for i in 6:
		var a := TAU * i / 8.0 + 1.2
		_part(site, "ruins/bandit_palisade", Vector2(cos(a), sin(a)) * 12.0, -a + PI * 0.5, true)
	site["lights"].append([Vector3(0, 0.8, 0), Color(1.0, 0.55, 0.25), 11.0, true])
	return site


## The shell of an old watchtower on a knoll west of Ashford, toward the Ashrun.
static func _collapsed_tower(rng: RandomNumberGenerator, taken: Array[Dictionary]) -> Dictionary:
	var best := Vector2.INF
	var best_h := -INF
	for i in 60:
		var a := rng.randf_range(2.3, 3.5)
		var q := Vector2(cos(a), sin(a)) * rng.randf_range(160.0, 320.0)
		if not _free(q, 14.0, taken, 20.0):
			continue
		var h := WorldGen.height(q.x, q.y)
		if h > best_h:
			best_h = h
			best = q
	if best == Vector2.INF:
		return {}
	var site := _site("Old Watchtower", "tower_ruin", best, rng.randf() * TAU, 14.0, true)
	_part(site, "ruins/collapsed_tower", Vector2.ZERO, 0.0, true)
	_part(site, "nature:rock_cluster", Vector2(8, 3), 0.5)
	_part(site, "nature:boulder_large", Vector2(-7, 6), 1.3, true)
	_part(site, "nature:bush_dark", Vector2(-6, -6), 0.0)
	_part(site, "nature:bush_berry", Vector2(7, -5), 0.0)
	return site


## Mine in the northern hills: the portal is cut into a slope facing downhill,
## with a winch, miners' hut, ore heaps and track running out to a buffer stop.
static func _mine(taken: Array[Dictionary]) -> Dictionary:
	var best := Vector2.INF
	var best_score := -INF
	for gx in range(-8, 9):
		for gz in range(0, 10):
			var q := Vector2(gx * 45.0 - 60.0, -380.0 - gz * 45.0)
			var sl := _slope(q)
			if sl < 0.18 or sl > 0.8 or not _free(q, 16.0, taken, 25.0):
				continue
			var score := minf(sl, 0.45) * 4.0 - absf(q.length() - 520.0) / 200.0 - WorldGen.forest_density(q.x, q.y) * 3.0
			if score > best_score:
				best_score = score
				best = q
	if best == Vector2.INF:
		return {}
	var down := _downhill(best)
	var site := _site("Greyseam Mine", "mine", best, _yaw_to(down), 28.0, false)
	_part(site, "mine/mine_entrance", Vector2.ZERO, 0.0, true)
	_part(site, "mine/mine_winch", Vector2(-7, 5), 0.4, true)
	_part(site, "mine/miners_hut", Vector2(9, 8), -0.5, true)
	_part(site, "mine/ore_pile_iron", Vector2(4, 6), 0.3)
	_part(site, "mine/ore_pile_coal", Vector2(-3, 9), 1.2)
	_part(site, "mine/ore_pile_copper", Vector2(6, 11), 2.2)
	_part(site, "mine/mine_props", Vector2(-5, 2), 0.0)
	_part(site, "mine/mine_cart", Vector2(0, 7), 0.0)
	# Track: rail_straight runs 4 m along its local -Z, so point it back at the portal.
	for i in 3:
		_part(site, "mine/rail_straight", Vector2(0, 5.0 + i * 4.0), PI)
	_part(site, "mine/rail_end", Vector2(0, 17.0), PI)
	_part(site, "props/lamp_post", Vector2(3, 3), 0.0)
	site["lights"].append([Vector3(0, 2.2, 1.5), Color(1.0, 0.65, 0.35), 7.0, true])
	return site


## The frontier watchfort at the edge of the runestone ward, looking out over Duskbriar.
static func _watchfort(places: Dictionary, taken: Array[Dictionary]) -> Dictionary:
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var wood: Vector2 = places["duskbriar_wood"]["pos"] if places.has("duskbriar_wood") else Vector2(380, 480)
	var toward := (wood - home).normalized()
	var best := home + toward * 230.0
	var best_h := -INF
	for i in 36:
		var q := home + toward.rotated(_rng.randf_range(-0.6, 0.6)) * _rng.randf_range(190.0, 280.0)
		if not _free(q, 16.0, taken, 18.0):
			continue
		var h := WorldGen.height(q.x, q.y)
		if h > best_h:
			best_h = h
			best = q
	var site := _site("Ember Watch", "watchfort", best, _yaw_to(toward), 20.0, true)
	_part(site, "meshy:landmark_watchfort@15", Vector2.ZERO, 0.0, true)
	_part(site, "props/weapon_rack", Vector2(9, 8), 0.0)
	_part(site, "props/crate_stack", Vector2(-9, 8), 0.4)
	site["lights"].append([Vector3(0, 12.0, 0), Color(1.0, 0.6, 0.3), 14.0, true])
	return site


## Two military forts guarding the outer rings: one on the kingdom road toward
## the border (past the capital), one out on the frontier (past the fortified
## frontier towns, toward Tuskridge and the wild). Reuses the Meshy watchfort
## landmark as the keep, a full palisade ring (ruins/bandit_palisade, the same
## kit the bandit camp and Cinderpost's stockade use), a barn for barracks and
## a garrison's weapon racks and crates. HOOK: garrison AI/Station is not wired
## up here -- a future guard-spawn system can key off site["kind"] == "fort"
## and site["garrison_point"] (barracks position, world space) to place its
## Station without touching this file again.
static func _forts(rng: RandomNumberGenerator, taken: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var capital := Vector2.INF
	var capital_radius := 175.0
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s["pos"]
			capital_radius = float(s["radius"])
			break
	var spacing := taken.duplicate()
	if capital != Vector2.INF:
		var border := capital + (capital - home).normalized() * 400.0
		var kingdom_fort := _fort("Kingsroad Bastion", capital, border, spacing, rng, capital_radius)
		if not kingdom_fort.is_empty():
			out.append(kingdom_fort)
			spacing.append(kingdom_fort)
	var frontier_town := Vector2.INF
	var frontier_radius := WorldGen.FRONTIER_TOWN_RADIUS
	var frontier_best := -INF
	for s in WorldGen.settlements:
		if s["kind"] == "frontier_town" and s["pos"].distance_to(home) > frontier_best \
				and (WorldGen.core_settlement_count == 0 or int(s["id"]) < WorldGen.core_settlement_count):
			frontier_best = s["pos"].distance_to(home)
			frontier_town = s["pos"]
			frontier_radius = float(s["radius"])
	var frontier_center: Vector2 = frontier_town if frontier_town != Vector2.INF else WorldGen.DUSKBRIAR_POS
	var guard_r: float = frontier_radius if frontier_town != Vector2.INF else WorldGen.DUSKBRIAR_RADIUS
	var frontier_fort := _fort("Farwatch Bastion", frontier_center, WorldGen.TUSKRIDGE_POS, spacing, rng, guard_r)
	if not frontier_fort.is_empty():
		out.append(frontier_fort)
	return out


## One fortified garrison: a watchfort keep facing `toward`, a barracks barn, a
## weapon rack and crates, ringed by a full palisade. Searches an annulus
## around `center` (the settlement it guards, or a wood/hold it watches) for
## dry, free ground on the way toward `toward`.
static func _fort(name: String, center: Vector2, toward: Vector2, taken: Array[Dictionary], rng: RandomNumberGenerator, guard_radius := 60.0) -> Dictionary:
	var dir := toward - center
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(0, 1)
	# Clear of the guarded settlement's own flatten-to-natural blend (out to
	# radius * 1.8, see WorldGen.height()) so the fort sits on real, untouched
	# ground of its own instead of crowding the settlement's suburbs.
	var near := guard_radius * 1.8 + 50.0
	var far := near + 260.0
	var best := Vector2.INF
	var best_h := -INF
	for i in 80:
		var q := center + dir.rotated(rng.randf_range(-0.5, 0.5)) * rng.randf_range(near, far)
		if not _free(q, 24.0, taken, 20.0) or _slope(q) > 0.3:
			continue
		var h := WorldGen.height(q.x, q.y)
		if h > best_h:
			best_h = h
			best = q
	if best == Vector2.INF:
		return {}
	var face := (center - best).normalized()
	var site := _site(name, "fort", best, _yaw_to(face), 30.0, true)
	site["garrison_point"] = best + Vector2(-15, 8).rotated(_yaw_to(face))
	_part(site, "meshy:landmark_watchfort@17", Vector2.ZERO, 0.0, true)
	_part(site, "farm/barn", Vector2(-15, 8), PI * 0.5, true)
	_part(site, "props/weapon_rack", Vector2(11, 10), 0.0)
	_part(site, "props/crate_stack", Vector2(14, 7), 0.3)
	_part(site, "props/water_trough", Vector2(-11, 2), 0.0)
	for i in 12:
		var a := TAU * i / 12.0
		_part(site, "ruins/bandit_palisade", Vector2(cos(a), sin(a)) * 24.0, -a + PI * 0.5, true)
	site["lights"].append([Vector3(0, 13.0, 0), Color(1.0, 0.55, 0.25), 15.0, true])
	site["lights"].append([Vector3(-14, 3.5, 10), Color(1.0, 0.6, 0.3), 7.0, true])
	return site


## A small forward camp right at the Rift's edge: the last waypoint before the
## wound in the world. Palisade, tents, a watchfort keep and an expedition
## noticeboard for the quests that send adventurers out here.
static func _rift_outpost(rift: Dictionary, taken: Array[Dictionary], rng: RandomNumberGenerator, outpost_name := "Rift's Edge Camp") -> Dictionary:
	if rift.is_empty():
		return {}
	var rp: Vector2 = rift["pos"]
	var best := Vector2.INF
	for i in 50:
		var a := rng.randf() * TAU
		var q := rp + Vector2(cos(a), sin(a)) * rng.randf_range(60.0, 95.0)
		if _free(q, 18.0, taken, 20.0):
			best = q
			break
	if best == Vector2.INF:
		return {}
	var face := (rp - best).normalized()
	var site := _site(outpost_name, "rift_outpost", best, _yaw_to(face), 20.0, true)
	_part(site, "meshy:landmark_watchfort@13", Vector2.ZERO, 0.0, true)
	_part(site, "ruins/bandit_tent", Vector2(-8, 6), 0.4, true)
	_part(site, "ruins/bandit_tent", Vector2(7, 7), -0.5, true)
	_part(site, "props/notice_board", Vector2(0, 10), 0.0, true)
	_part(site, "props/crate_stack", Vector2(9, 3), 0.2)
	_part(site, "props/weapon_rack", Vector2(-9, 2), 0.0)
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		_part(site, "ruins/bandit_palisade", Vector2(cos(a), sin(a)) * 16.0, -a + PI * 0.5, true)
	site["lights"].append([Vector3(0, 3.5, 0), Color(0.65, 0.4, 0.95), 12.0, true])
	return site


## The Rift: a wound in the world far past the orc hold, glowing violet.
static func _rift(taken: Array[Dictionary], center := Vector2(1150, 980), rift_name := "The Rift", rng: RandomNumberGenerator = _rng) -> Dictionary:
	var pos := center
	for i in 30:
		var q := center + Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		if _free(q, 20.0, taken, 30.0):
			pos = q
			break
	var site := _site(rift_name, "rift", pos, _yaw_to(-pos.normalized()), 24.0, true)
	_part(site, "meshy:landmark_rift@10", Vector2.ZERO, 0.0, true)
	_part(site, "nature:dead_snag", Vector2(12, -6), 0.4)
	_part(site, "nature:dead_snag", Vector2(-13, 4), 2.1)
	_part(site, "nature:rock_cluster", Vector2(7, 9), 0.2)
	_part(site, "nature:boulder_large", Vector2(-8, -9), 1.0, true)
	site["lights"].append([Vector3(0, 4.0, 0), Color(0.7, 0.35, 1.0), 22.0, true])
	return site


# --- Academy campus (ACADEMY_PLAN P4) -----------------------------------------------

const ACADEMY_NAME := "Kingsreach Academy of Arms and Arts"
## Campus layout, data only: [asset, local offset (x right, y front), yaw, collide].
## Assets: "gen:<name>@<scale>" is a big building from assets/generated (castle keep, temple,
## chapel, bell tower), "meshy:<name>@<height>" a Meshy hero building, the rest the usual keys.
## A part's yaw turns its front (+y) toward: 0 = the campus front, PI/2 = the right.
const ACADEMY_PARTS := [
	["gen:castle_keep@0.62", Vector2(0, -20), 0.0, true],          # the main hall
	["meshy:guild@9.1", Vector2(-27, -11), PI * 0.5, true],        # the arms hall (west wing)
	["gen:temple@0.5", Vector2(27, -13), -PI * 0.5, true],         # the arts hall (east wing)
	["meshy:house_manor@8.6", Vector2(-15, -42), 0.0, true],       # dormitories
	["meshy:house_manor@8.6", Vector2(15, -42), 0.0, true],
	["gen:bell_tower@1.0", Vector2(-13, 4), 0.0, true],
	["props/lamp_post", Vector2(-5, 6), 0.0, false], ["props/lamp_post", Vector2(5, 6), 0.0, false],
	["props/lamp_post", Vector2(-5, -8), 0.0, false], ["props/lamp_post", Vector2(5, -8), 0.0, false],
	["props/notice_board", Vector2(9, 8), 0.4, true], ["props/bench", Vector2(-9, 8), 0.0, false],
]
## The training field in front of the hall: dummies (scarecrows), racks, hay targets.
const ACADEMY_FIELD_HALF := Vector2(15.0, 8.5)
const ACADEMY_FIELD_AT := Vector2(0, 26)


## Free ground 150-400 m from Kingsreach, off the road, facing the town. Pure data; no random
## draws, so it cannot shift any other site.
static func _academy(taken: Array[Dictionary]) -> Dictionary:
	var capital := {}
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s
			break
	if capital.is_empty():
		return {}
	var c: Vector2 = capital["pos"]
	var edge := float(capital["radius"]) * 1.8 + 30.0   # past the town's own blend into natural ground
	var best := Vector2.INF
	var best_score := -INF
	for ring in range(0, 12):
		var d := maxf(150.0, edge) + ring * 22.0
		if d > 400.0:
			break
		for i in 48:
			var a := TAU * i / 48.0
			var q := c + Vector2(cos(a), sin(a)) * d
			if not _free(q, 44.0, taken, 30.0) or _slope(q) > 0.14:
				continue
			if WorldGen.forest_density(q.x, q.y) > 0.25:
				continue
			# Flat, near the town, visible from the road (not lost deep in a corner).
			var score := -_slope(q) * 6.0 - (d - 150.0) / 120.0 - WorldGen.road_distance(q.x, q.y) / 200.0
			if score > best_score:
				best_score = score
				best = q
	if best == Vector2.INF:
		return {}
	var site := _site(ACADEMY_NAME, "academy", best, _yaw_to((c - best).normalized()), 46.0, true)
	for p: Array in ACADEMY_PARTS:
		_part(site, String(p[0]), p[1], float(p[2]), bool(p[3]))
	# Field: a fence on three sides (the hall side stays open), dummies in a row, racks and hay.
	var f := ACADEMY_FIELD_AT
	var h := ACADEMY_FIELD_HALF
	var n_front := int(ceil(h.x * 2.0 / 3.1))
	for i in n_front:
		_part(site, "farm/fence_rail", f + Vector2(-h.x + (i + 0.5) * h.x * 2.0 / n_front, h.y), 0.0)
	var n_side := int(ceil(h.y * 2.0 / 3.1))
	for i in n_side:
		var z := f.y + h.y - (i + 0.5) * h.y * 2.0 / n_side
		_part(site, "farm/fence_rail", Vector2(f.x - h.x, z), PI * 0.5)
		_part(site, "farm/fence_rail", Vector2(f.x + h.x, z), PI * 0.5)
	for i in 5:
		_part(site, "farm/scarecrow", f + Vector2(-9.0 + i * 4.5, 3.0), PI, true)
	_part(site, "props/weapon_rack", f + Vector2(-11.0, -5.5), 0.0)
	_part(site, "props/weapon_rack", f + Vector2(-7.5, -5.5), 0.0)
	_part(site, "props/hay_bales", f + Vector2(9.0, -5.0), 0.5)
	_part(site, "props/hay_bales", f + Vector2(11.5, -4.0), -0.4)
	_part(site, "props/water_trough", f + Vector2(0, -6.0), 0.0)
	site["lights"].append([Vector3(-5, 3.6, 6), Color(1.0, 0.75, 0.4), 9.0, true])
	site["lights"].append([Vector3(5, 3.6, 6), Color(1.0, 0.75, 0.4), 9.0, true])
	return site


# --- The new land (8 x 8 km) ------------------------------------------------------------
# Content for everything beyond the original valley, scaled by distance from the capital:
# farms and bridges and waystones for the new roads, a roadhouse halfway along each long new
# road, bastions at the new town and the far frontier hold, hilltop lookouts, ruins, a second
# mine, bandit camps that thicken outward, and a second Rift with its outpost far in the
# south-east. Monster camps and dens come from data/world/first_region.json and
# Frontier._seed_frontier.

static func _is_outer_road(road: Vector2i) -> bool:
	return WorldGen.core_settlement_count > 0 and maxi(road.x, road.y) >= WorldGen.core_settlement_count


static func _capital_pos() -> Vector2:
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			return s["pos"]
	return Vector2.ZERO


static func _outer_sites(out: Array[Dictionary], rng: RandomNumberGenerator, core: int) -> void:
	var capital := _capital_pos()
	for s in WorldGen.settlements:
		if int(s["id"]) < core:
			continue
		var farm := _farmstead(s, rng, out)
		if not farm.is_empty():
			out.append(farm)
	out.append_array(_bridges(true))
	out.append_array(_waystones(rng, true))
	# A roadhouse (stable, trough, notice board, fast-travel point) halfway along each long new road.
	for road in WorldGen.roads:
		if not _is_outer_road(road):
			continue
		var a: Vector2 = WorldGen.settlements[road.x]["pos"]
		var b: Vector2 = WorldGen.settlements[road.y]["pos"]
		if a.distance_to(b) < 1500.0:
			continue
		var far_end := road.x if a.distance_to(capital) > b.distance_to(capital) else road.y
		for t: float in [0.5, 0.42, 0.58, 0.35, 0.65]:
			var mid := a.lerp(b, t)
			var dir := _nearest_road_dir(mid)
			var ground := mid + Vector2(dir.y, -dir.x) * 18.0
			if _free(ground, 24.0, out, -30.0) and not WorldGen.is_water(mid.x, mid.y) and _slope(ground) < 0.25:
				var st := _waystation({"pos": mid})
				st["name"] = "%s Roadhouse" % WorldGen.settlements[far_end]["name"]
				out.append(st)
				break
	# Bastions: one at the new town, one on the far frontier hold.
	for s in WorldGen.settlements:
		if int(s["id"]) < core or not (s["kind"] in ["town", "frontier_town"]):
			continue
		var away: Vector2 = s["pos"] - capital
		var fort := _fort("%s Bastion" % s["name"], s["pos"], s["pos"] + away, out, rng, float(s["radius"]))
		if not fort.is_empty():
			out.append(fort)
	# Hilltop lookouts beside the new villages.
	for s in WorldGen.settlements:
		if int(s["id"]) < core or s["kind"] != "village" or bool(s.get("hamlet", false)):
			continue
		var look := _lookout("%s Lookout" % s["name"], s["pos"], float(s["radius"]), out, rng)
		if not look.is_empty():
			out.append(look)
	# Old ruins and a second mine, far from home.
	var ruin_names := ["Sundered Tower", "The Old Beacon", "Broken Watch"]
	for i in ruin_names.size():
		var ruin := _far_ruin(ruin_names[i], 1800.0 + i * 700.0, out, rng)
		if not ruin.is_empty():
			out.append(ruin)
	var mine := _far_mine("Deepvein Mine", out, rng)
	if not mine.is_empty():
		out.append(mine)
	# Bandit camps in the deep woods: more of them, and further out, the harder the land.
	var camp_names := ["Red Hand Camp", "Blackthorn Camp", "Gallows Camp"]
	for i in camp_names.size():
		var spot := _wild_spot(rng, out, capital, 1700.0 + i * 800.0, 2600.0 + i * 900.0)
		if spot != Vector2.INF:
			out.append(_bandit_camp({"pos": spot, "radius": 40.0}, rng, out, camp_names[i]))
	# A second Rift, with its own outpost, in the far south-east.
	var rift := _rift(out, Vector2(2700, 2500), "The Ashen Scar", rng)
	out.append(rift)
	var outpost := _rift_outpost(rift, out, rng, "Scar Watch")
	if not outpost.is_empty():
		out.append(outpost)


## A wild, wooded, dry, level spot between dmin and dmax metres from the capital.
static func _wild_spot(rng: RandomNumberGenerator, taken: Array[Dictionary], capital: Vector2, dmin: float, dmax: float) -> Vector2:
	var lim := WorldGen.WORLD_HALF - 420.0
	for i in 400:
		var q := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		var d := q.distance_to(capital)
		if d < dmin or d > dmax or WorldGen.forest_density(q.x, q.y) < 0.4:
			continue
		if _free(q, 20.0, taken, 60.0) and _slope(q) < 0.22:
			var far_enough := true
			for s in WorldGen.settlements:
				if q.distance_to(s["pos"]) < float(s["radius"]) * 1.8 + 220.0:
					far_enough = false
					break
			if far_enough:
				return q
	return Vector2.INF


## A lookout tower (watchfort landmark) on the highest free ground near a settlement.
static func _lookout(lookout_name: String, center: Vector2, guard_radius: float, taken: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var best := Vector2.INF
	var best_h := -INF
	for i in 40:
		var q := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(guard_radius * 1.8 + 60.0, guard_radius * 1.8 + 280.0)
		if not _free(q, 16.0, taken, 18.0):
			continue
		var h := WorldGen.height(q.x, q.y)
		if h > best_h:
			best_h = h
			best = q
	if best == Vector2.INF:
		return {}
	var toward := (center - best).normalized()
	var site := _site(lookout_name, "watchfort", best, _yaw_to(toward), 20.0, true)
	_part(site, "meshy:landmark_watchfort@15", Vector2.ZERO, 0.0, true)
	_part(site, "props/weapon_rack", Vector2(9, 8), 0.0)
	_part(site, "props/crate_stack", Vector2(-9, 8), 0.4)
	site["lights"].append([Vector3(0, 12.0, 0), Color(1.0, 0.6, 0.3), 14.0, true])
	return site


## The shell of an old tower on a knoll roughly `dist` metres from Ashford.
static func _far_ruin(ruin_name: String, dist: float, taken: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var best := Vector2.INF
	var best_h := -INF
	var lim := WorldGen.WORLD_HALF - 420.0
	for i in 120:
		var q := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(dist, dist + 700.0)
		if absf(q.x) > lim or absf(q.y) > lim or not _free(q, 14.0, taken, 20.0):
			continue
		var h := WorldGen.height(q.x, q.y)
		if h > best_h and h < 75.0:
			best_h = h
			best = q
	if best == Vector2.INF:
		return {}
	var site := _site(ruin_name, "tower_ruin", best, rng.randf() * TAU, 14.0, true)
	_part(site, "ruins/collapsed_tower", Vector2.ZERO, 0.0, true)
	_part(site, "nature:rock_cluster", Vector2(8, 3), 0.5)
	_part(site, "nature:boulder_large", Vector2(-7, 6), 1.3, true)
	_part(site, "nature:bush_dark", Vector2(-6, -6), 0.0)
	_part(site, "nature:bush_berry", Vector2(7, -5), 0.0)
	return site


## A second mine, cut into a slope of the far hills.
static func _far_mine(mine_name: String, taken: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var best := Vector2.INF
	var best_score := -INF
	var lim := WorldGen.WORLD_HALF - 420.0
	for i in 500:
		var q := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if q.length() < 2200.0:
			continue
		var sl := _slope(q)
		if sl < 0.2 or sl > 0.6 or not _free(q, 16.0, taken, 25.0):
			continue
		var score := minf(sl, 0.45) * 4.0 - WorldGen.forest_density(q.x, q.y) * 3.0 + rng.randf()
		if score > best_score:
			best_score = score
			best = q
	if best == Vector2.INF:
		return {}
	var down := _downhill(best)
	var site := _site(mine_name, "mine", best, _yaw_to(down), 28.0, false)
	_part(site, "mine/mine_entrance", Vector2.ZERO, 0.0, true)
	_part(site, "mine/mine_winch", Vector2(-7, 5), 0.4, true)
	_part(site, "mine/miners_hut", Vector2(9, 8), -0.5, true)
	_part(site, "mine/ore_pile_iron", Vector2(4, 6), 0.3)
	_part(site, "mine/ore_pile_coal", Vector2(-3, 9), 1.2)
	_part(site, "mine/mine_props", Vector2(-5, 2), 0.0)
	_part(site, "mine/mine_cart", Vector2(0, 7), 0.0)
	for i in 3:
		_part(site, "mine/rail_straight", Vector2(0, 5.0 + i * 4.0), PI)
	_part(site, "mine/rail_end", Vector2(0, 17.0), PI)
	_part(site, "props/lamp_post", Vector2(3, 3), 0.0)
	site["lights"].append([Vector3(0, 2.2, 1.5), Color(1.0, 0.65, 0.35), 7.0, true])
	return site
