class_name RARunestoneNetwork
extends RefCounted
## Territorial safety network. Each stone projects protection that fades with
## distance; strength is power x condition. Stones wear down, can be damaged,
## sabotaged or overwhelmed, and need maintenance. Everything that cares about
## safety (monsters, land value, building, travel) reads coverage() from here.

signal stone_changed(stone: Dictionary)

## Each stone: {id, pos: Vector2, radius, power 0..1, condition 0..1,
##              last_maintained: day, owner: settlement id or -1, name}
var stones: Array[Dictionary] = []

const DECAY_PER_DAY := 0.004        # condition lost per day without maintenance
const NEGLECT_AFTER_DAYS := 20      # decay doubles once maintenance is this late
const POWER_RECOVERY := 0.02        # power regained per day when condition is good

## Roadside stones (besides the village ring): spaced so their radii just
## overlap on the roads civilization actually maintains, wider on a frontier
## road so it stays only weakly protected.
const ROAD_STONE_RADIUS := 110.0
const ROAD_SPACING := {"kingdom": 180.0, "rural": 195.0, "frontier": 420.0}
## A road stone's condition drifts a little every day: a small chance to fail
## outright (a few stones down somewhere at any time), and a slow repair
## otherwise, seeded so the same day always drifts the same way.
const ROAD_FAILURE_CHANCE := 0.015
const ROAD_REPAIR_PER_DAY := 0.03


## Condition band a stone reads as: glowing, dim, cracked or dark.
func condition_name(s: Dictionary) -> String:
	var c := float(s["condition"])
	if c >= 0.75:
		return "glowing"
	elif c >= 0.45:
		return "dim"
	elif c >= 0.15:
		return "cracked"
	return "dark"


## Adds stones along every kingdom and rural road (WorldGen.roads), tagged
## with the settlement the road leads toward so rumours() can name it.
## Frontier roads (village to village) get stones too, just far enough apart
## that coverage barely overlaps.
func seed_road_stones() -> void:
	for r in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		var tier := WorldGen.road_tier(r.x, r.y)
		var spacing: float = ROAD_SPACING[tier]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var ra: float = WorldGen.settlements[r.x]["radius"] * 1.8
		var rb: float = WorldGen.settlements[r.y]["radius"] * 1.8
		var to_name := String(WorldGen.settlements[r.y]["name"])
		var t := ra + spacing * 0.5
		var n := 1
		while t < length - rb:
			var p := a + dir * t
			var s := add_stone(p, ROAD_STONE_RADIUS, r.x, "%s Road Stone %d" % [to_name, n])
			s["road"] = true
			s["road_to"] = to_name
			s["tier"] = tier
			n += 1
			t += spacing


## Named roads with stones currently cracked or dark, for NPC gossip, e.g.
## "Don't take the road to Oakvale, two stones there stopped glowing."
func rumours() -> Array[String]:
	var failing: Dictionary = {}       # road_to name -> count
	for s in stones:
		if not bool(s.get("road", false)):
			continue
		if condition_name(s) in ["cracked", "dark"]:
			var road_to := String(s.get("road_to", ""))
			if road_to == "":
				continue
			failing[road_to] = int(failing.get(road_to, 0)) + 1
	var out: Array[String] = []
	for road_to in failing:
		var n: int = failing[road_to]
		if n == 1:
			out.append("Don't take the road to %s, a stone there stopped glowing." % road_to)
		else:
			out.append("Don't take the road to %s, %d stones there stopped glowing." % [road_to, n])
	return out


func add_stone(pos: Vector2, radius: float, owner := -1, stone_name := "") -> Dictionary:
	var s := {"id": stones.size(), "pos": pos, "radius": radius, "power": 1.0, "condition": 1.0,
		"last_maintained": 0, "owner": owner, "name": stone_name if stone_name != "" else "Runestone %d" % (stones.size() + 1)}
	stones.append(s)
	return s


func strength(s: Dictionary) -> float:
	return clampf(s["power"] * s["condition"], 0.0, 1.0)


## Protection at a point, 0..1. Strongest stone wins, fading smoothly to its radius.
func coverage(p: Vector2) -> float:
	var best := 0.0
	for s in stones:
		var d := p.distance_to(s["pos"])
		var r: float = s["radius"]
		if d >= r:
			continue
		var falloff := 1.0 - smoothstep(r * 0.55, r, d)
		best = maxf(best, strength(s) * falloff)
	return best


## The stones affecting a point, strongest first (for UI and explanations).
func stones_near(p: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in stones:
		if p.distance_to(s["pos"]) < s["radius"]:
			out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return strength(a) > strength(b))
	return out


func tick_day(day: int) -> void:
	for s in stones:
		var late: int = day - int(s["last_maintained"])
		var decay := DECAY_PER_DAY * (2.0 if late > NEGLECT_AFTER_DAYS else 1.0)
		s["condition"] = maxf(0.0, s["condition"] - decay)
		if s["condition"] > 0.5:
			s["power"] = minf(1.0, s["power"] + POWER_RECOVERY)
		if bool(s.get("road", false)):
			_drift_road_stone(s, day)
		stone_changed.emit(s)


## A road stone's daily luck: seeded on (stone id, day) so it is the same
## every time this day is simulated, but different stones and different days
## drift independently. Mostly a slow repair; now and then a stone fails.
func _drift_road_stone(s: Dictionary, day: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(s["id"]), day))
	if rng.randf() < ROAD_FAILURE_CHANCE:
		s["condition"] = maxf(0.0, s["condition"] - rng.randf_range(0.25, 0.55))
	elif s["condition"] < 1.0:
		s["condition"] = minf(1.0, s["condition"] + ROAD_REPAIR_PER_DAY)


func damage(stone_id: int, amount: float, drain_power := 0.0) -> void:
	var s := stones[stone_id]
	s["condition"] = maxf(0.0, s["condition"] - amount)
	s["power"] = maxf(0.0, s["power"] - drain_power)
	stone_changed.emit(s)


func maintain(stone_id: int, day: int, amount := 0.25) -> void:
	var s := stones[stone_id]
	s["condition"] = minf(1.0, s["condition"] + amount)
	s["last_maintained"] = day
	stone_changed.emit(s)


func serialize() -> Array:
	var out := []
	for s in stones:
		out.append({"id": s["id"], "x": s["pos"].x, "y": s["pos"].y, "radius": s["radius"], "power": s["power"],
			"condition": s["condition"], "last_maintained": s["last_maintained"], "owner": s["owner"], "name": s["name"],
			"road": bool(s.get("road", false)), "road_to": String(s.get("road_to", "")), "tier": String(s.get("tier", ""))})
	return out


func deserialize(data: Array) -> void:
	stones.clear()
	for d: Dictionary in data:
		var s := {"id": int(d["id"]), "pos": Vector2(d["x"], d["y"]), "radius": float(d["radius"]),
			"power": float(d["power"]), "condition": float(d["condition"]), "last_maintained": int(d["last_maintained"]),
			"owner": int(d["owner"]), "name": String(d["name"])}
		if bool(d.get("road", false)):
			s["road"] = true
			s["road_to"] = String(d.get("road_to", ""))
			s["tier"] = String(d.get("tier", ""))
		stones.append(s)
