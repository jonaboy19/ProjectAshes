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
## Towns medieval pass A/B: `--townsoff` disables this pass (frontage, building age / detail / regional moss, timber lamps,
## ashlar church) for the owner's before / after sheets. Healer sign texture and the Harrowgate identity edit are data, not switched.
static func towns_off() -> bool:
	return OS.get_cmdline_user_args().has("--townsoff")


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
	if not off and frontage_enabled and not towns_off():
		result["roof_thatch"] = float((prof.get("roof", {}) as Dictionary).get("thatch", 0.3))
		_frontage(result, kind, seed_value)   # towns medieval pass: continuous street frontage (lots APPENDED, earlier indices unchanged)
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


## The plaza's market stalls, ONE layout for SettlementBuilder (the models), StreetGraph (NPC obstacles) and NPCWorld (the
## smart-object spots): [{pos, yaw}]. A ring at plaza_r - 3 m facing the well; the profile's stall multiplier sets the count;
## no stall on a landmark or in the mouth of a street that opens onto the plaza. Fixed angles used to put stalls across the
## street mouths (real-world Ashford: the plaza became an NPC routing island).
static func plaza_stalls(s: Dictionary) -> Array:
	var plan_data: Dictionary = s.get("plan", {})
	var c: Vector2 = s["pos"]
	var pr: float = plan_data.get("plaza_r", 12.0)
	var n := 6 if String(s.get("kind", "")) == "village" else 12
	n = clampi(roundi(n * float(TownIdentity.profile(s).get("stalls", 1.0))), 3, 20)
	var ring := pr - 3.0
	var mouths: Array = []      # [angle, half angular width]
	for st: Dictionary in plan_data.get("streets", []):
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var inner := a if a.distance_to(c) < b.distance_to(c) else b
		var outer := b if inner == a else a
		if inner.distance_to(c) > pr + 1.5 or outer.distance_to(c) < ring or outer.distance_to(c) - inner.distance_to(c) < 2.0:
			continue          # only streets that run out of the plaza (not ring-road segments round it)
		# where the street crosses the stall ring
		var hit := Geometry2D.segment_intersects_circle(inner, outer, c, ring)
		var at := inner.lerp(outer, hit) if hit >= 0.0 else outer
		var hw := float(st["w"]) * 0.5 + 2.4          # half street + a stall's half width + a walking gap
		mouths.append([(at - c).angle(), atan(hw / maxf(ring, 1.0))])
	# Each stall keeps its even-ring angle when that spot is free, else slides (up to half the spacing) to the nearest free
	# angle: out of a street mouth, off a landmark, a stall's width clear of the stalls already placed. Deterministic.
	var out: Array = []
	var placed: Array[float] = []
	var sep := (3.5 + 0.6) / maxf(ring, 1.0)
	var step := deg_to_rad(2.5)
	for i in n:
		var base := TAU * i / n + 0.2
		var max_k := int((TAU / n) * 0.5 / step)
		for k in max_k * 2 + 1:
			var off := float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0) * step
			var ang := base + off
			var ok := true
			for m: Array in mouths:
				if absf(wrapf(ang - float(m[0]), -PI, PI)) < float(m[1]):
					ok = false
					break
			for pa: float in placed:
				if ok and absf(wrapf(ang - pa, -PI, PI)) < sep:
					ok = false
			var sp := c + Vector2(cos(ang), sin(ang)) * ring
			if ok and landmark_clearance(plan_data, sp) < 3.0:
				ok = false
			if ok:
				placed.append(ang)
				out.append({"pos": sp, "yaw": atan2(-cos(ang), -sin(ang))})
				break
	return out


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


## Towns medieval pass (docs/plans/TOWNS_MEDIEVAL_PASS.md): a real town. After the planned lots exist (they never move), the plan
## gains (1) an alley network: dead-end and through alleys 1.6-2.2 m wide branching off the ring streets and lanes, thick in the
## poor and craft quarters, rare in the market, none in the rich centre (appended to `streets`, so NPC street graphs and door
## paths use them), and (2) continuous frontage on every street and alley from the small house kit by quarter: rich centre = tall
## townhouses with gaps, burghers = narrow 3-5 m jettied houses, poor quarter / town edge / alleys = 2.6-3.2 m poor houses and
## hovels packed eave to eave. Save compatibility: new lots and streets are APPENDED and flagged (`infill`, `alley`), so every
## planned lot keeps its index, asset, position and district (property ids "s<i>:l<j>", town-kit bids, ownership); Property
## skips infill lots.
static var frontage_enabled := true   # tests: plan with and without, the shared prefix must be identical (save compatibility)
const FRONT_GAP := 0.35          # rich / burgher: metres between two footprints (eaves nearly touch)
const POOR_GAP := 0.05           # poor rows: eave to eave
const FRONT_STEP := 1.0
const FRONT_MAX_FRACTION := 2.5  # at most this many new lots per planned lot
## Pre-release (coordinator 2026-10-28: old saves are not a constraint): the main street and plaza edges are the refined
## Tudor / timber houses (props_refined/buildings), the burgher streets mix them with the kit, the poor quarter keeps the
## cottages (B60) and the kit.
const RICH := ["house_ref_tall", "house_ref_dormer", "house_ref_stone", "house_ref_row", "house_ref_corner", "house_ref_tall"]
const BURGHER := ["house_ref_tall", "house_ref_dormer", "house_narrow_a", "house_narrow_b", "house_narrow_c"]
const POOR := ["house_narrow_poor_a", "house_narrow_poor_b", "house_narrow_poor_a", "house_hovel_a", "house_hovel_b"]
const HOVELS := ["house_hovel_a", "house_hovel_b", "house_narrow_poor_a"]
const KIT_THATCH := ["house_narrow_b", "house_narrow_poor_a", "house_hovel_a", "house_hovel_b"]


static func _frontage(plan_data: Dictionary, kind: String, seed_value: int) -> void:
	var lots: Array = plan_data["lots"]
	var streets: Array = plan_data["streets"]
	var landmarks: Array = plan_data["landmarks"]
	var c: Vector2 = plan_data["centre"]
	var r: float = plan_data["wall_radius"]
	var walled: bool = plan_data["walls"]
	var inner: float = plan_data["inner_wall"]
	var plaza_r: float = plan_data["plaza_r"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "frontage", int(c.x), int(c.y)])
	# The town's own plain houses stay in the mix (its roof mix): tall townhouses for the rich centre, small homes for burghers.
	var tall: Array = []
	var own: Array = []
	for lot: Dictionary in lots:
		var a := String(lot["asset"])
		if not a.begins_with("house"):
			continue
		var sz := BuildingProfiles.size_of(a)
		if sz.x > 8.0 or sz.z > 10.6:
			continue
		if a.begins_with("house_town"):
			if not tall.has(a):
				tall.append(a)
		elif not own.has(a):
			own.append(a)
	var polys: Array = []
	var doors: Array[Vector2] = []
	for lot: Dictionary in lots:
		polys.append(_lot_poly(lot["pos"], lot["yaw"], String(lot["asset"])))
		doors.append(door_point(lot))
	for lm: Dictionary in landmarks:
		var half: Vector2 = LANDMARK_HALF.get(String(lm["asset"]), Vector2(3.0, 3.0))
		polys.append(_rect(lm["pos"], lm["yaw"], half.x, half.y))
	# The town keeps its layout shape (strung, radial, loose): new alleys and houses stay inside the planned lots' hull + 6 m.
	var pts := PackedVector2Array()
	for lot: Dictionary in lots:
		pts.append(lot["pos"])
	var hull := PackedVector2Array()
	if pts.size() >= 3 and not walled:     # a walled town fills up to its wall; open villages keep their planned shape
		var grown := Geometry2D.offset_polygon(Geometry2D.convex_hull(pts), 6.0 if walled else 14.0)   # villages: crofts along the outer lane too
		if not grown.is_empty():
			hull = grown[0]
	plan_data["_hull"] = hull
	var thatch := float(plan_data.get("roof_thatch", 0.3))
	_link_lanes(plan_data, polys)      # dangling lane ends join the network (NPC routes; loose villages had lane islands)
	var first_street := streets.size()
	_alleys(plan_data, polys, rng)
	plan_data["alleys_from"] = first_street
	var cap := int(lots.size() * FRONT_MAX_FRACTION) + 20
	var added := 0
	for si in streets.size():
		var st: Dictionary = streets[si]
		if float(st["w"]) >= 11.0:
			continue          # walled towns' broad gate / market roads keep their stalls and set-back townhouses
		var alley := si >= first_street
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var length := a.distance_to(b)
		if length < 4.0:
			continue
		var dir := (b - a) / length
		var normal := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var t := 0.5 if not alley else 3.0     # an alley's mouth stays open on its parent street
			while t < length - 0.5 and added < cap:
				var at := a + dir * t
				var frac := at.distance_to(c) / r
				var dk := district_at(plan_data, at)
				var tier := 1          # 0 rich, 1 burgher, 2 poor
				if alley or dk == Districts.POOR or frac > 0.8 or (not walled and frac > 0.62):
					tier = 2
				elif dk == Districts.ADMIN or (dk == Districts.MARKET and frac < 0.5):
					tier = 0
				var pool: Array = BURGHER
				if tier == 0:
					pool = tall + RICH
				elif tier == 2:
					pool = POOR if walled else HOVELS
				elif not own.is_empty() and rng.randf() < 0.85:
					pool = own      # benchmark slice (AAA gate): street fronts use the town's own textured houses; the kit is for poor rows / alleys
				var asset: String = pool[rng.randi() % pool.size()]
				if KIT_THATCH.has(asset) != (rng.randf() < thatch) and rng.randf() < 0.7:
					asset = pool[rng.randi() % pool.size()]      # one re-draw toward the town's roof mix
				var sz := BuildingProfiles.size_of(asset)
				var p := at + dir * sz.x * 0.5 + normal * side * (float(st["w"]) * 0.5 + 0.5 + sz.z * 0.5)
				var face := -normal * side
				var yaw := atan2(face.x, face.y)
				var gap := POOR_GAP if tier == 2 else FRONT_GAP
				if (hull.is_empty() or Geometry2D.is_point_in_polygon(p, hull)) and _frontage_ok(p, yaw, asset, c, r, plaza_r, walled, inner, streets, landmarks, polys, doors, gap):
					var lot := {"asset": asset, "pos": p, "yaw": yaw, "infill": true, "district": dk, "tier": tier}
					lot["wealth"] = [0.85, 0.5, 0.12][tier]
					lot["seed"] = hash([seed_value, roundi(p.x * 4.0), roundi(p.y * 4.0)])
					lots.append(lot)
					polys.append(_lot_poly(p, yaw, asset))
					doors.append(door_point(lot))
					added += 1
					t += sz.x + gap + (rng.randf_range(1.0, 3.0) if tier == 0 else 0.0)
				else:
					t += FRONT_STEP
	plan_data["infill_from"] = lots.size() - added
	plan_data.erase("_hull")


## Alleys off every ring street and lane (not the gate roads): 1.6 m in the poor quarter, 2.2 m elsewhere; every ~11 m in the
## poor quarter, ~15-18 m in craft / inn / military, ~26 m in the market, none in the rich centre. Each runs 9-24 m at a slight
## angle away from its street; if it meets another street it stops there (a through alley), else it ends blind (a dead end /
## back court). It must clear every planned building, landmark and earlier alley.
const ALLEY_STEP := {"poor": 11.0, "craft": 15.0, "inn": 16.0, "military": 18.0, "market": 26.0}


static func _alleys(plan_data: Dictionary, polys: Array, rng: RandomNumberGenerator) -> void:
	var streets: Array = plan_data["streets"]
	var c: Vector2 = plan_data["centre"]
	var r: float = plan_data["wall_radius"]
	var walled: bool = plan_data["walls"]
	var plaza_r: float = plan_data["plaza_r"]
	var n0 := streets.size()
	var mouths: Array[Vector2] = []
	for si in n0:
		var st: Dictionary = streets[si]
		if float(st["w"]) >= 11.0:
			continue
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var normal := Vector2(-dir.y, dir.x)
		var t := rng.randf_range(3.0, 8.0)
		while t < length - 2.0:
			var at := a + dir * t
			var dk := district_at(plan_data, at)
			var step: float = ALLEY_STEP.get(dk, 20.0)
			if dk == Districts.ADMIN or at.distance_to(c) < plaza_r + 10.0:
				t += 12.0
				continue
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var w := 1.6 if dk == Districts.POOR else 2.2
			var out := (normal * side).rotated(rng.randf_range(-0.3, 0.3))
			var L := rng.randf_range(9.0, 24.0)
			var ok := true
			for m: Vector2 in mouths:
				if m.distance_to(at) < 7.0:
					ok = false
					break
			var end := at + out * L
			if ok:
				for sj in streets.size():
					if sj == si:
						continue
					var o: Dictionary = streets[sj]
					var hit: Variant = Geometry2D.segment_intersects_segment(at + out * float(st["w"]) * 0.5, end, o["a"], o["b"])
					if hit != null and (hit as Vector2).distance_to(at) > 4.0:
						end = (hit as Vector2) + out * 0.2      # a through alley ends on the other street's centre line
						break
				var hull: PackedVector2Array = plan_data.get("_hull", PackedVector2Array())
				if not hull.is_empty() and not Geometry2D.is_point_in_polygon(end, hull):
					ok = false
				var de := end.distance_to(c)
				if at.distance_to(end) < 6.0 or de > (r - WALL_GAP - 1.0 if walled else r * 0.95) or de < plaza_r + 3.0:
					ok = false
			if ok:
				var rect := _seg_rect(at + out * float(st["w"]) * 0.5, end, w * 0.5 + 0.25)
				for q: PackedVector2Array in polys:
					if q[0].distance_to((at + end) * 0.5) > L + 16.0:
						continue
					if not Geometry2D.intersect_polygons(rect, q).is_empty():
						ok = false
						break
			if ok:
				for sj in range(n0, streets.size()):
					var o2: Dictionary = streets[sj]
					if Geometry2D.segment_intersects_segment(at, end, o2["a"], o2["b"]) != null:
						ok = false
						break
			if ok:
				streets.append({"a": at, "b": end, "w": w, "alley": true})
				mouths.append(at)
			t += step * rng.randf_range(0.8, 1.25)


## A street end that touches no other street (a radial lane starting in the open) gets a short link lane (3 m, appended, `link`)
## to the nearest point of another street, if that link crosses no building or landmark. Without it the lane and every house on it
## were an island in the NPC street graph (11 of Ashford's 20 planned houses could not route to the gate road).
static func _link_lanes(plan_data: Dictionary, polys: Array) -> void:
	var streets: Array = plan_data["streets"]
	var n0 := streets.size()
	var c0: Vector2 = plan_data["centre"]
	var pr0: float = plan_data["plaza_r"]
	for i in n0:
		for end: String in ["a", "b"]:
			var p: Vector2 = streets[i][end]
			if absf(p.distance_to(c0) - pr0) < 1.0:
				continue          # on the plaza edge: StreetGraph joins it to the well ring
			var other: Vector2 = streets[i]["b"] if end == "a" else streets[i]["a"]
			if p.distance_to(c0) > other.distance_to(c0):
				continue          # only the inner end: an outer dead end stays a dead end
			var touching := false
			var cands: Array = []        # [distance, point]: the closest point of every other street, nearest first
			for j2 in n0:
				if j2 == i:
					continue
				var sib: bool = (streets[j2]["a"] as Vector2).is_equal_approx(other) or (streets[j2]["b"] as Vector2).is_equal_approx(other)
				var q := Geometry2D.get_closest_point_to_segment(p, streets[j2]["a"], streets[j2]["b"])
				if sib and not ((streets[j2]["a"] as Vector2).is_equal_approx(p) or (streets[j2]["b"] as Vector2).is_equal_approx(p)):
					continue
				var d := p.distance_to(q)
				if d < float(streets[j2]["w"]) * 0.5 + 1.0:
					touching = true
					break
				if d <= 45.0:
					cands.append([d, q])
				# also the street's far points, so a link can go round an obstacle in front of the nearest one
				for f: float in [0.25, 0.5, 0.75]:
					var q3: Vector2 = (streets[j2]["a"] as Vector2).lerp(streets[j2]["b"], f)
					if p.distance_to(q3) <= 45.0:
						cands.append([p.distance_to(q3), q3])
			if touching:
				continue
			var c: Vector2 = plan_data["centre"]
			var pr: float = plan_data["plaza_r"]
			# a lane that starts inside a building (Ashford's south lane runs into the guild hall): link from the first lane point
			# that is clear of every footprint, toward the far end of the lane
			var pd := (other - p).normalized()
			for step in 24:
				var inside := false
				for q4: PackedVector2Array in polys:
					if q4[0].distance_to(p) < 30.0 and Geometry2D.is_point_in_polygon(p, Geometry2D.offset_polygon(q4, 1.1)[0]):
						inside = true
						break
				if not inside:
					break
				p += pd
			if p.distance_to(c) > pr + 1.0 and p.distance_to(c) - pr <= 45.0:
				# plaza edge straight in, and fanned out +-60 deg so a link can pass round a building on the plaza
				var a0 := (p - c).angle()
				for dk: int in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
					var tp := c + Vector2.from_angle(a0 + deg_to_rad(15.0 * dk)) * pr
					cands.append([p.distance_to(tp), tp])
			cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
			var linked := false
			for cd: Array in cands:
				var tq: Vector2 = cd[1]
				var rect := _seg_rect(p, tq, 0.9)
				var clear := true
				for q2: PackedVector2Array in polys:
					if q2[0].distance_to((p + tq) * 0.5) > p.distance_to(tq) + 16.0:
						continue
					if not Geometry2D.intersect_polygons(rect, q2).is_empty():
						clear = false
						break
				if clear:
					streets.append({"a": tq, "b": p, "w": 1.8, "link": true})
					linked = true
					break
			if not linked:
				# a dog-leg: two link segments through a via point to the side (a gap between two houses on the plaza)
				for cd3: Array in cands:
					var tq3: Vector2 = cd3[1]
					var perp := (tq3 - p).normalized().orthogonal()
					for k5: float in [4.0, -4.0, 7.0, -7.0, 10.0, -10.0, 13.0, -13.0]:
						var via := p + perp * k5     # step out sideways first, then in to the target (round a wide hall)
						var c1 := _link_clear(polys, p, via)
						var c2 := _link_clear(polys, via, tq3)
						# one leg blocked by exactly one planned house: slide that house (save-migrated, see _move_blocker)
						if c1 and not c2:
							c2 = _move_blocker(plan_data, polys, via, tq3)
						elif c2 and not c1:
							c1 = _move_blocker(plan_data, polys, p, via)
						if c1 and c2:
							streets.append({"a": tq3, "b": via, "w": 1.8, "link": true})
							streets.append({"a": via, "b": p, "w": 1.8, "link": true})
							linked = true
							break
					if linked:
						break
			if not linked:
				# exactly one planned house stands in a link: slide it (index kept, `moved_from` recorded: the builder keeps its door
				# id and interior seed, so saved property and interiors follow it). Nearest link first.
				for cd2: Array in cands:
					var tq0: Vector2 = cd2[1]
					if _move_blocker(plan_data, polys, p, tq0):
						streets.append({"a": tq0, "b": p, "w": 1.8, "link": true})
						break


## The one planned lot whose footprint blocks a link from `p` to `q`, slid along its street (its local X) by the smallest of
## +-2 .. +-8 m that clears the link, fits the town (walls, landmarks), stays off every street and keeps 0.3 m to every other
## footprint. The lot keeps its index, asset and yaw; `moved_from` = its planned position (save migration: door id, interior
## seed). The town-kit registry entry follows. False when no single lot blocks or no shift works.
static func _move_blocker(plan_data: Dictionary, polys: Array, p: Vector2, q: Vector2) -> bool:
	var lots: Array = plan_data["lots"]
	var streets: Array = plan_data["streets"]
	var rect := _seg_rect(p, q, 0.9)
	var hits: Array[int] = []
	for i in polys.size():
		if not Geometry2D.intersect_polygons(rect, polys[i]).is_empty():
			if i >= lots.size():
				return false        # a landmark blocks: never move those
			hits.append(i)
	if hits.size() != 1:
		return false
	var j := hits[0]
	var lot: Dictionary = lots[j]
	var asset := String(lot["asset"])
	var yaw := float(lot["yaw"])
	var ex := Vector2(cos(yaw), -sin(yaw))
	var ez := Vector2(sin(yaw), cos(yaw))
	var c: Vector2 = plan_data["centre"]
	var shifts: Array = []
	for k: float in [2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, -5.0, 6.0, -6.0, 8.0, -8.0]:
		shifts.append(ex * k)          # along its street
	for k2: float in [-2.0, -3.0, -4.0, -5.0, -6.0]:
		shifts.append(ez * k2)         # back from its street
	for sh: Vector2 in shifts:
		var np: Vector2 = (lot["pos"] as Vector2) + sh
		var poly := _lot_poly(np, yaw, asset)
		if not Geometry2D.intersect_polygons(rect, poly).is_empty():
			continue
		if not fits(asset, np, yaw, c, float(plan_data["wall_radius"]), bool(plan_data["walls"]), float(plan_data["inner_wall"]), plan_data["landmarks"]):
			continue
		var ok := true
		for i in polys.size():
			if i != j and _poly_gap(poly, polys[i]) < 0.3:
				ok = false
				break
		if ok:
			for st: Dictionary in streets:
				for v: Vector2 in Array(poly) + [np]:
					if v.distance_to(Geometry2D.get_closest_point_to_segment(v, st["a"], st["b"])) < float(st["w"]) * 0.5 + 0.3:
						ok = false
						break
				if not ok:
					break
		if not ok:
			continue
		lot["moved_from"] = lot["pos"]
		lot["pos"] = np
		polys[j] = poly
		var bid := String(lot.get("bid", ""))
		var sl: Dictionary = plan_data.get("slice", {})
		if bid != "" and (sl.get("buildings", {}) as Dictionary).has(bid):
			sl["buildings"][bid]["pos"] = np
			sl["buildings"][bid]["door"] = BuildingProfiles.door_point(lot)
		return true
	return false


static func _link_clear(polys: Array, a: Vector2, b: Vector2) -> bool:
	var rect := _seg_rect(a, b, 0.9)
	for q: PackedVector2Array in polys:
		if q[0].distance_to((a + b) * 0.5) > a.distance_to(b) + 16.0:
			continue
		if not Geometry2D.intersect_polygons(rect, q).is_empty():
			return false
	return true


static func _seg_rect(a: Vector2, b: Vector2, hw: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * hw
	return PackedVector2Array([a + n, b + n, b - n, a - n])


static func _rect(p: Vector2, yaw: float, hx: float, hz: float) -> PackedVector2Array:
	var ex := Vector2(cos(yaw), -sin(yaw))
	var ez := Vector2(sin(yaw), cos(yaw))
	return PackedVector2Array([p - ex * hx - ez * hz, p + ex * hx - ez * hz, p + ex * hx + ez * hz, p - ex * hx + ez * hz])


static func _lot_poly(p: Vector2, yaw: float, asset: String) -> PackedVector2Array:
	var sz := BuildingProfiles.size_of(asset)
	return _rect(p, yaw, sz.x * 0.5, sz.z * 0.5)


static func _frontage_ok(p: Vector2, yaw: float, asset: String, c: Vector2, r: float, plaza_r: float, walled: bool, inner: float,
		streets: Array, landmarks: Array, polys: Array, doors: Array[Vector2], gap := FRONT_GAP) -> bool:
	var d := p.distance_to(c)
	if d < plaza_r + 5.0 or (not walled and d > r * 0.95):
		return false
	if not fits(asset, p, yaw, c, r, walled, inner, landmarks):
		return false
	var poly := _lot_poly(p, yaw, asset)
	var reach := 14.0
	for q: PackedVector2Array in polys:
		if q[0].distance_to(p) > reach + 12.0:
			continue
		if _poly_gap(poly, q) < gap:
			return false
	# no street, lane or gate road may run through it (its own street included: the front stays 0.6 m off the edge)
	var pts := Array(poly)
	for i in 4:      # every metre along each edge: a 20 m row front used to straddle a 1.6 m alley between its corner samples
		var e0: Vector2 = poly[i]
		var e1: Vector2 = poly[(i + 1) % 4]
		var ns := maxi(2, int(e0.distance_to(e1)))
		for k in range(1, ns):
			pts.append(e0.lerp(e1, float(k) / ns))
	pts.append(p)
	for st: Dictionary in streets:
		for v: Vector2 in pts:
			var q2 := Geometry2D.get_closest_point_to_segment(v, st["a"], st["b"])
			if v.distance_to(q2) < float(st["w"]) * 0.5 + 0.3:
				return false
	# keep every existing front door reachable (2.4 m in front of it)
	for dp: Vector2 in doors:
		if dp.distance_to(p) < 16.0 and _poly_gap(poly, PackedVector2Array([dp + Vector2(-1.2, -1.2), dp + Vector2(1.2, -1.2), dp + Vector2(1.2, 1.2), dp + Vector2(-1.2, 1.2)])) < 0.3:
			return false
	return true
