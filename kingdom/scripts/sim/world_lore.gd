class_name RAWorldLore
extends RefCounted
## The world's peoples and powers, loaded from data/world/*.json: races,
## cultures, nations, sects, tribes, bloodlines and the first region's places.
##
## Usage:
##   var lore := RAWorldLore.new()        # loads res://data/world
##   lore.culture("caldric")["greeting"]
##   lore.random_name("seirune", rng)     # "Amagiri Tsubane"
##   lore.places_in_region()              # pos converted to Vector2 (x, z)

const DATA_DIR := "res://data/world"
const FILES := ["races", "cultures", "nations", "sects", "tribes_bloodlines", "first_region"]

## Raw parsed files by name (see FILES).
var files: Dictionary = {}
## Parse errors by file name; empty when everything loaded.
var errors: Dictionary = {}

var races: Dictionary = {}       # id -> Dictionary
var cultures: Dictionary = {}
var nations: Dictionary = {}
var sects: Dictionary = {}
var tribes: Dictionary = {}
var bloodlines: Dictionary = {}
var places: Dictionary = {}      # id -> place (pos as Vector2, path as PackedVector2Array)
var region: Dictionary = {}      # first_region.json without "places"


func _init(dir := DATA_DIR) -> void:
	load_all(dir)


func load_all(dir := DATA_DIR) -> bool:
	files.clear()
	errors.clear()
	for f: String in FILES:
		var path := "%s/%s.json" % [dir, f]
		if not FileAccess.file_exists(path):
			errors[f] = "missing %s" % path
			continue
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(path))
		if err != OK:
			errors[f] = "line %d: %s" % [json.get_error_line(), json.get_error_message()]
			continue
		if typeof(json.data) != TYPE_DICTIONARY:
			errors[f] = "top level is not an object"
			continue
		files[f] = json.data
	races = _index("races", "races")
	cultures = _index("cultures", "cultures")
	nations = _index("nations", "nations")
	sects = _index("sects", "sects")
	tribes = _index("tribes_bloodlines", "tribes")
	bloodlines = _index("tribes_bloodlines", "bloodlines")
	places.clear()
	region = {}
	if files.has("first_region"):
		var fr: Dictionary = files["first_region"]
		region = fr.duplicate()
		region.erase("places")
		for p: Dictionary in fr.get("places", []):
			places[p["id"]] = _place(p)
	return errors.is_empty()


func _index(file: String, key: String) -> Dictionary:
	var out := {}
	if not files.has(file):
		return out
	for e: Variant in files[file].get(key, []):
		if typeof(e) == TYPE_DICTIONARY and e.has("id"):
			out[e["id"]] = e
	return out


static func _vec(a: Variant) -> Vector2:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func _place(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	out["pos"] = _vec(p.get("pos", [0, 0]))
	if p.has("path"):
		var pts := PackedVector2Array()
		for q: Variant in p["path"]:
			pts.append(_vec(q))
		out["path"] = pts
	return out


# --- Lookups ({} when unknown) ----------------------------------------------

func race(id: String) -> Dictionary:
	return races.get(id, {})


func culture(id: String) -> Dictionary:
	return cultures.get(id, {})


func nation(id: String) -> Dictionary:
	return nations.get(id, {})


func sect(id: String) -> Dictionary:
	return sects.get(id, {})


func tribe(id: String) -> Dictionary:
	return tribes.get(id, {})


func bloodline(id: String) -> Dictionary:
	return bloodlines.get(id, {})


func place(id: String) -> Dictionary:
	return places.get(id, {})


## "Given Family" or "Family Given" depending on the culture's name order.
## gender: "male" | "female" | "" (either).
func random_name(culture_id: String, rng: RandomNumberGenerator, gender := "") -> String:
	var c := culture(culture_id)
	if c.is_empty():
		return ""
	var firsts: Dictionary = c["first_names"]
	var g := gender
	if not firsts.has(g):
		g = "male" if rng.randi() % 2 == 0 else "female"
	var given_list: Array = firsts[g]
	var family_list: Array = c["family_names"]
	var given: String = given_list[rng.randi() % given_list.size()]
	var family: String = family_list[rng.randi() % family_list.size()]
	if c.get("name_order", "given_first") == "family_first":
		return "%s %s" % [family, given]
	return "%s %s" % [given, family]


## Ids of the sects and academies allowed to travel to Xiava's Lake.
func sects_with_xiava_access() -> Array[String]:
	var out: Array[String] = []
	for id: String in sects:
		if sects[id].get("xiava_access", false):
			out.append(id)
	return out


## The first region's places (pos as Vector2 x/z metres from Ashford).
## kind filters by place kind ("lake", "river", "orc_village", ...).
func places_in_region(kind := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in places:
		var p: Dictionary = places[id]
		if kind.is_empty() or p.get("kind", "") == kind:
			out.append(p)
	return out


func sects_of(nation_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in sects:
		if sects[id].get("nation", "") == nation_id:
			out.append(id)
	return out


## Every evolution step a race can take, as the JSON gives them.
func evolutions(race_id: String) -> Array:
	return race(race_id).get("evolution", [])


## Races someone of race_id can be transformed into (blood rites etc.).
func transformations_from(race_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in races:
		var t: Dictionary = races[id].get("transformation", {})
		if t.get("possible", false) and (t.get("from", []) as Array).has(race_id):
			out.append(id)
	return out


## Diplomatic stance of a toward b ("allied" .. "war"; "self" for the same).
func stance(a: String, b: String) -> String:
	if a == b:
		return "self"
	return str(nation(a).get("relations", {}).get(b, "neutral"))


## Roll whether a newborn of this race/culture carries a dormant bloodline.
## Returns the bloodline id or "".
func roll_bloodline(race_id: String, culture_id: String, rng: RandomNumberGenerator) -> String:
	var rarities: Dictionary = files.get("tribes_bloodlines", {}).get("rarities", {})
	for id: String in bloodlines:
		var b: Dictionary = bloodlines[id]
		if not (b.get("races", []) as Array).has(race_id):
			continue
		if not (b.get("cultures", []) as Array).has(culture_id):
			continue
		var chance: float = rarities.get(b.get("rarity", "common"), {}).get("birth_chance", 0.0)
		if rng.randf() < chance:
			return id
	return ""
