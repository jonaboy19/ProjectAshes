extends GdUnitTestSuite
## Ready v1 C11: PC rebinding (conflicts, swap, reset, persistence) and keyboard / mouse / gamepad glyphs.

const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const IG := preload("res://scripts/ui/input_glyphs.gd")
const TutorialView := preload("res://scripts/region1/tutorial_prompt_view.gd")
const InteractLabelS := preload("res://scripts/ui/interact_label.gd")
const SCRATCH := "user://test_v1_controls.cfg"


func before_test() -> void:
	SS.controls_path_override = SCRATCH
	DirAccess.remove_absolute(SCRATCH)
	Game._setup_input()
	IG.device = IG.Device.KEYBOARD


func after_test() -> void:
	DirAccess.remove_absolute(SCRATCH)
	SS.controls_path_override = ""
	Game._setup_input()
	IG.device = IG.Device.KEYBOARD


func _keys_of(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			out.append(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return out


func test_rebind_round_trip_survives_a_restart() -> void:
	assert_str(SS.try_bind("interact", KEY_X)).is_equal("")
	assert_array(_keys_of("interact")).is_equal([KEY_X])
	Game._setup_input()                      # a fresh boot: defaults first ...
	assert_array(_keys_of("interact")).is_equal([KEY_E])
	SS.apply_controls()                      # ... then the saved rebinds
	assert_array(_keys_of("interact")).is_equal([KEY_X])
	assert_str(IG.glyph("interact")).is_equal(IG.key_text(KEY_X))


func test_conflicting_key_is_refused_and_nothing_changes() -> void:
	assert_str(SS.try_bind("interact", KEY_J)).is_equal("conflict:attack")
	assert_array(_keys_of("interact")).is_equal([KEY_E])
	assert_array(_keys_of("attack")).is_equal([KEY_J])
	assert_str(SS.bind_problem("interact", KEY_J)).is_equal("conflict:attack")
	assert_str(SS.bind_problem("interact", KEY_ESCAPE)).is_equal("reserved")
	assert_str(SS.bind_problem("interact", KEY_E)).is_equal("")       # its own key is fine


func test_swap_exchanges_the_two_actions_and_persists() -> void:
	assert_str(SS.try_bind("interact", KEY_J, true)).is_equal("")
	assert_array(_keys_of("interact")).is_equal([KEY_J])
	assert_array(_keys_of("attack")).is_equal([KEY_E])
	Game._setup_input()
	SS.apply_controls()                      # swapped pair loads without tripping the conflict check
	assert_array(_keys_of("interact")).is_equal([KEY_J])
	assert_array(_keys_of("attack")).is_equal([KEY_E])


func test_hotbar_order_and_seal_digits_stay_shareable() -> void:
	assert_str(SS.bind_problem("order_follow", KEY_4)).is_equal("")   # seal_1 default is 4
	assert_str(SS.bind_problem("interact", KEY_1)).is_equal("conflict:order_follow")


func test_reset_restores_defaults_and_clears_the_file() -> void:
	SS.try_bind("interact", KEY_X)
	SS.try_bind("jump", KEY_Z)
	SS.reset_controls()
	assert_array(_keys_of("interact")).is_equal([KEY_E])
	assert_array(_keys_of("jump")).is_equal([KEY_SPACE])
	var cf := ConfigFile.new()
	cf.load(SCRATCH)
	assert_bool(cf.has_section("controls")).is_false()


func test_every_rebindable_action_exists() -> void:
	for a: Array in SS.ACTIONS:
		assert_bool(InputMap.has_action(String(a[0]))).override_failure_message("missing action " + String(a[0])).is_true()


func test_glyph_per_device() -> void:
	assert_str(IG.glyph("interact", IG.Device.KEYBOARD)).is_equal("E")
	assert_str(IG.glyph("interact", IG.Device.GAMEPAD)).is_equal("Y")
	assert_str(IG.glyph("attack", IG.Device.KEYBOARD)).is_equal("J")
	assert_str(IG.glyph("attack", IG.Device.KEYBOARD, true)).is_equal("LMB")
	assert_str(IG.glyph("attack", IG.Device.GAMEPAD)).is_equal("X")
	assert_str(IG.glyph("block", IG.Device.GAMEPAD)).is_equal("LT")
	assert_str(IG.glyph("sprint", IG.Device.GAMEPAD)).is_equal("RT")
	assert_str(IG.glyph("crouch", IG.Device.GAMEPAD)).is_equal("L3")
	assert_str(IG.glyph("world_map", IG.Device.GAMEPAD)).is_equal("D-pad Up")
	assert_str(IG.glyph("move_forward", IG.Device.GAMEPAD)).is_equal("Left Stick")
	assert_str(IG.glyph("eat", IG.Device.GAMEPAD)).is_equal("-")      # no pad button: shown as unbound
	assert_str(IG.glyph("no_such_action")).is_equal("-")


func test_combo_and_fill_and_hint_line() -> void:
	assert_str(IG.combo(IG.MOVE_ACTIONS, IG.Device.KEYBOARD)).is_equal("WASD")
	assert_str(IG.combo(IG.MOVE_ACTIONS, IG.Device.GAMEPAD)).is_equal("Left Stick")
	assert_str(IG.fill("Press {interact} to talk", IG.Device.KEYBOARD)).is_equal("Press E to talk")
	assert_str(IG.fill("Press {interact} to talk", IG.Device.GAMEPAD)).is_equal("Press Y to talk")
	assert_str(IG.hint_line(IG.Device.KEYBOARD)).starts_with("LMB attack")
	assert_str(IG.hint_line(IG.Device.GAMEPAD)).starts_with("X attack")
	assert_str(IG.hint_line(IG.Device.GAMEPAD)).contains("Y interact")


func test_device_follows_the_last_input() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	assert_bool(IG.note_event(pad)).is_true()
	assert_int(IG.device).is_equal(IG.Device.GAMEPAD)
	assert_bool(IG.note_event(pad)).is_false()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	assert_bool(IG.note_event(key)).is_true()
	assert_int(IG.device).is_equal(IG.Device.KEYBOARD)
	var small := InputEventJoypadMotion.new()
	small.axis = JOY_AXIS_LEFT_X
	small.axis_value = 0.2
	assert_bool(IG.note_event(small)).is_false()         # stick drift does not flip the device


func test_relabel_swaps_the_key_word_only() -> void:
	assert_str(IG.relabel("Press E to talk", ["E"], "X")).is_equal("Press X to talk")
	assert_str(IG.relabel("Druk op Spatie om te rollen", ["Space", "Spatie"], "K")).is_equal("Druk op K om te rollen")
	assert_str(IG.relabel("Hold E to read the ash", ["E"], "Y")).is_equal("Hold Y to read the ash")
	assert_str(IG.relabel("Press the Eagle", ["E"], "X")).is_equal("Press the Eagle")


func test_tutorial_prompt_follows_rebind_and_gamepad() -> void:
	var view: Variant = auto_free(TutorialView.new())
	add_child(view as Node)
	var p := {"id": &"dodge", "text_key": "NOPE", "text_en": "Press Space to roll", "touch_mode": false, "anchor": "btn_dodge", "touch": "tap"}
	view.show_prompt(&"dodge", p)
	assert_str(view._label.text).is_equal("Press K to roll")            # the old text said Space; the key is K
	SS.try_bind("dodge", KEY_X)
	view._label.text = view._prompt_text()
	assert_str(view._label.text).is_equal("Press X to roll")
	IG.device = IG.Device.GAMEPAD
	assert_str(view._prompt_text()).is_equal("Press B to roll")
	var move := {"id": &"move", "text_key": "NOPE", "text_en": "Walk with WASD", "touch_mode": false, "anchor": "left_stick", "touch": "drag"}
	view.prompt = move
	assert_str(view._prompt_text()).is_equal("Walk with the left stick")
	view.prompt = {"id": &"talk", "text_key": "NOPE", "text_en": "Tap to talk", "touch_mode": true, "anchor": "btn_interact", "touch": "tap"}
	assert_str(view._prompt_text()).is_equal("Tap to talk")           # phone layout keeps gesture text


func test_interact_label_with_glyph() -> void:
	var lab := InteractLabelS.pack("Talk", "Roland Ward")
	var g := InteractLabelS.with_glyph(lab, "E")
	assert_str(g["text"]).is_equal("[E] Talk — Roland Ward")
	assert_str(lab["text"]).is_equal("Talk — Roland Ward")            # the original is untouched
	assert_str(InteractLabelS.with_glyph(lab, "")["text"]).is_equal("Talk — Roland Ward")


func test_virtual_joystick_is_touch_only() -> void:
	var stick := VirtualJoystick.new()
	add_child(stick)
	auto_free(stick)
	if VirtualJoystick.wanted():
		assert_bool(stick.visible).is_true()
	else:
		assert_bool(stick.visible).is_false()
		assert_int(stick.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
