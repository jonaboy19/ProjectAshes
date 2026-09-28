class_name RANaming
extends RefCounted
## Naming. Giving a monster a name binds it as a named subordinate: it evolves
## into a greater form of its species (goblin -> Hobgoblin, wolf -> Storm Wolf)
## and takes a class chosen from what its species can become (warrior, scout,
## mage, guardian, artisan, hunter, healer).
##
## A name is paid in magicules: cost grows with the target's level and its
## species' power. Naming with too few magicules (overdrawing) or naming
## something far above you is dangerous: the caster may temporarily lose levels,
## suffer Soul Fatigue (a temporary injury), or take a permanent injury such as
## a Fractured Core that stays until a healer treats it.
##
## Deterministic: all rolls come from a seeded RNG (serialized) so outcomes are
## testable and reproducible.
##
## INTEGRATION (for Life; not wired yet):
## - Life owns `var naming := RANaming.new()` next to `magicules` and `injuries`.
## - A "Name this creature" interaction on a defeated/tamed monster calls
##   `naming.preview(magicules, player_level, species, level)` to show cost and
##   risk, then `naming.name_monster(magicules, injuries, player_level, species,
##   level, given_name, klass, WorldSim.day)`; show r.text, apply r.damage to the
##   player, then `magicules.apply_effects(injuries.effects())`.
## - The player's effective level is `player_level - naming.level_penalty(day)`.
## - At hour 5: `naming.tick_day(WorldSim.day)` (level loss wears off, low-loyalty
##   subordinates may leave).
## - Save: snapshot["naming"] = naming.serialize().

## species -> {power, evolves_to, hint, classes (first = favoured)}
const SPECIES := {
	"goblin": {"power": 1.0, "evolves_to": "Hobgoblin",
		"hint": "Stands taller; with more names in the tribe, Hobgoblins may one day become Goblin Lords.",
		"classes": ["warrior", "artisan", "scout", "guardian"]},
	"wolf": {"power": 1.3, "evolves_to": "Storm Wolf",
		"hint": "Its fur crackles with static; a Storm Wolf pack-leader may grow into a Thunderfang.",
		"classes": ["scout", "hunter", "warrior"]},
	"kobold": {"power": 0.9, "evolves_to": "Greater Kobold",
		"hint": "Keen-nosed miners; Greater Kobolds learn to smell ore veins.",
		"classes": ["artisan", "scout", "guardian"]},
	"slime": {"power": 0.6, "evolves_to": "Spirit Slime",
		"hint": "Its core clears like glass; Spirit Slimes can absorb and mimic what they eat.",
		"classes": ["healer", "mage", "artisan"]},
	"lizardfolk": {"power": 1.6, "evolves_to": "Drakeblood Lizardfolk",
		"hint": "Scales harden to plates; Drakeblood warriors carry a trace of dragon fire.",
		"classes": ["warrior", "guardian", "hunter"]},
	"orc": {"power": 1.8, "evolves_to": "High Orc",
		"hint": "The hunger quiets; High Orcs build and keep their word.",
		"classes": ["warrior", "guardian", "artisan"]},
	"spider": {"power": 1.4, "evolves_to": "Veil Weaver",
		"hint": "Its silk shimmers; Veil Weavers spin threads that bind magicules.",
		"classes": ["scout", "artisan", "mage"]},
	"ogre": {"power": 2.5, "evolves_to": "Ashborn Ogre",
		"hint": "Horns darken to ember; Ashborn Ogres fight with martial discipline.",
		"classes": ["warrior", "guardian", "mage"]},
}

## class -> stat offsets granted with the name.
const CLASSES := {
	"warrior": {"attack": 0.25, "health": 0.15},
	"scout": {"speed": 0.2, "perception": 0.3},
	"mage": {"magicules": 0.4, "attack": 0.1},
	"guardian": {"health": 0.35, "defense": 0.2},
	"artisan": {"craft": 0.4},
	"hunter": {"attack": 0.15, "perception": 0.2},
	"healer": {"healing": 0.4, "magicules": 0.1},
}

const BASE_COST := 8.0
## risk = shortfall/max * SHORTFALL_RISK + levels_above * LEVEL_GAP_RISK
##        + (power-1) * POWER_RISK (only when above you) + SOUL_FATIGUE_RISK if already fatigued
const SHORTFALL_RISK := 1.5
const LEVEL_GAP_RISK := 0.06
const POWER_RISK := 0.08
const SOUL_FATIGUE_RISK := 0.2
const MAX_RISK := 0.95
## Permanent injury chance = (risk - INJURY_THRESHOLD) * INJURY_FACTOR
const INJURY_THRESHOLD := 0.25
const INJURY_FACTOR := 0.8
const BASE_LOYALTY := 75
const FAVOURED_LOYALTY := 10
const DESERT_BELOW := 25
const DESERT_CHANCE := 0.1

## Named subordinates: [{id, name, species, form, class, level, loyalty, named_day, bonus}]
var roster: Array[Dictionary] = []
## Temporary level losses of the caster: [{levels, until_day}]
var level_losses: Array[Dictionary] = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()

## --- Soul Name ritual (Rising Ashes pillar 4) -------------------------------------
## A rarer, deeper naming: the caster permanently shares a fraction of their max
## Soul Power (magicules.grow with a negative value) to forge a Soul Bond with a
## monster OR a trusted person. It requires a soul tier of at least MIN_SOUL_TIER
## (see scripts/sim/soul.gd's `tier()`), and is safer at a shrine or on a festival
## night. Concurrent bonds are limited by tier. Distinct from, and does not touch,
## the ordinary `name_monster` roster above.
##
## INTEGRATION (for Life; not wired yet):
## - `naming.soul_name_ritual(magicules, Soul.tier(), target, given_name, WorldSim.day,
##   {"at_shrine": true})` where target is {"kind": "monster", "species", "level",
##   "name"} or {"kind": "person", "id", "name", "trust", "tendencies", "element"}.
## - Save: already covered by `naming.serialize()` (soul_bonds are included).

## Soul tier required before a Soul Name can be spoken at all.
const MIN_SOUL_TIER := 3
## Concurrent Soul-Named bonds allowed, keyed by the lowest tier that grants the count.
const BOND_LIMITS_BY_TIER := [[3, 1], [5, 2], [7, 3], [9, 4], [11, 6]]
## Fraction of the caster's effective max Soul Power permanently shared per ritual.
const SHARE_FRACTION := 0.08
const SHARE_REGEN_FRACTION := 0.02
const PERSON_TRUST_MIN := 40.0
const BOND_LOYALTY := 90
## Ritual risk (of Soul Fatigue backlash): base, plus a penalty away from a proper
## site/time, minus a reduction per tier above the minimum.
const RITUAL_BASE_RISK := 0.08
const RITUAL_SITE_RISK := 0.22
const RITUAL_TIER_RISK_REDUCTION := 0.03
const RITUAL_MAX_RISK := 0.85

## species -> possible evolved Soul-Named forms (one is chosen deterministically
## from the seeded RNG so outcomes stay reproducible).
const SOUL_FORMS := {
	"wolf": ["Dire Wolf", "Ashwolf"],
	"goblin": ["Goblin Chief", "Ashmarked Goblin"],
	"kobold": ["Deep Kobold", "Ashvein Kobold"],
	"slime": ["Ember Slime", "Soulglass Slime"],
	"lizardfolk": ["Drakekin Lizardfolk", "Ashscale Lizardfolk"],
	"orc": ["Warlord Orc", "Ashbrand Orc"],
	"spider": ["Nightweb Spider", "Ashspun Spider"],
	"ogre": ["Ashborn Warlord", "Cinder Ogre"],
	"bear": ["Ironhide Bear", "Ashclaw Bear"],
	"troll": ["Ashhide Troll", "Deeproot Troll"],
}

## Soul Bonds forged by the ritual: [{id, kind: "monster"|"person", soul_name,
##   target_name, target_id, species, form/title, day, loyalty, tendencies,
##   element, level}]
var soul_bonds: Array[Dictionary] = []
## Total Soul Power permanently given away across all rituals (for display/lore).
var soul_power_shared := 0.0
var _next_bond_id := 1


func _init(seed_value := 8128) -> void:
	_rng.seed = seed_value


static func species_info(species: String) -> Dictionary:
	return SPECIES.get(species, {"power": 1.0, "evolves_to": "Named " + species.capitalize(),
		"hint": "It changes in ways nobody has recorded.", "classes": ["warrior", "scout", "guardian"]})


static func class_options(species: String) -> Array:
	return species_info(species)["classes"]


static func evolution_hint(species: String) -> String:
	var s := species_info(species)
	return "%s -> %s. %s" % [species.capitalize(), s["evolves_to"], s["hint"]]


## Magicule cost of naming a `species` of `level`.
static func cost(species: String, level: int) -> int:
	var lv := maxi(1, level)
	return int(round(BASE_COST * float(species_info(species)["power"]) * lv * (1.0 + lv * 0.1)))


## Risk (0..MAX_RISK) of naming with this pool at this caster level.
func risk(caster: RAMagicules, injuries: RAInjuries, caster_level: int, species: String, level: int) -> float:
	var c := float(cost(species, level))
	var shortfall := maxf(0.0, c - maxf(caster.current, 0.0))
	var gap := maxi(0, level - caster_level)
	var r := shortfall / caster.effective_max() * SHORTFALL_RISK + gap * LEVEL_GAP_RISK
	if gap > 0:
		r += maxf(0.0, float(species_info(species)["power"]) - 1.0) * POWER_RISK
	if injuries != null and injuries.has("soul_fatigue"):
		r += SOUL_FATIGUE_RISK
	return clampf(r, 0.0, MAX_RISK)


## What the player sees before naming: {cost, risk, possible, overdraw, form, classes}.
func preview(caster: RAMagicules, caster_level: int, species: String, level: int, injuries: RAInjuries = null) -> Dictionary:
	var c := cost(species, level)
	return {"cost": c, "risk": risk(caster, injuries, caster_level, species, level),
		"possible": float(c) <= caster.spendable(), "overdraw": maxf(0.0, float(c) - maxf(caster.current, 0.0)),
		"form": species_info(species)["evolves_to"], "classes": class_options(species)}


## Name a monster. Returns {ok, subordinate, cost, risk, overdraw, damage,
## soul_fatigue_days, levels_lost, level_loss_days, injuries: [type], text}.
func name_monster(caster: RAMagicules, injuries: RAInjuries, caster_level: int, species: String, level: int,
		given_name: String, klass: String, day: int) -> Dictionary:
	var out := {"ok": false, "subordinate": {}, "cost": cost(species, level), "risk": 0.0, "overdraw": 0.0,
		"damage": 0, "soul_fatigue_days": 0, "levels_lost": 0, "level_loss_days": 0, "injuries": [], "text": ""}
	if given_name.strip_edges() == "":
		out["text"] = "A name must be spoken."
		return out
	if not klass in class_options(species):
		out["text"] = "A %s cannot become a %s." % [species, klass]
		return out
	var c: int = out["cost"]
	if float(c) > caster.spendable():
		out["text"] = "The name will not hold: it needs %d magicules and you can give at most %d." % [
			c, int(floor(caster.spendable()))]
		return out
	var r := risk(caster, injuries, caster_level, species, level)
	out["risk"] = r
	var spent := caster.spend(float(c))
	out["overdraw"] = spent["overdraw"]
	out["damage"] = spent["damage"]
	var lines: Array[String] = []
	var info := species_info(species)
	var sub := {"id": _next_id, "name": given_name.strip_edges(), "species": species,
		"form": info["evolves_to"], "class": klass, "level": level,
		"loyalty": clampi(BASE_LOYALTY + (FAVOURED_LOYALTY if klass == class_options(species)[0] else 0), 0, 100),
		"named_day": day, "bonus": (CLASSES.get(klass, {}) as Dictionary).duplicate()}
	_next_id += 1
	roster.append(sub)
	out["ok"] = true
	out["subordinate"] = sub
	lines.append("%s the %s becomes %s, a %s %s." % [sub["name"], species, sub["name"], sub["form"], klass])
	# Consequences. Fixed roll order keeps outcomes reproducible for a seed.
	var roll_fatigue := _rng.randf()
	var roll_levels := _rng.randf()
	var roll_injury := _rng.randf()
	if float(spent["overdraw"]) > 0.0 or roll_fatigue < r:
		var days := 1 + int(ceil(r * 6.0))
		out["soul_fatigue_days"] = days
		if injuries != null:
			var existing := injuries.find("soul_fatigue")
			if existing.is_empty():
				injuries.add("soul_fatigue", day, days)
			else:
				existing["heals_on"] = maxi(int(existing["heals_on"]), day + days)
		lines.append("Soul Fatigue settles over you (%d days)." % days)
	if roll_levels < r:
		var lost := 1 + int(r * 4.0)
		var ldays := 3 + int(r * 10.0)
		level_losses.append({"levels": lost, "until_day": day + ldays})
		out["levels_lost"] = lost
		out["level_loss_days"] = ldays
		lines.append("The name takes part of you: -%d levels for %d days." % [lost, ldays])
	if roll_injury < (r - INJURY_THRESHOLD) * INJURY_FACTOR:
		out["injuries"].append("fractured_core")
		if injuries != null:
			injuries.add("fractured_core", day)
		lines.append("Your core fractures. Only a healer can mend it.")
	if int(spent["damage"]) > 0:
		lines.append("Overdrawing hurts you (-%d health)." % int(spent["damage"]))
	out["text"] = " ".join(lines)
	return out


## Levels the caster is currently missing.
func level_penalty(day: int) -> int:
	var n := 0
	for l in level_losses:
		if day < int(l["until_day"]):
			n += int(l["levels"])
	return n


func subordinate(id: int) -> Dictionary:
	for s in roster:
		if int(s["id"]) == id:
			return s
	return {}


func adjust_loyalty(id: int, delta: int) -> int:
	var s := subordinate(id)
	if s.is_empty():
		return -1
	s["loyalty"] = clampi(int(s["loyalty"]) + delta, 0, 100)
	return int(s["loyalty"])


func dismiss(id: int) -> void:
	var s := subordinate(id)
	if not s.is_empty():
		roster.erase(s)


## Level losses wear off; disloyal subordinates may leave.
## Returns events [{type: "levels_restored"|"deserted", ...}].
func tick_day(day: int) -> Array:
	var events := []
	var keep: Array[Dictionary] = []
	for l in level_losses:
		if day >= int(l["until_day"]):
			events.append({"type": "levels_restored", "levels": int(l["levels"]), "text": "Your lost levels return."})
		else:
			keep.append(l)
	level_losses = keep
	for s in roster.duplicate():
		if int(s["loyalty"]) < DESERT_BELOW and _rng.randf() < DESERT_CHANCE:
			roster.erase(s)
			events.append({"type": "deserted", "subordinate": s, "text": "%s has left you." % s["name"]})
	return events


## How many concurrent Soul Bonds a soul of this tier may hold.
static func bond_limit(caster_tier: int) -> int:
	var n := 0
	for pair in BOND_LIMITS_BY_TIER:
		if caster_tier >= int(pair[0]):
			n = int(pair[1])
	return n


## Risk (0..RITUAL_MAX_RISK) of Soul Fatigue backlash from the ritual.
static func ritual_risk(caster_tier: int, ctx := {}) -> float:
	var r := RITUAL_BASE_RISK
	if not (bool(ctx.get("at_shrine", false)) or bool(ctx.get("festival_night", false))):
		r += RITUAL_SITE_RISK
	r -= maxf(0.0, float(caster_tier - MIN_SOUL_TIER)) * RITUAL_TIER_RISK_REDUCTION
	return clampf(r, 0.0, RITUAL_MAX_RISK)


func soul_bond(id: int) -> Dictionary:
	for b in soul_bonds:
		if int(b["id"]) == id:
			return b
	return {}


func adjust_bond_loyalty(id: int, delta: int) -> int:
	var b := soul_bond(id)
	if b.is_empty():
		return -1
	b["loyalty"] = clampi(int(b["loyalty"]) + delta, 0, 100)
	return int(b["loyalty"])


func dismiss_bond(id: int) -> void:
	var b := soul_bond(id)
	if not b.is_empty():
		soul_bonds.erase(b)


func _soul_form(species: String) -> String:
	var forms: Array = SOUL_FORMS.get(species, ["Soul-Bound " + species.capitalize()])
	return String(forms[_rng.randi() % forms.size()])


## Speak a Soul Name over a monster or a trusted person, permanently sharing a
## fraction of the caster's Soul Power. `target`:
##   monster: {"kind": "monster", "species", "level", "name" (optional flavour name)}
##   person:  {"kind": "person", "id", "name", "trust", "tendencies" (Array),
##             "element" (String, optional)}
## `ctx`: {"at_shrine": bool, "festival_night": bool}. Returns {ok, text, bond,
## shared, risk, soul_fatigue_days}.
func soul_name_ritual(caster: RAMagicules, caster_tier: int, target: Dictionary, name: String, day: int,
		ctx := {}) -> Dictionary:
	var out := {"ok": false, "text": "", "bond": {}, "shared": 0.0, "risk": 0.0, "soul_fatigue_days": 0}
	if name.strip_edges() == "":
		out["text"] = "A Soul Name must be spoken."
		return out
	if caster_tier < MIN_SOUL_TIER:
		out["text"] = "Your soul is not yet strong enough to speak a Soul Name (tier %d needed)." % MIN_SOUL_TIER
		return out
	var limit := bond_limit(caster_tier)
	if soul_bonds.size() >= limit:
		out["text"] = "Your soul cannot hold another bond; it already carries %d of %d it can bear." % [
			soul_bonds.size(), limit]
		return out
	var kind := String(target.get("kind", "monster"))
	if kind == "person":
		var trust := float(target.get("trust", 0.0))
		if trust < PERSON_TRUST_MIN:
			out["text"] = "%s does not trust you enough for this." % String(target.get("name", "They"))
			return out
	var r := ritual_risk(caster_tier, ctx)
	out["risk"] = r
	var shared := caster.effective_max() * SHARE_FRACTION
	caster.grow(-shared, -shared * SHARE_REGEN_FRACTION)
	soul_power_shared += shared
	out["shared"] = shared
	var given := name.strip_edges()
	var bond: Dictionary
	if kind == "person":
		var pid := int(target.get("id", -1))
		var target_name := String(target.get("name", "Someone"))
		var tendencies: Array = (target.get("tendencies", []) as Array).duplicate()
		var element := String(target.get("element", ""))
		bond = {"id": _next_bond_id, "kind": "person", "target_id": pid, "target_name": target_name,
			"soul_name": given, "title": "the Soul-Named", "day": day, "loyalty": BOND_LOYALTY,
			"tendencies": tendencies, "element": element, "species": "", "form": "", "level": 0}
		bond["text"] = ("You speak %s's Soul Name: %s. Something in them deepens and steadies; they are known " +
			"from now on as %s, %s.") % [target_name, given, target_name, bond["title"]]
	else:
		var species := String(target.get("species", "wolf"))
		var target_name2 := String(target.get("name", given))
		var form := _soul_form(species)
		bond = {"id": _next_bond_id, "kind": "monster", "species": species, "target_name": target_name2,
			"soul_name": given, "form": form, "day": day, "loyalty": BOND_LOYALTY,
			"level": int(target.get("level", 1)), "title": "", "tendencies": [], "element": "", "target_id": -1}
		bond["text"] = "You speak the %s's Soul Name: %s. It changes before you: %s becomes %s, %s." % [
			species, given, target_name2, given, form]
	_next_bond_id += 1
	soul_bonds.append(bond)
	out["ok"] = true
	out["bond"] = bond
	var lines: Array[String] = [String(bond["text"])]
	if _rng.randf() < r:
		var days := 1 + int(ceil(r * 5.0))
		out["soul_fatigue_days"] = days
		lines.append("The ritual draws deep: Soul Fatigue settles over you (%d days)." % days)
	out["text"] = " ".join(lines)
	return out


func serialize() -> Dictionary:
	var r := []
	for s in roster:
		r.append(s.duplicate(true))
	var l := []
	for x in level_losses:
		l.append(x.duplicate())
	var b := []
	for x in soul_bonds:
		b.append(x.duplicate(true))
	return {"roster": r, "level_losses": l, "next_id": _next_id, "rng": str(_rng.state),
		"soul_bonds": b, "soul_power_shared": soul_power_shared, "next_bond_id": _next_bond_id}


func deserialize(d: Dictionary) -> void:
	roster.clear()
	for s: Dictionary in d.get("roster", []):
		roster.append({"id": int(s["id"]), "name": String(s["name"]), "species": String(s["species"]),
			"form": String(s["form"]), "class": String(s["class"]), "level": int(s["level"]),
			"loyalty": int(s["loyalty"]), "named_day": int(s["named_day"]),
			"bonus": (s.get("bonus", {}) as Dictionary).duplicate()})
	level_losses.clear()
	for l: Dictionary in d.get("level_losses", []):
		level_losses.append({"levels": int(l["levels"]), "until_day": int(l["until_day"])})
	_next_id = int(d.get("next_id", _next_id))
	soul_bonds.clear()
	for x: Dictionary in d.get("soul_bonds", []):
		soul_bonds.append({"id": int(x["id"]), "kind": String(x.get("kind", "monster")),
			"target_id": int(x.get("target_id", -1)), "target_name": String(x.get("target_name", "")),
			"soul_name": String(x.get("soul_name", "")), "title": String(x.get("title", "")),
			"day": int(x.get("day", 0)), "loyalty": int(x.get("loyalty", BOND_LOYALTY)),
			"tendencies": (x.get("tendencies", []) as Array).duplicate(),
			"element": String(x.get("element", "")), "species": String(x.get("species", "")),
			"form": String(x.get("form", "")), "level": int(x.get("level", 0))})
	soul_power_shared = float(d.get("soul_power_shared", 0.0))
	_next_bond_id = int(d.get("next_bond_id", _next_bond_id))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
