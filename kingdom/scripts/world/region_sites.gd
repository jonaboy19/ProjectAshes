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
		if s["kind"] == "village":
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
	out.append(_rift(out))
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
static func _bridges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in WorldGen.roads:
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
static func _waystones(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in WorldGen.roads:
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
			var p := a + dir * t + side * 4.2 * flip
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
static func _bandit_camp(pl: Dictionary, rng: RandomNumberGenerator, taken: Array[Dictionary]) -> Dictionary:
	var c: Vector2 = pl["pos"]
	var r: float = float(pl.get("radius", 300.0))
	var pos := c
	for i in 40:
		var a := rng.randf() * TAU
		var q := c + Vector2(cos(a), sin(a)) * rng.randf_range(r * 0.2, r * 0.6)
		if _free(q, 18.0, taken, 50.0) and _slope(q) < 0.25:
			pos = q
			break
	var site := _site("Bandit Camp", "bandit_camp", pos, rng.randf() * TAU, 16.0, true)
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


## The Rift: a wound in the world far past the orc hold, glowing violet.
static func _rift(taken: Array[Dictionary]) -> Dictionary:
	var pos := Vector2(1150, 980)
	for i in 30:
		var q := Vector2(1150, 980) + Vector2(_rng.randf_range(-250, 250), _rng.randf_range(-250, 250))
		if _free(q, 20.0, taken, 30.0):
			pos = q
			break
	var site := _site("The Rift", "rift", pos, _yaw_to(-pos.normalized()), 24.0, true)
	_part(site, "meshy:landmark_rift@10", Vector2.ZERO, 0.0, true)
	_part(site, "nature:dead_snag", Vector2(12, -6), 0.4)
	_part(site, "nature:dead_snag", Vector2(-13, 4), 2.1)
	_part(site, "nature:rock_cluster", Vector2(7, 9), 0.2)
	_part(site, "nature:boulder_large", Vector2(-8, -9), 1.0, true)
	site["lights"].append([Vector3(0, 4.0, 0), Color(0.7, 0.35, 1.0), 22.0, true])
	return site
