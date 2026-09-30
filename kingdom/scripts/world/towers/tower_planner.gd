extends RefCounted
## Plans the dungeon tower sites for RegionSites (hook: one line at the end of RegionSites.plan):
##   out.append_array(preload("res://scripts/world/towers/tower_planner.gd").sites(seed_value, out))
## Own RNG stream (seed * 73 + 41) so no other site moves. The Ashfall Spire stands on open, level ground 1.3-2.4 km from
## Kingsreach (so it towers over the capital's skyline), facing the capital; 150 m of cleared, levelled ground around it
## hold the base camp.

const TowerData := preload("res://scripts/world/towers/tower_data.gd")
const CLEAR := 150.0
const REACH_MIN := 1300.0
const REACH_MAX := 2400.0


static func sites(seed_value: int, taken: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 73 + 41
	var anchor := _capital()
	var pos := _find(anchor, rng, taken)
	if pos == Vector2.INF:
		return out
	var to := anchor - pos
	var yaw := atan2(to.x, to.y)
	var tid := TowerData.DEFAULT_TOWER
	out.append({"name": String(TowerData.tower(tid)["name"]), "kind": "dungeon_tower", "tower": tid, "pos": pos, "yaw": yaw,
		"clear": CLEAR, "flatten": true, "parts": [], "lights": []})
	return out


static func _capital() -> Vector2:
	for s: Dictionary in WorldGen.settlements:
		if String(s.get("name", "")) == "Kingsreach":
			return s["pos"]
	for s: Dictionary in WorldGen.settlements:
		if String(s.get("kind", "")) == "castle":
			return s["pos"]
	return Vector2.ZERO


static func _find(anchor: Vector2, rng: RandomNumberGenerator, taken: Array) -> Vector2:
	var best := Vector2.INF
	var best_score := -1.0e9
	for i in 240:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(REACH_MIN, REACH_MAX)
		var p := anchor + Vector2(cos(ang), sin(ang)) * dist
		if absf(p.x) > WorldGen.WORLD_HALF - 500.0 or absf(p.y) > WorldGen.WORLD_HALF - 500.0:
			continue
		if not RegionSites._free(p, CLEAR + 40.0, _typed(taken), 30.0):
			continue
		# level ground over the camp and the spire: sample a ring and the centre
		var h0 := WorldGen.height(p.x, p.y)
		var worst := 0.0
		for k in 12:
			var q := p + Vector2(cos(TAU * float(k) / 12.0), sin(TAU * float(k) / 12.0)) * 110.0
			worst = maxf(worst, absf(WorldGen.height(q.x, q.y) - h0))
		if worst > 14.0:
			continue
		# a little height helps the silhouette, closeness to 1.7 km helps the view from the capital
		var score := h0 * 0.25 - worst * 3.0 - absf(dist - 1700.0) * 0.02
		if score > best_score:
			best_score = score
			best = p
	return best


static func _typed(taken: Array) -> Array[Dictionary]:
	var t: Array[Dictionary] = []
	for d in taken:
		t.append(d)
	return t
