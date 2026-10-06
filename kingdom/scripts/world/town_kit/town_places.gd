extends RefCounted
## Where a town's places are in the live world, from the town file's `anchors`, `doors` and `places` (town_data.gd). Everything
## derives from WorldGen.settlements and WorldGen.sites, so it follows the layout if a site moves.
## Preload, no class_name; every function is static.
##
##   places(tid)           {place id: {pos: Vector2, radius: float}}   for enter_area / kill events (unresolved ones left out)
##   place_pos(tid, id)    Vector2.INF when unknown
##   door_of_site(tid, id) the door-side spot of a work site (`doors`), Vector2.INF for anything else
##   resolve(tid, def)     world XZ of any {anchor | building, at} definition (clues, stashes, livestock)
##   frame(tid, anchor)    {pos, yaw} of an anchor frame (settlement: yaw 0, world axes; site; landmark of the plan), {} when unresolved

const TownData := preload("res://scripts/world/town_kit/town_data.gd")


static func settlement(tid: String) -> Dictionary:
	var nm := String(TownData.town(tid).get("settlement", ""))
	for s in WorldGen.settlements:
		if String(s["name"]) == nm:
			return s
	return {}


## The WorldGen site an anchor names (by r1id, else by exact name), {} when the world has none.
static func site_of(def: Dictionary) -> Dictionary:
	var r1id := String(def.get("r1id", ""))
	var nm := String(def.get("name", ""))
	for s in WorldGen.sites:
		if r1id != "" and String(s.get("r1id", "")) == r1id:
			return s
		if r1id == "" and nm != "" and String(s["name"]) == nm:
			return s
	return {}


## Site-local offset -> world XZ (the same transform RegionDressing places site parts with).
static func to_world(site: Dictionary, local: Vector2) -> Vector2:
	var yaw: float = site["yaw"]
	return (site["pos"] as Vector2) + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


## Unit vector the site's +Y (front) points to in the world.
static func front(site: Dictionary) -> Vector2:
	return to_world(site, Vector2(0, 1)) - (site["pos"] as Vector2)


## The site of a named anchor of town `tid` ({} for the settlement anchor or an unknown one).
static func anchor_site(tid: String, anchor: String) -> Dictionary:
	var def: Dictionary = (TownData.town(tid).get("anchors", {}) as Dictionary).get(anchor, {})
	if String(def.get("kind", "")) != "site":
		return {}
	return site_of(def)


## The plan landmark of settlement `tid` whose asset is `def["asset"]` ("castle" = Kingsreach's keep): {pos, yaw} or {}.
static func landmark_of(tid: String, def: Dictionary) -> Dictionary:
	var s := settlement(tid)
	if s.is_empty():
		return {}
	for lm: Dictionary in (s["plan"] as Dictionary).get("landmarks", []):
		if String(lm.get("asset", "")) == String(def.get("asset", "")):
			return {"pos": lm["pos"], "yaw": float(lm.get("yaw", 0.0))}
	return {}


## {pos, yaw} of a named anchor (see town_data.gd `anchors`); {} when the world has no such place. Site-local x is right, y is front.
static func frame(tid: String, anchor: String) -> Dictionary:
	var a: Dictionary = (TownData.town(tid).get("anchors", {}) as Dictionary).get(anchor, {})
	match String(a.get("kind", "")):
		"settlement":
			var s := settlement(tid)
			return {"pos": s["pos"], "yaw": 0.0} if not s.is_empty() else {}
		"site":
			return site_of(a)
		"landmark":
			return landmark_of(tid, a)
	return {}


static func _vec(a: Variant) -> Vector2:
	return Vector2(float((a as Array)[0]), float((a as Array)[1])) if a is Array and (a as Array).size() >= 2 else Vector2.ZERO


## World XZ of a {anchor | building, at} definition. Vector2.INF when the anchor does not exist in this world.
static func resolve(tid: String, def: Dictionary) -> Vector2:
	var at := _vec(def.get("at", [0, 0]))
	if def.has("building"):
		var door: Vector2 = (load("res://scripts/world/town_kit/town_lots.gd") as GDScript).call("door_pos", String(def["building"]))
		return door + at if door != Vector2.INF else Vector2.INF
	var a: Dictionary = (TownData.town(tid).get("anchors", {}) as Dictionary).get(String(def.get("anchor", "")), {})
	var p := Vector2.INF
	match String(a.get("kind", "")):
		"settlement":
			var s := settlement(tid)
			p = (s["pos"] as Vector2) + at if not s.is_empty() else Vector2.INF
		"site":
			var site := site_of(a)
			p = to_world(site, at) if not site.is_empty() else Vector2.INF
		"landmark":
			var lm := landmark_of(tid, a)
			p = to_world(lm, at) if not lm.is_empty() else Vector2.INF
	if p != Vector2.INF and bool(def.get("dry", false)):
		p = dry_near(p)
	return p


## `p` itself when it is dry ground, else the nearest dry point on rings around it (deterministic).
static func dry_near(p: Vector2) -> Vector2:
	if not WorldGen.near_water(p.x, p.y, 4.0):
		return p
	for ring in range(1, 9):
		for k in 12:
			var a := TAU * float(k) / 12.0
			var q := p + Vector2(cos(a), sin(a)) * (10.0 * float(ring))
			if not WorldGen.near_water(q.x, q.y, 4.0):
				return q
	return p


## {id: {pos: Vector2, radius: float}} for the town's places, unresolved entries left out.
static func places(tid: String) -> Dictionary:
	var out := {}
	for p: Dictionary in TownData.town(tid).get("places", []):
		var pos := resolve(tid, p)
		if pos != Vector2.INF:
			out[String(p["id"])] = {"pos": pos, "radius": float(p["radius"])}
	return out


static func place_pos(tid: String, id: String) -> Vector2:
	var p: Dictionary = places(tid).get(id, {})
	return p["pos"] if not p.is_empty() else Vector2.INF


## Door-side position of a work site (`doors`), Vector2.INF for anything else.
static func door_of_site(tid: String, bid: String) -> Vector2:
	var def: Dictionary = (TownData.town(tid).get("doors", {}) as Dictionary).get(bid, {})
	if def.is_empty():
		return Vector2.INF
	return resolve(tid, def)


## Same for whichever town owns the id (ids start with the town id).
static func door_of_any(bid: String) -> Vector2:
	for tid: String in TownData.ids():
		if (TownData.town(tid).get("doors", {}) as Dictionary).has(bid):
			return door_of_site(tid, bid)
	return Vector2.INF
