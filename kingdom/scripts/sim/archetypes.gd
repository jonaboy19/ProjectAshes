class_name RAArchetypes
extends RefCounted
## Archetypes: who the character is becoming, chosen by what they do, not a
## menu. Each archetype has weights over action tags (from RALifePath.actions)
## and, optionally, over earned titles. Scores are weighted sums; affinities
## are each score's share of the total. The table is data: add types with
## register() or by editing DEFAULT_TABLE, no code changes needed.
##
## Pure data. Hooking it in (later):
##   var archetypes := RAArchetypes.new()
##   var top := archetypes.leading(life_path.actions, titles.earned, 3)
##   # -> [{id, name, score, affinity}, ...]; show on the character sheet, feed
##   #    NPC reactions ("You have the look of a hunter"), gate trainers/quests:
##   if archetypes.affinity(life_path.actions, "assassin") > 0.35: ...

## Score the villager archetype always has, so an idle life reads as "Villager"
## until something else clearly overtakes it.
const VILLAGER_BASELINE := 3.0

## id -> {name, desc, tags: {action_tag: weight}, titles: {title_id: bonus}}
## Negative weights pull a character away from an archetype.
const DEFAULT_TABLE := {
	"villager": {"name": "Villager", "desc": "An ordinary life, well lived.",
		"tags": {"helped_parent": 1.0, "chores": 1.0, "farmed": 0.3, "traded": 0.2}},
	"farmer": {"name": "Farmer", "desc": "Hands in the soil.",
		"tags": {"farmed": 1.5, "helped_farmer": 1.5, "tended_animals": 1.2, "gathered_herbs": 0.3}},
	"hunter": {"name": "Hunter", "desc": "Tracks, bows and patience.",
		"tags": {"hunted": 1.6, "tracked": 1.2, "explored_forest": 0.6, "trapped": 1.0, "sneaked": 0.3}},
	"assassin": {"name": "Assassin", "desc": "Unseen, unheard, unforgiving.",
		"tags": {"stole": 0.9, "sneaked": 1.4, "killed_unseen": 2.0, "poisoned": 1.5, "helped_farmer": -0.3},
		"titles": {"unseen": 4.0}},
	"thief": {"name": "Thief", "desc": "Quick fingers, quicker feet.",
		"tags": {"stole": 1.6, "sneaked": 0.8, "lockpicked": 1.4}},
	"merchant": {"name": "Merchant", "desc": "Everything has a price.",
		"tags": {"traded": 1.6, "haggled": 1.2, "sold": 0.8, "bought": 0.4, "hauled_goods": 0.8}},
	"scholar": {"name": "Scholar", "desc": "Ink, questions and old books.",
		"tags": {"studied": 1.6, "read": 1.2, "taught": 1.0, "explored_ruins": 0.6}},
	"martial_artist": {"name": "Martial Artist", "desc": "The body as a weapon, the mind as its edge.",
		"tags": {"trained_fist": 1.6, "meditated": 1.0, "sparred": 1.2, "trained_sword": 0.4}},
	"swordsman": {"name": "Swordsman", "desc": "Steel and form.",
		"tags": {"trained_sword": 1.6, "sparred": 0.8, "fought": 0.5}},
	"guard": {"name": "Guard / Soldier", "desc": "Holds the line for others.",
		"tags": {"guarded": 1.6, "patrolled": 1.2, "trained_sword": 0.6, "fought": 0.6, "stole": -0.6}},
	"adventurer": {"name": "Adventurer", "desc": "Always the next horizon.",
		"tags": {"explored": 1.4, "explored_forest": 0.9, "explored_ruins": 1.2, "killed_monster": 1.2, "commission": 1.4}},
	"healer": {"name": "Healer", "desc": "Mends what others break.",
		"tags": {"healed": 1.8, "gathered_herbs": 1.0, "prayed": 0.6, "studied": 0.2}},
	"craftsman": {"name": "Craftsman", "desc": "Makes things that last.",
		"tags": {"crafted": 1.5, "smithed": 1.6, "chopped_wood": 0.5, "mined": 0.8}},
	"fisher": {"name": "Fisher", "desc": "Reads the water.",
		"tags": {"fished": 1.8, "swam": 0.6, "sailed": 1.0}},
	"mystic": {"name": "Mystic", "desc": "Hears what the world whispers.",
		"tags": {"meditated": 0.8, "prayed": 1.0, "visited_shrine": 1.6, "communed": 2.0},
		"titles": {"spirit_touched": 6.0, "moon_child": 3.0}},
	"beast_tamer": {"name": "Beast Tamer", "desc": "Monsters answer to you.",
		"tags": {"tamed": 2.0, "fed_animal": 0.8, "tended_animals": 0.5, "named_monster": 3.0}},
	"bard": {"name": "Bard", "desc": "Songs open more doors than swords.",
		"tags": {"performed": 1.8, "told_story": 1.0, "traded": 0.2}},
}

## Live table (a deep copy of DEFAULT_TABLE plus anything registered).
var table: Dictionary = {}


func _init() -> void:
	table = DEFAULT_TABLE.duplicate(true)


## Adds or replaces an archetype.
func register(id: String, display: String, tags: Dictionary, titles := {}, desc := "") -> void:
	table[id] = {"name": display, "desc": desc, "tags": tags.duplicate(), "titles": titles.duplicate()}


func display_name(id: String) -> String:
	var a: Dictionary = table.get(id, {})
	return String(a.get("name", id.capitalize()))


## Raw scores: id -> float (never below 0). `titles` is the set of earned title
## ids, as Dictionary keys or an Array.
func score(actions: Dictionary, titles: Variant = {}) -> Dictionary:
	var out := {}
	for id: String in table:
		var a: Dictionary = table[id]
		var s := 0.0
		var tags: Dictionary = a.get("tags", {})
		for tag: String in tags:
			s += float(actions.get(tag, 0.0)) * float(tags[tag])
		var tb: Dictionary = a.get("titles", {})
		for t: String in tb:
			if _has_title(titles, t):
				s += float(tb[t])
		if id == "villager":
			s += VILLAGER_BASELINE
		out[id] = maxf(s, 0.0)
	return out


## Affinities: id -> share of the total score (0..1, sums to 1).
func affinities(actions: Dictionary, titles: Variant = {}) -> Dictionary:
	var scores := score(actions, titles)
	var total := _total(scores)
	var out := {}
	for id: String in scores:
		out[id] = float(scores[id]) / total if total > 0.0 else 0.0
	return out


func affinity(actions: Dictionary, id: String, titles: Variant = {}) -> float:
	return float(affinities(actions, titles).get(id, 0.0))


## The `count` highest-scoring archetypes as [{id, name, score, affinity}],
## best first. Archetypes with zero score are left out.
func leading(actions: Dictionary, titles: Variant = {}, count := 3) -> Array:
	var scores := score(actions, titles)
	var total := _total(scores)
	var rows := []
	for id: String in scores:
		var s: float = scores[id]
		if s > 0.0:
			rows.append({"id": id, "name": display_name(id), "score": s,
				"affinity": s / total if total > 0.0 else 0.0})
	rows.sort_custom(_by_score)
	return rows.slice(0, count)


## The single leading archetype id ("villager" for an empty life).
func primary(actions: Dictionary, titles: Variant = {}) -> String:
	var top := leading(actions, titles, 1)
	return String(top[0]["id"]) if not top.is_empty() else "villager"


static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = a["score"]
	var sb: float = b["score"]
	if sa != sb:
		return sa > sb
	return String(a["id"]) < String(b["id"])


static func _total(scores: Dictionary) -> float:
	var t := 0.0
	for id: String in scores:
		t += float(scores[id])
	return t


static func _has_title(titles: Variant, id: String) -> bool:
	if titles is Dictionary:
		return (titles as Dictionary).has(id)
	if titles is Array:
		return (titles as Array).has(id)
	return false
