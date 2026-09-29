extends SceneTree
## Region 1 story lint (package L14). Validates every quest step, objective (trigger) type,
## speaker, flag, dialogue node and cross-reference, then autoplays the quest through every
## combination of player choices with the real runtime (scripts/region1/story_quest.gd) and
## the real dialogue runner, so a branch that cannot finish is an error.
##
##   Godot --headless --path kingdom -s res://tools_qa/region1/lint_quests.gd [-- --quest=<path>] [-- --quiet]
##
## Exit code 0 = no errors (warnings are printed but allowed). Tests call the static
## `lint()` directly (tests/test_region1_story.gd).

const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const StoryQuest := preload("res://scripts/region1/story_quest.gd")
const Tutorial := preload("res://scripts/region1/tutorial_director.gd")

const MAIN_QUEST := "res://data/region1/quests/r1_main.json"
const DIALOGUE_DIR := "res://data/region1/dialogue"
const ITEMS := "res://data/items.json"
const FIRST_REGION := "res://data/world/first_region.json"

const MECHANICS := ["wardwright", "scar_tide", "ember_legacy", "ashsight"]
const LINE_MAX := 120        # characters per dialogue line (mobile: two lines at 390 px)
const CHOICE_MAX := 40
const OBJECTIVE_MAX := 48    # HUD tracker pin
const TITLE_MAX := 32
const JOURNAL_MAX := 160
const PRINCIPAL_CAST := 12

## Objective (trigger) types: required keys and optional keys. "id" and "type" are implied;
## "do" (actions when the objective completes) and "sets" (flag) are allowed on all.
const OBJECTIVES := {
	"flag": {"req": ["flag"], "opt": []},
	"choice": {"req": ["group"], "opt": []},
	"talk": {"req": ["node"], "opt": []},
	"age": {"req": ["min"], "opt": []},
	"item": {"req": ["item"], "opt": ["count"]},
	"enter_area": {"req": ["place"], "opt": ["radius"]},
	"kill": {"req": ["target"], "opt": ["place", "count"]},
	"defeat": {"req": ["target"], "opt": ["subdue"]},
	"carve": {"req": ["glyph", "stone"], "opt": ["count"]},
	"relight_elder": {"req": ["stone"], "opt": []},
	"wardline_link": {"req": ["to"], "opt": ["from", "count"]},
	"scar_contain": {"req": ["place", "cells"], "opt": []},
	"scar_harvest": {"req": ["place", "crystals"], "opt": []},
	"ashsight": {"req": ["site"], "opt": []},
	"ember_choice": {"req": ["who", "group"], "opt": []},
	"cutscene_done": {"req": ["cutscene"], "opt": []},
	"festival": {"req": ["festival"], "opt": []},
	"any": {"req": ["of"], "opt": []},
}
const STEP_REQ := ["id", "act", "title", "objective", "journal", "giver", "place", "objectives"]
const STEP_OPT := ["requires", "dialogue", "mechanics", "tutorial", "on_start", "on_complete", "staging"]
## Emotional staging per step (docs/regions/EMOTION_MAP_R1.md). "intensity" is -5..+5; "music" must be a
## registry music cue; "needs" lists who builds the beat (C9 cutscene, Codex animation, VFX).
const STAGING_KEYS := ["intensity", "emotion", "music", "sfx", "camera", "anim", "vfx", "silence", "weather", "time", "needs"]
const STAGING_NEEDS := ["c9", "codex", "vfx"]
## A run of this many steps (file order) whose intensity stays within 1 of each other is a flat stretch.
const FLAT_RUN := 4
## Quest actions (on_start / on_complete / objective "do") and their argument checks.
const QUEST_ACTIONS := ["flag", "give", "rep", "gold", "cutscene", "marker", "spawn", "tutorial"]
## Dialogue "do" verbs understood by dialogue_runner.gd.
const DIALOGUE_ACTIONS := ["opinion", "rep", "bond", "flag", "record", "give", "chores", "gift", "quests",
	"turn_in", "close", "tell_hint"]
const CONDITIONS := ["tier", "tier_not", "min_tier", "bond", "time", "weather", "child", "role", "flag", "no_flag",
	"event", "no_event", "min_op", "max_op", "min_age", "max_age", "has", "not_has", "chance"]
const BLESSINGS := ["blessing:fire", "blessing:water", "blessing:wind", "blessing:earth", "blessing:none", "blessing:lightning"]


func _init() -> void:
	var quest := MAIN_QUEST
	var quiet := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quest="):
			quest = a.substr(8)
		elif a == "--quiet":
			quiet = true
	var r := lint(quest)
	if not quiet:
		for w: String in r["warnings"]:
			print("WARN  ", w)
	for e: String in r["errors"]:
		print("ERROR ", e)
	print("lint_quests: %s" % JSON.stringify(r["stats"]))
	print("lint_quests: %d errors, %d warnings -> %s" % [r["errors"].size(), r["warnings"].size(),
		"OK" if r["errors"].is_empty() else "FAIL"])
	quit(0 if r["errors"].is_empty() else 1)


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## {errors: [], warnings: [], stats: {}}
static func lint(quest_path: String = MAIN_QUEST, exhaustive := false, autoplay := true) -> Dictionary:
	var L := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "stats": {},
		"flags_read": {}, "flags_written": {}, "speakers_used": {}, "gives": {}}
	var q: Variant = _json(quest_path)
	if not (q is Dictionary):
		L["errors"].append("%s: missing or not valid JSON" % quest_path)
		return _result(L)
	var reg: Variant = _json(String(q.get("registry", "")))
	var cast: Variant = _json(String(q.get("cast", "")))
	var items: Variant = _json(ITEMS)
	if not (reg is Dictionary):
		L["errors"].append("registry missing: %s" % q.get("registry", ""))
		return _result(L)
	if not (cast is Dictionary):
		L["errors"].append("cast missing: %s" % q.get("cast", ""))
		return _result(L)
	var speakers: Dictionary = cast.get("speakers", {})
	var item_ids := {}
	if items is Dictionary:
		for k: String in items:
			item_ids[k] = true
	for k: String in reg.get("new_items", {}):
		if not k.begins_with("_"):
			item_ids[k] = true
	# Existing places must really exist in first_region.json.
	var fr: Variant = _json(FIRST_REGION)
	var fr_ids := {}
	if fr is Dictionary:
		for p: Dictionary in fr.get("places", []):
			fr_ids[String(p.get("id", ""))] = true
	var dir := String(q.get("dialogue_dir", DIALOGUE_DIR))

	_lint_cast(L, speakers)
	_lint_registry(L, reg, fr_ids)

	# Dialogue files: every *.json in the dialogue dir.
	var dialogues := {}
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var d: Variant = _json(dir + "/" + f)
			if not (d is Dictionary):
				L["errors"].append("dialogue %s: not valid JSON" % f)
				continue
			dialogues[f.get_basename()] = d
			_lint_dialogue(L, f.get_basename(), d, speakers, reg, item_ids)

	var acts := {}
	for a: Dictionary in q.get("acts", []):
		acts[int(a.get("act", 0))] = a
		if not dialogues.has(String(a.get("dialogue", ""))):
			L["errors"].append("act %s: dialogue file '%s' missing" % [a.get("act"), a.get("dialogue")])
	if acts.size() != 5:
		L["errors"].append("expected 5 acts, found %d" % acts.size())

	var entries := {}   # "file:node" -> true (quest entry points into dialogue)
	var steps: Array = q.get("steps", [])
	var ids := {}
	for s: Dictionary in steps:
		var id := String(s.get("id", ""))
		if ids.has(id):
			L["errors"].append("step '%s' defined twice" % id)
		ids[id] = s
	for s: Dictionary in steps:
		_lint_step(L, s, ids, acts, dialogues, speakers, reg, item_ids, entries)
	_lint_graph(L, steps, ids)
	_lint_mechanics(L, steps)
	_lint_curve(L, steps)
	_lint_flags(L, reg, q)
	_lint_reachability(L, dialogues, entries)
	for sp: String in speakers:
		if bool((speakers[sp] as Dictionary).get("principal", false)) and not L["speakers_used"].has(sp):
			L["errors"].append("principal cast '%s' never speaks" % sp)
	if autoplay:
		_autoplay(L, q, reg, dialogues, exhaustive)
	L["stats"]["steps"] = steps.size()
	L["stats"]["dialogue_files"] = dialogues.size()
	var n_nodes := 0
	var n_lines := 0
	for k: String in dialogues:
		for node: String in dialogues[k].get("nodes", {}):
			n_nodes += 1
			n_lines += (dialogues[k]["nodes"][node].get("lines", []) as Array).size()
	L["stats"]["nodes"] = n_nodes
	L["stats"]["lines"] = n_lines
	return _result(L)


static func _result(L: Dictionary) -> Dictionary:
	return {"errors": L["errors"], "warnings": L["warnings"], "stats": L["stats"]}


# --- parts ----------------------------------------------------------------------------

static func _lint_cast(L: Dictionary, speakers: Dictionary) -> void:
	var principal := 0
	for sp: String in speakers:
		var c: Dictionary = speakers[sp]
		for k: String in ["display", "role", "voice"]:
			if not c.has(k):
				L["errors"].append("cast '%s': missing '%s'" % [sp, k])
		if bool(c.get("principal", false)):
			principal += 1
	if principal != PRINCIPAL_CAST:
		L["errors"].append("cast: %d principal speakers, expected %d" % [principal, PRINCIPAL_CAST])


static func _lint_registry(L: Dictionary, reg: Dictionary, fr_ids: Dictionary) -> void:
	var places: Dictionary = reg.get("places", {})
	for p: String in places:
		var row: Dictionary = places[p]
		if String(row.get("status", "")) == "existing" and not fr_ids.is_empty() and not fr_ids.has(p) \
				and not ["ashford", "kingsreach", "duskbriar_bandit_camp", "rifts_edge_camp", "rift_mouth"].has(p):
			L["warnings"].append("place '%s' marked existing but not in first_region.json (C0 adds it)" % p)
		if not (row.get("pos", null) is Array) or (row["pos"] as Array).size() != 2:
			L["errors"].append("place '%s': pos must be [x, z]" % p)
	for s: String in reg.get("stones", {}):
		if s.begins_with("_"):
			continue
		var st: Dictionary = reg["stones"][s]
		if not places.has(String(st.get("place", ""))):
			L["errors"].append("stone '%s': unknown place '%s'" % [s, st.get("place", "")])
		if not ["road", "elder", "anchor"].has(String(st.get("kind", ""))):
			L["errors"].append("stone '%s': bad kind '%s'" % [s, st.get("kind", "")])
	for g: String in reg.get("choice_groups", {}):
		if g.begins_with("_"):
			continue
		var grp: Dictionary = reg["choice_groups"][g]
		if not ["dialogue", "objective", "ember_choice"].has(String(grp.get("source", ""))):
			L["errors"].append("choice group '%s': bad source" % g)
		if (grp.get("flags", []) as Array).size() < 2:
			L["errors"].append("choice group '%s': needs at least 2 flags" % g)
		for f: Variant in grp.get("flags", []):
			if String(grp.get("source", "")) != "dialogue":
				L["flags_written"][String(f)] = "choice group %s (%s)" % [g, grp["source"]]


static func _lint_dialogue(L: Dictionary, file: String, d: Dictionary, speakers: Dictionary, reg: Dictionary,
		item_ids: Dictionary) -> void:
	for problem: String in DialogueRunner.validate(d):
		L["errors"].append("dialogue %s: %s" % [file, problem])
	var tokens: Array = reg.get("tokens", [])
	var factions: Array = reg.get("factions", [])
	var nodes: Dictionary = d.get("nodes", {})
	for n: String in nodes:
		var node: Dictionary = nodes[n]
		var where := "dialogue %s/%s" % [file, n]
		var sp := String(node.get("speaker", ""))
		if not speakers.has(sp):
			L["errors"].append("%s: unknown speaker '%s'" % [where, sp])
		else:
			L["speakers_used"][sp] = true
		for l: Dictionary in node.get("lines", []):
			var t := String(l.get("text", ""))
			if t.strip_edges() == "":
				L["errors"].append("%s: empty line" % where)
			if t.length() > LINE_MAX:
				L["errors"].append("%s: line is %d chars (max %d): %s" % [where, t.length(), LINE_MAX, t.left(40)])
			_check_tokens(L, where, t, tokens)
			_read_cond(L, l.get("if", {}), where)
			_check_dialogue_actions(L, where, l.get("do", []), factions, item_ids)
		for c: Dictionary in node.get("choices", []):
			var t := String(c.get("text", ""))
			if t.length() > CHOICE_MAX:
				L["errors"].append("%s: choice is %d chars (max %d): %s" % [where, t.length(), CHOICE_MAX, t])
			_check_tokens(L, where, t, tokens)
			_read_cond(L, c.get("if", {}), where)
			_check_dialogue_actions(L, where, c.get("do", []), factions, item_ids)


static func _check_tokens(L: Dictionary, where: String, text: String, tokens: Array) -> void:
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for m in re.search_all(text):
		if not tokens.has(m.get_string(1)):
			L["errors"].append("%s: unknown token {%s}" % [where, m.get_string(1)])


static func _read_cond(L: Dictionary, cond: Dictionary, where: String) -> void:
	for k: String in cond:
		if not CONDITIONS.has(k):
			L["errors"].append("%s: unknown condition '%s'" % [where, k])
		if k == "flag" or k == "no_flag":
			var v: Variant = cond[k]
			for f: Variant in (v if v is Array else [v]):
				L["flags_read"][String(f)] = where


static func _check_dialogue_actions(L: Dictionary, where: String, acts: Array, factions: Array,
		item_ids: Dictionary) -> void:
	for a: Variant in acts:
		if not (a is Array) or (a as Array).is_empty():
			L["errors"].append("%s: action must be a non-empty array" % where)
			continue
		var verb := String(a[0])
		if not DIALOGUE_ACTIONS.has(verb):
			L["errors"].append("%s: unknown dialogue action '%s'" % [where, verb])
		match verb:
			"flag":
				if a.size() < 2:
					L["errors"].append("%s: flag action needs a name" % where)
				else:
					L["flags_written"][String(a[1])] = where
			"rep":
				if a.size() < 3 or not factions.has(String(a[1])):
					L["errors"].append("%s: rep needs a known faction and a delta: %s" % [where, str(a)])
			"give":
				if a.size() < 3 or not item_ids.has(String(a[1])) or int(a[2]) <= 0:
					L["errors"].append("%s: give needs a known item and a count: %s" % [where, str(a)])
				else:
					L["gives"][String(a[1])] = where


static func _check_quest_actions(L: Dictionary, where: String, acts: Array, reg: Dictionary,
		item_ids: Dictionary) -> void:
	for a: Variant in acts:
		if not (a is Array) or (a as Array).is_empty():
			L["errors"].append("%s: action must be a non-empty array" % where)
			continue
		var verb := String(a[0])
		var ok := true
		match verb:
			"flag": ok = a.size() == 2
			"give": ok = a.size() == 3 and item_ids.has(String(a[1])) and int(a[2]) > 0
			"rep": ok = a.size() == 3 and (reg.get("factions", []) as Array).has(String(a[1]))
			"gold": ok = a.size() == 2 and int(a[1]) > 0
			"cutscene": ok = a.size() == 2 and (reg.get("cutscenes", {}) as Dictionary).has(String(a[1]))
			"marker": ok = a.size() == 2 and (reg.get("places", {}) as Dictionary).has(String(a[1]))
			"spawn": ok = a.size() == 4 and (reg.get("targets", {}) as Dictionary).has(String(a[1])) \
					and (reg.get("places", {}) as Dictionary).has(String(a[2])) and int(a[3]) > 0
			"tutorial": ok = a.size() == 2 and Tutorial.PROMPTS.has(String(a[1]))
			_:
				L["errors"].append("%s: unknown quest action '%s'" % [where, verb])
				continue
		if not ok:
			L["errors"].append("%s: bad '%s' action %s" % [where, verb, str(a)])
		elif verb == "flag":
			L["flags_written"][String(a[1])] = where
		elif verb == "give":
			L["gives"][String(a[1])] = where


static func _lint_step(L: Dictionary, s: Dictionary, ids: Dictionary, acts: Dictionary, dialogues: Dictionary,
		speakers: Dictionary, reg: Dictionary, item_ids: Dictionary, entries: Dictionary) -> void:
	var id := String(s.get("id", "?"))
	var where := "step %s" % id
	for k: String in STEP_REQ:
		if not s.has(k):
			L["errors"].append("%s: missing '%s'" % [where, k])
	for k: String in s:
		if not STEP_REQ.has(k) and not STEP_OPT.has(k):
			L["errors"].append("%s: unknown key '%s'" % [where, k])
	if not RegEx.create_from_string("^a[1-5]_[a-z0-9_]+$").search(id):
		L["errors"].append("%s: id must look like a<act>_<name>" % where)
	var act := int(s.get("act", 0))
	if not acts.has(act):
		L["errors"].append("%s: unknown act %d" % [where, act])
	elif not id.begins_with("a%d_" % act):
		L["errors"].append("%s: id prefix does not match act %d" % [where, act])
	if String(s.get("title", "")).length() > TITLE_MAX:
		L["errors"].append("%s: title longer than %d" % [where, TITLE_MAX])
	if String(s.get("objective", "")).length() > OBJECTIVE_MAX:
		L["errors"].append("%s: objective text longer than %d (HUD pin)" % [where, OBJECTIVE_MAX])
	if String(s.get("journal", "")).length() > JOURNAL_MAX:
		L["errors"].append("%s: journal longer than %d" % [where, JOURNAL_MAX])
	if not speakers.has(String(s.get("giver", ""))):
		L["errors"].append("%s: unknown giver '%s'" % [where, s.get("giver", "")])
	var places: Dictionary = reg.get("places", {})
	if not places.has(String(s.get("place", ""))):
		L["errors"].append("%s: unknown place '%s'" % [where, s.get("place", "")])
	var r: Dictionary = s.get("requires", {})
	for dep: Variant in r.get("steps", []):
		if not ids.has(String(dep)):
			L["errors"].append("%s: requires unknown step '%s'" % [where, dep])
		elif int((ids[String(dep)] as Dictionary).get("act", 0)) > act:
			L["errors"].append("%s: requires '%s' from a later act" % [where, dep])
	_read_cond(L, r.get("if", {}), where)
	for m: String in s.get("mechanics", {}):
		if not MECHANICS.has(m):
			L["errors"].append("%s: unknown mechanic '%s'" % [where, m])
		if not ["teach", "use"].has(String(s["mechanics"][m])):
			L["errors"].append("%s: mechanic '%s' must be teach or use" % [where, m])
	for t: Variant in s.get("tutorial", []):
		if not Tutorial.PROMPTS.has(String(t)):
			L["errors"].append("%s: unknown tutorial prompt '%s'" % [where, t])
	_check_quest_actions(L, where + " on_start", s.get("on_start", []), reg, item_ids)
	_check_quest_actions(L, where + " on_complete", s.get("on_complete", []), reg, item_ids)
	_lint_staging(L, where, s, reg)

	var objs: Array = s.get("objectives", [])
	if objs.is_empty():
		L["errors"].append("%s: no objectives" % where)
	var oids := {}
	for o: Dictionary in objs:
		_lint_objective(L, where, o, oids, reg, item_ids, dialogues, s)
	# Dialogue entries.
	var file := String((acts.get(act, {}) as Dictionary).get("dialogue", ""))
	for e: Dictionary in s.get("dialogue", []):
		var f := String(e.get("file", file))
		var node := String(e.get("node", ""))
		if not dialogues.has(f) or not (dialogues[f].get("nodes", {}) as Dictionary).has(node):
			L["errors"].append("%s: dialogue entry %s/%s missing" % [where, f, node])
			continue
		entries["%s:%s" % [f, node]] = true
		var after := String(e.get("after", ""))
		if after != "" and not oids.has(after):
			L["errors"].append("%s: dialogue %s after unknown objective '%s'" % [where, node, after])
	# Talk objectives count as entry points too (reached via choices, but check they exist).
	for o: Dictionary in objs:
		if String(o.get("type", "")) == "talk":
			var node := String(o.get("node", ""))
			if not dialogues.has(file) or not (dialogues[file].get("nodes", {}) as Dictionary).has(node):
				L["errors"].append("%s: talk objective node '%s' not in %s" % [where, node, file])


static func _lint_staging(L: Dictionary, where: String, s: Dictionary, reg: Dictionary) -> void:
	if not s.has("staging"):
		L["warnings"].append("%s: no staging (intensity, music) for the emotion map" % where)
		return
	if not (s["staging"] is Dictionary):
		L["errors"].append("%s: staging must be an object" % where)
		return
	var st: Dictionary = s["staging"]
	for k: String in st:
		if not STAGING_KEYS.has(k):
			L["errors"].append("%s: unknown staging key '%s'" % [where, k])
	var iv: Variant = st.get("intensity", null)
	if not (iv is float or iv is int) or float(iv) != float(int(iv)) or absi(int(iv)) > 5:
		L["errors"].append("%s: staging.intensity must be an integer from -5 to 5" % where)
	var music: Dictionary = reg.get("music", {})
	if st.has("music") and not music.has(String(st["music"])):
		L["errors"].append("%s: staging.music '%s' is not a registry music cue" % [where, st["music"]])
	for n: Variant in st.get("needs", []):
		if not STAGING_NEEDS.has(String(n)):
			L["errors"].append("%s: staging.needs '%s' must be one of %s" % [where, n, STAGING_NEEDS])


## The emotional curve: intensity per step in file order. Warns on flat stretches (FLAT_RUN steps in a
## row within 1 of each other) and reports range and swings in the stats.
static func _lint_curve(L: Dictionary, steps: Array) -> void:
	var curve: Array = []
	for s: Dictionary in steps:
		var st: Variant = s.get("staging", {})
		if st is Dictionary and (st as Dictionary).has("intensity"):
			curve.append([String(s.get("id", "")), int(st["intensity"])])
	if curve.is_empty():
		return
	var lo := 99
	var hi := -99
	var swings := 0
	for i in curve.size():
		var v: int = curve[i][1]
		lo = mini(lo, v)
		hi = maxi(hi, v)
		if i > 0 and signi(v) != 0 and signi(v) != signi(int(curve[i - 1][1])):
			swings += 1
	var i := 0
	while i + FLAT_RUN <= curve.size():
		var a: int = curve[i][1]
		var b: int = curve[i][1]
		var j := i
		while j < curve.size() and maxi(b, int(curve[j][1])) - mini(a, int(curve[j][1])) <= 1:
			a = mini(a, int(curve[j][1]))
			b = maxi(b, int(curve[j][1]))
			j += 1
		if j - i >= FLAT_RUN:
			L["warnings"].append("emotional curve is flat from %s to %s (%d steps within 1 point)" % [
				curve[i][0], curve[j - 1][0], j - i])
			i = j
		else:
			i += 1
	L["stats"]["curve_min"] = lo
	L["stats"]["curve_max"] = hi
	L["stats"]["curve_swings"] = swings


static func _lint_objective(L: Dictionary, where: String, o: Dictionary, oids: Dictionary, reg: Dictionary,
		item_ids: Dictionary, dialogues: Dictionary, s: Dictionary) -> void:
	var t := String(o.get("type", ""))
	var oid := String(o.get("id", ""))
	var w := "%s objective %s" % [where, oid]
	if oid == "":
		L["errors"].append("%s: objective without id" % where)
	elif oids.has(oid):
		L["errors"].append("%s: duplicate objective id '%s'" % [where, oid])
	oids[oid] = true
	if not OBJECTIVES.has(t):
		L["errors"].append("%s: unknown trigger type '%s'" % [w, t])
		return
	var spec: Dictionary = OBJECTIVES[t]
	for k: String in spec["req"]:
		if not o.has(k):
			L["errors"].append("%s: '%s' needs '%s'" % [w, t, k])
	for k: String in o:
		if not (["id", "type", "do", "sets"] + spec["req"] + spec["opt"]).has(k):
			L["errors"].append("%s: unknown key '%s' for type '%s'" % [w, k, t])
	for k: String in ["count", "cells", "crystals", "min"]:
		if o.has(k) and (int(o[k]) <= 0 or float(o[k]) != float(int(o[k]))):
			L["errors"].append("%s: '%s' must be a positive integer" % [w, k])
	var places: Dictionary = reg.get("places", {})
	var stones: Dictionary = reg.get("stones", {})
	match t:
		"flag":
			L["flags_read"][String(o.get("flag", ""))] = w
		"choice":
			if not (reg.get("choice_groups", {}) as Dictionary).has(String(o.get("group", ""))):
				L["errors"].append("%s: unknown choice group '%s'" % [w, o.get("group", "")])
			else:
				for f: Variant in reg["choice_groups"][String(o["group"])].get("flags", []):
					L["flags_read"][String(f)] = w
		"item":
			if not item_ids.has(String(o.get("item", ""))):
				L["errors"].append("%s: unknown item '%s'" % [w, o.get("item", "")])
		"enter_area", "scar_contain", "scar_harvest":
			if not places.has(String(o.get("place", ""))):
				L["errors"].append("%s: unknown place '%s'" % [w, o.get("place", "")])
		"kill", "defeat":
			if not (reg.get("targets", {}) as Dictionary).has(String(o.get("target", ""))):
				L["errors"].append("%s: unknown target '%s'" % [w, o.get("target", "")])
			if o.has("place") and not places.has(String(o["place"])):
				L["errors"].append("%s: unknown place '%s'" % [w, o["place"]])
		"carve":
			if not (reg.get("glyphs", []) as Array).has(String(o.get("glyph", ""))):
				L["errors"].append("%s: unknown glyph '%s'" % [w, o.get("glyph", "")])
			if not stones.has(String(o.get("stone", ""))):
				L["errors"].append("%s: unknown stone '%s'" % [w, o.get("stone", "")])
		"relight_elder":
			if String((stones.get(String(o.get("stone", "")), {}) as Dictionary).get("kind", "")) != "elder":
				L["errors"].append("%s: '%s' is not an Elder Stone" % [w, o.get("stone", "")])
		"wardline_link":
			for k: String in ["from", "to"]:
				if o.has(k) and not stones.has(String(o[k])) and not places.has(String(o[k])):
					L["errors"].append("%s: unknown ward-line end '%s'" % [w, o[k]])
		"ashsight":
			if not places.has(String(o.get("site", ""))):
				L["errors"].append("%s: unknown ash site '%s'" % [w, o.get("site", "")])
		"ember_choice":
			var g: Dictionary = (reg.get("choice_groups", {}) as Dictionary).get(String(o.get("group", "")), {})
			if String(g.get("source", "")) != "ember_choice":
				L["errors"].append("%s: group '%s' must have source ember_choice" % [w, o.get("group", "")])
			for f: Variant in g.get("flags", []):
				if not String(f).begins_with("ember.%s." % o.get("who", "")):
					L["errors"].append("%s: ember flag '%s' must be ember.<who>.<choice>" % [w, f])
		"cutscene_done":
			if not (reg.get("cutscenes", {}) as Dictionary).has(String(o.get("cutscene", ""))):
				L["errors"].append("%s: unknown cutscene '%s'" % [w, o.get("cutscene", "")])
		"festival":
			if not (reg.get("festivals", []) as Array).has(String(o.get("festival", ""))):
				L["errors"].append("%s: unknown festival '%s'" % [w, o.get("festival", "")])
		"any":
			var subs: Array = o.get("of", [])
			if subs.size() < 2:
				L["errors"].append("%s: 'any' needs at least 2 branches" % w)
			for sub: Dictionary in subs:
				if String(sub.get("type", "")) == "any":
					L["errors"].append("%s: nested 'any' is not supported" % w)
					continue
				_lint_objective(L, w, sub, oids, reg, item_ids, dialogues, s)
	if o.has("sets"):
		L["flags_written"][String(o["sets"])] = w
	_check_quest_actions(L, w + " do", o.get("do", []), reg, item_ids)


## Steps form a DAG, the first step needs nothing, and a step's requirements come first in
## file order (keeps the data readable top to bottom).
static func _lint_graph(L: Dictionary, steps: Array, ids: Dictionary) -> void:
	var pos := {}
	for i in steps.size():
		pos[String(steps[i].get("id", ""))] = i
	var roots := 0
	for s: Dictionary in steps:
		var deps: Array = (s.get("requires", {}) as Dictionary).get("steps", [])
		if deps.is_empty():
			roots += 1
		for dep: Variant in deps:
			if pos.has(String(dep)) and int(pos[String(dep)]) >= int(pos[String(s["id"])]):
				L["errors"].append("step %s: requires '%s' which comes later in the file (cycle?)" % [s["id"], dep])
	if roots != 1:
		L["errors"].append("expected exactly 1 starting step (no requirements), found %d" % roots)


## Every mechanic is taught before it is used and appears in at least two acts.
static func _lint_mechanics(L: Dictionary, steps: Array) -> void:
	for m: String in MECHANICS:
		var first_teach := -1
		var first_use := -1
		var acts := {}
		for i in steps.size():
			var mm: Dictionary = steps[i].get("mechanics", {})
			if not mm.has(m):
				continue
			acts[int(steps[i].get("act", 0))] = true
			if String(mm[m]) == "teach" and first_teach < 0:
				first_teach = i
			if String(mm[m]) == "use" and first_use < 0:
				first_use = i
		if first_teach < 0:
			L["errors"].append("mechanic '%s' is never taught" % m)
		elif first_use >= 0 and first_use < first_teach:
			L["errors"].append("mechanic '%s' is used before it is taught" % m)
		if acts.size() < 2:
			L["errors"].append("mechanic '%s' appears in only %d act(s); needs 2+" % [m, acts.size()])
		L["stats"]["acts_" + m] = acts.keys()


static func _lint_flags(L: Dictionary, reg: Dictionary, q: Dictionary) -> void:
	var ext: Dictionary = reg.get("external_flags", {})
	L["flags_written"][String(q.get("complete_flag", ""))] = "quest"
	for f: String in L["flags_read"]:
		if L["flags_written"].has(f):
			continue
		var external := false
		for e: String in ext:
			if e.begins_with("_"):
				continue
			if f == e or (e.ends_with(":") and f.begins_with(e)):
				external = true
		if not external:
			L["errors"].append("flag '%s' is read (%s) but nothing sets it" % [f, L["flags_read"][f]])
	for f: String in reg.get("exported_flags", {}):
		if not f.begins_with("_"):
			L["flags_read"][f] = "exported_flags"
	for f: String in L["flags_written"]:
		if not L["flags_read"].has(f) and f != String(q.get("complete_flag", "")):
			L["warnings"].append("flag '%s' is set (%s) but never read" % [f, L["flags_written"][f]])
		if not (f.begins_with("r1.") or f.begins_with("ember.")):
			L["errors"].append("flag '%s' must use the r1. or ember. namespace" % f)
	for g: String in reg.get("choice_groups", {}):
		if g.begins_with("_"):
			continue
		for f: Variant in reg["choice_groups"][g].get("flags", []):
			if not L["flags_written"].has(String(f)):
				L["errors"].append("choice group '%s': nothing sets '%s'" % [g, f])


## Every dialogue node is reachable from a quest entry point through choices.
static func _lint_reachability(L: Dictionary, dialogues: Dictionary, entries: Dictionary) -> void:
	var seen := {}
	var stack: Array = entries.keys()
	while not stack.is_empty():
		var key := String(stack.pop_back())
		if seen.has(key):
			continue
		seen[key] = true
		var parts := key.split(":")
		var nodes: Dictionary = dialogues.get(parts[0], {}).get("nodes", {})
		for c: Dictionary in (nodes.get(parts[1], {}) as Dictionary).get("choices", []):
			var g := String(c.get("goto", ""))
			if g != "" and g != "@end":
				stack.append("%s:%s" % [parts[0], g])
	for f: String in dialogues:
		for n: String in dialogues[f].get("nodes", {}):
			if not seen.has("%s:%s" % [f, n]):
				L["errors"].append("dialogue %s/%s: unreachable from any quest step" % [f, n])


# --- autoplay -------------------------------------------------------------------------

## Play the quest to the end for every combination of choice-group options (and a spread of
## Blessing results), with the real runtime and dialogue runner. Reports stuck steps, nodes
## with no line to show, and nodes/lines never reached in any run.
static func _autoplay(L: Dictionary, q: Dictionary, reg: Dictionary, dialogues: Dictionary, exhaustive := false) -> void:
	var groups: Array = []
	for g: String in reg.get("choice_groups", {}):
		if not g.begins_with("_"):
			groups.append(g)
	var sizes: Array = []
	var total := 1
	for g: String in groups:
		sizes.append((reg["choice_groups"][g]["flags"] as Array).size())
		total *= int(sizes[-1])
	# Combinations: every option of every group at least once (with the others varied), plus
	# seeded random combinations. --exhaustive (or exhaustive=true) plays the full product.
	var combos: Array = []   # Array of index arrays
	var seen_combo := {}
	var add := func(c: Array) -> void:
		var k := str(c)
		if not seen_combo.has(k):
			seen_combo[k] = true
			combos.append(c)
	if exhaustive or OS.get_cmdline_user_args().has("--exhaustive"):
		for i in total:
			var c: Array = []
			var rest := i
			for gi in groups.size():
				c.append(rest % int(sizes[gi]))
				rest /= int(sizes[gi])
			add.call(c)
	else:
		var maxs: int = sizes.max() if not sizes.is_empty() else 1
		for shift in maxs:   # diagonals: group gi picks (shift + gi) mod size
			for base in maxs:
				var c: Array = []
				for gi in groups.size():
					c.append((base + shift * gi) % int(sizes[gi]))
				add.call(c)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1066
		for i in 48:
			var c: Array = []
			for gi in groups.size():
				c.append(rng.randi() % int(sizes[gi]))
			add.call(c)
	var visited_nodes := {}
	var shown_lines := {}
	var failures := 0
	var t0 := Time.get_ticks_msec()
	for combo_i in combos.size():
		var pick := {}
		for gi in groups.size():
			pick[groups[gi]] = String(reg["choice_groups"][groups[gi]]["flags"][int(combos[combo_i][gi])])
		var blessing: String = BLESSINGS[combo_i % BLESSINGS.size()]
		var err := _play_once(q, reg, dialogues, pick, blessing, visited_nodes, shown_lines, combo_i)
		if err != "":
			failures += 1
			if failures <= 5:
				L["errors"].append("autoplay %s (%s): %s" % [JSON.stringify(pick.values()), blessing, err])
	if failures > 5:
		L["errors"].append("autoplay: %d more failing combinations" % (failures - 5))
	L["stats"]["autoplay_runs"] = combos.size()
	L["stats"]["combinations_total"] = total
	L["stats"]["autoplay_failures"] = failures
	L["stats"]["autoplay_ms"] = Time.get_ticks_msec() - t0
	var never_lines := 0
	for f: String in dialogues:
		for n: String in dialogues[f].get("nodes", {}):
			var key := "%s:%s" % [f, n]
			if not visited_nodes.has(key):
				L["errors"].append("dialogue %s/%s: never reached by any autoplay run" % [f, n])
			var lines: Array = dialogues[f]["nodes"][n].get("lines", [])
			for i in lines.size():
				if not shown_lines.has("%s:%d" % [key, i]):
					never_lines += 1
					L["warnings"].append("dialogue %s/%s line %d never shown in autoplay: %s" % [f, n, i,
						String(lines[i].get("text", "")).left(50)])
	L["stats"]["lines_never_shown"] = never_lines


static func _play_once(q: Dictionary, reg: Dictionary, dialogues: Dictionary, pick: Dictionary, blessing: String,
		visited_nodes: Dictionary, shown_lines: Dictionary, run := 0) -> String:
	var sq: Region1StoryQuest = StoryQuest.new()
	sq.setup(1)
	sq.use_quest(q, reg)
	# Vary the world a little per run so conditional lines get shown somewhere.
	var ctx := {"flags": {blessing: true}, "age": 8, "items": {}, "child": true,
		"time": ["morning", "evening", "afternoon", "night"][run % 4], "weather": ["clear", "rain"][run % 2],
		"vars": {"ancestor": "Wenna Ashby", "family": "Ashby", "stone_name": "The Miller's Stone"}}
	if run % 4 == 1:
		ctx["flags"]["spirit_seen"] = true
	if run % 3 == 2:
		ctx["flags"]["ember.has_ancestor"] = true
	var chosen := {}
	for g: String in pick:
		chosen[String(pick[g])] = true
	var played := {}
	_apply_events(sq.refresh(ctx), ctx)
	for iter in 400:
		if sq.is_complete():
			return ""
		var progressed := false
		for sid: String in sq.active_steps():
			for e: Dictionary in sq.dialogue_entries(sid):
				var key := sid + ":" + String(e["node"])
				if played.has(key):
					continue
				played[key] = true
				progressed = true
				var err := _walk(sq, dialogues, String(e["file"]), String(e["node"]), ctx, chosen, sid,
					visited_nodes, shown_lines, run)
				if err != "":
					return "step %s: %s" % [sid, err]
			var o := sq.current_objective(sid)
			if o.is_empty() or not sq.is_active(sid):
				continue
			var t := String(o.get("type", ""))
			if t == "age":
				if int(ctx["age"]) < int(o["min"]):
					ctx["age"] = int(o["min"])
					ctx["child"] = int(o["min"]) < 16
					progressed = true
			elif StoryQuest.EVENT_TYPES.has(t) or t == "any":
				var ev := _synth(o, reg, chosen)
				if ev.is_empty():
					continue
				if String(ev["type"]) == "talk":
					continue   # only the dialogue walk may satisfy a talk objective
				_apply_events(sq.notify(StringName(ev["type"]), ev["params"], ctx), ctx)
				progressed = true
		_apply_events(sq.refresh(ctx), ctx)
		if not progressed:
			var stuck: Array = []
			for sid: String in sq.active_steps():
				stuck.append("%s@%s" % [sid, sq.current_objective(sid).get("id", "?")])
			return "stuck at %s" % ", ".join(stuck)
	return "did not finish in 400 iterations"


static func _synth(o: Dictionary, reg: Dictionary, chosen: Dictionary) -> Dictionary:
	var t := String(o.get("type", ""))
	if t == "any":
		for sub: Dictionary in o.get("of", []):
			if chosen.has(String(sub.get("sets", ""))):
				return _synth(sub, reg, chosen)
		return _synth(o["of"][0], reg, chosen)
	var params := {}
	for k: String in StoryQuest.EVENT_TYPES[t]["match"]:
		if o.has(k):
			params[k] = o[k]
	var need_key := String(StoryQuest.EVENT_TYPES[t]["need"])
	params["amount"] = int(o.get(need_key, 1)) if need_key != "" else 1
	if t == "ember_choice":
		var g: Dictionary = reg["choice_groups"][String(o["group"])]
		for f: Variant in g["flags"]:
			if chosen.has(String(f)):
				params["choice"] = String(f).get_slice(".", 2)
	return {"type": t, "params": params}


static func _apply_events(ev: Array, ctx: Dictionary) -> void:
	for e: Dictionary in ev:
		if String(e.get("type", "")) == "action":
			var a: Array = e["action"]
			if String(a[0]) == "give":
				ctx["items"][String(a[1])] = int(ctx["items"].get(String(a[1]), 0)) + int(a[2])


## Walk one conversation from `node` like a player would: show the best line, take the choice
## that matches this run's picks (or the first unvisited one), apply its actions.
static func _walk(sq: Region1StoryQuest, dialogues: Dictionary, file: String, node: String, ctx: Dictionary,
		chosen: Dictionary, sid: String, visited_nodes: Dictionary, shown_lines: Dictionary, run := 0) -> String:
	var d: Dictionary = dialogues.get(file, {})
	var seen := {}
	for hop in 40:
		var cctx := sq.condition_ctx(ctx)
		var n: Dictionary = d.get("nodes", {}).get(node, {})
		var line := DialogueRunner.pick_line(d, node, cctx, null)
		if line.is_empty():
			return "%s/%s has no line to show (flags %s)" % [file, node, JSON.stringify(cctx["flags"].keys())]
		visited_nodes["%s:%s" % [file, node]] = true
		var lines: Array = n.get("lines", [])
		for i in lines.size():
			if DialogueRunner.fill(String(lines[i].get("text", "")), cctx) == line["text"]:
				shown_lines["%s:%s:%d" % [file, node, i]] = true
		seen[node] = true
		_apply_events(sq.apply_dialogue_actions(line.get("do", []), ctx, sid), ctx)
		_apply_events(sq.notify(&"talk", {"node": node}, ctx), ctx)
		var opts := DialogueRunner.choices(d, node, sq.condition_ctx(ctx))
		if opts.is_empty():
			return ""
		var take: Dictionary = {}
		for c: Dictionary in opts:   # the option this run picked
			for a: Variant in c["do"]:
				if a is Array and String(a[0]) == "flag" and chosen.has(String(a[1])):
					take = c
		if take.is_empty():
			# Else one of the options that sets no flag of another pick and does not loop;
			# which one varies with the run so flavour branches get walked too.
			var ok: Array = []
			for c: Dictionary in opts:
				var blocked := false
				for a: Variant in c["do"]:
					if a is Array and String(a[0]) == "flag" and _is_group_flag(sq, String(a[1])) \
							and not chosen.has(String(a[1])):
						blocked = true
				if not blocked and not seen.has(String(c["goto"])):
					ok.append(c)
			if not ok.is_empty():
				take = ok[(run + hop) % ok.size()]
		if take.is_empty():
			return "%s/%s: no choice fits this run" % [file, node]
		_apply_events(sq.apply_dialogue_actions(take["do"], ctx, sid), ctx)
		var g := String(take["goto"])
		if g == "" or g == "@end":
			return ""
		node = g
	return "%s: conversation longer than 40 hops" % file


static func _is_group_flag(sq: Region1StoryQuest, f: String) -> bool:
	for g: String in sq.registry.get("choice_groups", {}):
		if g.begins_with("_"):
			continue
		if (sq.registry["choice_groups"][g].get("flags", []) as Array).has(f):
			return true
	return false
