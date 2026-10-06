class_name CityPlanner
extends RefCounted
## Lays out a settlement as data: streets, building lots, walls, gates and
## landmarks. Pure function of the settlement and seed, computed once at world
## setup so terrain (street paving, grass), the simulation (homes, markets)
## and the builder (meshes) all agree on the same city.
##
## Layout: central plaza -> main streets out to each gate (one per road) ->
## ring streets -> radial lanes -> buildings lining both sides of every street,
## rejected where they would overlap a street, another building or the walls.

const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const Districts := preload("res://scripts/world/districts.gd")
const TownIdentity := preload("res://scripts/world/town_identity.gd")   # per-town layout shape + roof mix (data/world/town_identity.json)
const TownLots := preload("res://scripts/world/town_kit/town_lots.gd")   # town kit: every town with a data/region1/towns file always has its smithy, shop, tavern (and bakery, guard post, healer)

const LOT_SPACING := 10.5
const LOT_CLEARANCE := 9.5
const TOWNHOUSES := ["house_town_a", "house_town_b", "house_town_c", "house_town_d"]
const HOMES := ["house_1", "house_2", "house_3", "house_4", "house_5", "house_6", "house_7", "house_8",
	"house_9", "house_10", "house_11", "house_12", "house_13", "house_14", "house_15", "house_16",
	# Meshy house types, weighted so they make up about half of the homes.
	"mhouse_peasant_a", "mhouse_peasant_b", "mhouse_family", "mhouse_trader", "mhouse_manor",
	"mhouse_peasant_a", "mhouse_peasant_b", "mhouse_family", "mhouse_trader",
	"mhouse_peasant_a", "mhouse_peasant_b", "mhouse_family", "mhouse_peasant_b",
	"mhouse_peasant_a", "mhouse_family", "mhouse_trader"]
const TRADES := ["inn", "blacksmith", "stable", "blacksmith"]
## Landmark footprint half extents (local x, z in metres, measured from the GLB bounds; the builder places
## these pieces at native size, ignoring the plan's "scale"). Used to keep lots and props off them.
const LANDMARK_HALF := {
	"temple": Vector2(7.75, 14.25), "castle": Vector2(14.4, 14.9), "bell_tower": Vector2(3.7, 3.75),
	"well": Vector2(1.2, 1.2), "stable": Vector2(6.05, 4.2), "chapel": Vector2(4.3, 6.9)}
## Clear space kept between a lot's footprint rectangle and a landmark's.
const LANDMARK_GAP := 1.5
## A lot's footprint keeps this far inside the town wall (wall half depth + a tower's 3.7 m half width + margin)
## and outside the keep wall.
const WALL_GAP := 4.2
## Fallback when the drawn building does not fit its spot but a small house does.
const SMALL_HOUSE := "house_1"


## Medieval pass (local): QA A/B switch, `--medievaloff` on the command line restores the pre-pass layout and dressing.
static func medieval_off() -> bool:
	return OS.get_cmdline_user_args().has("--medievaloff")

## Medieval pass (local): radius factor of a wandering ring street at angle `a` (about 0.97 .. 1.03, closes on itself).
static func _wander(a: float, ph: float, rf: float) -> float:
	return 1.0 + 0.022 * sin(3.0 * a + ph) + 0.011 * sin(7.0 * a + ph * 1.7 + rf * 5.0)


## Returns {streets: [{a, b, w}], lots: [{asset, pos, yaw}], walls: bool,
##          wall_radius, gates: [angle], plaza_r, landmarks: [{asset, pos, yaw, scale}]}
static func plan(s: Dictionary, gate_angles: Array[float], seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + int(s["id"]) * 7919
	var c: Vector2 = s["pos"]
	var r: float = s["radius"]
	var kind: String = s["kind"]
	var gates: Array[float] = gate_angles.duplicate()
	while gates.size() < 2:
		gates.append((gates[0] + PI) if not gates.is_empty() else rng.randf() * TAU)
	# Visual identity: the town's layout shape (rings, lanes, plaza, density, road corridors; empty = the original layout).
	var prof := TownIdentity.profile(s)
	var lay: Dictionary = prof["lay"]
	var plaza_r := maxf(12.0, r * 0.13) * float(lay.get("plaza", 1.0))
	var walled := kind != "village"
	var result := {"streets": [], "lots": [], "walls": walled, "wall_radius": r, "gates": gates,
		"plaza_r": plaza_r, "landmarks": [], "inner_wall": 0.0, "centre": c}
	var streets: Array = result["streets"]

	var lctx := TownIdentity.layout_context(prof, c, r, gates)
	var narrow := float(lay.get("narrow", 1.0))
	# Medieval pass (local): narrower lanes (rings 5.5 -> 4.6 m, radial lanes 4.5 -> 3.8 m) and houses set closer to the street edge,
	# so the quarters read as tight medieval lanes instead of a suburb on a lawn. Main gate roads keep their market width.
	var off := medieval_off()
	var ring_w := 5.5 if off else 4.6
	var lane_w := 4.5 if off else 3.8
	var wob_ph := float(int(s["id"]) * 37 % 100) * 0.0628
	# Main streets: plaza to each gate.
	for g in gates:
		var d := Vector2(cos(g), sin(g))
		# Walled towns get a broad gate road wide enough for a market (Kingsreach reference).
		streets.append({"a": c + d * plaza_r, "b": c + d * r * 1.05, "w": 11.0 if walled else 8.0})
	# Ring streets.
	var rings: Array[float] = []
	match kind:
		"castle": rings = [0.34, 0.56, 0.78]
		"town": rings.assign([0.42, 0.72] if off else [0.40, 0.56, 0.72])    # Medieval pass (local): one more ring (was 0.42 / 0.72): burgage rows back to back
		_: rings = [0.55]
	if lay.has("rings"):
		rings.assign(lay["rings"])
	for rf in rings:
		var rr := r * rf
		var segs := maxi(10, int(TAU * rr / 16.0))
		# Medieval pass (local): the ring wanders (two slow waves, +-3 % of its radius) so it is no compass circle. A pure function of the
		# angle (no rng draw), so the rest of the layout stream is unchanged and both ends of a segment agree.
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			streets.append({"a": c + Vector2(cos(a0), sin(a0)) * rr * (1.0 if off else _wander(a0, wob_ph, rf)), "b": c + Vector2(cos(a1), sin(a1)) * rr * (1.0 if off else _wander(a1, wob_ph, rf)), "w": ring_w * narrow})
	# Radial lanes between the first ring and the walls, avoiding the main streets.
	var lanes := 5
	match kind:
		"village": lanes = 5
		"frontier_town": lanes = 6   # small palisade hold: fewer lanes than a real town
		"town": lanes = 8
		"castle": lanes = 11
	if lay.has("lanes"):
		lanes = int(lay["lanes"])
	elif lay.has("lanes_mul"):
		lanes = maxi(2, roundi(lanes * float(lay["lanes_mul"])))
	var lane_from: float = rings[0] if not rings.is_empty() else 0.34
	for i in lanes:
		var ang := TAU * (i + 0.5) / lanes + rng.randf_range(-0.12, 0.12)
		if _near_angle(ang, gates, 0.3):
			continue
		var d := Vector2(cos(ang), sin(ang))
		# Medieval pass (local): a lane is two segments with a 2-3 m kink at the middle, alternating left / right (no ruler-straight spokes).
		var la := c + d * r * lane_from
		var lb := c + d * r * (0.96 if walled else 0.9)
		var lmid := (la + lb) * 0.5 + Vector2(-d.y, d.x) * (0.0 if off else (2.6 if i % 2 == 0 else -2.2))
		streets.append({"a": la, "b": lmid, "w": lane_w * narrow})
		streets.append({"a": lmid, "b": lb, "w": lane_w * narrow})

	# Landmarks around the plaza.
	var landmarks: Array = result["landmarks"]
	if kind == "castle":
		result["inner_wall"] = r * 0.2
		landmarks.append({"asset": "castle", "pos": c, "yaw": 0.0, "scale": 1.0})
	else:
		landmarks.append({"asset": "well", "pos": c, "yaw": 0.0, "scale": 1.0})
	var church_ang := gates[0] + PI * 0.5
	var church_r := plaza_r + (14.0 if kind != "village" else 8.0) if kind != "castle" else r * 0.3
	var church_pos := c + Vector2(cos(church_ang), sin(church_ang)) * church_r
	var church_yaw := atan2(-cos(church_ang), -sin(church_ang))
	if bool(lay.get("temple_centre", false)) and kind != "castle":
		# Religious towns: the temple (bell tower in a village) stands in the middle of a big close, facing the first gate;
		# the well moves to the edge of the green.
		church_pos = c
		church_yaw = atan2(cos(float(gates[0])), sin(float(gates[0])))
		var wa := float(gates[0]) + PI * 0.5
		landmarks[0] = {"asset": "well", "pos": c + Vector2(cos(wa), sin(wa)) * (plaza_r * 0.6), "yaw": 0.0, "scale": 1.0}
	landmarks.append({"asset": "temple" if kind != "village" else "bell_tower",
		"pos": church_pos, "yaw": church_yaw, "scale": 9.0 if kind == "village" else 11.0})
	if bool(lay.get("academy", false)) and kind != "castle":
		# Scholarly towns: an academy / library hall opposite the first gate.
		var aa := float(gates[0]) + PI
		landmarks.append({"asset": "chapel", "pos": c + Vector2(cos(aa), sin(aa)) * (plaza_r + 13.0), "yaw": atan2(-cos(aa), -sin(aa)), "scale": 1.0})
	if kind != "village":
		var keep_ang := gates[0] - PI * 0.5
		landmarks.append({"asset": "stable", "pos": c + Vector2(cos(keep_ang), sin(keep_ang)) * (church_r + 2.0),
			"yaw": atan2(-cos(keep_ang), -sin(keep_ang)), "scale": 9.0})

	# Lots along every street.
	var lots: Array = result["lots"]
	var blocked: Array[Vector2] = []
	var lay_out := func(lc: Dictionary) -> void:
		for st in streets:
			var a: Vector2 = st["a"]
			var b: Vector2 = st["b"]
			var w: float = st["w"]
			var dir := (b - a).normalized()
			var normal := Vector2(-dir.y, dir.x)
			var length := a.distance_to(b)
			var t := LOT_SPACING * 0.5
			while t < length:
				for side: float in [-1.0, 1.0]:
					var gate_road := w >= 11.0   # broad market road: tall townhouses set back behind the stalls
					var p := a + dir * t + normal * side * (w * 0.5 + (8.4 if gate_road else (5.6 if off else 4.7)))
					if _lot_ok(p, c, r, plaza_r, walled, result["inner_wall"], streets, blocked, landmarks) and TownIdentity.keep_lot(lc, p):
						var face := -normal * side
						var dist_frac := p.distance_to(c) / r
						var asset: String = HOMES[rng.randi() % HOMES.size()]
						if walled:
							# Towns speak one architectural language (the art reference): tall jettied
							# townhouses and the painted Blender houses, no mixed-style Meshy shells.
							asset = TOWNHOUSES[rng.randi() % TOWNHOUSES.size()] if rng.randf() < 0.55 \
								else "house_%d" % (1 + rng.randi() % 16)
						if dist_frac < 0.5 and rng.randf() < 0.3:
							asset = TRADES[rng.randi() % TRADES.size()]
						elif gate_road:
							asset = TOWNHOUSES[rng.randi() % TOWNHOUSES.size()]
						var lyaw := atan2(face.x, face.y)
						if not fits(asset, p, lyaw, c, r, walled, result["inner_wall"], landmarks):
							asset = SMALL_HOUSE
							if not fits(asset, p, lyaw, c, r, walled, result["inner_wall"], landmarks):
								continue
						lots.append({"asset": asset, "pos": p, "yaw": lyaw})
						blocked.append(p)
				t += LOT_SPACING
	lay_out.call(lctx)
	# A layout shape that thins a small place too far (a strung hamlet, a loose village) is relaxed step by step until the place
	# keeps a believable number of homes (the guild and healer need a handful, a village needs a street).
	var relax := 0
	var min_lots := TownIdentity.min_lots(prof)
	while lots.size() < min_lots and relax < 4 and not lay.is_empty():
		relax += 1
		lots.clear()
		blocked.clear()
		lay_out.call(TownIdentity.relaxed(lctx, relax))
	if kind == "frontier_town":
		_infill(lots, blocked, streets, landmarks, c, r, plaza_r, result["inner_wall"], rng)
	_civic_lots(lots, c, r, walled, result["inner_wall"], landmarks)
	_zone_districts(result, kind, c, r, plaza_r, walled, seed_value, prof)
	TownLots.enforce(result, s, fits)   # town kit: forces the lots the village life needs (no-op for a settlement without a town file)
	result["paths"] = _door_paths(lots, streets)
	return result


## District zoning (scripts/world/districts.gd): anchors, a district and a wealth on every lot, and the building variants
## each quarter favours (tall merchant houses in the market, small houses in the poor quarter, a courthouse beside the
## temple, a second smithy or stable where the quarter wants one). Own RNG stream: the layout above is untouched.
const MAX_EXTRA_SMITHS := 2
const MAX_EXTRA_STABLES := 1
## A swapped-in house must not be wider or deeper than this (the lot spacing was drawn for houses).
const VARIANT_MAX_FOOT := 10.6


static func _zone_districts(plan_data: Dictionary, kind: String, c: Vector2, r: float, plaza_r: float, walled: bool, seed_value: int, prof: Dictionary = {}) -> void:
	var lots: Array = plan_data["lots"]
	var landmarks: Array = plan_data["landmarks"]
	var inner: float = plan_data["inner_wall"]
	var anchors := Districts.anchors(kind, c, r, plaza_r, plan_data["gates"], lots, landmarks)
	plan_data["district_anchors"] = anchors
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "districts"]) + 31 * lots.size()
	var smiths := 0
	var stables := 0
	var courthouse := false
	# The lot nearest the admin anchor becomes the courthouse / steward's hall (one per town that has a civic quarter).
	var court_idx := -1
	var court_best := INF
	var admin_anchors := Districts.anchors_of(anchors, Districts.ADMIN)
	for i in lots.size():
		lots[i]["district"] = Districts.nearest_kind(anchors, lots[i]["pos"])
		if lots[i]["district"] == Districts.ADMIN and String(lots[i]["asset"]).begins_with("house") and not admin_anchors.is_empty():
			var d := (lots[i]["pos"] as Vector2).distance_to(admin_anchors[0]["pos"])
			if d < court_best:
				court_best = d
				court_idx = i
	for i in lots.size():
		var lot: Dictionary = lots[i]
		var dk: String = lot["district"]
		var p: Vector2 = lot["pos"]
		var asset := String(lot["asset"])
		lot["wealth"] = Districts.wealth_of(dk, p.distance_to(c) / r, rng)
		lot["seed"] = hash([seed_value, roundi(p.x * 4.0), roundi(p.y * 4.0)])
		if not (asset.begins_with("house") or asset.begins_with("mhouse")):
			continue   # inn, smithy, guild hall, healer, stable keep their lot
		var want := asset
		var role := ""
		var roll := rng.randf()
		if i == court_idx and not courthouse:
			want = "mhouse_manor"
			role = "courthouse"
		elif dk == Districts.CRAFT and smiths < MAX_EXTRA_SMITHS and roll < 0.16:
			want = "blacksmith"
			role = "workshop"
		elif dk == Districts.INN and stables < MAX_EXTRA_STABLES and roll < 0.14:
			want = "stable"
		elif Districts.VARIANTS.has(dk) and roll < 0.78:
			want = Districts.pick(Districts.VARIANTS[dk], rng)
		if want == asset:
			continue
		var big := BuildingProfiles.size_of(want)
		if want != "stable" and want != "blacksmith" and maxf(big.x, big.z) > VARIANT_MAX_FOOT:
			continue
		if not fits(want, p, lot["yaw"], c, r, walled, inner, landmarks):
			continue
		# An unwalled place has no wall to keep a big building off the slope where the flattened ground ends.
		if not walled and want in ["stable", "blacksmith", "mhouse_manor"] and p.distance_to(c) + maxf(big.x, big.z) * 0.5 > r * 0.88:
			continue
		# A neighbour closer than a big building's reach would overlap it: only the lot grid's own spacing is trusted.
		if want in ["stable", "blacksmith", "mhouse_manor"] and _crowded(lots, i, want):
			continue
		lot["asset"] = want
		if role != "":
			lot["role"] = role
		if want == "blacksmith":
			smiths += 1
		elif want == "stable":
			stables += 1
		elif want == "mhouse_manor":
			courthouse = true
	# Identity restyle: the town's roof mix decides which plain houses it uses (thatch hamlet, slate guild town ...).
	if not prof.is_empty():
		TownIdentity.restyle_lots(plan_data, prof, seed_value, func(a: String, lp: Vector2, yw: float) -> bool:
			var sz := BuildingProfiles.size_of(a)
			return maxf(sz.x, sz.z) <= VARIANT_MAX_FOOT and fits(a, lp, yw, c, r, walled, inner, landmarks))


## True when another lot sits closer than the two buildings' half widths (plus a 1.5 m lane) allow.
static func _crowded(lots: Array, idx: int, asset: String) -> bool:
	var me: Dictionary = lots[idx]
	var s := BuildingProfiles.size_of(asset)
	var reach := maxf(s.x, s.z) * 0.5
	for j in lots.size():
		if j == idx:
			continue
		var o: Dictionary = lots[j]
		var os := BuildingProfiles.size_of(String(o["asset"]))
		if (me["pos"] as Vector2).distance_to(o["pos"]) < reach + maxf(os.x, os.z) * 0.5 + 1.5:
			return true
	return false


## District ("market", "craft", "poor", "admin", "inn", "military", or "" outside the walls) of a world point of a plan.
static func district_at(plan_data: Dictionary, p: Vector2) -> String:
	return Districts.at_plan(plan_data, p)


## Small walled hold: the keep-off-the-wall rule takes its outer row of lots, so further houses go on free plots
## inside the walls (nearest a street first, facing it, close enough for a door path) up to FRONTIER_LOTS lots.
const FRONTIER_LOTS := 54
const INFILL_STREET_MAX := 14.0


static func _infill(lots: Array, blocked: Array[Vector2], streets: Array, landmarks: Array, c: Vector2, r: float,
		plaza_r: float, inner_wall: float, rng: RandomNumberGenerator) -> void:
	var cands := []     # [street edge distance, pos, yaw]
	var step := 3.0
	var gx := -r
	while gx <= r:
		var gz := -r
		while gz <= r:
			var p := c + Vector2(gx, gz)
			gz += step
			if p.distance_to(c) > r:
				continue
			var best := INF
			var bq := Vector2.ZERO
			var bw := 0.0
			for st in streets:
				var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
				var e: float = p.distance_to(q) - float(st["w"]) * 0.5
				if e < best:
					best = e
					bq = q
					bw = st["w"]
			if best > INFILL_STREET_MAX or best < 4.6:
				continue
			var face := (bq - p).normalized()
			cands.append([best, p, atan2(face.x, face.y)])
		gx += step
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and (a[1] as Vector2).x < (b[1] as Vector2).x))
	for cd: Array in cands:
		if lots.size() >= FRONTIER_LOTS:
			break
		var p: Vector2 = cd[1]
		if not _lot_ok(p, c, r, plaza_r, true, inner_wall, streets, blocked, landmarks):
			continue
		var asset: String = TOWNHOUSES[rng.randi() % TOWNHOUSES.size()] if rng.randf() < 0.55 else "house_%d" % (1 + rng.randi() % 16)
		if not fits(asset, p, cd[2], c, r, true, inner_wall, landmarks):
			asset = SMALL_HOUSE
			if not fits(asset, p, cd[2], c, r, true, inner_wall, landmarks):
				continue
		lots.append({"asset": asset, "pos": p, "yaw": cd[2]})
		blocked.append(p)


## Trodden footpaths from each front door to the nearest street. The door is
## the building's real entrance threshold (BuildingProfiles.door_point), the
## same point SettlementBuilder puts its InteriorDoor on.
static func _door_paths(lots: Array, streets: Array) -> Array:
	var out := []
	for lot: Dictionary in lots:
		var door := door_point(lot)
		var best := Vector2.ZERO
		var bd := INF
		for st in streets:
			var q := Geometry2D.get_closest_point_to_segment(door, st["a"], st["b"])
			if door.distance_to(q) < bd:
				bd = door.distance_to(q)
				best = q
		if bd < 18.0:
			out.append({"a": door, "b": best, "w": 1.3})
	return out


## World XZ of a lot's front-door threshold ({asset, pos, yaw}).
static func door_point(lot: Dictionary) -> Vector2:
	return BuildingProfiles.door_point(lot)


static func path_distance(plan_data: Dictionary, p: Vector2) -> float:
	var best := INF
	for st in plan_data.get("paths", []):
		var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
		best = minf(best, p.distance_to(q) - st["w"] * 0.5)
	return best


## Every settlement gets an Adventurer Guild hall and a healer's house on the
## lots nearest its plaza (both Blender-built, see tools/blender). The guild is
## wide, so lots crowding it are dropped.
static func _civic_lots(lots: Array, c: Vector2, r: float, walled: bool, inner_wall: float, landmarks: Array) -> void:
	if lots.size() < 6:
		return
	var has_smithy := false
	for lot: Dictionary in lots:
		if lot["asset"] == "blacksmith":
			has_smithy = true
	if not has_smithy:
		# The third-nearest home to the plaza becomes the smithy.
		var homes := []
		for i in lots.size():
			if String(lots[i]["asset"]).begins_with("house") or String(lots[i]["asset"]).begins_with("mhouse"):
				homes.append(i)
		homes.sort_custom(func(a: int, b: int) -> bool:
			return (lots[a]["pos"] as Vector2).distance_to(c) < (lots[b]["pos"] as Vector2).distance_to(c))
		for hi in range(3, homes.size()):
			var hl: Dictionary = lots[homes[hi]]
			if homes.size() > 4 and fits("blacksmith", hl["pos"], hl["yaw"], c, r, walled, inner_wall, landmarks):
				hl["asset"] = "blacksmith"
				break
	var order := range(lots.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return (lots[a]["pos"] as Vector2).distance_to(c) < (lots[b]["pos"] as Vector2).distance_to(c))
	var guild: Dictionary = {}
	# 17 m from the inn: the inn (13.5 m) and the guild (16 m wide) overlapped at the old 14 m (Longmeadow, world lint).
	for i in order:
		var cand: Dictionary = lots[i]
		if cand["asset"] != "inn" and _clear_of_inns(lots, cand["pos"]) \
				and fits("adventurer_guild", cand["pos"], cand["yaw"], c, r, walled, inner_wall, landmarks):
			guild = cand
			break
	if guild.is_empty():
		return
	guild["asset"] = "adventurer_guild"
	var gp: Vector2 = guild["pos"]
	for i in range(1, order.size()):
		var lot: Dictionary = lots[order[i]]
		if (lot["pos"] as Vector2).distance_to(gp) > 13.0 and lot["asset"] != "inn" \
				and fits("healer_house", lot["pos"], lot["yaw"], c, r, walled, inner_wall, landmarks):
			lot["asset"] = "healer_house"
			break
	for i in range(lots.size() - 1, -1, -1):
		var lot: Dictionary = lots[i]
		if lot != guild and lot["asset"] != "inn" and lot["asset"] != "healer_house" and (lot["pos"] as Vector2).distance_to(gp) < 12.5:
			lots.remove_at(i)


## No inn lot within 17 m of `p` (the guild is 16 m wide, an inn 13.5 m: any closer and their footprints overlap).
static func _clear_of_inns(lots: Array, p: Vector2) -> bool:
	for lot: Dictionary in lots:
		if lot["asset"] == "inn" and (lot["pos"] as Vector2).distance_to(p) <= 17.0:
			return false
	return true


static func _lot_ok(p: Vector2, c: Vector2, r: float, plaza_r: float, walled: bool, inner_wall: float,
		streets: Array, blocked: Array[Vector2], landmarks: Array = []) -> bool:
	var d := p.distance_to(c)
	if d < plaza_r + 5.0 or d > (r - WALL_GAP if walled else r):
		return false
	if inner_wall > 0.0 and d < inner_wall + WALL_GAP:
		return false
	for lm: Dictionary in landmarks:
		if landmark_distance(lm, p) < 2.0:
			return false
	for st in streets:
		var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
		if p.distance_to(q) < st["w"] * 0.5 + 4.6:
			return false
	for other in blocked:
		if p.distance_to(other) < LOT_CLEARANCE:
			return false
	return true


## True when the building `asset` (oriented rectangle of BuildingProfiles.size_of at p, yaw) clears every
## landmark footprint by LANDMARK_GAP and the town wall / keep wall by WALL_GAP.
static func fits(asset: String, p: Vector2, yaw: float, c: Vector2, r: float, walled: bool, inner_wall: float, landmarks: Array) -> bool:
	var size := BuildingProfiles.size_of(asset)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var ex := Vector2(cos(yaw), -sin(yaw))
	var ez := Vector2(sin(yaw), cos(yaw))
	var d := p.distance_to(c)
	if d > 0.001:
		var u := (p - c) / d
		var ext := hx * absf(u.dot(ex)) + hz * absf(u.dot(ez))
		if walled and d + ext > r - WALL_GAP:
			return false
		if inner_wall > 0.0 and d - ext < inner_wall + WALL_GAP:
			return false
	var poly := PackedVector2Array([p - ex * hx - ez * hz, p + ex * hx - ez * hz, p + ex * hx + ez * hz, p - ex * hx + ez * hz])
	for lm: Dictionary in landmarks:
		var half: Vector2 = LANDMARK_HALF.get(String(lm["asset"]), Vector2(3.0, 3.0))
		var ly: float = lm["yaw"]
		var lc: Vector2 = lm["pos"]
		var lx := Vector2(cos(ly), -sin(ly))
		var lz := Vector2(sin(ly), cos(ly))
		var lpoly := PackedVector2Array([lc - lx * half.x - lz * half.y, lc + lx * half.x - lz * half.y,
			lc + lx * half.x + lz * half.y, lc - lx * half.x + lz * half.y])
		if _poly_gap(poly, lpoly) < LANDMARK_GAP:
			return false
	return true


## Gap between two convex polygons (0 when they overlap).
static func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return 0.0
	var best := INF
	for i in a.size():
		for j in b.size():
			best = minf(best, a[i].distance_to(Geometry2D.get_closest_point_to_segment(a[i], b[j], b[(j + 1) % b.size()])))
			best = minf(best, b[j].distance_to(Geometry2D.get_closest_point_to_segment(b[j], a[i], a[(i + 1) % a.size()])))
	return best


## Distance from world XZ point p to a landmark's footprint rectangle (0 inside). The rectangle's axes
## are the ones Basis(UP, yaw) gives the placed piece (local +Z = (sin yaw, cos yaw)).
static func landmark_distance(lm: Dictionary, p: Vector2) -> float:
	var half: Vector2 = LANDMARK_HALF.get(String(lm["asset"]), Vector2(3.0, 3.0))
	var yaw: float = lm["yaw"]
	var v: Vector2 = p - (lm["pos"] as Vector2)
	var lx := v.x * cos(yaw) - v.y * sin(yaw)
	var lz := v.x * sin(yaw) + v.y * cos(yaw)
	return Vector2(maxf(absf(lx) - half.x, 0.0), maxf(absf(lz) - half.y, 0.0)).length()


## Distance from p to the nearest landmark footprint of a plan (INF without landmarks).
static func landmark_clearance(plan_data: Dictionary, p: Vector2) -> float:
	var best := INF
	for lm: Dictionary in plan_data.get("landmarks", []):
		best = minf(best, landmark_distance(lm, p))
	return best


static func _near_angle(ang: float, list: Array[float], width: float) -> bool:
	for g in list:
		if absf(wrapf(ang - g, -PI, PI)) < width:
			return true
	return false


## Distance from p to the nearest street of this plan.
static func street_distance(plan_data: Dictionary, p: Vector2) -> float:
	var best := INF
	for st in plan_data["streets"]:
		var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
		best = minf(best, p.distance_to(q) - st["w"] * 0.5)
	return best
