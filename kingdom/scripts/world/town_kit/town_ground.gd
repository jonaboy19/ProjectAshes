extends RefCounted
## Ground checks for everything the town kit places by hand (clues, stashes, livestock groups, pens, dens): flat enough, dry,
## off the road and clear of the town's buildings. The kit files give offsets from an anchor, and an offset that was fine on paper
## can land on a 10 m slope or in a pond (Skarholm's pen). `settle` moves such a spot to the nearest acceptable ground (rings around it,
## deterministic) and `pen_ok` / `prop_ok` are what the world lint (tools_qa/lint_world/kit_lint.gd) asserts.
## Preload, no class_name; every function is static.

const PEN_MAX_RELIEF := 2.0          # m, highest minus lowest ground under a pen's footprint
const PEN_MAX_PIECE_DROP := 0.9      # m, height difference between the two ends of one 3 m fence piece
const PROP_RING := 1.4               # m, radius of the footprint a clue / stash stands on
const PROP_MAX_RELIEF := 0.7         # m across that ring (about 27 degrees): the level spot `settle_prop` looks for
const PROP_LINT_RELIEF := 1.2        # m: the lint's limit for the least-bad spot (a 0.5 m prop then hangs < 0.2 m over its low side)
const GROUP_RING := 6.0              # m, an animal group's patch of ground
const GROUP_MAX_RELIEF := 3.0
const DEN_MAX_RELIEF := 6.0          # m within 8 m of a den site
const WET := 3.0                     # m of dry margin around a pen / group centre
const SEARCH_RINGS := 8
const SEARCH_STEP := 6.0


## Highest minus lowest ground over a centred ellipse-ish patch: centre plus 8 points on the ring `r`.
static func relief_ring(p: Vector2, r: float) -> float:
	var lo := WorldGen.height(p.x, p.y)
	var hi := lo
	for k in 8:
		var a := TAU * float(k) / 8.0
		var h := WorldGen.height(p.x + cos(a) * r, p.y + sin(a) * r)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


## Highest minus lowest ground over a rectangle `size` (x, y metres) turned by `yaw` around `p`; 5x5 samples.
static func relief_rect(p: Vector2, size: Vector2, yaw: float) -> float:
	var lo := INF
	var hi := -INF
	var c := cos(yaw)
	var s := sin(yaw)
	for i in 5:
		for j in 5:
			var lx := (float(i) / 4.0 - 0.5) * size.x
			var ly := (float(j) / 4.0 - 0.5) * size.y
			var h := WorldGen.height(p.x + lx * c + ly * s, p.y - lx * s + ly * c)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Any of the rectangle's 5x5 sample points (and a margin) in or next to water.
static func rect_wet(p: Vector2, size: Vector2, yaw: float) -> bool:
	var c := cos(yaw)
	var s := sin(yaw)
	for i in 3:
		for j in 3:
			var lx := (float(i) / 2.0 - 0.5) * size.x
			var ly := (float(j) / 2.0 - 0.5) * size.y
			if WorldGen.near_water(p.x + lx * c + ly * s, p.y - lx * s + ly * c, 1.5):
				return true
	return false


## The settlement plan lots near `p` (so a moved prop never lands in a house): [{pos, r}] within `reach` of p.
static func _lots_near(tid: String, p: Vector2, reach: float) -> Array:
	var out: Array = []
	var s := _settlement(tid)
	if s.is_empty():
		return out
	var plan: Dictionary = s.get("plan", {})
	for lot: Dictionary in plan.get("lots", []):
		if (lot["pos"] as Vector2).distance_to(p) < reach + 9.0:
			out.append({"pos": lot["pos"], "r": 9.0})
	for lm: Dictionary in plan.get("landmarks", []):
		if (lm["pos"] as Vector2).distance_to(p) < reach + 14.0:
			out.append({"pos": lm["pos"], "r": 14.0})
	return out


static func _settlement(tid: String) -> Dictionary:
	return (load("res://scripts/world/town_kit/town_places.gd") as GDScript).call("settlement", tid)


## Is `p` inside the walls of a lot's building (its oriented footprint, `pad` m larger)? Uses the profile sizes the planner places by.
static func inside_building(tid: String, p: Vector2, pad := 0.3) -> bool:
	var BP := load("res://scripts/world/building_profiles.gd") as GDScript
	var s := _settlement(tid)
	if s.is_empty():
		return false
	for lot: Dictionary in (s["plan"] as Dictionary).get("lots", []):
		var d: Vector2 = p - (lot["pos"] as Vector2)
		if d.length() > 22.0:
			continue
		var asset := String(lot["asset"])
		var size: Vector3 = BP.call("size_of", asset)
		var wall: float = BP.get("HERO_WALL") if (BP.get("HERO") as Dictionary).has(asset) else BP.get("HOUSE_WALL")
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		if absf(d.dot(side)) < size.x * wall + pad and absf(d.dot(fwd)) < size.z * wall + pad:
			return true
	return false


## True when a lot (or landmark) is within `radius` of `p` besides `radius`-sized props: used to keep moved pens off buildings.
static func near_building(tid: String, p: Vector2, radius: float) -> bool:
	for l: Dictionary in _lots_near(tid, p, radius):
		if (l["pos"] as Vector2).distance_to(p) < float(l["r"]) + radius:
			return true
	return false


## Is `p` on the road (its half width plus `pad`)?
static func on_road(p: Vector2, pad: float) -> bool:
	var ri := WorldGen.road_info(p.x, p.y)
	return float(ri["dist"]) < float(ri["width"]) * 0.5 + pad


static func rect_on_road(p: Vector2, size: Vector2, yaw: float) -> bool:
	var c := cos(yaw)
	var s := sin(yaw)
	for i in 3:
		for j in 3:
			var lx := (float(i) / 2.0 - 0.5) * size.x
			var ly := (float(j) / 2.0 - 0.5) * size.y
			if on_road(Vector2(p.x + lx * c + ly * s, p.y - lx * s + ly * c), 0.5):
				return true
	return false


static func prop_ok(p: Vector2) -> bool:
	return not WorldGen.near_water(p.x, p.y, 1.0) and relief_ring(p, PROP_RING) <= PROP_MAX_RELIEF


static func group_ok(p: Vector2) -> bool:
	return not WorldGen.near_water(p.x, p.y, WET) and relief_ring(p, GROUP_RING) <= GROUP_MAX_RELIEF


static func pen_ok(p: Vector2, size: Vector2, yaw: float) -> bool:
	return not rect_wet(p, size, yaw) and relief_rect(p, size, yaw) <= PEN_MAX_RELIEF


## `p` itself when `ok.call(p)` holds, else the nearest spot on rings around it that does (and clear of buildings when `tid` is
## given); Vector2.INF when nothing within SEARCH_RINGS * SEARCH_STEP qualifies (the caller drops the prop).
static func settle(tid: String, p: Vector2, ok: Callable, clearance := 0.0, step := SEARCH_STEP, rings := SEARCH_RINGS) -> Vector2:
	if ok.call(p) and not (clearance > 0.0 and tid != "" and near_building(tid, p, clearance)):
		return p
	for ring in range(1, rings + 1):
		var n := 8 + 4 * ring
		for k in n:
			var a := TAU * float(k) / float(n) + 0.37 * float(ring)
			var q := p + Vector2(cos(a), sin(a)) * (step * float(ring))
			if ok.call(q) and not (clearance > 0.0 and tid != "" and near_building(tid, q, clearance)):
				return q
	return Vector2.INF


## A quest prop (clue, stash) must exist, so it never gets dropped: the nearest acceptable spot within 20 m, else the least bad one
## (lowest relief, dry before wet, outside the walls) in that disc.
static func settle_prop(tid: String, p: Vector2) -> Vector2:
	var ok := func(q: Vector2) -> bool: return prop_ok(q) and not inside_building(tid, q)
	var best := settle(tid, p, ok, 0.0, 2.0, 6)
	if best != Vector2.INF:
		return best
	var score := INF
	for ring in range(0, 9):
		var n := 1 if ring == 0 else 8 + 4 * ring
		for k in n:
			var a := TAU * float(k) / float(n) + 0.37 * float(ring)
			var q := p + Vector2(cos(a), sin(a)) * (2.5 * float(ring))
			var sc := relief_ring(q, PROP_RING) + 0.02 * p.distance_to(q)
			if WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 1.0):
				sc += 50.0
			if inside_building(tid, q):
				sc += 100.0
			if sc < score:
				score = sc
				best = q
	return best
