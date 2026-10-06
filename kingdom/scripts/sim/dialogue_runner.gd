extends RefCounted
## A small data-driven dialogue runner over JSON files in res://dialogue/.
##
## Why not Dialogue Manager (addons/dialogue_manager, autoloaded)? Its runtime is
## coroutine based (`await DialogueManager.get_next_dialogue_line(res, title)`),
## .dialogue files only load after the editor imports them, and conditions read
## game state by reflection over autoloads. Our menus are synchronous
## (hud.show_menu calls a source Callable on every rebuild) and must be testable
## headless, so conversations are plain JSON evaluated against a context
## Dictionary. Nothing here touches the scene tree.
##
## File format (dialogue/<id>.json):
##   {"id": "villager", "start": "greet",
##    "nodes": {"greet": {
##        "lines":   [{"text": "Morning, {player}.", "if": {"time": "morning"}, "p": 1}, ...],
##        "choices": [{"text": "Any news?", "goto": "gossip", "if": {...}, "do": [["opinion", ...]]}, ...]}}}
##
## Lines: of those whose "if" holds, the ones with the highest "p" (priority,
## default 0) are candidates and one is chosen with the rng, so a specific line
## ("you helped me yesterday", p 3) beats a tier greeting (p 1) beats a generic one.
## A line may carry its own "do" (applied when it is shown, e.g. a gossip line
## that marks a hint as told).
##
## Conditions ("if"), all must hold:
##   tier: "friend" | [..]          tier_not: ..        bond: "mother" | [..] | "" (none)
##   min_tier: "acquaintance"       time: "morning"|"afternoon"|"evening"|"night" | [..]
##   weather: "rain" | [..]         child: true|false   role: "healer" | [..]
##   flag: "spirit_seen" | [..]     no_flag: ..         event: "helped_recently" | [..]
##   no_event: ..                   min_op / max_op: opinion bounds
##   min_age / max_age              has: "rumour" | [..]  (ctx key must be truthy)
##   min_soul_tier / min_gear_tier / min_level   progression gates (ctx soul_tier, gear_tier, level; absent = not gated)
##   not_has: ..                    chance: 0.3
##
## Choice "goto": a node id, "" to stay on the current line, "@end" to close.
##
## Text tokens: {name} {first} {player} {town} {time} {weather} {greeting} {reply}
## {rumour} {hint} {mother} {father} {kid} (lad/child/friend), plus any string in
## ctx["vars"].
##
## Actions ("do", returned for the caller to apply):
##   ["opinion", id, label, value, fade_days]  ["rep", faction, delta]
##   ["bond", delta]  ["flag", name]  ["record", tag, weight]  ["give", item, n]  ["chores"]
##   ["gift"]  ["quests"]  ["turn_in"]  ["close"]  ["tell_hint"]
##
## Usage:
##   const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
##   var d := DialogueRunner.load_file("villager")        # {} on error
##   var line := DialogueRunner.pick_line(d, "greet", ctx, rng)   # {text, do}
##   var opts := DialogueRunner.choices(d, "greet", ctx)          # [{text, goto, do}]

const DIR := "res://dialogue"
const TIERS := ["enemy", "rival", "stranger", "acquaintance", "friend", "close_friend"]

static var _cache: Dictionary = {}


## Parsed dialogue file (cached), or {} when missing / invalid.
static func load_file(id: String, dir := DIR) -> Dictionary:
	var path := "%s/%s.json" % [dir, id]
	if _cache.has(path):
		return _cache[path]
	var out := {}
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			out = data
		else:
			push_warning("dialogue: could not parse %s" % path)
	_cache[path] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


static func start_node(d: Dictionary) -> String:
	return String(d.get("start", "greet"))


static func node_exists(d: Dictionary, node: String) -> bool:
	return (d.get("nodes", {}) as Dictionary).has(node)


static func time_bucket(hour: float) -> String:
	if hour >= 5.0 and hour < 12.0:
		return "morning"
	if hour >= 12.0 and hour < 17.0:
		return "afternoon"
	if hour >= 17.0 and hour < 21.5:
		return "evening"
	return "night"


static func _as_list(v: Variant) -> Array:
	return v if v is Array else [v]


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is String or v is StringName:
		return String(v) != ""
	if v is Array or v is Dictionary:
		return not v.is_empty()
	if v is int or v is float:
		return v != 0
	return true


## True when every condition in `cond` holds for ctx.
static func check(cond: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	for k: String in cond:
		var v: Variant = cond[k]
		match k:
			"tier":
				if not _as_list(v).has(ctx.get("tier", "stranger")):
					return false
			"tier_not":
				if _as_list(v).has(ctx.get("tier", "stranger")):
					return false
			"min_tier":
				if TIERS.find(String(ctx.get("tier", "stranger"))) < TIERS.find(String(v)):
					return false
			"bond":
				if not _as_list(v).has(String(ctx.get("bond", ""))):
					return false
			"time":
				if not _as_list(v).has(ctx.get("time", "")):
					return false
			"weather":
				if not _as_list(v).has(ctx.get("weather", "")):
					return false
			"child":
				if bool(ctx.get("child", false)) != bool(v):
					return false
			"role":
				if not _as_list(v).has(ctx.get("role", "")):
					return false
			"flag":
				var flags: Dictionary = ctx.get("flags", {})
				for f: Variant in _as_list(v):
					if not _truthy(flags.get(String(f))):
						return false
			"no_flag":
				var flags2: Dictionary = ctx.get("flags", {})
				for f: Variant in _as_list(v):
					if _truthy(flags2.get(String(f))):
						return false
			"event":
				var ev: Array = ctx.get("events", [])
				for e: Variant in _as_list(v):
					if not ev.has(e):
						return false
			"no_event":
				var ev2: Array = ctx.get("events", [])
				for e: Variant in _as_list(v):
					if ev2.has(e):
						return false
			"min_op":
				if float(ctx.get("opinion", 0)) < float(v):
					return false
			"max_op":
				if float(ctx.get("opinion", 0)) > float(v):
					return false
			"min_age":
				if int(ctx.get("age", 0)) < int(v):
					return false
			"max_age":
				if int(ctx.get("age", 0)) > int(v):
					return false
			# Progression gates (C13, data/region1/progression_spine.json). A context that carries no figure (tests, plain
			# conversations) is not gated; the story director passes the real soul tier, gear tier and level.
			"min_soul_tier":
				if int(ctx.get("soul_tier", 1 << 20)) < int(v):
					return false
			"min_gear_tier":
				if int(ctx.get("gear_tier", 1 << 20)) < int(v):
					return false
			"min_level":
				if int(ctx.get("level", 1 << 20)) < int(v):
					return false
			"has":
				for key: Variant in _as_list(v):
					if not _truthy(ctx.get(String(key))):
						return false
			"not_has":
				for key: Variant in _as_list(v):
					if _truthy(ctx.get(String(key))):
						return false
			"chance":
				var roll := rng.randf() if rng else 0.0
				if roll >= float(v):
					return false
	return true


## Fills {tokens} from ctx (unknown tokens are left as they are).
static func fill(text: String, ctx: Dictionary) -> String:
	var vars := {}
	for k: String in ["name", "first", "role", "player", "town", "time", "weather", "greeting", "reply", "rumour",
			"hint", "mother", "father", "kid"]:
		if ctx.has(k):
			vars[k] = str(ctx[k])
	var extra: Dictionary = ctx.get("vars", {})
	for k: Variant in extra:
		vars[String(k)] = str(extra[k])
	return text.format(vars)


## {text, do} for the node, or {} when no line matches.
static func pick_line(d: Dictionary, node: String, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var n: Dictionary = d.get("nodes", {}).get(node, {})
	var best: Array = []
	var best_p := -INF
	for l: Dictionary in n.get("lines", []):
		if not check(l.get("if", {}), ctx, rng):
			continue
		var p := float(l.get("p", 0))
		if p > best_p:
			best_p = p
			best = [l]
		elif p == best_p:
			best.append(l)
	if best.is_empty():
		return {}
	var pick: Dictionary = best[rng.randi() % best.size()] if rng else best[0]
	return {"text": fill(String(pick.get("text", "")), ctx), "do": pick.get("do", [])}


## [{text, goto, do}] for the node's choices whose conditions hold.
static func choices(d: Dictionary, node: String, ctx: Dictionary) -> Array:
	var n: Dictionary = d.get("nodes", {}).get(node, {})
	var out: Array = []
	for c: Dictionary in n.get("choices", []):
		if not check(c.get("if", {}), ctx, null):
			continue
		out.append({"text": fill(String(c.get("text", "")), ctx), "goto": String(c.get("goto", "")), "do": c.get("do", [])})
	return out


## Every problem found in a dialogue file: gotos to missing nodes, nodes with no
## lines, unknown condition keys. Empty when the file is sound (used by tests).
static func validate(d: Dictionary) -> PackedStringArray:
	var known := ["tier", "tier_not", "min_tier", "bond", "time", "weather", "child", "role", "flag", "no_flag",
		"event", "no_event", "min_op", "max_op", "min_age", "max_age", "has", "not_has", "chance", "min_soul_tier", "min_gear_tier", "min_level"]
	var out := PackedStringArray()
	var nodes: Dictionary = d.get("nodes", {})
	if not nodes.has(start_node(d)):
		out.append("start node '%s' missing" % start_node(d))
	for id: String in nodes:
		var n: Dictionary = nodes[id]
		if (n.get("lines", []) as Array).is_empty():
			out.append("%s: no lines" % id)
		for l: Dictionary in n.get("lines", []):
			for k: String in l.get("if", {}):
				if not known.has(k):
					out.append("%s: unknown condition '%s'" % [id, k])
		for c: Dictionary in n.get("choices", []):
			var g := String(c.get("goto", ""))
			if g != "" and g != "@end" and not nodes.has(g):
				out.append("%s: goto '%s' missing" % [id, g])
			for k: String in c.get("if", {}):
				if not known.has(k):
					out.append("%s: unknown condition '%s'" % [id, k])
	return out
