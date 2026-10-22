extends RefCounted
## Town districts as data (docs/design/VERTICAL_SLICE.md P1 "Thornfield districts readable without the HUD").
## Preload this script; no class_name.
##
## A settlement plan (CityPlanner.plan) gets a list of district ANCHORS: weighted points, each belonging to one of
## six districts. A lot, or any world point, belongs to the district whose anchor has the lowest distance / weight.
## That weighted Voronoi gives six contiguous quarters for any town, from a few numbers, no per-town data:
##   market    plaza and the gate street: tall merchant houses, stalls, carts, signs
##   craft     the smithy and workshops: smoke, woodpiles, material piles
##   poor      the outer ring in the widest gap between gates: small houses, mud, communal wells
##   admin     beside the temple: courthouse, notice boards, banners, guards
##   inn       the inn and stable: stables, wagons, food stalls, travellers
##   military  around every gate (towns, castles and frontier holds only): barracks, drill yard, racks, patrol posts
## `district_at(pos)` is the query for NPC schedules and micro-events.

const MARKET := "market"
const CRAFT := "craft"
const POOR := "poor"
const ADMIN := "admin"
const INN := "inn"
const MILITARY := "military"
const KINDS := [MARKET, CRAFT, POOR, ADMIN, INN, MILITARY]
const LABELS := {MARKET: "Market Quarter", CRAFT: "Craft Quarter", POOR: "Poor Quarter", ADMIN: "Civic Quarter",
	INN: "Inn District", MILITARY: "Gate Ward"}
## Mean wealth 0..1 of a district's lots (house details and prop sets read it).
const WEALTH := {MARKET: 0.72, CRAFT: 0.48, POOR: 0.14, ADMIN: 0.85, INN: 0.55, MILITARY: 0.42}

## Building variants by district: [asset, weight]. Only plain houses are swapped (never the inn, smithy, guild or healer),
## and only for assets whose lot footprint is no bigger than a house's (CityPlanner checks `fits`).
const VARIANTS := {
	MARKET: [["house_town_a", 3], ["house_town_b", 3], ["house_town_c", 3], ["house_town_d", 3], ["house_9", 1]],
	ADMIN: [["house_town_c", 4], ["house_town_d", 4], ["house_town_a", 1]],
	CRAFT: [["house_5", 2], ["house_6", 2], ["house_7", 2], ["house_8", 2]],
	POOR: [["house_1", 3], ["house_2", 3], ["house_3", 2], ["house_4", 2]],
	INN: [["house_10", 1], ["house_11", 1], ["house_town_b", 1]],
	MILITARY: [["house_13", 1], ["house_14", 1], ["house_town_d", 1]],
}


## Which districts a settlement of this kind has (villages are too small for a civic or military ward).
static func kinds_for(town_kind: String) -> Array:
	match town_kind:
		"village":
			return [MARKET, CRAFT, POOR, INN]
		"frontier_town":
			return [MARKET, CRAFT, POOR, INN, MILITARY]
	return KINDS


## Anchors for a plan being built: [{kind, pos: Vector2, w}]. `lots` supplies the inn and smithy positions, so a quarter
## forms around the building that names it; `landmarks` the stable and the temple.
static func anchors(town_kind: String, c: Vector2, r: float, plaza_r: float, gates: Array, lots: Array, landmarks: Array) -> Array:
	var out: Array = []
	var have := kinds_for(town_kind)
	var g0: float = gates[0] if not gates.is_empty() else 0.0
	var sorted_gates: Array = gates.duplicate()
	sorted_gates.sort()
	# Gaps between neighbouring gates (angle centre, width), widest first: the poor quarter takes the widest, craft the next.
	var gaps: Array = []
	for i in sorted_gates.size():
		var a0: float = sorted_gates[i]
		var a1: float = sorted_gates[(i + 1) % sorted_gates.size()]
		var width := wrapf(a1 - a0, 0.0, TAU)
		if sorted_gates.size() == 1:
			width = TAU
		gaps.append([a0 + width * 0.5, width])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var at := func(ang: float, frac: float) -> Vector2:
		return c + Vector2(cos(ang), sin(ang)) * r * frac
	# Market: the plaza and the broad gate street(s).
	if MARKET in have:
		out.append({"kind": MARKET, "pos": c, "w": 0.8})
		out.append({"kind": MARKET, "pos": at.call(g0, 0.40), "w": 1.2})
		if gates.size() > 1:
			out.append({"kind": MARKET, "pos": at.call(gates[1], 0.34), "w": 0.8})
	# Admin: between the plaza and the temple / bell tower, or the keep ring of a castle.
	if ADMIN in have:
		var church := c + Vector2(cos(g0 + PI * 0.5), sin(g0 + PI * 0.5)) * r * 0.30
		for lm: Dictionary in landmarks:
			if lm["asset"] in ["temple", "bell_tower"]:
				church = lm["pos"]
		var to_c := (c - church).normalized()
		var side := Vector2(-to_c.y, to_c.x)
		out.append({"kind": ADMIN, "pos": church + to_c * 9.0 + side * 12.0, "w": 1.6})
	# Inn: the inn itself (else the stable landmark), plus the stable.
	if INN in have:
		var inn_pos := Vector2.INF
		for lot: Dictionary in lots:
			if lot["asset"] == "inn":
				inn_pos = lot["pos"]
				break
		var stable_pos := Vector2.INF
		for lm: Dictionary in landmarks:
			if lm["asset"] == "stable":
				stable_pos = lm["pos"]
		if inn_pos == Vector2.INF:
			inn_pos = stable_pos if stable_pos != Vector2.INF else at.call(g0 - PI * 0.5, 0.45)
		out.append({"kind": INN, "pos": inn_pos, "w": 1.7})
		if stable_pos != Vector2.INF:
			out.append({"kind": INN, "pos": stable_pos, "w": 1.2})
	# Craft: the first smithy, plus the gap that is not the widest.
	if CRAFT in have:
		var smith := Vector2.INF
		for lot: Dictionary in lots:
			if lot["asset"] == "blacksmith":
				smith = lot["pos"]
				break
		var craft_gap: float = gaps[1][0] if gaps.size() > 1 else g0 + PI
		if smith != Vector2.INF:
			out.append({"kind": CRAFT, "pos": smith, "w": 1.1})
		out.append({"kind": CRAFT, "pos": at.call(craft_gap, 0.62), "w": 0.95 if smith != Vector2.INF else 1.2})
	# Poor: the outer ring in the widest gap between gates.
	if POOR in have:
		var poor_gap: float = gaps[0][0] if not gaps.is_empty() else g0 + PI
		out.append({"kind": POOR, "pos": at.call(poor_gap, 0.84), "w": 1.25})
		out.append({"kind": POOR, "pos": at.call(poor_gap + 0.7, 0.88), "w": 0.8})
		out.append({"kind": POOR, "pos": at.call(poor_gap - 0.7, 0.88), "w": 0.8})
	# Military: a ward inside every gate.
	if MILITARY in have:
		for g: float in gates:
			out.append({"kind": MILITARY, "pos": at.call(g, 0.84), "w": 0.62})
	return out


static func anchors_of(anchors_list: Array, kind: String) -> Array:
	return anchors_list.filter(func(a: Dictionary) -> bool: return a["kind"] == kind)


## District of world point `p` for a plan ("" outside the walls). Pure function of plan["district_anchors"].
static func at_plan(plan: Dictionary, p: Vector2) -> String:
	var anchors_list: Array = plan.get("district_anchors", [])
	if anchors_list.is_empty():
		return ""
	var c: Vector2 = plan["centre"]
	var r: float = plan["wall_radius"]
	if p.distance_to(c) > r * 1.04:
		return ""
	return nearest_kind(anchors_list, p)


static func nearest_kind(anchors_list: Array, p: Vector2) -> String:
	var best := INF
	var kind := ""
	for a: Dictionary in anchors_list:
		var d := p.distance_to(a["pos"]) / float(a["w"])
		if d < best:
			best = d
			kind = a["kind"]
	return kind


## District at a world position of any settlement ("" in the countryside). The query for NPC schedules and events.
static func district_at(pos: Vector2) -> String:
	var s := WorldGen.nearest_settlement(pos)
	if s.is_empty() or not s.has("plan"):
		return ""
	return at_plan(s["plan"], pos)


## Settlement dict and district of a world position: {settlement: Dictionary, district: String} (empty when outside).
static func locate(pos: Vector2) -> Dictionary:
	var s := WorldGen.nearest_settlement(pos)
	if s.is_empty() or not s.has("plan"):
		return {}
	var d := at_plan(s["plan"], pos)
	if d == "":
		return {}
	return {"settlement": s, "district": d}


## Wealth 0..1 of a lot: the district mean, richer toward the plaza, a little jitter.
static func wealth_of(kind: String, dist_frac: float, rng: RandomNumberGenerator) -> float:
	return clampf(float(WEALTH.get(kind, 0.5)) + (0.5 - dist_frac) * 0.18 + rng.randf_range(-0.12, 0.12), 0.0, 1.0)


## Weighted pick from a [[asset, weight], ...] table.
static func pick(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e: Array in table:
		total += float(e[1])
	var roll := rng.randf() * total
	for e: Array in table:
		roll -= float(e[1])
		if roll <= 0.0:
			return String(e[0])
	return String(table[table.size() - 1][0])
