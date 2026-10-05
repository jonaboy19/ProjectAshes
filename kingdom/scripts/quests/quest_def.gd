class_name QuestDef
extends RefCounted
## A quest as data: stages of objectives from the library. Quests are optional (nobody is forced to take one),
## show no markers on their own (the player pins them), and never play cutscenes.
##
## JSON shape (data/quests/<area>/<quest>.json):
## {
##   "id": "thornfield_spoiled_barley", "title": "...", "summary": "...",
##   "giver": {"npc": "hesta_thorne", "name": "Hesta Thorne", "place": "thornfield"},
##   "requires": ["other_quest_id"],                    # quests that must be completed first
##   "offer_text": "...", "turn_in_text": "...",
##   "stages": [
##     {"id": "s1", "title": "...", "mode": "all" | "any" | "sequence",
##      "objectives": [{"id": "o1", "type": "investigate", ...}],
##      "next": "stage id"          # default: the next stage in the list
##      "branches": {"option id": "stage id"}   # from a choose objective of this stage
##      "end": true                 # completes the quest here
##      "rewards": {...}}           # applied when the stage completes
##   ],
##   "rewards": {...}              # applied when the quest completes
##   "on_fail": {...}              # applied when the quest fails
## }
## Rewards: {gold, items: {item: n}, rep: {faction: n}, relationship: [{npc, value, label, days}], flags: [..]}.

const Objectives := preload("res://scripts/quests/quest_objectives.gd")
const MODES := ["all", "any", "sequence"]

var data: Dictionary = {}
var id := ""
var title := ""
var stages: Array = []
var _index: Dictionary = {}   # stage id -> index


static func from_dict(d: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.data = d.duplicate(true)
	q.id = String(d.get("id", ""))
	q.title = String(d.get("title", q.id))
	q.stages = q.data.get("stages", [])
	for i in q.stages.size():
		var s: Dictionary = q.stages[i]
		if not s.has("id"):
			s["id"] = "s%d" % (i + 1)
		q._index[String(s["id"])] = i
	return q


static func load_json(path: String) -> QuestDef:
	if not FileAccess.file_exists(path):
		return null
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(v) if v is Dictionary else null


func summary() -> String:
	return String(data.get("summary", ""))


func giver_npc() -> String:
	return String((data.get("giver", {}) as Dictionary).get("npc", ""))


func giver_name() -> String:
	var g: Dictionary = data.get("giver", {})
	return String(g.get("name", g.get("npc", "")))


func requires() -> Array:
	return data.get("requires", [])


func rewards() -> Dictionary:
	return data.get("rewards", {})


func has_stage(sid: String) -> bool:
	return _index.has(sid)


func stage(sid: String) -> Dictionary:
	return stages[_index[sid]] if _index.has(sid) else {}


func first_stage() -> String:
	return String(stages[0]["id"]) if not stages.is_empty() else ""


## The stage after `sid` given the options chosen so far ({objective id: option id}); "" ends the quest.
func next_stage(sid: String, chosen: Dictionary) -> String:
	var s := stage(sid)
	if s.is_empty() or bool(s.get("end", false)):
		return ""
	var branches: Dictionary = s.get("branches", {})
	for o: Dictionary in s.get("objectives", []):
		if String(o.get("type", "")) == "choose" and chosen.has(String(o.get("id", ""))):
			var opt := String(chosen[String(o["id"])])
			if branches.has(opt):
				return String(branches[opt])
	if s.has("next"):
		return String(s["next"])
	var i: int = _index[sid] + 1
	return String(stages[i]["id"]) if i < stages.size() else ""


## Objective types used by the quest (for the "uses N types" checks and tooling).
func objective_types() -> PackedStringArray:
	var seen := {}
	for s: Dictionary in stages:
		for o: Dictionary in s.get("objectives", []):
			seen[String(Objectives.ALIASES.get(String(o.get("type", "")), o.get("type", "")))] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## Problems with the data, empty when it is sound.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if id == "":
		errs.append("quest has no id")
	if stages.is_empty():
		errs.append("%s: no stages" % id)
	var oids := {}
	for s: Dictionary in stages:
		var sid := String(s.get("id", ""))
		if not MODES.has(String(s.get("mode", "all"))):
			errs.append("%s/%s: unknown mode" % [id, sid])
		if (s.get("objectives", []) as Array).is_empty():
			errs.append("%s/%s: no objectives" % [id, sid])
		var chooses := {}
		for o: Dictionary in s.get("objectives", []):
			var oid := String(o.get("id", ""))
			if oid == "" or oids.has(oid):
				errs.append("%s/%s: objective id '%s' missing or duplicated" % [id, sid, oid])
			oids[oid] = true
			if not Objectives.has_type(String(o.get("type", ""))):
				errs.append("%s/%s/%s: unknown objective type '%s'" % [id, sid, oid, o.get("type", "")])
			if String(o.get("type", "")) == "choose":
				for opt: Dictionary in o.get("options", []):
					chooses[String(opt.get("id", ""))] = true
		for opt: String in (s.get("branches", {}) as Dictionary):
			if not chooses.has(opt):
				errs.append("%s/%s: branch '%s' is not an option of a choose objective" % [id, sid, opt])
			if not has_stage(String(s["branches"][opt])):
				errs.append("%s/%s: branch '%s' goes to unknown stage" % [id, sid, opt])
		if s.has("next") and not has_stage(String(s["next"])):
			errs.append("%s/%s: next goes to unknown stage" % [id, sid])
	return errs
