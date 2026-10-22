extends GdUnitTestSuite
## PC input map (docs/controls.md): gamepad sticks/triggers/buttons and mouse buttons come from Game.PADS.
## Mouse capture and a physical pad cannot be exercised here; this checks the InputMap they feed.


func before_test() -> void:
	Game._setup_input()


func _motion(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			out.append([(ev as InputEventJoypadMotion).axis, (ev as InputEventJoypadMotion).axis_value])
	return out


func _has_mouse(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return true
	return false


func _has_joy_button(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


func test_left_stick_moves() -> void:
	assert_array(_motion("move_forward")).contains([[JOY_AXIS_LEFT_Y, -1.0]])
	assert_array(_motion("move_back")).contains([[JOY_AXIS_LEFT_Y, 1.0]])
	assert_array(_motion("move_left")).contains([[JOY_AXIS_LEFT_X, -1.0]])
	assert_array(_motion("move_right")).contains([[JOY_AXIS_LEFT_X, 1.0]])


func test_right_stick_looks_with_deadzone() -> void:
	assert_array(_motion("look_left")).contains([[JOY_AXIS_RIGHT_X, -1.0]])
	assert_array(_motion("look_right")).contains([[JOY_AXIS_RIGHT_X, 1.0]])
	assert_array(_motion("look_up")).contains([[JOY_AXIS_RIGHT_Y, -1.0]])
	assert_array(_motion("look_down")).contains([[JOY_AXIS_RIGHT_Y, 1.0]])
	assert_float(InputMap.action_get_deadzone("look_left")).is_equal_approx(0.2, 0.001)


func test_mouse_and_pad_combat_bindings() -> void:
	assert_bool(_has_mouse("attack", MOUSE_BUTTON_LEFT)).is_true()
	assert_bool(_has_mouse("block", MOUSE_BUTTON_RIGHT)).is_true()
	assert_bool(_has_mouse("lock_on", MOUSE_BUTTON_MIDDLE)).is_true()
	assert_bool(_has_joy_button("attack", JOY_BUTTON_X)).is_true()
	assert_bool(_has_joy_button("jump", JOY_BUTTON_A)).is_true()
	assert_bool(_has_joy_button("dodge", JOY_BUTTON_B)).is_true()
	assert_bool(_has_joy_button("interact", JOY_BUTTON_Y)).is_true()
	assert_array(_motion("block")).contains([[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	assert_array(_motion("sprint")).contains([[JOY_AXIS_TRIGGER_RIGHT, 1.0]])


func test_no_two_actions_share_an_input() -> void:
	var owner_of := {}
	var actions: Array = Game.KEYS.keys() + Game.AXIS_ONLY
	for action: String in actions:
		for ev in InputMap.action_get_events(action):
			var id := ""
			if ev is InputEventKey:
				id = "key%d" % (ev as InputEventKey).physical_keycode
			elif ev is InputEventMouseButton:
				id = "mouse%d" % (ev as InputEventMouseButton).button_index
			elif ev is InputEventJoypadButton:
				id = "joy%d" % (ev as InputEventJoypadButton).button_index
			elif ev is InputEventJoypadMotion:
				id = "axis%d_%d" % [(ev as InputEventJoypadMotion).axis, int(signf((ev as InputEventJoypadMotion).axis_value))]
			if id.is_empty():
				continue
			# Hotbar / army orders / seals share the number keys on purpose (tests/test_controls_scheme.gd).
			if id in ["key49", "key50", "key51", "key52", "key53", "key54", "key55", "key56", "key57"]:
				continue
			assert_bool(owner_of.has(id) and owner_of[id] != action).override_failure_message(
				"%s and %s share %s" % [action, owner_of.get(id, ""), id]).is_false()
			owner_of[id] = action


func test_setup_is_repeatable_without_duplicate_events() -> void:
	var before := InputMap.action_get_events("move_forward").size()
	Game._setup_input()
	assert_int(InputMap.action_get_events("move_forward").size()).is_equal(before)
	assert_int(_motion("look_left").size()).is_equal(1)
