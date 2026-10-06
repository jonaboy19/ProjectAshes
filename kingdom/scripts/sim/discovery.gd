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
const HOSTILE_KINDS := ["goblin_warren", "orc_village", "bandit_camp", "rift", "hideout", "warren_tunnels"]
## Fast travel is a coach between discovered waystations only (travel_rules.gd); every settlement has a coach inn.
const TRAVEL_KINDS := ["waystation", "ferry"]   # ferry: Emberglass Ferry landings (Region 1 look pass), a coach-like node over water

const KIND_LABELS := {
	"village": "Village", "town": "Market Town", "castle": "Royal Castle", "capital": "Royal Capital",
	"farm": "Farmstead", "bridge": "River Crossing", "waystation": "Waystation", "wayshrine": "Wayshrine",
	"shrine": "Ruined Shrine", "ruined_shrine": "Ruined Shrine", "hollow": "Hidden Hollow",
	"hidden_place": "Hidden Place", "bandit_camp": "Bandit Camp", "tower_ruin": "Ancient Ruin",
	"mine": "Mine", "watchfort": "Watchfort", "rift": "The Rift", "lake": "Lake", "river": "River",
	"forest": "Forest", "road": "Road", "goblin_warren": "Goblin Warren",
	"orc_village": "Orc Stronghold", "academy": "Academy",
	"cave": "Cave", "hidden_cave": "Hidden Cave", "old_mine": "Abandoned Mine", "hideout": "Bandit Hideout",
	"warren_tunnels": "Goblin Tunnels", "crypt": "Ancient Crypt",
	# Region 1 world packages (scripts/world/region1_world.gd)
	"keep": "Knightly Keep", "elder_stone": "Elder Stone", "estate": "Crown Estate", "border_gate": "Closed Border",
	"pass": "Snowed-shut Pass", "scar_arena": "Rift Mouth", "chapel": "Mission Chapel", "caravan_camp": "Caravan Camp",
	"landmark": "Local Landmark", "glade": "Sacred Glade", "windmill_hill": "Windmill Hill",
	# Region 1 look pass landmarks (scripts/region1/region1_landmarks.gd, data/region1/landmarks.json)
	"valley": "Valley", "waterfall": "Waterfall", "standing_stones": "Standing Stones", "ruins": "Ruins", "lookout": "Lookout",
	"old_bridge": "Old Bridge", "ferry": "Ferry", "sunken_chapel": "Sunken Chapel", "bones": "Giant's Bones",
	# Exploration secrets (scripts/world/hidden_valley.gd, region_pois.gd)
	"hidden_vale": "Hidden Vale", "poi_vista": "Vista", "poi_shrine": "Hidden Shrine", "poi_lore": "Lore Stone",
	"poi_camp": "Abandoned Camp", "poi_herbs": "Herb Patch", "poi_cache": "Buried Cache", "poi_battlefield": "Old Battlefield",
	"poi_fishing": "Fishing Secret", "poi_hermit": "Hermit's Hut", "poi_rift": "Rift Anomaly", "poi_hunter": "Hunter's Camp",
}
## Aliases: WorldGen keeps its names (saves, sims and sprites key on them); the map shows the poster name.
const ALIAS_FILE := "res://data/region1/world/settlements.json"
static var _aliases: Dictionary = {}

var places: Array[Dictionary] = []
var found: Dictionary = {}       # id -> day found (int)
var _by_id: Dictionary = {}      # id -> index into places
## Secret sites ({"secret": true} in WorldGen.sites: the Hidden Vale, exploration POIs) stay out of `places` (map,
## compass, "N of M") until found, so nothing is spoiled. id -> place dict.
var _secret: Dictionary = {}


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
	_secret.clear()
	for s: Dictionary in settlements:
		var p: Vector2 = s["pos"]
		var r := float(s.get("radius", TRIGGER_RADIUS))
		_add({"id": "settlement:%s" % s["name"], "name": display_name(String(s["name"])), "kind": String(s.get("kind", "village")),
			"category": "settlement", "pos": p, "radius": clampf(r, TRIGGER_RADIUS, MAX_TRIGGER), "hostile": false,
			"travel": false, "travel_pos": _settlement_arrival(s)})
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
		if bool(s.get("hidden", false)):
			continue        # hidden entrances join the map only when found: reveal_site()
		var p: Vector2 = s["pos"]
		if bool(s.get("secret", false)):
			var sid := "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)]
			_secret[sid] = {"id": sid, "name": String(s["name"]), "kind": kind, "category": "site", "pos": p,
				"radius": float(s.get("radius", 30.0)), "hostile": false, "travel": false, "travel_pos": p, "secret": true,
				"poi": String(s.get("poi", ""))}
			continue
		var travel := kind in TRAVEL_KINDS
		var arrive := p
		if travel:
			# Sites face their road (+y local = front, see RegionSites): arrive out front.
			var yaw := float(s.get("yaw", 0.0))
			arrive = p + Vector2(sin(yaw), cos(yaw)) * maxf(float(s.get("clear", 0.0)) - 4.0, 6.0)
		var place := {"id": "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)], "name": String(s["name"]), "kind": kind,
			"category": "site", "pos": p, "radius": clampf(float(s.get("clear", 0.0)) + 10.0, TRIGGER_RADIUS, MAX_TRIGGER),
			"hostile": kind in HOSTILE_KINDS, "travel": travel, "travel_pos": arrive}
		if s.has("hint"):
			place["hint"] = String(s["hint"])        # closed exits: the map card explains why (Eastern Gate, Grimfen Pass)
			place["locked"] = bool(s.get("locked", false))
		_add(place)
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
	for sid: String in _secret:      # secrets found before this rebuild (a load) rejoin the list
		if found.has(sid):
			_add(_secret[sid])


## A hidden site (caves behind waterfalls, vines, rockfalls...) found by the player: it joins the place list
## (map, journal "Discoveries") and, with `found_now`, is marked discovered (banner). Idempotent, and also
## called after a load for every already revealed site (the found set is saved, the place list is not).
func reveal_site(s: Dictionary, day := 0, found_now := true) -> bool:
	var p: Vector2 = s["pos"]
	var id := "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)]
	if not _by_id.has(id):
		_add({"id": id, "name": String(s["name"]), "kind": String(s.get("kind", "hidden_cave")), "category": "site", "pos": p,
			"radius": TRIGGER_RADIUS, "hostile": false, "travel": false, "travel_pos": p, "hidden_found": true})
	if found_now:
		return discover(id, day)
	return false


## The poster name for a settlement ("Oakvale" -> "Greenhollow", "Ironmarch" -> "Silverford"), else its own name.
static func display_name(settlement_name: String) -> String:
	if _aliases.is_empty():
		_aliases = {"_": ""}
		if FileAccess.file_exists(ALIAS_FILE):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ALIAS_FILE))
			if d is Dictionary:
				for st: Dictionary in d.get("settlements", []):
					if String(st.get("alias", "")) != "":
						_aliases[String(st["name"])] = String(st["alias"])
	return String(_aliases.get(settlement_name, settlement_name))


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
	if found.has(id):
		return false
	if not _by_id.has(id) and _secret.has(id):
		_add(_secret[id])
	if not _by_id.has(id):
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


## Secret sites: ids, place dicts and counts (the journal lists found ones, only counts the rest).
func secret_ids() -> Array:
	var ids := _secret.keys()
	ids.sort()
	return ids


func secret_place(id: String) -> Dictionary:
	return _secret.get(id, {})


func secret_count(prefix := "", only_found := false) -> int:
	var n := 0
	for id: String in _secret:
		if id.begins_with(prefix) and (not only_found or found.has(id)):
			n += 1
	return n


## A free-form record in the saved set (harvest days of exploration nodes: "res:<id>" -> day). Not a place.
func note(key: String, day := 0) -> void:
	found[key] = day


func noted(key: String) -> bool:
	return found.has(key)


func note_day(key: String, default := -1) -> int:
	return int(found.get(key, default))


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
	for sid: String in _secret:    # found secrets rejoin the place list
		if found.has(sid):
			_add(_secret[sid])


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
