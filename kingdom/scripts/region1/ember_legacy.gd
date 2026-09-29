class_name EmberLegacy
extends Region1Sim
## N3 Ember Legacy (package L10): when a life ends, its soul is an Ember and the player
## chooses where it rests:
##   * a RUNESTONE   -> the stone becomes an ancestor stone: more power and reach, a
##                      personality derived from the biography and bark templates that
##                      speak in the old character's voice;
##   * an HEIRLOOM   -> a weapon or tool that levels up with each generation;
##   * the HEIR      -> the heir inherits one Echo (and a small skill trace).
##
## Pure data (RefCounted, JSON-safe, no scene tree, no autoloads). Everything the sim needs
## from the game arrives as plain Dictionaries through `on_life_ended(summary)`. Build that
## summary with the static `build_summary()` (duck-typed on the Biography and Echoes
## objects) or, in the game hook H7, with the one-liner `emit_life_ended()`.
##
## Data: data/region1/ember_legacy.json (power formula, archetypes, heirlooms, barks).

const RALifePath := preload("res://scripts/sim/life_path.gd")
const DATA_PATH := "res://data/region1/ember_legacy.json"
const SAVE_STATE_VERSION := 1
const CHOICE_STONE := "runestone"
const CHOICE_HEIRLOOM := "heirloom"
const CHOICE_HEIR := "heir"
const MAX_LINEAGE := 64

## Emitted when a life ends and an ember is waiting for a choice (H7 payload).
signal life_ended(summary: Dictionary)
signal ember_placed(choice: String, result: Dictionary)

static var _data_cache: Dictionary = {}

## Pending embers: [{id, born_day, profile}]
var embers: Array[Dictionary] = []
## stone id (String) -> ancestor stone record
var ancestor_stones: Dictionary = {}
## [{id, name, kind, item, stat, ancestor, family, level, xp, gen}]
var heirlooms: Array[Dictionary] = []
## [{name, choice, day, detail}]: every ember ever placed, newest last
var lineage: Array[Dictionary] = []
var generation := 0
var _next_id := 1


func _init() -> void:
	module_name = &"ember_legacy"
	state_version = SAVE_STATE_VERSION


# --- data -----------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data_cache.is_empty():
		var txt := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(txt)
		_data_cache = parsed if parsed is Dictionary else {"archetypes": {}, "barks": {}}
	return _data_cache


# --- H7: a life ends -------------------------------------------------------------------

## Build the summary `on_life_ended` needs from the game's own objects. `biography` is a
## biography.gd instance (or anything with `serialize()` returning chapters and reputation),
## `echoes` an echoes.gd instance (or null). `extra` may carry: place, mastery {disc: xp},
## tendencies {}, cause. Pure function: reads, never writes.
static func build_summary(biography: Object, echoes: Object, full_name: String, age: int,
		family_name: String, day: int, extra: Dictionary = {}) -> Dictionary:
	var bio: Dictionary = biography.serialize() if biography != null and biography.has_method("serialize") else {}
	var ec: Dictionary = echoes.serialize() if echoes != null and echoes.has_method("serialize") else {}
	var attuned: Array = ec.get("attuned", [])
	var echo_list: Array = []
	for e: Dictionary in ec.get("echoes", []):
		echo_list.append({"type": String(e.get("type", "")), "source_name": String(e.get("source_name", "")),
			"strength": float(e.get("strength", 1.0)), "day": int(e.get("day", 0)),
			"attuned": int(e.get("id", -1)) in attuned})
	var highlights: Array = []
	var chapters: Array = []
	for c: Dictionary in bio.get("chapters", []):
		chapters.append({"role": String(c.get("role", "")), "org": String(c.get("org", "")),
			"place": String(c.get("place", "")), "start_day": int(c.get("start_day", 0)),
			"end_day": int(c.get("end_day", -1))})
		for h: Dictionary in c.get("highlights", []):
			highlights.append({"text": String(h.get("text", "")), "day": int(h.get("day", 0))})
	highlights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) < int(b["day"]))
	return {
		"name": full_name, "family": family_name, "age": age, "day": day,
		"cause": String(extra.get("cause", "old age")), "place": String(extra.get("place", "")),
		"reputation": (bio.get("reputation", {}) as Dictionary).duplicate(),
		"chapters": chapters, "highlights": highlights, "echoes": echo_list,
		"mastery": (extra.get("mastery", {}) as Dictionary).duplicate(),
		"tendencies": (extra.get("tendencies", {}) as Dictionary).duplicate(),
	}


## Hook H7 in one line (see docs/regions/HOOKS_FOR_CLOUD.md): finds the live sim and files
## the summary. Returns the new ember id, or -1 when the module is not running.
static func emit_life_ended(biography: Object, echoes: Object, full_name: String, age: int,
		family_name: String, day: int, extra: Dictionary = {}) -> int:
	var s := Region1State.sim(&"ember_legacy") as EmberLegacy
	if s == null:
		return -1
	return s.on_life_ended(build_summary(biography, echoes, full_name, age, family_name, day, extra))


## A life has ended: derive the ancestor profile and queue the ember for a choice.
func on_life_ended(summary: Dictionary) -> int:
	var id := _next_id
	_next_id += 1
	var profile := derive_profile(summary)
	embers.append({"id": id, "born_day": int(summary.get("day", 0)), "profile": profile})
	emit_event(&"ember_born", {"id": id, "name": profile["name"], "archetype": profile["archetype"]})
	life_ended.emit(summary)
	return id


# --- profile derived from the biography ------------------------------------------------

## sphere ("military", "trade", ...) for a chapter role id, by keyword. "" when unknown.
static func sphere_of_role(role: String) -> String:
	var table: Dictionary = data().get("role_sphere", {})
	var r := role.to_lower()
	for sphere: String in table:
		for kw: String in table[sphere]:
			if r.contains(kw):
				return sphere
	return ""


## Personality and stats of the ancestor, from the summary. Deterministic.
static func derive_profile(sum: Dictionary) -> Dictionary:
	var rep: Dictionary = sum.get("reputation", {})
	# Sphere: strongest |reputation| (>= 10), else the longest-held role, else farming.
	var sphere := ""
	var best := 0.0
	for s: String in rep:
		if absf(float(rep[s])) > absf(best):
			best = float(rep[s])
			sphere = s
	if absf(best) < 10.0:
		sphere = ""
	var role_days: Dictionary = {}
	var last_place := String(sum.get("place", ""))
	var last_role := ""
	var days_lived := 0
	for c: Dictionary in sum.get("chapters", []):
		var end := int(c.get("end_day", -1))
		if end < 0:
			end = int(sum.get("day", 0))
		var span := maxi(0, end - int(c.get("start_day", 0)))
		days_lived += span
		role_days[String(c.get("role", ""))] = int(role_days.get(String(c.get("role", "")), 0)) + span
		if String(c.get("place", "")) != "":
			last_place = String(c["place"])
		last_role = String(c.get("role", ""))
	var top_role := ""
	var top_days := -1
	for r: String in role_days:
		if int(role_days[r]) > top_days:
			top_days = int(role_days[r])
			top_role = r
	if sphere == "":
		sphere = sphere_of_role(top_role)
	if sphere == "":
		sphere = "farming"
	var arch: Dictionary = data().get("archetypes", {}).get(sphere, {})
	var traits: Dictionary = (arch.get("traits", {"warmth": 0.5, "stern": 0.5, "humor": 0.5}) as Dictionary).duplicate()
	# A disliked ancestor is colder; tendencies nudge the mood (compassion warms, martial hardens).
	var tend: Dictionary = sum.get("tendencies", {})
	traits["warmth"] = clampf(float(traits["warmth"]) + (0.15 if best > 0.0 else (-0.25 if best < 0.0 else 0.0))
		+ 0.2 * (float(tend.get("compassion", 0.35)) - 0.35), 0.0, 1.0)
	traits["stern"] = clampf(float(traits["stern"]) + 0.2 * (float(tend.get("martial", 0.35)) - 0.35), 0.0, 1.0)
	traits["humor"] = clampf(float(traits["humor"]) + 0.2 * (float(tend.get("mischief", 0.35)) - 0.35), 0.0, 1.0)
	var highlights: Array = sum.get("highlights", [])
	var deed := "You know what I did"
	if not highlights.is_empty():
		deed = String((highlights[highlights.size() - 1] as Dictionary).get("text", deed))
	var full := String(sum.get("name", "An ancestor"))
	var family := String(sum.get("family", full.get_slice(" ", 1) if full.contains(" ") else ""))
	var years := int(days_lived / float(RALifePath.DAYS_PER_YEAR)) if days_lived > 0 else int(sum.get("age", 0)) / 3
	var rep_total := 0.0
	for s: String in rep:
		rep_total += absf(float(rep[s]))
	var pw: Dictionary = data().get("power", {})
	var bonus := float(pw.get("base", 0.1)) + rep_total * float(pw.get("per_rep_point", 0.002)) \
		+ float(years) * float(pw.get("per_year_lived", 0.0015)) \
		+ float(highlights.size()) * float(pw.get("per_highlight", 0.006))
	bonus = clampf(bonus, 0.0, float(pw.get("max", 0.45)))
	# Best skill for the skill trace.
	var mastery: Dictionary = sum.get("mastery", {})
	var top_skill := ""
	var top_xp := 0.0
	for d: String in mastery:
		if float(mastery[d]) > top_xp:
			top_xp = float(mastery[d])
			top_skill = d
	return {
		"name": full, "family": family, "first": full.get_slice(" ", 0), "age": int(sum.get("age", 0)),
		"sphere": sphere, "archetype": sphere, "title": String(arch.get("title", "the Remembered")),
		"traits": traits, "role": top_role if top_role != "" else last_role, "place": last_place,
		"years": years, "deed": deed, "power_bonus": bonus, "top_skill": top_skill,
		"echoes": (sum.get("echoes", []) as Array).duplicate(true),
	}


# --- choices ---------------------------------------------------------------------------

func ember(id: int) -> Dictionary:
	for e in embers:
		if int(e["id"]) == id:
			return e
	return {}


func pending() -> Array[Dictionary]:
	return embers


## The 3-card choice UI reads this: [{choice, title, text}].
func choices_for(ember_id: int) -> Array[Dictionary]:
	var e := ember(ember_id)
	if e.is_empty():
		return []
	var p: Dictionary = e["profile"]
	var arch: Dictionary = data().get("archetypes", {}).get(String(p["archetype"]), {})
	var hl: Dictionary = arch.get("heirloom", {})
	var echo_name := "a whisper of their strength"
	var best := pick_echo(p.get("echoes", []))
	if not best.is_empty():
		echo_name = "%s" % String(best.get("source_name", best.get("type", "")))
	return [
		{"choice": CHOICE_STONE, "title": "Rest in a runestone",
			"text": "The stone gains +%d%% power and speaks as %s." % [int(round(float(p["power_bonus"]) * 100.0)), p["first"]]},
		{"choice": CHOICE_HEIRLOOM, "title": "Rest in an heirloom",
			"text": "%s that grows stronger with every generation." % String(hl.get("name", "A keepsake")).replace("{family}", String(p["family"]))},
		{"choice": CHOICE_HEIR, "title": "Rest in your heir",
			"text": "Your heir inherits an Echo (%s) and a trace of skill." % echo_name},
	]


## Put the ember into a runestone. `stone_id` is a runestone_network stone id (int or String).
func choose_runestone(ember_id: int, stone_id: Variant, stone_name: String = "", day: int = -1) -> Dictionary:
	var e := ember(ember_id)
	if e.is_empty():
		return {"ok": false, "text": "There is no such ember."}
	var key := str(stone_id)
	if ancestor_stones.has(key):
		return {"ok": false, "text": "An ancestor already rests in that stone."}
	var p: Dictionary = e["profile"]
	var rec := {
		"stone_id": key, "stone_name": stone_name, "ancestor": String(p["name"]), "family": String(p["family"]),
		"first": String(p["first"]), "title": String(p["title"]), "archetype": String(p["archetype"]),
		"traits": (p["traits"] as Dictionary).duplicate(), "power_bonus": float(p["power_bonus"]),
		"role": String(p["role"]), "place": String(p["place"]), "years": int(p["years"]), "deed": String(p["deed"]),
		"echoes": _echo_types(p), "day": day if day >= 0 else int(e["born_day"]), "gen": generation,
		"barks_seed": hash([String(p["name"]), key]),
	}
	ancestor_stones[key] = rec
	_finish(e, CHOICE_STONE, {"stone_id": key})
	return {"ok": true, "text": "%s's ember settles into the stone, and it glows gold." % p["name"], "stone": rec}


## Turn the ember into a family heirloom. Returns {ok, text, heirloom}.
func choose_heirloom(ember_id: int) -> Dictionary:
	var e := ember(ember_id)
	if e.is_empty():
		return {"ok": false, "text": "There is no such ember."}
	var p: Dictionary = e["profile"]
	var arch: Dictionary = data().get("archetypes", {}).get(String(p["archetype"]), {})
	var hl: Dictionary = arch.get("heirloom", {"name": "{family} Keepsake", "kind": "tool", "item": "heirloom_keepsake", "stat": "luck"})
	var item := {
		"id": _next_id, "name": String(hl["name"]).replace("{family}", String(p["family"])),
		"kind": String(hl["kind"]), "item": String(hl["item"]), "stat": String(hl["stat"]),
		"ancestor": String(p["name"]), "family": String(p["family"]), "level": 1, "xp": 0, "gen": generation,
	}
	_next_id += 1
	heirlooms.append(item)
	_finish(e, CHOICE_HEIRLOOM, {"heirloom": int(item["id"])})
	return {"ok": true, "text": "%s's ember wakes in the %s." % [p["name"], item["name"]], "heirloom": item.duplicate(true)}


## Bless the heir. Picks the strongest of the ancestor's echoes (or the family echo when they
## had none) and a skill trace. Does not touch game objects: pass the result to
## `apply_blessing()` (or add it yourself). {ok, text, echo: {type, source_name, strength},
## skill: {discipline, xp}}.
func choose_heir(ember_id: int) -> Dictionary:
	var e := ember(ember_id)
	if e.is_empty():
		return {"ok": false, "text": "There is no such ember."}
	var p: Dictionary = e["profile"]
	var echo := pick_echo(p.get("echoes", []))
	if echo.is_empty():
		echo = {"type": String(data().get("blessing", {}).get("fallback_echo", "family_echo")),
			"source_name": String(p["name"]), "strength": 1.0}
	else:
		echo = {"type": String(echo["type"]), "source_name": String(echo.get("source_name", p["name"])),
			"strength": float(echo.get("strength", 1.0))}
	var skill := {"discipline": String(p["top_skill"]),
		"xp": float(data().get("blessing", {}).get("skill_trace_xp", 60.0)) if String(p["top_skill"]) != "" else 0.0}
	_finish(e, CHOICE_HEIR, {"echo": echo["type"]})
	return {"ok": true, "text": "%s's ember rests in you. You carry %s." % [p["name"], echo["source_name"]],
		"echo": echo, "skill": skill}


## Adds the blessed Echo to the heir's echoes.gd instance (and the skill trace to a
## mastery.gd instance if given). Idempotent per (type, source): returns the echo dict.
func apply_blessing(blessing: Dictionary, echoes_obj: Object, day: int, mastery_obj: Object = null) -> Dictionary:
	if not bool(blessing.get("ok", false)) or echoes_obj == null:
		return {}
	var echo: Dictionary = blessing["echo"]
	var src := String(echo["source_name"])
	for x: Dictionary in echoes_obj.echoes:
		if String(x["type"]) == String(echo["type"]) and String(x["source_name"]) == src:
			return x
	var added: Dictionary = echoes_obj.add_echo(String(echo["type"]), src, day, float(echo["strength"]))
	var sk: Dictionary = blessing.get("skill", {})
	if mastery_obj != null and float(sk.get("xp", 0.0)) > 0.0 and "xp" in mastery_obj:
		var d := String(sk["discipline"])
		mastery_obj.xp[d] = float(mastery_obj.xp.get(d, 0.0)) + float(sk["xp"])
	return added


## The echo an ancestor passes on: attuned first, then strongest, then newest. {} if none.
static func pick_echo(echo_list: Array) -> Dictionary:
	var best: Dictionary = {}
	for x: Variant in echo_list:
		var e: Dictionary = x
		if best.is_empty():
			best = e
			continue
		var ka := [1 if bool(e.get("attuned", false)) else 0, float(e.get("strength", 1.0)), int(e.get("day", 0))]
		var kb := [1 if bool(best.get("attuned", false)) else 0, float(best.get("strength", 1.0)), int(best.get("day", 0))]
		for i in 3:
			if ka[i] != kb[i]:
				if ka[i] > kb[i]:
					best = e
				break
	return best


func _echo_types(p: Dictionary) -> Array:
	var out: Array = []
	for x: Dictionary in p.get("echoes", []):
		out.append(String(x.get("type", "")))
	return out


func _finish(e: Dictionary, choice: String, detail: Dictionary) -> void:
	var p: Dictionary = e["profile"]
	embers.erase(e)
	lineage.append({"name": String(p["name"]), "choice": choice, "day": int(e["born_day"]), "detail": detail})
	if lineage.size() > MAX_LINEAGE:
		lineage.pop_front()
	emit_event(&"ember_placed", {"choice": choice, "name": p["name"]})
	ember_placed.emit(choice, detail)


# --- ancestor stones -------------------------------------------------------------------

func is_ancestor_stone(stone_id: Variant) -> bool:
	return ancestor_stones.has(str(stone_id))


func stone_record(stone_id: Variant) -> Dictionary:
	return ancestor_stones.get(str(stone_id), {})


## Fractional power bonus of an ancestor stone (0.0 when none).
func power_bonus(stone_id: Variant) -> float:
	return float(stone_record(stone_id).get("power_bonus", 0.0))


## Multiplier for the stone's strength (1.0 + bonus).
func strength_multiplier(stone_id: Variant) -> float:
	return 1.0 + power_bonus(stone_id)


## Make the ancestor stones real inside a runestone_network.gd instance without touching
## it: radius grows, power and condition are lifted, and the stone dict is tagged
## (`ancestor`, `ancestor_bonus`, for map gold marks and UI). Idempotent; call it after
## loading a save and whenever a stone is created. Returns the number of stones touched.
func apply_to_network(net: Object) -> int:
	var pw: Dictionary = data().get("power", {})
	var touched := 0
	for s: Dictionary in net.stones:
		var key := str(s["id"])
		if not ancestor_stones.has(key):
			continue
		var b := float(ancestor_stones[key]["power_bonus"])
		if not s.has("base_radius"):
			s["base_radius"] = float(s["radius"])
		s["radius"] = float(s["base_radius"]) * (1.0 + b * float(pw.get("radius_per_power", 0.6)))
		s["power"] = minf(1.0, float(s["power"]) + b)
		s["condition"] = minf(1.0, float(s["condition"]) + b * float(pw.get("heal_condition_per_power", 0.5)))
		s["ancestor"] = String(ancestor_stones[key]["ancestor"])
		s["ancestor_bonus"] = b
		touched += 1
	return touched


# --- barks -----------------------------------------------------------------------------

const SITUATIONS := ["greet", "warn_pack", "warn_raid", "rumour", "proud", "dim"]

## Which bark fits the moment. Priority: raid, pack, dim stone, rumour, greeting.
static func situation_for(threats: Dictionary, condition: float = 1.0, has_rumour: bool = false) -> String:
	if bool(threats.get("raid", false)):
		return "warn_raid"
	if bool(threats.get("pack", false)):
		return "warn_pack"
	if condition < 0.4:
		return "dim"
	if has_rumour:
		return "rumour"
	return "greet"


## A line of the ancestor's voice for a stone. Deterministic per (stone, situation, salt).
## ctx: heir (full name), place, first (heir first name). Empty when the stone is not an
## ancestor stone.
func bark(stone_id: Variant, situation: String, ctx: Dictionary = {}, salt: int = 0) -> String:
	var rec := stone_record(stone_id)
	if rec.is_empty():
		return ""
	var barks: Dictionary = data().get("barks", {})
	var pool: Array = (barks.get(String(rec["archetype"]), {}) as Dictionary).get(situation, [])
	if pool.is_empty():
		pool = (data().get("generic_barks", {}) as Dictionary).get(situation, [])
	if pool.is_empty():
		return ""
	var idx: int = absi(hash([int(rec["barks_seed"]), situation, salt])) % pool.size()
	var heir := String(ctx.get("heir", "child"))
	var line := String(pool[idx])
	line = line.replace("{heir}", heir).replace("{first}", String(ctx.get("first", heir.get_slice(" ", 0)))) \
		.replace("{family}", String(rec["family"])).replace("{ancestor}", String(rec["ancestor"])) \
		.replace("{place}", String(ctx.get("place", rec["place"] if String(rec["place"]) != "" else "the road"))) \
		.replace("{role}", String(rec["role"])).replace("{years}", str(int(rec["years"]))) \
		.replace("{deed}", String(rec["deed"])).replace("{sphere}", String(rec["archetype"]))
	return line


## Text of the tap-a-stone biography card.
func card(stone_id: Variant) -> Dictionary:
	var rec := stone_record(stone_id)
	if rec.is_empty():
		return {}
	return {"title": "%s, %s" % [rec["ancestor"], rec["title"]],
		"lines": ["%d years as a %s." % [int(rec["years"]), String(rec["role"]).capitalize()] if String(rec["role"]) != "" else "A quiet life, well lived.",
			"%s." % rec["deed"], "Stone power +%d%%." % int(round(float(rec["power_bonus"]) * 100.0))]}


# --- heirlooms ------------------------------------------------------------------------

func heirloom(id: int) -> Dictionary:
	for h in heirlooms:
		if int(h["id"]) == id:
			return h
	return {}


## Stat multiplier of the heirloom (1.0 at level 1, grows per level).
func heirloom_power(id: int) -> float:
	var h := heirloom(id)
	if h.is_empty():
		return 1.0
	return 1.0 + float(int(h["level"]) - 1) * float(data().get("heirloom", {}).get("stat_per_level", 0.06))


## An inventory-style item dict for an heirloom (id = item id, plus heirloom fields).
func heirloom_item(id: int) -> Dictionary:
	var h := heirloom(id)
	if h.is_empty():
		return {}
	return {"id": String(h["item"]), "name": String(h["name"]), "qty": 1, "heirloom_id": int(h["id"]),
		"level": int(h["level"]), "stat": String(h["stat"]), "power": heirloom_power(id),
		"desc": "Once %s's. It remembers." % String(h["ancestor"])}


## A new generation has taken over (call after succession): every heirloom levels up once.
func on_succession() -> void:
	generation += 1
	var mx := int(data().get("heirloom", {}).get("max_level", 10))
	var gain := int(data().get("heirloom", {}).get("xp_per_generation", 1))
	for h in heirlooms:
		h["level"] = mini(mx, int(h["level"]) + gain)
	emit_event(&"generation", {"generation": generation})


# --- persistence -----------------------------------------------------------------------

func _save_state() -> Dictionary:
	return {"embers": embers.duplicate(true), "stones": ancestor_stones.duplicate(true),
		"heirlooms": heirlooms.duplicate(true), "lineage": lineage.duplicate(true),
		"generation": generation, "next_id": _next_id}


func _load_state(d: Dictionary) -> void:
	embers.clear()
	for e: Dictionary in d.get("embers", []):
		embers.append(e.duplicate(true))
	ancestor_stones = (d.get("stones", {}) as Dictionary).duplicate(true)
	heirlooms.clear()
	for h: Dictionary in d.get("heirlooms", []):
		var hh := h.duplicate(true)
		hh["id"] = int(hh["id"])   # JSON gives floats
		hh["level"] = int(hh["level"])
		hh["xp"] = int(hh.get("xp", 0))
		hh["gen"] = int(hh.get("gen", 0))
		heirlooms.append(hh)
	lineage.clear()
	for l: Dictionary in d.get("lineage", []):
		lineage.append(l.duplicate(true))
	generation = int(d.get("generation", 0))
	_next_id = int(d.get("next_id", 1))
	# JSON turns every number into a float: put the integer fields back so digests match.
	for e in embers:
		e["id"] = int(e["id"])
		e["born_day"] = int(e["born_day"])
		var p: Dictionary = e["profile"]
		p["age"] = int(p["age"])
		p["years"] = int(p["years"])
		for x: Dictionary in p.get("echoes", []):
			x["day"] = int(x.get("day", 0))
	for k: String in ancestor_stones:
		var r: Dictionary = ancestor_stones[k]
		r["barks_seed"] = int(r["barks_seed"])
		r["years"] = int(r["years"])
		r["day"] = int(r["day"])
		r["gen"] = int(r["gen"])
	for l in lineage:
		l["day"] = int(l["day"])
		var det: Dictionary = l["detail"]
		if det.has("heirloom"):
			det["heirloom"] = int(det["heirloom"])


func summary() -> String:
	return "%s embers=%d stones=%d heirlooms=%d gen=%d" % [super.summary(), embers.size(),
		ancestor_stones.size(), heirlooms.size(), generation]
