extends RefCounted
## W4 landmarks and POIs (PA_plans/WORLD_BRIEF.md phase W4): physical bodies for bible places that had none (named-forest groves, the Ashford
## runestone circle, the Rift Mouth, Greenhollow's south fields, Silverford's market square, river and border markers, road milestones ...).
## Data: data/region1/world/w4_sites.json (tools/region1/gen_w4_sites.py writes it). RegionSites.plan() calls plan() after every other site
## (so no existing id or position moves) and then Region1Terrain.activate_late() (the W4 terrain stamps start after planning, same reason).
## A site is {name, kind, pos, yaw, clear, flatten, parts, lights} in the RegionSites format plus r1id "w4_..." and `covers` (the inventory ids it
## gives a body to). Placement: `fixed` = exactly `at`; otherwise the nearest good ground within `snap` m (dry, off roads, clear of other sites,
## slope <= `slope`); `bank` sites stand on the dry ground nearest the water; `milestones` become one small site per post along the nearest road.

const PATH := "res://data/region1/world/w4_sites.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
		_cache = d if d is Dictionary else {"sites": []}
	return _cache


## The live W4 site with this id ("w4_grove_duskbriar") in WorldGen.sites, or {}.
static func site(r1id: String) -> Dictionary:
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) == r1id:
			return s
	return {}


static func plan(out: Array[Dictionary]) -> void:
	if OS.get_cmdline_user_args().has("--w4off") or OS.get_cmdline_user_args().has("--r1worldoff"):      # QA A/B
		return
	_relocate(out)
	for spec: Dictionary in data().get("sites", []):
		if spec.has("milestones"):
			_milestones(spec, out)
			continue
		var at_a: Array = spec["at"]
		var at := Vector2(float(at_a[0]), float(at_a[1]))
		var pos := at if bool(spec.get("fixed", false)) else _snap(at, spec, out)
		if pos == Vector2.INF:
			push_warning("Region1W4: no ground for %s" % spec["name"])
			continue
		var st := _make(spec, pos, _facing(spec, pos))
		out.append(st)


## Moves planned sites to their canon points AFTER every plan has run (a move inside the plan changes what is free for every later site and
## shifted 18 caves): the Scar Mouth Arena goes from its searched ground next to the Scar to (2864.1, 2586.4), the point of
## data/world/first_region.json; sites standing on its old point (the Scar Mouth Orbs) go with it.
static func _relocate(out: Array[Dictionary]) -> void:
	for rel: Dictionary in data().get("relocate", []):
		var ta: Array = rel["to"]
		var to := Vector2(float(ta[0]), float(ta[1]))
		var old := Vector2.INF
		for s in out:
			if String(s.get("r1id", "")) == String(rel["r1id"]):
				old = s["pos"]
		if old == Vector2.INF:
			continue
		for s in out:
			var p: Vector2 = s["pos"]
			if p.distance_to(old) < 1.0 and (String(s.get("r1id", "")) == String(rel["r1id"]) or bool(rel.get("with_same_point", false))):
				s["pos"] = p + (to - old)


static func _make(spec: Dictionary, pos: Vector2, yaw: float, suffix := "") -> Dictionary:
	var s := RegionSites._site(String(spec["name"]), String(spec["kind"]), pos, yaw, float(spec["clear"]), bool(spec.get("flatten", false)))
	s["r1id"] = String(spec["id"]) + suffix
	s["covers"] = spec.get("covers", [])
	for p: Array in spec["parts"]:
		RegionSites._part(s, String(p[0]), Vector2(float(p[1]), float(p[2])), deg_to_rad(float(p[3])), int(p[4]) != 0)
		if float(p[5]) != 0.0:
			(s["parts"][s["parts"].size() - 1] as Array).append(float(p[5]))
	for l: Array in spec.get("lights", []):
		var col: Array = l[3]
		s["lights"].append([Vector3(float(l[0]), float(l[1]), float(l[2])), Color(float(col[0]), float(col[1]), float(col[2])), float(l[4]), bool(l[5])])
	var x: Dictionary = spec.get("x", {})
	if not x.is_empty():
		s["x"] = x
	return s


## Groves and markers turn their face toward the nearest settlement (the way a visitor comes); others face south.
static func _facing(spec: Dictionary, pos: Vector2) -> float:
	if bool(spec.get("fixed", false)):
		return 0.0
	var best := Vector2.INF
	var bd := INF
	for s in WorldGen.settlements:
		var d := pos.distance_to(s["pos"])
		if d < bd:
			bd = d
			best = s["pos"]
	return RegionSites._yaw_to((best - pos).normalized()) if best != Vector2.INF else 0.0


## Nearest good ground to `at`: rings of 16 candidates every 6 m up to `snap`; score = distance + slope penalty.
static func _snap(at: Vector2, spec: Dictionary, out: Array[Dictionary]) -> Vector2:
	var snap := float(spec.get("snap", 0.0))
	var r := float(spec["clear"]) + 2.0
	var slope_max := float(spec.get("slope", 0.2))
	var bank := bool(spec.get("bank", false))
	var best := Vector2.INF
	var best_score := INF
	var rr := 0.0
	while rr <= snap:
		var n := 1 if rr == 0.0 else 16
		for i in n:
			var q := at + Vector2.from_angle(TAU * i / n + rr) * rr
			if not _ok(q, r, out, bank):
				continue
			var sl := RegionSites._slope(q)
			if sl > slope_max:
				continue
			var score := rr + sl * 90.0
			if score < best_score:
				best_score = score
				best = q
		if best != Vector2.INF and rr > best_score:      # nothing farther can beat what is found
			break
		rr += 6.0
	return best


static func _ok(q: Vector2, r: float, out: Array[Dictionary], bank: bool) -> bool:
	if not bank:
		return RegionSites._free(q, r, out, 4.0)
	# A river/lake marker: dry, off the road, clear of settlements and other sites, but within 40 m of the water.
	if not WorldGen.in_bounds(q, 300.0):
		return false
	if WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 9.0) or not WorldGen.near_water(q.x, q.y, 45.0):
		return false
	if WorldGen.road_distance(q.x, q.y) < r + 4.0:
		return false
	for s in WorldGen.settlements:
		if q.distance_to(s["pos"]) < float(s["radius"]) * 1.15 + r:
			return false
	for o in out:
		if q.distance_to(o["pos"]) < float(o["clear"]) + r + 2.0:
			return false
	return true


## Posts every `spacing` m along the road nearest to `near`, 5-6 m off the verge, alternating sides, facing the road.
static func _milestones(spec: Dictionary, out: Array[Dictionary]) -> void:
	var m: Dictionary = spec["milestones"]
	var na: Array = m["near"]
	var near := Vector2(float(na[0]), float(na[1]))
	var segs_a: PackedVector2Array = WorldGen._road_a
	var segs_b: PackedVector2Array = WorldGen._road_b
	if segs_a.is_empty():
		return
	var bi := -1
	var bd := INF
	var start := near
	for i in segs_a.size():
		var cp := Geometry2D.get_closest_point_to_segment(near, segs_a[i], segs_b[i])
		var d := near.distance_to(cp)
		if d < bd:
			bd = d
			bi = i
			start = cp
	var dir := (segs_b[bi] - segs_a[bi]).normalized()
	var count := int(m["count"])
	var spacing := float(m["spacing"])
	var side := float(m["side"])
	var n := 0
	for k in range(-count / 2, count / 2 + 1):
		var target := start + dir * spacing * k
		# Pull the target onto the road network (the road bends away from the first segment's line).
		var rp := target
		var rd := INF
		var rseg := -1
		for i in segs_a.size():
			var cp := Geometry2D.get_closest_point_to_segment(target, segs_a[i], segs_b[i])
			var d := target.distance_to(cp)
			if d < rd:
				rd = d
				rp = cp
				rseg = i
		if rd > spacing * 0.5:
			continue
		var nrm := Vector2(-(segs_b[rseg] - segs_a[rseg]).y, (segs_b[rseg] - segs_a[rseg]).x).normalized()
		var q := rp + nrm * side * (1.0 if k % 2 == 0 else -1.0)
		if WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 3.0) or not RegionSites._free(q, 1.5, out, 3.0, true):
			continue
		var st := _make(spec, q, RegionSites._yaw_to((rp - q).normalized()), "_%d" % n)
		out.append(st)
		n += 1
