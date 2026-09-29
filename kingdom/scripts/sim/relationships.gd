extends RefCounted
## What people think of the player, and how the player stands with factions.
##
## Per-NPC opinion (-100..100) is a base value plus a stack of modifiers, in the
## spirit of Crusader Kings opinion modifiers: "Helped with chores +10 (fades over
## 30 days)", "Insulted -15". A modifier with a fade fades linearly to nothing and
## is dropped; fade 0 means it lasts until removed. The NPC's faction standing adds
## a derived, unstored modifier ("Ashford thinks well of you +4").
##
## Tiers (by opinion and familiarity): stranger, acquaintance, friend,
## close_friend, rival, enemy. Parents carry a bond: their opinion never drops
## below PARENT_FLOOR, so a parent can be disappointed but never an enemy.
##
## Gifts: each NPC loves, likes and dislikes items, derived from their career and
## culture (gift_prefs). One gift a day counts; the same item again within a week
## counts half. What an NPC thought of an item is remembered, so menus can say so.
##
## Pure data (serialisable), no scene tree or autoloads. Time is in game days as a
## float (WorldSim.day + WorldSim.time_of_day / 24.0).
##
## Usage:
##   const Relationships := preload("res://scripts/sim/relationships.gd")
##   var rel := Relationships.new()
##   rel.ensure("p42", {"name": "Edda Brook", "role": "farmer", "culture": "caldric", "faction": "ashford"})
##   rel.add_modifier("p42", "chores", "Helped with chores", 10, now, 30.0)
##   rel.opinion("p42", now); rel.tier("p42", now)
##   rel.change_rep("adventurer_guild", 5)
##   var r := rel.give_gift("p42", "cheese", now)   # {delta, reaction, text}

const TIERS := ["stranger", "acquaintance", "friend", "close_friend", "rival", "enemy"]
const TIER_NAMES := {"stranger": "Stranger", "acquaintance": "Acquaintance", "friend": "Friend",
	"close_friend": "Close friend", "rival": "Rival", "enemy": "Enemy"}
## Opinion thresholds.
const FRIEND_AT := 30
const CLOSE_FRIEND_AT := 65
const RIVAL_AT := -25
const ENEMY_AT := -60
## Conversations before a stranger becomes an acquaintance (any positive opinion
## also counts once you've met).
const MEET_TALKS := 1
const PARENT_FLOOR := 0
const GIFT_REPEAT_DAYS := 7.0
## Conversation topic memory is deliberately small and expires by game day.
const TOPIC_TTL_DAYS := 30.0
const TOPIC_MAX_NPCS := 128
const TOPIC_MAX_PER_NPC := 8
const TOPIC_MAX_TOTAL := 512
const TOPIC_MAX_NPC_ID := 128
const TOPIC_MAX_TEXT := 160
const TOPIC_MAX_SOURCE := 160

## Factions: id -> [display name, starting reputation]. Sects are added from data
## (add_faction / add_sects).
const FACTIONS := {
	"ashford": ["Ashford", 10.0],
	"adventurer_guild": ["Adventurer Guild", 0.0],
	"crown_caldrenn": ["Crown of Caldrenn", 0.0],
	"mossfang": ["Mossfang Goblins", -45.0],
	"tuskridge": ["Tuskridge Orcs", -5.0],
}
const STANDINGS := [[-75.0, "Hated"], [-40.0, "Hostile"], [-10.0, "Unfriendly"], [10.0, "Neutral"],
	[40.0, "Friendly"], [75.0, "Honoured"], [INF, "Revered"]]

## Gift tables. Item ids are GLoot prototype ids (data/items.json and
## scripts/sim/gathering_items.gd).
const CAREER_GIFTS := {
	"farmer": {"loves": ["cheese"], "likes": ["bread", "firewood", "stew"], "dislikes": ["wolf_meat"]},
	"blacksmith": {"loves": ["firewood"], "likes": ["stew", "pork", "venison"], "dislikes": ["wild_berries"]},
	"merchant": {"loves": ["fox_pelt"], "likes": ["wolf_pelt", "deer_hide", "boar_tusk"], "dislikes": ["mushroom"]},
	"guard": {"loves": ["stew"], "likes": ["bandage", "bread", "venison"], "dislikes": ["wild_berries"]},
	"laborer": {"loves": ["stew"], "likes": ["bread", "apple", "cheese"], "dislikes": ["healing_herb"]},
	"woodcutter": {"loves": ["pork"], "likes": ["stew", "bread"], "dislikes": ["firewood"]},
	"healer": {"loves": ["healing_herb"], "likes": ["mushroom", "wild_berries", "bandage"], "dislikes": ["wolf_meat", "boar_tusk"]},
	"innkeeper": {"loves": ["venison"], "likes": ["trout", "pike", "mushroom", "apple"], "dislikes": ["wolf_pelt"]},
	"trader": {"loves": ["fox_pelt"], "likes": ["wolf_pelt", "deer_hide"], "dislikes": ["apple"]},
	"receptionist": {"loves": ["emberfin"], "likes": ["apple", "wild_berries", "cheese"], "dislikes": ["wolf_meat"]},
	"hunter": {"loves": ["boar_tusk"], "likes": ["bandage", "wolf_pelt"], "dislikes": ["apple"]},
	"child": {"loves": ["wild_berries", "apple"], "likes": ["bread", "cheese"], "dislikes": ["healing_herb", "firewood"]},
	"mother": {"loves": ["wild_berries", "healing_herb"], "likes": ["apple", "trout", "cheese"], "dislikes": ["wolf_meat"]},
	"father": {"loves": ["venison", "fox_pelt"], "likes": ["firewood", "trout", "boar_tusk"], "dislikes": []},
}
const CULTURE_GIFTS := {
	"caldric": {"loves": [], "likes": ["bread", "cheese", "trout", "apple"], "dislikes": []},
	"urrokai": {"loves": ["pork", "boar_tusk"], "likes": ["wolf_meat", "venison"], "dislikes": ["apple", "wild_berries"]},
	"veyl": {"loves": ["wild_berries"], "likes": ["mushroom", "healing_herb"], "dislikes": ["wolf_pelt", "fox_pelt", "deer_hide"]},
	"durrow": {"loves": ["mushroom"], "likes": ["pork", "bread"], "dislikes": ["trout"]},
	"seirune": {"loves": ["emberfin"], "likes": ["perch", "trout", "pike"], "dislikes": ["cheese"]},
	"ongur": {"loves": ["cheese"], "likes": ["venison", "pork"], "dislikes": ["perch"]},
	"solenne": {"loves": ["bread"], "likes": ["wild_berries", "apple"], "dislikes": ["wolf_meat"]},
	"shenlu": {"loves": ["healing_herb"], "likes": ["pork", "mushroom"], "dislikes": ["wolf_meat"]},
}
const GIFT_VALUE := {"loves": 12, "likes": 6, "neutral": 2, "dislikes": -8}
const GIFT_FADE := 20.0

## npc id -> {name, role, culture, faction, bond, base, mods: [{id, label, value, day, fade}],
##           talks, last_talk, gifts: {item: last_day}, last_gift, known: {item: reaction}}
var npcs: Dictionary = {}
## faction id -> reputation (-100..100)
var reputation: Dictionary = {}
## faction id -> display name
var faction_names: Dictionary = {}
## npc id -> [{topic, day, source_ref, count}]. Optional save section.
var topic_memory: Dictionary = {}


func _init() -> void:
	for id: String in FACTIONS:
		add_faction(id, FACTIONS[id][0], FACTIONS[id][1])


# --- NPCs -----------------------------------------------------------------------

## The NPC's record, created on first use. `info` fills name/role/culture/faction
## (only fields given are updated; existing opinion is kept).
func ensure(npc: String, info := {}) -> Dictionary:
	var e: Dictionary = npcs.get(npc, {})
	if e.is_empty():
		e = {"name": "", "role": "", "culture": "", "faction": "", "bond": "", "base": 0.0,
			"mods": [], "talks": 0, "last_talk": -999.0, "gifts": {}, "last_gift": -999.0, "known": {}}
		npcs[npc] = e
	for k: String in ["name", "role", "culture", "faction"]:
		if info.has(k) and String(info[k]) != "":
			e[k] = String(info[k])
	if info.has("base"):
		e["base"] = float(info["base"])
	return e


func has_npc(npc: String) -> bool:
	return npcs.has(npc)


## Marks `npc` as family ("mother", "father", ...). `base` is their standing
## affection (e.g. RALifePath bond 0..100 mapped straight across).
func set_bond(npc: String, role: String, base := 60.0) -> void:
	var e := ensure(npc)
	e["bond"] = role
	e["base"] = clampf(base, PARENT_FLOOR, 100.0)
	e["talks"] = maxi(int(e["talks"]), MEET_TALKS)


func bond(npc: String) -> String:
	return String(npcs.get(npc, {}).get("bond", ""))


## Adds (or refreshes) a modifier. The same id replaces the old one unless
## max_stacks > 1, in which case up to max_stacks copies stack.
func add_modifier(npc: String, id: String, label: String, value: float, now: float, fade_days := 0.0, max_stacks := 1) -> void:
	var e := ensure(npc)
	var mods: Array = e["mods"]
	var same := mods.filter(func(m: Dictionary) -> bool: return m["id"] == id)
	if same.size() >= maxi(1, max_stacks):
		mods.erase(same[0])      # the oldest makes room
	mods.append({"id": id, "label": label, "value": value, "day": now, "fade": maxf(0.0, fade_days)})


func remove_modifier(npc: String, id: String) -> void:
	if not npcs.has(npc):
		return
	var mods: Array = npcs[npc]["mods"]
	npcs[npc]["mods"] = mods.filter(func(m: Dictionary) -> bool: return m["id"] != id)


func has_modifier(npc: String, id: String, now: float) -> bool:
	for m: Dictionary in npcs.get(npc, {}).get("mods", []):
		if m["id"] == id and modifier_value(m, now) != 0.0:
			return true
	return false


## Day the newest modifier with this id was added, or -999 if there is none.
func modifier_day(npc: String, id: String) -> float:
	var best := -999.0
	for m: Dictionary in npcs.get(npc, {}).get("mods", []):
		if m["id"] == id:
			best = maxf(best, float(m["day"]))
	return best


## Current strength of one modifier (linear fade; 0 once expired).
static func modifier_value(m: Dictionary, now: float) -> float:
	var fade := float(m["fade"])
	var v := float(m["value"])
	if fade <= 0.0:
		return v
	var t := (now - float(m["day"])) / fade
	if t >= 1.0:
		return 0.0
	return v * (1.0 - maxf(t, 0.0))


## Derived (unstored) modifier from the NPC's faction standing: a fifth of it.
func faction_modifier(npc: String) -> float:
	var f := String(npcs.get(npc, {}).get("faction", ""))
	if f == "" or not reputation.has(f):
		return 0.0
	return float(reputation[f]) / 5.0


func opinion_exact(npc: String, now: float) -> float:
	if not npcs.has(npc):
		return 0.0
	var e: Dictionary = npcs[npc]
	var v := float(e["base"]) + faction_modifier(npc)
	for m: Dictionary in e["mods"]:
		v += modifier_value(m, now)
	var lo := float(PARENT_FLOOR) if String(e["bond"]) != "" else -100.0
	return clampf(v, lo, 100.0)


func opinion(npc: String, now: float) -> int:
	return int(round(opinion_exact(npc, now)))


## [[label, value]] of everything behind an opinion, biggest first.
func breakdown(npc: String, now: float) -> Array:
	var out: Array = []
	if not npcs.has(npc):
		return out
	var e: Dictionary = npcs[npc]
	if absf(float(e["base"])) >= 0.5:
		out.append([("Family (%s)" % e["bond"]) if String(e["bond"]) != "" else "First impression", int(round(float(e["base"])))])
	var fm := faction_modifier(npc)
	if absf(fm) >= 0.5:
		out.append(["Your standing with %s" % faction_name(String(e["faction"])), int(round(fm))])
	for m: Dictionary in e["mods"]:
		var v := modifier_value(m, now)
		if absf(v) >= 0.5:
			out.append([String(m["label"]), int(round(v))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[1]) > absi(b[1]))
	return out


static func tier_for(op: float, talks: int) -> String:
	if op <= ENEMY_AT:
		return "enemy"
	if op <= RIVAL_AT:
		return "rival"
	if op >= CLOSE_FRIEND_AT:
		return "close_friend"
	if op >= FRIEND_AT:
		return "friend"
	if talks < MEET_TALKS and op < 10.0:
		return "stranger"
	return "acquaintance"


func tier(npc: String, now: float) -> String:
	return tier_for(opinion_exact(npc, now), int(npcs.get(npc, {}).get("talks", 0)))


## Tier rank for "at least" checks: enemy 0 .. close_friend 5.
static func tier_rank(t: String) -> int:
	return ["enemy", "rival", "stranger", "acquaintance", "friend", "close_friend"].find(t)


func tier_label(npc: String, now: float) -> String:
	var b := bond(npc)
	var t: String = TIER_NAMES[tier(npc, now)]
	return ("%s · %s" % [b.capitalize(), t]) if b != "" else t


## Counts a conversation. Returns true the first time today (callers give the
## small "chatted" opinion bump only then).
func note_talk(npc: String, now: float) -> bool:
	var e := ensure(npc)
	e["talks"] = int(e["talks"]) + 1
	var first_today := floorf(float(e["last_talk"])) < floorf(now)
	e["last_talk"] = now
	return first_today


func talked_today(npc: String, now: float) -> bool:
	return floorf(float(npcs.get(npc, {}).get("last_talk", -999.0))) == floorf(now)


## Remember a topic that was actually spoken in a conversation.
func remember_topic(npc: String, topic: String, now: float, source_ref := "") -> bool:
	if not _valid_topic_text(npc, TOPIC_MAX_NPC_ID) or not _valid_topic_text(topic, TOPIC_MAX_TEXT):
		return false
	if not is_finite(now) or (not source_ref.is_empty() and not _valid_topic_text(source_ref, TOPIC_MAX_SOURCE)):
		return false
	_prune_topic_memory(now)
	if not topic_memory.has(npc) and topic_memory.size() >= TOPIC_MAX_NPCS:
		_evict_oldest_topic_npc()
	var records: Array = topic_memory.get(npc, [])
	for i in range(records.size()):
		var record: Dictionary = records[i]
		if String(record["topic"]) == topic:
			record["day"] = now
			if not source_ref.is_empty():
				record["source_ref"] = source_ref
			record["count"] = mini(int(record.get("count", 1)) + 1, 999)
			records.remove_at(i)
			records.append(record)
			topic_memory[npc] = records
			return true
	if records.size() >= TOPIC_MAX_PER_NPC:
		records.pop_front()
	if _topic_record_count() >= TOPIC_MAX_TOTAL:
		_evict_oldest_topic_record()
	records.append({"topic": topic, "day": now, "source_ref": source_ref, "count": 1})
	topic_memory[npc] = records
	return true


## Returns the most recently remembered topic, or {} when none is current.
func last_topic(npc: String, now: float) -> Dictionary:
	if not is_finite(now):
		return {}
	_prune_topic_memory(now)
	var records: Array = topic_memory.get(npc, [])
	return (records.back() as Dictionary).duplicate() if not records.is_empty() else {}


## Returns recent conversation context, newest first, limited to eight records.
func topic_context(npc: String, now: float, limit := TOPIC_MAX_PER_NPC) -> Array:
	if not is_finite(now):
		return []
	_prune_topic_memory(now)
	var records: Array = topic_memory.get(npc, [])
	var out: Array = []
	var start := maxi(0, records.size() - clampi(limit, 0, TOPIC_MAX_PER_NPC))
	for i in range(records.size() - 1, start - 1, -1):
		out.append((records[i] as Dictionary).duplicate())
	return out


func _valid_topic_text(value: String, max_length: int) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= max_length


func _prune_topic_memory(now: float) -> void:
	for npc in topic_memory.keys():
		var records: Array = topic_memory[npc]
		records = records.filter(func(r: Dictionary) -> bool:
			return now >= float(r["day"]) and now - float(r["day"]) <= TOPIC_TTL_DAYS
		)
		if records.is_empty():
			topic_memory.erase(npc)
		else:
			topic_memory[npc] = records


func _topic_record_count() -> int:
	var total := 0
	for records: Array in topic_memory.values():
		total += records.size()
	return total


func _evict_oldest_topic_record() -> void:
	var oldest_npc := ""
	var oldest_index := -1
	var oldest_day := INF
	for npc in topic_memory:
		var records: Array = topic_memory[npc]
		for i in range(records.size()):
			if float(records[i]["day"]) < oldest_day:
				oldest_day = float(records[i]["day"])
				oldest_npc = String(npc)
				oldest_index = i
	if oldest_index >= 0:
		var records: Array = topic_memory[oldest_npc]
		records.remove_at(oldest_index)
		if records.is_empty():
			topic_memory.erase(oldest_npc)
		else:
			topic_memory[oldest_npc] = records


func _evict_oldest_topic_npc() -> void:
	var oldest_npc := ""
	var oldest_day := INF
	for npc in topic_memory:
		var records: Array = topic_memory[npc]
		for record: Dictionary in records:
			if float(record["day"]) < oldest_day:
				oldest_day = float(record["day"])
				oldest_npc = String(npc)
	if oldest_npc != "":
		topic_memory.erase(oldest_npc)


## Drops faded modifiers (call once a day).
func prune(now: float) -> void:
	for id: String in npcs:
		var mods: Array = npcs[id]["mods"]
		npcs[id]["mods"] = mods.filter(func(m: Dictionary) -> bool:
			return float(m["fade"]) <= 0.0 or now - float(m["day"]) < float(m["fade"]))
	if is_finite(now):
		_prune_topic_memory(now)


# --- factions -------------------------------------------------------------------

func add_faction(id: String, display: String, start := 0.0) -> void:
	faction_names[id] = display
	if not reputation.has(id):
		reputation[id] = start


## Adds every sect in `sects` (RAWorldLore.sects: id -> {name, ...}) as a faction.
func add_sects(sects: Dictionary) -> void:
	for id: String in sects:
		add_faction(id, String(sects[id].get("name", id)), 0.0)


func rep(faction: String) -> float:
	return float(reputation.get(faction, 0.0))


func change_rep(faction: String, delta: float) -> float:
	if not faction_names.has(faction):
		add_faction(faction, faction.capitalize())
	var v := clampf(rep(faction) + delta, -100.0, 100.0)
	reputation[faction] = v
	return v


func faction_name(faction: String) -> String:
	return String(faction_names.get(faction, faction.capitalize()))


static func standing_for(value: float) -> String:
	for s: Array in STANDINGS:
		if value < float(s[0]):
			return s[1]
	return "Revered"


func standing(faction: String) -> String:
	return standing_for(rep(faction))


# --- gifts ----------------------------------------------------------------------

## {loves, likes, dislikes} for a career/role and culture. Career wins over
## culture where they disagree.
static func gift_prefs(role: String, culture: String) -> Dictionary:
	var out := {"loves": [], "likes": [], "dislikes": []}
	var c: Dictionary = CULTURE_GIFTS.get(culture, {})
	var r: Dictionary = CAREER_GIFTS.get(role.to_lower(), {})
	for src: Dictionary in [c, r]:
		for k: String in out:
			for item: String in src.get(k, []):
				for other: String in out:
					(out[other] as Array).erase(item)
				(out[k] as Array).append(item)
	return out


static func reaction_to(item: String, prefs: Dictionary) -> String:
	for k: String in ["loves", "likes", "dislikes"]:
		if (prefs.get(k, []) as Array).has(item):
			return k
	return "neutral"


func prefs_of(npc: String) -> Dictionary:
	var e: Dictionary = npcs.get(npc, {})
	var role := String(e.get("bond", "")) if String(e.get("bond", "")) != "" else String(e.get("role", ""))
	return gift_prefs(role, String(e.get("culture", "")))


func gifted_today(npc: String, now: float) -> bool:
	return floorf(float(npcs.get(npc, {}).get("last_gift", -999.0))) == floorf(now)


## Gives `item` to `npc`: {ok, delta, reaction, text}. The caller removes the item
## from the inventory when ok.
func give_gift(npc: String, item: String, now: float) -> Dictionary:
	var e := ensure(npc)
	if gifted_today(npc, now):
		return {"ok": false, "delta": 0, "reaction": "", "text": "\"You've given me enough for one day.\""}
	var reaction := reaction_to(item, prefs_of(npc))
	var value := float(GIFT_VALUE[reaction])
	var gifts: Dictionary = e["gifts"]
	if gifts.has(item) and now - float(gifts[item]) < GIFT_REPEAT_DAYS and value > 0.0:
		value *= 0.5
	gifts[item] = now
	e["last_gift"] = now
	(e["known"] as Dictionary)[item] = reaction
	add_modifier(npc, "gift", "Gifts", value, now, GIFT_FADE, 5)
	var text: String = {"loves": "\"For me? Oh, I love this!\"", "likes": "\"How thoughtful. Thank you.\"",
		"neutral": "\"Oh. Thank you, I suppose.\"", "dislikes": "\"...What am I meant to do with this?\""}[reaction]
	return {"ok": true, "delta": int(round(value)), "reaction": reaction, "text": text}


## What the player has learned this NPC thinks of an item ("" if never given).
func known_reaction(npc: String, item: String) -> String:
	return String(npcs.get(npc, {}).get("known", {}).get(item, ""))


# --- save -----------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"npcs": npcs.duplicate(true), "reputation": reputation.duplicate(), "faction_names": faction_names.duplicate(),
		"topic_memory": topic_memory.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	# Validate this optional section as a unit; older saves simply omit it.
	var restored_topics: Dictionary = {}
	if d.has("topic_memory") and d["topic_memory"] is Dictionary and d["topic_memory"].size() <= TOPIC_MAX_NPCS:
		var candidate: Dictionary = {}
		var valid := true
		var total := 0
		var raw_topics: Dictionary = d["topic_memory"]
		for npc_variant in raw_topics:
			if not npc_variant is String or not _valid_topic_text(String(npc_variant), TOPIC_MAX_NPC_ID):
				valid = false
				break
			var raw_records: Variant = raw_topics[npc_variant]
			if not raw_records is Array or raw_records.size() > TOPIC_MAX_PER_NPC:
				valid = false
				break
			var parsed: Array = []
			var seen_topics: Dictionary = {}
			var previous_day := -INF
			for raw_record in raw_records:
				if not raw_record is Dictionary:
					valid = false
					break
				var rec: Dictionary = raw_record
				var topic: Variant = rec.get("topic", null)
				var source: Variant = rec.get("source_ref", "")
				var day: Variant = rec.get("day", null)
				var count: Variant = rec.get("count", 1)
				if not topic is String or not _valid_topic_text(String(topic), TOPIC_MAX_TEXT) \
				or not source is String or (not String(source).is_empty() and not _valid_topic_text(String(source), TOPIC_MAX_SOURCE)) \
				or not (day is float or day is int) or not is_finite(float(day)) \
				or not (count is int or count is float) or not is_finite(float(count)) \
				or float(count) != floorf(float(count)) or float(count) < 1.0 or float(count) > 999.0:
					valid = false
					break
				if seen_topics.has(String(topic)) or float(day) < previous_day:
					valid = false
					break
				seen_topics[String(topic)] = true
				previous_day = float(day)
				parsed.append({"topic": String(topic), "day": float(day), "source_ref": String(source), "count": int(count)})
			if not valid:
				break
			total += parsed.size()
			if total > TOPIC_MAX_TOTAL:
				valid = false
				break
			candidate[String(npc_variant)] = parsed
		if valid and candidate.size() <= TOPIC_MAX_NPCS and total <= TOPIC_MAX_TOTAL:
			restored_topics = candidate
	topic_memory = restored_topics
	npcs.clear()
	var src: Dictionary = d.get("npcs", {})
	for id: String in src:
		var e := ensure(String(id))
		var s: Dictionary = src[id]
		for k: String in ["name", "role", "culture", "faction", "bond"]:
			e[k] = String(s.get(k, ""))
		e["base"] = float(s.get("base", 0.0))
		e["talks"] = int(s.get("talks", 0))
		e["last_talk"] = float(s.get("last_talk", -999.0))
		e["last_gift"] = float(s.get("last_gift", -999.0))
		var mods: Array = []
		for m: Dictionary in s.get("mods", []):
			mods.append({"id": String(m["id"]), "label": String(m.get("label", "")), "value": float(m.get("value", 0.0)),
				"day": float(m.get("day", 0.0)), "fade": float(m.get("fade", 0.0))})
		e["mods"] = mods
		var gifts := {}
		var sg: Dictionary = s.get("gifts", {})
		for item: String in sg:
			gifts[item] = float(sg[item])
		e["gifts"] = gifts
		e["known"] = (s.get("known", {}) as Dictionary).duplicate()
	var names: Dictionary = d.get("faction_names", {})
	for id: String in names:
		faction_names[id] = String(names[id])
	var r: Dictionary = d.get("reputation", {})
	for id: String in r:
		reputation[id] = float(r[id])
