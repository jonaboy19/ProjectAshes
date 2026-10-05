extends GdUnitTestSuite
## The stat table (data/combat/archetypes.json) reaches the real bodies: spawned goblin / troll / wolf /
## bandit / guard take HP (and poise, cooldown) from it, scaled by enemy level vs player level.

const Stats := preload("res://scripts/combat/combat_stats.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const SoldierScript := preload("res://scripts/army/soldier.gd")
const WolfScript := preload("res://scripts/actors/wolf.gd")


func test_table_has_every_archetype() -> void:
	for a in ["goblin", "orc", "troll", "wolf", "bandit", "guard"]:
		assert_bool(Stats.has(a)).is_true()
		assert_object(Fighter.ARCHETYPES[a]).is_not_null()


func test_curve_scales_hp_and_damage_by_level_difference() -> void:
	var even := Stats.stats("goblin", 10, 10)
	assert_int(even["hp"]).is_equal(int(Fighter.ARCHETYPES["goblin"]["hp"]))
	assert_float(even["dmg"]).is_equal_approx(float(Fighter.ARCHETYPES["goblin"]["dmg"]), 0.0001)
	var tough := Stats.stats("goblin", 20, 10)
	var weak := Stats.stats("goblin", 1, 40)
	assert_int(tough["hp"]).is_greater(even["hp"])
	assert_int(weak["hp"]).is_less(even["hp"])
	assert_float(weak["dmg"]).is_greater_equal(even["dmg"] * 0.5 - 0.001)    # clamped
	assert_int(Stats.stats("goblin", 60, 1)["hp"]).is_equal(int(round(float(even["hp"]) * 3.0)))


func test_spawned_goblin_and_troll_use_the_table() -> void:
	for species in ["goblin", "troll"]:
		var m: CampMonster = auto_free(CampMonster.new())
		m.species = species
		add_child(m)
		assert_bool(m.is_queued_for_deletion()).is_false()     # it really spawned
		var st := Stats.stats(species, m.level, Stats.player_level())
		assert_int(m.max_health).is_equal(st["hp"])
		assert_int(m.health).is_equal(st["hp"])
		assert_float(m._fighter.poise_max).is_equal_approx(st["poise"], 0.001)
		assert_float(m._fighter.cd_mult).is_equal_approx(st["cdm"], 0.0001)


func test_spawned_wolf_uses_the_table() -> void:
	var w: Node = auto_free(WolfScript.new())
	w.species = "wolf"
	add_child(w)
	var st := Stats.stats("wolf", Stats.player_level(), Stats.player_level())
	assert_int(w.max_health).is_equal(st["hp"])


func test_spawned_bandit_and_guard_soldiers_use_the_table() -> void:
	var keep: Array[String] = []
	for team in [1, 0]:
		var s: Node = auto_free(SoldierScript.create(team, "", "Guard", keep))
		add_child(s)
		var arch := "bandit" if team == 1 else "guard"
		var pl := Stats.player_level()
		var st := Stats.stats(arch, pl, pl)
		assert_int(s.max_health).is_equal(st["hp"])
		assert_float(s._npc_scale).is_equal_approx(float(st["hp"]) / 40.0, 0.0001)


func test_army_blows_between_npcs_are_rescaled() -> void:
	var keep: Array[String] = []
	var s: Node = auto_free(SoldierScript.create(1, "", "Guard", keep))
	add_child(s)
	var other: Node = auto_free(Node3D.new())
	add_child(other)
	var hp0: int = s.health
	s.take_damage(8, other)
	# 8 damage used to be 20% of a 40 HP soldier: on a 170 HP body it is the same 20% (8 * 170/40 = 34).
	var lost: int = hp0 - s.health
	assert_int(lost).is_between(30, 36)
	assert_float(float(lost) / float(hp0)).is_between(0.17, 0.23)
