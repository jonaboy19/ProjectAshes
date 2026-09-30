extends GdUnitTestSuite
## Death costs (Life.apply_death_penalty), Quality overrides from the settings rows, and a full
## New Game reset (Life.reset: Game, WorldSim, Life systems, realm).

const SS := preload("res://scripts/ui/frontend/settings_store.gd")


func test_death_penalty_takes_gold_and_adds_a_minor_injury() -> void:
	var gold_before := Game.gold
	var inj_before: Dictionary = Life.injuries.serialize().duplicate(true)
	Game.gold = 200
	var r: Dictionary = Life.apply_death_penalty()
	assert_int(int(r["gold_lost"])).is_equal(20)
	assert_int(Game.gold).is_equal(180)
	assert_bool(Life.injuries.has(String(r["injury"]))).is_true()
	assert_str(String(r["text"])).contains("20 gold")
	Game.gold = gold_before
	Life.injuries.deserialize(inj_before)


func test_quality_overrides_change_only_their_group() -> void:
	var old: Dictionary = Quality.overrides.duplicate()
	Quality.set_overrides(-1, -1, -1, -1)
	var base_shadow: Variant = Quality.value("shadow")
	var base_radius: Variant = Quality.value("view_radius")
	Quality.set_overrides(0, 3, 0, 3)
	assert_int(int(Quality.value("view_radius"))).is_equal(Quality.TIERS[0]["view_radius"])
	assert_int(int(Quality.value("shadow"))).is_equal(Quality.TIERS[3]["shadow"])
	assert_float(float(Quality.value("tex_bias"))).is_equal(float(Quality.TIERS[0]["tex_bias"]))
	assert_bool(bool(Quality.value("glow"))).is_true()
	assert_int(Quality.view_radius).is_equal(Quality.TIERS[0]["view_radius"])
	Quality.set_overrides(-1, -1, -1, -1)
	assert_that(Quality.value("shadow")).is_equal(base_shadow)
	assert_that(Quality.value("view_radius")).is_equal(base_radius)
	Quality.set_overrides(old["view"], old["shadows"], old["textures"], old["effects"])


func test_level_rows_read_old_saves_as_auto() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "view_distance", 3)
	assert_array(SS.levels_from_config(cf)).is_equal([-1, -1, -1, -1])
	cf.set_value("display", "levels_v2", true)
	assert_array(SS.levels_from_config(cf)).is_equal([2, -1, -1, -1])


func test_new_game_reset_returns_to_a_fresh_state() -> void:
	var fresh_age := Life.age()
	Game.gold = 999
	Game.rank = 3
	WorldSim.day = 40
	WorldSim.job[5] = 3
	Life.appearance = {"sex": "female"}
	Life.tendencies.nudge_many({"martial": 0.5})
	Life.life_path.set_flag("test_flag_x")
	Life.injuries.add("deep_cut", WorldSim.day)
	Life.reset()
	assert_int(Game.gold).is_equal(40)
	assert_int(Game.rank).is_equal(0)
	assert_int(WorldSim.day).is_equal(1)
	assert_float(WorldSim.time_of_day).is_equal(8.0)
	assert_dict(Life.appearance).is_empty()
	assert_int(Life.injuries.active.size()).is_equal(0)
	assert_bool(Life.life_path.flags.has("test_flag_x")).is_false()
	assert_int(Life.age()).is_equal(fresh_age)
	assert_int(Life.inventory.get_items().size()).is_greater(0)
	assert_object(Life.realm).is_not_null()
