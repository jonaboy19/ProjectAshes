extends RefCounted
## Path trees as data (data/powers/*.json): magic, bending, sect, knight, beast. Each file holds the path's levels,
## sub-paths, manuals, milestones and techniques with unlock requirements; this class loads them and answers the
## questions the game asks: is a technique unlocked / ready / locked / beyond Region 1, why not, is chantless casting
## allowed, what does a second path cost, and what does the Skills tab show.
##
## Everything works on a plain *profile* Dictionary so the rules are testable without scenes:
##   {paths: [..], primary, levels: {path: n}, theory: {path: 0..1}, milestones: {path: [ids]},
##    subpaths: {path: [ids]}, realms: {path: {realm, stage}}, manuals: [ids], teachers: [ids], known: [technique ids],
##    mastery: {technique id: 0..1}, trust: 0..1, level: character level}
## Build one from the live game with profile_from(power_paths, cultivation, extra) or for an NPC with npc_profile().
##
## Rules (docs/design/ACADEMY_PLAN.md "Power systems", docs/balance/PROGRESSION_R1.md):
##   - every path needs cultivation (a realm/stage on its own track), whatever the path;
##   - sect = donghua martial arts (manuals, internal energy, meridian strain); knight = its own aura/forms/charge/
##     armour arts, separate tree, works on stamina with empty qi;
##   - chantless magic is advanced only: path level + spell-theory + several milestones + Core Formation;
##   - a second path is very hard to learn (second_path_gate) and costs power/xp afterwards (path_penalty);
##   - Region 1 caps at character level 60 and realm 3; later content is flagged `region: 2` ("beyond").

const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const Cult := preload("res://scripts/realm/cultivation.gd")
const DIR := "res://data/powers/"
const STAGES := 9

static var _index: Dictionary = {}
static var _paths: Dictionary = {}          # path -> raw data
static var _tech: Dictionary = {}           # technique id -> {path, row, ability}
static var _manuals: Dictionary = {}        # manual id -> manual dict (with path)
static var _loaded := false


static func _read(file: String) -> Variant:
	var p := DIR + file
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


static func load_all(force := false) -> void:
	if _loaded and not force:
		return
	_index = {}
	_paths = {}
	_tech = {}
	_manuals = {}
	var idx: Variant = _read("index.json")
	_index = idx if idx is Dictionary else {}
	for p: String in AbilityDef.PATHS:
		var d: Variant = _read(p + ".json")
		if not d is Dictionary:
			continue
		_paths[p] = d
		for m: Dictionary in d.get("manuals", []):
			var md := (m as Dictionary).duplicate(true)
			md["path"] = p
			_manuals[String(md["id"])] = md
		for row: Dictionary in d.get("techniques", []):
			var id := String(row["id"])
			var sub := _subpath_def(d, String(row.get("subpath", "")))
			var base := {"id": id, "name": row.get("name", id), "desc": row.get("desc", ""), "path": p,
				"subpath": row.get("subpath", ""), "tier": row.get("tier", 1),
				"kind": "passive" if String(row.get("kind", "attack")) == "passive" else "active", "role": row.get("kind", "attack")}
			var ab := base.duplicate(true)
			var src: Dictionary = row.get("ability", {})
			for k: String in src:
				ab[k] = src[k]
			if not ab.has("element"):
				ab["element"] = String(sub.get("element", d.get("element", "qi")))
			if not ab.has("tree"):
				ab["tree"] = p
			if row.has("passive"):
				ab["passive"] = row["passive"]
			_tech[id] = {"path": p, "row": row, "ability": AbilityDef.normalise(ab)}
	_loaded = true


static func _subpath_def(d: Dictionary, id: String) -> Dictionary:
	for s: Dictionary in d.get("subpaths", []):
		if s["id"] == id:
			return s
	return {}


static func index() -> Dictionary:
	load_all()
	return _index


static func path_ids() -> Array:
	load_all()
	var out: Array = []
	for p: String in AbilityDef.PATHS:
		if _paths.has(p):
			out.append(p)
	return out


static func path_data(path: String) -> Dictionary:
	load_all()
	return _paths.get(path, {})


static func path_name(path: String) -> String:
	return String(path_data(path).get("name", path.capitalize()))


static func region_cap() -> Dictionary:
	return index().get("region_cap", {"region": 1, "level": 60, "realm": 3, "path_level": 20})


static func technique_ids(path := "") -> Array:
	load_all()
	var out: Array = []
	for id: String in _tech:
		if path == "" or _tech[id]["path"] == path:
			out.append(id)
	return out


static func has_technique(id: String) -> bool:
	load_all()
	return _tech.has(id)


static func technique(id: String) -> Dictionary:
	load_all()
	return (_tech.get(id, {}) as Dictionary).get("row", {})


static func ability(id: String) -> Dictionary:
	load_all()
	return (_tech.get(id, {}) as Dictionary).get("ability", {})


static func path_of(id: String) -> String:
	load_all()
	return String((_tech.get(id, {}) as Dictionary).get("path", ""))


static func techniques_of(path: String) -> Array:
	load_all()
	return (path_data(path).get("techniques", []) as Array)


static func manual(id: String) -> Dictionary:
	load_all()
	return _manuals.get(id, {})


static func manuals_of(path: String) -> Array:
	load_all()
	var out: Array = []
	for id: String in _manuals:
		if _manuals[id]["path"] == path:
			out.append(_manuals[id])
	return out


static func subpaths(path: String) -> Array:
	return path_data(path).get("subpaths", [])


static func milestones(path: String) -> Array:
	return path_data(path).get("milestones", [])


## Sub-paths a character of `realm` may follow at once (a table of [realm, slots]).
static func subpath_slots(path: String, realm: int) -> int:
	var slots := 1
	for row: Array in path_data(path).get("subpath_slots", [[1, 1]]):
		if realm >= int(row[0]):
			slots = int(row[1])
	return slots


static func rank_name(path: String, level: int) -> String:
	var out := "Initiate"
	for r: Dictionary in path_data(path).get("levels", []):
		if level >= int(r["level"]):
			out = String(r["name"])
	return out


# --- profile ----------------------------------------------------------------------

static func empty_profile() -> Dictionary:
	return {"paths": [], "primary": "", "levels": {}, "theory": {}, "milestones": {}, "subpaths": {}, "realms": {},
		"manuals": [], "teachers": [], "known": [], "mastery": {}, "trust": 0.0, "level": 1}


## From the live realm modules (power_paths + cultivation). `extra` overrides keys (level, teachers, trust...).
static func profile_from(pp: Object, cult: Object = null, extra := {}) -> Dictionary:
	var p := empty_profile()
	if pp != null:
		for path: String in pp.call("paths"):
			(p["paths"] as Array).append(path)
			p["levels"][path] = int(pp.call("level", path))
			p["theory"][path] = float(pp.call("theory", path))
			p["milestones"][path] = pp.call("milestones", path)
			p["subpaths"][path] = pp.call("subpaths", path)
		p["manuals"] = (pp.call("manuals") as Array).duplicate()
		p["teachers"] = (pp.call("teachers") as Array).duplicate()
		p["known"] = (pp.call("known_techniques") as Array).duplicate()
		for id: String in technique_ids():
			var m := float(pp.call("technique_mastery", id))
			if m > 0.0:
				p["mastery"][id] = m
		var best := 0
		for path: String in p["paths"]:
			if int(p["levels"][path]) > best:
				best = int(p["levels"][path])
				p["primary"] = path
		if pp.has_method("primary_path") and String(pp.call("primary_path")) != "":
			p["primary"] = String(pp.call("primary_path"))
	if cult != null:
		for path: String in p["paths"]:
			if bool(cult.call("has_path", path)):
				p["realms"][path] = {"realm": int(cult.call("realm_of", path)), "stage": int(cult.call("stage_of", path))}
		for id: String in cult.call("learned_manuals"):
			if not (p["manuals"] as Array).has(id):
				(p["manuals"] as Array).append(id)
		if cult.get("prog") != null:
			p["level"] = int((cult.get("prog") as Object).get("level"))
		if String(cult.get("primary")) != "":
			p["primary"] = String(cult.get("primary"))
	for k: String in extra:
		p[k] = extra[k]
	return p


## An NPC's profile from its data row ({path, level, theory, milestones, realm, stage, subpaths, manuals}).
static func npc_profile(row: Dictionary) -> Dictionary:
	var p := empty_profile()
	var path := String(row.get("path", "magic"))
	p["paths"] = [path]
	p["primary"] = path
	p["levels"] = {path: int(row.get("path_level", 1))}
	p["theory"] = {path: float(row.get("theory", 0.0))}
	p["milestones"] = {path: (row.get("milestones", []) as Array).duplicate()}
	p["subpaths"] = {path: (row.get("subpaths", []) as Array).duplicate()}
	p["realms"] = {path: {"realm": int(row.get("realm", 1)), "stage": int(row.get("stage", 1))}}
	p["manuals"] = (row.get("manuals", []) as Array).duplicate()
	p["teachers"] = (row.get("teachers", []) as Array).duplicate()
	p["level"] = int(row.get("level", 1))
	p["trust"] = float(row.get("trust", 0.0))
	return p


static func position(profile: Dictionary, path: String) -> int:
	var r: Dictionary = (profile.get("realms", {}) as Dictionary).get(path, {})
	if r.is_empty():
		return 0
	return (int(r["realm"]) - 1) * STAGES + int(r["stage"])


static func position_of(realm: int, stage: int) -> int:
	return (realm - 1) * STAGES + stage


# --- chantless gate ----------------------------------------------------------------

## The chantless requirements of a path (magic by default; data/powers/magic.json "chantless_gate").
static func chantless_gate(path := "magic") -> Dictionary:
	return path_data(path).get("chantless_gate", {})


## -> {ok, reasons: [String], need: {...}, have: {...}}. Advanced casters only: high path level, spell-theory
## mastery, several path milestones and a cultivation realm. Beginners always chant.
static func chantless_check(profile: Dictionary, path := "magic") -> Dictionary:
	var g := chantless_gate(path)
	var reasons: Array[String] = []
	if g.is_empty():
		return {"ok": false, "reasons": ["No chantless art on this path."], "need": {}, "have": {}}
	if not (profile.get("paths", []) as Array).has(path):
		return {"ok": false, "reasons": ["You have not learned this path."], "need": g, "have": {}}
	var lvl := int((profile.get("levels", {}) as Dictionary).get(path, 0))
	var theory := float((profile.get("theory", {}) as Dictionary).get(path, 0.0))
	var have_ms: Array = (profile.get("milestones", {}) as Dictionary).get(path, [])
	var from: Array = g.get("milestone_ids", [])
	var n_ms := 0
	for m: Variant in have_ms:
		if from.is_empty() or from.has(m):
			n_ms += 1
	var pos := position(profile, path)
	var need_pos := position_of(int(g.get("realm", 4)), int(g.get("stage", 1)))
	if lvl < int(g.get("path_level", 20)):
		reasons.append("Magic level %d needed (you have %d)." % [int(g.get("path_level", 20)), lvl])
	if theory + 0.0001 < float(g.get("theory", 0.7)):
		reasons.append("Spell-theory mastery %d%% needed (you have %d%%)." % [int(round(float(g.get("theory", 0.7)) * 100.0)), int(round(theory * 100.0))])
	if n_ms < int(g.get("milestones", 3)):
		reasons.append("%d path milestones needed (you have %d)." % [int(g.get("milestones", 3)), n_ms])
	if pos < need_pos:
		reasons.append("Needs %s." % Cult.stage_label(path, int(g.get("realm", 4)), int(g.get("stage", 1))))
	return {"ok": reasons.is_empty(), "reasons": reasons, "need": g,
		"have": {"path_level": lvl, "theory": theory, "milestones": n_ms, "position": pos}}


## Chant time multiplier from path level (more skill, shorter chant), never below the data floor.
static func chant_factor(path: String, path_level: int) -> float:
	var c: Dictionary = path_data(path).get("chant", {})
	var per := float(c.get("shorten_per_level", 0.03))
	var floor_k := float(c.get("min_factor", 0.35))
	return maxf(floor_k, 1.0 - per * float(maxi(0, path_level - 1)))


static func chant_tier(path: String, path_level: int) -> Dictionary:
	var best := {}
	for t: Dictionary in path_data(path).get("chant", {}).get("tiers", []):
		if path_level >= int(t.get("min_level", 1)):
			best = t
	return best


# --- second path -------------------------------------------------------------------

## Is the character allowed to begin `path` as an additional path? Very hard on purpose.
## -> {ok, reasons}. The first path has no gate.
static func second_path_gate(profile: Dictionary, path: String, source := "academy") -> Dictionary:
	var reasons: Array[String] = []
	var paths: Array = profile.get("paths", [])
	if paths.has(path):
		return {"ok": false, "reasons": ["Already known."]}
	if paths.is_empty():
		return {"ok": true, "reasons": []}
	var g: Dictionary = index().get("second_path", {})
	var prim := String(profile.get("primary", paths[0]))
	var plvl := int((profile.get("levels", {}) as Dictionary).get(prim, 1))
	if plvl < int(g.get("min_primary_level", 12)):
		reasons.append("Your %s level must reach %d first." % [path_name(prim), int(g.get("min_primary_level", 12))])
	var need_pos := position_of(int(g.get("min_primary_realm", 2)), int(g.get("min_primary_stage", 5)))
	if position(profile, prim) < need_pos:
		reasons.append("Your %s cultivation must reach %s." % [path_name(prim), Cult.stage_label(prim, int(g.get("min_primary_realm", 2)), int(g.get("min_primary_stage", 5)))])
	if int(profile.get("level", 1)) < int(g.get("min_level", 20)):
		reasons.append("Character level %d needed." % int(g.get("min_level", 20)))
	if not source in (g.get("sources", ["academy", "teacher"]) as Array):
		reasons.append("A second path cannot be learned from %s alone." % source)
	var trial := String(g.get("milestone", "second_path_trial"))
	if not ((profile.get("milestones", {}) as Dictionary).get(prim, []) as Array).has(trial):
		reasons.append("Pass the trial of the second path (%s)." % trial.replace("_", " "))
	if paths.size() >= int(g.get("max_paths", 3)):
		reasons.append("No one masters more than %d paths." % int(g.get("max_paths", 3)))
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Power / cost / xp factors for the path at `order` (0 = primary, 1 = second...).
static func path_penalty(order: int) -> Dictionary:
	var g: Dictionary = index().get("second_path", {})
	var power: Array = g.get("power", [1.0, 0.75, 0.55])
	var cost: Array = g.get("cost", [1.0, 1.25, 1.5])
	var xp: Array = g.get("xp", [1.0, 0.35, 0.12])
	var i := clampi(order, 0, power.size() - 1)
	return {"power": float(power[i]), "cost": float(cost[mini(i, cost.size() - 1)]), "xp": float(xp[mini(i, xp.size() - 1)])}


## Order of `path` among the profile's paths: the primary is 0, others follow by level.
static func path_order(profile: Dictionary, path: String) -> int:
	var paths: Array = profile.get("paths", [])
	if not paths.has(path):
		return 0
	var prim := String(profile.get("primary", ""))
	if path == prim or prim == "":
		return 0
	var lv: Dictionary = profile.get("levels", {})
	var order := 1
	for q: String in paths:
		if q != prim and q != path and int(lv.get(q, 0)) > int(lv.get(path, 0)):
			order += 1
	return order


# --- technique requirements ----------------------------------------------------------

## One row per requirement: {key, label, met, need, have}.
static func requirements(id: String, profile: Dictionary) -> Array:
	var t := technique(id)
	var out: Array = []
	if t.is_empty():
		return out
	var path := path_of(id)
	var req: Dictionary = t.get("req", {})
	var paths: Array = profile.get("paths", [])
	out.append({"key": "path", "label": "Walk the %s path" % path_name(path), "met": paths.has(path), "need": path, "have": ""})
	var sub := String(t.get("subpath", ""))
	if sub != "" and sub != "core":
		var sd := _subpath_def(path_data(path), sub)
		var chosen: Array = (profile.get("subpaths", {}) as Dictionary).get(path, [])
		out.append({"key": "subpath", "label": "Sub-path: %s" % String(sd.get("name", sub)), "met": chosen.has(sub),
			"need": sub, "have": ""})
	var lvls: Dictionary = profile.get("levels", {})
	if req.has("path_level"):
		var have := int(lvls.get(path, 0))
		out.append({"key": "path_level", "label": "%s level %d" % [path_name(path), int(req["path_level"])],
			"met": have >= int(req["path_level"]), "need": int(req["path_level"]), "have": have})
	if req.has("realm"):
		var realm := int(req["realm"])
		var stage := int(req.get("stage", 1))
		var pos := position(profile, path)
		out.append({"key": "realm", "label": Cult.stage_label(path, realm, stage), "met": pos >= position_of(realm, stage),
			"need": position_of(realm, stage), "have": pos})
	if req.has("level"):
		out.append({"key": "level", "label": "Character level %d" % int(req["level"]),
			"met": int(profile.get("level", 1)) >= int(req["level"]), "need": int(req["level"]), "have": int(profile.get("level", 1))})
	if req.has("manual") or req.has("teacher"):
		# Learned from a manual OR taught in person: either source opens the technique.
		var ms: Array = []
		if req.has("manual"):
			ms = req["manual"] if req["manual"] is Array else [req["manual"]]
		var ts: Array = []
		if req.has("teacher"):
			ts = req["teacher"] if req["teacher"] is Array else [req["teacher"]]
		var met := false
		for m: Variant in ms:
			if (profile.get("manuals", []) as Array).has(String(m)):
				met = true
		for tt: Variant in ts:
			if (profile.get("teachers", []) as Array).has(String(tt)):
				met = true
		var names: Array = []
		for m: Variant in ms:
			names.append("manual " + _manual_name(String(m)))
		for tt: Variant in ts:
			names.append("taught by " + String(tt).replace("_", " ").capitalize())
		out.append({"key": "source", "label": "Learn: %s" % " or ".join(PackedStringArray(names)), "met": met,
			"need": {"manual": ms, "teacher": ts}, "have": ""})
	if req.has("theory"):
		var th := float((profile.get("theory", {}) as Dictionary).get(path, 0.0))
		out.append({"key": "theory", "label": "Spell-theory %d%%" % int(round(float(req["theory"]) * 100.0)),
			"met": th + 0.0001 >= float(req["theory"]), "need": float(req["theory"]), "have": th})
	if req.has("milestone"):
		var have_ms: Array = (profile.get("milestones", {}) as Dictionary).get(path, [])
		for m: Variant in req["milestone"] if req["milestone"] is Array else [req["milestone"]]:
			out.append({"key": "milestone", "label": "Milestone: %s" % String(m).replace("_", " ").capitalize(),
				"met": have_ms.has(String(m)), "need": m, "have": ""})
	if req.has("prereq"):
		for q: Variant in req["prereq"]:
			out.append({"key": "prereq", "label": "Know %s" % String(technique(String(q)).get("name", q)),
				"met": (profile.get("known", []) as Array).has(String(q)), "need": q, "have": ""})
	if req.has("mastery_of"):
		var mo: Dictionary = req["mastery_of"]
		for q: String in mo:
			var have_m := float((profile.get("mastery", {}) as Dictionary).get(q, 0.0))
			out.append({"key": "mastery", "label": "Master %s to %d%%" % [String(technique(q).get("name", q)), int(round(float(mo[q]) * 100.0))],
				"met": have_m + 0.0001 >= float(mo[q]), "need": float(mo[q]), "have": have_m})
	if req.has("bond"):
		var tr := float(profile.get("trust", 0.0))
		out.append({"key": "bond", "label": "Bond trust %d%%" % int(round(float(req["bond"]) * 100.0)),
			"met": tr + 0.0001 >= float(req["bond"]), "need": float(req["bond"]), "have": tr})
	return out


static func _manual_name(id: String) -> String:
	var m := manual(id)
	if m.is_empty():
		m = Cult.manual(id)
	return String(m.get("name", id))


## -> {state: known|ready|locked|beyond, reqs: [...], reasons: [String]}. `beyond`: Region 2+ content you cannot
## reach yet; a character that meets every requirement may still learn it.
static func state(id: String, profile: Dictionary) -> Dictionary:
	var t := technique(id)
	if t.is_empty():
		return {"state": "locked", "reqs": [], "reasons": ["Unknown technique."]}
	var reqs := requirements(id, profile)
	var reasons: Array[String] = []
	for r: Dictionary in reqs:
		if not bool(r["met"]):
			reasons.append(String(r["label"]))
	var known := (profile.get("known", []) as Array).has(id)
	var st := "locked"
	if known:
		st = "known"
	elif reasons.is_empty():
		st = "ready"
	elif int(t.get("region", 1)) > int(region_cap().get("region", 1)):
		st = "beyond"
	return {"state": st, "reqs": reqs, "reasons": reasons}


## Techniques ready to learn right now (all requirements met, not yet known).
static func ready(path: String, profile: Dictionary) -> Array:
	var out: Array = []
	for t: Dictionary in techniques_of(path):
		if String(state(String(t["id"]), profile)["state"]) == "ready":
			out.append(String(t["id"]))
	return out


## Region 1 audit helper: techniques whose requirements stay inside the Region 1 caps.
static func in_region_one(id: String) -> bool:
	var t := technique(id)
	var cap := region_cap()
	var req: Dictionary = t.get("req", {})
	return int(t.get("region", 1)) <= int(cap.get("region", 1)) and int(req.get("realm", 1)) <= int(cap.get("realm", 3)) \
		and int(req.get("level", 1)) <= int(cap.get("level", 60))


# --- view model for the Skills tab ---------------------------------------------------

## -> {path, name, blurb, resource, known: bool, level, rank, realm_label, primary, penalty, subpaths: [{id, name, desc,
##     chosen, slots_note, techniques: [{id, name, desc, tier, kind, state, reqs, reasons, cost, cooldown, cast}]}],
##     gate: {ok, reasons} (magic chantless), milestones: [{id, name, done}]}
static func view(path: String, profile: Dictionary) -> Dictionary:
	var d := path_data(path)
	if d.is_empty():
		return {}
	var paths: Array = profile.get("paths", [])
	var knows := paths.has(path)
	var lvl := int((profile.get("levels", {}) as Dictionary).get(path, 0))
	var realm_label := "Not cultivating"
	var r: Dictionary = (profile.get("realms", {}) as Dictionary).get(path, {})
	if not r.is_empty():
		realm_label = Cult.stage_label(path, int(r["realm"]), int(r["stage"]))
	var chosen: Array = (profile.get("subpaths", {}) as Dictionary).get(path, [])
	var subs: Array = []
	var seen := {}
	var core := {"id": "core", "name": "Foundations", "desc": "Shared by every follower of the path."}
	var order: Array = [core]
	order.append_array(d.get("subpaths", []))
	for s: Dictionary in order:
		var techs: Array = []
		for t: Dictionary in d.get("techniques", []):
			var sub := String(t.get("subpath", "core"))
			if sub == "":
				sub = "core"
			if sub != s["id"]:
				continue
			seen[t["id"]] = true
			var st := state(String(t["id"]), profile)
			var ab := ability(String(t["id"]))
			var cost := AbilityDef.primary_cost(ab)
			techs.append({"id": t["id"], "name": t["name"], "desc": t.get("desc", ""), "tier": int(t.get("tier", 1)),
				"kind": String(t.get("kind", "active")), "state": st["state"], "reqs": st["reqs"], "reasons": st["reasons"],
				"cost": float(cost["amount"]), "resource": String(cost["resource"]), "cooldown": float(ab.get("cooldown", 0.0)),
				"cast": String((ab.get("cast", {}) as Dictionary).get("kind", "instant")), "region": int(t.get("region", 1))})
		if techs.is_empty():
			continue
		subs.append({"id": s["id"], "name": s["name"], "desc": s.get("desc", ""),
			"chosen": s["id"] == "core" or chosen.has(s["id"]), "techniques": techs})
	var ms: Array = []
	for m: Dictionary in d.get("milestones", []):
		ms.append({"id": m["id"], "name": m["name"], "done": ((profile.get("milestones", {}) as Dictionary).get(path, []) as Array).has(m["id"])})
	var gate := {}
	if not chantless_gate(path).is_empty():
		gate = chantless_check(profile, path)
	var order_i := path_order(profile, path)
	return {"path": path, "name": d.get("name", path), "blurb": d.get("blurb", ""), "resource": d.get("resource_name", ""),
		"known": knows, "level": lvl, "rank": rank_name(path, lvl), "realm_label": realm_label,
		"primary": String(profile.get("primary", "")) == path, "penalty": path_penalty(order_i) if knows else {},
		"slots": subpath_slots(path, int(r.get("realm", 1))), "subpaths": subs, "gate": gate, "milestones": ms,
		"tradition": String(d.get("tradition", ""))}
