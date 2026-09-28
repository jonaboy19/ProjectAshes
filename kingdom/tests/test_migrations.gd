extends GdUnitTestSuite
## Monster migration chains: an apex creature displaces weaker dens toward
## human land, wolves near a settlement take livestock, winter pushes wolves
## down at a lower threshold, Rift instability seeds corrupted dens near the
## Rift outpost, and an apex_hunt radiant quest appears once a migration is
## noticed. See docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Living world simulation".

const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")


func _no_coverage(_p: Vector2) -> float:
	return 0.0


func test_apex_displaces_a_weaker_den_toward_the_nearest_settlement() -> void:
	WorldGen.setup(3131)
	var eco := RAMonsterEcology.new(55)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var den_pos := home + Vector2(500.0, 0.0)
	var nearest: Vector2 = WorldGen.nearest_settlement(den_pos)["pos"]
	var den := eco.add_den("wolf", den_pos, 14)
	den["food"] = 0.6                                   # moderate hunger only
	eco.spawn_apex("troll", den_pos + Vector2(30.0, 0.0), 1)
	var before_dist := den_pos.distance_to(nearest)
	eco.tick_day(_no_coverage, 0.0, false)
	# The original den split off a child fleeing the apex.
	assert_int(eco.dens.size()).is_equal(3)     # wolf den + apex + migrated child
	var child: Dictionary = eco.dens[2]
	assert_str(child["species"]).is_equal("wolf")
	assert_float((child["pos"] as Vector2).distance_to(nearest)).is_less(before_dist)
	var events := eco.events_since(0)
	var reasons := events.filter(func(e: Dictionary) -> bool: return e["type"] == "displaced")
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]["reason"]).is_equal("apex")
	assert_int(eco.pending_apex_hunts().size()).is_equal(1)


func test_wolves_near_a_settlement_can_take_livestock() -> void:
	WorldGen.setup(3131)
	var eco := RAMonsterEcology.new(9)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	eco.add_den("wolf", home + Vector2(50.0, 0.0), 8)
	var took := false
	for d in 60:
		eco.tick_day(_no_coverage, 0.0, false)
		for e: Dictionary in eco.events_since(0):
			if e["type"] == "livestock_taken":
				took = true
	assert_bool(took).is_true()


func test_winter_pushes_wolves_down_at_a_lower_pressure_threshold() -> void:
	WorldGen.setup(3131)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var den_pos := home + Vector2(700.0, 300.0)

	var summer := RAMonsterEcology.new(20)
	var sd := summer.add_den("wolf", den_pos, 8)
	sd["food"] = 0.6
	summer.tick_day(_no_coverage, 0.0, false)
	assert_int(summer.dens.size()).is_equal(1)     # no migration: pressure below the normal threshold

	var winter := RAMonsterEcology.new(20)
	var wd := winter.add_den("wolf", den_pos, 8)
	wd["food"] = 0.6
	winter.tick_day(_no_coverage, 0.0, true)
	assert_int(winter.dens.size()).is_equal(2)     # winter cold was enough to push it out
	var events := winter.events_since(0)
	var winter_events := events.filter(func(e: Dictionary) -> bool: return e["type"] == "displaced" and e["reason"] == "winter")
	assert_int(winter_events.size()).is_equal(1)


func test_rift_instability_can_seed_a_corrupted_den_near_the_outpost() -> void:
	WorldGen.setup(3131)
	var outpost := Vector2.INF
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "rift_outpost":
			outpost = s["pos"]
			break
	assert_bool(outpost != Vector2.INF).override_failure_message("seed 3131 has no rift outpost; pick another seed").is_true()
	var eco := RAMonsterEcology.new(3)
	for d in 80:
		eco.tick_day(_no_coverage, 0.85, false)
	var spawn_events := eco.events_since(0).filter(func(e: Dictionary) -> bool: return e["type"] == "rift_den")
	assert_int(spawn_events.size()).is_greater(0)
	var corrupted := eco.dens.filter(func(den: Dictionary) -> bool: return den["species"] == "corrupted_wolf")
	assert_int(corrupted.size()).is_greater(0)
	# It's seeded near the outpost, however it may have wandered since.
	for e: Dictionary in spawn_events:
		assert_float((e["pos"] as Vector2).distance_to(outpost)).is_less(300.0)


func test_apex_hunt_quest_appears_once_a_migration_is_noticed() -> void:
	WorldGen.setup(3131)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var world := {"home": home, "dens": [], "sites": [], "places": {}}
	assert_bool(RadiantQuests.available_kinds(world).has("apex_hunt")).is_false()
	world["apex_hunts"] = [{"id": 7, "pos": home + Vector2(600.0, 0.0), "species": "troll",
		"displaced_pos": home + Vector2(300.0, 0.0)}]
	assert_bool(RadiantQuests.available_kinds(world).has("apex_hunt")).is_true()
	var found := false
	for d in 20:
		for q: Dictionary in RadiantQuests.generate(world, 4, d):
			if q["kind"] == "apex_hunt":
				found = true
				assert_int(int(q["stages"][1]["den_id"])).is_equal(7)
	assert_bool(found).is_true()


func test_ecology_state_round_trips_through_serialisation() -> void:
	WorldGen.setup(3131)
	var eco := RAMonsterEcology.new(42)
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	eco.add_den("wolf", home + Vector2(500.0, 0.0), 14)
	eco.spawn_apex("wyvern", home + Vector2(520.0, 0.0), 1)
	for d in 5:
		eco.tick_day(_no_coverage, 0.2, false)
	var state := eco.serialize_state()
	var json := JSON.stringify(state)
	var copy := RAMonsterEcology.new(1)
	copy.deserialize_state(JSON.parse_string(json))
	assert_int(copy.dens.size()).is_equal(eco.dens.size())
	assert_int(copy.events_since(0).size()).is_equal(eco.events_since(0).size())
	assert_int(copy.pending_apex_hunts().size()).is_equal(eco.pending_apex_hunts().size())
	assert_str(JSON.stringify(copy.serialize())).is_equal(JSON.stringify(eco.serialize()))
