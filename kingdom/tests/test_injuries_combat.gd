extends GdUnitTestSuite
## Combat injuries in sim/injuries.gd: bleeding until bandaged, fractures cut speed or attack, healers, save round-trip.


func test_bleeding_drains_health_until_bandaged() -> void:
	var inj := RAInjuries.new()
	assert_float(inj.bleed_damage(1.0)).is_equal(0.0)
	inj.add("bleeding", 1)
	assert_bool(inj.is_bleeding()).is_true()
	assert_float(inj.bleed_damage(1.0)).is_equal(2.0)
	assert_float(inj.bleed_damage(3.0)).is_equal(6.0)
	inj.add("bleeding", 1)
	assert_float(inj.bleed_damage(1.0)).is_equal(4.0)
	assert_int(inj.bandage()).is_equal(2)
	assert_bool(inj.is_bleeding()).is_false()
	assert_float(inj.bleed_damage(5.0)).is_equal(0.0)


func test_bleeding_does_not_heal_by_itself() -> void:
	var inj := RAInjuries.new()
	inj.add("bleeding", 1)
	assert_array(inj.tick_day(400)).is_empty()
	assert_bool(inj.is_bleeding()).is_true()


func test_bandage_keeps_other_injuries() -> void:
	var inj := RAInjuries.new()
	inj.add("bleeding", 1)
	inj.add("fracture_leg", 1)
	inj.bandage()
	assert_bool(inj.has("fracture_leg")).is_true()
	assert_bool(inj.has("bleeding")).is_false()


func test_fractures_lower_speed_or_attack() -> void:
	var inj := RAInjuries.new()
	inj.add("fracture_leg", 1)
	assert_float(inj.effects()["speed"]).is_less(0.0)
	assert_bool(inj.effects().has("attack")).is_false()
	inj.add("fracture_arm", 1)
	assert_float(inj.effects()["attack"]).is_less(0.0)


func test_fractures_heal_naturally() -> void:
	var inj := RAInjuries.new()
	inj.add("fracture_arm", 10)
	assert_array(inj.tick_day(20)).is_empty()
	assert_int(inj.tick_day(30).size()).is_equal(1)
	assert_bool(inj.has("fracture_arm")).is_false()


func test_herbalist_treats_combat_injuries() -> void:
	var inj := RAInjuries.new()
	var b := inj.add("bleeding", 1)
	var f := inj.add("fracture_leg", 1)
	var r := inj.treat(int(b["uid"]), "herbalist", 50)
	assert_bool(r["ok"]).is_true()
	assert_bool(inj.treat(int(f["uid"]), "herbalist", 5)["ok"]).is_false()   # too poor
	assert_bool(inj.treat(int(f["uid"]), "herbalist", 100)["ok"]).is_true()
	assert_array(inj.active).is_empty()


func test_serialize_round_trip() -> void:
	var inj := RAInjuries.new()
	inj.add("bleeding", 3)
	inj.add("fracture_leg", 3)
	var copy := RAInjuries.new()
	copy.deserialize(inj.serialize())
	assert_float(copy.bleed_damage(1.0)).is_equal(2.0)
	assert_bool(copy.has("fracture_leg")).is_true()
	assert_dict(copy.serialize()).is_equal(inj.serialize())


func test_end_to_end_hit_to_injury() -> void:
	var HitZones := preload("res://scripts/combat/hit_zones.gd")
	var rng := RandomNumberGenerator.new()
	var inj := RAInjuries.new()
	for s in 300:
		rng.seed = s
		var z := HitZones.apply({"bone": "calf_l"}, 20, {}, rng)
		if z["injury"] != "":
			inj.add(String(z["injury"]), 1)
	assert_bool(inj.has("bleeding") or inj.has("fracture_leg")).is_true()
	assert_bool(inj.has("fracture_arm")).is_false()
