class_name Region1StoryQuest
extends Region1Sim
## Runtime for authored Region 1 quests (the main quest "The Stones Are Dimming", L14, and
## later the side quests, L15). Pure data machine: no scene tree, no autoloads. The game
## (package C7) feeds it events and applies the actions it hands back.
##
## Data: data/region1/quests/<quest>.json, schema in data/region1/quests/README.md.
##
##   var q := Region1StoryQuest.new()
##   q.setup(seed); q.load_quest("res://data/region1/quests/r1_main.json")
##   Region1State.register_sim(q)                 # saves under "story_quest"
##   q.refresh(ctx)                               # activates steps whose requirements hold
##   q.notify(&"carve", {"glyph": "ward", "stone": "miller_stone"}, ctx)
##   q.set_flag("r1.a1.taught", ctx)              # dialogue "do" ["flag", ...] goes here
##   q.dialogue_entries("a1_first_glyph")         # conversations available now: [{file, node, speaker}]
##
## ctx = {"flags": {name: true} (game flags: blessing:*, came_of_age, ...), "age": int,
##        "items": {item_id: count}}. Story flags ("r1.*", "ember.*") live here and are saved.
##
## notify()/refresh()/set_flag() return events, oldest first:
##   {"type": "step_started", "step": id}      {"type": "objective_done", "step": id, "objective": id}
##   {"type": "step_completed", "step": id}    {"type": "quest_completed", "quest": id}
##   {"type": "action", "step": id, "action": [...]}   # caller applies: give, rep, gold, cutscene,
##                                                     # marker, spawn, tutorial ("flag" is applied here)
## Objectives inside a step complete in order: only the first open one listens.

const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const SAVE_STATE_VERSION := 1

## type -> keys an event must match (when the objective sets them) and the amount key.
const EVENT_TYPES := {
	"enter_area": {"match": ["place"], "need": ""},
	"kill": {"match": ["target", "place"], "need": "count"},
	"defeat": {"match": ["target"], "need": ""},
	"carve": {"match": ["glyph", "stone"], "need": "count"},
	"relight_elder": {"match": ["stone"], "need": ""},
	"wardline_link": {"match": ["from", "to"], "need": "count"},
	"scar_contain": {"match": ["place"], "need": "cells"},
	"scar_harvest": {"match": ["place"], "need": "crystals"},
	"ashsight": {"match": ["site"], "need": ""},
	"ember_choice": {"match": ["who"], "need": ""},
	"cutscene_done": {"match": ["cutscene"], "need": ""},
	"talk": {"match": ["node"], "need": ""},
	"festival": {"match": ["festival"], "need": ""},
}
## Objective types judged from state rather than events.
const STATE_TYPES := ["flag", "choice", "age", "item"]

var quest: Dictionary = {}
var registry: Dictionary = {}
var steps: Array = []
var _by_id: Dictionary = {}
var status: Dictionary = {}     # step id -> "active" | "done"
var progress: Dictionary = {}   # step id -> {objective id: amount}
var flags: Dictionary = {}      # story flags -> true


func _init() -> void:
	module_name = &"story_quest"
	state_version = SAVE_STATE_VERSION


func _setup() -> void:
	status.clear()
	progress.clear()
	flags.clear()


func load_quest(path: String) -> bool:
	var q: Variant = _read_json(path)
	if not (q is Dictionary):
		return false
	use_quest(q, _read_json(String(q.get("registry", ""))) if q.has("registry") else {})
	return true


## Load already-parsed data (tests, lint).
func use_quest(q: Dictionary, reg: Variant = {}) -> void:
	quest = q
	registry = reg if reg is Dictionary else {}
	steps = q.get("steps", [])
	_by_id.clear()
	for s: Dictionary in steps:
		_by_id[String(s.get("id", ""))] = s


static func _read_json(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func step(id: String) -> Dictionary:
	return _by_id.get(id, {})


func is_done(id: String) -> bool:
	return status.get(id, "") == "done"


func is_active(id: String) -> bool:
	return status.get(id, "") == "active"


func active_steps() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in steps:
		if is_active(String(s["id"])):
			out.append(String(s["id"]))
	return out


func is_complete() -> bool:
	return flags.has(String(quest.get("complete_flag", "")))


func has_flag(f: String, ctx: Dictionary = {}) -> bool:
	return flags.has(f) or _truthy((ctx.get("flags", {}) as Dictionary).get(f))


## Game flags merged with story flags, for DialogueRunner.check() and dialogue lines.
func merged_flags(ctx: Dictionary = {}) -> Dictionary:
	var m: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
	for f: String in flags:
		m[f] = true
	return m


func condition_ctx(ctx: Dictionary = {}) -> Dictionary:
	var c := ctx.duplicate()
	c["flags"] = merged_flags(ctx)
	return c


# --- driving ------------------------------------------------------------------------

## Activate every locked step whose requirements hold, and complete state-met objectives.
func refresh(ctx: Dictionary = {}) -> Array:
	var ev: Array = []
	var changed := true
	var guard := 0
	while changed and guard < 64:
		changed = false
		guard += 1
		for s: Dictionary in steps:
			var id := String(s["id"])
			if status.has(id) or not _requirements_met(s, ctx):
				continue
			status[id] = "active"
			progress[id] = {}
			ev.append({"type": "step_started", "step": id})
			_run_actions(id, s.get("on_start", []), ev)
			changed = true
		for id: String in active_steps():
			if _advance(id, ctx, ev):
				changed = true
	return ev


## Report a world event. `type` is an EVENT_TYPES key; params as in the objective
## (plus "amount" for counted objectives). ember_choice params {who, choice} also set
## the story flag "ember.<who>.<choice>".
func notify(type: StringName, params: Dictionary = {}, ctx: Dictionary = {}) -> Array:
	var ev: Array = []
	var t := String(type)
	if t == "ember_choice" and params.has("who") and params.has("choice"):
		flags["ember.%s.%s" % [params["who"], params["choice"]]] = true
	for id: String in active_steps():
		var o := _current_objective(id)
		if o.is_empty():
			continue
		var hit := _event_hits(o, t, params)
		if hit.is_empty():
			continue
		var p: Dictionary = progress[id]
		var key := String(hit.get("id", o.get("id", "")))
		p[key] = int(p.get(key, 0)) + int(params.get("amount", 1))
	ev.append_array(refresh(ctx))
	return ev


func set_flag(f: String, ctx: Dictionary = {}) -> Array:
	flags[f] = true
	return refresh(ctx)


## Apply a dialogue "do" list: flags are handled here, everything else is returned as
## action events for the caller (give, rep, opinion, bond, record, ...).
func apply_dialogue_actions(actions: Array, ctx: Dictionary = {}, step_id := "") -> Array:
	var ev: Array = []
	for a: Variant in actions:
		if a is Array and not (a as Array).is_empty() and String(a[0]) == "flag":
			flags[String(a[1])] = true
		else:
			ev.append({"type": "action", "step": step_id, "action": a})
	ev.append_array(refresh(ctx))
	return ev


## Conversations the giver (or the node's speaker) offers for this step right now:
## entries without "after", or whose "after" objective is done. [{file, node, speaker}]
func dialogue_entries(step_id: String) -> Array:
	var s := step(step_id)
	var out: Array = []
	if s.is_empty() or not is_active(step_id):
		return out
	for e: Dictionary in s.get("dialogue", []):
		var after := String(e.get("after", ""))
		if after != "" and not objective_done(step_id, after):
			continue
		var file := String(e.get("file", act_dialogue(int(s.get("act", 0)))))
		var d := load_dialogue(file)
		var node: Dictionary = d.get("nodes", {}).get(String(e["node"]), {})
		out.append({"file": file, "node": String(e["node"]), "speaker": String(node.get("speaker", ""))})
	return out


func act_dialogue(act: int) -> String:
	for a: Dictionary in quest.get("acts", []):
		if int(a.get("act", -1)) == act:
			return String(a.get("dialogue", ""))
	return ""


func load_dialogue(file: String) -> Dictionary:
	return DialogueRunner.load_file(file, String(quest.get("dialogue_dir", "res://data/region1/dialogue")))


## The open objective the tracker should show ({} when none).
func current_objective(step_id: String) -> Dictionary:
	return _current_objective(step_id)


func objective_done(step_id: String, obj_id: String) -> bool:
	if is_done(step_id):
		return true
	var s := step(step_id)
	for o: Dictionary in s.get("objectives", []):
		if String(o.get("id", "")) == obj_id:
			return bool((progress.get(step_id, {}) as Dictionary).get("_done_" + obj_id, false))
	return false


# --- internals ----------------------------------------------------------------------

func _requirements_met(s: Dictionary, ctx: Dictionary) -> bool:
	var r: Dictionary = s.get("requires", {})
	for dep: Variant in r.get("steps", []):
		if not is_done(String(dep)):
			return false
	var cond: Dictionary = r.get("if", {})
	return cond.is_empty() or DialogueRunner.check(cond, condition_ctx(ctx), null)


func _current_objective(id: String) -> Dictionary:
	var p: Dictionary = progress.get(id, {})
	for o: Dictionary in step(id).get("objectives", []):
		if not bool(p.get("_done_" + String(o.get("id", "")), false)):
			return o
	return {}


## Complete open objectives in order while they are met. True when anything changed.
func _advance(id: String, ctx: Dictionary, ev: Array) -> bool:
	var s := step(id)
	var p: Dictionary = progress[id]
	var changed := false
	for o: Dictionary in s.get("objectives", []):
		var oid := String(o.get("id", ""))
		if bool(p.get("_done_" + oid, false)):
			continue
		var met := _met(o, p, ctx)
		if met.is_empty():
			break
		p["_done_" + oid] = true
		changed = true
		ev.append({"type": "objective_done", "step": id, "objective": oid})
		if met.has("sets"):
			flags[String(met["sets"])] = true
		_run_actions(id, met.get("do", []), ev)
		if met != o:
			_run_actions(id, o.get("do", []), ev)
	if _current_objective(id).is_empty():
		status[id] = "done"
		ev.append({"type": "step_completed", "step": id})
		_run_actions(id, s.get("on_complete", []), ev)
		if is_complete():
			ev.append({"type": "quest_completed", "quest": String(quest.get("id", ""))})
		changed = true
	return changed


## The objective (or the "any" branch) that is met, or {}.
func _met(o: Dictionary, p: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := String(o.get("type", ""))
	match t:
		"any":
			for sub: Dictionary in o.get("of", []):
				if not _met(sub, p, ctx).is_empty():
					return sub
			return {}
		"flag":
			return o if has_flag(String(o.get("flag", "")), ctx) else {}
		"choice":
			var g: Dictionary = (registry.get("choice_groups", {}) as Dictionary).get(String(o.get("group", "")), {})
			for f: Variant in g.get("flags", []):
				if has_flag(String(f), ctx):
					return o
			return {}
		"age":
			return o if int(ctx.get("age", 0)) >= int(o.get("min", 0)) else {}
		"item":
			var have := int((ctx.get("items", {}) as Dictionary).get(String(o.get("item", "")), 0))
			have = maxi(have, int(p.get(String(o.get("id", "")), 0)))
			return o if have >= int(o.get("count", 1)) else {}
	if EVENT_TYPES.has(t):
		var need_key := String(EVENT_TYPES[t]["need"])
		var need := int(o.get(need_key, 1)) if need_key != "" else 1
		return o if int(p.get(String(o.get("id", "")), 0)) >= need else {}
	return {}


## The objective (or "any" branch) this event advances, or {}.
func _event_hits(o: Dictionary, t: String, params: Dictionary) -> Dictionary:
	if String(o.get("type", "")) == "any":
		for sub: Dictionary in o.get("of", []):
			if not _event_hits(sub, t, params).is_empty():
				return sub
		return {}
	if t == "item" and String(o.get("type", "")) == "item":
		return o if String(params.get("item", "")) == String(o.get("item", "")) else {}
	if String(o.get("type", "")) != t or not EVENT_TYPES.has(t):
		return {}
	for k: String in EVENT_TYPES[t]["match"]:
		if o.has(k) and String(params.get(k, "")) != String(o[k]):
			return {}
	return o


func _run_actions(step_id: String, actions: Array, ev: Array) -> void:
	for a: Variant in actions:
		if not (a is Array) or (a as Array).is_empty():
			continue
		if String(a[0]) == "flag":
			flags[String(a[1])] = true
		else:
			ev.append({"type": "action", "step": step_id, "action": a})


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is String:
		return v != ""
	if v is int or v is float:
		return v != 0
	return true


# --- persistence ----------------------------------------------------------------------

func _save_state() -> Dictionary:
	return {"quest": String(quest.get("id", "")), "status": status.duplicate(),
		"progress": progress.duplicate(true), "flags": flags.keys()}


func _load_state(d: Dictionary) -> void:
	status = (d.get("status", {}) as Dictionary).duplicate()
	progress = {}
	var pr: Dictionary = d.get("progress", {})
	for k: String in pr:
		var inner := {}
		for ok: String in pr[k]:
			var v: Variant = pr[k][ok]
			inner[ok] = v if v is bool else int(v)   # JSON turns ints into floats
		progress[k] = inner
	flags = {}
	for f: Variant in d.get("flags", []):
		flags[String(f)] = true
