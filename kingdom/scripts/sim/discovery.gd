extends RefCounted
## Which named places the player has found. The place list is rebuilt from the
## world (settlements, region sites, lore places, monster camps) and never saved;
## only the set of discovered ids is, so a save survives changes to the layout.
##
## Place: {id, name, kind, category: "settlement"|"camp"|"site"|"lore",
##         pos: Vector2, radius (trigger distance), hostile: bool,
##         travel: bool, travel_pos: Vector2 (safe arrival point for fast travel)}
##
## Usage: `var d := preload("res://scripts/sim/discovery.gd").new()`,
## `d.build_from_world(Life.lore.places_in_region())`, then `d.update(p)` a few
## times a second; it returns the places found on that call.
## Save: snapshot["discovery"] = d.serialize(); d.deserialize(snapshot["discovery"]).

signal place_discovered(place: Dictionary)

const SAVE_VERSION := 1
const TRIGGER_RADIUS := 40.0     # metres: how close counts as "found" for small places
const MAX_TRIGGER := 200.0       # big areas (a forest, a castle) trigger at their edge, capped
const MERGE_DISTANCE := 30.0     # a lore place this close to a known place is the same place
const CAMP_KINDS := ["goblin_warren", "orc_village"]
const HOSTILE_KINDS := ["goblin_warren", "orc_village", "bandit_camp", "rift"]
const TRAVEL_KINDS := ["village", "town", "castle", "capital", "waystation"]

const KIND_LABELS := {
	"village": "Village", "town": "Market Town", "castle": "Royal Castle", "capital": "Royal Capital",
	"farm": "Farmstead", "bridge": "River Crossing", "waystation": "Waystation", "wayshrine": "Wayshrine",
	"shrine": "Ruined Shrine", "ruined_shrine": "Ruined Shrine", "hollow": "Hidden Hollow",
	"hidden_place": "Hidden Place", "bandit_camp": "Bandit Camp", "tower_ruin": "Ancient Ruin",
	"mine": "Mine", "watchfort": "Watchfort", "rift": "The Rift", "lake": "Lake", "river": "River",
	"forest": "Forest", "road": "Road", "goblin_warren": "Goblin Warren",
	"orc_village": "Orc Stronghold", "academy": "Academy",
}

var places: Array[Dictionary] = []
var found: Dictionary = {}       # id -> day found (int)
var _by_id: Dictionary = {}      # id -> index into places


static func kind_label(kind: String) -> String:
	return KIND_LABELS.get(kind, kind.capitalize())


## Builds the place list from WorldGen's statics plus the lore places
## (Life.lore.places_in_region(), or first_region.json when none are given).
func build_from_world(lore_places: Array = []) -> void:
	if lore_places.is_empty():
		lore_places = _load_region_places()
	build(WorldGen.settlements, WorldGen.sites, lore_places, WorldGen.camp_grounds)


## Pure form of build_from_world, for tests: every input is plain data.
func build(settlements: Array, sites: Array, lore_places: Array, camps: Array) -> void:
	places.clear()
	_by_id.clear()
	for s: Dictionary in settlements:
		var p: Vector2 = s["pos"]
		var r := float(s.get("radius", TRIGGER_RADIUS))
		_add({"id": "settlement:%s" % s["name"], "name": String(s["name"]), "kind": String(s.get("kind", "village")),
			"category": "settlement", "pos": p, "radius": clampf(r, TRIGGER_RADIUS, MAX_TRIGGER), "hostile": false,
			"travel": true, "travel_pos": _settlement_arrival(s)})
	# Camps take their names from the lore places they were laid out from.
	for i in camps.size():
		var c: Dictionary = camps[i]
		var cp: Vector2 = c["pos"]
		var src := {}
		for pl: Dictionary in lore_places:
			if String(pl.get("kind", "")) in CAMP_KINDS and _vec(pl.get("pos")).distance_to(cp) < 8.0:
				src = pl
				break
		var kind := String(src.get("kind", "goblin_warren"))
		_add({"id": "camp:%s" % src.get("id", str(i)), "name": String(src.get("name", "Monster Camp")), "kind": kind,
			"category": "camp", "pos": cp, "radius": clampf(float(c.get("radius", 30.0)) + 15.0, TRIGGER_RADIUS, MAX_TRIGGER),
			"hostile": true, "travel": false, "travel_pos": cp})
	for s: Dictionary in sites:
		var kind := String(s.get("kind", ""))
		if kind == "waystone" or kind == "roadside":
			continue
		var p: Vector2 = s["pos"]
		var travel := kind in TRAVEL_KINDS
		var arrive := p
		if travel:
			# Sites face their road (+y local = front, see RegionSites): arrive out front.
			var yaw := float(s.get("yaw", 0.0))
			arrive = p + Vector2(sin(yaw), cos(yaw)) * maxf(float(s.get("clear", 0.0)) - 4.0, 6.0)
		_add({"id": "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)], "name": String(s["name"]), "kind": kind,
			"category": "site", "pos": p, "radius": clampf(float(s.get("clear", 0.0)) + 10.0, TRIGGER_RADIUS, MAX_TRIGGER),
			"hostile": kind in HOSTILE_KINDS, "travel": travel, "travel_pos": arrive})
	for pl: Dictionary in lore_places:
		if bool(pl.get("hidden", false)):
			continue
		var kind := String(pl.get("kind", ""))
		var p := _vec(pl.get("pos"))
		var pname := String(pl.get("name", ""))
		if pname.is_empty():
			continue
		var same := _duplicate_of(pname, p)
		if not same.is_empty():
			# A generic site ("Bridge") laid out from this lore place takes its proper name.
			if same["category"] == "site" and same["kind"] == kind:
				same["name"] = pname
			continue
		var r := float(pl.get("radius", 0.0))
		_add({"id": "lore:%s" % pl.get("id", pname), "name": pname, "kind": kind, "category": "lore", "pos": p,
			"radius": clampf(r, TRIGGER_RADIUS, MAX_TRIGGER), "hostile": kind in HOSTILE_KINDS,
			"travel": kind in TRAVEL_KINDS, "travel_pos": p})


func place(id: String) -> Dictionary:
	return places[_by_id[id]] if _by_id.has(id) else {}


func is_discovered(id: String) -> bool:
	return found.has(id)


func discovered_count() -> int:
	var n := 0
	for pl in places:
		if found.has(pl["id"]):
			n += 1
	return n


## Marks a place found; returns true only the first time.
func discover(id: String, day := 0) -> bool:
	if found.has(id) or not _by_id.has(id):
		return false
	found[id] = day
	place_discovered.emit(place(id))
	return true


## Checks the player's position; returns the places discovered by this call,
## nearest first (entering two overlapping places on one step finds both).
func update(p: Vector2, day := 0) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for pl in places:
		# Distance first: the 8 x 8 km world has a few hundred places and only the near ones need a lookup.
		if p.distance_squared_to(pl["pos"]) <= float(pl["radius"]) * float(pl["radius"]) and not found.has(pl["id"]):
			hits.append(pl)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return p.distance_squared_to(a["pos"]) < p.distance_squared_to(b["pos"]))
	for pl in hits:
		discover(pl["id"], day)
	return hits


## Places within `radius` of p (only discovered ones unless `all`), nearest first.
func nearby(p: Vector2, radius: float, all := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r2 := radius * radius
	for pl in places:
		if (all or found.has(pl["id"])) and p.distance_squared_to(pl["pos"]) <= r2:
			out.append(pl)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return p.distance_squared_to(a["pos"]) < p.distance_squared_to(b["pos"]))
	return out


## Discovered places the player may fast travel to.
func travel_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pl in places:
		if pl["travel"] and found.has(pl["id"]):
			out.append(pl)
	return out


func serialize() -> Dictionary:
	return {"version": SAVE_VERSION, "found": found.duplicate()}


func deserialize(d: Dictionary) -> void:
	found.clear()
	var f: Variant = d.get("found", {})
	if f is Dictionary:
		for id: Variant in f:
			found[String(id)] = int(f[id])
	elif f is Array:               # tolerate a plain id list
		for id: Variant in f:
			found[String(id)] = 0


# --- internals -------------------------------------------------------------------

func _add(pl: Dictionary) -> void:
	if _by_id.has(pl["id"]):
		return
	_by_id[pl["id"]] = places.size()
	places.append(pl)


func _duplicate_of(pname: String, p: Vector2) -> Dictionary:
	for other in places:
		if other["name"] == pname or (other["pos"] as Vector2).distance_to(p) < MERGE_DISTANCE:
			return other
	return {}


## Just outside a gate, on the road: never inside a house or the market well.
static func _settlement_arrival(s: Dictionary) -> Vector2:
	var p: Vector2 = s["pos"]
	var r := float(s.get("radius", 60.0))
	if s.has("id") and not WorldGen.roads.is_empty():
		var gates := WorldGen.gate_angles(s)
		if not gates.is_empty():
			return p + Vector2(cos(gates[0]), sin(gates[0])) * (r + 8.0)
	return p + Vector2(0.0, r + 8.0)


static func _vec(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _load_region_places() -> Array:
	var path := "res://data/world/first_region.json"
	if not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("places", []) if data is Dictionary else []
