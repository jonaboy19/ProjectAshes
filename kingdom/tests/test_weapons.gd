extends GdUnitTestSuite
## F3: hold-to-charge heavy, per-weapon move tables, bow draw / aim / arrows, the projectile pool, the player's
## knockdown and get-up. Rules are pure (weapon_rules.gd, knockdown_state.gd); player glue is player_arms.gd.

const PlayerScript := preload("res://scripts/actors/player.gd")
const PlayerArms := preload("res://scripts/actors/player_arms.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")
const Rules := preload("res://scripts/combat/weapon_rules.gd")
const Knockdown := preload("res://scripts/combat/knockdown_state.gd")
const Pool := preload("res://scripts/vfx/projectile_pool.gd")
const Caster := preload("res://scripts/actors/technique_caster.gd")

var _p: Node3D


## A hostile that describes its blow the way monster.gd does (attack_info) and records what hits it.
class Foe extends Node3D:
	var poise := 10.0
	var unblockable := false
	var hits: Array = []
	var dead := false
	func attack_info() -> Dictionary:
		return {"poise_damage": poise, "lane": 0, "parryable": not unblockable, "unblockable": unblockable}
	func take_damage(amount: int, _from: Node = null, knockback := Vector3.ZERO) -> void:
		hits.append([amount, knockback])


class FakeEquipment extends RefCounted:
	signal changed(slot: String, item_id: String)
	var main := "ash_shortbow"
	func item_in(slot: String) -> String:
		return main if slot == "main_hand" else ""
	func stats() -> Dictionary:
		return {"damage": 4.0}


class FakeLife extends RefCounted:
	var equipment := FakeEquipment.new()
	var bag := {"flint_arrow": 5, "iron_arrow": 3}
	func count(id: String) -> int:
		return int(bag.get(id, 0))
	func take(id: String, n := 1) -> bool:
		if count(id) < n:
			return false
		bag[id] = count(id) - n
		return true


func before_test() -> void:
	Rules.set_data({})
	_p = auto_free(PlayerScript.new())
	add_child(_p)
	_p.stamina = 100.0


func after_test() -> void:
	Rules.set_data({})
	Life.equipment.unequip("main_hand")


func _equip(id: String) -> void:
	Life.equipment.equip(id)


# --- heavy charge timing ---------------------------------------------------------------------------

func test_press_kind_switches_at_the_hold_time() -> void:
	assert_float(Rules.hold_time()).is_equal_approx(0.3, 0.0001)
	assert_str(Rules.press_kind(0.29)).is_equal("tap")
	assert_str(Rules.press_kind(0.3)).is_equal("charging")
	assert_float(Rules.charge_mult(0.3)).is_equal_approx(1.0, 0.0001)
	assert_float(Rules.charge_mult(5.0)).is_equal_approx(1.25, 0.0001)
	assert_float(Rules.charge_mult(0.8)).is_between(1.0, 1.25)


func test_tap_fires_the_light_combo_on_release() -> void:
	var arms: Object = _p._arms
	arms.press(false)
	arms.tick(0.1)
	assert_bool(arms.charging).is_false()
	assert_int(_p.swing_id()).is_equal(0)
	arms.release()
	assert_int(_p.swing_id()).is_equal(1)
	assert_str(_p._action.id).is_equal("sword_1")


func test_hold_past_the_threshold_charges_and_release_swings_the_heavy() -> void:
	var arms: Object = _p._arms
	arms.press(false)
	arms.tick(0.25)
	assert_bool(arms.charging).is_false()
	arms.tick(0.1)                                   # 0.35 s held
	assert_bool(arms.charging).is_true()
	assert_int(_p.swing_id()).is_equal(0)            # nothing swung while charging
	arms.tick(0.5)
	var id_before: int = _p.swing_id()
	arms.release()
	assert_int(_p.swing_id()).is_equal(id_before + 1)
	assert_str(_p._action.id).is_equal("sword_heavy")
	assert_bool(_p._action.guard_break).is_true()
	assert_bool(arms.charging).is_false()


func test_heavy_is_slower_and_hits_harder_than_every_light() -> void:
	for style in ["sword", "spear", "staff"]:
		var h: Resource = Moves.heavy(style)
		assert_object(h).is_not_null()
		assert_float(h.charge_time).is_equal_approx(0.3, 0.0001)
		for light: Resource in Moves.combo(style):
			assert_int(h.damage).is_greater(light.damage - 1)
			assert_float(h.poise_damage).is_greater(light.poise_damage - 0.01)
			assert_float(h.knockback).is_greater(light.knockback - 0.01)
			assert_float(h.total()).is_greater(light.total())
	assert_bool(Moves.heavy("sword").guard_break).is_true()
	assert_bool(Moves.heavy("staff").technique).is_true()
	assert_object(Moves.heavy("bow")).is_null()


func test_charged_heavy_deals_more_than_a_bare_threshold_heavy() -> void:
	var arms: Object = _p._arms
	_p._swing = 5.0                                  # mid-swing: the released heavy waits (buffered) so its multiplier stays readable
	_p._swing_cancel = 0.0
	arms.press(false)
	arms.tick(0.31)
	arms.release()
	assert_object(arms._heavy).is_not_null()
	var quick: float = arms._charge_mult
	assert_float(quick).is_equal_approx(1.0, 0.01)
	arms._heavy = null
	arms.press(false)
	arms.tick(1.3)
	arms.release()
	assert_float(arms._charge_mult).is_greater(quick + 0.2)
	# a pending heavy expires if no opening comes
	arms.tick(0.5)
	assert_object(arms._heavy).is_null()
	assert_float(arms.take_charge_mult()).is_equal_approx(1.0, 0.0001)


func test_a_hit_taken_cancels_the_charge() -> void:
	var arms: Object = _p._arms
	arms.press(false)
	arms.tick(0.5)
	assert_bool(arms.charging).is_true()
	_p.take_damage(5)
	assert_bool(arms.charging).is_false()
	assert_bool(arms.input_held).is_false()


# --- move table follows the equipped weapon -------------------------------------------------------------

func test_weapon_types_map_to_tables() -> void:
	for pair in [["sword", "sword"], ["axe", "sword"], ["greatsword", "sword"], ["spear", "spear"], ["halberd", "spear"],
			["staff", "staff"], ["wand", "staff"], ["shortbow", "bow"], ["longbow", "bow"], ["crossbow", "bow"], ["", "sword"]]:
		assert_str(Rules.style_for_type(pair[0])).override_failure_message(pair[0]).is_equal(pair[1])


func test_equipping_changes_the_player_move_table() -> void:
	var arms: Object = _p._arms
	assert_str(_p.combat_style).is_equal("sword")
	_equip("iron_spear")
	assert_str(arms.style).is_equal("spear")
	assert_str(_p.combat_style).is_equal("spear")
	_p.attack()
	assert_str(_p._action.id).is_equal("spear_1")
	assert_str(_p._action.anim).is_equal("Spear_Thrust_1")
	assert_float(_p._action.reach).is_greater(Moves.combo("sword")[0].reach)
	_equip("ash_staff")
	assert_str(_p.combat_style).is_equal("staff")
	assert_float(Moves.combo("staff")[0].arc_dot).is_less(Moves.combo("sword")[0].arc_dot)
	_equip("ash_shortbow")
	assert_str(_p.combat_style).is_equal("bow")
	Life.equipment.unequip("main_hand")
	assert_str(_p.combat_style).is_equal("sword")


func test_move_tables_are_distinct_and_well_formed() -> void:
	for style in ["sword", "spear", "staff"]:
		var steps := Moves.combo(style)
		assert_int(steps.size()).is_equal(4 if style == "sword" else 3)
		assert_bool(steps[steps.size() - 1].finisher).is_true()
		for a: Resource in steps:
			assert_str(a.style).is_equal(style)
			assert_float(a.total()).is_greater(0.3)
	assert_str(Moves.combo("spear")[0].anim).is_not_equal(Moves.combo("sword")[0].anim)
	assert_bool(Moves.combo("bow")[0].ranged).is_true()


func test_spear_reaches_further_than_the_sword_in_resolve_hit() -> void:
	var foe: Foe = auto_free(Foe.new())
	add_child(foe)
	foe.add_to_group("team1")
	foe.global_position = _p.global_position + _p.facing() * 3.2
	_p._action = Moves.combo("sword")[0]
	_p._resolve_hit(14, 1.5, false)
	assert_int(foe.hits.size()).is_equal(0)          # 3.2 m is beyond the sword's 2.6
	_p._action = Moves.combo("spear")[0]
	_p._resolve_hit(13, 1.5, false)
	assert_int(foe.hits.size()).is_equal(1)


# --- bow --------------------------------------------------------------------------------------------------

func test_bow_draw_curve_rewards_a_longer_draw() -> void:
	var last := -1.0
	for t in [0.0, 0.12, 0.3, 0.5, 0.7, 0.9, 1.4]:
		var pw: float = Rules.bow_power(t)
		assert_float(pw).is_greater(last - 0.0001)
		last = pw
	assert_float(Rules.bow_power(0.0)).is_equal_approx(0.3, 0.0001)
	assert_float(Rules.bow_power(0.9)).is_equal_approx(1.0, 0.0001)
	assert_float(Rules.bow_power(5.0)).is_equal_approx(1.0, 0.0001)
	assert_int(Rules.bow_damage(4.0, 1.0, 0.9)).is_greater(Rules.bow_damage(4.0, 1.0, 0.12) * 2 - 1)
	assert_float(Rules.arrow_speed(0.9)).is_greater(Rules.arrow_speed(0.12))
	assert_float(Rules.bow_stamina(0.9)).is_greater(Rules.bow_stamina(0.0))
	assert_int(Rules.bow_damage(4.0, 3.0, 0.9)).is_greater(Rules.bow_damage(4.0, 1.0, 0.9))


func test_aim_assist_pulls_toward_a_cone_target_and_snaps_to_the_lock() -> void:
	var origin := Vector3.ZERO
	var face := Vector3(0, 0, 1)
	# 6 degrees off the facing, 12 m away: inside the 11 degree assist
	var near := Vector3(sin(deg_to_rad(6.0)) * 12.0, 0, cos(deg_to_rad(6.0)) * 12.0)
	var r: Dictionary = Rules.aim_direction(origin, face, [near])
	assert_bool(r["assisted"]).is_true()
	assert_float((r["dir"] as Vector3).x).is_greater(0.01)
	assert_float(face.angle_to(r["dir"])).is_less(face.angle_to((near + Vector3(0, 0.9, 0)).normalized()) + 0.001)
	# 40 degrees off: outside the cone pick, shoots straight
	var wide := Vector3(sin(deg_to_rad(40.0)) * 12.0, 0, cos(deg_to_rad(40.0)) * 12.0)
	var w: Dictionary = Rules.aim_direction(origin, face, [wide])
	assert_bool(w["assisted"]).is_false()
	assert_float((w["dir"] as Vector3).x).is_equal_approx(0.0, 0.0001)
	# locked: snaps whatever the angle
	var l: Dictionary = Rules.aim_direction(origin, face, [], Vector3(10, 0, 4))
	assert_bool(l["assisted"]).is_true()
	assert_float((l["dir"] as Vector3).x).is_greater(0.5)


func test_bow_shot_spends_stamina_and_one_arrow_and_spawns_a_pooled_arrow() -> void:
	var fake := FakeLife.new()
	var arms: Object = PlayerArms.new(_p, fake)
	assert_str(arms.style).is_equal("bow")
	assert_str(arms.ammo_id()).is_equal("iron_arrow")           # strongest stack first
	var pool: Node3D = Pool.at(_p.get_parent())
	var before := 100.0
	_p.stamina = before
	var shot: Dictionary = arms.fire_bow(0.9)
	assert_bool(shot.is_empty()).is_false()
	assert_int(fake.count("iron_arrow")).is_equal(2)
	assert_float(before - _p.stamina).is_equal_approx(Rules.bow_stamina(0.9), 0.001)
	assert_int(pool.in_use("arrow")).is_equal(1)
	var quick: Dictionary = arms.fire_bow(0.0)
	assert_int(int(shot["damage"])).is_greater(int(quick["damage"]))
	assert_float(shot["speed"]).is_greater(quick["speed"])


func test_bow_needs_arrows() -> void:
	var fake := FakeLife.new()
	fake.bag.clear()
	var arms: Object = PlayerArms.new(_p, fake)
	var pool: Node3D = Pool.at(_p.get_parent())
	var used: int = pool.in_use("arrow")
	assert_bool((arms.fire_bow(0.9) as Dictionary).is_empty()).is_true()
	assert_int(pool.in_use("arrow")).is_equal(used)
	arms.press(false)
	assert_bool(arms.drawing).is_false()


func test_bow_hold_draws_and_release_fires() -> void:
	var fake := FakeLife.new()
	var arms: Object = PlayerArms.new(_p, fake)
	var shots := []
	arms.arrow_shot.connect(func(info: Dictionary) -> void: shots.append(info))
	arms.press(false)
	assert_bool(arms.drawing).is_true()
	arms.tick(0.9)
	arms.release()
	assert_int(shots.size()).is_equal(1)
	assert_float(Rules.bow_power(shots[0]["draw"])).is_equal_approx(1.0, 0.001)
	assert_bool(arms.drawing).is_false()


func test_arrow_hits_a_foe_then_sticks_briefly_and_returns() -> void:
	var pool: Node3D = auto_free(Pool.new(4, 2))
	add_child(pool)
	var foe: Foe = auto_free(Foe.new())
	add_child(foe)
	foe.add_to_group("team1")
	foe.global_position = Vector3(0, 0, 10)
	var slot: Dictionary = pool.fire_arrow(Vector3(0, 0.9, 0), Vector3(0, 0, 1), 40.0, {"damage": 17, "shooter": _p})
	for i in 30:
		pool.step(1.0 / 60.0)
	assert_int(foe.hits.size()).is_equal(1)
	assert_int(foe.hits[0][0]).is_equal(17)
	assert_str(slot["state"]).is_equal("stuck")
	for i in 60:
		pool.step(1.0 / 60.0)           # 1 s: past the 0.6 s body stick time
	assert_str(slot["state"]).is_equal("free")


func test_arrow_sticks_in_a_wall_for_the_surface_time() -> void:
	var pool: Node3D = auto_free(Pool.new(2, 1))
	pool.ray_fn = func(from: Vector3, to: Vector3) -> Dictionary:
		return {"position": Vector3(0, 1, 8), "collider": null} if to.z >= 8.0 and from.z < 8.0 else {}
	var slot: Dictionary = pool.fire_arrow(Vector3(0, 1, 0), Vector3(0, 0, 1), 30.0, {"gravity": 0.0})
	for i in 60:
		pool.step(1.0 / 60.0)
	assert_str(slot["state"]).is_equal("stuck")
	assert_float((slot["pos"] as Vector3).z).is_greater(7.9)
	for i in int(Rules.cfg("pool")["stick_time"] * 60.0) + 5:
		pool.step(1.0 / 60.0)
	assert_str(slot["state"]).is_equal("free")
	assert_bool((slot["node"] as Node3D).visible).is_false()


# --- projectile pool ------------------------------------------------------------------------------------------

func test_pool_cap_holds_and_nothing_is_allocated_per_shot() -> void:
	var pool: Node3D = auto_free(Pool.new(4, 3))
	var nodes: int = pool.node_total()
	assert_int(nodes).is_equal(7)
	var first: Array = []
	for i in 40:
		var s: Dictionary = pool.fire_arrow(Vector3(0, 5, 0), Vector3(0, 0, 1), 5.0, {"gravity": 0.0, "life": 100.0})
		assert_bool(s.is_empty()).is_false()          # arrows recycle the oldest instead of failing
		if i < 4:
			first.append(s["node"])
		assert_int(pool.in_use("arrow")).is_less(5)
	assert_int(pool.node_total()).is_equal(nodes)
	assert_int(pool.slot_count()).is_equal(nodes)
	assert_int(pool.in_use("arrow")).is_equal(4)
	for n in first:
		assert_bool(is_instance_valid(n)).is_true()   # reused, never freed


func test_pool_recycles_stuck_arrows_before_flying_ones() -> void:
	var pool: Node3D = auto_free(Pool.new(2, 1))
	pool.ray_fn = func(_f: Vector3, to: Vector3) -> Dictionary:
		return {"position": to} if to.z > 2.0 and to.x < 0.5 else {}
	var stuck: Dictionary = pool.fire_arrow(Vector3(0, 1, 0), Vector3(0, 0, 1), 60.0, {"gravity": 0.0})
	pool.step(0.1)
	assert_str(stuck["state"]).is_equal("stuck")
	var flying: Dictionary = pool.fire_arrow(Vector3(5, 1, 0), Vector3(1, 0, 0), 5.0, {"gravity": 0.0})
	var third: Dictionary = pool.fire_arrow(Vector3(5, 1, 0), Vector3(1, 0, 0), 5.0, {"gravity": 0.0})
	assert_object(third["node"]).is_same(stuck["node"])
	assert_str(flying["state"]).is_equal("fly")


func test_orbs_are_capped_and_released_back() -> void:
	var pool: Node3D = auto_free(Pool.new(1, 3))
	var got: Array = []
	for i in 3:
		got.append(pool.acquire_orb(Color.RED))
		assert_object(got[i]).is_not_null()
	assert_object(pool.acquire_orb(Color.RED)).is_null()          # all in flight: the cast goes unseen, not a new node
	assert_int(pool.node_total()).is_equal(4)
	assert_bool(pool.release_node(got[1])).is_true()
	assert_object(pool.acquire_orb(Color.BLUE)).is_same(got[1])
	assert_bool(pool.release_node(auto_free(Node3D.new()))).is_false()        # strangers are the caller's to free


func test_technique_caster_orbs_come_from_the_pool() -> void:
	var caster: Node = auto_free(Caster.new())
	caster.player = _p
	add_child(caster)
	var pool: Node3D = Pool.at(_p.get_parent())
	var used: int = pool.in_use("orb")
	var orb: Node3D = caster._orb({"element": "fire"})
	assert_object(orb).is_not_null()
	assert_object(orb.get_parent()).is_same(pool)
	assert_int(pool.in_use("orb")).is_equal(used + 1)
	caster._free_projectile(orb)
	assert_int(pool.in_use("orb")).is_equal(used)
	assert_bool(is_instance_valid(orb)).is_true()


# --- knockdown / get-up ----------------------------------------------------------------------------------------

func test_knockdown_thresholds_are_data() -> void:
	assert_str(Rules.knockdown_kind(10.0, 2.0)).is_equal("")
	assert_str(Rules.knockdown_kind(32.0, 5.0)).is_equal("")           # orc overhead stays standing
	assert_str(Rules.knockdown_kind(60.0, 8.0)).is_equal("fall")       # troll slam
	assert_str(Rules.knockdown_kind(40.0, 1.0)).is_equal("fall")       # poise alone
	assert_str(Rules.knockdown_kind(10.0, 6.0)).is_equal("fall")       # knockback alone
	Rules.set_data({"knockdown": {"poise_threshold": 5.0, "knockback_threshold": 99.0}})
	assert_str(Rules.knockdown_kind(6.0, 0.0)).is_equal("fall")
	Rules.set_data({"knockdown": {"ragdoll_enabled": true, "ragdoll_knockback": 9.0}})
	assert_str(Rules.knockdown_kind(60.0, 9.5)).is_equal("ragdoll")


func test_knockdown_machine_fall_down_getup_with_iframes() -> void:
	var kd := Knockdown.new()
	assert_str(kd.try_begin(10.0, 1.0)).is_equal("")
	assert_str(kd.try_begin(60.0, 8.0)).is_equal("fall")
	assert_int(kd.state).is_equal(Knockdown.S.FALL)
	assert_bool(kd.invulnerable()).is_false()
	assert_str(kd.try_begin(60.0, 8.0)).is_equal("")                 # no chain while floored
	var events: Array = []
	for i in 250:                                                   # 2.5 s: the whole 2.4 s fall / down / get-up, inside the cooldown
		var e := kd.tick(0.01)
		if e != "":
			events.append(e)
			if e == "getup":
				assert_bool(kd.invulnerable()).is_true()
	assert_array(events).is_equal(["down", "getup", "done"])
	assert_int(kd.state).is_equal(Knockdown.S.NONE)
	assert_str(kd.try_begin(60.0, 8.0)).is_equal("")                 # cooldown
	kd.tick(5.0)
	assert_str(kd.try_begin(60.0, 8.0)).is_equal("fall")


func test_dodge_while_down_rolls_out_with_iframes() -> void:
	var kd := Knockdown.new()
	kd.try_begin(60.0, 8.0)
	assert_str(kd.dodge_pressed()).is_equal("queued")                 # still falling: queued
	kd.tick(0.6)
	assert_int(kd.state).is_equal(Knockdown.S.DOWN)
	assert_bool(kd.take_queued_roll()).is_true()
	assert_int(kd.state).is_equal(Knockdown.S.NONE)
	assert_bool(kd.invulnerable()).is_true()
	var k2 := Knockdown.new()
	k2.try_begin(60.0, 8.0)
	k2.tick(0.6)
	assert_str(k2.dodge_pressed()).is_equal("roll")
	assert_float(k2.iframes).is_equal_approx(float(Rules.cfg("knockdown")["roll_iframes"]), 0.001)


func test_troll_slam_knocks_the_player_down_then_gets_up_with_iframes() -> void:
	var troll: Foe = auto_free(Foe.new())
	troll.poise = 60.0
	troll.unblockable = true
	add_child(troll)
	troll.global_position = _p.global_position + Vector3(0, 0, 2)
	var kd: Object = _p._arms.kd
	var hp: int = _p.health
	_p.take_damage(30, troll, Vector3(0, 0, -8))
	assert_int(_p.health).is_less(hp)
	assert_int(kd.state).is_equal(Knockdown.S.FALL)
	assert_float(_p._stunned).is_greater(1.0)
	assert_int(_p._swing_id).is_greater(-1)
	var arms: Object = _p._arms
	arms.tick(0.6)
	assert_int(kd.state).is_equal(Knockdown.S.DOWN)
	arms.tick(0.8)
	assert_int(kd.state).is_equal(Knockdown.S.GETUP)
	assert_float(_p._invulnerable).is_greater(0.3)
	var hp2: int = _p.health
	_p._hurt_cooldown = 0.0
	_p.take_damage(30, troll, Vector3(0, 0, -8))
	assert_int(_p.health).is_equal(hp2)                               # i-frames on get-up
	arms.tick(1.2)
	assert_int(kd.state).is_equal(Knockdown.S.NONE)


func test_small_hits_do_not_knock_the_player_down() -> void:
	var goblin: Foe = auto_free(Foe.new())
	goblin.poise = 6.0
	add_child(goblin)
	_p.take_damage(6, goblin, Vector3(0, 0, -2))
	assert_int(_p._arms.kd.state).is_equal(Knockdown.S.NONE)


func test_dodge_press_while_down_is_a_roll_out() -> void:
	var troll: Foe = auto_free(Foe.new())
	troll.poise = 60.0
	add_child(troll)
	_p.take_damage(30, troll, Vector3(0, 0, -8))
	var arms: Object = _p._arms
	arms.tick(0.6)
	assert_int(arms.kd.state).is_equal(Knockdown.S.DOWN)
	_p.stamina = 100.0
	_p.dodge()
	assert_int(arms.kd.state).is_equal(Knockdown.S.NONE)
	assert_float(_p._dodge).is_greater(0.0)
	assert_float(_p._stunned).is_less_equal(0.0)
	assert_float(_p._invulnerable).is_greater(0.3)


# --- a press lost to a bite or a knockdown is buffered, not dropped -----------------------------------------------------

func test_a_hit_while_holding_buffers_the_hold_and_restarts_it_when_control_returns() -> void:
	var arms: Object = _p._arms
	arms.press(false)
	arms.tick(0.5)
	assert_bool(arms.charging).is_true()
	_p._stunned = 0.4                                  # a wolf bite staggers
	arms.on_hit_taken(0, 5.0, 1.0, null)
	assert_bool(arms.input_held).is_false()
	assert_bool(arms.charging).is_false()
	assert_bool(arms.has_pending_press()).is_true()
	arms.tick(0.2)                                     # still staggered: waits
	assert_bool(arms.input_held).is_false()
	assert_bool(arms.has_pending_press()).is_true()
	_p._stunned = 0.0                                  # control is back, the button is still down
	arms.tick(0.05)
	assert_bool(arms.has_pending_press()).is_false()
	assert_bool(arms.input_held).is_true()
	arms.tick(0.35)
	assert_bool(arms.charging).is_true()               # the heavy charges again
	arms.tick(0.4)
	var id_before: int = _p.swing_id()
	arms.release()
	assert_int(_p.swing_id()).is_equal(id_before + 1)
	assert_str(_p._action.id).is_equal("sword_heavy")


func test_a_press_during_knockdown_starts_when_the_player_is_up() -> void:
	var troll: Foe = auto_free(Foe.new())
	troll.poise = 60.0
	troll.unblockable = true
	add_child(troll)
	_p.take_damage(30, troll, Vector3(0, 0, -8))
	var arms: Object = _p._arms
	assert_bool(arms.kd.is_active()).is_true()
	arms.press(false)                                  # the button goes down on the floor
	assert_bool(arms.input_held).is_false()
	assert_bool(arms.has_pending_press()).is_true()
	var guard := 0
	while arms.kd.is_active() and guard < 100:
		arms.tick(0.1)                                 # fall, down, get-up: the whole knockdown
		guard += 1
	_p._stunned = 0.0
	arms.tick(0.05)
	assert_bool(arms.kd.is_active()).is_false()
	assert_bool(arms.input_held).is_true()
	arms.tick(0.5)
	assert_bool(arms.charging).is_true()


func test_a_press_released_before_control_returns_does_nothing() -> void:
	var arms: Object = _p._arms
	_p._stunned = 1.0
	arms.press(false)
	assert_bool(arms.has_pending_press()).is_true()
	arms.release()                                     # let go while still staggered
	assert_bool(arms.has_pending_press()).is_false()
	_p._stunned = 0.0
	arms.tick(0.1)
	assert_bool(arms.input_held).is_false()
	assert_int(_p.swing_id()).is_equal(0)


func test_a_real_button_that_is_no_longer_down_drops_the_buffered_press() -> void:
	var arms: Object = _p._arms
	_p._stunned = 1.0
	arms.press(true)                                   # real input: the engine's attack action is up in a headless run
	assert_bool(arms.has_pending_press()).is_true()
	arms.tick(0.1)
	assert_bool(arms.has_pending_press()).is_false()
	assert_bool(arms.input_held).is_false()


func test_a_buffered_press_expires_and_the_bow_never_buffers() -> void:
	var arms: Object = _p._arms
	_p._stunned = 100.0
	arms.press(false)
	arms.tick(PlayerArms.PRESS_BUFFER_LIFE + 0.5)
	assert_bool(arms.has_pending_press()).is_false()
	var fake := FakeLife.new()
	var bow: Object = PlayerArms.new(_p, fake)
	assert_str(bow.style).is_equal("bow")
	bow.press(false)
	assert_bool(bow.has_pending_press()).is_false()    # an unarmed draw would surprise: the bow just ignores the press
