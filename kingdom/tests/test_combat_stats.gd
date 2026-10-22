extends GdUnitTestSuite
## The stat table (data/combat/archetypes.json) reaches the real bodies: spawned goblin / troll / wolf /
## bandit / guard take HP (and poise, cooldown) from it, scaled by enemy level vs player level.

const Stats := preload("res://scripts/combat/combat_stats.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const SoldierScript := preload("res://scripts/army/soldier.gd")
const WolfScript := preload("res://scripts/actors/wolf.gd")
const CombatMovesScript := preload("res://scripts/combat/combat_moves.gd")


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


# --- the wolf in a long fight (tf_combat "the wolf can be finished with light attacks" flake) -------------------------
# Cause found in the playtest logs: a heavy swing leaves the 45 hp wolf at ~3 hp, under its flee_below (15), so by design it
# runs (flee speed above the player's walk, ESCAPE_DISTANCE 30) and retreats home healing; the bot then chased it at 2 fps and
# timed out. These pin the real-game side: blows always land on a fleeing wolf, light swings can finish it, and a body that fled
# and was pooled comes back whole.

func _wolf_with_player() -> Array:
	var w: Node = auto_free(WolfScript.new())
	w.species = "wolf"
	add_child(w)
	var p: Node3D = auto_free(Node3D.new())
	add_child(p)
	p.global_position = Vector3(3, 0, 0)
	return [w, p]


func test_a_badly_hurt_wolf_flees_but_every_blow_still_lands() -> void:
	var wp := _wolf_with_player()
	var w: Node = wp[0]
	var p: Node3D = wp[1]
	w.take_damage(w.max_health - 3, p)                       # a heavy leaves it at 3 hp
	assert_int(w.health).is_equal(3)
	w._decide(p, 0.0)
	assert_int(w.state).is_equal(WolfScript.State.FLEE)
	w.take_damage(2, p)                                      # a light tap while it runs still counts
	assert_int(w.health).is_equal(1)
	w.take_damage(2, p)
	assert_bool(w.dead).is_true()
	assert_bool(w.is_in_group("team1")).is_false()


func test_light_swings_finish_a_full_health_wolf() -> void:
	var wp := _wolf_with_player()
	var w: Node = wp[0]
	var p: Node3D = wp[1]
	var light: int = int(CombatMovesScript.combo("sword")[0].damage)
	assert_int(light).is_greater(0)
	var swings := 0
	while not w.dead and swings < 20:
		w.take_damage(light, p)
		w._decide(p, 0.0)
		swings += 1
	assert_bool(w.dead).is_true()
	assert_int(swings).is_less(12)


func test_a_wolf_that_fled_and_was_recycled_is_whole_again() -> void:
	var wp := _wolf_with_player()
	var w: Node = wp[0]
	var p: Node3D = wp[1]
	if w._model == null:
		return                                               # model not imported in this run: reset() has nothing to restore
	w.take_damage(w.max_health - 2, p)
	w._decide(p, 0.0)
	w._regen = 0.7
	w._flee_time = 4.0
	w._escape_told = true
	w._busy = 2.0
	w.reset()
	assert_int(w.state).is_equal(WolfScript.State.ROAM)
	assert_int(w.health).is_equal(w.max_health)
	assert_bool(w.dead).is_false()
	assert_float(w._regen).is_equal(0.0)
	assert_float(w._flee_time).is_equal(0.0)
	assert_bool(w._escape_told).is_false()
	assert_float(w._busy).is_equal(0.0)
	assert_bool(w.is_in_group("team1")).is_true()
