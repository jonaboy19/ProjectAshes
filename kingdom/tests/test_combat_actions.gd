extends GdUnitTestSuite
## CombatAction data and the move tables. The sword table must reproduce player.gd's old COMBO exactly.

const Moves := preload("res://scripts/combat/combat_moves.gd")

## The old COMBO constant: [anim, damage, lock, hit, speed, cost, knockback]
const OLD := [
	["Sword_Light_1_Upper", 14, 0.42, 0.25, 1.2, 10.0, 1.5],
	["Sword_Light_2_Upper", 14, 0.39, 0.19, 1.2, 10.0, 1.5],
	["Sword_Light_3_Upper", 18, 0.42, 0.25, 1.2, 12.0, 1.5],
	["Sword_Light_4_Upper", 30, 0.64, 0.44, 1.2, 16.0, 7.0],
]
const OLD_SWING_CANCEL := 0.22
const OLD_ACTIVE_BEFORE := 0.03
const OLD_ACTIVE_AFTER := 0.05


func test_sword_combo_matches_old_table_exactly() -> void:
	var steps := Moves.combo("sword")
	assert_int(steps.size()).is_equal(4)
	for i in 4:
		var a: Resource = steps[i]
		var o: Array = OLD[i]
		assert_str(a.anim).is_equal(o[0])
		assert_int(a.damage).is_equal(o[1])
		assert_float(a.total()).is_equal_approx(o[2], 0.0001)
		assert_float(a.hit_time()).is_equal_approx(o[3], 0.0001)
		assert_float(a.anim_speed).is_equal_approx(o[4], 0.0001)
		assert_float(a.cost).is_equal_approx(o[5], 0.0001)
		assert_float(a.knockback).is_equal_approx(o[6], 0.0001)


func test_active_window_matches_old_dodge_gate() -> void:
	for i in 4:
		var a: Resource = Moves.combo("sword")[i]
		var hit: float = OLD[i][3]
		assert_float(a.active_start()).is_equal_approx(hit - OLD_ACTIVE_BEFORE, 0.0001)
		assert_float(a.active_end()).is_equal_approx(hit + OLD_ACTIVE_AFTER, 0.0001)
		assert_bool(a.is_active(hit)).is_true()
		assert_bool(a.is_active(hit - 0.05)).is_false()
		assert_bool(a.is_active(hit + 0.07)).is_false()


func test_cancel_window_is_last_22_percent_and_finisher_has_none() -> void:
	var steps := Moves.combo("sword")
	for i in 3:
		var a: Resource = steps[i]
		var lock: float = OLD[i][2]
		assert_float(a.cancel_remaining("attack")).is_equal_approx(lock * OLD_SWING_CANCEL, 0.0001)
		assert_bool(a.can_cancel("attack", lock * 0.5)).is_false()
		assert_bool(a.can_cancel("attack", lock * 0.9)).is_true()
	var fin: Resource = steps[3]
	assert_bool(fin.finisher).is_true()
	assert_float(fin.cancel_remaining("attack")).is_equal(0.0)
	assert_bool(fin.can_cancel("attack", 0.6)).is_false()


func test_total_is_windup_plus_active_plus_recovery() -> void:
	for style: String in Moves.styles():
		for a: Resource in Moves.moves(style):
			assert_float(a.total()).is_equal_approx(a.windup + a.active + a.recovery, 0.0001)
			assert_float(a.windup).is_greater(0.0)
			assert_float(a.recovery).is_greater(0.0)
			assert_float(a.hit_time()).is_less_equal(a.active_end() + 0.0001)


func test_creature_default_moves_match_species_rows() -> void:
	# [style, windup, windup+recover, reach, damage]  from monster.gd / wolf.gd SPECIES
	for row: Array in [["goblin", 0.5, 0.95, 2.2, 6], ["orc", 0.85, 1.45, 2.6, 15], ["troll", 1.1, 1.9, 3.2, 22], ["wolf", 0.5, 0.95, 2.3, 9]]:
		var a: Resource = Moves.moves(row[0])[0]
		assert_float(a.hit_time()).is_equal_approx(row[1], 0.0001)
		assert_float(a.total()).is_equal_approx(row[2], 0.0001)
		assert_float(a.reach).is_equal_approx(row[3], 0.0001)
		assert_int(a.damage).is_equal(row[4])


func test_every_creature_has_two_or_three_moves_and_telegraphs() -> void:
	for style in ["goblin", "orc", "troll", "wolf"]:
		var n := Moves.moves(style).size()
		assert_bool(n >= 2 and n <= 3).is_true()
		for a: Resource in Moves.moves(style):
			# ashes-melee-combat: heavy blows telegraph for >= 0.35 s on touch
			if a.damage >= 15:
				assert_float(a.windup).is_greater_equal(0.35)
	assert_object(Moves.find("bandit", "bandit_cleave")).is_not_null()
	assert_object(Moves.find("bandit", "nope")).is_null()


func test_f3_weapon_tables_and_heavies() -> void:
	for style in ["sword", "spear", "staff"]:
		var steps: Array = Moves.combo(style)
		assert_bool(steps.size() >= 3).is_true()
		var heavy: Resource = Moves.heavy(style)
		assert_object(heavy).is_not_null()
		assert_bool(heavy.charge_time > 0.0).is_true()
		assert_bool(heavy.finisher).is_true()
		assert_bool(heavy.cancel_windows.is_empty()).is_true()
	assert_float(Moves.combo("spear")[0].reach).is_greater(Moves.combo("sword")[0].reach)
	assert_float(Moves.heavy("spear").arc_dot).is_less(Moves.combo("spear")[0].arc_dot)   # the sweep is wider than the thrust
	assert_int(Moves.moves("sword").size()).is_equal(4)                                   # the old light chain is unchanged
	assert_bool(Moves.combo("bow")[0].ranged).is_true()
