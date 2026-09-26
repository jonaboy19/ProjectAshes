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

const LOT_SPACING := 7.6
const LOT_CLEARANCE := 6.8
const HOMES := ["building_home_A_red", "building_home_B_red", "building_home_A_blue", "building_home_B_blue",
	"building_home_A_yellow", "building_home_B_yellow", "building_home_A_green", "building_home_B_green"]
const TRADES := ["building_tavern_red", "building_tavern_green", "building_blacksmith_blue", "building_market_red",
	"building_market_yellow"]


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
		streets.append({"a": c + d * plaza_r, "b": c + d * r * 1.05, "w": 8.0})
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
	var lanes := 5 if kind == "village" else (8 if kind == "town" else 11)
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
		landmarks.append({"asset": "building_castle_blue", "pos": c, "yaw": 0.0, "scale": 20.0})
	else:
		landmarks.append({"asset": "building_well_red", "pos": c, "yaw": 0.0, "scale": 6.0})
	var church_ang := gates[0] + PI * 0.5
	var church_r := plaza_r + 9.0 if kind != "castle" else r * 0.27
	landmarks.append({"asset": "building_church_blue" if kind != "village" else "building_church_red",
		"pos": c + Vector2(cos(church_ang), sin(church_ang)) * church_r, "yaw": atan2(-cos(church_ang), -sin(church_ang)), "scale": 9.0 if kind == "village" else 11.0})
	if kind != "village":
		var keep_ang := gates[0] - PI * 0.5
		landmarks.append({"asset": "building_barracks_blue", "pos": c + Vector2(cos(keep_ang), sin(keep_ang)) * (church_r + 2.0),
			"yaw": atan2(-cos(keep_ang), -sin(keep_ang)), "scale": 9.0})

	# Lots along every street.
	var lots: Array = result["lots"]
	var blocked: Array[Vector2] = []
	for lm in landmarks:
		blocked.append(lm["pos"])
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
				var p := a + dir * t + normal * side * (w * 0.5 + 4.3)
				if _lot_ok(p, c, r, plaza_r, walled, result["inner_wall"], streets, blocked):
					var face := -normal * side
					var dist_frac := p.distance_to(c) / r
					var asset: String = HOMES[rng.randi() % HOMES.size()]
					if dist_frac < 0.5 and rng.randf() < 0.3:
						asset = TRADES[rng.randi() % TRADES.size()]
					lots.append({"asset": asset, "pos": p, "yaw": atan2(face.x, face.y)})
					blocked.append(p)
			t += LOT_SPACING
	return result


static func _lot_ok(p: Vector2, c: Vector2, r: float, plaza_r: float, walled: bool, inner_wall: float,
		streets: Array, blocked: Array[Vector2]) -> bool:
	var d := p.distance_to(c)
	if d < plaza_r + 5.0 or d > r * (0.93 if walled else 1.0):
		return false
	if inner_wall > 0.0 and d < inner_wall + 6.0:
		return false
	for st in streets:
		var q := Geometry2D.get_closest_point_to_segment(p, st["a"], st["b"])
		if p.distance_to(q) < st["w"] * 0.5 + 3.4:
			return false
	for other in blocked:
		if p.distance_to(other) < LOT_CLEARANCE:
			return false
	return true


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
