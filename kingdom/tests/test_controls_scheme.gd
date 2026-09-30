extends GdUnitTestSuite
## One key scheme (docs/controls.md): Game.KEYS is the single table of defaults, no two world actions
## share a key (the number keys are contextual on purpose), and the Pack menu's tab keys never reuse a
## combat key (C, J, L, R...).

const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
## Shared by design: hotbar 1-8, army orders 1-3 (only while you lead soldiers) and seals 4-9 (only mid-sequence).
const CONTEXTUAL := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]


func test_no_two_world_actions_share_a_key() -> void:
	var owner_of := {}
	for action: String in Game.KEYS:
		for key: int in Game.KEYS[action]:
			if CONTEXTUAL.has(key):
				continue
			assert_bool(owner_of.has(key)).override_failure_message(
				"%s and %s both use %s" % [action, owner_of.get(key, ""), OS.get_keycode_string(key)]).is_false()
			owner_of[key] = action


func test_menu_tab_keys_do_not_shadow_combat_keys() -> void:
	var world := {}
	for action: String in Game.KEYS:
		if action in ["menu_inventory", "menu_skills", "world_map", "journal"]:
			continue
		for key: int in Game.KEYS[action]:
			world[key] = action
	for t: Array in GameMenu.TABS:
		var key: int = t[2]
		if key == KEY_NONE:
			continue
		assert_bool(world.has(key)).override_failure_message(
			"tab %s uses %s, which is the world action %s" % [t[0], OS.get_keycode_string(key), world.get(key, "")]).is_false()
	for combat: int in [KEY_C, KEY_J, KEY_L, KEY_R]:
		for t: Array in GameMenu.TABS:
			assert_int(int(t[2])).is_not_equal(combat)


func test_menu_open_keys_match_their_tabs() -> void:
	var tab_key := {}
	for t: Array in GameMenu.TABS:
		tab_key[t[0]] = int(t[2])
	assert_int(int(Game.KEYS["menu_inventory"][0])).is_equal(tab_key["inventory"])
	assert_int(int(Game.KEYS["menu_skills"][0])).is_equal(tab_key["skills"])
	assert_int(int(Game.KEYS["world_map"][0])).is_equal(tab_key["map"])


func test_setup_input_defines_every_action_and_is_repeatable() -> void:
	Game._setup_input()
	Game._setup_input()
	for action: String in Game.KEYS:
		assert_bool(InputMap.has_action(action)).is_true()
		var keys := 0
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys += 1
		assert_int(keys).is_equal((Game.KEYS[action] as Array).size())
	assert_bool(InputMap.has_action("lock_on")).is_true()
