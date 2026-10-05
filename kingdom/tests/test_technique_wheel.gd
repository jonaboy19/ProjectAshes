extends GdUnitTestSuite
## Radial technique wheel: pure model (scripts/ui/technique_wheel_model.gd) and the control's open / confirm /
## time-scale safeguards (scripts/ui/technique_wheel.gd).

const Model := preload("res://scripts/ui/technique_wheel_model.gd")
const Wheel := preload("res://scripts/ui/technique_wheel.gd")
const Skills := preload("res://scripts/sim/skills.gd")


class FakeCaster extends Node:
	var cast_ids: Array = []
	func cast_technique(id: String, _sealed := false) -> Dictionary:
		cast_ids.append(id)
		return {"ok": true}


func after_test() -> void:
	Engine.time_scale = 1.0


func _entries(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": "t%d" % i, "name": "Technique %d" % i, "color": Color.ORANGE, "resource": "qi", "cost": 5.0 + i,
			"cooldown": 4.0, "left": 0.0, "ready": true, "reason": "", "tier": 1})
	return out


# --- model ---------------------------------------------------------------------------------

func test_wedge_zero_is_up_and_goes_clockwise() -> void:
	assert_int(Model.wedge_at(Vector2(0, -100), 4)).is_equal(0)
	assert_int(Model.wedge_at(Vector2(100, 0), 4)).is_equal(1)
	assert_int(Model.wedge_at(Vector2(0, 100), 4)).is_equal(2)
	assert_int(Model.wedge_at(Vector2(-100, 0), 4)).is_equal(3)
	assert_int(Model.wedge_at(Vector2(-3, -100), 4)).is_equal(0)       # just left of up is still wedge 0


func test_hub_deadzone_and_empty() -> void:
	assert_int(Model.wedge_at(Vector2(2, 2), 6, 100.0)).is_equal(-1)
	assert_int(Model.wedge_at(Vector2(0, -100), 0)).is_equal(-1)
	assert_int(Model.wedge_at(Vector2(0.05, -0.05), 6, 0.5)).is_equal(-1)
	assert_int(Model.wedge_at(Vector2(0.9, 0.0), 6, 1.0)).is_not_equal(-1)   # a stick, reach 1.0


func test_every_wedge_is_reachable_for_each_count() -> void:
	for n in range(1, Model.MAX_WEDGES + 1):
		var seen := {}
		for i in 360:
			var a := deg_to_rad(float(i))
			seen[Model.wedge_at(Vector2(sin(a), -cos(a)) * 100.0, n)] = true
		assert_int(seen.size()).is_equal(n)
		for i in n:
			var a := Model.wedge_angle(i, n)
			assert_int(Model.wedge_at(Vector2(sin(a), -cos(a)) * 100.0, n)).is_equal(i)


func test_step_wedge_wraps() -> void:
	assert_int(Model.step_wedge(-1, 1, 5)).is_equal(0)
	assert_int(Model.step_wedge(-1, -1, 5)).is_equal(4)
	assert_int(Model.step_wedge(4, 1, 5)).is_equal(0)
	assert_int(Model.step_wedge(0, -1, 5)).is_equal(4)
	assert_int(Model.step_wedge(0, 1, 0)).is_equal(-1)


func test_gather_uses_learned_actives_loadout_first() -> void:
	var s := Skills.new()
	var actives: Array = []
	for id: String in s.techniques:
		if String(s.techniques[id].get("kind", "active")) == "active" and actives.size() < 5:
			actives.append(id)
	assert_int(actives.size()).is_equal(5)
	for id: String in actives:
		s.grant(id)
	s.loadout[0] = actives[3]
	s.loadout[1] = actives[1]
	var ids := Model.gather_ids(s)
	assert_str(ids[0]).is_equal(actives[3])
	assert_str(ids[1]).is_equal(actives[1])
	for id: String in actives:
		assert_bool(ids.has(id)).is_true()
	assert_int(ids.size()).is_equal(5)


func test_gather_skips_unlearned_and_passives_and_caps() -> void:
	var s := Skills.new()
	assert_int(Model.gather_ids(s).size()).is_equal(0)
	for id: String in s.techniques:
		s.grant(id)
	var ids := Model.gather_ids(s)
	assert_int(ids.size()).is_equal(Model.MAX_WEDGES)
	for id in ids:
		assert_str(String(s.techniques[id].get("kind", "active"))).is_not_equal("passive")


func test_gather_includes_power_path_techniques() -> void:
	var ids: Array = AbilityLibIds.path_ids()
	assert_bool(ids.is_empty()).is_false()
	var out := Model.gather_ids(null, [ids[0]])
	assert_str(out[0]).is_equal(ids[0])
	assert_int(Model.gather_ids(null, ["no_such_technique"]).size()).is_equal(0)


class AbilityLibIds:
	static func path_ids() -> Array:
		return preload("res://scripts/abilities/ability_lib.gd").path_ids()


func test_entry_and_hub_lines_are_live() -> void:
	var s := Skills.new()
	var id := ""
	for k: String in s.techniques:
		if String(s.techniques[k].get("kind", "active")) == "active":
			id = k
			break
	s.grant(id)
	s.qi = 500.0
	var e := Model.entry(id, s, {"stamina": 100.0, "magicules": 100.0})
	assert_str(String(e["name"])).is_not_empty()
	assert_bool(bool(e["ready"])).is_true()
	var lines := Model.hub_lines(e)
	assert_str(String(lines["name"])).is_equal(String(e["name"]))
	assert_str(String(lines["state"])).contains("Ready")
	s.cooldowns[id] = 3.2
	e = Model.entry(id, s, {"stamina": 100.0, "magicules": 100.0})
	assert_bool(bool(e["ready"])).is_false()
	assert_str(String(Model.hub_lines(e)["state"])).contains("3.2")
	s.cooldowns[id] = 0.0
	e = Model.entry(id, s, {"stamina": 0.0, "magicules": 0.0})
	if String(e["resource"]) != "qi":
		assert_bool(bool(e["ready"])).is_false()
		assert_str(String(e["reason"])).starts_with("Not enough")


func test_hub_lines_when_nothing_hovered() -> void:
	var l := Model.hub_lines({})
	assert_str(String(l["name"])).is_equal("Techniques")
	assert_str(String(Model.hub_lines({"name": "X", "cost": 0.0, "resource": "stamina", "ready": true})["cost"])).is_equal("Free")


func test_slow_scale_rule() -> void:
	assert_float(Model.slow_scale(true, false)).is_less(0.5)
	assert_float(Model.slow_scale(false, false)).is_equal(1.0)
	assert_float(Model.slow_scale(true, true)).is_equal(1.0)     # a hit-stop owns the clock


# --- control ---------------------------------------------------------------------------------

func _wheel(n := 5) -> Control:
	var w: Control = Wheel.new()
	w.entries_override = _entries(n)
	add_child(auto_free(w))
	w.size = Vector2(2340, 1080)
	return w


func test_open_slows_time_and_close_restores_it() -> void:
	var w := _wheel()
	assert_bool(w.open_wheel("key")).is_true()
	assert_bool(w.is_open).is_true()
	assert_float(Engine.time_scale).is_equal(Wheel.SLOW_SCALE)
	assert_bool(w.visible).is_true()
	w.close_wheel(false)
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(w.is_open).is_false()


func test_exit_tree_never_leaves_time_slowed() -> void:
	var w: Control = Wheel.new()
	w.entries_override = _entries(3)
	add_child(w)
	w.open_wheel("key")
	assert_float(Engine.time_scale).is_equal(Wheel.SLOW_SCALE)
	remove_child(w)
	assert_float(Engine.time_scale).is_equal(1.0)
	w.free()


func test_hiding_the_wheel_restores_time() -> void:
	var w := _wheel()
	w.open_wheel("key")
	w.hide()
	assert_bool(w.is_open).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_disallowed_blocks_opening() -> void:
	var w := _wheel()
	w.allowed = func() -> bool: return false
	assert_bool(w.open_wheel("key")).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_no_techniques_means_no_wheel() -> void:
	var w: Control = Wheel.new()
	add_child(auto_free(w))
	assert_bool(w.open_wheel("key")).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_pointer_hover_and_confirm_casts_once() -> void:
	var w := _wheel(4)
	var caster := FakeCaster.new()
	add_child(auto_free(caster))
	w.caster = caster
	w.open_wheel("touch", w.ring_centre() + Vector2(0, -150))
	w._point(w.ring_centre() + Vector2(120, 0))
	assert_int(w.hover).is_equal(1)
	var got: Array = []
	w.confirmed.connect(func(id: String) -> void: got.append(id))
	w.close_wheel(true)
	assert_array(caster.cast_ids).is_equal(["t1"])
	assert_array(got).is_equal(["t1"])
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(w.is_open).is_false()


func test_cancel_and_hub_release_cast_nothing() -> void:
	var w := _wheel(4)
	var caster := FakeCaster.new()
	add_child(auto_free(caster))
	w.caster = caster
	w.open_wheel("key")
	w._point(w.ring_centre() + Vector2(3, 3))       # inside the hub
	assert_int(w.hover).is_equal(-1)
	w.close_wheel(true)
	assert_int(caster.cast_ids.size()).is_equal(0)
	w.open_wheel("key")
	w._point(w.ring_centre() + Vector2(0, -150))
	w.close_wheel(false)
	assert_int(caster.cast_ids.size()).is_equal(0)


func test_slow_time_setting_off_keeps_the_clock_alone() -> void:
	var w := _wheel()
	var SS := preload("res://scripts/ui/frontend/settings_store.gd")
	assert_bool(SS.DEFAULTS.has("wheel_slow")).is_true()
	assert_bool(SS.DEFAULTS.has("cast_camera")).is_true()
	assert_bool(bool(SS.DEFAULTS["wheel_slow"])).is_true()
	assert_bool(w._slow_wanted()).is_true()


func test_dissolve_finishes_and_hides() -> void:
	var w := _wheel(4)
	w.open_wheel("key")
	w._point(w.ring_centre() + Vector2(0, -150))
	w.close_wheel(true)
	assert_bool(w.visible).is_true()
	for i in 80:
		w._process(0.016)
		await get_tree().process_frame
	assert_bool(w.visible).is_false()


func test_keyboard_arrows_and_numbers() -> void:
	var w := _wheel(4)
	var caster := FakeCaster.new()
	add_child(auto_free(caster))
	w.caster = caster
	w.open_wheel("key")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_RIGHT
	ev.pressed = true
	w._key(ev)
	assert_int(w.hover).is_equal(0)
	w._key(ev)
	assert_int(w.hover).is_equal(1)
	var three := InputEventKey.new()
	three.physical_keycode = KEY_3
	three.pressed = true
	w._key(three)
	assert_array(caster.cast_ids).is_equal(["t2"])
	assert_bool(w.is_open).is_false()


func test_input_actions_exist_and_do_not_collide() -> void:
	Game._setup_input()
	assert_bool(InputMap.has_action("technique_wheel")).is_true()
	assert_bool(Game.KEYS.has("technique_wheel")).is_true()
