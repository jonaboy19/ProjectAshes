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
	"well": Vector2(1.2, 1.2), "stable": Vector2(6.05, 4.2)}
## A lot's centre stays this far from every landmark rectangle (covers the widest lot, the 16 m guild hall).
const LANDMARK_LOT_GAP := 9.5
## A lot centre stays this far inside a town wall / outside the keep wall (house half-diagonal + wall depth).
const WALL_LOT_GAP := 8.5


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
	var plaza_r := maxf(12.0, r * 0.13)
	var walled := kind != "village"
	var result := {"streets": [], "lots": [], "walls": walled, "wall_radius": r, "gates": gates,
		"plaza_r": plaza_r, "landmarks": [], "inner_wall": 0.0}
	var streets: Array = result["streets"]

	# Main streets: plaza to each gate.
	for g in gates:
		var d := Vector2(cos(g), sin(g))
		# Walled towns get a broad gate road wide enough for a market (Kingsreach reference).
		streets.append({"a": c + d * plaza_r, "b": c + d * r * 1.05, "w": 11.0 if walled else 8.0})
	# Ring streets.
	var rings: Array[float] = []
	match kind:
		"castle": rings = [0.34, 0.56, 0.78]
		"town": rings = [0.42, 0.72]
		_: rings = [0.55]
	for rf in rings:
		var rr := r * rf
		var segs := maxi(10, int(TAU * rr / 16.0))
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			streets.append({"a": c + Vector2(cos(a0), sin(a0)) * rr, "b": c + Vector2(cos(a1), sin(a1)) * rr, "w": 5.5})
	# Radial lanes between the first ring and the walls, avoiding the main streets.
	var lanes := 5
	match kind:
		"village": lanes = 5
		"frontier_town": lanes = 6   # small palisade hold: fewer lanes than a real town
		"town": lanes = 8
		"castle": lanes = 11
	for i in lanes:
		var ang := TAU * (i + 0.5) / lanes + rng.randf_range(-0.12, 0.12)
		if _near_angle(ang, gates, 0.3):
			continue
		var d := Vector2(cos(ang), sin(ang))
		streets.append({"a": c + d * r * rings[0], "b": c + d * r * (0.96 if walled else 0.9), "w": 4.5})

	# Landmarks around the plaza.
	var landmarks: Array = result["landmarks"]
	if kind == "castle":
		result["inner_wall"] = r * 0.2
		landmarks.append({"asset": "castle", "pos": c, "yaw": 0.0, "scale": 1.0})
	else:
		landmarks.append({"asset": "well", "pos": c, "yaw": 0.0, "scale": 1.0})
	var church_ang := gates[0] + PI * 0.5
	var church_r := plaza_r + (14.0 if kind != "village" else 8.0) if kind != "castle" else r * 0.3
	landmarks.append({"asset": "temple" if kind != "village" else "bell_tower",
		"pos": c + Vector2(cos(church_ang), sin(church_ang)) * church_r, "yaw": atan2(-cos(church_ang), -sin(church_ang)), "scale": 9.0 if kind == "village" else 11.0})
	if kind != "village":
		var keep_ang := gates[0] - PI * 0.5
		landmarks.append({"asset": "stable", "pos": c + Vector2(cos(keep_ang), sin(keep_ang)) * (church_r + 2.0),
			"yaw": atan2(-cos(keep_ang), -sin(keep_ang)), "scale": 9.0})

	# Lots along every street.
	var lots: Array = result["lots"]
	var blocked: Array[Vector2] = []
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
				var p := a + dir * t + normal * side * (w * 0.5 + (8.4 if gate_road else 5.6))
				if _lot_ok(p, c, r, plaza_r, walled, result["inner_wall"], streets, blocked, landmarks):
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
					lots.append({"asset": asset, "pos": p, "yaw": atan2(face.x, face.y)})
					blocked.append(p)
			t += LOT_SPACING
	_civic_lots(lots, c)
	result["paths"] = _door_paths(lots, streets)
	return result


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
		if bd < 14.0:
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
static func _civic_lots(lots: Array, c: Vector2) -> void:
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
		if homes.size() > 4:
			lots[homes[3]]["asset"] = "blacksmith"
	var order := range(lots.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return (lots[a]["pos"] as Vector2).distance_to(c) < (lots[b]["pos"] as Vector2).distance_to(c))
	var inn_pos := Vector2(INF, INF)
	for lot: Dictionary in lots:
		if lot["asset"] == "inn":
			inn_pos = lot["pos"]
			break
	var guild: Dictionary = {}
	for i in order:
		var cand: Dictionary = lots[i]
		if cand["asset"] != "inn" and (cand["pos"] as Vector2).distance_to(inn_pos) > 14.0:
			guild = cand
			break
	if guild.is_empty():
		return
	guild["asset"] = "adventurer_guild"
	var gp: Vector2 = guild["pos"]
	for i in range(1, order.size()):
		var lot: Dictionary = lots[order[i]]
		if (lot["pos"] as Vector2).distance_to(gp) > 13.0 and lot["asset"] != "inn":
			lot["asset"] = "healer_house"
			break
	for i in range(lots.size() - 1, -1, -1):
		var lot: Dictionary = lots[i]
		if lot != guild and lot["asset"] != "inn" and lot["asset"] != "healer_house" and (lot["pos"] as Vector2).distance_to(gp) < 12.5:
			lots.remove_at(i)


static func _lot_ok(p: Vector2, c: Vector2, r: float, plaza_r: float, walled: bool, inner_wall: float,
		streets: Array, blocked: Array[Vector2], landmarks: Array = []) -> bool:
	var d := p.distance_to(c)
	if d < plaza_r + 5.0 or d > (r - WALL_LOT_GAP if walled else r):
		return false
	if inner_wall > 0.0 and d < inner_wall + WALL_LOT_GAP:
		return false
	for lm: Dictionary in landmarks:
		if landmark_distance(lm, p) < LANDMARK_LOT_GAP:
			return false
	for st in streets:
		var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
		if p.distance_to(q) < st["w"] * 0.5 + 4.6:
			return false
	for other in blocked:
		if p.distance_to(other) < LOT_CLEARANCE:
			return false
	return true


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
