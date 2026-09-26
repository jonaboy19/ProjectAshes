extends GdUnitTestSuite
## Frontier simulation: runestone coverage, decay/repair, ecology and threat.


func test_coverage_is_full_at_stone_and_zero_outside() -> void:
	var net := RARunestoneNetwork.new()
	net.add_stone(Vector2.ZERO, 100.0)
	assert_float(net.coverage(Vector2.ZERO)).is_equal_approx(1.0, 0.001)
	assert_float(net.coverage(Vector2(150, 0))).is_equal(0.0)
	assert_float(net.coverage(Vector2(80, 0))).is_between(0.0, 1.0)


func test_damage_weakens_and_maintenance_restores() -> void:
	var net := RARunestoneNetwork.new()
	var s := net.add_stone(Vector2.ZERO, 100.0)
	net.damage(s["id"], 0.6, 0.5)
	var weak := net.coverage(Vector2.ZERO)
	assert_float(weak).is_less(0.3)
	net.maintain(s["id"], 1, 0.5)
	assert_float(net.coverage(Vector2.ZERO)).is_greater(weak)


func test_neglect_decays_faster() -> void:
	var net := RARunestoneNetwork.new()
	var s := net.add_stone(Vector2.ZERO, 100.0)
	net.tick_day(1)
	var early_loss := 1.0 - float(s["condition"])
	s["condition"] = 1.0
	net.tick_day(40)
	assert_float(1.0 - float(s["condition"])).is_greater(early_loss)


func test_threat_is_lower_inside_protection() -> void:
	WorldGen.setup(1066)
	var net := RARunestoneNetwork.new()
	var eco := RAMonsterEcology.new()
	var p := Vector2(900, 900)
	eco.add_den("wolf", p + Vector2(40, 0), 10)
	var map := RAThreatMap.new(net, eco)
	var unprotected: float = map.evaluate(p)["total"]
	net.add_stone(p, 150.0)
	var protected: float = map.evaluate(p)["total"]
	assert_float(protected).is_less(unprotected)


func test_culling_a_den_to_zero_kills_it() -> void:
	var eco := RAMonsterEcology.new()
	var den := eco.add_den("wolf", Vector2.ZERO, 3)
	eco.cull(den["id"], 3)
	assert_bool(den["alive"]).is_false()


func test_event_modifier_raises_then_expires() -> void:
	WorldGen.setup(1066)
	var map := RAThreatMap.new(RARunestoneNetwork.new(), RAMonsterEcology.new())
	var p := Vector2(1200, -300)
	var base: float = map.evaluate(p)["total"]
	map.add_modifier("Patrol killed", p, 200.0, 12.0, 5)
	assert_float(map.evaluate(p)["total"]).is_greater(base)
	map.expire(6)
	assert_float(map.evaluate(p)["total"]).is_equal_approx(base, 0.01)
