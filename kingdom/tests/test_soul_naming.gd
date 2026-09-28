extends GdUnitTestSuite
## Soul Name ritual (scripts/sim/naming.gd): rare, tier-gated, permanently shares
## Soul Power, works on monsters and trusted people, bonds are limited by tier.

func _monster_target(species := "wolf", level := 5) -> Dictionary:
	return {"kind": "monster", "species": species, "level": level, "name": "Grix"}


func _person_target(trust := 60.0) -> Dictionary:
	return {"kind": "person", "id": 42, "name": "Edda Brook", "trust": trust,
		"tendencies": ["fire", "resolute"], "element": "fire"}


func test_ritual_refused_below_tier() -> void:
	var n := RANaming.new(1)
	var m := RAMagicules.new(100.0, 2.0, 1)
	var r := n.soul_name_ritual(m, 2, _monster_target(), "Kael", 1)
	assert_bool(r["ok"]).is_false()
	assert_str(r["text"]).contains("tier 3")
	assert_int(n.soul_bonds.size()).is_equal(0)
	assert_float(m.max_pool).is_equal(100.0)
	# Tier 3 is enough.
	var ok := n.soul_name_ritual(m, 3, _monster_target(), "Kael", 1)
	assert_bool(ok["ok"]).is_true()


func test_ritual_shares_soul_power_permanently() -> void:
	var n := RANaming.new(2)
	var m := RAMagicules.new(100.0, 2.0, 2)
	var before := m.max_pool
	var r := n.soul_name_ritual(m, 5, _monster_target(), "Storme", 1, {"at_shrine": true})
	assert_bool(r["ok"]).is_true()
	assert_float(r["shared"]).is_greater(0.0)
	assert_float(m.max_pool).is_equal(before - r["shared"])
	assert_float(n.soul_power_shared).is_equal(r["shared"])
	# It never comes back on its own: the pool stays shrunk after regen.
	m.regenerate(1000.0)
	assert_float(m.max_pool).is_equal(before - r["shared"])
	assert_float(m.current).is_equal(m.effective_max())


func test_bond_limit_grows_with_tier() -> void:
	assert_int(RANaming.bond_limit(1)).is_equal(0)
	assert_int(RANaming.bond_limit(3)).is_equal(1)
	assert_int(RANaming.bond_limit(4)).is_equal(1)
	assert_int(RANaming.bond_limit(5)).is_equal(2)
	assert_int(RANaming.bond_limit(11)).is_equal(6)
	var n := RANaming.new(3)
	var m := RAMagicules.new(500.0, 5.0, 3)
	var tier := 3   # limit 1
	var first := n.soul_name_ritual(m, tier, _monster_target("goblin"), "One", 1, {"at_shrine": true})
	assert_bool(first["ok"]).is_true()
	var second := n.soul_name_ritual(m, tier, _monster_target("kobold"), "Two", 1, {"at_shrine": true})
	assert_bool(second["ok"]).is_false()
	assert_str(second["text"]).contains("cannot hold another bond")
	assert_int(n.soul_bonds.size()).is_equal(1)


func test_person_target_needs_trust() -> void:
	var n := RANaming.new(4)
	var m := RAMagicules.new(200.0, 2.0, 4)
	var low := n.soul_name_ritual(m, 5, _person_target(10.0), "Bright", 1)
	assert_bool(low["ok"]).is_false()
	assert_str(low["text"]).contains("does not trust")
	assert_int(n.soul_bonds.size()).is_equal(0)
	var ok := n.soul_name_ritual(m, 5, _person_target(60.0), "Bright", 1, {"at_shrine": true})
	assert_bool(ok["ok"]).is_true()
	var bond: Dictionary = ok["bond"]
	assert_str(bond["kind"]).is_equal("person")
	assert_int(bond["target_id"]).is_equal(42)
	assert_array(bond["tendencies"]).contains(["fire", "resolute"])
	assert_str(bond["element"]).is_equal("fire")
	assert_str(bond["soul_name"]).is_equal("Bright")


func test_monster_target_evolves_into_a_soul_form() -> void:
	var n := RANaming.new(6)
	var m := RAMagicules.new(200.0, 2.0, 6)
	var r := n.soul_name_ritual(m, 5, _monster_target("wolf"), "Fenra", 1, {"at_shrine": true})
	assert_bool(r["ok"]).is_true()
	var bond: Dictionary = r["bond"]
	assert_str(bond["kind"]).is_equal("monster")
	assert_array(RANaming.SOUL_FORMS["wolf"]).contains([bond["form"]])
	assert_str(bond["soul_name"]).is_equal("Fenra")
	assert_int(bond["loyalty"]).is_equal(RANaming.BOND_LOYALTY)


func test_site_and_time_lower_risk() -> void:
	var risky := RANaming.ritual_risk(3, {})
	var safe := RANaming.ritual_risk(3, {"at_shrine": true})
	var festival := RANaming.ritual_risk(3, {"festival_night": true})
	assert_float(safe).is_less(risky)
	assert_float(festival).is_less(risky)
	# Higher tiers are safer still, and risk never goes negative.
	assert_float(RANaming.ritual_risk(11, {"at_shrine": true})).is_equal(0.0)


func test_deterministic_outcome_with_seed() -> void:
	var n1 := RANaming.new(99)
	var m1 := RAMagicules.new(100.0, 2.0, 99)
	var r1 := n1.soul_name_ritual(m1, 3, _monster_target("wolf"), "Same", 5)
	var n2 := RANaming.new(99)
	var m2 := RAMagicules.new(100.0, 2.0, 99)
	var r2 := n2.soul_name_ritual(m2, 3, _monster_target("wolf"), "Same", 5)
	assert_str(r1["bond"]["form"]).is_equal(r2["bond"]["form"])
	assert_int(r1["soul_fatigue_days"]).is_equal(r2["soul_fatigue_days"])
	assert_float(r1["risk"]).is_equal(r2["risk"])


func test_ritual_never_touches_the_ordinary_roster() -> void:
	var n := RANaming.new(7)
	var m := RAMagicules.new(500.0, 5.0, 7)
	n.name_monster(m, RAInjuries.new(), 10, "goblin", 2, "Rigo", "warrior", 1)
	n.soul_name_ritual(m, 5, _monster_target("wolf"), "Fenra", 1, {"at_shrine": true})
	assert_int(n.roster.size()).is_equal(1)
	assert_int(n.soul_bonds.size()).is_equal(1)


func test_empty_soul_name_is_refused() -> void:
	var n := RANaming.new(8)
	var m := RAMagicules.new(200.0, 2.0, 8)
	var r := n.soul_name_ritual(m, 5, _monster_target(), "   ", 1)
	assert_bool(r["ok"]).is_false()
	assert_int(n.soul_bonds.size()).is_equal(0)
	assert_float(m.max_pool).is_equal(200.0)


func test_soul_bond_roundtrip() -> void:
	var n := RANaming.new(9)
	var m := RAMagicules.new(200.0, 2.0, 9)
	n.soul_name_ritual(m, 5, _person_target(70.0), "Ash", 3, {"at_shrine": true})
	n.soul_name_ritual(m, 5, _monster_target("ogre"), "Grom", 3, {"festival_night": true})
	var d := RANaming.new()
	d.deserialize(JSON.parse_string(JSON.stringify(n.serialize())))
	assert_int(d.soul_bonds.size()).is_equal(2)
	assert_float(d.soul_power_shared).is_equal_approx(n.soul_power_shared, 0.001)
	assert_str(d.soul_bonds[0]["soul_name"]).is_equal("Ash")
	assert_str(d.soul_bonds[1]["form"]).is_equal(n.soul_bonds[1]["form"])
	assert_int(typeof(d.soul_bonds[0]["day"])).is_equal(TYPE_INT)
	# Bond helpers survive the round trip.
	var id := int(d.soul_bonds[0]["id"])
	assert_int(d.adjust_bond_loyalty(id, -10)).is_equal(RANaming.BOND_LOYALTY - 10)
	d.dismiss_bond(id)
	assert_int(d.soul_bonds.size()).is_equal(1)
