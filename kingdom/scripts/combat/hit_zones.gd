class_name HitZones
extends RefCounted
## Locational damage as pure data (WP-03). A hit bone or a hit height becomes a body zone, the zone gives a
## damage multiplier, the armour worn over it reduces the hit, and a seeded roll may produce an injury for
## sim/injuries.gd. No scene access, no randf(): the caller passes the seeded rng that HitResolver already uses.
##
## INTEGRATION: HitResolver.resolve() calls apply() when the attack carries "bone" or "hit_height"; the
## result then has zone, zone_mult, armour_reduction and injury. The caller applies the injury:
##   if r.injury != "": injuries.add(r.injury, WorldSim.day)
## and every hour: `hp -= injuries.bleed_damage(1.0)`.

const Equipment := preload("res://scripts/sim/equipment.gd")

enum Zone { HEAD, TORSO, ARMS, LEGS }
const NAMES := ["head", "torso", "arms", "legs"]

const DAMAGE_MULT := {"head": 2.0, "torso": 1.0, "arms": 0.7, "legs": 0.8}
## Equipment slots that cover each zone (a share of the worn armour value counts for every listed slot).
const ZONE_SLOTS := {"head": ["head"], "torso": ["body", "cloak"], "arms": ["hands", "body"], "legs": ["legs", "feet"]}
## Share of a covering slot's armour that counts (body covers the arms only partly; a cloak is thin).
const SLOT_SHARE := {"body": 1.0, "head": 1.0, "hands": 1.0, "legs": 1.0, "feet": 0.6, "cloak": 0.4}
const BODY_SHARE_ON_ARMS := 0.5
const ARMOUR_K := 40.0            # reduction = armour / (armour + K)
const MAX_REDUCTION := 0.8

## Bone name fragments, lower case, checked in order (UAL / Mixamo / Godot humanoid names).
const BONE_ZONES := [
	["head", "head"], ["neck", "head"], ["jaw", "head"],
	["upperarm", "arms"], ["upper_arm", "arms"], ["lowerarm", "arms"], ["forearm", "arms"], ["shoulder", "arms"],
	["clavicle", "arms"], ["hand", "arms"], ["finger", "arms"], ["thumb", "arms"], ["arm", "arms"],
	["thigh", "legs"], ["upleg", "legs"], ["calf", "legs"], ["shin", "legs"], ["foot", "legs"], ["toe", "legs"],
	["leg", "legs"], ["spine", "torso"], ["chest", "torso"], ["pelvis", "torso"], ["hips", "torso"], ["root", "torso"],
]
## hit_height as a fraction of body height (0 = soles, 1 = crown) when no bone is known.
const HEIGHT_HEAD := 0.82
const HEIGHT_TORSO := 0.5
## Arms are hit from the side: a lateral offset beyond this share of body half-width counts as arms.
const ARM_LATERAL := 0.55

## Injury table: zone -> [{type, chance (per landed hit before armour/severity scaling), min_damage}].
const INJURY_ROLLS := {
	"head": [{"type": "bleeding", "chance": 0.25, "min_damage": 6}],
	"torso": [{"type": "bleeding", "chance": 0.2, "min_damage": 8}],
	"arms": [{"type": "bleeding", "chance": 0.15, "min_damage": 6}, {"type": "fracture_arm", "chance": 0.12, "min_damage": 12}],
	"legs": [{"type": "bleeding", "chance": 0.15, "min_damage": 6}, {"type": "fracture_leg", "chance": 0.14, "min_damage": 12}],
}


static func zone_of_bone(bone: String) -> String:
	var b := bone.to_lower()
	for pair: Array in BONE_ZONES:
		if b.contains(String(pair[0])):
			return String(pair[1])
	return "torso"


## Zone from a normalised hit height (0..1) and optional lateral offset (-1..1 across the body).
static func zone_of_height(height: float, lateral := 0.0) -> String:
	if height >= HEIGHT_HEAD:
		return "head"
	if height >= HEIGHT_TORSO:
		return "arms" if absf(lateral) >= ARM_LATERAL else "torso"
	return "legs"


## Zone of an attack dictionary: "zone" wins, then "bone", then "hit_height". "" = no locational data.
static func zone_of_attack(attack: Dictionary) -> String:
	var z := String(attack.get("zone", ""))
	if NAMES.has(z):
		return z
	if attack.has("bone"):
		return zone_of_bone(String(attack["bone"]))
	if attack.has("hit_height"):
		return zone_of_height(float(attack["hit_height"]), float(attack.get("hit_lateral", 0.0)))
	return ""


## Armour value protecting a zone from `armour_by_slot` ({slot: armour}). Armour pierce (0..1) cuts it.
static func zone_armour(zone: String, armour_by_slot: Dictionary, pierce := 0.0) -> float:
	var total := 0.0
	for slot: String in ZONE_SLOTS.get(zone, []):
		var share: float = float(SLOT_SHARE.get(slot, 1.0))
		if zone == "arms" and slot == "body":
			share *= BODY_SHARE_ON_ARMS
		total += float(armour_by_slot.get(slot, 0.0)) * share
	return total * (1.0 - clampf(pierce, 0.0, 1.0))


static func armour_reduction(armour: float) -> float:
	if armour <= 0.0:
		return 0.0
	return minf(armour / (armour + ARMOUR_K), MAX_REDUCTION)


## Armour per slot for a sim/equipment.gd instance: {slot: armour} using each worn piece's quality and durability.
static func armour_by_slot(equipment: Object) -> Dictionary:
	var out := {}
	for slot: String in SLOT_SHARE:
		var e: Dictionary = equipment.equipped(slot)
		if e.is_empty():
			continue
		var st := Equipment.item_stats(String(e["id"]), int(e["quality"]), int(e["durability"]))
		out[slot] = float(st.get("armour", 0.0))
	return out


## Final damage and injury for one landed hit. attack: {damage, zone|bone|hit_height, armour_pierce?};
## defender_armour: {slot: armour}. Returns {zone, zone_mult, armour_reduction, damage, injury}.
## Draws from rng only when a zone is known, so unzoned fights replay exactly as before.
static func apply(attack: Dictionary, base_damage: int, defender_armour: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var zone := zone_of_attack(attack)
	if zone == "" or base_damage <= 0:
		return {"zone": zone, "zone_mult": 1.0, "armour_reduction": 0.0, "damage": base_damage, "injury": ""}
	var mult: float = float(DAMAGE_MULT[zone])
	var red := armour_reduction(zone_armour(zone, defender_armour, float(attack.get("armour_pierce", 0.0))))
	var dmg := maxi(1, int(round(float(base_damage) * mult * (1.0 - red))))
	return {"zone": zone, "zone_mult": mult, "armour_reduction": red, "damage": dmg,
		"injury": roll_injury(zone, dmg, red, rng)}


## At most one injury per hit. Armour lowers the chance by its reduction; a hit under min_damage never injures.
static func roll_injury(zone: String, damage: int, reduction: float, rng: RandomNumberGenerator) -> String:
	for row: Dictionary in INJURY_ROLLS.get(zone, []):
		if damage < int(row["min_damage"]):
			continue
		var chance := float(row["chance"]) * (1.0 - reduction) * (1.0 + float(damage - int(row["min_damage"])) * 0.03)
		if rng.randf() < minf(chance, 0.95):
			return String(row["type"])
	return ""
