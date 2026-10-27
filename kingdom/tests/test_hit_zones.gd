extends GdUnitTestSuite
## HitZones: bone/height -> zone, damage multipliers, armour per slot, seeded injury rolls, resolver integration.

const Z := preload("res://scripts/combat/hit_zones.gd")
const R := preload("res://scripts/combat/hit_resolver.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")


func _rng(s := 11) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_bones_map_to_zones() -> void:
	assert_str(Z.zone_of_bone("Head")).is_equal("head")
	assert_str(Z.zone_of_bone("mixamorig:Neck")).is_equal("head")
	assert_str(Z.zone_of_bone("upperarm_l")).is_equal("arms")
	assert_str(Z.zone_of_bone("hand_r")).is_equal("arms")
	assert_str(Z.zone_of_bone("spine_02")).is_equal("torso")
	assert_str(Z.zone_of_bone("thigh_r")).is_equal("legs")
	assert_str(Z.zone_of_bone("foot_l")).is_equal("legs")
	assert_str(Z.zone_of_bone("unknown_bone")).is_equal("torso")


func test_height_maps_to_zones() -> void:
	assert_str(Z.zone_of_height(0.95)).is_equal("head")
	assert_str(Z.zone_of_height(0.6)).is_equal("torso")
	assert_str(Z.zone_of_height(0.6, 0.8)).is_equal("arms")
	assert_str(Z.zone_of_height(0.2)).is_equal("legs")


func test_attack_without_location_has_no_zone() -> void:
	assert_str(Z.zone_of_attack({"damage": 10})).is_equal("")
	assert_str(Z.zone_of_attack({"zone": "legs"})).is_equal("legs")
	assert_str(Z.zone_of_attack({"bone": "head"})).is_equal("head")


func test_multipliers_without_armour() -> void:
	var head := Z.apply({"bone": "head"}, 10, {}, _rng())
	var torso := Z.apply({"bone": "spine"}, 10, {}, _rng())
	var arm := Z.apply({"bone": "lowerarm_l"}, 10, {}, _rng())
	assert_int(head["damage"]).is_equal(20)
	assert_int(torso["damage"]).is_equal(10)
	assert_int(arm["damage"]).is_equal(7)
	assert_float(head["armour_reduction"]).is_equal(0.0)


func test_armour_reduces_only_its_zone() -> void:
	var armour := {"head": 4.0, "body": 5.0, "feet": 1.0}
	assert_float(Z.zone_armour("head", armour)).is_equal(4.0)
	assert_float(Z.zone_armour("torso", armour)).is_equal(5.0)
	assert_float(Z.zone_armour("arms", armour)).is_equal(2.5)      # half the body armour
	assert_float(Z.zone_armour("legs", armour)).is_equal_approx(0.6, 0.001)
	var bare := Z.apply({"bone": "head"}, 10, {}, _rng())
	var helmed := Z.apply({"bone": "head"}, 10, armour, _rng())
	assert_int(helmed["damage"]).is_less(bare["damage"])
	assert_int(helmed["damage"]).is_greater(0)


func test_armour_pierce_and_cap() -> void:
	assert_float(Z.zone_armour("head", {"head": 10.0}, 0.5)).is_equal(5.0)
	assert_float(Z.armour_reduction(100000.0)).is_equal(Z.MAX_REDUCTION)
	assert_float(Z.armour_reduction(0.0)).is_equal(0.0)


func test_minimum_damage_one() -> void:
	var r := Z.apply({"bone": "foot"}, 1, {"legs": 500.0}, _rng())
	assert_int(r["damage"]).is_equal(1)


func test_armour_by_slot_reads_equipment() -> void:
	var eq := Equipment.new()
	eq.equip("leather_jerkin")
	eq.equip("iron_helm")
	var a := Z.armour_by_slot(eq)
	assert_float(a["body"]).is_greater(0.0)
	assert_float(a["head"]).is_greater(0.0)
	assert_bool(a.has("legs")).is_false()
	# Worn-out armour protects half as much.
	eq.slots["head"]["durability"] = 0
	assert_float(Z.armour_by_slot(eq)["head"]).is_less(a["head"])


func test_small_hits_never_injure() -> void:
	for s in 50:
		assert_str(Z.roll_injury("legs", 3, 0.0, _rng(s))).is_equal("")


func test_injury_roll_is_seeded_and_zone_typed() -> void:
	var seen := {}
	for s in 400:
		var t := Z.roll_injury("legs", 20, 0.0, _rng(s))
		assert_str(Z.roll_injury("legs", 20, 0.0, _rng(s))).is_equal(t)   # replays
		seen[t] = true
	assert_bool(seen.has("bleeding")).is_true()
	assert_bool(seen.has("fracture_leg")).is_true()
	assert_bool(seen.has("fracture_arm")).is_false()
	for s in 400:
		assert_str(Z.roll_injury("head", 30, 0.0, _rng(s))).is_not_equal("fracture_leg")


func test_armour_lowers_injury_rate() -> void:
	var bare := 0
	var armoured := 0
	for s in 1000:
		if Z.roll_injury("torso", 20, 0.0, _rng(s)) != "":
			bare += 1
		if Z.roll_injury("torso", 20, 0.7, _rng(s)) != "":
			armoured += 1
	assert_int(armoured).is_less(bare)


func test_resolver_hit_carries_zone_data() -> void:
	var atk := {"damage": 10, "poise_damage": 5.0, "lane": 1, "parryable": true, "unblockable": false, "stat": 0.0,
		"bone": "head"}
	var def := {"guarding": false, "poise": 30.0, "evading": false, "from_front": true, "armour": {"head": 20.0}}
	var r := R.resolve(atk, def, _rng())
	assert_int(r["result"]).is_equal(R.Outcome.HIT)
	assert_str(r["zone"]).is_equal("head")
	assert_float(r["zone_mult"]).is_equal(2.0)
	assert_float(r["armour_reduction"]).is_greater(0.0)
	assert_int(r["damage"]).is_between(1, 19)
	assert_bool(r.has("injury")).is_true()


func test_resolver_without_zone_is_unchanged() -> void:
	var atk := {"damage": 10, "poise_damage": 5.0, "lane": 1, "parryable": true, "unblockable": false, "stat": 0.0}
	var r := R.resolve(atk, {"poise": 30.0}, _rng())
	assert_int(r["damage"]).is_equal(10)
	assert_bool(r.has("zone")).is_false()


func test_resolver_block_and_dodge_skip_zones() -> void:
	var atk := {"damage": 10, "poise_damage": 5.0, "lane": 1, "parryable": false, "unblockable": false, "stat": 0.0,
		"bone": "head"}
	var blocked := R.resolve(atk, {"guarding": true, "guard_age": 99.0, "guard_pool": 100.0, "poise": 30.0, "from_front": true}, _rng())
	assert_int(blocked["result"]).is_equal(R.Outcome.BLOCKED)
	assert_bool(blocked.has("zone")).is_false()
	var dodged := R.resolve(atk, {"evading": true}, _rng())
	assert_bool(dodged.has("zone")).is_false()
