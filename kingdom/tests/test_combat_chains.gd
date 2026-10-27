extends GdUnitTestSuite
## Full-motion weapon chains (scripts/combat/combat_chains.gd): timing from measured clip markers, contact on the
## feel target, cancel windows, finisher/heavy commitment, directional cuts.

const Chains := preload("res://scripts/combat/combat_chains.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")


func before_test() -> void:
	Chains.enabled = true
	Chains.clear_cache()


func test_every_style_builds_a_chain_from_markers() -> void:
	for style in ["sword", "greatsword", "axe"]:
		var c := Chains.combo(style)
		assert_int(c.size()).override_failure_message(style).is_equal(4)
		assert_bool(c[3].finisher).is_true()
		assert_object(Chains.heavy(style, 0.3)).is_not_null()
		assert_object(Chains.kick(style)).is_not_null()


func test_contact_lands_on_the_feel_target() -> void:
	for a: Resource in Chains.combo("sword").slice(0, 3):
		assert_float(a.hit_time()).override_failure_message(a.anim).is_between(Chains.LIGHT_HIT - 0.12, Chains.LIGHT_HIT + 0.12)
		assert_bool(a.hit_time() > a.windup - 0.001 and a.hit_time() <= a.active_end() + 0.001).is_true()
		assert_bool(a.root_motion).is_true()


func test_light_steps_chain_after_contact_but_finisher_commits() -> void:
	var c := Chains.combo("sword")
	var first: Resource = c[0]
	assert_float(first.cancel_from("attack")).is_equal_approx(first.hit_time() + Chains.CHAIN_CANCEL, 0.001)
	assert_bool(first.can_cancel("attack", first.hit_time())).is_false()
	assert_float((c[3] as Resource).cancel_from("attack")).is_equal(-1.0)
	assert_float(first.cancel_from("block")).is_greater_equal(first.active_end() - 0.001)


func test_heavy_is_slower_and_breaks_guard() -> void:
	var h := Chains.heavy("sword", 0.3)
	assert_float(h.hit_time()).is_greater(Chains.combo("sword")[0].hit_time())
	assert_bool(h.guard_break).is_true()
	assert_float(h.charge_time).is_equal(0.3)


func test_directional_input_picks_the_cut() -> void:
	assert_str(Chains.cut_for(Vector2(1, 0))).is_equal("right")
	assert_str(Chains.cut_for(Vector2(-1, 0.2))).is_equal("left")
	assert_str(Chains.cut_for(Vector2(0, 1))).is_equal("thrust")
	assert_str(Chains.cut_for(Vector2(0, -1))).is_equal("overhead")
	assert_str(Chains.cut_for(Vector2(0.2, 0.1))).is_equal("")
	var steps := Chains.combo("sword")
	var over: Resource = Chains.pick("sword", steps, 1, Vector2(0, -1))
	assert_str(over.anim).is_equal("Mx_SnS_Attack_3")
	assert_object(Chains.pick("sword", steps, 3, Vector2(0, -1))).is_same(steps[3])
	assert_object(Chains.pick("sword", steps, 1, Vector2.ZERO)).is_same(steps[1])


func test_moves_table_uses_full_motion_and_classic_switch_falls_back() -> void:
	assert_str(String(Moves.combo("sword")[0].anim)).starts_with("Mx_")
	Chains.enabled = false
	assert_str(String(Moves.combo("axe")[0].anim)).is_equal("Sword_Light_1_Upper")
	Chains.enabled = true


func test_guard_legs_weight_eases_in_and_out_capped() -> void:
	var GL := preload("res://scripts/combat/guard_legs.gd")
	var w := 0.0
	for i in 60:
		w = GL.step_weight(w, 1.0, 1.0 / 60.0)
	assert_float(w).is_equal_approx(GL.MAX_WEIGHT, 0.001)
	w = GL.step_weight(w, 0.0, 0.05)
	assert_float(w).is_less(GL.MAX_WEIGHT)
	for style in ["sword", "greatsword", "axe"]:
		assert_bool(Chains.markers().has(Chains.guard_clip(style))).is_true()


func test_parry_contact_point_lies_between_hand_and_chest() -> void:
	var PC := preload("res://scripts/combat/parry_contact.gd")
	var at: Vector3 = PC.contact_point_from(Vector3(0, 1.4, 2.0), Vector3(0, 1.25, 0))
	assert_float(at.z).is_between(0.6, 2.0)
	assert_float(Vector3(0, 1.4, 2.0).distance_to(at)).is_equal_approx(PC.BLADE_REACH, 0.001)
