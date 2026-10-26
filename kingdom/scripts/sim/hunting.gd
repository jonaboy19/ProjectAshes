class_name Hunting
extends RefCounted
## Skinning and butchering rules for the hunting loop (READY_V1 C10). A kill leaves a carcass; the player skins it
## (CorpseLoot.attach_animal) and the haul scales with the hunting mastery (sim/mastery.gd). Pure and deterministic:
## the same carcass key and level always give the same haul, so tests and saves agree.
##
## Base haul is Gathering.HUNT_DROPS (venison, deer_hide, ...), plus EXTRA (antlers, wolf pelts). Skill changes it:
##   - an apprentice can ruin the hide (tear it) with ruin_chance(level), gone at RUIN_GONE_LEVEL;
##   - meat gets a bonus portion with bonus_chance(level), capped at BONUS_CAP.

const Gathering := preload("res://scripts/sim/gathering_items.gd")

## Extra salvage per kind: [[item, chance 0..1 at level 1, count], ...]. Chance rises with skill (see extra_chance).
const EXTRA := {
	"deer": [["antler", 0.15, 1]],
	"stag": [["antler", 0.9, 1]],
	"wolf": [["wolf_pelt", 0.85, 1], ["wolf_meat", 0.7, 1]],
	"boar": [],
	"bear": [["bear_pelt", 0.9, 1]],
}
## Kinds a player can skin (Gathering game plus the beasts a hunter takes).
const SKINNABLE := ["rabbit", "fox", "deer", "stag", "boar", "wolf", "bear"]
## Mastery xp for one skinned carcass (the kill itself already paid 1.0 through Life.record("hunted")).
const XP := {"rabbit": 0.4, "fox": 0.7, "deer": 1.0, "stag": 1.4, "boar": 1.2, "wolf": 1.2, "bear": 1.6}
## Items that are hides: these are what a clumsy hand tears.
const HIDES := ["deer_hide", "fox_pelt", "wolf_pelt", "bear_pelt"]
const RUIN_START := 0.35
const RUIN_PER_LEVEL := 0.02
const BONUS_PER_LEVEL := 0.012
const BONUS_CAP := 0.6
const EXTRA_PER_LEVEL := 0.01
const HOLD_SECONDS := 1.6


static func can_skin(kind: String) -> bool:
	return kind in SKINNABLE


## Chance a hide is torn at this hunting level (0 once level >= 1 + RUIN_START / RUIN_PER_LEVEL).
static func ruin_chance(level: int) -> float:
	return clampf(RUIN_START - float(maxi(level, 1) - 1) * RUIN_PER_LEVEL, 0.0, RUIN_START)


## Chance of one bonus portion of meat.
static func bonus_chance(level: int) -> float:
	return clampf(float(maxi(level, 1) - 1) * BONUS_PER_LEVEL, 0.0, BONUS_CAP)


static func extra_chance(base: float, level: int) -> float:
	return clampf(base + float(maxi(level, 1) - 1) * EXTRA_PER_LEVEL, 0.0, 1.0)


static func _base_drops(kind: String) -> Array:
	if kind == "wolf":
		return []     # a wolf gives only what EXTRA lists
	return Gathering.drops_for(kind)


## The haul for one carcass. Returns {items: [[id, qty], ...], ruined: [ids torn], xp: float}.
static func roll(kind: String, level: int, key: String) -> Dictionary:
	var out := {"items": [], "ruined": [], "xp": float(XP.get(kind, 0.5))}
	if not can_skin(kind):
		out["xp"] = 0.0
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["skin", kind, key])
	var tear := ruin_chance(level)
	var bonus := bonus_chance(level)
	var tally := {}
	for pair: Array in _base_drops(kind):
		var id := String(pair[0])
		var n := int(pair[1])
		if id in HIDES:
			if rng.randf() < tear:
				(out["ruined"] as Array).append(id)
				continue
		elif rng.randf() < bonus:
			n += 1
		tally[id] = int(tally.get(id, 0)) + n
	for e: Array in EXTRA.get(kind, []):
		var id := String(e[0])
		if rng.randf() < extra_chance(float(e[1]), level):
			if id in HIDES and rng.randf() < tear:
				(out["ruined"] as Array).append(id)
				continue
			tally[id] = int(tally.get(id, 0)) + int(e[2])
	for id: String in tally:
		(out["items"] as Array).append([id, int(tally[id])])
	return out


## Skins a carcass for `life` (anything with `mastery`, `give(id, n)` and `item_name(id)`: the Life autoload, or a
## test double). Gives the haul, credits hunting xp on `day`. Returns the roll plus {level_up: bool, text: String}.
static func skin(kind: String, key: String, life: Object, day: int) -> Dictionary:
	var m: Object = life.get("mastery")
	var level := int(m.call("level", "hunting")) if m != null else 1
	var res := roll(kind, level, key)
	var parts := PackedStringArray()
	for e: Array in res["items"]:
		life.call("give", String(e[0]), int(e[1]))
		parts.append("%s ×%d" % [life.call("item_name", String(e[0])), int(e[1])])
	var torn := PackedStringArray()
	for id: String in res["ruined"]:
		torn.append(String(life.call("item_name", id)).to_lower())
	res["level_up"] = false
	if m != null and float(res["xp"]) > 0.0:
		var g: Dictionary = m.call("gain", "hunting", float(res["xp"]), day)
		res["level_up"] = bool(g.get("level_up", false))
	var text := "You skin the %s: %s." % [kind, ", ".join(parts) if not parts.is_empty() else "nothing worth taking"]
	if not torn.is_empty():
		text += " The %s tore under your knife." % " and ".join(torn)
	if bool(res["level_up"]):
		text += " Your hunting improves."
	res["text"] = text
	return res
