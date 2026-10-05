extends RefCounted
## Named path teachers (data/powers/teachers.json): the in-person source of path techniques, the alternative to a
## manual. Pure rules; institutions (education.gd) roll the people, `learn_from` applies the terms to a power_paths
## module. A taught lesson is permanent: the teacher id is stored in power_paths.teachers() and every technique whose
## req.teacher lists it opens (PowerTrees.state).

const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const PATH := "res://data/powers/teachers.json"
const WAYS := ["quest", "favour", "gold"]       # free ways are tried before the paying one

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = (d as Dictionary).get("teachers", {}) if d is Dictionary else {}
	return _cache


static func ids() -> Array:
	return data().keys()


static func teacher(id: String) -> Dictionary:
	return data().get(id, {})


## The teacher types seated at an institution kind (or "barracks").
static func at_venue(kind: String) -> Array:
	var out: Array = []
	for id: String in data():
		if (data()[id]["venues"] as Array).has(kind):
			out.append(id)
	return out


## Deterministic named person for an institution: {id, name, title, path, ...}.
static func person(id: String, seed_text: String) -> Dictionary:
	var t := teacher(id)
	if t.is_empty():
		return {}
	var names: Array = t.get("names", [id])
	var d: Dictionary = t.duplicate(true)
	d["id"] = id
	d["name"] = String(names[absi(hash(seed_text + id)) % names.size()])
	return d


## The techniques this teacher opens (every technique listing the id in req.teacher).
static func lessons(id: String) -> Array:
	var out: Array = []
	for tid: String in PowerTrees.technique_ids():
		var req: Dictionary = PowerTrees.technique(tid).get("req", {})
		var ts: Array = req.get("teacher", []) if req.get("teacher", []) is Array else [req["teacher"]]
		if ts.has(id):
			out.append(tid)
	return out


## Terms check. ctx: gold, favour (standing), quests (done quest ids), path_level (of the teacher's path), known_path.
## -> {ok, via: "quest"|"favour"|"gold"|"all", fee, reasons: [String]}
static func check(id: String, ctx: Dictionary) -> Dictionary:
	var t := teacher(id)
	if t.is_empty():
		return {"ok": false, "via": "", "fee": 0, "reasons": ["Nobody by that name."]}
	var reasons: Array[String] = []
	var ways: Dictionary = t["ways"]
	var path := String(t.get("path", ""))
	var plevel := int(ctx.get("path_level", 0))
	if path != "" and bool(ctx.get("known_path", false)) and plevel < int(t.get("min_path_level", 1)):
		reasons.append("Your %s level must reach %d first." % [PowerTrees.path_name(path), int(t.get("min_path_level", 1))])
	var met := {}
	if ways.has("quest"):
		met["quest"] = (ctx.get("quests", []) as Array).has(String(ways["quest"]))
	if ways.has("favour"):
		met["favour"] = float(ctx.get("favour", 0.0)) >= float(ways["favour"])
	if ways.has("gold"):
		met["gold"] = int(ctx.get("gold", 0)) >= int(ways["gold"])
	var fee := 0
	var via := ""
	if String(t.get("require", "any")) == "all":
		for k: String in met:
			if not bool(met[k]):
				reasons.append(_way_text(k, ways[k]))
		via = "all"
		fee = int(ways.get("gold", 0))
	else:
		for k: String in WAYS:
			if met.has(k) and bool(met[k]):
				via = k
				fee = int(ways["gold"]) if k == "gold" else 0
				break
		if via == "":
			var opts: Array = []
			for k: String in WAYS:
				if ways.has(k):
					opts.append(_way_text(k, ways[k]))
			reasons.append("Needs one of: " + "; ".join(PackedStringArray(opts)) + ".")
	return {"ok": reasons.is_empty(), "via": via, "fee": fee, "reasons": reasons}


static func _way_text(way: String, v: Variant) -> String:
	match way:
		"gold":
			return "%d gold" % int(v)
		"favour":
			return "standing %d at this school" % int(v)
		_:
			return "the deed '%s'" % String(v).replace("_", " ")


## Studies under the teacher: checks the terms, takes the path on if the character has none of it (the second-path
## gate applies), records the teacher and pays any milestone. -> {ok, text, fee, reasons}. The caller deducts `fee`.
static func learn_from(id: String, pp: Object, ctx: Dictionary = {}) -> Dictionary:
	var t := teacher(id)
	if t.is_empty() or pp == null:
		return {"ok": false, "text": "", "fee": 0, "reasons": ["Nobody by that name."]}
	if (pp.call("teachers") as Array).has(id):
		return {"ok": false, "text": "You already study under them.", "fee": 0, "reasons": ["Already taught."]}
	var path := String(t.get("path", ""))
	var c := ctx.duplicate()
	var knows := path == "" or bool(pp.call("knows", path))
	c["known_path"] = knows
	if path != "" and knows:
		c["path_level"] = int(pp.call("level", path))
	var chk := check(id, c)
	if not bool(chk["ok"]):
		return {"ok": false, "text": String(" ".join(PackedStringArray(chk["reasons"]))), "fee": 0, "reasons": chk["reasons"]}
	if path != "" and not knows:
		var g: Dictionary = pp.call("learn_checked", path, "teacher", c.get("profile_extra", {}))
		if not bool(g["ok"]):
			return {"ok": false, "text": " ".join(PackedStringArray(g["reasons"])), "fee": 0, "reasons": g["reasons"]}
	pp.call("add_teacher", id)
	for mid: Variant in t.get("gives", []):             # the teacher hands over a text of their own
		pp.call("learn_manual", String(mid))
	var grants: Dictionary = t.get("grants", {})
	if grants.has("milestone"):
		var prim := String(pp.call("primary_path"))
		if prim != "":
			pp.call("add_milestone", prim, String(grants["milestone"]))
	var n := lessons(id).size()
	return {"ok": true, "text": "%s takes you as a pupil (%s)." % [String(t["title"]), "%d lessons open" % n if n > 0 else "a trial passed"],
		"fee": int(chk["fee"]), "reasons": []}
