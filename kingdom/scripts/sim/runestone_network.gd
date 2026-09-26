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
		stone_changed.emit(s)


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
			"condition": s["condition"], "last_maintained": s["last_maintained"], "owner": s["owner"], "name": s["name"]})
	return out


func deserialize(data: Array) -> void:
	stones.clear()
	for d: Dictionary in data:
		stones.append({"id": int(d["id"]), "pos": Vector2(d["x"], d["y"]), "radius": float(d["radius"]),
			"power": float(d["power"]), "condition": float(d["condition"]), "last_maintained": int(d["last_maintained"]),
			"owner": int(d["owner"]), "name": String(d["name"])})
