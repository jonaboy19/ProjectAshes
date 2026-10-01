extends GdUnitTestSuite
## Player combat wiring on top of the move tables: swing timings come from CombatMoves, the combo
## chains through the cancel window, and incoming blows go through HitResolver (parry / block / break).

const PlayerScript := preload("res://scripts/actors/player.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")

var _p: Node3D


func before_test() -> void:
	_p = auto_free(PlayerScript.new())
	add_child(_p)
	_p.stamina = 100.0


func test_first_swing_uses_table_timings() -> void:
	var a: Resource = Moves.combo("sword")[0]
	_p.attack()
	assert_float(_p._swing).is_equal_approx(a.total(), 0.0001)
	assert_float(_p._swing_hit).is_equal_approx(a.hit_time(), 0.0001)
	assert_float(_p._swing_cancel).is_equal_approx(a.cancel_remaining("attack"), 0.0001)
	assert_float(_p.stamina).is_equal_approx(100.0 - a.cost, 0.001)


func test_swing_started_signal_carries_the_action() -> void:
	var got := []
	_p.swing_started.connect(func(action: Resource, info: Dictionary) -> void: got.append([action, info]))
	_p.attack()
	assert_int(got.size()).is_equal(1)
	assert_str(got[0][0].id).is_equal("sword_1")
	assert_float(got[0][1]["hit_t"]).is_equal_approx(0.25, 0.0001)


func test_attack_cannot_chain_before_the_cancel_window() -> void:
	_p.attack()
	var id: int = _p.swing_id()
	_p._swing_elapsed = 0.0
	_p.attack()                      # too early: buffered, not started
	assert_int(_p.swing_id()).is_equal(id)
	_p._swing = _p._swing_cancel * 0.5   # inside the window
	_p.attack()
	assert_int(_p.swing_id()).is_equal(id + 1)


func test_blow_while_blocking_late_is_blocked_with_old_stamina_cost() -> void:
	_p.blocking = true
	_p._block_age = 5.0
	var before: float = _p.stamina
	var blocked := []
	_p.blocked.connect(func(_a: Node, broken: bool) -> void: blocked.append(broken))
	_p.take_damage(10)
	assert_float(before - _p.stamina).is_equal_approx(16.0, 0.01)   # 1.6 x damage, as before
	assert_array(blocked).is_equal([false])
	assert_int(_p.health).is_equal(_p.max_health - 1)               # 15% chip, int(1.5) as before


func test_blow_in_parry_window_is_parried() -> void:
	_p.blocking = true
	_p._block_age = 0.02
	var grades := []
	_p.parried.connect(func(_a: Node, _pt: Vector3, g: String) -> void: grades.append(g))
	_p.take_damage(10)
	assert_array(grades).is_equal(["perfect"])
	assert_int(_p.health).is_equal(_p.max_health)
	assert_float(_p._parry_bonus).is_greater(0.0)


func test_guard_break_when_stamina_runs_out() -> void:
	_p.blocking = true
	_p._block_age = 5.0
	_p.stamina = 5.0
	_p.take_damage(20)
	assert_float(_p._stunned).is_greater(0.5)
	assert_int(_p.health).is_less(_p.max_health)
