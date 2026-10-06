extends RefCounted
## The town kit's data layer: one JSON file per settlement in data/region1/towns/<id>.json (scripts/world/town_kit/town_data.gd).
## Any settlement with a file there gets the living-place treatment (roster, forced lots, keepers, places, quests, threat,
## livestock); nothing else in the game names a town. Pure functions over the files: no autoloads, no nodes.
##
## File shape (every key but id, settlement and residents is optional):
##   id, settlement (the WorldGen name), kind, population, hub_name, dialogue_dir, identity {arch, flavour, trade}
##   residents [{id, name, age, role, job, home, work, traits[], schedule[], dialogue{greeting[], rumour[], opinions{}},
##               relationships{}, child?, bind?, station?, ...}]
##   lots      {required [{btype, asset, bid}], homes N, sites {site id: label}}
##   anchors   {name: {kind: "settlement"} | {kind: "site", r1id | name} | {kind: "landmark", asset}}   reference frames for places, doors, livestock
##             (landmark = a building of the settlement's plan by asset, local metres like a site: "castle" is Kingsreach's keep)
##   doors     {door id: {anchor, at [x, y]}}                                  where a work site's door is (a resident's `work`)
##   default_spots [id, ...]   ids a resident's home/work may name that deliberately have no door: they use the settlement's shared spot
##   places    [{id, anchor | building, at [x, y], radius, dry?}]              quest places (enter_area / kill places)
##   quests    ["res://data/quests/<id>/<quest>.json", ...]
##   clues     [{id, anchor | building, at, h, target, note, prop}]            kit-placed Investigate clues
##   stashes   [{id, item, count, anchor | building, at, quest, stage, target, say, prop}]   goods a Collect stage lets you take
##   threat    {species, spawner, group, den_ring [near, far], night [from, to], probe_chance, probe_place, probe_near,
##              probe_count [n, n_every_third_day], probe_from, probe_territory, ambush_from, ambush_territory}
##   livestock {groups [{anchor, at, kinds [[kind, n]], radius, tag}], pens [{anchor, at, size [x, y], yaw?}]}   a pen on the settlement
##             anchor lies along the world axes turned by `yaw` (radians; its gate side faces local +y), and is skipped on wet ground
##   outdoor_work true   named craftsmen and merchants whose `work` is a door (a work site, the keep gate) stand outside there all day
##             (WorldSim.is_indoors would hide 3 in 4 of them "inside the shop": a yard has no inside)
##   special   "res://scripts/.../special.gd"   the town's one-off code (see town_hub.gd for the hooks)
## `anchor` frames: settlement = world metres from the settlement centre; site = site-local metres (x right, y front).
## Preload this script (no class_name); every function is static.

const DIR := "res://data/region1/towns"
const BTYPES := ["tavern", "smithy", "general_shop", "bakery", "guard_post", "healer"]
const ANCHOR_KINDS := ["settlement", "site", "landmark"]
const PHASES := ["home", "work", "market", "inn", "temple", "train", "social"]

static var _docs: Dictionary = {}          # id -> parsed file
static var _ids: Array[String] = []
static var _scanned := false


static func clear_cache() -> void:
	_docs.clear()
	_ids.clear()
	_scanned = false


## Ids of every town file (sorted), i.e. every settlement with the treatment.
static func ids() -> Array[String]:
	if not _scanned:
		_scanned = true
		_ids.clear()
		if DirAccess.dir_exists_absolute(DIR):
			for f: String in DirAccess.get_files_at(DIR):
				if f.ends_with(".json"):
					var id := f.trim_suffix(".json")
					if not town(id).is_empty():
						_ids.append(id)
		_ids.sort()
	return _ids


static func town(id: String) -> Dictionary:
	if _docs.has(id):
		return _docs[id]
	var path := "%s/%s.json" % [DIR, id]
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			d = _normalise(v)
	if not d.is_empty():
		_docs[id] = d
	return d


## The town file of a WorldGen settlement name ("" when it has none).
static func id_of_settlement(name: String) -> String:
	for id: String in ids():
		if String(town(id).get("settlement", "")) == name:
			return id
	return ""


static func has_town(settlement_name: String) -> bool:
	return id_of_settlement(settlement_name) != ""


static func residents(id: String) -> Array:
	return town(id).get("residents", [])


## JSON numbers are floats; the few fields the game reads as ints are converted once, on load.
static func _normalise(d: Dictionary) -> Dictionary:
	for e: Dictionary in d.get("residents", []):
		e["job"] = int(e.get("job", 4))
		e["age"] = int(e.get("age", 30))
	var lots: Dictionary = d.get("lots", {})
	if lots.has("homes"):
		lots["homes"] = int(lots["homes"])
	var ls: Dictionary = d.get("livestock", {})
	for g: Dictionary in ls.get("groups", []):
		var kinds: Array = []
		for k: Array in g.get("kinds", []):
			kinds.append([String(k[0]), int(k[1])])
		g["kinds"] = kinds
	return d


# --- validation ---------------------------------------------------------------------------------

## Problems with a town document, empty when it is sound. `check_files` also opens the quest files and the special script.
static func validate(d: Dictionary, check_files := true) -> PackedStringArray:
	var errs := PackedStringArray()
	var id := String(d.get("id", ""))
	if id == "":
		errs.append("town has no id")
		return errs
	if String(d.get("settlement", "")) == "":
		errs.append("%s: no settlement" % id)
	var people: Array = d.get("residents", [])
	if people.is_empty():
		errs.append("%s: no residents" % id)
	var ids_seen := {}
	var names_seen := {}
	for e: Dictionary in people:
		var rid := String(e.get("id", ""))
		if rid == "" or ids_seen.has(rid):
			errs.append("%s: resident id '%s' missing or duplicated" % [id, rid])
		ids_seen[rid] = true
		var nm := String(e.get("name", ""))
		if nm == "" or names_seen.has(nm):
			errs.append("%s/%s: name '%s' missing or duplicated" % [id, rid, nm])
		names_seen[nm] = true
		if not (e.has("role") and e.has("job") and e.has("schedule")):
			errs.append("%s/%s: needs role, job and schedule" % [id, rid])
		if int(e.get("job", 4)) < 0 or int(e.get("job", 4)) > 5:
			errs.append("%s/%s: job out of range" % [id, rid])
		for s: Dictionary in e.get("schedule", []):
			if not PHASES.has(String(s.get("phase", ""))):
				errs.append("%s/%s: unknown schedule phase '%s'" % [id, rid, s.get("phase", "")])
		var dlg: Dictionary = e.get("dialogue", {})
		if bool(e.get("bind", true)) or bool(e.get("station", false)):
			if (dlg.get("greeting", []) as Array).is_empty() or (dlg.get("rumour", []) as Array).is_empty():
				errs.append("%s/%s: dialogue needs greeting and rumour lines" % [id, rid])
	var lots: Dictionary = d.get("lots", {})
	var bids := {}
	for r: Dictionary in lots.get("required", []):
		if not BTYPES.has(String(r.get("btype", ""))):
			errs.append("%s: unknown lot type '%s'" % [id, r.get("btype", "")])
		var bid := String(r.get("bid", ""))
		if bid == "" or bids.has(bid):
			errs.append("%s: lot bid '%s' missing or duplicated" % [id, bid])
		bids[bid] = true
		if String(r.get("asset", "")) == "":
			errs.append("%s/%s: lot has no asset" % [id, bid])
	var homes := int(lots.get("homes", 0))
	for k in homes:
		bids["%s_house_%d" % [id, k + 1]] = true
	var anchors: Dictionary = d.get("anchors", {})
	for a: String in anchors:
		var def: Dictionary = anchors[a]
		if not ANCHOR_KINDS.has(String(def.get("kind", ""))):
			errs.append("%s: anchor '%s' has an unknown kind" % [id, a])
		if String(def.get("kind", "")) == "site" and String(def.get("r1id", def.get("name", ""))) == "":
			errs.append("%s: site anchor '%s' needs r1id or name" % [id, a])
		if String(def.get("kind", "")) == "landmark" and String(def.get("asset", "")) == "":
			errs.append("%s: landmark anchor '%s' needs an asset" % [id, a])
	var doors: Dictionary = d.get("doors", {})
	var defaults: Array = d.get("default_spots", [])
	for k: String in doors:
		if not anchors.has(String(doors[k].get("anchor", ""))):
			errs.append("%s: door '%s' has an unknown anchor" % [id, k])
	var place_ids := {}
	for p: Dictionary in d.get("places", []):
		var pid := String(p.get("id", ""))
		if pid == "" or place_ids.has(pid):
			errs.append("%s: place '%s' missing or duplicated" % [id, pid])
		place_ids[pid] = true
		if not _located(p, anchors, bids, doors):
			errs.append("%s: place '%s' has no valid anchor or building" % [id, pid])
		if float(p.get("radius", 0.0)) <= 0.0:
			errs.append("%s: place '%s' has no radius" % [id, pid])
	for e: Dictionary in people:
		for key: String in ["home", "work"]:
			var ref := String(e.get(key, ""))
			if ref != "" and not bids.has(ref) and not doors.has(ref) and not defaults.has(ref):
				errs.append("%s/%s: %s '%s' is not a lot or a door" % [id, e.get("id", ""), key, ref])
		for other: String in (e.get("relationships", {}) as Dictionary):
			if not ids_seen.has(other):
				errs.append("%s/%s: relationship with unknown '%s'" % [id, e.get("id", ""), other])
		for other2: String in ((e.get("dialogue", {}) as Dictionary).get("opinions", {}) as Dictionary):
			if not ids_seen.has(other2):
				errs.append("%s/%s: opinion of unknown '%s'" % [id, e.get("id", ""), other2])
	for c: Dictionary in d.get("clues", []):
		if String(c.get("id", "")) == "" or not _located(c, anchors, bids, doors):
			errs.append("%s: clue '%s' has no id or location" % [id, c.get("id", "")])
	for s: Dictionary in d.get("stashes", []):
		if String(s.get("id", "")) == "" or String(s.get("item", "")) == "" or not _located(s, anchors, bids, doors):
			errs.append("%s: stash '%s' needs id, item and a location" % [id, s.get("id", "")])
	var th: Dictionary = d.get("threat", {})
	if not th.is_empty():
		if String(th.get("species", "")) == "":
			errs.append("%s: threat has no species" % id)
		if String(th.get("probe_place", "")) != "" and not place_ids.has(String(th["probe_place"])):
			errs.append("%s: threat probe_place '%s' is not a place" % [id, th["probe_place"]])
	for g: Dictionary in (d.get("livestock", {}) as Dictionary).get("groups", []):
		if not anchors.has(String(g.get("anchor", ""))):
			errs.append("%s: livestock group '%s' has an unknown anchor" % [id, g.get("tag", "")])
	for pen: Dictionary in (d.get("livestock", {}) as Dictionary).get("pens", []):
		if not anchors.has(String(pen.get("anchor", ""))) or (pen.get("at", []) as Array).size() < 2 or (pen.get("size", []) as Array).size() < 2:
			errs.append("%s: a livestock pen needs a known anchor, at [x, y] and size [x, y]" % id)
	if check_files:
		for path: String in d.get("quests", []):
			if not FileAccess.file_exists(path):
				errs.append("%s: quest file %s missing" % [id, path])
				continue
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (v is Dictionary):
				errs.append("%s: quest file %s is not JSON" % [id, path])
		var sp := String(d.get("special", ""))
		if sp != "" and not ResourceLoader.exists(sp):
			errs.append("%s: special script %s missing" % [id, sp])
	return errs


static func _located(def: Dictionary, anchors: Dictionary, bids: Dictionary, doors := {}) -> bool:
	if def.has("building"):
		return bids.has(String(def["building"])) or doors.has(String(def["building"]))
	return anchors.has(String(def.get("anchor", ""))) and (def.get("at", []) as Array).size() >= 2


## Every resident name of every town (for the region-wide uniqueness check).
static func all_names() -> Array[String]:
	var out: Array[String] = []
	for id: String in ids():
		for e: Dictionary in residents(id):
			out.append(String(e.get("name", "")))
	return out
